// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
Account _$AccountFromJson(
  Map<String, dynamic> json
) {
        switch (json['accountType']) {
                  case 'microsoft':
          return MicrosoftAccount.fromJson(
            json
          );
        
          default:
            return LocalAccount.fromJson(
  json
);
        }
      
}

/// @nodoc
mixin _$Account {

 String get id; String get displayName; String get email;
/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCopyWith<Account> get copyWith => _$AccountCopyWithImpl<Account>(this as Account, _$identity);

  /// Serializes this Account to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as Account;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Account&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.email, _this.email) || other.email == _this.email));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as Account;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.email);
}

@override
String toString() {
  final _this = this as Account;
  return 'Account(id: ${_this.id}, displayName: ${_this.displayName}, email: ${_this.email})';
}


}

/// @nodoc
abstract mixin class $AccountCopyWith<$Res>  {
  factory $AccountCopyWith(Account value, $Res Function(Account) _then) = _$AccountCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, String email
});




}
/// @nodoc
class _$AccountCopyWithImpl<$Res>
    implements $AccountCopyWith<$Res> {
  _$AccountCopyWithImpl(this._self, this._then);

  final Account _self;
  final $Res Function(Account) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? email = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Account].
extension AccountPatterns on Account {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LocalAccount value)?  local,TResult Function( MicrosoftAccount value)?  microsoft,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LocalAccount() when local != null:
return local(_that);case MicrosoftAccount() when microsoft != null:
return microsoft(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LocalAccount value)  local,required TResult Function( MicrosoftAccount value)  microsoft,}){
final _that = this;
switch (_that) {
case LocalAccount():
return local(_that);case MicrosoftAccount():
return microsoft(_that);}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LocalAccount value)?  local,TResult? Function( MicrosoftAccount value)?  microsoft,}){
final _that = this;
switch (_that) {
case LocalAccount() when local != null:
return local(_that);case MicrosoftAccount() when microsoft != null:
return microsoft(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String displayName,  String email)?  local,TResult Function( String id,  String displayName,  String email,  String microsoftUserId,  String? avatarBase64, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? lastSyncedAt,  String? syncError)?  microsoft,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LocalAccount() when local != null:
return local(_that.id,_that.displayName,_that.email);case MicrosoftAccount() when microsoft != null:
return microsoft(_that.id,_that.displayName,_that.email,_that.microsoftUserId,_that.avatarBase64,_that.lastSyncedAt,_that.syncError);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String displayName,  String email)  local,required TResult Function( String id,  String displayName,  String email,  String microsoftUserId,  String? avatarBase64, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? lastSyncedAt,  String? syncError)  microsoft,}) {final _that = this;
switch (_that) {
case LocalAccount():
return local(_that.id,_that.displayName,_that.email);case MicrosoftAccount():
return microsoft(_that.id,_that.displayName,_that.email,_that.microsoftUserId,_that.avatarBase64,_that.lastSyncedAt,_that.syncError);}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String displayName,  String email)?  local,TResult? Function( String id,  String displayName,  String email,  String microsoftUserId,  String? avatarBase64, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? lastSyncedAt,  String? syncError)?  microsoft,}) {final _that = this;
switch (_that) {
case LocalAccount() when local != null:
return local(_that.id,_that.displayName,_that.email);case MicrosoftAccount() when microsoft != null:
return microsoft(_that.id,_that.displayName,_that.email,_that.microsoftUserId,_that.avatarBase64,_that.lastSyncedAt,_that.syncError);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class LocalAccount extends Account {
  const LocalAccount({required this.id, required this.displayName, this.email = '',  String? $type}): $type = $type ?? 'local',super._();
  factory LocalAccount.fromJson(Map<String, dynamic> json) => _$LocalAccountFromJson(json);

@override final  String id;
@override final  String displayName;
@override@JsonKey() final  String email;

@JsonKey(name: 'accountType')
final String $type;


/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalAccountCopyWith<LocalAccount> get copyWith => _$LocalAccountCopyWithImpl<LocalAccount>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$LocalAccountToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalAccount&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.email, email) || other.email == email));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,email);
}

@override
String toString() {
    return 'Account.local(id: $id, displayName: $displayName, email: $email)';
}


}

/// @nodoc
abstract mixin class $LocalAccountCopyWith<$Res> implements $AccountCopyWith<$Res> {
  factory $LocalAccountCopyWith(LocalAccount value, $Res Function(LocalAccount) _then) = _$LocalAccountCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String email
});




}
/// @nodoc
class _$LocalAccountCopyWithImpl<$Res>
    implements $LocalAccountCopyWith<$Res> {
  _$LocalAccountCopyWithImpl(this._self, this._then);

  final LocalAccount _self;
  final $Res Function(LocalAccount) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? email = null,}) {
  return _then(LocalAccount(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
@JsonSerializable()

class MicrosoftAccount extends Account {
  const MicrosoftAccount({required this.id, required this.displayName, this.email = '', this.microsoftUserId = '', this.avatarBase64, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.lastSyncedAt, this.syncError,  String? $type}): $type = $type ?? 'microsoft',super._();
  factory MicrosoftAccount.fromJson(Map<String, dynamic> json) => _$MicrosoftAccountFromJson(json);

@override final  String id;
@override final  String displayName;
@override@JsonKey() final  String email;
@JsonKey() final  String microsoftUserId;
 final  String? avatarBase64;
@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? lastSyncedAt;
 final  String? syncError;

@JsonKey(name: 'accountType')
final String $type;


/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$MicrosoftAccountCopyWith<MicrosoftAccount> get copyWith => _$MicrosoftAccountCopyWithImpl<MicrosoftAccount>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$MicrosoftAccountToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is MicrosoftAccount&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.email, email) || other.email == email)&&(identical(other.microsoftUserId, microsoftUserId) || other.microsoftUserId == microsoftUserId)&&(identical(other.avatarBase64, avatarBase64) || other.avatarBase64 == avatarBase64)&&(identical(other.lastSyncedAt, lastSyncedAt) || other.lastSyncedAt == lastSyncedAt)&&(identical(other.syncError, syncError) || other.syncError == syncError));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,email,microsoftUserId,avatarBase64,lastSyncedAt,syncError);
}

@override
String toString() {
    return 'Account.microsoft(id: $id, displayName: $displayName, email: $email, microsoftUserId: $microsoftUserId, avatarBase64: $avatarBase64, lastSyncedAt: $lastSyncedAt, syncError: $syncError)';
}


}

/// @nodoc
abstract mixin class $MicrosoftAccountCopyWith<$Res> implements $AccountCopyWith<$Res> {
  factory $MicrosoftAccountCopyWith(MicrosoftAccount value, $Res Function(MicrosoftAccount) _then) = _$MicrosoftAccountCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String email, String microsoftUserId, String? avatarBase64,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? lastSyncedAt, String? syncError
});




}
/// @nodoc
class _$MicrosoftAccountCopyWithImpl<$Res>
    implements $MicrosoftAccountCopyWith<$Res> {
  _$MicrosoftAccountCopyWithImpl(this._self, this._then);

  final MicrosoftAccount _self;
  final $Res Function(MicrosoftAccount) _then;

/// Create a copy of Account
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? email = null,Object? microsoftUserId = null,Object? avatarBase64 = freezed,Object? lastSyncedAt = freezed,Object? syncError = freezed,}) {
  return _then(MicrosoftAccount(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,email: null == email ? _self.email : email // ignore: cast_nullable_to_non_nullable
as String,microsoftUserId: null == microsoftUserId ? _self.microsoftUserId : microsoftUserId // ignore: cast_nullable_to_non_nullable
as String,avatarBase64: freezed == avatarBase64 ? _self.avatarBase64 : avatarBase64 // ignore: cast_nullable_to_non_nullable
as String?,lastSyncedAt: freezed == lastSyncedAt ? _self.lastSyncedAt : lastSyncedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,syncError: freezed == syncError ? _self.syncError : syncError // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
