import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account_local_storage.dart';
import '../auth/browser_launcher.dart';
import '../auth/microsoft_auth_service.dart';
import '../auth/msa_webview_launcher.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../models/account.dart';
import '../sync/microsoft_todo_api.dart';

part 'account_provider.freezed.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final accountLocalStorageProvider = Provider<AccountLocalStorage>((ref) {
  return AccountLocalStorage(ref.watch(sharedPreferencesProvider));
});

final authTokenStorageProvider = Provider<AuthTokenStorage>((ref) {
  return AuthTokenStorage(ref.watch(sharedPreferencesProvider));
});

final microsoftAuthClientProvider = Provider<MicrosoftAuthClient>((ref) {
  return HttpMicrosoftAuthClient();
});

final msaInteractiveSignInProvider = Provider<MsaInteractiveSignInClient>((
  ref,
) {
  return PlatformMsaInteractiveSignInClient();
});

final externalUrlLauncherProvider = Provider<Future<bool> Function(String url)>(
  (ref) => launchExternalUrl,
);

final microsoftTodoApiProvider = Provider<MicrosoftTodoApi>((ref) {
  return HttpMicrosoftTodoApi();
});

@freezed
abstract class AccountState with _$AccountState {
  const AccountState._();

  const factory AccountState({
    required List<Account> accounts,
    required String? activeAccountId,
  }) = _AccountState;

  Account? get activeAccount {
    if (activeAccountId == null) return null;
    for (final account in accounts) {
      if (account.id == activeAccountId) return account;
    }
    return accounts.isNotEmpty ? accounts.first : null;
  }
}

class AccountNotifier extends Notifier<AccountState> {
  int _idCounter = 0;

  AccountLocalStorage get _storage => ref.read(accountLocalStorageProvider);

  String _nextAccountId() {
    _idCounter += 1;
    return 'acct_${DateTime.now().microsecondsSinceEpoch}_$_idCounter';
  }

  @override
  AccountState build() {
    final snapshot = _storage.load();
    return AccountState(
      accounts: snapshot.accounts,
      activeAccountId: snapshot.activeAccountId,
    );
  }

  /// Creates a new local account with isolated storage and makes it active.
  Future<LocalAccount> signInLocal(
    String rawInput, {
    required String fallbackName,
    required String fallbackEmail,
  }) async {
    final parsed = Account.parseLoginInput(
      rawInput,
      fallbackName: fallbackName,
      fallbackEmail: fallbackEmail,
    );
    final account = LocalAccount(
      id: _nextAccountId(),
      displayName: parsed.displayName,
      email: parsed.email,
      createdAt: DateTime.now().toUtc(),
    );

    final nextAccounts = [...state.accounts, account];
    state = AccountState(accounts: nextAccounts, activeAccountId: account.id);
    await _storage.saveAccounts(nextAccounts);
    await _storage.saveActiveAccountId(account.id);
    return account;
  }

  /// Signs into a Microsoft account (reusing existing account if same Microsoft user ID).
  Future<MicrosoftAccount> signInMicrosoft(MicrosoftSignInResult result) async {
    final tokenStorage = ref.read(authTokenStorageProvider);
    final existingIndex = state.accounts.indexWhere(
      (a) => a is MicrosoftAccount && a.microsoftUserId == result.profile.id,
    );

    late final MicrosoftAccount account;
    late final List<Account> nextAccounts;

    if (existingIndex >= 0) {
      final existing = state.accounts[existingIndex] as MicrosoftAccount;
      account = existing.copyWith(
        displayName: result.profile.displayName,
        email: result.profile.email,
        avatarBase64: result.profile.avatarBase64 ?? existing.avatarBase64,
        syncError: null,
      );
      nextAccounts = [
        for (var i = 0; i < state.accounts.length; i++)
          if (i == existingIndex) account else state.accounts[i],
      ];
    } else {
      account = MicrosoftAccount(
        id: _nextAccountId(),
        displayName: result.profile.displayName,
        email: result.profile.email,
        createdAt: DateTime.now().toUtc(),
        microsoftUserId: result.profile.id,
        avatarBase64: result.profile.avatarBase64,
      );
      nextAccounts = [...state.accounts, account];
    }

    await tokenStorage.saveTokens(account.id, result.tokens);
    state = AccountState(accounts: nextAccounts, activeAccountId: account.id);
    await _storage.saveAccounts(nextAccounts);
    await _storage.saveActiveAccountId(account.id);
    return account;
  }

  Future<void> updateSyncStatus(
    String accountId, {
    DateTime? lastSyncedAt,
    String? syncError,
    bool clearSyncError = false,
  }) async {
    final idx = state.accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return;
    final target = state.accounts[idx];
    if (target is! MicrosoftAccount) return;

    final updated = target.copyWith(
      lastSyncedAt: (lastSyncedAt ?? target.lastSyncedAt)?.toUtc(),
      syncError: clearSyncError ? null : (syncError ?? target.syncError),
    );
    final nextAccounts = [
      for (var i = 0; i < state.accounts.length; i++)
        if (i == idx) updated else state.accounts[i],
    ];
    state = state.copyWith(accounts: nextAccounts);
    await _storage.saveAccounts(nextAccounts);
  }

  Future<void> updateMicrosoftProfile(
    String accountId, {
    String? displayName,
    String? email,
    String? avatarBase64,
  }) async {
    final idx = state.accounts.indexWhere((a) => a.id == accountId);
    if (idx < 0) return;
    final target = state.accounts[idx];
    if (target is! MicrosoftAccount) return;

    final updated = target.copyWith(
      displayName: displayName ?? target.displayName,
      email: email ?? target.email,
      avatarBase64: avatarBase64 ?? target.avatarBase64,
    );
    final nextAccounts = [
      for (var i = 0; i < state.accounts.length; i++)
        if (i == idx) updated else state.accounts[i],
    ];
    state = state.copyWith(accounts: nextAccounts);
    await _storage.saveAccounts(nextAccounts);
  }

  TodoRepository _repositoryFor(String accountId) => TodoRepository.forAccount(
    ref.read(sharedPreferencesProvider),
    accountId: accountId,
    database: ref.read(todoDatabaseProvider),
  );

  Future<void> switchAccount(String accountId) async {
    if (state.activeAccountId == accountId) return;
    if (!state.accounts.any((a) => a.id == accountId)) return;

    await _repositoryFor(accountId).preload();
    state = state.copyWith(activeAccountId: accountId);
    await _storage.saveActiveAccountId(accountId);
  }

  Future<void> signOut(String accountId) async {
    await ref.read(authTokenStorageProvider).clearTokens(accountId);
    await _storage.deleteAccountData(accountId);
    await _repositoryFor(accountId).deleteAccountRecords();
    final remaining = state.accounts.where((a) => a.id != accountId).toList();
    final nextActiveId = state.activeAccountId == accountId
        ? (remaining.isNotEmpty ? remaining.first.id : null)
        : state.activeAccountId;

    state = AccountState(accounts: remaining, activeAccountId: nextActiveId);
    await _storage.saveAccounts(remaining);
    await _storage.saveActiveAccountId(nextActiveId);
  }
}

final accountProvider = NotifierProvider<AccountNotifier, AccountState>(
  AccountNotifier.new,
);
