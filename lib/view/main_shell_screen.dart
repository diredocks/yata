import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../account/account_provider.dart';
import '../data/todo_provider.dart';
import '../detailview/detail_view_presenter.dart';
import '../detailview/detail_view_screen.dart';
import '../homeview/home_view_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/account.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../notifications/notification_service.dart';
import '../notifications/snooze_reminder_sheet.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../sync/sync_provider.dart';
import '../tasksview/richentry/task_entry_sheet.dart';
import '../tasksview/tasks_view_presenter.dart';
import '../tasksview/tasks_view_screen.dart';
import '../widget/home_widget_sync.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen>
    with WidgetsBindingObserver {
  StreamSubscription<NotificationActionEvent>? _notificationSub;
  StreamSubscription<HomeWidgetAction>? _widgetActionSub;
  ModalRoute<void>? _activeTasksRoute;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    final notificationService = ref.read(notificationServiceProvider);
    _notificationSub = notificationService.events.listen(
      _handleNotificationAction,
    );
    _widgetActionSub = ref
        .read(homeWidgetSyncProvider)
        .actions
        .listen(_handleWidgetAction);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(todoProvider);
      final l10n = AppLocalizations.of(context);
      final strings = NotificationStrings.fromLocalizations(l10n);
      unawaited(notificationService.syncWithState(state, strings: strings));
      _restoreLastEnteredListIfNeeded();
      unawaited(_bootstrapAndStartSync());
    });
  }

  Future<void> _bootstrapAndStartSync() async {
    final initialAction = await ref.read(homeWidgetSyncProvider).bootstrap();
    if (!mounted) return;
    _startSyncForActiveAccount();
    if (initialAction != null) {
      _handleWidgetAction(initialAction);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_onAppResumed());
    } else if (state == AppLifecycleState.paused) {
      ref.read(syncProvider.notifier).onAppPaused();
    }
  }

  Future<void> _onAppResumed() async {
    await ref.read(homeWidgetSyncProvider).syncFromWidget(reason: 'resume');
    if (!mounted) return;
    ref.read(syncProvider.notifier).onAppResumed();
  }

  void _handleWidgetAction(HomeWidgetAction action) {
    if (!mounted) return;

    final state = ref.read(todoProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final isExtraWide = MediaQuery.sizeOf(context).width >= 960;

    switch (action.type) {
      case HomeWidgetActionType.quickAdd:
        final targetList = state.lists.firstWhere(
          (l) => l.id == action.listId,
          orElse: () => state.selectedList,
        );
        _navigateToListFromWidget(state, targetList, isWide);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _openQuickAddSheet(ref.read(todoProvider), targetList);
        });
      case HomeWidgetActionType.openList:
        final targetList = state.lists.firstWhere(
          (l) => l.id == action.listId,
          orElse: () => state.selectedList,
        );
        _navigateToListFromWidget(state, targetList, isWide);
      case HomeWidgetActionType.openTask:
        final taskId = action.taskId;
        if (taskId == null) return;
        for (final task in state.tasks) {
          if (task.id == taskId) {
            Navigator.of(context).popUntil((route) => route.isFirst);
            if (!isWide) {
              final taskList = state.lists.firstWhere(
                (l) => l.id == (action.listId ?? task.listId),
                orElse: () => state.selectedList,
              );
              _pushTasksView(taskList, animated: false);
            }
            _handleOpenTask(task, isExtraWide);
            break;
          }
        }
    }
    if (isWide && action.listId != null) {
      final matched = state.lists
          .where((l) => l.id == action.listId)
          .firstOrNull;
      if (matched != null) {
        ref.read(todoProvider.notifier).selectList(matched.id);
      }
    }
  }

  void _openQuickAddSheet(TodoState state, TodoList currentList) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskEntrySheet(
        lists: state.lists,
        currentList: currentList,
        startOfWeek: state.startOfWeek,
        onSubmit:
            ({
              required String title,
              String? targetListId,
              DateTime? dueDate,
              DateTime? reminderAt,
              RecurrenceType recurrence = RecurrenceType.none,
            }) {
              ref
                  .read(tasksViewPresenterProvider)
                  .addTask(
                    title: title,
                    targetListId: targetListId,
                    dueDate: dueDate,
                    reminderAt: reminderAt,
                    recurrence: recurrence,
                  );
            },
      ),
    );
  }

  void _startSyncForActiveAccount({bool accountChanged = false}) {
    if (!accountChanged && !ref.read(startupSyncEnabledProvider)) return;
    final account = ref.read(accountProvider).activeAccount;
    if (account is! MicrosoftAccount) return;
    unawaited(ref.read(syncProvider.notifier).syncNow());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_notificationSub?.cancel());
    unawaited(_widgetActionSub?.cancel());
    super.dispose();
  }

  Future<void> _handleNotificationAction(NotificationActionEvent event) async {
    if (!mounted) return;
    final state = ref.read(todoProvider);
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    final isExtraWide = MediaQuery.sizeOf(context).width >= 960;

    switch (event.type) {
      case NotificationActionType.completeTask:
        final taskId = event.taskId;
        if (taskId != null) {
          ref
              .read(tasksViewPresenterProvider)
              .setTaskCompleted(taskId, completed: true);
        }
      case NotificationActionType.snoozeTask:
        final taskId = event.taskId;
        if (taskId == null) return;
        TaskItem? matchedTask;
        for (final task in state.tasks) {
          if (task.id == taskId) {
            matchedTask = task;
            break;
          }
        }
        final duration = await showSnoozeReminderSheet(
          context,
          taskTitle: matchedTask?.title,
        );
        if (duration != null && mounted) {
          ref
              .read(detailViewPresenterProvider)
              .setTaskReminder(taskId, DateTime.now().toUtc().add(duration));
        }
      case NotificationActionType.openTask:
        final taskId = event.taskId;
        if (taskId == null) return;
        for (final task in state.tasks) {
          if (task.id == taskId) {
            _handleOpenTask(task, isExtraWide);
            break;
          }
        }
      case NotificationActionType.openMyDay:
        final myDay = state.lists.firstWhere(
          (l) => l.smartType == SmartListType.myDay,
          orElse: () => state.selectedList,
        );
        _handleSelectList(myDay, isWide);
      case NotificationActionType.quickAdd:
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => TaskEntrySheet(
            lists: state.lists,
            currentList: state.selectedList,
            startOfWeek: state.startOfWeek,
            onSubmit:
                ({
                  required String title,
                  String? targetListId,
                  DateTime? dueDate,
                  DateTime? reminderAt,
                  RecurrenceType recurrence = RecurrenceType.none,
                }) {
                  ref
                      .read(tasksViewPresenterProvider)
                      .addTask(
                        title: title,
                        targetListId: targetListId,
                        dueDate: dueDate,
                        reminderAt: reminderAt,
                        recurrence: recurrence,
                      );
                },
          ),
        );
    }
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => SearchScreen(
          onOpenTask: (task) {
            Navigator.of(ctx).push(buildDetailViewRoute(taskId: task.id));
          },
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
  }

  void _restoreLastEnteredListIfNeeded() {
    if (!mounted) return;
    final isWide = MediaQuery.sizeOf(context).width >= 600;
    if (isWide) return;
    final lastListId = ref
        .read(todoSettingsStoreProvider)
        .loadLastEnteredListId();
    if (lastListId == null) return;
    final lists = ref.read(todoProvider).lists;
    TodoList? targetList;
    for (final list in lists) {
      if (list.id == lastListId) {
        targetList = list;
        break;
      }
    }
    if (targetList == null) {
      ref.read(todoProvider.notifier).setLastEnteredListId(null);
      return;
    }
    _pushTasksView(targetList, animated: false);
  }

  void _navigateToListFromWidget(
    TodoState state,
    TodoList targetList,
    bool isWide,
  ) {
    if (isWide) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      ref.read(todoProvider.notifier).selectList(targetList.id);
      return;
    }

    final activeRoute = _activeTasksRoute;
    final alreadyOnTargetList =
        activeRoute != null &&
        activeRoute.isActive &&
        state.selectedListId == targetList.id;
    if (alreadyOnTargetList) {
      return;
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
    _pushTasksView(targetList, animated: false);
  }

  void _pushTasksView(TodoList list, {bool animated = true}) {
    ref.read(todoProvider.notifier).selectList(list.id);
    ref.read(todoProvider.notifier).setLastEnteredListId(list.id);
    Widget buildScreen(BuildContext routeCtx) => TasksViewScreen(
      onBackPressed: () => Navigator.of(routeCtx).pop(),
      onOpenTask: (task) => _handleOpenTask(task, false),
    );
    final route = animated
        ? MaterialPageRoute<void>(builder: buildScreen)
        : _InstantEnterMaterialPageRoute<void>(builder: buildScreen);
    _activeTasksRoute = route;
    Navigator.of(context).push(route).then((_) {
      if (mounted && identical(_activeTasksRoute, route)) {
        _activeTasksRoute = null;
        ref.read(todoProvider.notifier).setLastEnteredListId(null);
      }
    });
  }

  void _handleSelectList(TodoList list, bool isWide, {bool animated = true}) {
    if (!isWide) {
      _pushTasksView(list, animated: animated);
    } else {
      ref.read(todoProvider.notifier).selectList(list.id);
    }
  }

  void _handleOpenTask(TaskItem task, bool isWide) {
    if (isWide) {
      ref.read(todoProvider.notifier).selectTask(task.id);
    } else {
      Navigator.of(context).push(buildDetailViewRoute(taskId: task.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    ref.listen<String?>(accountProvider.select((s) => s.activeAccountId), (
      previous,
      next,
    ) {
      if (previous != null && next != null && previous != next) {
        ref.read(todoProvider.notifier).setLastEnteredListId(null);
      }
      if (previous != next) {
        _startSyncForActiveAccount(accountChanged: true);
      }
    });
    ref.listen<TodoState>(todoProvider, (_, next) {
      unawaited(
        ref
            .read(notificationServiceProvider)
            .syncWithState(
              next,
              strings: NotificationStrings.fromLocalizations(l10n),
            ),
      );
    });
    final state = ref.watch(todoProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 600;
    final isExtraWide = width >= 960;

    if (!isWide) {
      return HomeViewScreen(
        onSelectList: (list) => _handleSelectList(list, false),
        onOpenSearch: _openSearch,
        onOpenSettings: _openSettings,
      );
    }

    final showDetail = isExtraWide && state.selectedTaskId != null;

    // Wide layout (tablet / desktop, inspired by activity_main_duo.xml)
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: HomeViewScreen(
              isSidebar: true,
              onSelectList: (list) => _handleSelectList(list, true),
              onOpenSearch: _openSearch,
              onOpenSettings: _openSettings,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: TasksViewScreen(
              onOpenTask: (task) => _handleOpenTask(task, isExtraWide),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [...previousChildren, ?currentChild],
            ),
            transitionBuilder: (child, animation) => SizeTransition(
              axis: Axis.horizontal,
              alignment: AlignmentDirectional.centerStart,
              sizeFactor: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: showDetail
                ? Row(
                    key: ValueKey('detail_${state.selectedTaskId}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 360,
                        child: DetailViewScreen(
                          taskId: state.selectedTaskId!,
                          onClose: () =>
                              ref.read(todoProvider.notifier).selectTask(null),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('detail_empty')),
          ),
        ],
      ),
    );
  }
}

/// Material route that enters immediately without an opening transition,
/// while preserving standard Material pop/back-swipe animation.
class _InstantEnterMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _InstantEnterMaterialPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;
}
