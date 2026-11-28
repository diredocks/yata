import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/todo_list.dart';
import '../../sync/microsoft/todo_wire_codecs.dart';
import 'todo_settings_store.dart';
import '../state/todo_state.dart';

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

class RoutineNotificationConfig {
  const RoutineNotificationConfig({required this.time, required this.days});

  final TimeOfDay time;
  final List<int> days;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutineNotificationConfig &&
          time == other.time &&
          const ListEquality<int>().equals(days, other.days));

  @override
  int get hashCode => Object.hash(time, const ListEquality<int>().hash(days));
}

RoutineNotificationConfig? _decodeRoutineConfig(String raw) {
  final time = decodeRoutineConfigTime(raw);
  if (time == null) return null;
  final days = decodeRoutineConfigDays(raw);
  return RoutineNotificationConfig(
    time: time,
    days: (days == null || days.isEmpty) ? const [1, 2, 3, 4, 5, 6, 7] : days,
  );
}

class _GlobalSettingSpec<T> {
  const _GlobalSettingSpec({
    required this.key,
    required this.readState,
    required this.decode,
    required this.encode,
    required this.applyToState,
    required this.persist,
  });

  final String key;
  final T Function(TodoState state) readState;
  final T? Function(String raw) decode;
  final String Function(T value) encode;
  final TodoState Function(TodoState state, T value) applyToState;
  final Future<void> Function(TodoSettingsStore store, T value) persist;

  bool hasChanged(TodoState prev, TodoState next) =>
      readState(prev) != readState(next);

  String encodeState(TodoState state) => encode(readState(state));

  TodoState applyWire({
    required TodoState state,
    required String? raw,
    required TodoSettingsStore settings,
    required List<Future<void>> persistFutures,
  }) {
    if (raw == null) return state;
    final value = decode(raw);
    if (value == null) return state;
    persistFutures.add(persist(settings, value));
    return applyToState(state, value);
  }
}

final List<_GlobalSettingSpec<Object?>> _globalSettingSpecs = [
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.confirmOnDelete,
    readState: (s) => s.confirmBeforeDeleting,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(confirmBeforeDeleting: v),
    persist: (store, v) => store.saveConfirmBeforeDeleting(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.soundOnCompletion,
    readState: (s) => s.playCompletionSound,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(playCompletionSound: v),
    persist: (store, v) => store.savePlayCompletionSound(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.myDayShowDueTasks,
    readState: (s) => s.showDueTodayInMyDay,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showDueTodayInMyDay: v),
    persist: (store, v) => store.saveShowDueTodayInMyDay(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.addTasksToTop,
    readState: (s) => s.addNewTasksOnTop,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(addNewTasksOnTop: v),
    persist: (store, v) => store.saveAddNewTasksOnTop(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.moveStarredTasksToTop,
    readState: (s) => s.moveStarredTasksToTop,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(moveStarredTasksToTop: v),
    persist: (store, v) => store.saveMoveStarredTasksToTop(v),
  ),
  _GlobalSettingSpec<WeekStart>(
    key: TodoSettingKeys.startWeekFrom,
    readState: (s) => s.startOfWeek,
    decode: decodeWeekStart,
    encode: (v) => encodeIntSetting(encodeWeekStart(v)),
    applyToState: (s, v) => s.copyWith(startOfWeek: v),
    persist: (store, v) => store.saveStartOfWeek(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.reminderNotifications,
    readState: (s) => s.remindersEnabled,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(remindersEnabled: v),
    persist: (store, v) => store.saveRemindersEnabled(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.dueDateNotifications,
    readState: (s) => s.dueTodayNotificationsEnabled,
    decode: parseWireBoolOrNull,
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
    decode: decodeTimeOfDaySetting,
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
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(pinReminders: v),
    persist: (store, v) => store.savePinReminders(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.setAlarmClockReminderAndroid,
    readState: (s) => s.accurateReminders,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(accurateReminders: v),
    persist: (store, v) => store.saveAccurateReminders(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.routineNotification,
    readState: (s) => s.routineNotificationEnabled,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
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
    decode: _decodeRoutineConfig,
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
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListImportant: v),
    persist: (store, v) => store.saveShowSmartListImportant(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListPlannedEnabled,
    readState: (s) => s.showSmartListPlanned,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListPlanned: v),
    persist: (store, v) => store.saveShowSmartListPlanned(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListAllEnabled,
    readState: (s) => s.showSmartListAll,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListAll: v),
    persist: (store, v) => store.saveShowSmartListAll(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListCompletedEnabled,
    readState: (s) => s.showSmartListCompleted,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(showSmartListCompleted: v),
    persist: (store, v) => store.saveShowSmartListCompleted(v),
  ),
  _GlobalSettingSpec<bool>(
    key: TodoSettingKeys.smartListsAutoHide,
    readState: (s) => s.autoHideEmptySmartLists,
    decode: parseWireBoolOrNull,
    encode: encodeBoolSetting,
    applyToState: (s, v) => s.copyWith(autoHideEmptySmartLists: v),
    persist: (store, v) => store.saveAutoHideEmptySmartLists(v),
  ),
  _GlobalSettingSpec<PlannedDueDateFilter>(
    key: TodoSettingKeys.smartListPlannedDueDateFilter,
    readState: (s) => s.plannedDueDateFilter,
    decode: decodePlannedDueDateFilter,
    encode: (v) => encodeIntSetting(encodePlannedDueDateFilter(v)),
    applyToState: (s, v) => s.copyWith(plannedDueDateFilter: v),
    persist: (store, v) => store.savePlannedDueDateFilter(v),
  ),
  _GlobalSettingSpec<PlannedGroupOption>(
    key: TodoSettingKeys.smartListPlannedGroupType,
    readState: (s) => s.plannedGroupOption,
    decode: decodePlannedGroupOption,
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

/// Decodes and applies raw Substrate `/settings` wire key/value entries
/// directly into [current] and [lists], skipping any locally dirty keys.
({
  TodoState state,
  List<TodoList> lists,
  List<Future<void>> persistFutures,
  Set<String> updatedShowCompletedSmartListIds,
})
applyRemoteSettingsWire({
  required TodoSettingsStore settings,
  required TodoState current,
  required Map<String, String> remoteSettings,
  required List<TodoList> lists,
  required Set<String> dirtySettings,
}) {
  String? wireVal(String? key) =>
      (key == null || dirtySettings.contains(key)) ? null : remoteSettings[key];

  final persistFutures = <Future<void>>[];
  var next = current;
  for (final spec in _globalSettingSpecs) {
    next = spec.applyWire(
      state: next,
      raw: wireVal(spec.key),
      settings: settings,
      persistFutures: persistFutures,
    );
  }

  final updatedShowCompletedSmartListIds = <String>{};
  var anyListChanged = false;
  final updatedLists = <TodoList>[];
  for (final list in lists) {
    final mapping = smartListSettingKeyMap[list.id];
    if (mapping == null) {
      updatedLists.add(list);
      continue;
    }
    var updated = list;
    final showRaw = wireVal(mapping.showCompletedKey);
    if (showRaw != null) {
      final show = parseWireBoolOrNull(showRaw);
      if (show != null) {
        updatedShowCompletedSmartListIds.add(list.id);
        updated = updated.copyWith(showCompleted: show);
      }
    }
    final themeRaw = wireVal(mapping.themeColorKey);
    if (themeRaw != null && themeRaw.trim().isNotEmpty) {
      final decoded = decodeThemeColor(
        themeRaw,
        fallbackColor: updated.themeColor,
      );
      final themeChanged =
          decoded.themeColor != updated.themeColor ||
          decoded.themePhoto != updated.themePhoto;
      updated = updated.copyWith(
        themeColor: decoded.themeColor,
        themePhoto: decoded.themePhoto,
        customBackgroundPath: themeChanged
            ? null
            : updated.customBackgroundPath,
      );
    }
    final sortRaw = wireVal(mapping.sortTypeKey);
    if (sortRaw != null) {
      updated = updated.copyWith(sortOption: decodeSortType(sortRaw));
    }
    final ascRaw = wireVal(mapping.sortAscKey);
    if (ascRaw != null) {
      final asc = parseWireBoolOrNull(ascRaw);
      if (asc != null) {
        updated = updated.copyWith(sortAscending: asc);
      }
    }
    anyListChanged |= !identical(updated, list);
    updatedLists.add(updated);
  }

  return (
    state: next,
    lists: anyListChanged ? updatedLists : lists,
    persistFutures: persistFutures,
    updatedShowCompletedSmartListIds: updatedShowCompletedSmartListIds,
  );
}

/// Encodes local [state] field corresponding to Substrate setting [key].
String? extractSettingValueForKey(TodoState state, String key) {
  final globalSpec = _globalSpecByKey[key];
  if (globalSpec != null) {
    return globalSpec.encodeState(state);
  }

  for (final entry in smartListSettingKeyMap.entries) {
    final list = state.lists.firstWhereOrNull((l) => l.id == entry.key);
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

bool isSyncableFolderList(TodoList list) =>
    !list.isSmartList || list.smartType == SmartListType.tasks;

/// Recomputes per-list completed-section expansion from synced folder and smart-list settings.
({Map<String, bool> expanded, bool changed}) recomputeCompletedExpandedByList({
  required Map<String, bool> currentExpanded,
  required List<TodoList> lists,
  Set<String> dirtyListIds = const {},
  Set<String> updatedShowCompletedSmartListIds = const {},
  bool includeSyncableFolders = true,
}) {
  final nextExpanded = Map<String, bool>.from(currentExpanded);
  var changed = false;
  for (final list in lists) {
    if (list.smartType == SmartListType.all ||
        list.smartType == SmartListType.completed ||
        list.smartType == SmartListType.important) {
      continue;
    }
    if (isSyncableFolderList(list)) {
      if (includeSyncableFolders &&
          list.remoteId != null &&
          !dirtyListIds.contains(list.id) &&
          nextExpanded[list.id] != list.showCompleted) {
        nextExpanded[list.id] = list.showCompleted;
        changed = true;
      }
    } else if (updatedShowCompletedSmartListIds.contains(list.id) &&
        nextExpanded[list.id] != list.showCompleted) {
      nextExpanded[list.id] = list.showCompleted;
      changed = true;
    }
  }
  return (expanded: nextExpanded, changed: changed);
}
