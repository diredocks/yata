import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/local/account_local_storage.dart';
import '../models/account.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final accountLocalStorageProvider = Provider<AccountLocalStorage>((ref) {
  return AccountLocalStorage(ref.watch(sharedPreferencesProvider));
});

@immutable
class AccountState {
  const AccountState({
    required this.accounts,
    required this.activeAccountId,
  });

  final List<Account> accounts;
  final String? activeAccountId;

  Account? get activeAccount {
    if (activeAccountId == null) return null;
    for (final account in accounts) {
      if (account.id == activeAccountId) return account;
    }
    return accounts.isNotEmpty ? accounts.first : null;
  }

  AccountState copyWith({
    List<Account>? accounts,
    String? activeAccountId,
    bool clearActiveAccountId = false,
  }) {
    return AccountState(
      accounts: accounts ?? this.accounts,
      activeAccountId: clearActiveAccountId
          ? null
          : (activeAccountId ?? this.activeAccountId),
    );
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
  Future<Account> signInLocal(
    String rawInput, {
    required String fallbackName,
    required String fallbackEmail,
  }) async {
    final parsed = Account.parseLoginInput(
      rawInput,
      fallbackName: fallbackName,
      fallbackEmail: fallbackEmail,
    );
    final account = Account(
      id: _nextAccountId(),
      displayName: parsed.displayName,
      email: parsed.email,
      createdAt: DateTime.now(),
    );

    final nextAccounts = [...state.accounts, account];
    state = AccountState(
      accounts: nextAccounts,
      activeAccountId: account.id,
    );
    await _storage.saveAccounts(nextAccounts);
    await _storage.saveActiveAccountId(account.id);
    return account;
  }

  Future<void> switchAccount(String accountId) async {
    if (state.activeAccountId == accountId) return;
    if (!state.accounts.any((a) => a.id == accountId)) return;

    state = state.copyWith(activeAccountId: accountId);
    await _storage.saveActiveAccountId(accountId);
  }

  Future<void> signOut(String accountId) async {
    await _storage.deleteAccountData(accountId);
    final remaining = state.accounts.where((a) => a.id != accountId).toList();
    final nextActiveId = state.activeAccountId == accountId
        ? (remaining.isNotEmpty ? remaining.first.id : null)
        : state.activeAccountId;

    state = AccountState(
      accounts: remaining,
      activeAccountId: nextActiveId,
    );
    await _storage.saveAccounts(remaining);
    await _storage.saveActiveAccountId(nextActiveId);
  }
}

final accountProvider = NotifierProvider<AccountNotifier, AccountState>(
  AccountNotifier.new,
);
