import 'dart:collection';

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
    _store.settings.saveThemeMode(mode);
  }

  void setUseDynamicColor(bool value) {
    _store.commit(_state.copyWith(useDynamicColor: value));
    _store.settings.saveUseDynamicColor(value);
  }

  void setAddNewTasksOnTop(bool value) {
    _store.commit(_state.copyWith(addNewTasksOnTop: value));
    _store.settings.saveAddNewTasksOnTop(value);
  }

  void setMoveStarredTasksToTop(bool value) {
    _store.commit(_state.copyWith(moveStarredTasksToTop: value));
    _store.settings.saveMoveStarredTasksToTop(value);
  }

  void setPlayCompletionSound(bool value) {
    _store.commit(_state.copyWith(playCompletionSound: value));
    _store.settings.savePlayCompletionSound(value);
  }

  void setConfirmBeforeDeleting(bool value) {
    _store.commit(_state.copyWith(confirmBeforeDeleting: value));
    _store.settings.saveConfirmBeforeDeleting(value);
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
      _store.repository.saveTasks(updatedTasks);
    }
    _store.settings.saveShowDueTodayInMyDay(value);
  }

  void setStartOfWeek(WeekStart value) {
    _store.commit(_state.copyWith(startOfWeek: value));
    _store.settings.saveStartOfWeek(value);
  }

  void setShowSmartListImportant(bool value) {
    _store.commit(_state.copyWith(showSmartListImportant: value));
    _store.settings.saveShowSmartListImportant(value);
  }

  void setShowSmartListPlanned(bool value) {
    _store.commit(_state.copyWith(showSmartListPlanned: value));
    _store.settings.saveShowSmartListPlanned(value);
  }

  void setShowSmartListAll(bool value) {
    _store.commit(_state.copyWith(showSmartListAll: value));
    _store.settings.saveShowSmartListAll(value);
  }

  void setShowSmartListCompleted(bool value) {
    _store.commit(_state.copyWith(showSmartListCompleted: value));
    _store.settings.saveShowSmartListCompleted(value);
  }

  void setAutoHideEmptySmartLists(bool value) {
    _store.commit(_state.copyWith(autoHideEmptySmartLists: value));
    _store.settings.saveAutoHideEmptySmartLists(value);
  }

  void setRemindersEnabled(bool value) {
    _store.commit(_state.copyWith(remindersEnabled: value));
    _store.settings.saveRemindersEnabled(value);
  }

  void setPinReminders(bool value) {
    _store.commit(_state.copyWith(pinReminders: value));
    _store.settings.savePinReminders(value);
  }

  void setAccurateReminders(bool value) {
    _store.commit(_state.copyWith(accurateReminders: value));
    _store.settings.saveAccurateReminders(value);
  }

  void setDueTodayNotificationsEnabled(bool value) {
    _store.commit(_state.copyWith(dueTodayNotificationsEnabled: value));
    _store.settings.saveDueTodayNotificationsEnabled(value);
  }

  void setDueTodayNotificationTime(int hour, int minute) {
    _store.commit(
      _state.copyWith(
        dueTodayNotificationHour: hour,
        dueTodayNotificationMinute: minute,
      ),
    );
    _store.settings.saveDueTodayNotificationTime(hour, minute);
  }

  void setRoutineNotificationEnabled(bool value) {
    _store.commit(_state.copyWith(routineNotificationEnabled: value));
    _store.settings.saveRoutineNotificationEnabled(value);
  }

  void setRoutineNotificationTime(int hour, int minute) {
    _store.commit(
      _state.copyWith(
        routineNotificationHour: hour,
        routineNotificationMinute: minute,
      ),
    );
    _store.settings.saveRoutineNotificationTime(hour, minute);
  }

  void setRoutineNotificationDays(List<int> days) {
    final sorted = SplayTreeSet<int>.of(days).toList();
    _store.commit(_state.copyWith(routineNotificationDays: sorted));
    _store.settings.saveRoutineNotificationDays(sorted);
  }

  void setQuickAddNotificationEnabled(bool value) {
    _store.commit(_state.copyWith(quickAddNotificationEnabled: value));
    _store.settings.saveQuickAddNotificationEnabled(value);
  }
}

final settingsPresenterProvider = Provider<SettingsPresenter>((ref) {
  return SettingsPresenter(ref);
});
