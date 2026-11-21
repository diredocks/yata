import 'package:flutter/foundation.dart';

enum RecurrenceType {
  none,
  daily,
  weekdays,
  weekly,
  monthly,
  yearly,
}

@immutable
class TaskStep {
  const TaskStep({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  final String id;
  final String title;
  final bool isCompleted;

  TaskStep copyWith({
    String? id,
    String? title,
    bool? isCompleted,
  }) {
    return TaskStep(
      id: id ?? this.id,
      title: title ?? this.title,
      isCompleted: isCompleted ?? this.isCompleted,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isCompleted': isCompleted,
    };
  }

  factory TaskStep.fromJson(Map<String, dynamic> json) {
    return TaskStep(
      id: json['id'] as String,
      title: json['title'] as String,
      isCompleted: json['isCompleted'] as bool? ?? false,
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
    this.dueDate,
    this.reminderAt,
    this.recurrence = RecurrenceType.none,
    this.note = '',
    this.steps = const [],
  });

  final String id;
  final String listId;
  final String title;
  final DateTime createdAt;
  final bool isCompleted;
  final bool isImportant;
  final bool isInMyDay;
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final RecurrenceType recurrence;
  final String note;
  final List<TaskStep> steps;

  int get completedStepsCount =>
      steps.where((step) => step.isCompleted).length;

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
    DateTime? dueDate,
    bool clearDueDate = false,
    DateTime? reminderAt,
    bool clearReminderAt = false,
    RecurrenceType? recurrence,
    String? note,
    List<TaskStep>? steps,
  }) {
    return TaskItem(
      id: id ?? this.id,
      listId: listId ?? this.listId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      isCompleted: isCompleted ?? this.isCompleted,
      isImportant: isImportant ?? this.isImportant,
      isInMyDay: isInMyDay ?? this.isInMyDay,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      reminderAt: clearReminderAt ? null : (reminderAt ?? this.reminderAt),
      recurrence: recurrence ?? this.recurrence,
      note: note ?? this.note,
      steps: steps ?? this.steps,
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
      'dueDate': dueDate?.toIso8601String(),
      'reminderAt': reminderAt?.toIso8601String(),
      'recurrence': recurrence.name,
      'note': note,
      'steps': steps.map((s) => s.toJson()).toList(),
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
      dueDate: json['dueDate'] != null
          ? DateTime.parse(json['dueDate'] as String)
          : null,
      reminderAt: json['reminderAt'] != null
          ? DateTime.parse(json['reminderAt'] as String)
          : null,
      recurrence: recurrence,
      note: json['note'] as String? ?? '',
      steps: rawSteps
          .map((e) => TaskStep.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
