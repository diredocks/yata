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
      'createdAt': utcDateTimeToJson(instance.createdAt),
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
      lastSyncedAt: nullableUtcDateTimeFromJson(
        json['lastSyncedAt'] as String?,
      ),
      syncError: json['syncError'] as String?,
      $type: json['accountType'] as String?,
    );

Map<String, dynamic> _$MicrosoftAccountToJson(MicrosoftAccount instance) =>
    <String, dynamic>{
      'id': instance.id,
      'displayName': instance.displayName,
      'email': instance.email,
      'createdAt': utcDateTimeToJson(instance.createdAt),
      'microsoftUserId': instance.microsoftUserId,
      'avatarBase64': instance.avatarBase64,
      'lastSyncedAt': nullableUtcDateTimeToJson(instance.lastSyncedAt),
      'syncError': instance.syncError,
      'accountType': instance.$type,
    };
