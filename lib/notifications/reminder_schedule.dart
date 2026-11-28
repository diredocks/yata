import 'package:timezone/timezone.dart' as tz;

import '../core/time/time_zone_database.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';

int notificationIdForTask(String taskId) {
  // Deterministic positive 31-bit ID >= 100000 to avoid colliding with fixed IDs.
  var hash = 0;
  for (var i = 0; i < taskId.length; i++) {
    hash = (hash * 31 + taskId.codeUnitAt(i)) & 0x3FFFFFFF;
  }
  return 100000 + hash;
}

tz.Location resolveLocalLocation(Duration utcOffset) {
  for (final loc in timeZoneDatabase.locations.values) {
    if (loc.currentTimeZone.offset == utcOffset) return loc;
  }
  return tz.UTC;
}

DateTime nextDailyOccurrence(int hour, int minute, DateTime now) {
  var candidate = DateTime(now.year, now.month, now.day, hour, minute);
  if (!candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 1));
  }
  return candidate;
}

DateTime nextWeeklyOccurrence(int weekday, int hour, int minute, DateTime now) {
  final daysUntil = (weekday - now.weekday + 7) % 7;
  var candidate = DateTime(
    now.year,
    now.month,
    now.day,
    hour,
    minute,
  ).add(Duration(days: daysUntil));
  if (!candidate.isAfter(now)) {
    candidate = candidate.add(const Duration(days: 7));
  }
  return candidate;
}

String resolveListName(
  TaskItem task,
  List<TodoList> lists,
  String defaultTasksName,
) {
  if (task.listId == 'tasks') return defaultTasksName;
  for (final list in lists) {
    if (list.id == task.listId) return list.title;
  }
  return defaultTasksName;
}
