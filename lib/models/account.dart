import 'package:flutter/foundation.dart';

@immutable
sealed class Account {
  const Account({
    required this.id,
    required this.displayName,
    required this.email,
    required this.createdAt,
  });

  final String id;
  final String displayName;
  final String email;
  final DateTime createdAt;

  bool get isMicrosoft => this is MicrosoftAccount;
  bool get isLocal => this is LocalAccount;

  Map<String, dynamic> toJson();

  factory Account.fromJson(Map<String, dynamic> json) {
    final typeName = json['accountType'] as String? ?? 'local';
    if (typeName == 'microsoft') {
      return MicrosoftAccount.fromJson(json);
    }
    return LocalAccount.fromJson(json);
  }

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

@immutable
final class LocalAccount extends Account {
  const LocalAccount({
    required super.id,
    required super.displayName,
    required super.email,
    required super.createdAt,
  });

  LocalAccount copyWith({
    String? id,
    String? displayName,
    String? email,
    DateTime? createdAt,
  }) {
    return LocalAccount(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
      'accountType': 'local',
    };
  }

  factory LocalAccount.fromJson(Map<String, dynamic> json) {
    return LocalAccount(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

@immutable
final class MicrosoftAccount extends Account {
  const MicrosoftAccount({
    required super.id,
    required super.displayName,
    required super.email,
    required super.createdAt,
    required this.microsoftUserId,
    this.avatarBase64,
    this.lastSyncedAt,
    this.syncError,
  });

  final String microsoftUserId;
  final String? avatarBase64;
  final DateTime? lastSyncedAt;
  final String? syncError;

  MicrosoftAccount copyWith({
    String? id,
    String? displayName,
    String? email,
    DateTime? createdAt,
    String? microsoftUserId,
    String? avatarBase64,
    DateTime? lastSyncedAt,
    String? syncError,
    bool clearSyncError = false,
  }) {
    return MicrosoftAccount(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      microsoftUserId: microsoftUserId ?? this.microsoftUserId,
      avatarBase64: avatarBase64 ?? this.avatarBase64,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      syncError: clearSyncError ? null : (syncError ?? this.syncError),
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
      'accountType': 'microsoft',
      'microsoftUserId': microsoftUserId,
      'avatarBase64': avatarBase64,
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'syncError': syncError,
    };
  }

  factory MicrosoftAccount.fromJson(Map<String, dynamic> json) {
    return MicrosoftAccount(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      microsoftUserId: json['microsoftUserId'] as String? ?? '',
      avatarBase64: json['avatarBase64'] as String?,
      lastSyncedAt: json['lastSyncedAt'] != null
          ? DateTime.parse(json['lastSyncedAt'] as String)
          : null,
      syncError: json['syncError'] as String?,
    );
  }
}
