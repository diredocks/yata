import 'package:flutter/foundation.dart';

enum RecurrenceType { none, daily, weekdays, weekly, monthly, yearly }

@immutable
class TaskStep {
  const TaskStep({
    required this.id,
    required this.title,
    this.isCompleted = false,
    this.remoteId,
    this.orderDateTime,
  });

  final String id;
  final String title;
  final bool isCompleted;
  final String? remoteId;
  final DateTime? orderDateTime;

  TaskStep copyWith({
    String? id,
    String? title,
    bool? isCompleted,
    String? remoteId,
    bool clearRemoteId = false,
    DateTime? orderDateTime,
    bool clearOrderDateTime = false,
  }) {
    return TaskStep(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      orderDateTime: clearOrderDateTime
          ? null
          : (orderDateTime ?? this.orderDateTime),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
      'remoteId': remoteId,
      'orderDateTime': orderDateTime?.toIso8601String(),
    };
  }

  factory TaskStep.fromJson(Map<String, dynamic> json) {
    return TaskStep(
      id: json['id'] as String,
      title: json['title'] as String,
      isCompleted: json['isCompleted'] as bool? ?? false,
      remoteId: json['remoteId'] as String?,
      orderDateTime: json['orderDateTime'] != null
          ? DateTime.parse(json['orderDateTime'] as String)
          : null,
    );
  }
}

@immutable
class TaskItem {
  const TaskItem({
    required this.id,
    required this.listId,
    required this.title,
    required this.createdAt,
    this.isCompleted = false,
    this.isImportant = false,
    this.isInMyDay = false,
    this.myDayDate,
    this.postponedDay,
    this.dueDate,
    this.reminderAt,
    this.recurrence = RecurrenceType.none,
    this.note = '',
    this.noteUpdatedAt,
    this.completedAt,
    this.steps = const [],
    this.remoteId,
    this.remoteParentFolderId,
    this.orderDateTime,
    this.committedOrder,
    this.changeKey,
    this.updatedAt,
  });

  final String id;
  final String listId;
  final String title;
  final DateTime createdAt;
  final bool isCompleted;
  final bool isImportant;
  final bool isInMyDay;
  final DateTime? myDayDate;
  final DateTime? postponedDay;
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final RecurrenceType recurrence;
  final String note;
  final DateTime? noteUpdatedAt;
  final DateTime? completedAt;
  final List<TaskStep> steps;
  final String? remoteId;
  final String? remoteParentFolderId;
  final DateTime? orderDateTime;
  final DateTime? committedOrder;
  final String? changeKey;
  final DateTime? updatedAt;

  int get completedStepsCount => steps.where((step) => step.isCompleted).length;

  bool get isOverdue {
    if (dueDate == null || isCompleted) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(dueDate!.year, dueDate!.month, dueDate!.day);
    return due.isBefore(today);
  }

  TaskItem copyWith({
    String? id,
    String? listId,
    String? title,
    DateTime? createdAt,
    bool? isCompleted,
    bool? isImportant,
    bool? isInMyDay,
    DateTime? myDayDate,
    bool clearMyDayDate = false,
    DateTime? postponedDay,
    bool clearPostponedDay = false,
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    RecurrenceType? recurrence,
    String? note,
    DateTime? noteUpdatedAt,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    List<TaskStep>? steps,
    String? remoteId,
    bool clearRemoteId = false,
    String? remoteParentFolderId,
    bool clearRemoteParentFolderId = false,
    DateTime? orderDateTime,
    bool clearOrderDateTime = false,
    DateTime? committedOrder,
    bool clearCommittedOrder = false,
    String? changeKey,
    bool clearChangeKey = false,
    DateTime? updatedAt,
  }) {
    return TaskItem(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
      isImportant: isImportant ?? this.isImportant,
      isInMyDay: isInMyDay ?? this.isInMyDay,
      myDayDate: clearMyDayDate ? null : (myDayDate ?? this.myDayDate),
      postponedDay: clearPostponedDay
          ? null
          : (postponedDay ?? this.postponedDay),
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
      recurrence: recurrence ?? this.recurrence,
      note: note ?? this.note,
      noteUpdatedAt: noteUpdatedAt ?? this.noteUpdatedAt,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      steps: steps ?? this.steps,
      remoteId: clearRemoteId ? null : (remoteId ?? this.remoteId),
      remoteParentFolderId: clearRemoteParentFolderId
          ? null
          : (remoteParentFolderId ?? this.remoteParentFolderId),
      orderDateTime: clearOrderDateTime
          ? null
          : (orderDateTime ?? this.orderDateTime),
      committedOrder: clearCommittedOrder
          ? null
          : (committedOrder ?? this.committedOrder),
      changeKey: clearChangeKey ? null : (changeKey ?? this.changeKey),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'listId': listId,
      'title': title,
      'createdAt': createdAt.toIso8601String(),
      'isCompleted': isCompleted,
      'isImportant': isImportant,
      'isInMyDay': isInMyDay,
      'myDayDate': myDayDate?.toIso8601String(),
      'postponedDay': postponedDay?.toIso8601String(),
      'dueDate': dueDate?.toIso8601String(),
      'reminderAt': reminderAt?.toIso8601String(),
      'recurrence': recurrence.name,
      'note': note,
      'noteUpdatedAt': noteUpdatedAt?.toIso8601String(),
      'completedAt': completedAt?.toIso8601String(),
      'steps': steps.map((s) => s.toJson()).toList(),
      'remoteId': remoteId,
      'remoteParentFolderId': remoteParentFolderId,
      'orderDateTime': orderDateTime?.toIso8601String(),
      'committedOrder': committedOrder?.toIso8601String(),
      'changeKey': changeKey,
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }

  factory TaskItem.fromJson(Map<String, dynamic> json) {
    final recurrenceName = json['recurrence'] as String? ?? 'none';
    final recurrence = RecurrenceType.values.firstWhere(
      (e) => e.name == recurrenceName,
      orElse: () => RecurrenceType.none,
    );
    final rawSteps = json['steps'] as List<dynamic>? ?? const [];

    return TaskItem(
      id: json['id'] as String,
      listId: json['listId'] as String,
      title: json['title'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isCompleted: json['isCompleted'] as bool? ?? false,
      isImportant: json['isImportant'] as bool? ?? false,
      isInMyDay: json['isInMyDay'] as bool? ?? false,
      myDayDate: json['myDayDate'] != null
          ? DateTime.parse(json['myDayDate'] as String)
          : null,
      postponedDay: json['postponedDay'] != null
          ? DateTime.parse(json['postponedDay'] as String)
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      reminderAt: json['reminderAt'] != null
          ? DateTime.parse(json['reminderAt'] as String)
          : null,
      recurrence: recurrence,
      note: json['note'] as String? ?? '',
      noteUpdatedAt: json['noteUpdatedAt'] != null
          ? DateTime.parse(json['noteUpdatedAt'] as String)
          : null,
      completedAt: json['completedAt'] != null
          ? DateTime.parse(json['completedAt'] as String)
          : null,
      steps: rawSteps
          .map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
          .toList(),
      remoteId: json['remoteId'] as String?,
      remoteParentFolderId: json['remoteParentFolderId'] as String?,
      orderDateTime: json['orderDateTime'] != null
          ? DateTime.parse(json['orderDateTime'] as String)
          : null,
      committedOrder: json['committedOrder'] != null
          ? DateTime.parse(json['committedOrder'] as String)
          : null,
      changeKey: json['changeKey'] as String?,
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
    );
  }
}
