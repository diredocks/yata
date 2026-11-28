import '../../core/utils.dart';
import '../../models/task_item.dart';
import 'my_day.dart';

/// Updates [task]'s due date, clearing recurrence if removed and updating My Day.
TaskItem applyDueDate(
  TaskItem task,
  DateTime? dueDate, {
  required DateTime now,
  required bool showDueTodayInMyDay,
}) {
  final clearPostponed =
      dueDate != null &&
      showDueTodayInMyDay &&
      task.postponedDay != null &&
      isSameCalendarDay(dueDate, task.postponedDay!);
  return syncMyDayFlag(
    task.copyWith(
      dueDate: dueDate,
      recurrence: dueDate == null ? RecurrenceType.none : task.recurrence,
      rawRecurrence: dueDate == null ? null : task.rawRecurrence,
      postponedDay: clearPostponed ? null : task.postponedDay,
    ),
    now: now,
    showDueTodayInMyDay: showDueTodayInMyDay,
  );
}
