import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:result_dart/result_dart.dart';

import '../account/account_provider.dart';
import '../core/error/app_error.dart';
import '../core/result/app_result.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'cloud_sync_service.dart';
import 'microsoft_todo_api.dart';
import 'sync_guard.dart';

part 'sync_provider.freezed.dart';

/// Allows tests to disable background realtime long-polling streams.
final realtimeSyncEnabledProvider = Provider<bool>((ref) => true);

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService(
    authClient: ref.watch(microsoftAuthClientProvider),
    todoApi: ref.watch(microsoftTodoApiProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
  );
});

enum SyncStatus { idle, syncing, success, error, requiresRelogin }

@freezed
abstract class SyncState with _$SyncState {
  const SyncState._();

  const factory SyncState({
    @Default(SyncStatus.idle) SyncStatus status,
    DateTime? lastSyncedAt,
    String? error,
  }) = _SyncState;

  bool get isSyncing => status == SyncStatus.syncing;
  bool get requiresRelogin => status == SyncStatus.requiresRelogin;
}

class SyncNotifier extends Notifier<SyncState> {
  static const _debounceDuration = Duration(milliseconds: 1500);
  static const _realtimeInitialBackoff = Duration(seconds: 2);
  static const _realtimeMaxBackoff = Duration(seconds: 60);

  Timer? _debounceTimer;
  Timer? _realtimeReconnectTimer;
  StreamSubscription<RealtimeEvent>? _realtimeSub;

  bool _disposed = false;
  Future<void>? _activeSync;
  bool _syncQueued = false;
  Duration _realtimeBackoff = _realtimeInitialBackoff;
  String? _realtimeAccountId;

  @override
  SyncState build() {
    _disposed = false;
    ref.onDispose(_disposeResources);

    final accountIdentity = ref.watch(
      accountProvider.select(
        (s) => (
          id: s.activeAccount?.id,
          isMicrosoft: s.activeAccount is MicrosoftAccount,
        ),
      ),
    );
    final activeAccount = ref.read(accountProvider).activeAccount;

    ref.listen<int>(todoProvider.select((s) => s.mutationVersion), (
      prev,
      next,
    ) {
      if (prev != null && next > prev) {
        scheduleDebouncedSync();
      }
    });

    if (!accountIdentity.isMicrosoft || activeAccount is! MicrosoftAccount) {
      _stopRealtime();
      _debounceTimer?.cancel();
      _debounceTimer = null;
      return const SyncState();
    }

    if (ref.watch(realtimeSyncEnabledProvider) &&
        _realtimeAccountId != activeAccount.id) {
      _startRealtimeFor(activeAccount);
    }

    return SyncState(lastSyncedAt: activeAccount.lastSyncedAt);
  }

  void _disposeResources() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _stopRealtime();
  }

  void _stopRealtime() {
    _realtimeAccountId = null;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    unawaited(_realtimeSub?.cancel());
    _realtimeSub = null;
  }

  void scheduleDebouncedSync({Duration delay = _debounceDuration}) {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      if (!_disposed) {
        unawaited(syncNow());
      }
    });
  }

  Future<void> syncNow() {
    if (_disposed) return Future<void>.value();
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return Future<void>.value();

    final inFlight = _activeSync;
    if (inFlight != null) {
      _syncQueued = true;
      return inFlight;
    }

    final completer = Completer<void>();
    _activeSync = completer.future;
    unawaited(() async {
      try {
        await _runSyncLoop();
      } finally {
        if (!completer.isCompleted) completer.complete();
      }
    }());
    return completer.future;
  }

  Future<void> _runSyncLoop() async {
    state = state.copyWith(status: SyncStatus.syncing, error: null);
    try {
      do {
        _syncQueued = false;
        await _syncOnce();
      } while (_syncQueued && !_disposed);
    } finally {
      _syncQueued = false;
      _activeSync = null;
    }
  }

  Future<void> _syncOnce() async {
    final active = ref.read(accountProvider).activeAccount;
    if (_disposed || active is! MicrosoftAccount) return;

    final service = ref.read(cloudSyncServiceProvider);
    final todoNotifier = ref.read(todoProvider.notifier);
    final snapshotState = ref.read(todoProvider);
    final repository = todoNotifier.repository;
    final settings = todoNotifier.settings;

    final result = await service
        .syncAccount(
          account: active,
          currentState: snapshotState,
          repository: repository,
          settings: settings,
          idGenerator: todoNotifier.nextId,
        )
        .flatMap((outcome) async {
          if (_disposed ||
              ref.read(accountProvider).activeAccount?.id != active.id) {
            return Success<SyncOutcome, AppError>(outcome);
          }
          return todoNotifier
              .applySyncResult(
                groups: outcome.groups,
                lists: outcome.lists,
                tasks: outcome.tasks,
                settingsPatch: outcome.settingsPatch,
                snapshotGroups: snapshotState.groups,
                snapshotLists: snapshotState.lists,
                snapshotTasks: snapshotState.tasks,
                snapshotState: snapshotState,
                processedDeletedGroupRemoteIds:
                    outcome.processedDeletedGroupRemoteIds,
                processedDeletedListRemoteIds:
                    outcome.processedDeletedListRemoteIds,
                processedDeletedTaskRemoteIds:
                    outcome.processedDeletedTaskRemoteIds,
                processedDeletedSteps: outcome.processedDeletedSteps,
                syncedGroupIds: outcome.syncedGroupIds,
                syncedListIds: outcome.syncedListIds,
                syncedTaskIds: outcome.syncedTaskIds,
                syncedSettingKeys: outcome.syncedSettingKeys,
              )
              .map((_) => outcome);
        })
        .flatMap(
          (outcome) => guardAsyncUnit(() async {
            await ref
                .read(accountProvider.notifier)
                .updateSyncStatus(
                  active.id,
                  lastSyncedAt: outcome.syncedAt,
                  clearSyncError: true,
                );
            await _refreshProfileIfIncomplete(service, active);
          }, operation: 'updateSyncStatus').map((_) => outcome),
        );

    if (_disposed) return;

    await result.fold(
      (outcome) async {
        state = state.copyWith(
          status: SyncStatus.success,
          lastSyncedAt: outcome.syncedAt,
          error: null,
        );
      },
      (error) async {
        final status = switch (error) {
          AuthError(:final requiresReauth) =>
            requiresReauth ? SyncStatus.requiresRelogin : SyncStatus.error,
          NetworkError() => SyncStatus.error,
          DatabaseError() => SyncStatus.error,
          NotFoundError() => SyncStatus.error,
          ValidationError() => SyncStatus.error,
          UnknownError() => SyncStatus.error,
        };
        final message = error.describe();
        await ref
            .read(accountProvider.notifier)
            .updateSyncStatus(active.id, syncError: message);
        if (!_disposed) {
          state = state.copyWith(status: status, error: message);
        }
      },
    );
  }

  Future<void> _refreshProfileIfIncomplete(
    CloudSyncService service,
    MicrosoftAccount account,
  ) async {
    final needsName =
        account.displayName == 'Microsoft Account' ||
        account.displayName.trim().isEmpty ||
        (account.email.isNotEmpty && account.displayName == account.email);
    final needsEmail = account.email.trim().isEmpty;
    final needsAvatar =
        account.avatarBase64 == null || account.avatarBase64!.isEmpty;
    if (!needsName && !needsEmail && !needsAvatar) return;

    await guardApiCall(() async {
      final tokens = await service.tokenStorage.loadTokens(account.id);
      if (tokens == null || tokens.refreshToken.isEmpty) return;
      final cid = tokens.userId.isNotEmpty
          ? tokens.userId
          : account.microsoftUserId;
      final profile = await service.authClient.fetchUserProfile(
        cid: cid,
        refreshToken: tokens.refreshToken,
        fallbackEmail: account.email,
      );
      if (_disposed) return;

      final nextName =
          profile.displayName.trim().isNotEmpty &&
              profile.displayName != 'Microsoft Account' &&
              (needsName || profile.displayName != account.displayName)
          ? profile.displayName
          : null;
      final nextEmail =
          profile.email.trim().isNotEmpty &&
              (needsEmail || profile.email != account.email)
          ? profile.email
          : null;
      final nextAvatar =
          (profile.avatarBase64 != null &&
              profile.avatarBase64!.isNotEmpty &&
              needsAvatar)
          ? profile.avatarBase64
          : null;

      if (nextName == null && nextEmail == null && nextAvatar == null) {
        return;
      }
      await ref
          .read(accountProvider.notifier)
          .updateMicrosoftProfile(
            account.id,
            displayName: nextName,
            email: nextEmail,
            avatarBase64: nextAvatar,
          );
    }, operation: 'refreshProfile');

    // Best-effort; failures are logged by the guard.
  }

  void _startRealtimeFor(MicrosoftAccount account) {
    _stopRealtime();
    _realtimeAccountId = account.id;
    _realtimeBackoff = _realtimeInitialBackoff;
    unawaited(_connectRealtime(account));
  }

  Future<void> _connectRealtime(MicrosoftAccount account) async {
    if (_disposed || _realtimeAccountId != account.id) return;
    if (!ref.read(realtimeSyncEnabledProvider)) return;

    final service = ref.read(cloudSyncServiceProvider);
    final settings = ref.read(todoProvider.notifier).settings;
    final ctxResult = await service.resolveContext(account, settings);

    if (_disposed || _realtimeAccountId != account.id) return;

    final ctx = ctxResult.fold((ctx) => ctx, (_) => null);
    if (ctx == null) {
      _scheduleRealtimeReconnect(account);
      return;
    }

    final stream = service.todoApi.connectRealtime(ctx);
    _realtimeSub = stream.listen(
      (event) {
        if (_disposed || _realtimeAccountId != account.id) return;
        _realtimeBackoff = _realtimeInitialBackoff;
        if (event.isKeepAlive) return;
        if (service.todoApi.isOwnRequestId(event.requestId)) return;
        scheduleDebouncedSync(delay: const Duration(milliseconds: 200));
      },
      onError: (_) {
        _scheduleRealtimeReconnect(account);
      },
      onDone: () {
        _scheduleRealtimeReconnect(account);
      },
      cancelOnError: true,
    );
  }

  void _scheduleRealtimeReconnect(MicrosoftAccount account) {
    if (_disposed || _realtimeAccountId != account.id) return;
    if (!ref.read(realtimeSyncEnabledProvider)) return;
    _realtimeSub = null;
    _realtimeReconnectTimer?.cancel();
    final wait = _realtimeBackoff;
    final nextSecs = (wait.inSeconds * 2).clamp(
      _realtimeInitialBackoff.inSeconds,
      _realtimeMaxBackoff.inSeconds,
    );
    _realtimeBackoff = Duration(seconds: nextSecs);
    _realtimeReconnectTimer = Timer(wait, () {
      if (!_disposed && _realtimeAccountId == account.id) {
        unawaited(_connectRealtime(account));
      }
    });
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
