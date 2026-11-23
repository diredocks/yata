// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'app_error.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AppError {

 String get message;
/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppErrorCopyWith<AppError> get copyWith => _$AppErrorCopyWithImpl<AppError>(this as AppError, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AppError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as AppError;
  return Object.hash(runtimeType,_this.message);
}

@override
String toString() {
  final _this = this as AppError;
  return 'AppError(message: ${_this.message})';
}


}

/// @nodoc
abstract mixin class $AppErrorCopyWith<$Res>  {
  factory $AppErrorCopyWith(AppError value, $Res Function(AppError) _then) = _$AppErrorCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$AppErrorCopyWithImpl<$Res>
    implements $AppErrorCopyWith<$Res> {
  _$AppErrorCopyWithImpl(this._self, this._then);

  final AppError _self;
  final $Res Function(AppError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? message = null,}) {
  return _then(_self.copyWith(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AppError].
extension AppErrorPatterns on AppError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NetworkError value)?  network,TResult Function( DatabaseError value)?  database,TResult Function( NotFoundError value)?  notFound,TResult Function( ValidationError value)?  validation,TResult Function( AuthError value)?  auth,TResult Function( UnknownError value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NetworkError() when network != null:
return network(_that);case DatabaseError() when database != null:
return database(_that);case NotFoundError() when notFound != null:
return notFound(_that);case ValidationError() when validation != null:
return validation(_that);case AuthError() when auth != null:
return auth(_that);case UnknownError() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NetworkError value)  network,required TResult Function( DatabaseError value)  database,required TResult Function( NotFoundError value)  notFound,required TResult Function( ValidationError value)  validation,required TResult Function( AuthError value)  auth,required TResult Function( UnknownError value)  unknown,}){
final _that = this;
switch (_that) {
case NetworkError():
return network(_that);case DatabaseError():
return database(_that);case NotFoundError():
return notFound(_that);case ValidationError():
return validation(_that);case AuthError():
return auth(_that);case UnknownError():
return unknown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NetworkError value)?  network,TResult? Function( DatabaseError value)?  database,TResult? Function( NotFoundError value)?  notFound,TResult? Function( ValidationError value)?  validation,TResult? Function( AuthError value)?  auth,TResult? Function( UnknownError value)?  unknown,}){
final _that = this;
switch (_that) {
case NetworkError() when network != null:
return network(_that);case DatabaseError() when database != null:
return database(_that);case NotFoundError() when notFound != null:
return notFound(_that);case ValidationError() when validation != null:
return validation(_that);case AuthError() when auth != null:
return auth(_that);case UnknownError() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String message,  String? code,  int? statusCode,  bool isRetryable)?  network,TResult Function( String message,  String? operation,  String? details)?  database,TResult Function( String message,  String? entity,  String? id)?  notFound,TResult Function( String message,  String? field)?  validation,TResult Function( String message,  String? code,  bool requiresReauth)?  auth,TResult Function( String message,  String? details)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NetworkError() when network != null:
return network(_that.message,_that.code,_that.statusCode,_that.isRetryable);case DatabaseError() when database != null:
return database(_that.message,_that.operation,_that.details);case NotFoundError() when notFound != null:
return notFound(_that.message,_that.entity,_that.id);case ValidationError() when validation != null:
return validation(_that.message,_that.field);case AuthError() when auth != null:
return auth(_that.message,_that.code,_that.requiresReauth);case UnknownError() when unknown != null:
return unknown(_that.message,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String message,  String? code,  int? statusCode,  bool isRetryable)  network,required TResult Function( String message,  String? operation,  String? details)  database,required TResult Function( String message,  String? entity,  String? id)  notFound,required TResult Function( String message,  String? field)  validation,required TResult Function( String message,  String? code,  bool requiresReauth)  auth,required TResult Function( String message,  String? details)  unknown,}) {final _that = this;
switch (_that) {
case NetworkError():
return network(_that.message,_that.code,_that.statusCode,_that.isRetryable);case DatabaseError():
return database(_that.message,_that.operation,_that.details);case NotFoundError():
return notFound(_that.message,_that.entity,_that.id);case ValidationError():
return validation(_that.message,_that.field);case AuthError():
return auth(_that.message,_that.code,_that.requiresReauth);case UnknownError():
return unknown(_that.message,_that.details);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String message,  String? code,  int? statusCode,  bool isRetryable)?  network,TResult? Function( String message,  String? operation,  String? details)?  database,TResult? Function( String message,  String? entity,  String? id)?  notFound,TResult? Function( String message,  String? field)?  validation,TResult? Function( String message,  String? code,  bool requiresReauth)?  auth,TResult? Function( String message,  String? details)?  unknown,}) {final _that = this;
switch (_that) {
case NetworkError() when network != null:
return network(_that.message,_that.code,_that.statusCode,_that.isRetryable);case DatabaseError() when database != null:
return database(_that.message,_that.operation,_that.details);case NotFoundError() when notFound != null:
return notFound(_that.message,_that.entity,_that.id);case ValidationError() when validation != null:
return validation(_that.message,_that.field);case AuthError() when auth != null:
return auth(_that.message,_that.code,_that.requiresReauth);case UnknownError() when unknown != null:
return unknown(_that.message,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class NetworkError implements AppError {
  const NetworkError({this.message = 'A network error occurred. Please try again.', this.code, this.statusCode, this.isRetryable = true});
  

@override@JsonKey() final  String message;
 final  String? code;
 final  int? statusCode;
@JsonKey() final  bool isRetryable;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NetworkErrorCopyWith<NetworkError> get copyWith => _$NetworkErrorCopyWithImpl<NetworkError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NetworkError&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code)&&(identical(other.statusCode, statusCode) || other.statusCode == statusCode)&&(identical(other.isRetryable, isRetryable) || other.isRetryable == isRetryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code,statusCode,isRetryable);
}

@override
String toString() {
    return 'AppError.network(message: $message, code: $code, statusCode: $statusCode, isRetryable: $isRetryable)';
}


}

/// @nodoc
abstract mixin class $NetworkErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $NetworkErrorCopyWith(NetworkError value, $Res Function(NetworkError) _then) = _$NetworkErrorCopyWithImpl;
@override @useResult
$Res call({
 String message, String? code, int? statusCode, bool isRetryable
});




}
/// @nodoc
class _$NetworkErrorCopyWithImpl<$Res>
    implements $NetworkErrorCopyWith<$Res> {
  _$NetworkErrorCopyWithImpl(this._self, this._then);

  final NetworkError _self;
  final $Res Function(NetworkError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,Object? statusCode = freezed,Object? isRetryable = null,}) {
  return _then(NetworkError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,statusCode: freezed == statusCode ? _self.statusCode : statusCode // ignore: cast_nullable_to_non_nullable
as int?,isRetryable: null == isRetryable ? _self.isRetryable : isRetryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class DatabaseError implements AppError {
  const DatabaseError({this.message = 'A local database error occurred.', this.operation, this.details});
  

@override@JsonKey() final  String message;
 final  String? operation;
 final  String? details;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DatabaseErrorCopyWith<DatabaseError> get copyWith => _$DatabaseErrorCopyWithImpl<DatabaseError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DatabaseError&&(identical(other.message, message) || other.message == message)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,operation,details);
}

@override
String toString() {
    return 'AppError.database(message: $message, operation: $operation, details: $details)';
}


}

/// @nodoc
abstract mixin class $DatabaseErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $DatabaseErrorCopyWith(DatabaseError value, $Res Function(DatabaseError) _then) = _$DatabaseErrorCopyWithImpl;
@override @useResult
$Res call({
 String message, String? operation, String? details
});




}
/// @nodoc
class _$DatabaseErrorCopyWithImpl<$Res>
    implements $DatabaseErrorCopyWith<$Res> {
  _$DatabaseErrorCopyWithImpl(this._self, this._then);

  final DatabaseError _self;
  final $Res Function(DatabaseError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? operation = freezed,Object? details = freezed,}) {
  return _then(DatabaseError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class NotFoundError implements AppError {
  const NotFoundError({this.message = 'The requested item could not be found.', this.entity, this.id});
  

@override@JsonKey() final  String message;
 final  String? entity;
 final  String? id;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NotFoundErrorCopyWith<NotFoundError> get copyWith => _$NotFoundErrorCopyWithImpl<NotFoundError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NotFoundError&&(identical(other.message, message) || other.message == message)&&(identical(other.entity, entity) || other.entity == entity)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,entity,id);
}

@override
String toString() {
    return 'AppError.notFound(message: $message, entity: $entity, id: $id)';
}


}

/// @nodoc
abstract mixin class $NotFoundErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $NotFoundErrorCopyWith(NotFoundError value, $Res Function(NotFoundError) _then) = _$NotFoundErrorCopyWithImpl;
@override @useResult
$Res call({
 String message, String? entity, String? id
});




}
/// @nodoc
class _$NotFoundErrorCopyWithImpl<$Res>
    implements $NotFoundErrorCopyWith<$Res> {
  _$NotFoundErrorCopyWithImpl(this._self, this._then);

  final NotFoundError _self;
  final $Res Function(NotFoundError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? entity = freezed,Object? id = freezed,}) {
  return _then(NotFoundError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,entity: freezed == entity ? _self.entity : entity // ignore: cast_nullable_to_non_nullable
as String?,id: freezed == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class ValidationError implements AppError {
  const ValidationError({this.message = 'The provided input is invalid.', this.field});
  

@override@JsonKey() final  String message;
 final  String? field;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ValidationErrorCopyWith<ValidationError> get copyWith => _$ValidationErrorCopyWithImpl<ValidationError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ValidationError&&(identical(other.message, message) || other.message == message)&&(identical(other.field, field) || other.field == field));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,field);
}

@override
String toString() {
    return 'AppError.validation(message: $message, field: $field)';
}


}

/// @nodoc
abstract mixin class $ValidationErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $ValidationErrorCopyWith(ValidationError value, $Res Function(ValidationError) _then) = _$ValidationErrorCopyWithImpl;
@override @useResult
$Res call({
 String message, String? field
});




}
/// @nodoc
class _$ValidationErrorCopyWithImpl<$Res>
    implements $ValidationErrorCopyWith<$Res> {
  _$ValidationErrorCopyWithImpl(this._self, this._then);

  final ValidationError _self;
  final $Res Function(ValidationError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? field = freezed,}) {
  return _then(ValidationError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,field: freezed == field ? _self.field : field // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc


class AuthError implements AppError {
  const AuthError({this.message = 'Authentication failed. Please sign in again.', this.code, this.requiresReauth = false});
  

@override@JsonKey() final  String message;
 final  String? code;
@JsonKey() final  bool requiresReauth;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AuthErrorCopyWith<AuthError> get copyWith => _$AuthErrorCopyWithImpl<AuthError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AuthError&&(identical(other.message, message) || other.message == message)&&(identical(other.code, code) || other.code == code)&&(identical(other.requiresReauth, requiresReauth) || other.requiresReauth == requiresReauth));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,code,requiresReauth);
}

@override
String toString() {
    return 'AppError.auth(message: $message, code: $code, requiresReauth: $requiresReauth)';
}


}

/// @nodoc
abstract mixin class $AuthErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AuthErrorCopyWith(AuthError value, $Res Function(AuthError) _then) = _$AuthErrorCopyWithImpl;
@override @useResult
$Res call({
 String message, String? code, bool requiresReauth
});




}
/// @nodoc
class _$AuthErrorCopyWithImpl<$Res>
    implements $AuthErrorCopyWith<$Res> {
  _$AuthErrorCopyWithImpl(this._self, this._then);

  final AuthError _self;
  final $Res Function(AuthError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? code = freezed,Object? requiresReauth = null,}) {
  return _then(AuthError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,code: freezed == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String?,requiresReauth: null == requiresReauth ? _self.requiresReauth : requiresReauth // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class UnknownError implements AppError {
  const UnknownError({this.message = 'An unexpected error occurred.', this.details});
  

@override@JsonKey() final  String message;
 final  String? details;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnknownErrorCopyWith<UnknownError> get copyWith => _$UnknownErrorCopyWithImpl<UnknownError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownError&&(identical(other.message, message) || other.message == message)&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message,details);
}

@override
String toString() {
    return 'AppError.unknown(message: $message, details: $details)';
}


}

/// @nodoc
abstract mixin class $UnknownErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $UnknownErrorCopyWith(UnknownError value, $Res Function(UnknownError) _then) = _$UnknownErrorCopyWithImpl;
@override @useResult
$Res call({
 String message, String? details
});




}
/// @nodoc
class _$UnknownErrorCopyWithImpl<$Res>
    implements $UnknownErrorCopyWith<$Res> {
  _$UnknownErrorCopyWithImpl(this._self, this._then);

  final UnknownError _self;
  final $Res Function(UnknownError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? message = null,Object? details = freezed,}) {
  return _then(UnknownError(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
