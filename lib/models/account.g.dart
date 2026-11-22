// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

LocalAccount _$LocalAccountFromJson(Map<String, dynamic> json) => LocalAccount(
  id: json['id'] as String,
  displayName: json['displayName'] as String,
  email: json['email'] as String? ?? '',
  createdAt: _dateTimeFromJsonOrNow(json['createdAt']),
  $type: json['accountType'] as String?,
);

Map<String, dynamic> _$LocalAccountToJson(LocalAccount instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'email': instance.email,
      'createdAt': instance.createdAt.toIso8601String(),
      'accountType': instance.$type,
    };

MicrosoftAccount _$MicrosoftAccountFromJson(Map<String, dynamic> json) =>
    MicrosoftAccount(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      email: json['email'] as String? ?? '',
      createdAt: _dateTimeFromJsonOrNow(json['createdAt']),
      microsoftUserId: json['microsoftUserId'] as String? ?? '',
      avatarBase64: json['avatarBase64'] as String?,
      lastSyncedAt: json['lastSyncedAt'] == null
          ? null
          : DateTime.parse(json['lastSyncedAt'] as String),
      syncError: json['syncError'] as String?,
      $type: json['accountType'] as String?,
    );

Map<String, dynamic> _$MicrosoftAccountToJson(MicrosoftAccount instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'email': instance.email,
      'createdAt': instance.createdAt.toIso8601String(),
      'microsoftUserId': instance.microsoftUserId,
      'avatarBase64': instance.avatarBase64,
      'lastSyncedAt': instance.lastSyncedAt?.toIso8601String(),
      'syncError': instance.syncError,
      'accountType': instance.$type,
    };
