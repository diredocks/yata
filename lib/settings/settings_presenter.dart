import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../models/todo_list.dart';
import '../data/todo_provider.dart';

/// Presenter for `settings/SettingsActivity`.
class SettingsPresenter {
  SettingsPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void setThemeMode(ThemeMode mode) {
    _store.commit(_state.copyWith(themeMode: mode));
    _store.storage.saveThemeMode(mode);
  }

  void toggleShowCompleted(bool value) {
    _store.commit(_state.copyWith(showCompleted: value));
    _store.storage.saveShowCompleted(value);
  }

  void setAddNewTasksOnTop(bool value) {
    _store.commit(_state.copyWith(addNewTasksOnTop: value));
    _store.storage.saveAddNewTasksOnTop(value);
  }

  void setMoveStarredTasksToTop(bool value) {
    _store.commit(_state.copyWith(moveStarredTasksToTop: value));
    _store.storage.saveMoveStarredTasksToTop(value);
  }

  void setPlayCompletionSound(bool value) {
    _store.commit(_state.copyWith(playCompletionSound: value));
    _store.storage.savePlayCompletionSound(value);
  }

  void setConfirmBeforeDeleting(bool value) {
    _store.commit(_state.copyWith(confirmBeforeDeleting: value));
    _store.storage.saveConfirmBeforeDeleting(value);
  }

  void setShowDueTodayInMyDay(bool value) {
    final now = DateTime.now();
    var changed = false;
    final updatedTasks = [
      for (final task in _state.tasks)
        () {
          final synced = TodoNotifier.syncMyDayFlag(
            task,
            now: now,
            showDueTodayInMyDay: value,
          );
          if (!identical(synced, task)) {
            changed = true;
          }
          return synced;
        }(),
    ];
    _store.commit(
      _state.copyWith(
        showDueTodayInMyDay: value,
        tasks: changed ? updatedTasks : _state.tasks,
      ),
    );
    if (changed) {
      _store.storage.saveTasks(updatedTasks);
    }
    _store.storage.saveShowDueTodayInMyDay(value);
  }

  void setStartOfWeek(WeekStart value) {
    _store.commit(_state.copyWith(startOfWeek: value));
    _store.storage.saveStartOfWeek(value);
  }

  void setShowSmartListImportant(bool value) {
    _store.commit(_state.copyWith(showSmartListImportant: value));
    _store.storage.saveShowSmartListImportant(value);
  }

  void setShowSmartListPlanned(bool value) {
    _store.commit(_state.copyWith(showSmartListPlanned: value));
    _store.storage.saveShowSmartListPlanned(value);
  }

  void setShowSmartListAll(bool value) {
    _store.commit(_state.copyWith(showSmartListAll: value));
    _store.storage.saveShowSmartListAll(value);
  }

  void setShowSmartListCompleted(bool value) {
    _store.commit(_state.copyWith(showSmartListCompleted: value));
    _store.storage.saveShowSmartListCompleted(value);
  }

  void setAutoHideEmptySmartLists(bool value) {
    _store.commit(_state.copyWith(autoHideEmptySmartLists: value));
    _store.storage.saveAutoHideEmptySmartLists(value);
  }

  void setRemindersEnabled(bool value) {
    _store.commit(_state.copyWith(remindersEnabled: value));
    _store.storage.saveRemindersEnabled(value);
  }

  void setPinReminders(bool value) {
    _store.commit(_state.copyWith(pinReminders: value));
    _store.storage.savePinReminders(value);
  }

  void setDueTodayNotificationsEnabled(bool value) {
    _store.commit(_state.copyWith(dueTodayNotificationsEnabled: value));
    _store.storage.saveDueTodayNotificationsEnabled(value);
  }

  void setDueTodayNotificationTime(int hour, int minute) {
    _store.commit(
      _state.copyWith(
        dueTodayNotificationHour: hour,
        dueTodayNotificationMinute: minute,
      ),
    );
    _store.storage.saveDueTodayNotificationTime(hour, minute);
  }

  void setRoutineNotificationEnabled(bool value) {
    _store.commit(_state.copyWith(routineNotificationEnabled: value));
    _store.storage.saveRoutineNotificationEnabled(value);
  }

  void setRoutineNotificationTime(int hour, int minute) {
    _store.commit(
      _state.copyWith(
        routineNotificationHour: hour,
        routineNotificationMinute: minute,
      ),
    );
    _store.storage.saveRoutineNotificationTime(hour, minute);
  }

  void setQuickAddNotificationEnabled(bool value) {
    _store.commit(_state.copyWith(quickAddNotificationEnabled: value));
    _store.storage.saveQuickAddNotificationEnabled(value);
  }
}

final settingsPresenterProvider = Provider<SettingsPresenter>((ref) {
  return SettingsPresenter(ref);
});
