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

enum TaskSortOption {
  defaultOrder,
  importance,
  dueDate,
  alphabetical,
}

@immutable
class TodoList {
  const TodoList({
    required this.id,
    required this.title,
    this.smartType,
    this.groupId,
    this.themeColor = ListThemeColor.blue,
    this.icon = Icons.format_list_bulleted,
  });

  final String id;
  final String title;
  final SmartListType? smartType;
  final String? groupId;
  final ListThemeColor themeColor;
  final IconData icon;

  bool get isSmartList => smartType != null;

  TodoList copyWith({
    String? id,
    String? title,
    SmartListType? smartType,
    String? groupId,
    bool clearGroupId = false,
    ListThemeColor? themeColor,
    IconData? icon,
  }) {
    return TodoList(
      id: id ?? this.id,
      title: title ?? this.title,
      smartType: smartType ?? this.smartType,
      groupId: clearGroupId ? null : (groupId ?? this.groupId),
      themeColor: themeColor ?? this.themeColor,
      icon: icon ?? this.icon,
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
      'themeColor': themeColor.name,
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

    return TodoList(
      id: json['id'] as String,
      title: json['title'] as String,
      smartType: smartType,
      groupId: json['groupId'] as String?,
      themeColor: themeColor,
      icon: iconForSmartType(smartType),
    );
  }
}

@immutable
class ListGroup {
  const ListGroup({
    required this.id,
    required this.title,
    this.isExpanded = true,
  });

  final String id;
  final String title;
  final bool isExpanded;

  ListGroup copyWith({
    String? id,
    String? title,
    bool? isExpanded,
  }) {
    return ListGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isExpanded': isExpanded,
    };
  }

  factory ListGroup.fromJson(Map<String, dynamic> json) {
    return ListGroup(
      id: json['id'] as String,
      title: json['title'] as String,
      isExpanded: json['isExpanded'] as bool? ?? true,
    );
  }
}
