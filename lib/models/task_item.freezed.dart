// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'task_item.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TaskStep {

 String get id; String get title; bool get isCompleted; String? get remoteId;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get orderDateTime;
/// Create a copy of TaskStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskStepCopyWith<TaskStep> get copyWith => _$TaskStepCopyWithImpl<TaskStep>(this as TaskStep, _$identity);

  /// Serializes this TaskStep to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TaskStep;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskStep&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.isCompleted, _this.isCompleted) || other.isCompleted == _this.isCompleted)&&(identical(other.remoteId, _this.remoteId) || other.remoteId == _this.remoteId)&&(identical(other.orderDateTime, _this.orderDateTime) || other.orderDateTime == _this.orderDateTime));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TaskStep;
  return Object.hash(runtimeType,_this.id,_this.title,_this.isCompleted,_this.remoteId,_this.orderDateTime);
}

@override
String toString() {
  final _this = this as TaskStep;
  return 'TaskStep(id: ${_this.id}, title: ${_this.title}, isCompleted: ${_this.isCompleted}, remoteId: ${_this.remoteId}, orderDateTime: ${_this.orderDateTime})';
}


}

/// @nodoc
abstract mixin class $TaskStepCopyWith<$Res>  {
  factory $TaskStepCopyWith(TaskStep value, $Res Function(TaskStep) _then) = _$TaskStepCopyWithImpl;
@useResult
$Res call({
 String id, String title, bool isCompleted, String? remoteId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime
});




}
/// @nodoc
class _$TaskStepCopyWithImpl<$Res>
    implements $TaskStepCopyWith<$Res> {
  _$TaskStepCopyWithImpl(this._self, this._then);

  final TaskStep _self;
  final $Res Function(TaskStep) _then;

/// Create a copy of TaskStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? isCompleted = null,Object? remoteId = freezed,Object? orderDateTime = freezed,}) {
  return _then(TaskStep(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskStep].
extension TaskStepPatterns on TaskStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskStep value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskStep() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskStep value)  $default,){
final _that = this;
switch (_that) {
case _TaskStep():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskStep value)?  $default,){
final _that = this;
switch (_that) {
case _TaskStep() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  bool isCompleted,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskStep() when $default != null:
return $default(_that.id,_that.title,_that.isCompleted,_that.remoteId,_that.orderDateTime);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  bool isCompleted,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime)  $default,) {final _that = this;
switch (_that) {
case _TaskStep():
return $default(_that.id,_that.title,_that.isCompleted,_that.remoteId,_that.orderDateTime);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  bool isCompleted,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime)?  $default,) {final _that = this;
switch (_that) {
case _TaskStep() when $default != null:
return $default(_that.id,_that.title,_that.isCompleted,_that.remoteId,_that.orderDateTime);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskStep implements TaskStep {
  const _TaskStep({required this.id, required this.title, this.isCompleted = false, this.remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.orderDateTime});
  factory _TaskStep.fromJson(Map<String, dynamic> json) => _$TaskStepFromJson(json);

@override final  String id;
@override final  String title;
@override@JsonKey() final  bool isCompleted;
@override final  String? remoteId;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? orderDateTime;

/// Create a copy of TaskStep
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskStepCopyWith<_TaskStep> get copyWith => __$TaskStepCopyWithImpl<_TaskStep>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskStepToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskStep&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.remoteId, remoteId) || other.remoteId == remoteId)&&(identical(other.orderDateTime, orderDateTime) || other.orderDateTime == orderDateTime));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,title,isCompleted,remoteId,orderDateTime);
}

@override
String toString() {
    return 'TaskStep(id: $id, title: $title, isCompleted: $isCompleted, remoteId: $remoteId, orderDateTime: $orderDateTime)';
}


}

/// @nodoc
abstract mixin class _$TaskStepCopyWith<$Res> implements $TaskStepCopyWith<$Res> {
  factory _$TaskStepCopyWith(_TaskStep value, $Res Function(_TaskStep) _then) = __$TaskStepCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, bool isCompleted, String? remoteId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime
});




}
/// @nodoc
class __$TaskStepCopyWithImpl<$Res>
    implements _$TaskStepCopyWith<$Res> {
  __$TaskStepCopyWithImpl(this._self, this._then);

  final _TaskStep _self;
  final $Res Function(_TaskStep) _then;

/// Create a copy of TaskStep
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? isCompleted = null,Object? remoteId = freezed,Object? orderDateTime = freezed,}) {
  return _then(_TaskStep(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$TaskAttachment {

 String get id; String get displayName; String? get remoteId; String get entityType; String? get entitySubType; String? get webLink; String? get contentType; int get size;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get lastModifiedDateTime; String? get localPath; bool get isTransferring;
/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskAttachmentCopyWith<TaskAttachment> get copyWith => _$TaskAttachmentCopyWithImpl<TaskAttachment>(this as TaskAttachment, _$identity);

  /// Serializes this TaskAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TaskAttachment;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskAttachment&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.remoteId, _this.remoteId) || other.remoteId == _this.remoteId)&&(identical(other.entityType, _this.entityType) || other.entityType == _this.entityType)&&(identical(other.entitySubType, _this.entitySubType) || other.entitySubType == _this.entitySubType)&&(identical(other.webLink, _this.webLink) || other.webLink == _this.webLink)&&(identical(other.contentType, _this.contentType) || other.contentType == _this.contentType)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.lastModifiedDateTime, _this.lastModifiedDateTime) || other.lastModifiedDateTime == _this.lastModifiedDateTime)&&(identical(other.localPath, _this.localPath) || other.localPath == _this.localPath)&&(identical(other.isTransferring, _this.isTransferring) || other.isTransferring == _this.isTransferring));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TaskAttachment;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.remoteId,_this.entityType,_this.entitySubType,_this.webLink,_this.contentType,_this.size,_this.lastModifiedDateTime,_this.localPath,_this.isTransferring);
}

@override
String toString() {
  final _this = this as TaskAttachment;
  return 'TaskAttachment(id: ${_this.id}, displayName: ${_this.displayName}, remoteId: ${_this.remoteId}, entityType: ${_this.entityType}, entitySubType: ${_this.entitySubType}, webLink: ${_this.webLink}, contentType: ${_this.contentType}, size: ${_this.size}, lastModifiedDateTime: ${_this.lastModifiedDateTime}, localPath: ${_this.localPath}, isTransferring: ${_this.isTransferring})';
}


}

/// @nodoc
abstract mixin class $TaskAttachmentCopyWith<$Res>  {
  factory $TaskAttachmentCopyWith(TaskAttachment value, $Res Function(TaskAttachment) _then) = _$TaskAttachmentCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, String? remoteId, String entityType, String? entitySubType, String? webLink, String? contentType, int size,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? lastModifiedDateTime, String? localPath, bool isTransferring
});




}
/// @nodoc
class _$TaskAttachmentCopyWithImpl<$Res>
    implements $TaskAttachmentCopyWith<$Res> {
  _$TaskAttachmentCopyWithImpl(this._self, this._then);

  final TaskAttachment _self;
  final $Res Function(TaskAttachment) _then;

/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? remoteId = freezed,Object? entityType = null,Object? entitySubType = freezed,Object? webLink = freezed,Object? contentType = freezed,Object? size = null,Object? lastModifiedDateTime = freezed,Object? localPath = freezed,Object? isTransferring = null,}) {
  return _then(TaskAttachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,entityType: null == entityType ? _self.entityType : entityType // ignore: cast_nullable_to_non_nullable
as String,entitySubType: freezed == entitySubType ? _self.entitySubType : entitySubType // ignore: cast_nullable_to_non_nullable
as String?,webLink: freezed == webLink ? _self.webLink : webLink // ignore: cast_nullable_to_non_nullable
as String?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,lastModifiedDateTime: freezed == lastModifiedDateTime ? _self.lastModifiedDateTime : lastModifiedDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,isTransferring: null == isTransferring ? _self.isTransferring : isTransferring // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskAttachment].
extension TaskAttachmentPatterns on TaskAttachment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskAttachment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskAttachment value)  $default,){
final _that = this;
switch (_that) {
case _TaskAttachment():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskAttachment value)?  $default,){
final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  String? remoteId,  String entityType,  String? entitySubType,  String? webLink,  String? contentType,  int size, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? lastModifiedDateTime,  String? localPath,  bool isTransferring)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that.id,_that.displayName,_that.remoteId,_that.entityType,_that.entitySubType,_that.webLink,_that.contentType,_that.size,_that.lastModifiedDateTime,_that.localPath,_that.isTransferring);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  String? remoteId,  String entityType,  String? entitySubType,  String? webLink,  String? contentType,  int size, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? lastModifiedDateTime,  String? localPath,  bool isTransferring)  $default,) {final _that = this;
switch (_that) {
case _TaskAttachment():
return $default(_that.id,_that.displayName,_that.remoteId,_that.entityType,_that.entitySubType,_that.webLink,_that.contentType,_that.size,_that.lastModifiedDateTime,_that.localPath,_that.isTransferring);case _:
  throw StateError('Unexpected subclass');

}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  String? remoteId,  String entityType,  String? entitySubType,  String? webLink,  String? contentType,  int size, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? lastModifiedDateTime,  String? localPath,  bool isTransferring)?  $default,) {final _that = this;
switch (_that) {
case _TaskAttachment() when $default != null:
return $default(_that.id,_that.displayName,_that.remoteId,_that.entityType,_that.entitySubType,_that.webLink,_that.contentType,_that.size,_that.lastModifiedDateTime,_that.localPath,_that.isTransferring);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskAttachment extends TaskAttachment {
  const _TaskAttachment({required this.id, required this.displayName, this.remoteId, this.entityType = 'file', this.entitySubType, this.webLink, this.contentType, this.size = 0, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.lastModifiedDateTime, this.localPath, this.isTransferring = false}): super._();
  factory _TaskAttachment.fromJson(Map<String, dynamic> json) => _$TaskAttachmentFromJson(json);

@override final  String id;
@override final  String displayName;
@override final  String? remoteId;
@override@JsonKey() final  String entityType;
@override final  String? entitySubType;
@override final  String? webLink;
@override final  String? contentType;
@override@JsonKey() final  int size;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? lastModifiedDateTime;
@override final  String? localPath;
@override@JsonKey() final  bool isTransferring;

/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskAttachmentCopyWith<_TaskAttachment> get copyWith => __$TaskAttachmentCopyWithImpl<_TaskAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskAttachment&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.remoteId, remoteId) || other.remoteId == remoteId)&&(identical(other.entityType, entityType) || other.entityType == entityType)&&(identical(other.entitySubType, entitySubType) || other.entitySubType == entitySubType)&&(identical(other.webLink, webLink) || other.webLink == webLink)&&(identical(other.contentType, contentType) || other.contentType == contentType)&&(identical(other.size, size) || other.size == size)&&(identical(other.lastModifiedDateTime, lastModifiedDateTime) || other.lastModifiedDateTime == lastModifiedDateTime)&&(identical(other.localPath, localPath) || other.localPath == localPath)&&(identical(other.isTransferring, isTransferring) || other.isTransferring == isTransferring));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,remoteId,entityType,entitySubType,webLink,contentType,size,lastModifiedDateTime,localPath,isTransferring);
}

@override
String toString() {
    return 'TaskAttachment(id: $id, displayName: $displayName, remoteId: $remoteId, entityType: $entityType, entitySubType: $entitySubType, webLink: $webLink, contentType: $contentType, size: $size, lastModifiedDateTime: $lastModifiedDateTime, localPath: $localPath, isTransferring: $isTransferring)';
}


}

/// @nodoc
abstract mixin class _$TaskAttachmentCopyWith<$Res> implements $TaskAttachmentCopyWith<$Res> {
  factory _$TaskAttachmentCopyWith(_TaskAttachment value, $Res Function(_TaskAttachment) _then) = __$TaskAttachmentCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String? remoteId, String entityType, String? entitySubType, String? webLink, String? contentType, int size,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? lastModifiedDateTime, String? localPath, bool isTransferring
});




}
/// @nodoc
class __$TaskAttachmentCopyWithImpl<$Res>
    implements _$TaskAttachmentCopyWith<$Res> {
  __$TaskAttachmentCopyWithImpl(this._self, this._then);

  final _TaskAttachment _self;
  final $Res Function(_TaskAttachment) _then;

/// Create a copy of TaskAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? remoteId = freezed,Object? entityType = null,Object? entitySubType = freezed,Object? webLink = freezed,Object? contentType = freezed,Object? size = null,Object? lastModifiedDateTime = freezed,Object? localPath = freezed,Object? isTransferring = null,}) {
  return _then(_TaskAttachment(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,entityType: null == entityType ? _self.entityType : entityType // ignore: cast_nullable_to_non_nullable
as String,entitySubType: freezed == entitySubType ? _self.entitySubType : entitySubType // ignore: cast_nullable_to_non_nullable
as String?,webLink: freezed == webLink ? _self.webLink : webLink // ignore: cast_nullable_to_non_nullable
as String?,contentType: freezed == contentType ? _self.contentType : contentType // ignore: cast_nullable_to_non_nullable
as String?,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,lastModifiedDateTime: freezed == lastModifiedDateTime ? _self.lastModifiedDateTime : lastModifiedDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,localPath: freezed == localPath ? _self.localPath : localPath // ignore: cast_nullable_to_non_nullable
as String?,isTransferring: null == isTransferring ? _self.isTransferring : isTransferring // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}


/// @nodoc
mixin _$TaskItem {

 String get id; String get listId; String get title;@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime get createdAt; bool get isCompleted; bool get isImportant; bool get isInMyDay; DateTime? get myDayDate; DateTime? get postponedDay; DateTime? get dueDate;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get reminderAt;@JsonKey(unknownEnumValue: RecurrenceType.none) RecurrenceType get recurrence; Map<String, dynamic>? get rawRecurrence; String get note; String get noteHtml; String? get noteContentType;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get noteUpdatedAt;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get completedAt; List<TaskStep> get steps; List<TaskAttachment> get attachments; String? get remoteId; String? get remoteParentFolderId;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get orderDateTime;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get committedOrder; String? get changeKey;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get updatedAt;
/// Create a copy of TaskItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskItemCopyWith<TaskItem> get copyWith => _$TaskItemCopyWithImpl<TaskItem>(this as TaskItem, _$identity);

  /// Serializes this TaskItem to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TaskItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskItem&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.isCompleted, _this.isCompleted) || other.isCompleted == _this.isCompleted)&&(identical(other.isImportant, _this.isImportant) || other.isImportant == _this.isImportant)&&(identical(other.isInMyDay, _this.isInMyDay) || other.isInMyDay == _this.isInMyDay)&&(identical(other.myDayDate, _this.myDayDate) || other.myDayDate == _this.myDayDate)&&(identical(other.postponedDay, _this.postponedDay) || other.postponedDay == _this.postponedDay)&&(identical(other.dueDate, _this.dueDate) || other.dueDate == _this.dueDate)&&(identical(other.reminderAt, _this.reminderAt) || other.reminderAt == _this.reminderAt)&&(identical(other.recurrence, _this.recurrence) || other.recurrence == _this.recurrence)&&const DeepCollectionEquality().equals(other.rawRecurrence, _this.rawRecurrence)&&(identical(other.note, _this.note) || other.note == _this.note)&&(identical(other.noteHtml, _this.noteHtml) || other.noteHtml == _this.noteHtml)&&(identical(other.noteContentType, _this.noteContentType) || other.noteContentType == _this.noteContentType)&&(identical(other.noteUpdatedAt, _this.noteUpdatedAt) || other.noteUpdatedAt == _this.noteUpdatedAt)&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt)&&const DeepCollectionEquality().equals(other.steps, _this.steps)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&(identical(other.remoteId, _this.remoteId) || other.remoteId == _this.remoteId)&&(identical(other.remoteParentFolderId, _this.remoteParentFolderId) || other.remoteParentFolderId == _this.remoteParentFolderId)&&(identical(other.orderDateTime, _this.orderDateTime) || other.orderDateTime == _this.orderDateTime)&&(identical(other.committedOrder, _this.committedOrder) || other.committedOrder == _this.committedOrder)&&(identical(other.changeKey, _this.changeKey) || other.changeKey == _this.changeKey)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TaskItem;
  return Object.hashAll([runtimeType,_this.id,_this.listId,_this.title,_this.createdAt,_this.isCompleted,_this.isImportant,_this.isInMyDay,_this.myDayDate,_this.postponedDay,_this.dueDate,_this.reminderAt,_this.recurrence,const DeepCollectionEquality().hash(_this.rawRecurrence),_this.note,_this.noteHtml,_this.noteContentType,_this.noteUpdatedAt,_this.completedAt,const DeepCollectionEquality().hash(_this.steps),const DeepCollectionEquality().hash(_this.attachments),_this.remoteId,_this.remoteParentFolderId,_this.orderDateTime,_this.committedOrder,_this.changeKey,_this.updatedAt]);
}

@override
String toString() {
  final _this = this as TaskItem;
  return 'TaskItem(id: ${_this.id}, listId: ${_this.listId}, title: ${_this.title}, createdAt: ${_this.createdAt}, isCompleted: ${_this.isCompleted}, isImportant: ${_this.isImportant}, isInMyDay: ${_this.isInMyDay}, myDayDate: ${_this.myDayDate}, postponedDay: ${_this.postponedDay}, dueDate: ${_this.dueDate}, reminderAt: ${_this.reminderAt}, recurrence: ${_this.recurrence}, rawRecurrence: ${_this.rawRecurrence}, note: ${_this.note}, noteHtml: ${_this.noteHtml}, noteContentType: ${_this.noteContentType}, noteUpdatedAt: ${_this.noteUpdatedAt}, completedAt: ${_this.completedAt}, steps: ${_this.steps}, attachments: ${_this.attachments}, remoteId: ${_this.remoteId}, remoteParentFolderId: ${_this.remoteParentFolderId}, orderDateTime: ${_this.orderDateTime}, committedOrder: ${_this.committedOrder}, changeKey: ${_this.changeKey}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $TaskItemCopyWith<$Res>  {
  factory $TaskItemCopyWith(TaskItem value, $Res Function(TaskItem) _then) = _$TaskItemCopyWithImpl;
@useResult
$Res call({
 String id, String listId, String title,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime createdAt, bool isCompleted, bool isImportant, bool isInMyDay, DateTime? myDayDate, DateTime? postponedDay, DateTime? dueDate,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? reminderAt,@JsonKey(unknownEnumValue: RecurrenceType.none) RecurrenceType recurrence, Map<String, dynamic>? rawRecurrence, String note, String noteHtml, String? noteContentType,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? noteUpdatedAt,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? completedAt, List<TaskStep> steps, List<TaskAttachment> attachments, String? remoteId, String? remoteParentFolderId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? committedOrder, String? changeKey,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
});




}
/// @nodoc
class _$TaskItemCopyWithImpl<$Res>
    implements $TaskItemCopyWith<$Res> {
  _$TaskItemCopyWithImpl(this._self, this._then);

  final TaskItem _self;
  final $Res Function(TaskItem) _then;

/// Create a copy of TaskItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? listId = null,Object? title = null,Object? createdAt = null,Object? isCompleted = null,Object? isImportant = null,Object? isInMyDay = null,Object? myDayDate = freezed,Object? postponedDay = freezed,Object? dueDate = freezed,Object? reminderAt = freezed,Object? recurrence = null,Object? rawRecurrence = freezed,Object? note = null,Object? noteHtml = null,Object? noteContentType = freezed,Object? noteUpdatedAt = freezed,Object? completedAt = freezed,Object? steps = null,Object? attachments = null,Object? remoteId = freezed,Object? remoteParentFolderId = freezed,Object? orderDateTime = freezed,Object? committedOrder = freezed,Object? changeKey = freezed,Object? updatedAt = freezed,}) {
  return _then(TaskItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,isImportant: null == isImportant ? _self.isImportant : isImportant // ignore: cast_nullable_to_non_nullable
as bool,isInMyDay: null == isInMyDay ? _self.isInMyDay : isInMyDay // ignore: cast_nullable_to_non_nullable
as bool,myDayDate: freezed == myDayDate ? _self.myDayDate : myDayDate // ignore: cast_nullable_to_non_nullable
as DateTime?,postponedDay: freezed == postponedDay ? _self.postponedDay : postponedDay // ignore: cast_nullable_to_non_nullable
as DateTime?,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as DateTime?,reminderAt: freezed == reminderAt ? _self.reminderAt : reminderAt // ignore: cast_nullable_to_non_nullable
as DateTime?,recurrence: null == recurrence ? _self.recurrence : recurrence // ignore: cast_nullable_to_non_nullable
as RecurrenceType,rawRecurrence: freezed == rawRecurrence ? _self._rawRecurrence : rawRecurrence // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,noteHtml: null == noteHtml ? _self.noteHtml : noteHtml // ignore: cast_nullable_to_non_nullable
as String,noteContentType: freezed == noteContentType ? _self.noteContentType : noteContentType // ignore: cast_nullable_to_non_nullable
as String?,noteUpdatedAt: freezed == noteUpdatedAt ? _self.noteUpdatedAt : noteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<TaskStep>,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<TaskAttachment>,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,remoteParentFolderId: freezed == remoteParentFolderId ? _self.remoteParentFolderId : remoteParentFolderId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,committedOrder: freezed == committedOrder ? _self.committedOrder : committedOrder // ignore: cast_nullable_to_non_nullable
as DateTime?,changeKey: freezed == changeKey ? _self.changeKey : changeKey // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// @nodoc
@JsonSerializable()

class _TaskItem extends TaskItem {
  const _TaskItem({required this.id, required this.listId, required this.title, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) required this.createdAt, this.isCompleted = false, this.isImportant = false, this.isInMyDay = false, this.myDayDate, this.postponedDay, this.dueDate, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.reminderAt, @JsonKey(unknownEnumValue: RecurrenceType.none) this.recurrence = RecurrenceType.none,  Map<String, dynamic>? rawRecurrence, this.note = '', this.noteHtml = '', this.noteContentType, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.noteUpdatedAt, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.completedAt,  List<TaskStep> steps = const <TaskStep>[],  List<TaskAttachment> attachments = const <TaskAttachment>[], this.remoteId, this.remoteParentFolderId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.committedOrder, this.changeKey, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.updatedAt}): _rawRecurrence = rawRecurrence,_steps = steps,_attachments = attachments,super._();
  factory _TaskItem.fromJson(Map<String, dynamic> json) => _$TaskItemFromJson(json);

@override final  String id;
@override final  String listId;
@override final  String title;
@override@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) final  DateTime createdAt;
@override@JsonKey() final  bool isCompleted;
@override@JsonKey() final  bool isImportant;
@override@JsonKey() final  bool isInMyDay;
@override final  DateTime? myDayDate;
@override final  DateTime? postponedDay;
@override final  DateTime? dueDate;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? reminderAt;
@override@JsonKey(unknownEnumValue: RecurrenceType.none) final  RecurrenceType recurrence;
 final  Map<String, dynamic>? _rawRecurrence;
@override Map<String, dynamic>? get rawRecurrence {
  final value = _rawRecurrence;
  if (value == null) return null;
  if (_rawRecurrence is EqualUnmodifiableMapView) return _rawRecurrence;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}

@override@JsonKey() final  String note;
@override@JsonKey() final  String noteHtml;
@override final  String? noteContentType;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? noteUpdatedAt;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? completedAt;
 final  List<TaskStep> _steps;
@override@JsonKey() List<TaskStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
}

 final  List<TaskAttachment> _attachments;
@override@JsonKey() List<TaskAttachment> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}

@override final  String? remoteId;
@override final  String? remoteParentFolderId;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? orderDateTime;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? committedOrder;
@override final  String? changeKey;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? updatedAt;

/// Create a copy of TaskItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskItemCopyWith<_TaskItem> get copyWith => __$TaskItemCopyWithImpl<_TaskItem>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskItemToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskItem&&(identical(other.id, id) || other.id == id)&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.isImportant, isImportant) || other.isImportant == isImportant)&&(identical(other.isInMyDay, isInMyDay) || other.isInMyDay == isInMyDay)&&(identical(other.myDayDate, myDayDate) || other.myDayDate == myDayDate)&&(identical(other.postponedDay, postponedDay) || other.postponedDay == postponedDay)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.reminderAt, reminderAt) || other.reminderAt == reminderAt)&&(identical(other.recurrence, recurrence) || other.recurrence == recurrence)&&const DeepCollectionEquality().equals(other.rawRecurrence, _rawRecurrence)&&(identical(other.note, note) || other.note == note)&&(identical(other.noteHtml, noteHtml) || other.noteHtml == noteHtml)&&(identical(other.noteContentType, noteContentType) || other.noteContentType == noteContentType)&&(identical(other.noteUpdatedAt, noteUpdatedAt) || other.noteUpdatedAt == noteUpdatedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&const DeepCollectionEquality().equals(other.steps, _steps)&&const DeepCollectionEquality().equals(other.attachments, _attachments)&&(identical(other.remoteId, remoteId) || other.remoteId == remoteId)&&(identical(other.remoteParentFolderId, remoteParentFolderId) || other.remoteParentFolderId == remoteParentFolderId)&&(identical(other.orderDateTime, orderDateTime) || other.orderDateTime == orderDateTime)&&(identical(other.committedOrder, committedOrder) || other.committedOrder == committedOrder)&&(identical(other.changeKey, changeKey) || other.changeKey == changeKey)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,listId,title,createdAt,isCompleted,isImportant,isInMyDay,myDayDate,postponedDay,dueDate,reminderAt,recurrence,const DeepCollectionEquality().hash(_rawRecurrence),note,noteHtml,noteContentType,noteUpdatedAt,completedAt,const DeepCollectionEquality().hash(_steps),const DeepCollectionEquality().hash(_attachments),remoteId,remoteParentFolderId,orderDateTime,committedOrder,changeKey,updatedAt]);
}

@override
String toString() {
    return 'TaskItem(id: $id, listId: $listId, title: $title, createdAt: $createdAt, isCompleted: $isCompleted, isImportant: $isImportant, isInMyDay: $isInMyDay, myDayDate: $myDayDate, postponedDay: $postponedDay, dueDate: $dueDate, reminderAt: $reminderAt, recurrence: $recurrence, rawRecurrence: $rawRecurrence, note: $note, noteHtml: $noteHtml, noteContentType: $noteContentType, noteUpdatedAt: $noteUpdatedAt, completedAt: $completedAt, steps: $steps, attachments: $attachments, remoteId: $remoteId, remoteParentFolderId: $remoteParentFolderId, orderDateTime: $orderDateTime, committedOrder: $committedOrder, changeKey: $changeKey, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$TaskItemCopyWith<$Res> implements $TaskItemCopyWith<$Res> {
  factory _$TaskItemCopyWith(_TaskItem value, $Res Function(_TaskItem) _then) = __$TaskItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String listId, String title,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime createdAt, bool isCompleted, bool isImportant, bool isInMyDay, DateTime? myDayDate, DateTime? postponedDay, DateTime? dueDate,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? reminderAt,@JsonKey(unknownEnumValue: RecurrenceType.none) RecurrenceType recurrence, Map<String, dynamic>? rawRecurrence, String note, String noteHtml, String? noteContentType,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? noteUpdatedAt,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? completedAt, List<TaskStep> steps, List<TaskAttachment> attachments, String? remoteId, String? remoteParentFolderId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? committedOrder, String? changeKey,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
});




}
/// @nodoc
class __$TaskItemCopyWithImpl<$Res>
    implements _$TaskItemCopyWith<$Res> {
  __$TaskItemCopyWithImpl(this._self, this._then);

  final _TaskItem _self;
  final $Res Function(_TaskItem) _then;

/// Create a copy of TaskItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? listId = null,Object? title = null,Object? createdAt = null,Object? isCompleted = null,Object? isImportant = null,Object? isInMyDay = null,Object? myDayDate = freezed,Object? postponedDay = freezed,Object? dueDate = freezed,Object? reminderAt = freezed,Object? recurrence = null,Object? rawRecurrence = freezed,Object? note = null,Object? noteHtml = null,Object? noteContentType = freezed,Object? noteUpdatedAt = freezed,Object? completedAt = freezed,Object? steps = null,Object? attachments = null,Object? remoteId = freezed,Object? remoteParentFolderId = freezed,Object? orderDateTime = freezed,Object? committedOrder = freezed,Object? changeKey = freezed,Object? updatedAt = freezed,}) {
  return _then(_TaskItem(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,isCompleted: null == isCompleted ? _self.isCompleted : isCompleted // ignore: cast_nullable_to_non_nullable
as bool,isImportant: null == isImportant ? _self.isImportant : isImportant // ignore: cast_nullable_to_non_nullable
as bool,isInMyDay: null == isInMyDay ? _self.isInMyDay : isInMyDay // ignore: cast_nullable_to_non_nullable
as bool,myDayDate: freezed == myDayDate ? _self.myDayDate : myDayDate // ignore: cast_nullable_to_non_nullable
as DateTime?,postponedDay: freezed == postponedDay ? _self.postponedDay : postponedDay // ignore: cast_nullable_to_non_nullable
as DateTime?,dueDate: freezed == dueDate ? _self.dueDate : dueDate // ignore: cast_nullable_to_non_nullable
as DateTime?,reminderAt: freezed == reminderAt ? _self.reminderAt : reminderAt // ignore: cast_nullable_to_non_nullable
as DateTime?,recurrence: null == recurrence ? _self.recurrence : recurrence // ignore: cast_nullable_to_non_nullable
as RecurrenceType,rawRecurrence: freezed == rawRecurrence ? _self._rawRecurrence : rawRecurrence // ignore: cast_nullable_to_non_nullable
as Map<String, dynamic>?,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,noteHtml: null == noteHtml ? _self.noteHtml : noteHtml // ignore: cast_nullable_to_non_nullable
as String,noteContentType: freezed == noteContentType ? _self.noteContentType : noteContentType // ignore: cast_nullable_to_non_nullable
as String?,noteUpdatedAt: freezed == noteUpdatedAt ? _self.noteUpdatedAt : noteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<TaskStep>,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<TaskAttachment>,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,remoteParentFolderId: freezed == remoteParentFolderId ? _self.remoteParentFolderId : remoteParentFolderId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,committedOrder: freezed == committedOrder ? _self.committedOrder : committedOrder // ignore: cast_nullable_to_non_nullable
as DateTime?,changeKey: freezed == changeKey ? _self.changeKey : changeKey // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
