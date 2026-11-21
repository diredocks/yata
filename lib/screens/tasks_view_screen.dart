import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import '../widgets/list_theme_picker.dart';
import '../widgets/task_entry_sheet.dart';
import '../widgets/task_list_tile.dart';

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
  final Set<String> _multiSelectedIds = {};

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

  String _emptyMessage(AppLocalizations l10n, TodoList list) {
    return switch (list.smartType) {
      SmartListType.myDay => l10n.emptyMyDaySubtitle,
      SmartListType.important => l10n.emptyImportantTitle,
      SmartListType.planned => l10n.emptyPlannedTitle,
      SmartListType.completed => l10n.emptyCompletedTitle,
      _ => l10n.emptyListTitle,
    };
  }

  void _openAddTaskSheet(TodoState state) {
    final notifier = ref.read(todoProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TaskEntrySheet(
        lists: state.lists,
        currentList: state.selectedList,
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

  Future<void> _showSortSheet(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todoProvider.notifier);
    final options = <(TaskSortOption, String, IconData)>[
      (TaskSortOption.defaultOrder, l10n.sortByDefault, Icons.list),
      (TaskSortOption.importance, l10n.sortByImportance, Icons.star_outline),
      (
        TaskSortOption.dueDate,
        l10n.sortByDueDate,
        Icons.calendar_today_outlined,
      ),
      (
        TaskSortOption.alphabetical,
        l10n.sortByAlphabetical,
        Icons.sort_by_alpha,
      ),
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
                trailing: state.sortOption == option
                    ? const Icon(Icons.check)
                    : null,
                onTap: () {
                  notifier.setSortOption(option);
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
    final notifier = ref.read(todoProvider.notifier);
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

  Future<void> _batchPickDueDate() async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todoProvider.notifier);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.today),
              title: Text(l10n.today),
              onTap: () => Navigator.pop(ctx, 'today'),
            ),
            ListTile(
              leading: const Icon(Icons.wb_twilight),
              title: Text(l10n.tomorrow),
              onTap: () => Navigator.pop(ctx, 'tomorrow'),
            ),
            ListTile(
              leading: const Icon(Icons.next_week),
              title: Text(l10n.nextWeek),
              onTap: () => Navigator.pop(ctx, 'next_week'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(l10n.pickDate),
              onTap: () => Navigator.pop(ctx, 'pick'),
            ),
          ],
        ),
      ),
    );

    if (!mounted || choice == null) return;
    DateTime? targetDate;
    if (choice == 'today') {
      targetDate = today;
    } else if (choice == 'tomorrow') {
      targetDate = today.add(const Duration(days: 1));
    } else if (choice == 'next_week') {
      targetDate = today.add(const Duration(days: 7));
    } else if (choice == 'pick') {
      targetDate = await showDatePicker(
        context: context,
        initialDate: today,
        firstDate: today.subtract(const Duration(days: 365)),
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
    }

    if (targetDate != null) {
      notifier.batchSetDueDate(_multiSelectedIds, targetDate);
      setState(() => _multiSelectedIds.clear());
    }
  }

  Future<void> _batchMoveToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(todoProvider.notifier);
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
    final notifier = ref.read(todoProvider.notifier);
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
    final supportsToggleCompleted = list.smartType != SmartListType.planned &&
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

  void _handleMenuAction(
    _ListMenuAction action,
    TodoState state,
    TodoList currentList,
  ) {
    final notifier = ref.read(todoProvider.notifier);
    switch (action) {
      case _ListMenuAction.rename:
        showRenameListDialog(
          context: context,
          initialTitle: currentList.title,
          onRename: (title) => notifier.renameList(currentList.id, title),
        );
      case _ListMenuAction.sort:
        _showSortSheet(state);
      case _ListMenuAction.reorder:
        setState(() {
          _isReordering = true;
          _multiSelectedIds.clear();
        });
      case _ListMenuAction.changeTheme:
        showChangeThemeDialog(
          context: context,
          currentColor: currentList.themeColor,
          onSelectColor: (color) =>
              notifier.changeListTheme(currentList.id, color),
        );
      case _ListMenuAction.toggleCompleted:
        notifier.toggleShowCompleted(!state.showCompleted);
      case _ListMenuAction.duplicate:
        notifier.duplicateList(currentList.id);
      case _ListMenuAction.delete:
        _confirmDeleteList(currentList, state.confirmBeforeDeleting);
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final notifier = ref.read(todoProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final currentList = state.selectedList;
    final listTitle = _localizedListTitle(l10n, currentList);
    final accentColor = TodoColors.accentFor(currentList.themeColor);
    final gradient = TodoColors.gradientFor(
      currentList.themeColor,
      brightness: brightness,
    );
    final headerFg = TodoColors.headerForegroundFor(
      currentList.themeColor,
      brightness: brightness,
    );

    final allTasks = state.tasksForList(currentList);
    final isCompletedList = currentList.smartType == SmartListType.completed;
    final activeTasks = isCompletedList
        ? allTasks
        : allTasks.where((t) => !t.isCompleted).toList();
    final completedTasks = isCompletedList
        ? const <TaskItem>[]
        : (state.showCompleted
            ? allTasks.where((t) => t.isCompleted).toList()
            : const <TaskItem>[]);

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
                IconButton(
                  tooltip: l10n.addToMyDay,
                  onPressed: () {
                    notifier.batchSetMyDay(_multiSelectedIds, true);
                    setState(() => _multiSelectedIds.clear());
                  },
                  icon: const Icon(Icons.wb_sunny_outlined),
                ),
                IconButton(
                  tooltip: l10n.addDueDate,
                  onPressed: _batchPickDueDate,
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
                      notifier.batchSetImportant(_multiSelectedIds, true);
                      setState(() => _multiSelectedIds.clear());
                    } else if (value == 'move') {
                      _batchMoveToList(state);
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
      body: Container(
        decoration: BoxDecoration(gradient: gradient),
        child: SafeArea(
          bottom: false,
          child: CustomScrollView(
            slivers: [
              if (!_isMultiSelecting)
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  foregroundColor: headerFg,
                  expandedHeight: subtitle != null ? 144 : 116,
                  pinned: true,
                  elevation: 0,
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
                          state.showCompleted,
                        ),
                      ),
                  ],
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final topPadding = MediaQuery.paddingOf(context).top;
                      final collapsedHeight = kToolbarHeight + topPadding;
                      final isCollapsed =
                          constraints.maxHeight <= collapsedHeight + 20;

                      return FlexibleSpaceBar(
                        expandedTitleScale: 1.5,
                        titlePadding: EdgeInsetsDirectional.only(
                          start: (widget.onBackPressed != null && isCollapsed)
                              ? 56
                              : 16,
                          bottom:
                              (subtitle != null && !isCollapsed) ? 42 : 14,
                          end: 56,
                        ),
                        title: Text(
                          listTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: headerFg,
                            fontWeight: FontWeight.w600,
                            fontSize: 20,
                          ),
                        ),
                        background: subtitle != null
                            ? Align(
                                alignment: AlignmentDirectional.bottomStart,
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 16,
                                    bottom: 12,
                                    end: 16,
                                  ),
                                  child: Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: headerFg.withValues(alpha: 0.95),
                                      fontSize: 20,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
                ),

              // Task list (clean themed background when empty, matching original MS To Do)
              if (activeTasks.isEmpty && completedTasks.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: SizedBox.shrink(),
                )
              else ...[
                if (_isReordering)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    sliver: SliverReorderableList(
                      itemCount: activeTasks.length,
                      onReorder: (oldIndex, newIndex) =>
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
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: InkWell(
                          onTap: () => setState(
                            () => _completedExpanded = !_completedExpanded,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: TodoColors.isLightTheme(
                                      currentList.themeColor)
                                  ? Colors.white.withValues(alpha: 0.72)
                                  : Colors.black.withValues(alpha: 0.22),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _completedExpanded
                                      ? Icons.keyboard_arrow_down
                                      : Icons.keyboard_arrow_right,
                                  color: headerFg,
                                  size: 18,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${l10n.completed}  ${completedTasks.length}',
                                  style: TextStyle(
                                    color: headerFg,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                if (completedTasks.isNotEmpty && _completedExpanded)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 84),
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
                  )
                else
                  const SliverToBoxAdapter(child: SizedBox(height: 84)),
              ],
            ],
          ),
        ),
      ),
      floatingActionButton: (_isReordering || _isMultiSelecting || isCompletedList)
          ? null
          : FloatingActionButton(
              onPressed: () => _openAddTaskSheet(state),
              backgroundColor: TodoColors.fabBackgroundFor(
                currentList.themeColor,
                brightness: brightness,
              ),
              foregroundColor: TodoColors.fabForegroundFor(
                currentList.themeColor,
                brightness: brightness,
              ),
              tooltip: l10n.addTaskPlaceholder,
              child: const Icon(Icons.add),
            ),
    );
  }
}
