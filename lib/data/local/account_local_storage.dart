import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/account.dart';

class AccountSnapshot {
  const AccountSnapshot({
    required this.accounts,
    required this.activeAccountId,
  });

  final List<Account> accounts;
  final String? activeAccountId;
}

class AccountLocalStorage {
  AccountLocalStorage(this._prefs);

  final SharedPreferences _prefs;

  static const accountsKey = 'yata.accounts';
  static const activeAccountIdKey = 'yata.active_account_id';
  static const _accountPrefix = 'yata.acct.';

  static String accountKeyPrefix(String accountId) =>
      '$_accountPrefix$accountId.';

  AccountSnapshot load() {
    final accountsRaw = _prefs.getString(accountsKey);
    if (accountsRaw == null) {
      return const AccountSnapshot(accounts: [], activeAccountId: null);
    }

    final decoded = jsonDecode(accountsRaw) as List<dynamic>;
    final accounts = decoded
        .map((e) => Account.fromJson(e as Map<String, dynamic>))
        .toList();

    var activeId = _prefs.getString(activeAccountIdKey);
    if (accounts.isEmpty) {
      activeId = null;
    } else if (activeId == null || !accounts.any((a) => a.id == activeId)) {
      activeId = accounts.first.id;
      _prefs.setString(activeAccountIdKey, activeId);
    }

    return AccountSnapshot(accounts: accounts, activeAccountId: activeId);
  }

  Future<void> saveAccounts(List<Account> accounts) async {
    await _prefs.setString(
      accountsKey,
      jsonEncode(accounts.map((a) => a.toJson()).toList()),
    );
  }

  Future<void> saveActiveAccountId(String? accountId) async {
    if (accountId == null) {
      await _prefs.remove(activeAccountIdKey);
    } else {
      await _prefs.setString(activeAccountIdKey, accountId);
    }
  }

  Future<void> deleteAccountData(String accountId) async {
    final prefix = accountKeyPrefix(accountId);
    final keysToRemove =
        _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      await _prefs.remove(key);
    }
  }
}
