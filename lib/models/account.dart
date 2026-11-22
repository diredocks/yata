import 'package:flutter/foundation.dart';

@immutable
class Account {
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

  Account copyWith({
    String? id,
    String? displayName,
    String? email,
    DateTime? createdAt,
  }) {
    return Account(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'displayName': displayName,
      'email': email,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
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
