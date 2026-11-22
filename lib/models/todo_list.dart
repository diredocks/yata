import 'package:material_ui/material_ui.dart';

enum SmartListType {
  myDay,
  important,
  planned,
  all,
  completed,
  tasks,
}

enum WeekStart {
  system,
  sunday,
  monday,
  saturday,
}

enum ListThemeColor {
  blue,
  rose,
  teal,
  green,
  purple,
  red,
  grey,
  lightBlue,
  lightRose,
  lightTeal,
  lightGreen,
  lightPurple,
  lightRed,
  lightGrey,
}

enum ListThemePhoto {
  beach,
  desert,
  fern,
  field,
  gradient,
  lighthouse,
  safari,
  sea,
  tvTower,
}

enum TaskSortOption {
  defaultOrder,
  importance,
  dueDate,
  addedToMyDay,
  alphabetical,
  creationDate,
}

extension TaskSortOptionDefaults on TaskSortOption {
  bool get defaultAscending {
    return switch (this) {
      TaskSortOption.defaultOrder => false,
      TaskSortOption.importance => false,
      TaskSortOption.dueDate => true,
      TaskSortOption.addedToMyDay => false,
      TaskSortOption.alphabetical => true,
      TaskSortOption.creationDate => false,
    };
  }
}

enum PlannedDueDateFilter {
  overdue,
  today,
  tomorrow,
  thisWeek,
  later,
  all,
}

enum PlannedGroupOption {
  ungroup,
  byDueDate,
  byList,
}

@immutable
class TodoList {
  const TodoList({
    required this.id,
    required this.title,
    this.smartType,
    this.groupId,
    this.emoji,
    this.themeColor = ListThemeColor.blue,
    this.themePhoto,
    this.icon = Icons.format_list_bulleted,
    this.sortOption = TaskSortOption.defaultOrder,
    this.sortAscending = true,
    this.showCompleted = true,
    this.remoteId,
    this.orderDateTime,
    this.updatedAt,
  });

  final String id;
  final String title;
  final SmartListType? smartType;
  final String? groupId;
  final String? emoji;
  final ListThemeColor themeColor;
  final ListThemePhoto? themePhoto;
  final IconData icon;
  final TaskSortOption sortOption;
  final bool sortAscending;
  final bool showCompleted;
  final String? remoteId;
  final DateTime? orderDateTime;
  final DateTime? updatedAt;

  bool get isSmartList => smartType != null;

  TodoList copyWith({
    String? id,
    String? title,
    SmartListType? smartType,
    String? groupId,
    bool clearGroupId = false,
    String? emoji,
    bool clearEmoji = false,
    ListThemeColor? themeColor,
    ListThemePhoto? themePhoto,
    bool clearThemePhoto = false,
    IconData? icon,
    TaskSortOption? sortOption,
    bool? sortAscending,
    bool? showCompleted,
    String? remoteId,
    bool clearRemoteId = false,
    DateTime? orderDateTime,
    bool clearOrderDateTime = false,
    DateTime? updatedAt,
  }) {
    return TodoList(
      id: id ?? this.id,
      title: title ?? this.title,
      smartType: smartType ?? this.smartType,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      emoji: clearEmoji ? null : (emoji ?? this.emoji),
      themeColor: themeColor ?? this.themeColor,
      themePhoto: clearThemePhoto ? null : (themePhoto ?? this.themePhoto),
      icon: icon ?? this.icon,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
      showCompleted: showCompleted ?? this.showCompleted,
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      orderDateTime:
          clearOrderDateTime ? null : (orderDateTime ?? this.orderDateTime),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static IconData iconForSmartType(SmartListType? type) {
    return switch (type) {
      SmartListType.myDay => Icons.wb_sunny_outlined,
      SmartListType.important => Icons.star_outline,
      SmartListType.planned => Icons.calendar_today_outlined,
      SmartListType.all => Icons.all_inclusive,
      SmartListType.completed => Icons.check_circle_outline,
      SmartListType.tasks => Icons.home_outlined,
      null => Icons.format_list_bulleted,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'smartType': smartType?.name,
      'groupId': groupId,
      'emoji': emoji,
      'themeColor': themeColor.name,
      'themePhoto': themePhoto?.name,
      'sortOption': sortOption.name,
      'sortAscending': sortAscending,
      'showCompleted': showCompleted,
      'remoteId': remoteId,
      'orderDateTime': orderDateTime?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory TodoList.fromJson(Map<String, dynamic> json) {
    final smartName = json['smartType'] as String?;
    final smartType = smartName == null
        ? null
        : SmartListType.values.where((e) => e.name == smartName).firstOrNull;
    final colorName = json['themeColor'] as String? ?? 'blue';
    final themeColor = ListThemeColor.values.firstWhere(
      (e) => e.name == colorName,
      orElse: () => ListThemeColor.blue,
    );
    final photoName = json['themePhoto'] as String?;
    final themePhoto = photoName == null
        ? null
        : ListThemePhoto.values.where((e) => e.name == photoName).firstOrNull;
    final sortName = json['sortOption'] as String? ?? 'defaultOrder';
    final sortOption = TaskSortOption.values.firstWhere(
      (e) => e.name == sortName,
      orElse: () => TaskSortOption.defaultOrder,
    );

    return TodoList(
      id: json['id'] as String,
      title: json['title'] as String,
      smartType: smartType,
      groupId: json['groupId'] as String?,
      emoji: json['emoji'] as String?,
      themeColor: themeColor,
      themePhoto: themePhoto,
      icon: iconForSmartType(smartType),
      sortOption: sortOption,
      sortAscending: json['sortAscending'] as bool? ?? true,
      showCompleted: json['showCompleted'] as bool? ?? true,
      remoteId: json['remoteId'] as String?,
      orderDateTime: json['orderDateTime'] != null
          ? DateTime.parse(json['orderDateTime'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}

@immutable
class ListGroup {
  const ListGroup({
    required this.id,
    required this.title,
    this.isExpanded = true,
    this.remoteId,
    this.orderDateTime,
    this.updatedAt,
  });

  final String id;
  final String title;
  final bool isExpanded;
  final String? remoteId;
  final DateTime? orderDateTime;
  final DateTime? updatedAt;

  ListGroup copyWith({
    String? id,
    String? title,
    bool? isExpanded,
    String? remoteId,
    bool clearRemoteId = false,
    DateTime? orderDateTime,
    bool clearOrderDateTime = false,
    DateTime? updatedAt,
  }) {
    return ListGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      isExpanded: isExpanded ?? this.isExpanded,
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      orderDateTime:
          clearOrderDateTime ? null : (orderDateTime ?? this.orderDateTime),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isExpanded': isExpanded,
      'remoteId': remoteId,
      'orderDateTime': orderDateTime?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory ListGroup.fromJson(Map<String, dynamic> json) {
    return ListGroup(
      id: json['id'] as String,
      title: json['title'] as String,
      isExpanded: json['isExpanded'] as bool? ?? true,
      remoteId: json['remoteId'] as String?,
      orderDateTime: json['orderDateTime'] != null
          ? DateTime.parse(json['orderDateTime'] as String)
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}
