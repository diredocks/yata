import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/account.dart';
import 'cloud_sync_service.dart';
import '../auth/microsoft_auth_service.dart';
import '../account/account_provider.dart';
import '../data/todo_provider.dart';

final cloudSyncServiceProvider = Provider<CloudSyncService>((ref) {
  return CloudSyncService(
    authClient: ref.watch(microsoftAuthClientProvider),
    tokenStorage: ref.watch(authTokenStorageProvider),
    todoApi: ref.watch(microsoftTodoApiProvider),
  );
});

@immutable
class SyncState {
  const SyncState({
    this.isSyncing = false,
    this.error,
    this.requiresRelogin = false,
  });

  final bool isSyncing;
  final String? error;
  final bool requiresRelogin;

  SyncState copyWith({
    bool? isSyncing,
    String? error,
    bool clearError = false,
    bool? requiresRelogin,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      error: clearError ? null : (error ?? this.error),
      requiresRelogin: requiresRelogin ?? this.requiresRelogin,
    );
  }
}

class SyncNotifier extends Notifier<SyncState> {
  Timer? _debounceTimer;
  Future<void>? _activeSync;

  @override
  SyncState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
    });

    final activeAccountId = ref.watch(
      accountProvider.select((s) => s.activeAccount?.id),
    );
    final activeAccount = ref.read(accountProvider).activeAccount;

    ref.listen<int>(
      todoProvider.select((s) => s.mutationVersion),
      (prev, next) {
        if (prev != null && next > prev) {
          scheduleSync();
        }
      },
    );

    if (activeAccountId != null && activeAccount is MicrosoftAccount) {
      Future.microtask(syncNow);
    }

    return SyncState(
      error: activeAccount is MicrosoftAccount ? activeAccount.syncError : null,
    );
  }

  void scheduleSync({Duration delay = const Duration(milliseconds: 1500)}) {
    final active = ref.read(accountProvider).activeAccount;
    if (active is! MicrosoftAccount) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(delay, () {
      syncNow();
    });
  }

  Future<bool> syncNow() async {
    if (_activeSync != null) {
      await _activeSync;
      return state.error == null;
    }

    final account = ref.read(accountProvider).activeAccount;
    if (account is! MicrosoftAccount) return true;

    final completer = Completer<void>();
    _activeSync = completer.future;

    state = state.copyWith(
      isSyncing: true,
      clearError: true,
      requiresRelogin: false,
    );

    try {
      final todoState = ref.read(todoProvider);
      final storage = ref.read(todoLocalStorageProvider);
      final service = ref.read(cloudSyncServiceProvider);

      final outcome = await service.sync(
        account: account,
        localLists: todoState.lists,
        localTasks: todoState.tasks,
        pendingDeletedListRemoteIds: storage.loadPendingDeletedListRemoteIds(),
        pendingDeletedTasks: storage.loadPendingDeletedTasks(),
        addNewTasksOnTop: todoState.addNewTasksOnTop,
      );

      // Ensure we are still on the same account before committing.
      if (ref.read(accountProvider).activeAccountId == account.id) {
        await ref.read(todoProvider.notifier).applySyncResult(
              lists: outcome.lists,
              tasks: outcome.tasks,
            );
      }

      await ref.read(accountProvider.notifier).updateSyncStatus(
            account.id,
            lastSyncedAt: outcome.syncedAt,
            clearSyncError: true,
          );

      state = const SyncState(isSyncing: false);
      return true;
    } on MicrosoftAuthException catch (e) {
      await ref.read(accountProvider.notifier).updateSyncStatus(
            account.id,
            syncError: e.message,
          );
      state = SyncState(
        isSyncing: false,
        error: e.message,
        requiresRelogin: e.requiresRelogin,
      );
      return false;
    } catch (e) {
      final message = e.toString();
      await ref.read(accountProvider.notifier).updateSyncStatus(
            account.id,
            syncError: message,
          );
      state = SyncState(
        isSyncing: false,
        error: message,
      );
      return false;
    } finally {
      _activeSync = null;
      completer.complete();
    }
  }
}

final syncProvider = NotifierProvider<SyncNotifier, SyncState>(
  SyncNotifier.new,
);
