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
mixin _$TaskItem {

 String get id; String get listId; String get title;@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime get createdAt; bool get isCompleted; bool get isImportant; bool get isInMyDay; DateTime? get myDayDate; DateTime? get postponedDay; DateTime? get dueDate;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get reminderAt;@JsonKey(unknownEnumValue: RecurrenceType.none) RecurrenceType get recurrence; String get note;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get noteUpdatedAt;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get completedAt; List<TaskStep> get steps; String? get remoteId; String? get remoteParentFolderId;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get orderDateTime;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get committedOrder; String? get changeKey;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get updatedAt;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskItem&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.isCompleted, _this.isCompleted) || other.isCompleted == _this.isCompleted)&&(identical(other.isImportant, _this.isImportant) || other.isImportant == _this.isImportant)&&(identical(other.isInMyDay, _this.isInMyDay) || other.isInMyDay == _this.isInMyDay)&&(identical(other.myDayDate, _this.myDayDate) || other.myDayDate == _this.myDayDate)&&(identical(other.postponedDay, _this.postponedDay) || other.postponedDay == _this.postponedDay)&&(identical(other.dueDate, _this.dueDate) || other.dueDate == _this.dueDate)&&(identical(other.reminderAt, _this.reminderAt) || other.reminderAt == _this.reminderAt)&&(identical(other.recurrence, _this.recurrence) || other.recurrence == _this.recurrence)&&(identical(other.note, _this.note) || other.note == _this.note)&&(identical(other.noteUpdatedAt, _this.noteUpdatedAt) || other.noteUpdatedAt == _this.noteUpdatedAt)&&(identical(other.completedAt, _this.completedAt) || other.completedAt == _this.completedAt)&&const DeepCollectionEquality().equals(other.steps, _this.steps)&&(identical(other.remoteId, _this.remoteId) || other.remoteId == _this.remoteId)&&(identical(other.remoteParentFolderId, _this.remoteParentFolderId) || other.remoteParentFolderId == _this.remoteParentFolderId)&&(identical(other.orderDateTime, _this.orderDateTime) || other.orderDateTime == _this.orderDateTime)&&(identical(other.committedOrder, _this.committedOrder) || other.committedOrder == _this.committedOrder)&&(identical(other.changeKey, _this.changeKey) || other.changeKey == _this.changeKey)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TaskItem;
  return Object.hashAll([runtimeType,_this.id,_this.listId,_this.title,_this.createdAt,_this.isCompleted,_this.isImportant,_this.isInMyDay,_this.myDayDate,_this.postponedDay,_this.dueDate,_this.reminderAt,_this.recurrence,_this.note,_this.noteUpdatedAt,_this.completedAt,const DeepCollectionEquality().hash(_this.steps),_this.remoteId,_this.remoteParentFolderId,_this.orderDateTime,_this.committedOrder,_this.changeKey,_this.updatedAt]);
}

@override
String toString() {
  final _this = this as TaskItem;
  return 'TaskItem(id: ${_this.id}, listId: ${_this.listId}, title: ${_this.title}, createdAt: ${_this.createdAt}, isCompleted: ${_this.isCompleted}, isImportant: ${_this.isImportant}, isInMyDay: ${_this.isInMyDay}, myDayDate: ${_this.myDayDate}, postponedDay: ${_this.postponedDay}, dueDate: ${_this.dueDate}, reminderAt: ${_this.reminderAt}, recurrence: ${_this.recurrence}, note: ${_this.note}, noteUpdatedAt: ${_this.noteUpdatedAt}, completedAt: ${_this.completedAt}, steps: ${_this.steps}, remoteId: ${_this.remoteId}, remoteParentFolderId: ${_this.remoteParentFolderId}, orderDateTime: ${_this.orderDateTime}, committedOrder: ${_this.committedOrder}, changeKey: ${_this.changeKey}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $TaskItemCopyWith<$Res>  {
  factory $TaskItemCopyWith(TaskItem value, $Res Function(TaskItem) _then) = _$TaskItemCopyWithImpl;
@useResult
$Res call({
 String id, String listId, String title,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime createdAt, bool isCompleted, bool isImportant, bool isInMyDay, DateTime? myDayDate, DateTime? postponedDay, DateTime? dueDate,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? reminderAt,@JsonKey(unknownEnumValue: RecurrenceType.none) RecurrenceType recurrence, String note,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? noteUpdatedAt,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? completedAt, List<TaskStep> steps, String? remoteId, String? remoteParentFolderId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? committedOrder, String? changeKey,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? listId = null,Object? title = null,Object? createdAt = null,Object? isCompleted = null,Object? isImportant = null,Object? isInMyDay = null,Object? myDayDate = freezed,Object? postponedDay = freezed,Object? dueDate = freezed,Object? reminderAt = freezed,Object? recurrence = null,Object? note = null,Object? noteUpdatedAt = freezed,Object? completedAt = freezed,Object? steps = null,Object? remoteId = freezed,Object? remoteParentFolderId = freezed,Object? orderDateTime = freezed,Object? committedOrder = freezed,Object? changeKey = freezed,Object? updatedAt = freezed,}) {
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
as RecurrenceType,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,noteUpdatedAt: freezed == noteUpdatedAt ? _self.noteUpdatedAt : noteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,steps: null == steps ? _self.steps : steps // ignore: cast_nullable_to_non_nullable
as List<TaskStep>,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,remoteParentFolderId: freezed == remoteParentFolderId ? _self.remoteParentFolderId : remoteParentFolderId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,committedOrder: freezed == committedOrder ? _self.committedOrder : committedOrder // ignore: cast_nullable_to_non_nullable
as DateTime?,changeKey: freezed == changeKey ? _self.changeKey : changeKey // ignore: cast_nullable_to_non_nullable
as String?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskItem].
extension TaskItemPatterns on TaskItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskItem value)  $default,){
final _that = this;
switch (_that) {
case _TaskItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskItem value)?  $default,){
final _that = this;
switch (_that) {
case _TaskItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String listId,  String title, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson)  DateTime createdAt,  bool isCompleted,  bool isImportant,  bool isInMyDay,  DateTime? myDayDate,  DateTime? postponedDay,  DateTime? dueDate, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? reminderAt, @JsonKey(unknownEnumValue: RecurrenceType.none)  RecurrenceType recurrence,  String note, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? noteUpdatedAt, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? completedAt,  List<TaskStep> steps,  String? remoteId,  String? remoteParentFolderId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? committedOrder,  String? changeKey, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskItem() when $default != null:
return $default(_that.id,_that.listId,_that.title,_that.createdAt,_that.isCompleted,_that.isImportant,_that.isInMyDay,_that.myDayDate,_that.postponedDay,_that.dueDate,_that.reminderAt,_that.recurrence,_that.note,_that.noteUpdatedAt,_that.completedAt,_that.steps,_that.remoteId,_that.remoteParentFolderId,_that.orderDateTime,_that.committedOrder,_that.changeKey,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String listId,  String title, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson)  DateTime createdAt,  bool isCompleted,  bool isImportant,  bool isInMyDay,  DateTime? myDayDate,  DateTime? postponedDay,  DateTime? dueDate, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? reminderAt, @JsonKey(unknownEnumValue: RecurrenceType.none)  RecurrenceType recurrence,  String note, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? noteUpdatedAt, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? completedAt,  List<TaskStep> steps,  String? remoteId,  String? remoteParentFolderId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? committedOrder,  String? changeKey, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _TaskItem():
return $default(_that.id,_that.listId,_that.title,_that.createdAt,_that.isCompleted,_that.isImportant,_that.isInMyDay,_that.myDayDate,_that.postponedDay,_that.dueDate,_that.reminderAt,_that.recurrence,_that.note,_that.noteUpdatedAt,_that.completedAt,_that.steps,_that.remoteId,_that.remoteParentFolderId,_that.orderDateTime,_that.committedOrder,_that.changeKey,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String listId,  String title, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson)  DateTime createdAt,  bool isCompleted,  bool isImportant,  bool isInMyDay,  DateTime? myDayDate,  DateTime? postponedDay,  DateTime? dueDate, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? reminderAt, @JsonKey(unknownEnumValue: RecurrenceType.none)  RecurrenceType recurrence,  String note, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? noteUpdatedAt, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? completedAt,  List<TaskStep> steps,  String? remoteId,  String? remoteParentFolderId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? committedOrder,  String? changeKey, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _TaskItem() when $default != null:
return $default(_that.id,_that.listId,_that.title,_that.createdAt,_that.isCompleted,_that.isImportant,_that.isInMyDay,_that.myDayDate,_that.postponedDay,_that.dueDate,_that.reminderAt,_that.recurrence,_that.note,_that.noteUpdatedAt,_that.completedAt,_that.steps,_that.remoteId,_that.remoteParentFolderId,_that.orderDateTime,_that.committedOrder,_that.changeKey,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskItem extends TaskItem {
  const _TaskItem({required this.id, required this.listId, required this.title, @JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) required this.createdAt, this.isCompleted = false, this.isImportant = false, this.isInMyDay = false, this.myDayDate, this.postponedDay, this.dueDate, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.reminderAt, @JsonKey(unknownEnumValue: RecurrenceType.none) this.recurrence = RecurrenceType.none, this.note = '', @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.noteUpdatedAt, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.completedAt,  List<TaskStep> steps = const <TaskStep>[], this.remoteId, this.remoteParentFolderId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.committedOrder, this.changeKey, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.updatedAt}): _steps = steps,super._();
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
@override@JsonKey() final  String note;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? noteUpdatedAt;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? completedAt;
 final  List<TaskStep> _steps;
@override@JsonKey() List<TaskStep> get steps {
  if (_steps is EqualUnmodifiableListView) return _steps;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_steps);
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
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskItem&&(identical(other.id, id) || other.id == id)&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.title, title) || other.title == title)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.isCompleted, isCompleted) || other.isCompleted == isCompleted)&&(identical(other.isImportant, isImportant) || other.isImportant == isImportant)&&(identical(other.isInMyDay, isInMyDay) || other.isInMyDay == isInMyDay)&&(identical(other.myDayDate, myDayDate) || other.myDayDate == myDayDate)&&(identical(other.postponedDay, postponedDay) || other.postponedDay == postponedDay)&&(identical(other.dueDate, dueDate) || other.dueDate == dueDate)&&(identical(other.reminderAt, reminderAt) || other.reminderAt == reminderAt)&&(identical(other.recurrence, recurrence) || other.recurrence == recurrence)&&(identical(other.note, note) || other.note == note)&&(identical(other.noteUpdatedAt, noteUpdatedAt) || other.noteUpdatedAt == noteUpdatedAt)&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&const DeepCollectionEquality().equals(other.steps, _steps)&&(identical(other.remoteId, remoteId) || other.remoteId == remoteId)&&(identical(other.remoteParentFolderId, remoteParentFolderId) || other.remoteParentFolderId == remoteParentFolderId)&&(identical(other.orderDateTime, orderDateTime) || other.orderDateTime == orderDateTime)&&(identical(other.committedOrder, committedOrder) || other.committedOrder == committedOrder)&&(identical(other.changeKey, changeKey) || other.changeKey == changeKey)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hashAll([runtimeType,id,listId,title,createdAt,isCompleted,isImportant,isInMyDay,myDayDate,postponedDay,dueDate,reminderAt,recurrence,note,noteUpdatedAt,completedAt,const DeepCollectionEquality().hash(_steps),remoteId,remoteParentFolderId,orderDateTime,committedOrder,changeKey,updatedAt]);
}

@override
String toString() {
    return 'TaskItem(id: $id, listId: $listId, title: $title, createdAt: $createdAt, isCompleted: $isCompleted, isImportant: $isImportant, isInMyDay: $isInMyDay, myDayDate: $myDayDate, postponedDay: $postponedDay, dueDate: $dueDate, reminderAt: $reminderAt, recurrence: $recurrence, note: $note, noteUpdatedAt: $noteUpdatedAt, completedAt: $completedAt, steps: $steps, remoteId: $remoteId, remoteParentFolderId: $remoteParentFolderId, orderDateTime: $orderDateTime, committedOrder: $committedOrder, changeKey: $changeKey, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$TaskItemCopyWith<$Res> implements $TaskItemCopyWith<$Res> {
  factory _$TaskItemCopyWith(_TaskItem value, $Res Function(_TaskItem) _then) = __$TaskItemCopyWithImpl;
@override @useResult
$Res call({
 String id, String listId, String title,@JsonKey(fromJson: utcDateTimeFromJson, toJson: utcDateTimeToJson) DateTime createdAt, bool isCompleted, bool isImportant, bool isInMyDay, DateTime? myDayDate, DateTime? postponedDay, DateTime? dueDate,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? reminderAt,@JsonKey(unknownEnumValue: RecurrenceType.none) RecurrenceType recurrence, String note,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? noteUpdatedAt,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? completedAt, List<TaskStep> steps, String? remoteId, String? remoteParentFolderId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? committedOrder, String? changeKey,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? listId = null,Object? title = null,Object? createdAt = null,Object? isCompleted = null,Object? isImportant = null,Object? isInMyDay = null,Object? myDayDate = freezed,Object? postponedDay = freezed,Object? dueDate = freezed,Object? reminderAt = freezed,Object? recurrence = null,Object? note = null,Object? noteUpdatedAt = freezed,Object? completedAt = freezed,Object? steps = null,Object? remoteId = freezed,Object? remoteParentFolderId = freezed,Object? orderDateTime = freezed,Object? committedOrder = freezed,Object? changeKey = freezed,Object? updatedAt = freezed,}) {
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
as RecurrenceType,note: null == note ? _self.note : note // ignore: cast_nullable_to_non_nullable
as String,noteUpdatedAt: freezed == noteUpdatedAt ? _self.noteUpdatedAt : noteUpdatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,completedAt: freezed == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,steps: null == steps ? _self._steps : steps // ignore: cast_nullable_to_non_nullable
as List<TaskStep>,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
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
