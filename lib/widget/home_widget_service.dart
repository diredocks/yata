import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_local_storage.dart';
import '../account/account_provider.dart';
import '../core/logging/app_logger.dart';
import '../data/todo_provider.dart';
import '../data/todo_repository.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../sync/sync_provider.dart';
import '../tasksview/tasks_view_presenter.dart';
import '../theme/todo_theme.dart';

/// Key in [SharedPreferences] recording the last time the widget background
/// callback mutated the database, so the foreground app can reload on resume.
const String kWidgetLastMutationMsKey = 'yata.widget_last_mutation_ms';

const String kAndroidWidgetProviderName =
    'top.clickfling.yata.widget.TodoWidgetProvider';

enum HomeWidgetActionType {
  quickAdd,
  openList,
  openTask,
  toggleComplete,
  toggleImportant,
  refresh,
}

class HomeWidgetAction {
  const HomeWidgetAction({
    required this.type,
    this.listId,
    this.taskId,
    this.flagValue,
  });

  final HomeWidgetActionType type;
  final String? listId;
  final String? taskId;
  final bool? flagValue;

  static HomeWidgetAction? fromUri(Uri? uri) {
    if (uri == null || uri.scheme != 'yata' || uri.host != 'widget') {
      return null;
    }
    final path = uri.path;
    final params = uri.queryParameters;
    return switch (path) {
      '/add' => HomeWidgetAction(
        type: HomeWidgetActionType.quickAdd,
        listId: params['listId'],
      ),
      '/open_list' => HomeWidgetAction(
        type: HomeWidgetActionType.openList,
        listId: params['listId'],
      ),
      '/open_task' => HomeWidgetAction(
        type: HomeWidgetActionType.openTask,
        taskId: params['taskId'],
        listId: params['listId'],
      ),
      '/toggle_complete' => HomeWidgetAction(
        type: HomeWidgetActionType.toggleComplete,
        taskId: params['taskId'],
        flagValue: _parseBool(params['completed']),
      ),
      '/toggle_important' => HomeWidgetAction(
        type: HomeWidgetActionType.toggleImportant,
        taskId: params['taskId'],
        flagValue: _parseBool(params['important']),
      ),
      '/refresh' => const HomeWidgetAction(type: HomeWidgetActionType.refresh),
      _ => null,
    };
  }

  static bool? _parseBool(String? raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return null;
  }
}

class HomeWidgetStrings {
  const HomeWidgetStrings({
    this.myDay = 'My Day',
    this.important = 'Important',
    this.planned = 'Planned',
    this.all = 'All',
    this.completedList = 'Completed',
    this.tasks = 'Tasks',
    this.today = 'Today',
    this.tomorrow = 'Tomorrow',
    this.yesterday = 'Yesterday',
    this.emptyListMessage = 'No tasks in this list',
  });

  factory HomeWidgetStrings.fromLocalizations(AppLocalizations l10n) {
    return HomeWidgetStrings(
      myDay: l10n.myDay,
      important: l10n.important,
      planned: l10n.planned,
      all: l10n.all,
      completedList: l10n.completedList,
      tasks: l10n.tasks,
      today: l10n.today,
      tomorrow: l10n.tomorrow,
      yesterday: l10n.createdYesterday,
      emptyListMessage: l10n.emptyListTitle,
    );
  }

  final String myDay;
  final String important;
  final String planned;
  final String all;
  final String completedList;
  final String tasks;
  final String today;
  final String tomorrow;
  final String yesterday;
  final String emptyListMessage;

  String titleForList(TodoList list) {
    return switch (list.smartType) {
      SmartListType.myDay => myDay,
      SmartListType.important => important,
      SmartListType.planned => planned,
      SmartListType.all => all,
      SmartListType.completed => completedList,
      SmartListType.tasks => tasks,
      null => list.title,
    };
  }
}

abstract class HomeWidgetTransport {
  Future<void> saveWidgetData(String id, Object? data);
  Future<void> updateWidget({String? qualifiedAndroidName});
  Future<Uri?> initiallyLaunchedFromHomeWidget();
  Stream<Uri?> get widgetClicked;
}

class FlutterHomeWidgetTransport implements HomeWidgetTransport {
  const FlutterHomeWidgetTransport();

  bool get _isSupportedPlatform {
    if (kIsWeb) return false;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    return Platform.isAndroid || Platform.isIOS;
  }

  Future<T?> _guardPlatform<T>(Future<T?> Function() action) async {
    if (!_isSupportedPlatform) return null;
    try {
      return await action();
    } on MissingPluginException catch (e) {
      appLog('plugin unavailable: $e', label: 'HomeWidgetTransport');
      return null;
    } on PlatformException catch (e) {
      appLog('platform error: $e', label: 'HomeWidgetTransport');
      return null;
    }
  }

  @override
  Future<void> saveWidgetData(String id, Object? data) async {
    await _guardPlatform(() => HomeWidget.saveWidgetData<Object?>(id, data));
  }

  @override
  Future<void> updateWidget({String? qualifiedAndroidName}) async {
    await _guardPlatform(
      () => HomeWidget.updateWidget(qualifiedAndroidName: qualifiedAndroidName),
    );
  }

  @override
  Future<Uri?> initiallyLaunchedFromHomeWidget() async {
    return await _guardPlatform(HomeWidget.initiallyLaunchedFromHomeWidget);
  }

  @override
  Stream<Uri?> get widgetClicked {
    if (!_isSupportedPlatform) return const Stream<Uri?>.empty();
    return HomeWidget.widgetClicked;
  }
}

final homeWidgetServiceProvider = Provider<HomeWidgetService>((ref) {
  return HomeWidgetService(const FlutterHomeWidgetTransport());
});

class HomeWidgetService {
  HomeWidgetService(this._transport);

  final HomeWidgetTransport _transport;
  HomeWidgetStrings _lastStrings = const HomeWidgetStrings();
  String? _lastAccountName;

  Stream<Uri?> get widgetClicked => _transport.widgetClicked;

  Future<Uri?> initiallyLaunchedFromHomeWidget() =>
      _transport.initiallyLaunchedFromHomeWidget();

  Future<void> syncWithState(
    TodoState state, {
    String? accountName,
    HomeWidgetStrings? strings,
  }) async {
    if (strings != null) {
      _lastStrings = strings;
    }
    if (accountName != null) {
      _lastAccountName = accountName;
    }
    final activeStrings = strings ?? _lastStrings;
    final effectiveAccountName = accountName ?? _lastAccountName ?? '';

    final listById = {for (final l in state.lists) l.id: l};
    final listTaskIds = <String, List<String>>{};
    final serializedLists = <Map<String, dynamic>>[];

    for (final list in state.lists) {
      final tasksInList = state.tasksForList(list);
      listTaskIds[list.id] = [for (final t in tasksInList) t.id];
      final activeCount = list.smartType == SmartListType.completed
          ? tasksInList.length
          : tasksInList.where((t) => !t.isCompleted).length;
      serializedLists.add({
        'id': list.id,
        'title': activeStrings.titleForList(list),
        'smartType': list.smartType?.name,
        'emoji': list.emoji,
        'activeCount': activeCount,
        'accentColorLight': TodoColors.accentFor(
          list.themeColor,
          brightness: Brightness.light,
        ).toARGB32(),
        'accentColorDark': TodoColors.accentFor(
          list.themeColor,
          brightness: Brightness.dark,
        ).toARGB32(),
      });
    }

    final now = DateTime.now();
    final serializedTasks = <Map<String, dynamic>>[
      for (final task in state.tasks)
        _serializeTask(
          task,
          list: listById[task.listId],
          strings: activeStrings,
          now: now,
        ),
    ];

    await _transport.saveWidgetData(
      'widget_lists_json',
      jsonEncode(serializedLists),
    );
    await _transport.saveWidgetData(
      'widget_tasks_json',
      jsonEncode(serializedTasks),
    );
    await _transport.saveWidgetData(
      'widget_list_task_ids_json',
      jsonEncode(listTaskIds),
    );
    await _transport.saveWidgetData(
      'widget_account_name',
      effectiveAccountName,
    );
    await _transport.saveWidgetData(
      'widget_empty_message',
      activeStrings.emptyListMessage,
    );
    await _transport.saveWidgetData(
      'widget_my_day_label',
      activeStrings.myDay,
    );
    await _transport.saveWidgetData(
      'widget_move_starred_to_top',
      state.moveStarredTasksToTop,
    );
    await _transport.saveWidgetData('widget_is_refreshing', false);
    await _transport.updateWidget(
      qualifiedAndroidName: kAndroidWidgetProviderName,
    );
  }

  static Map<String, dynamic> _serializeTask(
    TaskItem task, {
    required TodoList? list,
    required HomeWidgetStrings strings,
    required DateTime now,
  }) {
    final listTitle = list == null ? '' : strings.titleForList(list);
    return {
      'id': task.id,
      'listId': task.listId,
      'listTitle': listTitle,
      'title': task.title,
      'isCompleted': task.isCompleted,
      'isImportant': task.isImportant,
      'isInMyDay': task.isInMyDay,
      'hasDueDate': task.dueDate != null,
      'hasReminder': task.reminderAt != null,
      'isRecurring': task.recurrence != RecurrenceType.none,
      'isOverdue': task.isOverdue,
      'dueLabel': _formatDueDate(task.dueDate, strings: strings, now: now),
      'reminderLabel': _formatReminder(task.reminderAt, strings: strings, now: now),
    };
  }

  static String _formatDueDate(
    DateTime? date, {
    required HomeWidgetStrings strings,
    required DateTime now,
  }) {
    if (date == null) return '';
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return strings.today;
    if (diff == 1) return strings.tomorrow;
    if (diff == -1) return strings.yesterday;
    return DateFormat.MMMd().format(date);
  }

  static String _formatReminder(
    DateTime? reminder, {
    required HomeWidgetStrings strings,
    required DateTime now,
  }) {
    if (reminder == null) return '';
    final timeStr = DateFormat.Hm().format(reminder);
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(reminder.year, reminder.month, reminder.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return timeStr;
    if (diff == 1) return '${strings.tomorrow} $timeStr';
    return '${DateFormat.MMMd().format(reminder)} $timeStr';
  }
}

Future<void> _widgetBgChain = Future<void>.value();
Timer? _widgetSyncDebounceTimer;
bool _widgetSyncRunning = false;
bool _widgetSyncQueued = false;

Future<T> _enqueueWidgetBgWork<T>(Future<T> Function() work) {
  final next = _widgetBgChain.then((_) => work(), onError: (_) => work());
  _widgetBgChain = next.then((_) {}, onError: (_, _) {});
  return next;
}

void _scheduleDetachedWidgetSync() {
  _widgetSyncDebounceTimer?.cancel();
  _widgetSyncDebounceTimer = Timer(const Duration(milliseconds: 600), () {
    unawaited(_triggerDetachedWidgetSync());
  });
}

Future<void> _triggerDetachedWidgetSync() async {
  if (_widgetSyncRunning) {
    _widgetSyncQueued = true;
    return;
  }
  _widgetSyncRunning = true;
  try {
    do {
      _widgetSyncQueued = false;
      await _enqueueWidgetBgWork(() async {
        final prefs = await SharedPreferences.getInstance();
        final database = TodoDatabase();
        ProviderContainer? container;
        try {
          final snapshot = AccountLocalStorage(prefs).load();
          final activeId = snapshot.activeAccountId;
          if (activeId != null) {
            await TodoRepository.forAccount(
              prefs,
              accountId: activeId,
              database: database,
            ).preload();
          }
          container = ProviderContainer(
            overrides: [
              sharedPreferencesProvider.overrideWithValue(prefs),
              todoDatabaseProvider.overrideWithValue(database),
              realtimeSyncEnabledProvider.overrideWithValue(false),
              periodicSyncEnabledProvider.overrideWithValue(false),
            ],
          );
          await container
              .read(syncProvider.notifier)
              .syncNow()
              .timeout(const Duration(seconds: 10), onTimeout: () {});
          await prefs.setInt(
            kWidgetLastMutationMsKey,
            DateTime.now().millisecondsSinceEpoch,
          );
          final activeAccount = container.read(accountProvider).activeAccount;
          final service = HomeWidgetService(const FlutterHomeWidgetTransport());
          await service.syncWithState(
            container.read(todoProvider),
            accountName: activeAccount?.displayName ?? '',
          );
        } catch (e) {
          appLog('widget detached sync failed: $e', label: 'HomeWidgetBackground');
        } finally {
          container?.dispose();
          await database.close();
        }
      });
    } while (_widgetSyncQueued);
  } finally {
    _widgetSyncRunning = false;
  }
}

/// Background entry point invoked by `home_widget` when the user taps a
/// checkbox or star directly on the Android home screen widget.
@pragma('vm:entry-point')
Future<void> homeWidgetBackgroundCallback(Uri? uri) async {
  final action = HomeWidgetAction.fromUri(uri);
  if (action == null) return;
  final isMutation =
      action.type == HomeWidgetActionType.toggleComplete ||
      action.type == HomeWidgetActionType.toggleImportant;
  if (isMutation && action.taskId == null) return;
  if (!isMutation && action.type != HomeWidgetActionType.refresh) return;

  WidgetsFlutterBinding.ensureInitialized();
  await _enqueueWidgetBgWork(() async {
    final prefs = await SharedPreferences.getInstance();
    final database = TodoDatabase();
    ProviderContainer? container;
    try {
      final snapshot = AccountLocalStorage(prefs).load();
      final activeId = snapshot.activeAccountId;
      if (activeId != null) {
        await TodoRepository.forAccount(
          prefs,
          accountId: activeId,
          database: database,
        ).preload();
      }

      container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          todoDatabaseProvider.overrideWithValue(database),
          realtimeSyncEnabledProvider.overrideWithValue(false),
          periodicSyncEnabledProvider.overrideWithValue(false),
        ],
      );

      final presenter = container.read(tasksViewPresenterProvider);
      final state = container.read(todoProvider);
      final activeAccount = container.read(accountProvider).activeAccount;

      var didMutate = false;
      if (isMutation) {
        final taskId = action.taskId!;
        final target = state.tasks.where((t) => t.id == taskId).firstOrNull;
        if (target != null) {
          if (action.type == HomeWidgetActionType.toggleComplete) {
            final completed = action.flagValue ?? !target.isCompleted;
            presenter.setTaskCompleted(taskId, completed: completed);
            didMutate = true;
          } else {
            final desiredImportant = action.flagValue ?? !target.isImportant;
            if (target.isImportant != desiredImportant) {
              presenter.toggleTaskImportant(taskId);
              didMutate = true;
            }
          }
          // Flush async Drift writes before closing the background database.
          final repo = container.read(todoRepositoryProvider);
          await repo.saveTasks(container.read(todoProvider).tasks);
          await repo.saveDirtyTaskIds(repo.loadDirtyTaskIds());
        }
        await prefs.setInt(
          kWidgetLastMutationMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      }

      if (action.type == HomeWidgetActionType.refresh) {
        await container.read(syncProvider.notifier).syncNow();
        await prefs.setInt(
          kWidgetLastMutationMsKey,
          DateTime.now().millisecondsSinceEpoch,
        );
        final service = HomeWidgetService(const FlutterHomeWidgetTransport());
        await service.syncWithState(
          container.read(todoProvider),
          accountName: activeAccount?.displayName ?? '',
        );
      } else if (didMutate) {
        // Debounce & coalesce background sync so rapid widget taps stay instant
        // and never overlap on SQLite or SharedPreferences.
        _scheduleDetachedWidgetSync();
      }
    } catch (e, st) {
      appLog('failed handling $uri: $e\n$st', label: 'HomeWidgetBackground');
    } finally {
      container?.dispose();
      await database.close();
    }
  });
}
