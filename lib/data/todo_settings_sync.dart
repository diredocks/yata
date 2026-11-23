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

class RoutineNotificationConfig {
  const RoutineNotificationConfig({required this.time, required this.days});

  final TimeOfDay time;
  final List<int> days;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! RoutineNotificationConfig) return false;
    if (time != other.time || days.length != other.days.length) return false;
    for (var i = 0; i < days.length; i++) {
      if (days[i] != other.days[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(time, Object.hashAll(days));
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
    this.accurateReminders,
    this.routineNotificationEnabled,
    this.routineNotificationConfig,
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
  final bool? accurateReminders;
  final bool? routineNotificationEnabled;
  final RoutineNotificationConfig? routineNotificationConfig;
  final bool? showSmartListImportant;
  final bool? showSmartListPlanned;
  final bool? showSmartListAll;
  final bool? showSmartListCompleted;
  final bool? autoHideEmptySmartLists;
  final PlannedDueDateFilter? plannedDueDateFilter;
  final PlannedGroupOption? plannedGroupOption;
  final Map<String, SmartListSettingsPatch> smartListPatches;
}

class _GlobalSettingSpec<T> {
  const _GlobalSettingSpec({
    required this.key,
    required this.readState,
    required this.readPatch,
    required this.encode,
    required this.applyToState,
    required this.persist,
  });

  final String key;
  final T Function(TodoState state) readState;
  final T? Function(SyncedSettingsPatch patch) readPatch;
  final String Function(T value) encode;
  final TodoState Function(TodoState state, T value) applyToState;
  final Future<void> Function(TodoSettingsStore store, T value) persist;

  bool hasChanged(TodoState prev, TodoState next) =>
      readState(prev) != readState(next);

  String encodeState(TodoState state) => encode(readState(state));

  Future<TodoState> applyIfPresent({
    required TodoState state,
    required SyncedSettingsPatch patch,
    required TodoSettingsStore settings,
    required bool Function(String key) canApply,
  }) async {
    final value = readPatch(patch);
    if (value == null || !canApply(key)) return state;
    final next = applyToState(state, value);
    await persist(settings, value);
    return next;
  }
}

final List<_GlobalSettingSpec<Object?>> _globalSettingSpecs = [
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.confirmOnDelete,
    readState: (s) => s.confirmBeforeDeleting,
    readPatch: (p) => p.confirmBeforeDeleting,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(confirmBeforeDeleting: v),
    persist: (store, v) => store.saveConfirmBeforeDeleting(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.soundOnCompletion,
    readState: (s) => s.playCompletionSound,
    readPatch: (p) => p.playCompletionSound,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(playCompletionSound: v),
    persist: (store, v) => store.savePlayCompletionSound(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.myDayShowDueTasks,
    readState: (s) => s.showDueTodayInMyDay,
    readPatch: (p) => p.showDueTodayInMyDay,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showDueTodayInMyDay: v),
    persist: (store, v) => store.saveShowDueTodayInMyDay(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.addTasksToTop,
    readState: (s) => s.addNewTasksOnTop,
    readPatch: (p) => p.addNewTasksOnTop,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(addNewTasksOnTop: v),
    persist: (store, v) => store.saveAddNewTasksOnTop(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.moveStarredTasksToTop,
    readState: (s) => s.moveStarredTasksToTop,
    readPatch: (p) => p.moveStarredTasksToTop,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(moveStarredTasksToTop: v),
    persist: (store, v) => store.saveMoveStarredTasksToTop(v),
  ),
  _GlobalSettingSpec<WeekStart>(
    key: TodoSettingKeys.startWeekFrom,
    readState: (s) => s.startOfWeek,
    readPatch: (p) => p.startOfWeek,
    encode: (v) => encodeIntSetting(encodeWeekStart(v)),
    applyToState: (s, v) => s.copyWith(startOfWeek: v),
    persist: (store, v) => store.saveStartOfWeek(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.reminderNotifications,
    readState: (s) => s.remindersEnabled,
    readPatch: (p) => p.remindersEnabled,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(remindersEnabled: v),
    persist: (store, v) => store.saveRemindersEnabled(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.dueDateNotifications,
    readState: (s) => s.dueTodayNotificationsEnabled,
    readPatch: (p) => p.dueTodayNotificationsEnabled,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(dueTodayNotificationsEnabled: v),
    persist: (store, v) => store.saveDueTodayNotificationsEnabled(v),
  ),
  _GlobalSettingSpec<TimeOfDay>(
    key: TodoSettingKeys.dueDateNotificationTime,
    readState: (s) => TimeOfDay(
      hour: s.dueTodayNotificationHour,
      minute: s.dueTodayNotificationMinute,
    ),
    readPatch: (p) => p.dueTodayNotificationTime,
    encode: encodeTimeOfDaySetting,
    applyToState: (s, v) => s.copyWith(
      dueTodayNotificationHour: v.hour,
      dueTodayNotificationMinute: v.minute,
    ),
    persist: (store, v) => store.saveDueTodayNotificationTime(v.hour, v.minute),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.pinReminders,
    readState: (s) => s.pinReminders,
    readPatch: (p) => p.pinReminders,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(pinReminders: v),
    persist: (store, v) => store.savePinReminders(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.setAlarmClockReminderAndroid,
    readState: (s) => s.accurateReminders,
    readPatch: (p) => p.accurateReminders,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(accurateReminders: v),
    persist: (store, v) => store.saveAccurateReminders(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.routineNotification,
    readState: (s) => s.routineNotificationEnabled,
    readPatch: (p) => p.routineNotificationEnabled,
    encode: encodeRoutineNotificationEnabled,
    applyToState: (s, v) => s.copyWith(routineNotificationEnabled: v),
    persist: (store, v) => store.saveRoutineNotificationEnabled(v),
  ),
  _GlobalSettingSpec<RoutineNotificationConfig>(
    key: TodoSettingKeys.routineNotificationConfiguration,
    readState: (s) => RoutineNotificationConfig(
      time: TimeOfDay(
        hour: s.routineNotificationHour,
        minute: s.routineNotificationMinute,
      ),
      days: s.routineNotificationDays,
    ),
    readPatch: (p) => p.routineNotificationConfig,
    encode: (v) => encodeRoutineConfig(v.time, days: v.days),
    applyToState: (s, v) => s.copyWith(
      routineNotificationHour: v.time.hour,
      routineNotificationMinute: v.time.minute,
      routineNotificationDays: v.days,
    ),
    persist: (store, v) async {
      await store.saveRoutineNotificationTime(v.time.hour, v.time.minute);
      await store.saveRoutineNotificationDays(v.days);
    },
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListStarredEnabled,
    readState: (s) => s.showSmartListImportant,
    readPatch: (p) => p.showSmartListImportant,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListImportant: v),
    persist: (store, v) => store.saveShowSmartListImportant(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListPlannedEnabled,
    readState: (s) => s.showSmartListPlanned,
    readPatch: (p) => p.showSmartListPlanned,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListPlanned: v),
    persist: (store, v) => store.saveShowSmartListPlanned(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListAllEnabled,
    readState: (s) => s.showSmartListAll,
    readPatch: (p) => p.showSmartListAll,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListAll: v),
    persist: (store, v) => store.saveShowSmartListAll(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListCompletedEnabled,
    readState: (s) => s.showSmartListCompleted,
    readPatch: (p) => p.showSmartListCompleted,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListCompleted: v),
    persist: (store, v) => store.saveShowSmartListCompleted(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListsAutoHide,
    readState: (s) => s.autoHideEmptySmartLists,
    readPatch: (p) => p.autoHideEmptySmartLists,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(autoHideEmptySmartLists: v),
    persist: (store, v) => store.saveAutoHideEmptySmartLists(v),
  ),
  _GlobalSettingSpec<PlannedDueDateFilter>(
    key: TodoSettingKeys.smartListPlannedDueDateFilter,
    readState: (s) => s.plannedDueDateFilter,
    readPatch: (p) => p.plannedDueDateFilter,
    encode: (v) => encodeIntSetting(encodePlannedDueDateFilter(v)),
    applyToState: (s, v) => s.copyWith(plannedDueDateFilter: v),
    persist: (store, v) => store.savePlannedDueDateFilter(v),
  ),
  _GlobalSettingSpec<PlannedGroupOption>(
    key: TodoSettingKeys.smartListPlannedGroupType,
    readState: (s) => s.plannedGroupOption,
    readPatch: (p) => p.plannedGroupOption,
    encode: (v) => encodeIntSetting(encodePlannedGroupOption(v)),
    applyToState: (s, v) => s.copyWith(plannedGroupOption: v),
    persist: (store, v) => store.savePlannedGroupOption(v),
  ),
];

final Map<String, _GlobalSettingSpec<Object?>> _globalSpecByKey = {
  for (final spec in _globalSettingSpecs) spec.key: spec,
};

Set<String> smartListChangedSettingKeys(TodoList prev, TodoList next) {
  final mapping = smartListSettingKeyMap[next.id];
  if (mapping == null) return const {};
  return {
    if (mapping.showCompletedKey != null &&
        prev.showCompleted != next.showCompleted)
      mapping.showCompletedKey!,
    if (mapping.themeColorKey != null &&
        (prev.themeColor != next.themeColor ||
            prev.themePhoto != next.themePhoto))
      mapping.themeColorKey!,
    if (mapping.sortTypeKey != null && prev.sortOption != next.sortOption)
      mapping.sortTypeKey!,
    if (mapping.sortAscKey != null && prev.sortAscending != next.sortAscending)
      mapping.sortAscKey!,
  };
}

Set<String> detectGlobalSettingChanges(TodoState prev, TodoState next) => {
  for (final spec in _globalSettingSpecs)
    if (spec.hasChanged(prev, next)) spec.key,
};

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
  for (final spec in _globalSettingSpecs) {
    next = await spec.applyIfPresent(
      state: next,
      patch: patch,
      settings: settings,
      canApply: canApplySetting,
    );
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
  final globalSpec = _globalSpecByKey[key];
  if (globalSpec != null) {
    return globalSpec.encodeState(state);
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

  T? mapVal<T>(String key, T? Function(String raw) decode) {
    final raw = getVal(key);
    return raw == null ? null : decode(raw);
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

  return SyncedSettingsPatch(
    confirmBeforeDeleting: boolOrNull(TodoSettingKeys.confirmOnDelete),
    playCompletionSound: boolOrNull(TodoSettingKeys.soundOnCompletion),
    showDueTodayInMyDay: boolOrNull(TodoSettingKeys.myDayShowDueTasks),
    addNewTasksOnTop: boolOrNull(TodoSettingKeys.addTasksToTop),
    moveStarredTasksToTop: boolOrNull(TodoSettingKeys.moveStarredTasksToTop),
    startOfWeek: mapVal(TodoSettingKeys.startWeekFrom, decodeWeekStart),
    remindersEnabled: boolOrNull(TodoSettingKeys.reminderNotifications),
    dueTodayNotificationsEnabled: boolOrNull(
      TodoSettingKeys.dueDateNotifications,
    ),
    dueTodayNotificationTime: mapVal(
      TodoSettingKeys.dueDateNotificationTime,
      decodeTimeOfDaySetting,
    ),
    pinReminders: boolOrNull(TodoSettingKeys.pinReminders),
    accurateReminders: boolOrNull(TodoSettingKeys.setAlarmClockReminderAndroid),
    routineNotificationEnabled: boolOrNull(TodoSettingKeys.routineNotification),
    routineNotificationConfig: mapVal(
      TodoSettingKeys.routineNotificationConfiguration,
      (raw) {
        final time = decodeRoutineConfigTime(raw);
        if (time == null) return null;
        final days = decodeRoutineConfigDays(raw);
        return RoutineNotificationConfig(
          time: time,
          days: (days == null || days.isEmpty)
              ? const [1, 2, 3, 4, 5, 6, 7]
              : days,
        );
      },
    ),
    showSmartListImportant: boolOrNull(TodoSettingKeys.smartListStarredEnabled),
    showSmartListPlanned: boolOrNull(TodoSettingKeys.smartListPlannedEnabled),
    showSmartListAll: boolOrNull(TodoSettingKeys.smartListAllEnabled),
    showSmartListCompleted: boolOrNull(
      TodoSettingKeys.smartListCompletedEnabled,
    ),
    autoHideEmptySmartLists: boolOrNull(TodoSettingKeys.smartListsAutoHide),
    plannedDueDateFilter: mapVal(
      TodoSettingKeys.smartListPlannedDueDateFilter,
      decodePlannedDueDateFilter,
    ),
    plannedGroupOption: mapVal(
      TodoSettingKeys.smartListPlannedGroupType,
      decodePlannedGroupOption,
    ),
    smartListPatches: smartPatches,
  );
}
