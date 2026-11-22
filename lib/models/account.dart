import 'package:freezed_annotation/freezed_annotation.dart';

part 'account.freezed.dart';
part 'account.g.dart';

DateTime _dateTimeFromJsonOrNow(Object? raw) {
  if (raw is String && raw.isNotEmpty) {
    return DateTime.parse(raw);
  }
  return DateTime.now();
}

@Freezed(unionKey: 'accountType', fallbackUnion: 'local')
sealed class Account with _$Account {
  const Account._();

  const factory Account.local({
    required String id,
    required String displayName,
    @Default('') String email,
    @JsonKey(fromJson: _dateTimeFromJsonOrNow) required DateTime createdAt,
  }) = LocalAccount;

  const factory Account.microsoft({
    required String id,
    required String displayName,
    @Default('') String email,
    @JsonKey(fromJson: _dateTimeFromJsonOrNow) required DateTime createdAt,
    @Default('') String microsoftUserId,
    String? avatarBase64,
    DateTime? lastSyncedAt,
    String? syncError,
  }) = MicrosoftAccount;

  factory Account.fromJson(Map<String, dynamic> json) =>
      _$AccountFromJson(json);

  bool get isMicrosoft => this is MicrosoftAccount;
  bool get isLocal => this is LocalAccount;

  /// Derives a display name and subtitle/email from user login input.
  static ({String displayName, String email}) parseLoginInput(
    String rawInput, {
    required String fallbackName,
    required String fallbackEmail,
  }) {
    final trimmed = rawInput.trim();
    if (trimmed.isEmpty) {
      return (displayName: fallbackName, email: fallbackEmail);
    }
    if (trimmed.contains('@')) {
      final localPart = trimmed.split('@').first.trim();
      final displayName = localPart.isEmpty
          ? trimmed
          : '${localPart[0].toUpperCase()}${localPart.substring(1)}';
      return (displayName: displayName, email: trimmed);
    }
    return (displayName: trimmed, email: fallbackEmail);
  }
}
