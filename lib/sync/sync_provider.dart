import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/account_profile_refresher.dart';
import '../data/account_provider.dart';
import '../data/todo_provider.dart';
import '../models/account.dart';
import 'background_sync_bridge.dart';
import 'sync_coordinator.dart';
import 'sync_dispatcher.dart';

export 'sync_coordinator.dart' show SyncState, SyncStatus;

/// Allows tests to disable background realtime long-polling streams.
final realtimeSyncEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to disable foreground periodic sync timers.
final periodicSyncEnabledProvider = Provider<bool>((ref) => true);

/// Allows tests to disable automatic cold-start sync on shell mount.
final startupSyncEnabledProvider = Provider<bool>((ref) => true);

/// Thin Riverpod bridge around [SyncCoordinator].
class SyncNotifier extends Notifier<SyncState> {
  SyncCoordinator? _coordinator;
  bool _disposed = false;

  SyncCoordinator _ensureCoordinator() {
    return _coordinator ??= SyncCoordinator(
      host: SyncHost(
        readActiveAccount: () {
          final active = ref.read(accountProvider).activeAccount;
          return active is MicrosoftAccount ? active : null;
        },
        readTodoState: () => ref.read(todoProvider),
        readRepository: () => ref.read(todoProvider.notifier).repository,
        nextId: (prefix) => ref.read(todoProvider.notifier).nextId(prefix),
        readTodoApi: () => ref.read(microsoftTodoApiProvider),
        readBackgroundScheduler: () =>
            ref.read(backgroundSyncSchedulerProvider),
        isRealtimeEnabled: () => ref.read(realtimeSyncEnabledProvider),
        isPeriodicEnabled: () => ref.read(periodicSyncEnabledProvider),
        isStartupSyncEnabled: () => ref.read(startupSyncEnabledProvider),
        commitPushBatch: (outcome) =>
            ref.read(todoProvider.notifier).commitPushBatch(outcome),
        applyRemoteState: ({groups, lists, tasks, remoteSettings}) => ref
            .read(todoProvider.notifier)
            .applyRemoteState(
              groups: groups,
              lists: lists,
              tasks: tasks,
              remoteSettings: remoteSettings,
            ),
        persistAccountSyncStatus:
            (active, {lastSyncedAt, syncError, required clearSyncError}) => ref
                .read(accountProvider.notifier)
                .updateSyncStatus(
                  active.id,
                  lastSyncedAt: lastSyncedAt,
                  syncError: syncError,
                  clearSyncError: clearSyncError,
                ),
        refreshProfileIfIncomplete: (active) =>
            refreshMicrosoftProfileIfIncomplete(
              authClient: ref.read(microsoftAuthClientProvider),
              tokenStorage: ref.read(authTokenStorageProvider),
              account: active,
              isDisposed: () => _disposed,
              onProfileUpdated: ref
                  .read(accountProvider.notifier)
                  .updateMicrosoftProfile,
            ),
        onBackgroundDbReloaded: () => ref.invalidate(todoProvider),
        onStateChanged: (next) {
          if (!_disposed) state = next;
        },
      ),
    );
  }

  @override
  SyncState build() {
    _disposed = false;
    final coordinator = _ensureCoordinator();
    ref.onDispose(() {
      _disposed = true;
      coordinator.dispose();
    });

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
        schedulePush();
      }
    });

    final microsoftAccount =
        accountIdentity.isMicrosoft && activeAccount is MicrosoftAccount
        ? activeAccount
        : null;

    return coordinator.configureSession(
      activeAccount: microsoftAccount,
      realtimeEnabled:
          microsoftAccount != null && ref.watch(realtimeSyncEnabledProvider),
      periodicEnabled:
          microsoftAccount != null && ref.watch(periodicSyncEnabledProvider),
    );
  }

  void onAppPaused() => _ensureCoordinator().onAppPaused();

  void onAppResumed() => _ensureCoordinator().onAppResumed();

  Future<void> refresh({SyncReason reason = SyncReason.manual}) =>
      _ensureCoordinator().refresh(reason: reason);

  void syncOnSessionStart({bool accountChanged = false}) =>
      _ensureCoordinator().syncOnSessionStart(accountChanged: accountChanged);

  void scheduleDebouncedSync({
    Duration delay = SyncCoordinator.debounceDuration,
    bool forceFullSync = false,
    SyncReason reason = SyncReason.debounced,
  }) => _ensureCoordinator().scheduleDebouncedSync(
    delay: delay,
    forceFullSync: forceFullSync,
    reason: reason,
  );

  void schedulePull(
    PullCommand command, {
    Duration delay = SyncCoordinator.debounceDuration,
  }) => _ensureCoordinator().schedulePull(command, delay: delay);

  void schedulePush({
    Duration delay = SyncCoordinator.mutationDebounceDuration,
    SyncReason reason = SyncReason.localMutation,
  }) => _ensureCoordinator().schedulePush(delay: delay, reason: reason);

  Future<void> syncNow({
    bool forceFullSync = false,
    SyncReason reason = SyncReason.manual,
  }) => _ensureCoordinator().syncNow(
    forceFullSync: forceFullSync,
    reason: reason,
  );
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
