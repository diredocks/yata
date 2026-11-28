import '../auth/microsoft_auth_service.dart';
import '../models/account.dart';
import '../core/network/http_guard.dart';

typedef UpdateMicrosoftProfileCallback = Future<void> Function(
  String accountId, {
  String? displayName,
  String? email,
  String? avatarBase64,
});

/// Backfills missing displayName, email, or avatar for a signed-in
/// [MicrosoftAccount] after a successful sync pass.
Future<void> refreshMicrosoftProfileIfIncomplete({
  required MicrosoftAuthClient authClient,
  required AuthTokenStorage tokenStorage,
  required MicrosoftAccount account,
  required bool Function() isDisposed,
  required UpdateMicrosoftProfileCallback onProfileUpdated,
}) async {
  final needsName =
      account.displayName == 'Microsoft Account' ||
      account.displayName.trim().isEmpty ||
      (account.email.isNotEmpty && account.displayName == account.email);
  final needsEmail = account.email.trim().isEmpty;
  final needsAvatar =
      account.avatarBase64 == null || account.avatarBase64!.isEmpty;
  if (!needsName && !needsEmail && !needsAvatar) return;

  await guardApiCall(() async {
    final tokens = await tokenStorage.loadTokens(account.id);
    if (tokens == null || tokens.refreshToken.isEmpty) return;
    final cid = tokens.userId.isNotEmpty
        ? tokens.userId
        : account.microsoftUserId;
    final profile = await authClient.fetchUserProfile(
      cid: cid,
      refreshToken: tokens.refreshToken,
      fallbackEmail: account.email,
    );
    if (isDisposed()) return;

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

    if (nextName == null && nextEmail == null && nextAvatar == null) return;
    await onProfileUpdated(
      account.id,
      displayName: nextName,
      email: nextEmail,
      avatarBase64: nextAvatar,
    );
  }, operation: 'refreshProfile');
}
