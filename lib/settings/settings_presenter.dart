import 'dart:collection';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/state/todo_provider.dart';
import '../models/todo_list.dart';

/// Presenter for `settings/SettingsActivity`.
class SettingsPresenter {
  SettingsPresenter(this._ref);

  final Ref _ref;

  TodoNotifier get _store => _ref.read(todoProvider.notifier);
  TodoState get _state => _ref.read(todoProvider);

  void setThemeMode(ThemeMode mode) {
    _store.mutateSetting(
      _state.copyWith(themeMode: mode),
      persistLocal: () => _store.settings.saveThemeMode(mode),
    );
  }

  void setUseDynamicColor(bool value) {
    _store.mutateSetting(
      _state.copyWith(useDynamicColor: value),
      persistLocal: () => _store.settings.saveUseDynamicColor(value),
    );
  }

  void setAddNewTasksOnTop(bool value) {
    _store.mutateSetting(
      _state.copyWith(addNewTasksOnTop: value),
      persistLocal: () => _store.settings.saveAddNewTasksOnTop(value),
    );
  }

  void setMoveStarredTasksToTop(bool value) {
    _store.mutateSetting(
      _state.copyWith(moveStarredTasksToTop: value),
      persistLocal: () => _store.settings.saveMoveStarredTasksToTop(value),
    );
  }

  void setPlayCompletionSound(bool value) {
    _store.mutateSetting(
      _state.copyWith(playCompletionSound: value),
      persistLocal: () => _store.settings.savePlayCompletionSound(value),
    );
  }

  void setConfirmBeforeDeleting(bool value) {
    _store.mutateSetting(
      _state.copyWith(confirmBeforeDeleting: value),
      persistLocal: () => _store.settings.saveConfirmBeforeDeleting(value),
    );
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
    _store.mutateSetting(
      _state.copyWith(showDueTodayInMyDay: value),
      derivedTasks: changed ? updatedTasks : null,
      persistLocal: () => _store.settings.saveShowDueTodayInMyDay(value),
    );
  }

  void setStartOfWeek(WeekStart value) {
    _store.mutateSetting(
      _state.copyWith(startOfWeek: value),
      persistLocal: () => _store.settings.saveStartOfWeek(value),
    );
  }

  void setShowSmartListImportant(bool value) {
    _store.mutateSetting(
      _state.copyWith(showSmartListImportant: value),
      persistLocal: () => _store.settings.saveShowSmartListImportant(value),
    );
  }

  void setShowSmartListPlanned(bool value) {
    _store.mutateSetting(
      _state.copyWith(showSmartListPlanned: value),
      persistLocal: () => _store.settings.saveShowSmartListPlanned(value),
    );
  }

  void setShowSmartListAll(bool value) {
    _store.mutateSetting(
      _state.copyWith(showSmartListAll: value),
      persistLocal: () => _store.settings.saveShowSmartListAll(value),
    );
  }

  void setShowSmartListCompleted(bool value) {
    _store.mutateSetting(
      _state.copyWith(showSmartListCompleted: value),
      persistLocal: () => _store.settings.saveShowSmartListCompleted(value),
    );
  }

  void setAutoHideEmptySmartLists(bool value) {
    _store.mutateSetting(
      _state.copyWith(autoHideEmptySmartLists: value),
      persistLocal: () => _store.settings.saveAutoHideEmptySmartLists(value),
    );
  }

  void setRemindersEnabled(bool value) {
    _store.mutateSetting(
      _state.copyWith(remindersEnabled: value),
      persistLocal: () => _store.settings.saveRemindersEnabled(value),
    );
  }

  void setPinReminders(bool value) {
    _store.mutateSetting(
      _state.copyWith(pinReminders: value),
      persistLocal: () => _store.settings.savePinReminders(value),
    );
  }

  void setAccurateReminders(bool value) {
    _store.mutateSetting(
      _state.copyWith(accurateReminders: value),
      persistLocal: () => _store.settings.saveAccurateReminders(value),
    );
  }

  void setDueTodayNotificationsEnabled(bool value) {
    _store.mutateSetting(
      _state.copyWith(dueTodayNotificationsEnabled: value),
      persistLocal: () =>
          _store.settings.saveDueTodayNotificationsEnabled(value),
    );
  }

  void setDueTodayNotificationTime(int hour, int minute) {
    _store.mutateSetting(
      _state.copyWith(
        dueTodayNotificationHour: hour,
        dueTodayNotificationMinute: minute,
      ),
      persistLocal: () =>
          _store.settings.saveDueTodayNotificationTime(hour, minute),
    );
  }

  void setRoutineNotificationEnabled(bool value) {
    _store.mutateSetting(
      _state.copyWith(routineNotificationEnabled: value),
      persistLocal: () => _store.settings.saveRoutineNotificationEnabled(value),
    );
  }

  void setRoutineNotificationTime(int hour, int minute) {
    _store.mutateSetting(
      _state.copyWith(
        routineNotificationHour: hour,
        routineNotificationMinute: minute,
      ),
      persistLocal: () =>
          _store.settings.saveRoutineNotificationTime(hour, minute),
    );
  }

  void setRoutineNotificationDays(List<int> days) {
    final sorted = SplayTreeSet<int>.of(days).toList();
    _store.mutateSetting(
      _state.copyWith(routineNotificationDays: sorted),
      persistLocal: () => _store.settings.saveRoutineNotificationDays(sorted),
    );
  }

  void setQuickAddNotificationEnabled(bool value) {
    _store.mutateSetting(
      _state.copyWith(quickAddNotificationEnabled: value),
      persistLocal: () =>
          _store.settings.saveQuickAddNotificationEnabled(value),
    );
  }
}

final settingsPresenterProvider = Provider<SettingsPresenter>((ref) {
  return SettingsPresenter(ref);
});
