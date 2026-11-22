import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../detailview/detail_view_presenter.dart';
import '../../detailview/detail_view_screen.dart';
import '../../homeview/home_view_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../../data/todo_provider.dart';
import '../../notifications/notification_service.dart';
import '../../search/search_screen.dart';
import '../../settings/settings_screen.dart';
import '../../tasksview/richentry/task_entry_sheet.dart';
import '../../tasksview/tasks_view_presenter.dart';
import '../../tasksview/tasks_view_screen.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  StreamSubscription<NotificationActionEvent>? _notificationSub;

  @override
  void initState() {
    super.initState();
    final notificationService = ref.read(notificationServiceProvider);
    _notificationSub =
        notificationService.events.listen(_handleNotificationAction);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(todoProvider);
      final strings =
          NotificationStrings.fromLocalizations(AppLocalizations.of(context));
      unawaited(notificationService.syncWithState(state, strings: strings));
    });
  }

  @override
  void dispose() {
    unawaited(_notificationSub?.cancel());
    super.dispose();
  }

  void _handleNotificationAction(NotificationActionEvent event) {
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
        if (taskId != null) {
          ref.read(detailViewPresenterProvider).setTaskReminder(
                taskId,
                DateTime.now().add(const Duration(minutes: 15)),
              );
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
            onSubmit: ({
              required String title,
              String? targetListId,
              DateTime? dueDate,
              DateTime? reminderAt,
              RecurrenceType recurrence = RecurrenceType.none,
            }) {
              ref.read(tasksViewPresenterProvider).addTask(
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
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  void _handleSelectList(TodoList list, bool isWide) {
    ref.read(todoProvider.notifier).selectList(list.id);
    if (!isWide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeCtx) => TasksViewScreen(
            onBackPressed: () => Navigator.of(routeCtx).pop(),
            onOpenTask: (task) => _handleOpenTask(task, false),
          ),
        ),
      );
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
    ref.listen<TodoState>(todoProvider, (_, next) {
      unawaited(
        ref.read(notificationServiceProvider).syncWithState(
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
              children: [
                ...previousChildren,
                ?currentChild,
              ],
            ),
            transitionBuilder: (child, animation) => SizeTransition(
              axis: Axis.horizontal,
              alignment: AlignmentDirectional.centerStart,
              sizeFactor: animation,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
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
