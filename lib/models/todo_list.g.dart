// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'todo_list.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_TodoList _$TodoListFromJson(Map<String, dynamic> json) => _TodoList(
  id: json['id'] as String,
  title: json['title'] as String,
  smartType: $enumDecodeNullable(
    _$SmartListTypeEnumMap,
    json['smartType'],
    unknownValue: JsonKey.nullForUndefinedEnumValue,
  ),
  groupId: json['groupId'] as String?,
  emoji: json['emoji'] as String?,
  themeColor:
      $enumDecodeNullable(
        _$ListThemeColorEnumMap,
        json['themeColor'],
        unknownValue: ListThemeColor.blue,
      ) ??
      ListThemeColor.blue,
  themePhoto: $enumDecodeNullable(
    _$ListThemePhotoEnumMap,
    json['themePhoto'],
    unknownValue: JsonKey.nullForUndefinedEnumValue,
  ),
  icon: _readSmartTypeForIcon(json, 'icon') == null
      ? Icons.format_list_bulleted
      : _iconFromJson(_readSmartTypeForIcon(json, 'icon')),
  sortOption:
      $enumDecodeNullable(
        _$TaskSortOptionEnumMap,
        json['sortOption'],
        unknownValue: TaskSortOption.defaultOrder,
      ) ??
      TaskSortOption.defaultOrder,
  sortAscending: json['sortAscending'] as bool? ?? true,
  showCompleted: json['showCompleted'] as bool? ?? true,
  remoteId: json['remoteId'] as String?,
  orderDateTime: nullableUtcDateTimeFromJson(json['orderDateTime'] as String?),
  updatedAt: nullableUtcDateTimeFromJson(json['updatedAt'] as String?),
);

Map<String, dynamic> _$TodoListToJson(_TodoList instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'smartType': _$SmartListTypeEnumMap[instance.smartType],
  'groupId': instance.groupId,
  'emoji': instance.emoji,
  'themeColor': _$ListThemeColorEnumMap[instance.themeColor]!,
  'themePhoto': _$ListThemePhotoEnumMap[instance.themePhoto],
  'sortOption': _$TaskSortOptionEnumMap[instance.sortOption]!,
  'sortAscending': instance.sortAscending,
  'showCompleted': instance.showCompleted,
  'remoteId': instance.remoteId,
  'orderDateTime': nullableUtcDateTimeToJson(instance.orderDateTime),
  'updatedAt': nullableUtcDateTimeToJson(instance.updatedAt),
};

const _$SmartListTypeEnumMap = {
  SmartListType.myDay: 'myDay',
  SmartListType.important: 'important',
  SmartListType.planned: 'planned',
  SmartListType.all: 'all',
  SmartListType.completed: 'completed',
  SmartListType.tasks: 'tasks',
};

const _$ListThemeColorEnumMap = {
  ListThemeColor.blue: 'blue',
  ListThemeColor.rose: 'rose',
  ListThemeColor.teal: 'teal',
  ListThemeColor.green: 'green',
  ListThemeColor.purple: 'purple',
  ListThemeColor.red: 'red',
  ListThemeColor.grey: 'grey',
  ListThemeColor.lightBlue: 'lightBlue',
  ListThemeColor.lightRose: 'lightRose',
  ListThemeColor.lightTeal: 'lightTeal',
  ListThemeColor.lightGreen: 'lightGreen',
  ListThemeColor.lightPurple: 'lightPurple',
  ListThemeColor.lightRed: 'lightRed',
  ListThemeColor.lightGrey: 'lightGrey',
};

const _$ListThemePhotoEnumMap = {
  ListThemePhoto.beach: 'beach',
  ListThemePhoto.desert: 'desert',
  ListThemePhoto.fern: 'fern',
  ListThemePhoto.field: 'field',
  ListThemePhoto.gradient: 'gradient',
  ListThemePhoto.lighthouse: 'lighthouse',
  ListThemePhoto.safari: 'safari',
  ListThemePhoto.sea: 'sea',
  ListThemePhoto.tvTower: 'tvTower',
};

const _$TaskSortOptionEnumMap = {
  TaskSortOption.defaultOrder: 'defaultOrder',
  TaskSortOption.importance: 'importance',
  TaskSortOption.dueDate: 'dueDate',
  TaskSortOption.addedToMyDay: 'addedToMyDay',
  TaskSortOption.alphabetical: 'alphabetical',
  TaskSortOption.creationDate: 'creationDate',
};

_ListGroup _$ListGroupFromJson(Map<String, dynamic> json) => _ListGroup(
  id: json['id'] as String,
  title: json['title'] as String,
  isExpanded: json['isExpanded'] as bool? ?? true,
  remoteId: json['remoteId'] as String?,
  orderDateTime: nullableUtcDateTimeFromJson(json['orderDateTime'] as String?),
  updatedAt: nullableUtcDateTimeFromJson(json['updatedAt'] as String?),
);

Map<String, dynamic> _$ListGroupToJson(_ListGroup instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'isExpanded': instance.isExpanded,
      'remoteId': instance.remoteId,
      'orderDateTime': nullableUtcDateTimeToJson(instance.orderDateTime),
      'updatedAt': nullableUtcDateTimeToJson(instance.updatedAt),
    };
