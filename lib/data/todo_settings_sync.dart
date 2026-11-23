import 'package:material_ui/material_ui.dart';

import '../models/todo_list.dart';
import '../sync/todo_wire_codecs.dart';
import 'todo_settings_store.dart';
import 'todo_state.dart';

class SmartListSettingKeys {
  const SmartListSettingKeys({
    this.showCompletedKey,
    this.themeColorKey,
    this.sortTypeKey,
    this.sortAscKey,
  });

  final String? showCompletedKey;
  final String? themeColorKey;
  final String? sortTypeKey;
  final String? sortAscKey;
}

const Map<String, SmartListSettingKeys> smartListSettingKeyMap = {
  'my_day': SmartListSettingKeys(
    showCompletedKey: TodoSettingKeys.myDayShowCompletedTasks,
    themeColorKey: TodoSettingKeys.myDayThemeColor,
    sortTypeKey: TodoSettingKeys.myDaySortType,
    sortAscKey: TodoSettingKeys.myDaySortAscending,
  ),
  'important': SmartListSettingKeys(
    showCompletedKey: TodoSettingKeys.smartListStarredShowCompletedTasks,
    themeColorKey: TodoSettingKeys.smartListStarredThemeColor,
    sortTypeKey: TodoSettingKeys.smartListStarredSortType,
    sortAscKey: TodoSettingKeys.smartListStarredSortAscending,
  ),
  'planned': SmartListSettingKeys(
    showCompletedKey: TodoSettingKeys.plannedShowCompletedTasks,
    themeColorKey: TodoSettingKeys.plannedThemeColor,
  ),
  'all': SmartListSettingKeys(
    themeColorKey: TodoSettingKeys.smartListAllThemeColor,
    sortTypeKey: TodoSettingKeys.smartListAllSortType,
    sortAscKey: TodoSettingKeys.smartListAllSortAscending,
  ),
  'completed': SmartListSettingKeys(
    themeColorKey: TodoSettingKeys.smartListCompletedThemeColor,
    sortTypeKey: TodoSettingKeys.smartListCompletedSortType,
    sortAscKey: TodoSettingKeys.smartListCompletedSortAscending,
  ),
};

class SmartListSettingsPatch {
  const SmartListSettingsPatch({
    this.showCompleted,
    this.hasTheme = false,
    this.themeColor,
    this.themePhoto,
    this.clearThemePhoto = false,
    this.sortOption,
    this.sortAscending,
  });

  final bool? showCompleted;
  final bool hasTheme;
  final ListThemeColor? themeColor;
  final ListThemePhoto? themePhoto;
  final bool clearThemePhoto;
  final TaskSortOption? sortOption;
  final bool? sortAscending;

  SmartListSettingsPatch merge({
    bool? showCompleted,
    bool? hasTheme,
    ListThemeColor? themeColor,
    ListThemePhoto? themePhoto,
    bool? clearThemePhoto,
    TaskSortOption? sortOption,
    bool? sortAscending,
  }) {
    return SmartListSettingsPatch(
      showCompleted: showCompleted ?? this.showCompleted,
      hasTheme: (hasTheme ?? false) || this.hasTheme,
      themeColor: themeColor ?? this.themeColor,
      themePhoto: (clearThemePhoto ?? false)
          ? null
          : (themePhoto ?? this.themePhoto),
      clearThemePhoto: (clearThemePhoto ?? false) || this.clearThemePhoto,
      sortOption: sortOption ?? this.sortOption,
      sortAscending: sortAscending ?? this.sortAscending,
    );
  }
}

class SyncedSettingsPatch {
  const SyncedSettingsPatch({
    this.confirmBeforeDeleting,
    this.playCompletionSound,
    this.showDueTodayInMyDay,
    this.addNewTasksOnTop,
    this.moveStarredTasksToTop,
    this.startOfWeek,
    this.remindersEnabled,
    this.dueTodayNotificationsEnabled,
    this.dueTodayNotificationTime,
    this.pinReminders,
    this.routineNotificationEnabled,
    this.routineNotificationTime,
    this.showSmartListImportant,
    this.showSmartListPlanned,
    this.showSmartListAll,
    this.showSmartListCompleted,
    this.autoHideEmptySmartLists,
    this.plannedDueDateFilter,
    this.plannedGroupOption,
    this.smartListPatches = const {},
  });

  final bool? confirmBeforeDeleting;
  final bool? playCompletionSound;
  final bool? showDueTodayInMyDay;
  final bool? addNewTasksOnTop;
  final bool? moveStarredTasksToTop;
  final WeekStart? startOfWeek;
  final bool? remindersEnabled;
  final bool? dueTodayNotificationsEnabled;
  final TimeOfDay? dueTodayNotificationTime;
  final bool? pinReminders;
  final bool? routineNotificationEnabled;
  final TimeOfDay? routineNotificationTime;
  final bool? showSmartListImportant;
  final bool? showSmartListPlanned;
  final bool? showSmartListAll;
  final bool? showSmartListCompleted;
  final bool? autoHideEmptySmartLists;
  final PlannedDueDateFilter? plannedDueDateFilter;
  final PlannedGroupOption? plannedGroupOption;
  final Map<String, SmartListSettingsPatch> smartListPatches;
}

Set<String> smartListChangedSettingKeys(TodoList prev, TodoList next) {
  final mapping = smartListSettingKeyMap[next.id];
  if (mapping == null) return const {};
  final changed = <String>{};
  if (mapping.showCompletedKey != null &&
      prev.showCompleted != next.showCompleted) {
    changed.add(mapping.showCompletedKey!);
  }
  if (mapping.themeColorKey != null &&
      (prev.themeColor != next.themeColor ||
          prev.themePhoto != next.themePhoto)) {
    changed.add(mapping.themeColorKey!);
  }
  if (mapping.sortTypeKey != null && prev.sortOption != next.sortOption) {
    changed.add(mapping.sortTypeKey!);
  }
  if (mapping.sortAscKey != null && prev.sortAscending != next.sortAscending) {
    changed.add(mapping.sortAscKey!);
  }
  return changed;
}

Set<String> detectGlobalSettingChanges(TodoState prev, TodoState next) {
  final changed = <String>{};
  if (prev.confirmBeforeDeleting != next.confirmBeforeDeleting) {
    changed.add(TodoSettingKeys.confirmOnDelete);
  }
  if (prev.playCompletionSound != next.playCompletionSound) {
    changed.add(TodoSettingKeys.soundOnCompletion);
  }
  if (prev.showDueTodayInMyDay != next.showDueTodayInMyDay) {
    changed.add(TodoSettingKeys.myDayShowDueTasks);
  }
  if (prev.addNewTasksOnTop != next.addNewTasksOnTop) {
    changed.add(TodoSettingKeys.addTasksToTop);
  }
  if (prev.moveStarredTasksToTop != next.moveStarredTasksToTop) {
    changed.add(TodoSettingKeys.moveStarredTasksToTop);
  }
  if (prev.startOfWeek != next.startOfWeek) {
    changed.add(TodoSettingKeys.startWeekFrom);
  }
  if (prev.remindersEnabled != next.remindersEnabled) {
    changed.add(TodoSettingKeys.reminderNotifications);
  }
  if (prev.dueTodayNotificationsEnabled != next.dueTodayNotificationsEnabled) {
    changed.add(TodoSettingKeys.dueDateNotifications);
  }
  if (prev.dueTodayNotificationHour != next.dueTodayNotificationHour ||
      prev.dueTodayNotificationMinute != next.dueTodayNotificationMinute) {
    changed.add(TodoSettingKeys.dueDateNotificationTime);
  }
  if (prev.pinReminders != next.pinReminders) {
    changed.add(TodoSettingKeys.pinReminders);
  }
  if (prev.routineNotificationEnabled != next.routineNotificationEnabled) {
    changed.add(TodoSettingKeys.routineNotification);
  }
  if (prev.routineNotificationHour != next.routineNotificationHour ||
      prev.routineNotificationMinute != next.routineNotificationMinute) {
    changed.add(TodoSettingKeys.routineNotificationConfiguration);
  }
  if (prev.showSmartListImportant != next.showSmartListImportant) {
    changed.add(TodoSettingKeys.smartListStarredEnabled);
  }
  if (prev.showSmartListPlanned != next.showSmartListPlanned) {
    changed.add(TodoSettingKeys.smartListPlannedEnabled);
  }
  if (prev.showSmartListAll != next.showSmartListAll) {
    changed.add(TodoSettingKeys.smartListAllEnabled);
  }
  if (prev.showSmartListCompleted != next.showSmartListCompleted) {
    changed.add(TodoSettingKeys.smartListCompletedEnabled);
  }
  if (prev.autoHideEmptySmartLists != next.autoHideEmptySmartLists) {
    changed.add(TodoSettingKeys.smartListsAutoHide);
  }
  if (prev.plannedDueDateFilter != next.plannedDueDateFilter) {
    changed.add(TodoSettingKeys.smartListPlannedDueDateFilter);
  }
  if (prev.plannedGroupOption != next.plannedGroupOption) {
    changed.add(TodoSettingKeys.smartListPlannedGroupType);
  }
  return changed;
}

Future<({TodoState state, List<TodoList> lists})> applySyncedSettingsPatch({
  required TodoSettingsStore settings,
  required TodoState current,
  required TodoState? snapshot,
  required SyncedSettingsPatch patch,
  required List<TodoList> lists,
  required Set<String> dirtySettings,
}) async {
  bool canApplySetting(String key) {
    if (dirtySettings.contains(key)) return false;
    if (snapshot == null) return true;
    return extractSettingValueForKey(current, key) ==
        extractSettingValueForKey(snapshot, key);
  }

  var next = current;
  if (patch.confirmBeforeDeleting != null &&
      canApplySetting(TodoSettingKeys.confirmOnDelete)) {
    next = next.copyWith(confirmBeforeDeleting: patch.confirmBeforeDeleting!);
    await settings.saveConfirmBeforeDeleting(next.confirmBeforeDeleting);
  }
  if (patch.playCompletionSound != null &&
      canApplySetting(TodoSettingKeys.soundOnCompletion)) {
    next = next.copyWith(playCompletionSound: patch.playCompletionSound!);
    await settings.savePlayCompletionSound(next.playCompletionSound);
  }
  if (patch.showDueTodayInMyDay != null &&
      canApplySetting(TodoSettingKeys.myDayShowDueTasks)) {
    next = next.copyWith(showDueTodayInMyDay: patch.showDueTodayInMyDay!);
    await settings.saveShowDueTodayInMyDay(next.showDueTodayInMyDay);
  }
  if (patch.addNewTasksOnTop != null &&
      canApplySetting(TodoSettingKeys.addTasksToTop)) {
    next = next.copyWith(addNewTasksOnTop: patch.addNewTasksOnTop!);
    await settings.saveAddNewTasksOnTop(next.addNewTasksOnTop);
  }
  if (patch.moveStarredTasksToTop != null &&
      canApplySetting(TodoSettingKeys.moveStarredTasksToTop)) {
    next = next.copyWith(moveStarredTasksToTop: patch.moveStarredTasksToTop!);
    await settings.saveMoveStarredTasksToTop(next.moveStarredTasksToTop);
  }
  if (patch.startOfWeek != null &&
      canApplySetting(TodoSettingKeys.startWeekFrom)) {
    next = next.copyWith(startOfWeek: patch.startOfWeek!);
    await settings.saveStartOfWeek(next.startOfWeek);
  }
  if (patch.remindersEnabled != null &&
      canApplySetting(TodoSettingKeys.reminderNotifications)) {
    next = next.copyWith(remindersEnabled: patch.remindersEnabled!);
    await settings.saveRemindersEnabled(next.remindersEnabled);
  }
  if (patch.dueTodayNotificationsEnabled != null &&
      canApplySetting(TodoSettingKeys.dueDateNotifications)) {
    next = next.copyWith(
      dueTodayNotificationsEnabled: patch.dueTodayNotificationsEnabled!,
    );
    await settings.saveDueTodayNotificationsEnabled(
      next.dueTodayNotificationsEnabled,
    );
  }
  if (patch.dueTodayNotificationTime != null &&
      canApplySetting(TodoSettingKeys.dueDateNotificationTime)) {
    final t = patch.dueTodayNotificationTime!;
    next = next.copyWith(
      dueTodayNotificationHour: t.hour,
      dueTodayNotificationMinute: t.minute,
    );
    await settings.saveDueTodayNotificationTime(t.hour, t.minute);
  }
  if (patch.pinReminders != null &&
      canApplySetting(TodoSettingKeys.pinReminders)) {
    next = next.copyWith(pinReminders: patch.pinReminders!);
    await settings.savePinReminders(next.pinReminders);
  }
  if (patch.routineNotificationEnabled != null &&
      canApplySetting(TodoSettingKeys.routineNotification)) {
    next = next.copyWith(
      routineNotificationEnabled: patch.routineNotificationEnabled!,
    );
    await settings.saveRoutineNotificationEnabled(
      next.routineNotificationEnabled,
    );
  }
  if (patch.routineNotificationTime != null &&
      canApplySetting(TodoSettingKeys.routineNotificationConfiguration)) {
    final t = patch.routineNotificationTime!;
    next = next.copyWith(
      routineNotificationHour: t.hour,
      routineNotificationMinute: t.minute,
    );
    await settings.saveRoutineNotificationTime(t.hour, t.minute);
  }
  if (patch.showSmartListImportant != null &&
      canApplySetting(TodoSettingKeys.smartListStarredEnabled)) {
    next = next.copyWith(showSmartListImportant: patch.showSmartListImportant!);
    await settings.saveShowSmartListImportant(next.showSmartListImportant);
  }
  if (patch.showSmartListPlanned != null &&
      canApplySetting(TodoSettingKeys.smartListPlannedEnabled)) {
    next = next.copyWith(showSmartListPlanned: patch.showSmartListPlanned!);
    await settings.saveShowSmartListPlanned(next.showSmartListPlanned);
  }
  if (patch.showSmartListAll != null &&
      canApplySetting(TodoSettingKeys.smartListAllEnabled)) {
    next = next.copyWith(showSmartListAll: patch.showSmartListAll!);
    await settings.saveShowSmartListAll(next.showSmartListAll);
  }
  if (patch.showSmartListCompleted != null &&
      canApplySetting(TodoSettingKeys.smartListCompletedEnabled)) {
    next = next.copyWith(showSmartListCompleted: patch.showSmartListCompleted!);
    await settings.saveShowSmartListCompleted(next.showSmartListCompleted);
  }
  if (patch.autoHideEmptySmartLists != null &&
      canApplySetting(TodoSettingKeys.smartListsAutoHide)) {
    next = next.copyWith(
      autoHideEmptySmartLists: patch.autoHideEmptySmartLists!,
    );
    await settings.saveAutoHideEmptySmartLists(next.autoHideEmptySmartLists);
  }
  if (patch.plannedDueDateFilter != null &&
      canApplySetting(TodoSettingKeys.smartListPlannedDueDateFilter)) {
    next = next.copyWith(plannedDueDateFilter: patch.plannedDueDateFilter!);
    await settings.savePlannedDueDateFilter(next.plannedDueDateFilter);
  }
  if (patch.plannedGroupOption != null &&
      canApplySetting(TodoSettingKeys.smartListPlannedGroupType)) {
    next = next.copyWith(plannedGroupOption: patch.plannedGroupOption!);
    await settings.savePlannedGroupOption(next.plannedGroupOption);
  }

  if (patch.smartListPatches.isEmpty) {
    return (state: next, lists: lists);
  }

  final updatedLists = [
    for (final list in lists)
      _applySmartListPatch(
        list: list,
        patch: patch.smartListPatches[list.id],
        mapping: smartListSettingKeyMap[list.id],
        canApplySetting: canApplySetting,
      ),
  ];
  return (state: next, lists: updatedLists);
}

TodoList _applySmartListPatch({
  required TodoList list,
  required SmartListSettingsPatch? patch,
  required SmartListSettingKeys? mapping,
  required bool Function(String key) canApplySetting,
}) {
  if (patch == null || mapping == null) return list;
  var updated = list;
  if (patch.showCompleted != null &&
      mapping.showCompletedKey != null &&
      canApplySetting(mapping.showCompletedKey!)) {
    updated = updated.copyWith(showCompleted: patch.showCompleted!);
  }
  if (patch.hasTheme &&
      mapping.themeColorKey != null &&
      canApplySetting(mapping.themeColorKey!)) {
    updated = updated.copyWith(
      themeColor: patch.themeColor ?? updated.themeColor,
      themePhoto: patch.clearThemePhoto ? null : patch.themePhoto,
    );
  }
  if (patch.sortOption != null &&
      mapping.sortTypeKey != null &&
      canApplySetting(mapping.sortTypeKey!)) {
    updated = updated.copyWith(sortOption: patch.sortOption!);
  }
  if (patch.sortAscending != null &&
      mapping.sortAscKey != null &&
      canApplySetting(mapping.sortAscKey!)) {
    updated = updated.copyWith(sortAscending: patch.sortAscending!);
  }
  return updated;
}

/// Encodes local [state] field corresponding to Substrate setting [key].
String? extractSettingValueForKey(TodoState state, String key) {
  switch (key) {
    case TodoSettingKeys.confirmOnDelete:
      return encodeBoolSetting(state.confirmBeforeDeleting);
    case TodoSettingKeys.soundOnCompletion:
      return encodeBoolSetting(state.playCompletionSound);
    case TodoSettingKeys.myDayShowDueTasks:
      return encodeBoolSetting(state.showDueTodayInMyDay);
    case TodoSettingKeys.addTasksToTop:
      return encodeBoolSetting(state.addNewTasksOnTop);
    case TodoSettingKeys.moveStarredTasksToTop:
      return encodeBoolSetting(state.moveStarredTasksToTop);
    case TodoSettingKeys.startWeekFrom:
      return encodeIntSetting(encodeWeekStart(state.startOfWeek));
    case TodoSettingKeys.reminderNotifications:
      return encodeBoolSetting(state.remindersEnabled);
    case TodoSettingKeys.dueDateNotifications:
      return encodeBoolSetting(state.dueTodayNotificationsEnabled);
    case TodoSettingKeys.dueDateNotificationTime:
      return encodeTimeOfDaySetting(
        TimeOfDay(
          hour: state.dueTodayNotificationHour,
          minute: state.dueTodayNotificationMinute,
        ),
      );
    case TodoSettingKeys.pinReminders:
      return encodeBoolSetting(state.pinReminders);
    case TodoSettingKeys.routineNotification:
      return encodeRoutineNotificationEnabled(state.routineNotificationEnabled);
    case TodoSettingKeys.routineNotificationConfiguration:
      return encodeRoutineConfig(
        TimeOfDay(
          hour: state.routineNotificationHour,
          minute: state.routineNotificationMinute,
        ),
      );
    case TodoSettingKeys.smartListStarredEnabled:
      return encodeBoolSetting(state.showSmartListImportant);
    case TodoSettingKeys.smartListPlannedEnabled:
      return encodeBoolSetting(state.showSmartListPlanned);
    case TodoSettingKeys.smartListAllEnabled:
      return encodeBoolSetting(state.showSmartListAll);
    case TodoSettingKeys.smartListCompletedEnabled:
      return encodeBoolSetting(state.showSmartListCompleted);
    case TodoSettingKeys.smartListsAutoHide:
      return encodeBoolSetting(state.autoHideEmptySmartLists);
    case TodoSettingKeys.smartListPlannedDueDateFilter:
      return encodeIntSetting(
        encodePlannedDueDateFilter(state.plannedDueDateFilter),
      );
    case TodoSettingKeys.smartListPlannedGroupType:
      return encodeIntSetting(
        encodePlannedGroupOption(state.plannedGroupOption),
      );
  }

  for (final entry in smartListSettingKeyMap.entries) {
    final list = state.lists.where((l) => l.id == entry.key).firstOrNull;
    if (list == null) continue;
    final mapping = entry.value;
    if (key == mapping.showCompletedKey) {
      return encodeBoolSetting(list.showCompleted);
    }
    if (key == mapping.themeColorKey) {
      return encodeThemeColor(list.themeColor, list.themePhoto);
    }
    if (key == mapping.sortTypeKey) {
      return encodeIntSetting(encodeSortType(list.sortOption));
    }
    if (key == mapping.sortAscKey) {
      return encodeBoolSetting(list.sortAscending);
    }
  }
  return null;
}

/// Converts raw Substrate `GET settings` map into a [SyncedSettingsPatch].
SyncedSettingsPatch buildSyncedSettingsPatchFromWire(
  Map<String, String> remoteSettings, {
  Set<String> skipKeys = const {},
}) {
  String? getVal(String key) =>
      skipKeys.contains(key) ? null : remoteSettings[key];

  bool? boolOrNull(String key) {
    final raw = getVal(key);
    if (raw == null) return null;
    final lower = raw.trim().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'enabled') return true;
    if (lower == 'false' || lower == '0' || lower == 'disabled') return false;
    return null;
  }

  final smartPatches = <String, SmartListSettingsPatch>{};
  for (final entry in smartListSettingKeyMap.entries) {
    final listId = entry.key;
    final mapping = entry.value;
    var patch = const SmartListSettingsPatch();
    var touched = false;

    if (mapping.showCompletedKey != null) {
      final show = boolOrNull(mapping.showCompletedKey!);
      if (show != null) {
        patch = patch.merge(showCompleted: show);
        touched = true;
      }
    }
    if (mapping.themeColorKey != null) {
      final rawTheme = getVal(mapping.themeColorKey!);
      if (rawTheme != null && rawTheme.trim().isNotEmpty) {
        final decoded = decodeThemeColor(rawTheme);
        patch = patch.merge(
          hasTheme: true,
          themeColor: decoded.themeColor,
          themePhoto: decoded.themePhoto,
          clearThemePhoto: decoded.themePhoto == null,
        );
        touched = true;
      }
    }
    if (mapping.sortTypeKey != null) {
      final rawSort = getVal(mapping.sortTypeKey!);
      if (rawSort != null) {
        patch = patch.merge(sortOption: decodeSortType(rawSort));
        touched = true;
      }
    }
    if (mapping.sortAscKey != null) {
      final asc = boolOrNull(mapping.sortAscKey!);
      if (asc != null) {
        patch = patch.merge(sortAscending: asc);
        touched = true;
      }
    }

    if (touched) {
      smartPatches[listId] = patch;
    }
  }

  final rawWeek = getVal(TodoSettingKeys.startWeekFrom);
  final rawDueFilter = getVal(TodoSettingKeys.smartListPlannedDueDateFilter);
  final rawGroupType = getVal(TodoSettingKeys.smartListPlannedGroupType);
  final rawDueTime = getVal(TodoSettingKeys.dueDateNotificationTime);
  final rawRoutineConfig = getVal(
    TodoSettingKeys.routineNotificationConfiguration,
  );

  return SyncedSettingsPatch(
    confirmBeforeDeleting: boolOrNull(TodoSettingKeys.confirmOnDelete),
    playCompletionSound: boolOrNull(TodoSettingKeys.soundOnCompletion),
    showDueTodayInMyDay: boolOrNull(TodoSettingKeys.myDayShowDueTasks),
    addNewTasksOnTop: boolOrNull(TodoSettingKeys.addTasksToTop),
    moveStarredTasksToTop: boolOrNull(TodoSettingKeys.moveStarredTasksToTop),
    startOfWeek: rawWeek != null ? decodeWeekStart(rawWeek) : null,
    remindersEnabled: boolOrNull(TodoSettingKeys.reminderNotifications),
    dueTodayNotificationsEnabled: boolOrNull(
      TodoSettingKeys.dueDateNotifications,
    ),
    dueTodayNotificationTime: rawDueTime != null
        ? decodeTimeOfDaySetting(rawDueTime)
        : null,
    pinReminders: boolOrNull(TodoSettingKeys.pinReminders),
    routineNotificationEnabled: boolOrNull(TodoSettingKeys.routineNotification),
    routineNotificationTime: rawRoutineConfig != null
        ? decodeRoutineConfigTime(rawRoutineConfig)
        : null,
    showSmartListImportant: boolOrNull(TodoSettingKeys.smartListStarredEnabled),
    showSmartListPlanned: boolOrNull(TodoSettingKeys.smartListPlannedEnabled),
    showSmartListAll: boolOrNull(TodoSettingKeys.smartListAllEnabled),
    showSmartListCompleted: boolOrNull(
      TodoSettingKeys.smartListCompletedEnabled,
    ),
    autoHideEmptySmartLists: boolOrNull(TodoSettingKeys.smartListsAutoHide),
    plannedDueDateFilter: rawDueFilter != null
        ? decodePlannedDueDateFilter(rawDueFilter)
        : null,
    plannedGroupOption: rawGroupType != null
        ? decodePlannedGroupOption(rawGroupType)
        : null,
    smartListPatches: smartPatches,
  );
}
