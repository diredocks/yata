// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'todo_list.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$TodoList {

 String get id; String get title;@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) SmartListType? get smartType; String? get groupId; String? get emoji;@JsonKey(unknownEnumValue: ListThemeColor.blue) ListThemeColor get themeColor;@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ListThemePhoto? get themePhoto; String? get customBackgroundPath;@JsonKey(unknownEnumValue: TaskSortOption.defaultOrder) TaskSortOption get sortOption; bool get sortAscending; bool get showCompleted; String? get remoteId;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get orderDateTime;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get updatedAt;
/// Create a copy of TodoList
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TodoListCopyWith<TodoList> get copyWith => _$TodoListCopyWithImpl<TodoList>(this as TodoList, _$identity);

  /// Serializes this TodoList to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as TodoList;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TodoList&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.smartType, _this.smartType) || other.smartType == _this.smartType)&&(identical(other.groupId, _this.groupId) || other.groupId == _this.groupId)&&(identical(other.emoji, _this.emoji) || other.emoji == _this.emoji)&&(identical(other.themeColor, _this.themeColor) || other.themeColor == _this.themeColor)&&(identical(other.themePhoto, _this.themePhoto) || other.themePhoto == _this.themePhoto)&&(identical(other.customBackgroundPath, _this.customBackgroundPath) || other.customBackgroundPath == _this.customBackgroundPath)&&(identical(other.sortOption, _this.sortOption) || other.sortOption == _this.sortOption)&&(identical(other.sortAscending, _this.sortAscending) || other.sortAscending == _this.sortAscending)&&(identical(other.showCompleted, _this.showCompleted) || other.showCompleted == _this.showCompleted)&&(identical(other.remoteId, _this.remoteId) || other.remoteId == _this.remoteId)&&(identical(other.orderDateTime, _this.orderDateTime) || other.orderDateTime == _this.orderDateTime)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as TodoList;
  return Object.hash(runtimeType,_this.id,_this.title,_this.smartType,_this.groupId,_this.emoji,_this.themeColor,_this.themePhoto,_this.customBackgroundPath,_this.sortOption,_this.sortAscending,_this.showCompleted,_this.remoteId,_this.orderDateTime,_this.updatedAt);
}

@override
String toString() {
  final _this = this as TodoList;
  return 'TodoList(id: ${_this.id}, title: ${_this.title}, smartType: ${_this.smartType}, groupId: ${_this.groupId}, emoji: ${_this.emoji}, themeColor: ${_this.themeColor}, themePhoto: ${_this.themePhoto}, customBackgroundPath: ${_this.customBackgroundPath}, sortOption: ${_this.sortOption}, sortAscending: ${_this.sortAscending}, showCompleted: ${_this.showCompleted}, remoteId: ${_this.remoteId}, orderDateTime: ${_this.orderDateTime}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $TodoListCopyWith<$Res>  {
  factory $TodoListCopyWith(TodoList value, $Res Function(TodoList) _then) = _$TodoListCopyWithImpl;
@useResult
$Res call({
 String id, String title,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) SmartListType? smartType, String? groupId, String? emoji,@JsonKey(unknownEnumValue: ListThemeColor.blue) ListThemeColor themeColor,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ListThemePhoto? themePhoto, String? customBackgroundPath,@JsonKey(unknownEnumValue: TaskSortOption.defaultOrder) TaskSortOption sortOption, bool sortAscending, bool showCompleted, String? remoteId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
});




}
/// @nodoc
class _$TodoListCopyWithImpl<$Res>
    implements $TodoListCopyWith<$Res> {
  _$TodoListCopyWithImpl(this._self, this._then);

  final TodoList _self;
  final $Res Function(TodoList) _then;

/// Create a copy of TodoList
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? smartType = freezed,Object? groupId = freezed,Object? emoji = freezed,Object? themeColor = null,Object? themePhoto = freezed,Object? customBackgroundPath = freezed,Object? sortOption = null,Object? sortAscending = null,Object? showCompleted = null,Object? remoteId = freezed,Object? orderDateTime = freezed,Object? updatedAt = freezed,}) {
  return _then(TodoList(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,smartType: freezed == smartType ? _self.smartType : smartType // ignore: cast_nullable_to_non_nullable
as SmartListType?,groupId: freezed == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,themeColor: null == themeColor ? _self.themeColor : themeColor // ignore: cast_nullable_to_non_nullable
as ListThemeColor,themePhoto: freezed == themePhoto ? _self.themePhoto : themePhoto // ignore: cast_nullable_to_non_nullable
as ListThemePhoto?,customBackgroundPath: freezed == customBackgroundPath ? _self.customBackgroundPath : customBackgroundPath // ignore: cast_nullable_to_non_nullable
as String?,sortOption: null == sortOption ? _self.sortOption : sortOption // ignore: cast_nullable_to_non_nullable
as TaskSortOption,sortAscending: null == sortAscending ? _self.sortAscending : sortAscending // ignore: cast_nullable_to_non_nullable
as bool,showCompleted: null == showCompleted ? _self.showCompleted : showCompleted // ignore: cast_nullable_to_non_nullable
as bool,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [TodoList].
extension TodoListPatterns on TodoList {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TodoList value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TodoList() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TodoList value)  $default,){
final _that = this;
switch (_that) {
case _TodoList():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TodoList value)?  $default,){
final _that = this;
switch (_that) {
case _TodoList() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  SmartListType? smartType,  String? groupId,  String? emoji, @JsonKey(unknownEnumValue: ListThemeColor.blue)  ListThemeColor themeColor, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ListThemePhoto? themePhoto,  String? customBackgroundPath, @JsonKey(unknownEnumValue: TaskSortOption.defaultOrder)  TaskSortOption sortOption,  bool sortAscending,  bool showCompleted,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TodoList() when $default != null:
return $default(_that.id,_that.title,_that.smartType,_that.groupId,_that.emoji,_that.themeColor,_that.themePhoto,_that.customBackgroundPath,_that.sortOption,_that.sortAscending,_that.showCompleted,_that.remoteId,_that.orderDateTime,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  SmartListType? smartType,  String? groupId,  String? emoji, @JsonKey(unknownEnumValue: ListThemeColor.blue)  ListThemeColor themeColor, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ListThemePhoto? themePhoto,  String? customBackgroundPath, @JsonKey(unknownEnumValue: TaskSortOption.defaultOrder)  TaskSortOption sortOption,  bool sortAscending,  bool showCompleted,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _TodoList():
return $default(_that.id,_that.title,_that.smartType,_that.groupId,_that.emoji,_that.themeColor,_that.themePhoto,_that.customBackgroundPath,_that.sortOption,_that.sortAscending,_that.showCompleted,_that.remoteId,_that.orderDateTime,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  SmartListType? smartType,  String? groupId,  String? emoji, @JsonKey(unknownEnumValue: ListThemeColor.blue)  ListThemeColor themeColor, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue)  ListThemePhoto? themePhoto,  String? customBackgroundPath, @JsonKey(unknownEnumValue: TaskSortOption.defaultOrder)  TaskSortOption sortOption,  bool sortAscending,  bool showCompleted,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _TodoList() when $default != null:
return $default(_that.id,_that.title,_that.smartType,_that.groupId,_that.emoji,_that.themeColor,_that.themePhoto,_that.customBackgroundPath,_that.sortOption,_that.sortAscending,_that.showCompleted,_that.remoteId,_that.orderDateTime,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TodoList extends TodoList {
  const _TodoList({required this.id, required this.title, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) this.smartType, this.groupId, this.emoji, @JsonKey(unknownEnumValue: ListThemeColor.blue) this.themeColor = ListThemeColor.blue, @JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) this.themePhoto, this.customBackgroundPath, @JsonKey(unknownEnumValue: TaskSortOption.defaultOrder) this.sortOption = TaskSortOption.defaultOrder, this.sortAscending = true, this.showCompleted = true, this.remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.updatedAt}): super._();
  factory _TodoList.fromJson(Map<String, dynamic> json) => _$TodoListFromJson(json);

@override final  String id;
@override final  String title;
@override@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) final  SmartListType? smartType;
@override final  String? groupId;
@override final  String? emoji;
@override@JsonKey(unknownEnumValue: ListThemeColor.blue) final  ListThemeColor themeColor;
@override@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) final  ListThemePhoto? themePhoto;
@override final  String? customBackgroundPath;
@override@JsonKey(unknownEnumValue: TaskSortOption.defaultOrder) final  TaskSortOption sortOption;
@override@JsonKey() final  bool sortAscending;
@override@JsonKey() final  bool showCompleted;
@override final  String? remoteId;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? orderDateTime;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? updatedAt;

/// Create a copy of TodoList
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TodoListCopyWith<_TodoList> get copyWith => __$TodoListCopyWithImpl<_TodoList>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TodoListToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TodoList&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.smartType, smartType) || other.smartType == smartType)&&(identical(other.groupId, groupId) || other.groupId == groupId)&&(identical(other.emoji, emoji) || other.emoji == emoji)&&(identical(other.themeColor, themeColor) || other.themeColor == themeColor)&&(identical(other.themePhoto, themePhoto) || other.themePhoto == themePhoto)&&(identical(other.customBackgroundPath, customBackgroundPath) || other.customBackgroundPath == customBackgroundPath)&&(identical(other.sortOption, sortOption) || other.sortOption == sortOption)&&(identical(other.sortAscending, sortAscending) || other.sortAscending == sortAscending)&&(identical(other.showCompleted, showCompleted) || other.showCompleted == showCompleted)&&(identical(other.remoteId, remoteId) || other.remoteId == remoteId)&&(identical(other.orderDateTime, orderDateTime) || other.orderDateTime == orderDateTime)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,title,smartType,groupId,emoji,themeColor,themePhoto,customBackgroundPath,sortOption,sortAscending,showCompleted,remoteId,orderDateTime,updatedAt);
}

@override
String toString() {
    return 'TodoList(id: $id, title: $title, smartType: $smartType, groupId: $groupId, emoji: $emoji, themeColor: $themeColor, themePhoto: $themePhoto, customBackgroundPath: $customBackgroundPath, sortOption: $sortOption, sortAscending: $sortAscending, showCompleted: $showCompleted, remoteId: $remoteId, orderDateTime: $orderDateTime, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$TodoListCopyWith<$Res> implements $TodoListCopyWith<$Res> {
  factory _$TodoListCopyWith(_TodoList value, $Res Function(_TodoList) _then) = __$TodoListCopyWithImpl;
@override @useResult
$Res call({
 String id, String title,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) SmartListType? smartType, String? groupId, String? emoji,@JsonKey(unknownEnumValue: ListThemeColor.blue) ListThemeColor themeColor,@JsonKey(unknownEnumValue: JsonKey.nullForUndefinedEnumValue) ListThemePhoto? themePhoto, String? customBackgroundPath,@JsonKey(unknownEnumValue: TaskSortOption.defaultOrder) TaskSortOption sortOption, bool sortAscending, bool showCompleted, String? remoteId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
});




}
/// @nodoc
class __$TodoListCopyWithImpl<$Res>
    implements _$TodoListCopyWith<$Res> {
  __$TodoListCopyWithImpl(this._self, this._then);

  final _TodoList _self;
  final $Res Function(_TodoList) _then;

/// Create a copy of TodoList
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? smartType = freezed,Object? groupId = freezed,Object? emoji = freezed,Object? themeColor = null,Object? themePhoto = freezed,Object? customBackgroundPath = freezed,Object? sortOption = null,Object? sortAscending = null,Object? showCompleted = null,Object? remoteId = freezed,Object? orderDateTime = freezed,Object? updatedAt = freezed,}) {
  return _then(_TodoList(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,smartType: freezed == smartType ? _self.smartType : smartType // ignore: cast_nullable_to_non_nullable
as SmartListType?,groupId: freezed == groupId ? _self.groupId : groupId // ignore: cast_nullable_to_non_nullable
as String?,emoji: freezed == emoji ? _self.emoji : emoji // ignore: cast_nullable_to_non_nullable
as String?,themeColor: null == themeColor ? _self.themeColor : themeColor // ignore: cast_nullable_to_non_nullable
as ListThemeColor,themePhoto: freezed == themePhoto ? _self.themePhoto : themePhoto // ignore: cast_nullable_to_non_nullable
as ListThemePhoto?,customBackgroundPath: freezed == customBackgroundPath ? _self.customBackgroundPath : customBackgroundPath // ignore: cast_nullable_to_non_nullable
as String?,sortOption: null == sortOption ? _self.sortOption : sortOption // ignore: cast_nullable_to_non_nullable
as TaskSortOption,sortAscending: null == sortAscending ? _self.sortAscending : sortAscending // ignore: cast_nullable_to_non_nullable
as bool,showCompleted: null == showCompleted ? _self.showCompleted : showCompleted // ignore: cast_nullable_to_non_nullable
as bool,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}


/// @nodoc
mixin _$ListGroup {

 String get id; String get title; bool get isExpanded; String? get remoteId;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get orderDateTime;@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? get updatedAt;
/// Create a copy of ListGroup
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ListGroupCopyWith<ListGroup> get copyWith => _$ListGroupCopyWithImpl<ListGroup>(this as ListGroup, _$identity);

  /// Serializes this ListGroup to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  final _this = this as ListGroup;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ListGroup&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.isExpanded, _this.isExpanded) || other.isExpanded == _this.isExpanded)&&(identical(other.remoteId, _this.remoteId) || other.remoteId == _this.remoteId)&&(identical(other.orderDateTime, _this.orderDateTime) || other.orderDateTime == _this.orderDateTime)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
  final _this = this as ListGroup;
  return Object.hash(runtimeType,_this.id,_this.title,_this.isExpanded,_this.remoteId,_this.orderDateTime,_this.updatedAt);
}

@override
String toString() {
  final _this = this as ListGroup;
  return 'ListGroup(id: ${_this.id}, title: ${_this.title}, isExpanded: ${_this.isExpanded}, remoteId: ${_this.remoteId}, orderDateTime: ${_this.orderDateTime}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $ListGroupCopyWith<$Res>  {
  factory $ListGroupCopyWith(ListGroup value, $Res Function(ListGroup) _then) = _$ListGroupCopyWithImpl;
@useResult
$Res call({
 String id, String title, bool isExpanded, String? remoteId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
});




}
/// @nodoc
class _$ListGroupCopyWithImpl<$Res>
    implements $ListGroupCopyWith<$Res> {
  _$ListGroupCopyWithImpl(this._self, this._then);

  final ListGroup _self;
  final $Res Function(ListGroup) _then;

/// Create a copy of ListGroup
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? isExpanded = null,Object? remoteId = freezed,Object? orderDateTime = freezed,Object? updatedAt = freezed,}) {
  return _then(ListGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isExpanded: null == isExpanded ? _self.isExpanded : isExpanded // ignore: cast_nullable_to_non_nullable
as bool,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

}


/// Adds pattern-matching-related methods to [ListGroup].
extension ListGroupPatterns on ListGroup {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ListGroup value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ListGroup() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ListGroup value)  $default,){
final _that = this;
switch (_that) {
case _ListGroup():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ListGroup value)?  $default,){
final _that = this;
switch (_that) {
case _ListGroup() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  bool isExpanded,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ListGroup() when $default != null:
return $default(_that.id,_that.title,_that.isExpanded,_that.remoteId,_that.orderDateTime,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  bool isExpanded,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _ListGroup():
return $default(_that.id,_that.title,_that.isExpanded,_that.remoteId,_that.orderDateTime,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  bool isExpanded,  String? remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _ListGroup() when $default != null:
return $default(_that.id,_that.title,_that.isExpanded,_that.remoteId,_that.orderDateTime,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ListGroup implements ListGroup {
  const _ListGroup({required this.id, required this.title, this.isExpanded = true, this.remoteId, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.orderDateTime, @JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) this.updatedAt});
  factory _ListGroup.fromJson(Map<String, dynamic> json) => _$ListGroupFromJson(json);

@override final  String id;
@override final  String title;
@override@JsonKey() final  bool isExpanded;
@override final  String? remoteId;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? orderDateTime;
@override@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) final  DateTime? updatedAt;

/// Create a copy of ListGroup
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ListGroupCopyWith<_ListGroup> get copyWith => __$ListGroupCopyWithImpl<_ListGroup>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ListGroupToJson(this, );
}

@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ListGroup&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.isExpanded, isExpanded) || other.isExpanded == isExpanded)&&(identical(other.remoteId, remoteId) || other.remoteId == remoteId)&&(identical(other.orderDateTime, orderDateTime) || other.orderDateTime == orderDateTime)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode {
    return Object.hash(runtimeType,id,title,isExpanded,remoteId,orderDateTime,updatedAt);
}

@override
String toString() {
    return 'ListGroup(id: $id, title: $title, isExpanded: $isExpanded, remoteId: $remoteId, orderDateTime: $orderDateTime, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$ListGroupCopyWith<$Res> implements $ListGroupCopyWith<$Res> {
  factory _$ListGroupCopyWith(_ListGroup value, $Res Function(_ListGroup) _then) = __$ListGroupCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, bool isExpanded, String? remoteId,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? orderDateTime,@JsonKey(fromJson: nullableUtcDateTimeFromJson, toJson: nullableUtcDateTimeToJson) DateTime? updatedAt
});




}
/// @nodoc
class __$ListGroupCopyWithImpl<$Res>
    implements _$ListGroupCopyWith<$Res> {
  __$ListGroupCopyWithImpl(this._self, this._then);

  final _ListGroup _self;
  final $Res Function(_ListGroup) _then;

/// Create a copy of ListGroup
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? isExpanded = null,Object? remoteId = freezed,Object? orderDateTime = freezed,Object? updatedAt = freezed,}) {
  return _then(_ListGroup(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,isExpanded: null == isExpanded ? _self.isExpanded : isExpanded // ignore: cast_nullable_to_non_nullable
as bool,remoteId: freezed == remoteId ? _self.remoteId : remoteId // ignore: cast_nullable_to_non_nullable
as String?,orderDateTime: freezed == orderDateTime ? _self.orderDateTime : orderDateTime // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}


}

// dart format on
