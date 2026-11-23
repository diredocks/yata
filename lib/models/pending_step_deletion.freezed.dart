// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'pending_step_deletion.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PendingStepDeletion {

 String get taskRemoteId; String get stepRemoteId;
/// Create a copy of PendingStepDeletion
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PendingStepDeletionCopyWith<PendingStepDeletion> get copyWith => _$PendingStepDeletionCopyWithImpl<PendingStepDeletion>(this as PendingStepDeletion, _$identity);

  /// Serializes this PendingStepDeletion to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as PendingStepDeletion;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingStepDeletion&&(identical(other.taskRemoteId, _this.taskRemoteId) || other.taskRemoteId == _this.taskRemoteId)&&(identical(other.stepRemoteId, _this.stepRemoteId) || other.stepRemoteId == _this.stepRemoteId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as PendingStepDeletion;
  return Object.hash(runtimeType,_this.taskRemoteId,_this.stepRemoteId);
}

@override
String toString() {
  final _this = this as PendingStepDeletion;
  return 'PendingStepDeletion(taskRemoteId: ${_this.taskRemoteId}, stepRemoteId: ${_this.stepRemoteId})';
}


}

/// @nodoc
abstract mixin class $PendingStepDeletionCopyWith<$Res>  {
  factory $PendingStepDeletionCopyWith(PendingStepDeletion value, $Res Function(PendingStepDeletion) _then) = _$PendingStepDeletionCopyWithImpl;
@useResult
$Res call({
 String taskRemoteId, String stepRemoteId
});




}
/// @nodoc
class _$PendingStepDeletionCopyWithImpl<$Res>
    implements $PendingStepDeletionCopyWith<$Res> {
  _$PendingStepDeletionCopyWithImpl(this._self, this._then);

  final PendingStepDeletion _self;
  final $Res Function(PendingStepDeletion) _then;

/// Create a copy of PendingStepDeletion
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? taskRemoteId = null,Object? stepRemoteId = null,}) {
  return _then(PendingStepDeletion(
taskRemoteId: null == taskRemoteId ? _self.taskRemoteId : taskRemoteId // ignore: cast_nullable_to_non_nullable
as String,stepRemoteId: null == stepRemoteId ? _self.stepRemoteId : stepRemoteId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [PendingStepDeletion].
extension PendingStepDeletionPatterns on PendingStepDeletion {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PendingStepDeletion value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PendingStepDeletion() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PendingStepDeletion value)  $default,){
final _that = this;
switch (_that) {
case _PendingStepDeletion():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PendingStepDeletion value)?  $default,){
final _that = this;
switch (_that) {
case _PendingStepDeletion() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String taskRemoteId,  String stepRemoteId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PendingStepDeletion() when $default != null:
return $default(_that.taskRemoteId,_that.stepRemoteId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String taskRemoteId,  String stepRemoteId)  $default,) {final _that = this;
switch (_that) {
case _PendingStepDeletion():
return $default(_that.taskRemoteId,_that.stepRemoteId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String taskRemoteId,  String stepRemoteId)?  $default,) {final _that = this;
switch (_that) {
case _PendingStepDeletion() when $default != null:
return $default(_that.taskRemoteId,_that.stepRemoteId);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PendingStepDeletion implements PendingStepDeletion {
  const _PendingStepDeletion({required this.taskRemoteId, required this.stepRemoteId});
  factory _PendingStepDeletion.fromJson(Map<String, dynamic> json) => _$PendingStepDeletionFromJson(json);

@override final  String taskRemoteId;
@override final  String stepRemoteId;

/// Create a copy of PendingStepDeletion
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PendingStepDeletionCopyWith<_PendingStepDeletion> get copyWith => __$PendingStepDeletionCopyWithImpl<_PendingStepDeletion>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PendingStepDeletionToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PendingStepDeletion&&(identical(other.taskRemoteId, taskRemoteId) || other.taskRemoteId == taskRemoteId)&&(identical(other.stepRemoteId, stepRemoteId) || other.stepRemoteId == stepRemoteId));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,taskRemoteId,stepRemoteId);
}

@override
String toString() {
    return 'PendingStepDeletion(taskRemoteId: $taskRemoteId, stepRemoteId: $stepRemoteId)';
}


}

/// @nodoc
abstract mixin class _$PendingStepDeletionCopyWith<$Res> implements $PendingStepDeletionCopyWith<$Res> {
  factory _$PendingStepDeletionCopyWith(_PendingStepDeletion value, $Res Function(_PendingStepDeletion) _then) = __$PendingStepDeletionCopyWithImpl;
@override @useResult
$Res call({
 String taskRemoteId, String stepRemoteId
});




}
/// @nodoc
class __$PendingStepDeletionCopyWithImpl<$Res>
    implements _$PendingStepDeletionCopyWith<$Res> {
  __$PendingStepDeletionCopyWithImpl(this._self, this._then);

  final _PendingStepDeletion _self;
  final $Res Function(_PendingStepDeletion) _then;

/// Create a copy of PendingStepDeletion
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? taskRemoteId = null,Object? stepRemoteId = null,}) {
  return _then(_PendingStepDeletion(
taskRemoteId: null == taskRemoteId ? _self.taskRemoteId : taskRemoteId // ignore: cast_nullable_to_non_nullable
as String,stepRemoteId: null == stepRemoteId ? _self.stepRemoteId : stepRemoteId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
