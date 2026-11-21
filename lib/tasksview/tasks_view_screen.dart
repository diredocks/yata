import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../customizations/theme_picker_sheet.dart';
import '../detailview/recurrence/task_pickers.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import 'recyclerview/ruled_lines_painter.dart';
import 'recyclerview/task_list_tile.dart';
import 'renamelist/list_editor_dialog.dart';
import 'richentry/task_entry_sheet.dart';
import 'tasks_action_presenter.dart';
import 'tasks_view_presenter.dart';

enum _ListMenuAction {
  rename,
  sort,
  reorder,
  changeTheme,
  toggleCompleted,
  duplicate,
  delete,
}

class TasksViewScreen extends ConsumerStatefulWidget {
  const TasksViewScreen({
    super.key,
    required this.onOpenTask,
    this.onBackPressed,
  });

  final void Function(TaskItem task) onOpenTask;
  final VoidCallback? onBackPressed;

  @override
  ConsumerState<TasksViewScreen> createState() => _TasksViewScreenState();
}

class _TasksViewScreenState extends ConsumerState<TasksViewScreen> {
  bool _completedExpanded = true;
  bool _isReordering = false;
  double _scrollOffset = 0.0;
  final Set<String> _multiSelectedIds = {};
  final Set<String> _collapsedPlannedBuckets = {};
  final Set<String> _collapsedCompletedListBuckets = {};

  bool get _isMultiSelecting => _multiSelectedIds.isNotEmpty;

  String _localizedListTitle(AppLocalizations l10n, TodoList list) {
    return switch (list.smartType) {
      SmartListType.myDay => l10n.myDay,
      SmartListType.important => l10n.important,
      SmartListType.planned => l10n.planned,
      SmartListType.all => l10n.all,
      SmartListType.completed => l10n.completedList,
      SmartListType.tasks => l10n.tasks,
      null => list.title,
    };
  }

  void _openAddTaskSheet(TodoState state) {
    final notifier = ref.read(tasksViewPresenterProvider);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TaskEntrySheet(
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
          notifier.addTask(
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

  String _sortLabel(AppLocalizations l10n, TaskSortOption option) {
    return switch (option) {
      TaskSortOption.defaultOrder => l10n.sortByDefault,
      TaskSortOption.importance => l10n.sortByImportance,
      TaskSortOption.dueDate => l10n.sortByDueDate,
      TaskSortOption.addedToMyDay => l10n.sortByAddedToMyDay,
      TaskSortOption.alphabetical => l10n.sortByAlphabetical,
      TaskSortOption.creationDate => l10n.sortByCreationDate,
    };
  }

  Future<void> _showSortSheet(TodoState state, TodoList currentList) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksViewPresenterProvider);
    final options = <(TaskSortOption, String, IconData)>[
      (TaskSortOption.importance, l10n.sortByImportance, Icons.star_outline),
      (
        TaskSortOption.dueDate,
        l10n.sortByDueDate,
        Icons.calendar_today_outlined,
      ),
      (
        TaskSortOption.addedToMyDay,
        l10n.sortByAddedToMyDay,
        Icons.wb_sunny_outlined,
      ),
      (
        TaskSortOption.alphabetical,
        l10n.sortByAlphabetical,
        Icons.sort_by_alpha,
      ),
      (
        TaskSortOption.creationDate,
        l10n.sortByCreationDate,
        Icons.access_time,
      ),
      (TaskSortOption.defaultOrder, l10n.sortByDefault, Icons.list),
    ];

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.sortBy,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            for (final (option, label, icon) in options)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                trailing: currentList.sortOption == option
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  notifier.setListSortOption(currentList.id, option);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteList(TodoList list, bool confirmRequired) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksViewPresenterProvider);
    if (confirmRequired) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.deleteList),
          content: Text(l10n.deleteListConfirm(list.title)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    notifier.deleteList(list.id);
    widget.onBackPressed?.call();
  }

  Future<void> _batchPickDueDate(WeekStart startOfWeek) async {
    final notifier = ref.read(tasksActionPresenterProvider);
    final result = await showDueDatePickerSheet(
      context,
      startOfWeek: startOfWeek,
      includeRemoveOption: true,
    );
    if (result == null) return;
    if (result.cleared) {
      notifier.batchSetDueDate(_multiSelectedIds, null);
      setState(() => _multiSelectedIds.clear());
    } else if (result.date != null) {
      notifier.batchSetDueDate(_multiSelectedIds, result.date);
      setState(() => _multiSelectedIds.clear());
    }
  }

  Future<void> _batchCopyToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksActionPresenterProvider);
    final selectableLists = state.lists
        .where((l) => !l.isSmartList || l.smartType == SmartListType.tasks)
        .toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.copyTasks,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final list in selectableLists)
                    ListTile(
                      leading: Icon(
                        list.icon,
                        color: TodoColors.accentFor(list.themeColor),
                      ),
                      title: Text(
                        list.smartType == SmartListType.tasks
                            ? l10n.tasks
                            : list.title,
                      ),
                      onTap: () => Navigator.pop(ctx, list.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      notifier.batchCopyToList(_multiSelectedIds, picked);
      setState(() => _multiSelectedIds.clear());
    }
  }

  Future<void> _duplicateListWithPrompt(
    TodoState state,
    TodoList currentList,
  ) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksViewPresenterProvider);
    final hasCompleted = currentList.showCompleted &&
        state.tasks
            .any((t) => t.listId == currentList.id && t.isCompleted);

    if (!hasCompleted) {
      notifier.duplicateList(currentList.id, keepCompleted: false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.duplicateListSuccess)),
        );
      }
      return;
    }

    final keepCompleted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.keepTasksCompletedTitle),
        content: Text(l10n.keepTasksCompletedMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.no),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yes),
          ),
        ],
      ),
    );
    if (keepCompleted != null) {
      notifier.duplicateList(currentList.id, keepCompleted: keepCompleted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.duplicateListSuccess)),
        );
      }
    }
  }

  Future<void> _batchMoveToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksActionPresenterProvider);
    final selectableLists = state.lists
        .where((l) => !l.isSmartList || l.smartType == SmartListType.tasks)
        .toList();

    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                l10n.moveToList,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final list in selectableLists)
                    ListTile(
                      leading: Icon(
                        list.icon,
                        color: TodoColors.accentFor(list.themeColor),
                      ),
                      title: Text(
                        list.smartType == SmartListType.tasks
                            ? l10n.tasks
                            : list.title,
                      ),
                      onTap: () => Navigator.pop(ctx, list.id),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      notifier.batchMoveToList(_multiSelectedIds, picked);
      setState(() => _multiSelectedIds.clear());
    }
  }

  Future<void> _batchDelete(bool confirmRequired) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksActionPresenterProvider);
    if (confirmRequired) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.deleteTaskTitle),
          content: Text(l10n.deleteSelectedConfirm(_multiSelectedIds.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.delete),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    notifier.batchDeleteTasks(_multiSelectedIds);
    setState(() => _multiSelectedIds.clear());
  }

  List<PopupMenuEntry<_ListMenuAction>> _buildMenuItems(
    AppLocalizations l10n,
    TodoList list,
    bool showCompleted,
  ) {
    final items = <PopupMenuEntry<_ListMenuAction>>[];
    final isCustom = !list.isSmartList;
    final supportsSort = isCustom ||
        list.smartType == SmartListType.myDay ||
        list.smartType == SmartListType.all ||
        list.smartType == SmartListType.tasks;
    final supportsReorder = isCustom ||
        list.smartType == SmartListType.myDay ||
        list.smartType == SmartListType.tasks;
    final supportsToggleCompleted = list.smartType != SmartListType.all &&
        list.smartType != SmartListType.completed;

    if (isCustom) {
      items.add(
        PopupMenuItem(
          value: _ListMenuAction.rename,
          child: ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l10n.renameList),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    if (supportsSort) {
      items.add(
        PopupMenuItem(
          value: _ListMenuAction.sort,
          child: ListTile(
            leading: const Icon(Icons.sort),
            title: Text(l10n.sortBy),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    if (supportsReorder) {
      items.add(
        PopupMenuItem(
          value: _ListMenuAction.reorder,
          child: ListTile(
            leading: const Icon(Icons.reorder),
            title: Text(l10n.reorderTasks),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    items.add(
      PopupMenuItem(
        value: _ListMenuAction.changeTheme,
        child: ListTile(
          leading: const Icon(Icons.palette_outlined),
          title: Text(l10n.changeTheme),
          contentPadding: EdgeInsets.zero,
          dense: true,
        ),
      ),
    );

    if (supportsToggleCompleted) {
      items.add(
        PopupMenuItem(
          value: _ListMenuAction.toggleCompleted,
          child: ListTile(
            leading: Icon(
              showCompleted
                  ? Icons.visibility_off_outlined
                  : Icons.check_circle_outline,
            ),
            title: Text(
              showCompleted
                  ? l10n.hideCompletedTasks
                  : l10n.showCompletedTasks,
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    if (isCustom) {
      items.add(
        PopupMenuItem(
          value: _ListMenuAction.duplicate,
          child: ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: Text(l10n.duplicateList),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
      items.add(const PopupMenuDivider());
      items.add(
        PopupMenuItem(
          value: _ListMenuAction.delete,
          child: ListTile(
            leading: const Icon(
              Icons.delete_outline,
              color: TodoColors.overdueRed,
            ),
            title: Text(
              l10n.deleteList,
              style: const TextStyle(color: TodoColors.overdueRed),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
        ),
      );
    }

    return items;
  }

  Future<void> _handleMenuAction(
    _ListMenuAction action,
    TodoState state,
    TodoList currentList,
  ) async {
    final notifier = ref.read(tasksViewPresenterProvider);
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case _ListMenuAction.rename:
        final result = await showListEditorDialog(
          context: context,
          dialogTitle: l10n.renameList,
          confirmLabel: l10n.save,
          initialTitle: currentList.title,
          initialEmoji: currentList.emoji,
          initialColor: currentList.themeColor,
          initialPhoto: currentList.themePhoto,
        );
        if (result != null) {
          notifier.updateList(
            currentList.id,
            title: result.title,
            emoji: result.emoji,
            clearEmoji: result.emoji == null,
            themeColor: result.themeColor,
            themePhoto: result.themePhoto,
            clearThemePhoto: result.themePhoto == null,
          );
        }
      case _ListMenuAction.sort:
        await _showSortSheet(state, currentList);
      case _ListMenuAction.reorder:
        setState(() {
          _isReordering = true;
          _multiSelectedIds.clear();
        });
      case _ListMenuAction.changeTheme:
        await showThemePickerBottomSheet(
          context: context,
          currentColor: currentList.themeColor,
          currentPhoto: currentList.themePhoto,
          onSelectTheme: (color, photo) => notifier.changeListTheme(
            currentList.id,
            color,
            themePhoto: photo,
          ),
        );
      case _ListMenuAction.toggleCompleted:
        notifier.toggleListShowCompleted(currentList.id);
      case _ListMenuAction.duplicate:
        await _duplicateListWithPrompt(state, currentList);
      case _ListMenuAction.delete:
        await _confirmDeleteList(currentList, state.confirmBeforeDeleting);
    }
  }

  void _toggleSelection(String taskId) {
    setState(() {
      if (_multiSelectedIds.contains(taskId)) {
        _multiSelectedIds.remove(taskId);
      } else {
        _multiSelectedIds.add(taskId);
      }
    });
  }

  List<(String, String, List<TaskItem>)> _groupPlannedTasks(
    AppLocalizations l10n,
    List<TaskItem> tasks,
    WeekStart startOfWeek,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final nextWeekStart = computeNextWeekDate(today, startOfWeek);

    final earlier = <TaskItem>[];
    final todayList = <TaskItem>[];
    final tomorrowList = <TaskItem>[];
    final thisWeek = <TaskItem>[];
    final later = <TaskItem>[];

    for (final task in tasks) {
      final date = task.dueDate ?? task.reminderAt;
      if (date == null) {
        later.add(task);
        continue;
      }
      final day = DateTime(date.year, date.month, date.day);
      if (day.isBefore(today)) {
        earlier.add(task);
      } else if (day == today) {
        todayList.add(task);
      } else if (day == tomorrow) {
        tomorrowList.add(task);
      } else if (day.isBefore(nextWeekStart)) {
        thisWeek.add(task);
      } else {
        later.add(task);
      }
    }

    return [
      if (earlier.isNotEmpty) ('earlier', l10n.plannedEarlier, earlier),
      if (todayList.isNotEmpty) ('today', l10n.today, todayList),
      if (tomorrowList.isNotEmpty) ('tomorrow', l10n.tomorrow, tomorrowList),
      if (thisWeek.isNotEmpty) ('this_week', l10n.plannedThisWeek, thisWeek),
      if (later.isNotEmpty) ('later', l10n.plannedLater, later),
    ];
  }

  List<(String, String, List<TaskItem>)> _groupCompletedByList(
    AppLocalizations l10n,
    List<TaskItem> tasks,
    List<TodoList> lists,
  ) {
    final grouped = <String, List<TaskItem>>{};
    for (final task in tasks) {
      grouped.putIfAbsent(task.listId, () => []).add(task);
    }
    final result = <(String, String, List<TaskItem>)>[];
    for (final entry in grouped.entries) {
      final list = lists.where((l) => l.id == entry.key).firstOrNull;
      final title = list == null
          ? l10n.tasks
          : (list.smartType == SmartListType.tasks ? l10n.tasks : list.title);
      result.add((entry.key, title, entry.value));
    }
    return result;
  }

  Widget _buildBucketPill({
    required String label,
    required int count,
    required bool isExpanded,
    required VoidCallback onTap,
    required TodoList currentList,
    required Color headerFg,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: currentList.themePhoto != null
                    ? Colors.black.withValues(alpha: 0.35)
                    : (Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withValues(alpha: 0.10)
                        : (TodoColors.isLightTheme(currentList.themeColor)
                            ? Colors.white.withValues(alpha: 0.72)
                            : Colors.black.withValues(alpha: 0.25))),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    color: headerFg,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: headerFg,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: headerFg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final notifier = ref.read(tasksViewPresenterProvider);
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final currentList = state.selectedList;
    final baseTitle = _localizedListTitle(l10n, currentList);
    final listTitle = (currentList.emoji != null && currentList.emoji!.isNotEmpty)
        ? '${currentList.emoji!} $baseTitle'
        : baseTitle;
    final accentColor = currentList.themePhoto != null
        ? TodoColors.photoFabBackgroundFor(currentList.themePhoto!)
        : TodoColors.accentFor(
            currentList.themeColor,
            brightness: brightness,
          );
    final gradient = TodoColors.gradientFor(
      currentList.themeColor,
      brightness: brightness,
    );
    final headerFg = currentList.themePhoto != null
        ? Colors.white
        : TodoColors.headerForegroundFor(
            currentList.themeColor,
            brightness: brightness,
          );

    final allTasks = state.tasksForList(currentList);
    final isCompletedList = currentList.smartType == SmartListType.completed;
    final isAllList = currentList.smartType == SmartListType.all;
    final isImportantList = currentList.smartType == SmartListType.important;
    final isPlannedList = currentList.smartType == SmartListType.planned;
    final activeTasks = (isCompletedList || isImportantList)
        ? (isImportantList && !currentList.showCompleted
            ? allTasks.where((t) => !t.isCompleted).toList()
            : allTasks)
        : allTasks.where((t) => !t.isCompleted).toList();
    final completedTasks = (isCompletedList || isImportantList || isAllList)
        ? const <TaskItem>[]
        : (currentList.showCompleted
            ? () {
                final list = allTasks.where((t) => t.isCompleted).toList();
                if (currentList.sortOption == TaskSortOption.defaultOrder) {
                  list.sort((a, b) {
                    final aTime = a.completedAt ?? a.createdAt;
                    final bTime = b.completedAt ?? b.createdAt;
                    return bTime.compareTo(aTime);
                  });
                }
                return list;
              }()
            : const <TaskItem>[]);
    final selectedTasks = _isMultiSelecting
        ? state.tasks.where((t) => _multiSelectedIds.contains(t.id)).toList()
        : const <TaskItem>[];
    final canBatchAddToMyDay = currentList.smartType != SmartListType.myDay &&
        selectedTasks.any((t) => !t.isInMyDay);
    final canBatchMarkImportant =
        currentList.smartType != SmartListType.important &&
            selectedTasks.any((t) => !t.isImportant);

    final isMyDay = currentList.smartType == SmartListType.myDay;
    final subtitle =
        isMyDay ? DateFormat.MMMMEEEEd().format(DateTime.now()) : null;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: _isMultiSelecting
          ? AppBar(
              backgroundColor: isDark
                  ? const Color(0xFF2B2B2B)
                  : TodoColors.secondaryTextLight,
              foregroundColor: Colors.white,
              leading: IconButton(
                onPressed: () => setState(() => _multiSelectedIds.clear()),
                icon: const Icon(Icons.close),
              ),
              title: Text(l10n.selectedCount(_multiSelectedIds.length)),
              actions: [
                if (canBatchAddToMyDay)
                  IconButton(
                    tooltip: l10n.addToMyDay,
                    onPressed: () {
                      actionPresenter.batchAddToMyDay(_multiSelectedIds);
                      setState(() => _multiSelectedIds.clear());
                    },
                    icon: const Icon(Icons.wb_sunny_outlined),
                  ),
                IconButton(
                  tooltip: l10n.addDueDate,
                  onPressed: () => _batchPickDueDate(state.startOfWeek),
                  icon: const Icon(Icons.calendar_today_outlined),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  tooltip: l10n.moreOptions,
                  onSelected: (value) {
                    if (value == 'select_all') {
                      setState(() {
                        _multiSelectedIds.addAll(allTasks.map((t) => t.id));
                      });
                    } else if (value == 'important') {
                      actionPresenter.batchMarkImportant(_multiSelectedIds);
                      setState(() => _multiSelectedIds.clear());
                    } else if (value == 'move') {
                      _batchMoveToList(state);
                    } else if (value == 'copy') {
                      _batchCopyToList(state);
                    } else if (value == 'delete') {
                      _batchDelete(state.confirmBeforeDeleting);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'select_all',
                      child: ListTile(
                        leading: const Icon(Icons.select_all),
                        title: Text(l10n.selectAll),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    if (canBatchMarkImportant)
                      PopupMenuItem(
                        value: 'important',
                        child: ListTile(
                          leading: const Icon(Icons.star_outline),
                          title: Text(l10n.important),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    PopupMenuItem(
                      value: 'move',
                      child: ListTile(
                        leading: const Icon(Icons.drive_file_move_outlined),
                        title: Text(l10n.moveToList),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: ListTile(
                        leading: const Icon(Icons.copy_outlined),
                        title: Text(l10n.copyTasks),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        leading: const Icon(Icons.delete_outline),
                        title: Text(l10n.delete),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (currentList.themePhoto != null)
            Image.asset(
              TodoColors.photoAssetFor(currentList.themePhoto!),
              fit: BoxFit.cover,
            )
          else
            DecoratedBox(decoration: BoxDecoration(gradient: gradient)),
          SafeArea(
            bottom: false,
            child: Stack(
              children: [
                NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    final offset = notification.metrics.pixels;
                    if ((offset - _scrollOffset).abs() > 0.5) {
                      setState(() => _scrollOffset = offset);
                    }
                    return false;
                  },
                  child: CustomScrollView(
                    slivers: [
              if (!_isMultiSelecting)
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: headerFg,
                  expandedHeight: subtitle != null ? 144 : 116,
                  pinned: true,
                  elevation: 0,
                  scrolledUnderElevation: 0,
                  leading: widget.onBackPressed != null
                      ? IconButton(
                          onPressed: widget.onBackPressed,
                          icon: Icon(Icons.arrow_back, color: headerFg),
                        )
                      : null,
                  automaticallyImplyLeading: widget.onBackPressed != null,
                  actions: [
                    if (_isReordering)
                      TextButton(
                        onPressed: () => setState(() => _isReordering = false),
                        child: Text(
                          l10n.done,
                          style: TextStyle(
                            color: headerFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    else
                      PopupMenuButton<_ListMenuAction>(
                        icon: Icon(Icons.more_vert, color: headerFg),
                        tooltip: l10n.moreOptions,
                        onSelected: (action) =>
                            _handleMenuAction(action, state, currentList),
                        itemBuilder: (context) => _buildMenuItems(
                          l10n,
                          currentList,
                          currentList.showCompleted,
                        ),
                      ),
                  ],
                  flexibleSpace: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (currentList.themePhoto != null) ...[
                          Image.asset(
                            TodoColors.photoAssetFor(currentList.themePhoto!),
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                          Container(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.12,
                            ),
                          ),
                        ] else
                          ColoredBox(color: gradient.colors.first),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final topPadding = MediaQuery.paddingOf(context).top;
                            final collapsedHeight = kToolbarHeight + topPadding;
                            final expandedHeight =
                                (subtitle != null ? 144.0 : 116.0) + topPadding;
                            final denom = (expandedHeight - collapsedHeight)
                                .clamp(1.0, 200.0);
                            final t =
                                ((expandedHeight - constraints.maxHeight) /
                                        denom)
                                    .clamp(0.0, 1.0);
                            final startPad = widget.onBackPressed != null
                                ? 16.0 + 40.0 * t
                                : 15.0;
                            final bottomPad = subtitle != null
                                ? 42.0 - 26.0 * t
                                : 16.0;
                            final subtitleSize = 20.0 - 7.0 * t;

                            return FlexibleSpaceBar(
                              expandedTitleScale: 1.5,
                              titlePadding: EdgeInsetsDirectional.only(
                                start: startPad,
                                bottom: bottomPad,
                                end: 56,
                              ),
                              title: Text(
                                listTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: headerFg,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 20,
                                ),
                              ),
                              background: subtitle != null
                                  ? Align(
                                      alignment:
                                          AlignmentDirectional.bottomStart,
                                      child: Padding(
                                        padding: EdgeInsetsDirectional.only(
                                          start: startPad,
                                          bottom: 10.0 - 4.0 * t,
                                          end: 56,
                                        ),
                                        child: Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: headerFg.withValues(
                                              alpha: 0.92,
                                            ),
                                            fontSize: subtitleSize,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                    )
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

              // Sort banner (task_list_header.xml)
              if (currentList.sortOption != TaskSortOption.defaultOrder &&
                  !_isReordering)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: TodoColors.isLightTheme(currentList.themeColor)
                              ? Colors.white.withValues(alpha: 0.72)
                              : Colors.black.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: InkWell(
                                  onTap: () => notifier
                                      .toggleListSortDirection(currentList.id),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Flexible(
                                          child: Text(
                                            l10n.sortedBy(
                                              _sortLabel(
                                                l10n,
                                                currentList.sortOption,
                                              ),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: headerFg,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w400,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Icon(
                                          currentList.sortAscending
                                              ? Icons.keyboard_arrow_up
                                              : Icons.keyboard_arrow_down,
                                          color: headerFg,
                                          size: 18,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => notifier.setListSortOption(
                                currentList.id,
                                TaskSortOption.defaultOrder,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.close,
                                  size: 20,
                                  color: headerFg,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // Task list (clean themed background when empty, matching original MS To Do)
              if (activeTasks.isEmpty && completedTasks.isEmpty)
                const SliverToBoxAdapter(child: SizedBox.shrink())
              else ...[
                if (_isReordering)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverReorderableList(
                      itemCount: activeTasks.length,
                      onReorderItem: (oldIndex, newIndex) =>
                          notifier.reorderActiveTasks(
                        activeTasks,
                        oldIndex,
                        newIndex,
                      ),
                      itemBuilder: (context, index) {
                        final task = activeTasks[index];
                        return Material(
                          key: ValueKey(task.id),
                          color: Colors.transparent,
                          child: TaskListTile(
                            task: task,
                            accentColor: accentColor,
                            onTap: () {},
                            onToggleCompleted: () =>
                                notifier.toggleTaskCompleted(task.id),
                            onToggleImportant: () =>
                                notifier.toggleTaskImportant(task.id),
                            trailingHandle: ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(Icons.drag_handle),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  )
                else if (isPlannedList &&
                    currentList.sortOption == TaskSortOption.defaultOrder)
                  for (final (bucketKey, bucketTitle, bucketTasks)
                      in _groupPlannedTasks(
                    l10n,
                    activeTasks,
                    state.startOfWeek,
                  )) ...[
                    SliverToBoxAdapter(
                      child: _buildBucketPill(
                        label: bucketTitle,
                        count: bucketTasks.length,
                        isExpanded:
                            !_collapsedPlannedBuckets.contains(bucketKey),
                        onTap: () => setState(() {
                          if (_collapsedPlannedBuckets.contains(bucketKey)) {
                            _collapsedPlannedBuckets.remove(bucketKey);
                          } else {
                            _collapsedPlannedBuckets.add(bucketKey);
                          }
                        }),
                        currentList: currentList,
                        headerFg: headerFg,
                      ),
                    ),
                    if (!_collapsedPlannedBuckets.contains(bucketKey))
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final task = bucketTasks[index];
                              final originListName = state.lists
                                  .where((l) => l.id == task.listId)
                                  .map(
                                    (l) => l.smartType == SmartListType.tasks
                                        ? l10n.tasks
                                        : l.title,
                                  )
                                  .firstOrNull;
                              return TaskListTile(
                                task: task,
                                listName: originListName,
                                showMyDayBadge: true,
                                accentColor: accentColor,
                                isSelected: state.selectedTaskId == task.id,
                                isMultiSelected:
                                    _multiSelectedIds.contains(task.id),
                                onTap: () {
                                  if (_isMultiSelecting) {
                                    _toggleSelection(task.id);
                                  } else {
                                    widget.onOpenTask(task);
                                  }
                                },
                                onLongPress: () => _toggleSelection(task.id),
                                onToggleCompleted: () =>
                                    notifier.toggleTaskCompleted(task.id),
                                onToggleImportant: () =>
                                    notifier.toggleTaskImportant(task.id),
                              );
                            },
                            childCount: bucketTasks.length,
                          ),
                        ),
                      ),
                  ]
                else if ((isCompletedList || isAllList) &&
                    currentList.sortOption == TaskSortOption.defaultOrder)
                  for (final (listId, listName, bucketTasks)
                      in _groupCompletedByList(
                    l10n,
                    activeTasks,
                    state.lists,
                  )) ...[
                    SliverToBoxAdapter(
                      child: _buildBucketPill(
                        label: listName,
                        count: bucketTasks.length,
                        isExpanded:
                            !_collapsedCompletedListBuckets.contains(listId),
                        onTap: () => setState(() {
                          if (_collapsedCompletedListBuckets.contains(listId)) {
                            _collapsedCompletedListBuckets.remove(listId);
                          } else {
                            _collapsedCompletedListBuckets.add(listId);
                          }
                        }),
                        currentList: currentList,
                        headerFg: headerFg,
                      ),
                    ),
                    if (!_collapsedCompletedListBuckets.contains(listId))
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final task = bucketTasks[index];
                              return TaskListTile(
                                task: task,
                                showMyDayBadge: true,
                                accentColor: accentColor,
                                isSelected: state.selectedTaskId == task.id,
                                isMultiSelected:
                                    _multiSelectedIds.contains(task.id),
                                onTap: () {
                                  if (_isMultiSelecting) {
                                    _toggleSelection(task.id);
                                  } else {
                                    widget.onOpenTask(task);
                                  }
                                },
                                onLongPress: () => _toggleSelection(task.id),
                                onToggleCompleted: () =>
                                    notifier.toggleTaskCompleted(task.id),
                                onToggleImportant: () =>
                                    notifier.toggleTaskImportant(task.id),
                              );
                            },
                            childCount: bucketTasks.length,
                          ),
                        ),
                      ),
                  ]
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final task = activeTasks[index];
                          final originListName = currentList.isSmartList
                              ? state.lists
                                  .where((l) => l.id == task.listId)
                                  .map(
                                    (l) => l.smartType == SmartListType.tasks
                                        ? l10n.tasks
                                        : l.title,
                                  )
                                  .firstOrNull
                              : null;
                          return TaskListTile(
                            task: task,
                            listName: originListName,
                            showMyDayBadge: !isMyDay,
                            accentColor: accentColor,
                            isSelected: state.selectedTaskId == task.id,
                            isMultiSelected:
                                _multiSelectedIds.contains(task.id),
                            onTap: () {
                              if (_isMultiSelecting) {
                                _toggleSelection(task.id);
                              } else {
                                widget.onOpenTask(task);
                              }
                            },
                            onLongPress: () => _toggleSelection(task.id),
                            onToggleCompleted: () =>
                                notifier.toggleTaskCompleted(task.id),
                            onToggleImportant: () =>
                                notifier.toggleTaskImportant(task.id),
                          );
                        },
                        childCount: activeTasks.length,
                      ),
                    ),
                  ),

                // Collapsible Completed bucket
                if (completedTasks.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildBucketPill(
                      label: l10n.completed,
                      count: completedTasks.length,
                      isExpanded: _completedExpanded,
                      onTap: () => setState(
                        () => _completedExpanded = !_completedExpanded,
                      ),
                      currentList: currentList,
                      headerFg: headerFg,
                    ),
                  ),

                if (completedTasks.isNotEmpty && _completedExpanded)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final task = completedTasks[index];
                          return TaskListTile(
                            task: task,
                            accentColor: accentColor,
                            isSelected: state.selectedTaskId == task.id,
                            isMultiSelected:
                                _multiSelectedIds.contains(task.id),
                            onTap: () {
                              if (_isMultiSelecting) {
                                _toggleSelection(task.id);
                              } else {
                                widget.onOpenTask(task);
                              }
                            },
                            onLongPress: () => _toggleSelection(task.id),
                            onToggleCompleted: () =>
                                notifier.toggleTaskCompleted(task.id),
                            onToggleImportant: () =>
                                notifier.toggleTaskImportant(task.id),
                          );
                        },
                        childCount: completedTasks.length,
                      ),
                    ),
                  ),
              ],

              // Ruled lines only in remaining empty space below all tasks/buckets
              SliverFillRemaining(
                hasScrollBody: false,
                fillOverscroll: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 84),
                  child: CustomPaint(
                    painter: RuledLinesPainter(
                      lineColor: currentList.themePhoto == null &&
                              TodoColors.isLightTheme(currentList.themeColor) &&
                              !isDark
                          ? TodoColors.taskViewDividerLight
                          : TodoColors.taskViewDividerDark,
                      rowHeight: 54.0,
                      horizontalInset: 8.0,
                    ),
                  ),
                ),
              ),
            ],
          ),
          ),
                if (_scrollOffset > 4 && !_isMultiSelecting)
                  Positioned(
                    top: ((subtitle != null ? 144.0 : 116.0) - _scrollOffset)
                        .clamp(
                      kToolbarHeight,
                      subtitle != null ? 144.0 : 116.0,
                    ),
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 3,
                        decoration: TodoColors.horizontalShadowDecoration,
                      ),
                    ),
                  ),
              ],
            ),
        ),
        ],
      ),
      floatingActionButton: (_isReordering || _isMultiSelecting || isCompletedList)
          ? null
          : FloatingActionButton(
              onPressed: () => _openAddTaskSheet(state),
              backgroundColor: currentList.themePhoto != null
                  ? TodoColors.photoFabBackgroundFor(currentList.themePhoto!)
                  : TodoColors.fabBackgroundFor(
                      currentList.themeColor,
                      brightness: brightness,
                    ),
              foregroundColor: currentList.themePhoto != null
                  ? (isDark ? Colors.black : Colors.white)
                  : TodoColors.fabForegroundFor(
                      currentList.themeColor,
                      brightness: brightness,
                    ),
              tooltip: l10n.addTaskPlaceholder,
              child: const Icon(Icons.add),
            ),
    );
  }
}
