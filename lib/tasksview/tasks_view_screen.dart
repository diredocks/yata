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
import '../view/delayed_task_completion.dart';
import 'recyclerview/ruled_lines_painter.dart';
import 'recyclerview/swipeable_task_card.dart';
import 'recyclerview/task_list_tile.dart';
import 'renamelist/list_editor_dialog.dart';
import 'richentry/task_entry_sheet.dart';
import 'tasks_action_presenter.dart';
import 'tasks_view_grouping.dart';
import 'tasks_view_presenter.dart';

enum _TasksViewMode {
  browsing,
  reordering,
  multiSelecting,
}

enum _ListMenuAction {
  rename,
  sort,
  reorder,
  changeTheme,
  toggleCompleted,
  duplicate,
  delete,
}

enum _MultiSelectAction {
  selectOrClearAll,
  important,
  move,
  copy,
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
  _TasksViewMode _mode = _TasksViewMode.browsing;
  bool _completedExpanded = true;
  double _scrollOffset = 0.0;
  final Set<String> _multiSelectedIds = {};
  final Set<String> _collapsedPlannedBuckets = {};
  final Set<String> _collapsedCompletedListBuckets = {};
  final _completionController = DelayedTaskCompletionController();
  late final TasksViewPresenter _presenter;

  @override
  void initState() {
    super.initState();
    _presenter = ref.read(tasksViewPresenterProvider);
  }

  @override
  void dispose() {
    _completionController.flushAndDispose(_presenter.setTaskCompleted);
    super.dispose();
  }

  void _enterReordering() {
    setState(() {
      _mode = _TasksViewMode.reordering;
      _multiSelectedIds.clear();
    });
  }

  void _exitReordering() {
    setState(() => _mode = _TasksViewMode.browsing);
  }

  void _toggleSelection(String taskId) {
    setState(() {
      if (!_multiSelectedIds.remove(taskId)) {
        _multiSelectedIds.add(taskId);
      }
      _mode = _multiSelectedIds.isEmpty
          ? _TasksViewMode.browsing
          : _TasksViewMode.multiSelecting;
    });
  }

  void _clearSelection() {
    setState(() {
      _multiSelectedIds.clear();
      _mode = _TasksViewMode.browsing;
    });
  }

  void _selectAll(List<TaskItem> tasks) {
    setState(() {
      _multiSelectedIds.addAll(tasks.map((t) => t.id));
      _mode = _multiSelectedIds.isEmpty
          ? _TasksViewMode.browsing
          : _TasksViewMode.multiSelecting;
    });
  }

  void _toggleBucket(Set<String> collapsed, String key) {
    setState(() {
      if (!collapsed.remove(key)) {
        collapsed.add(key);
      }
    });
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

  String _plannedBucketLabel(AppLocalizations l10n, PlannedBucket bucket) {
    return switch (bucket) {
      PlannedBucket.earlier => l10n.plannedEarlier,
      PlannedBucket.today => l10n.today,
      PlannedBucket.tomorrow => l10n.tomorrow,
      PlannedBucket.thisWeek => l10n.plannedThisWeek,
      PlannedBucket.later => l10n.plannedLater,
    };
  }

  Future<void> _showSortSheet(TodoList currentList) async {
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

  Future<bool> _confirmDialog({
    required String title,
    required String content,
    required String confirmLabel,
    required String cancelLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _confirmDeleteList(TodoList list, bool confirmRequired) async {
    final l10n = AppLocalizations.of(context);
    if (confirmRequired) {
      final confirmed = await _confirmDialog(
        title: l10n.deleteList,
        content: l10n.deleteListConfirm(list.title),
        confirmLabel: l10n.delete,
        cancelLabel: l10n.cancel,
      );
      if (!confirmed) return;
    }
    ref.read(tasksViewPresenterProvider).deleteList(list.id);
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
      _clearSelection();
      return;
    }
    if (result.date != null) {
      notifier.batchSetDueDate(_multiSelectedIds, result.date);
      _clearSelection();
    }
  }

  Future<String?> _pickTargetListSheet(
    TodoState state,
    String sheetTitle,
  ) async {
    final l10n = AppLocalizations.of(context);
    final selectableLists = state.lists
        .where((l) => !l.isSmartList || l.smartType == SmartListType.tasks)
        .toList();

    return showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                sheetTitle,
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
  }

  Future<void> _batchCopyToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickTargetListSheet(state, l10n.copyTasks);
    if (picked == null || !mounted) return;
    ref
        .read(tasksActionPresenterProvider)
        .batchCopyToList(_multiSelectedIds, picked);
    _clearSelection();
  }

  Future<void> _batchMoveToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final picked = await _pickTargetListSheet(state, l10n.moveToList);
    if (picked == null || !mounted) return;
    ref
        .read(tasksActionPresenterProvider)
        .batchMoveToList(_multiSelectedIds, picked);
    _clearSelection();
  }

  Future<void> _duplicateListWithPrompt(
    TodoState state,
    TodoList currentList,
  ) async {
    final l10n = AppLocalizations.of(context);
    final notifier = ref.read(tasksViewPresenterProvider);
    final hasCompleted = currentList.showCompleted &&
        state.tasks.any((t) => t.listId == currentList.id && t.isCompleted);

    var keepCompleted = false;
    if (hasCompleted) {
      final choice = await showDialog<bool>(
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
      if (choice == null) return;
      keepCompleted = choice;
    }

    notifier.duplicateList(currentList.id, keepCompleted: keepCompleted);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.duplicateListSuccess)),
    );
  }

  Future<void> _batchDelete(bool confirmRequired) async {
    final l10n = AppLocalizations.of(context);
    if (confirmRequired) {
      final confirmed = await _confirmDialog(
        title: l10n.deleteTaskTitle,
        content: l10n.deleteSelectedConfirm(_multiSelectedIds.length),
        confirmLabel: l10n.delete,
        cancelLabel: l10n.cancel,
      );
      if (!confirmed) return;
    }
    ref.read(tasksActionPresenterProvider).batchDeleteTasks(_multiSelectedIds);
    _clearSelection();
  }

  PopupMenuItem<T> _buildPopupMenuItem<T>({
    required T value,
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return PopupMenuItem<T>(
      value: value,
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: color != null ? TextStyle(color: color) : null,
        ),
        contentPadding: EdgeInsets.zero,
        dense: true,
      ),
    );
  }

  List<PopupMenuEntry<_ListMenuAction>> _buildMenuItems(
    AppLocalizations l10n,
    TodoList list,
    bool showCompleted,
    int activeTasksCount,
  ) {
    final isCustom = !list.isSmartList;
    final supportsSort = isCustom ||
        list.smartType == SmartListType.myDay ||
        list.smartType == SmartListType.all ||
        list.smartType == SmartListType.tasks;
    final supportsReorder = (isCustom ||
            list.smartType == SmartListType.myDay ||
            list.smartType == SmartListType.tasks) &&
        list.sortOption == TaskSortOption.defaultOrder &&
        activeTasksCount >= 2;
    final supportsToggleCompleted = list.smartType != SmartListType.all &&
        list.smartType != SmartListType.completed;

    return [
      if (isCustom)
        _buildPopupMenuItem(
          value: _ListMenuAction.rename,
          icon: Icons.edit_outlined,
          label: l10n.renameList,
        ),
      if (supportsSort)
        _buildPopupMenuItem(
          value: _ListMenuAction.sort,
          icon: Icons.sort,
          label: l10n.sortBy,
        ),
      if (supportsReorder)
        _buildPopupMenuItem(
          value: _ListMenuAction.reorder,
          icon: Icons.reorder,
          label: l10n.reorderTasks,
        ),
      _buildPopupMenuItem(
        value: _ListMenuAction.changeTheme,
        icon: Icons.palette_outlined,
        label: l10n.changeTheme,
      ),
      if (supportsToggleCompleted)
        _buildPopupMenuItem(
          value: _ListMenuAction.toggleCompleted,
          icon: showCompleted
              ? Icons.visibility_off_outlined
              : Icons.check_circle_outline,
          label:
              showCompleted ? l10n.hideCompletedTasks : l10n.showCompletedTasks,
        ),
      if (isCustom) ...[
        _buildPopupMenuItem(
          value: _ListMenuAction.duplicate,
          icon: Icons.copy_outlined,
          label: l10n.duplicateList,
        ),
        const PopupMenuDivider(),
        _buildPopupMenuItem(
          value: _ListMenuAction.delete,
          icon: Icons.delete_outline,
          label: l10n.deleteList,
          color: TodoColors.overdueRed,
        ),
      ],
    ];
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
        if (result == null) return;
        notifier.updateList(
          currentList.id,
          title: result.title,
          emoji: result.emoji,
          clearEmoji: result.emoji == null,
          themeColor: result.themeColor,
          themePhoto: result.themePhoto,
          clearThemePhoto: result.themePhoto == null,
        );
      case _ListMenuAction.sort:
        await _showSortSheet(currentList);
      case _ListMenuAction.reorder:
        if (currentList.sortOption != TaskSortOption.defaultOrder) {
          notifier.setListSortOption(
            currentList.id,
            TaskSortOption.defaultOrder,
          );
        }
        _enterReordering();
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

  void _handleMultiSelectAction(
    _MultiSelectAction action,
    TodoState state,
    List<TaskItem> allTasks,
  ) {
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    switch (action) {
      case _MultiSelectAction.selectOrClearAll:
        final allSelected = allTasks.isNotEmpty &&
            allTasks.every((t) => _multiSelectedIds.contains(t.id));
        if (allSelected) {
          _clearSelection();
        } else {
          _selectAll(allTasks);
        }
      case _MultiSelectAction.important:
        actionPresenter.batchMarkImportant(_multiSelectedIds);
        _clearSelection();
      case _MultiSelectAction.move:
        _batchMoveToList(state);
      case _MultiSelectAction.copy:
        _batchCopyToList(state);
      case _MultiSelectAction.delete:
        _batchDelete(state.confirmBeforeDeleting);
    }
  }

  void _swipeDeleteTask(TaskItem task, List<TaskItem> allStateTasks) {
    final l10n = AppLocalizations.of(context);
    final presenter = ref.read(tasksViewPresenterProvider);
    final originalIndex = allStateTasks.indexWhere((t) => t.id == task.id);
    ref.read(tasksActionPresenterProvider).batchDeleteTasks({task.id});
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.taskDeleted),
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => presenter.restoreTask(task, index: originalIndex),
        ),
      ),
    );
  }

  Widget _buildTaskTile({
    required TaskItem task,
    required TodoState state,
    required Color accentColor,
    required bool showMyDayBadge,
    String? originListName,
  }) {
    final notifier = ref.read(tasksViewPresenterProvider);
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    final displayTask = _completionController.effectiveTask(task);
    final isCompletedSmartList =
        state.selectedList.smartType == SmartListType.completed;
    return SwipeableTaskCard(
      key: ValueKey('task_${task.id}'),
      enabled: _mode == _TasksViewMode.browsing,
      isInMyDay: task.isInMyDay,
      accentColor: accentColor,
      onSwipeRight: () =>
          actionPresenter.batchSetMyDay({task.id}, !task.isInMyDay),
      onSwipeLeft: () => _swipeDeleteTask(task, state.tasks),
      child: TaskListTile(
        task: displayTask,
        listName: originListName,
        showMyDayBadge: showMyDayBadge,
        accentColor: accentColor,
        isSelected: state.selectedTaskId == task.id,
        isMultiSelecting: _mode == _TasksViewMode.multiSelecting,
        isMultiSelected: _multiSelectedIds.contains(task.id),
        onTap: () {
          if (_mode == _TasksViewMode.multiSelecting) {
            _toggleSelection(task.id);
          } else {
            widget.onOpenTask(task);
          }
        },
        onLongPress: () => _toggleSelection(task.id),
        onToggleCompleted: () => _completionController.toggle(
          task,
          instant: isCompletedSmartList,
          onCommit: notifier.setTaskCompleted,
          onStateChanged: () {
            if (mounted) setState(() {});
          },
        ),
        onToggleImportant: () => notifier.toggleTaskImportant(task.id),
      ),
    );
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
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Icon(
                      Icons.keyboard_arrow_right,
                      color: headerFg,
                      size: 18,
                    ),
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

  PreferredSizeWidget? _buildAppBar({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> allTasks,
    required bool isDark,
  }) {
    return switch (_mode) {
      _TasksViewMode.browsing => null,
      _TasksViewMode.reordering => _buildReorderingAppBar(l10n, isDark),
      _TasksViewMode.multiSelecting => _buildMultiSelectAppBar(
          l10n: l10n,
          state: state,
          currentList: currentList,
          allTasks: allTasks,
          isDark: isDark,
        ),
    };
  }

  PreferredSizeWidget _buildReorderingAppBar(
    AppLocalizations l10n,
    bool isDark,
  ) {
    return AppBar(
      backgroundColor: isDark
          ? TodoColors.primaryBackgroundDark
          : TodoColors.secondaryTextLight,
      foregroundColor: Colors.white,
      leading: IconButton(
        onPressed: _exitReordering,
        icon: const Icon(Icons.arrow_back),
      ),
      title: Text(l10n.reorderTasks),
      actions: [
        IconButton(
          tooltip: l10n.done,
          onPressed: _exitReordering,
          icon: const Icon(Icons.check),
        ),
      ],
    );
  }

  PreferredSizeWidget _buildMultiSelectAppBar({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> allTasks,
    required bool isDark,
  }) {
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    final selectedTasks =
        state.tasks.where((t) => _multiSelectedIds.contains(t.id)).toList();
    final canBatchAddToMyDay = currentList.smartType != SmartListType.myDay &&
        selectedTasks.any((t) => !t.isInMyDay);
    final canBatchMarkImportant =
        currentList.smartType != SmartListType.important &&
            selectedTasks.any((t) => !t.isImportant);
    final allSelected = allTasks.isNotEmpty &&
        allTasks.every((t) => _multiSelectedIds.contains(t.id));

    return AppBar(
      backgroundColor: isDark
          ? TodoColors.primaryBackgroundDark
          : TodoColors.secondaryTextLight,
      foregroundColor: Colors.white,
      leading: IconButton(
        onPressed: _clearSelection,
        icon: const Icon(Icons.close),
      ),
      title: Text('${_multiSelectedIds.length}'),
      actions: [
        if (canBatchAddToMyDay)
          IconButton(
            tooltip: l10n.addToMyDay,
            onPressed: () {
              actionPresenter.batchAddToMyDay(_multiSelectedIds);
              _clearSelection();
            },
            icon: const Icon(Icons.wb_sunny_outlined),
          ),
        IconButton(
          tooltip: l10n.addDueDate,
          onPressed: () => _batchPickDueDate(state.startOfWeek),
          icon: const Icon(Icons.calendar_today_outlined),
        ),
        PopupMenuButton<_MultiSelectAction>(
          icon: const Icon(Icons.more_vert),
          tooltip: l10n.moreOptions,
          onSelected: (action) =>
              _handleMultiSelectAction(action, state, allTasks),
          itemBuilder: (_) => [
            _buildPopupMenuItem(
              value: _MultiSelectAction.selectOrClearAll,
              icon: allSelected ? Icons.deselect_outlined : Icons.select_all,
              label: allSelected ? l10n.clearAll : l10n.selectAll,
            ),
            if (canBatchMarkImportant)
              _buildPopupMenuItem(
                value: _MultiSelectAction.important,
                icon: Icons.star_outline,
                label: l10n.important,
              ),
            _buildPopupMenuItem(
              value: _MultiSelectAction.move,
              icon: Icons.drive_file_move_outlined,
              label: l10n.moveToList,
            ),
            _buildPopupMenuItem(
              value: _MultiSelectAction.copy,
              icon: Icons.copy_outlined,
              label: l10n.copyTasks,
            ),
            _buildPopupMenuItem(
              value: _MultiSelectAction.delete,
              icon: Icons.delete_outline,
              label: l10n.delete,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackground(TodoList currentList, LinearGradient gradient) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: currentList.themePhoto != null
          ? SizedBox.expand(
              key: ValueKey('bg_photo_${currentList.themePhoto!.name}'),
              child: Image.asset(
                TodoColors.photoAssetFor(currentList.themePhoto!),
                fit: BoxFit.cover,
              ),
            )
          : AnimatedContainer(
              key: const ValueKey('bg_gradient'),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(gradient: gradient),
            ),
    );
  }

  Widget _buildSliverAppBar({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required String listTitle,
    required String? subtitle,
    required Color headerFg,
    required LinearGradient gradient,
    required int activeTasksCount,
    required bool isDark,
  }) {
    return SliverAppBar(
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
        PopupMenuButton<_ListMenuAction>(
          icon: Icon(Icons.more_vert, color: headerFg),
          tooltip: l10n.moreOptions,
          onSelected: (action) => _handleMenuAction(action, state, currentList),
          itemBuilder: (context) => _buildMenuItems(
            l10n,
            currentList,
            currentList.showCompleted,
            activeTasksCount,
          ),
        ),
      ],
      flexibleSpace: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: currentList.themePhoto != null
                  ? Stack(
                      key: ValueKey(
                        'header_photo_${currentList.themePhoto!.name}',
                      ),
                      fit: StackFit.expand,
                      children: [
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
                      ],
                    )
                  : AnimatedContainer(
                      key: const ValueKey('header_color'),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      color: gradient.colors.first,
                    ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final topPadding = MediaQuery.paddingOf(context).top;
                final collapsedHeight = kToolbarHeight + topPadding;
                final expandedHeight =
                    (subtitle != null ? 144.0 : 116.0) + topPadding;
                final denom =
                    (expandedHeight - collapsedHeight).clamp(1.0, 200.0);
                final t = ((expandedHeight - constraints.maxHeight) / denom)
                    .clamp(0.0, 1.0);
                final startPad =
                    widget.onBackPressed != null ? 16.0 + 40.0 * t : 15.0;
                final bottomPad = subtitle != null ? 42.0 - 26.0 * t : 16.0;
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
                          alignment: AlignmentDirectional.bottomStart,
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
                                color: headerFg.withValues(alpha: 0.92),
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
    );
  }

  Widget _buildSortBanner({
    required AppLocalizations l10n,
    required TodoList currentList,
    required Color headerFg,
  }) {
    final notifier = ref.read(tasksViewPresenterProvider);
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                      onTap: () =>
                          notifier.toggleListSortDirection(currentList.id),
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
                                  _sortLabel(l10n, currentList.sortOption),
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
                            AnimatedRotation(
                              turns: currentList.sortAscending ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeInOut,
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                color: headerFg,
                                size: 18,
                              ),
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
    );
  }

  List<Widget> _buildTaskSlivers({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> activeTasks,
    required List<TaskItem> completedTasks,
    required Color accentColor,
    required Color headerFg,
  }) {
    if (activeTasks.isEmpty && completedTasks.isEmpty) {
      return const [SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    return [
      if (_mode == _TasksViewMode.reordering)
        _buildReorderableSliver(
          l10n: l10n,
          state: state,
          currentList: currentList,
          activeTasks: activeTasks,
          accentColor: accentColor,
        )
      else if (currentList.smartType == SmartListType.planned &&
          currentList.sortOption == TaskSortOption.defaultOrder)
        ..._buildPlannedBucketSlivers(
          l10n: l10n,
          state: state,
          currentList: currentList,
          activeTasks: activeTasks,
          accentColor: accentColor,
          headerFg: headerFg,
        )
      else if ((currentList.smartType == SmartListType.completed ||
              currentList.smartType == SmartListType.all) &&
          currentList.sortOption == TaskSortOption.defaultOrder)
        ..._buildListBucketSlivers(
          l10n: l10n,
          state: state,
          currentList: currentList,
          activeTasks: activeTasks,
          accentColor: accentColor,
          headerFg: headerFg,
        )
      else
        _buildFlatTaskSliver(
          l10n: l10n,
          state: state,
          currentList: currentList,
          activeTasks: activeTasks,
          accentColor: accentColor,
        ),
      if (completedTasks.isNotEmpty)
        ..._buildCompletedBucketSlivers(
          l10n: l10n,
          state: state,
          currentList: currentList,
          completedTasks: completedTasks,
          accentColor: accentColor,
          headerFg: headerFg,
        ),
    ];
  }

  Widget _buildReorderableSliver({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> activeTasks,
    required Color accentColor,
  }) {
    final notifier = ref.read(tasksViewPresenterProvider);
    final showMyDayBadge = currentList.smartType != SmartListType.myDay;
    final showOriginList = currentList.isSmartList &&
        currentList.smartType != SmartListType.tasks;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverReorderableList(
        itemCount: activeTasks.length,
        onReorderItem: (oldIndex, newIndex) =>
            notifier.reorderActiveTasks(activeTasks, oldIndex, newIndex),
        itemBuilder: (context, index) {
          final task = activeTasks[index];
          return Material(
            key: ValueKey(task.id),
            color: Colors.transparent,
            child: TaskListTile(
              task: task,
              listName: showOriginList
                  ? resolveOriginListName(l10n, state.lists, task.listId)
                  : null,
              showMyDayBadge: showMyDayBadge,
              accentColor: accentColor,
              isReordering: true,
              onTap: () {},
              onToggleCompleted: () {},
              onToggleImportant: () {},
              trailingHandle: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: index > 0
                        ? () => notifier.reorderActiveTasks(
                              activeTasks,
                              index,
                              index - 1,
                            )
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: index < activeTasks.length - 1
                        ? () => notifier.reorderActiveTasks(
                              activeTasks,
                              index,
                              index + 1,
                            )
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_down),
                    visualDensity: VisualDensity.compact,
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildPlannedBucketSlivers({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> activeTasks,
    required Color accentColor,
    required Color headerFg,
  }) {
    final groups = groupPlannedTasks(activeTasks, state.startOfWeek);
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: _buildBucketPill(
            label: _plannedBucketLabel(l10n, group.bucket),
            count: group.tasks.length,
            isExpanded: !_collapsedPlannedBuckets.contains(group.bucket.name),
            onTap: () =>
                _toggleBucket(_collapsedPlannedBuckets, group.bucket.name),
            currentList: currentList,
            headerFg: headerFg,
          ),
        ),
        if (!_collapsedPlannedBuckets.contains(group.bucket.name))
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final task = group.tasks[index];
                  return _buildTaskTile(
                    task: task,
                    state: state,
                    accentColor: accentColor,
                    showMyDayBadge: true,
                    originListName: resolveOriginListName(
                      l10n,
                      state.lists,
                      task.listId,
                    ),
                  );
                },
                childCount: group.tasks.length,
              ),
            ),
          ),
      ],
    ];
  }

  List<Widget> _buildListBucketSlivers({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> activeTasks,
    required Color accentColor,
    required Color headerFg,
  }) {
    final groups = groupTasksByList(l10n, activeTasks, state.lists);
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: _buildBucketPill(
            label: group.title,
            count: group.tasks.length,
            isExpanded: !_collapsedCompletedListBuckets.contains(group.listId),
            onTap: () =>
                _toggleBucket(_collapsedCompletedListBuckets, group.listId),
            currentList: currentList,
            headerFg: headerFg,
          ),
        ),
        if (!_collapsedCompletedListBuckets.contains(group.listId))
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildTaskTile(
                  task: group.tasks[index],
                  state: state,
                  accentColor: accentColor,
                  showMyDayBadge: true,
                ),
                childCount: group.tasks.length,
              ),
            ),
          ),
      ],
    ];
  }

  Widget _buildFlatTaskSliver({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> activeTasks,
    required Color accentColor,
  }) {
    final isMyDay = currentList.smartType == SmartListType.myDay;
    final showOriginList = currentList.isSmartList &&
        currentList.smartType != SmartListType.tasks;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final task = activeTasks[index];
            return _buildTaskTile(
              task: task,
              state: state,
              accentColor: accentColor,
              showMyDayBadge: !isMyDay,
              originListName: showOriginList
                  ? resolveOriginListName(l10n, state.lists, task.listId)
                  : null,
            );
          },
          childCount: activeTasks.length,
        ),
      ),
    );
  }

  List<Widget> _buildCompletedBucketSlivers({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> completedTasks,
    required Color accentColor,
    required Color headerFg,
  }) {
    return [
      SliverToBoxAdapter(
        child: _buildBucketPill(
          label: l10n.completed,
          count: completedTasks.length,
          isExpanded: _completedExpanded,
          onTap: () => setState(() => _completedExpanded = !_completedExpanded),
          currentList: currentList,
          headerFg: headerFg,
        ),
      ),
      if (_completedExpanded)
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final task = completedTasks[index];
                final showOriginList = currentList.isSmartList &&
                    currentList.smartType != SmartListType.tasks;
                return _buildTaskTile(
                  task: task,
                  state: state,
                  accentColor: accentColor,
                  showMyDayBadge: currentList.smartType != SmartListType.myDay,
                  originListName: showOriginList
                      ? resolveOriginListName(l10n, state.lists, task.listId)
                      : null,
                );
              },
              childCount: completedTasks.length,
            ),
          ),
        ),
    ];
  }

  Widget _buildRuledLinesSliver(TodoList currentList, bool isDark) {
    final useLightLines = currentList.themePhoto == null &&
        TodoColors.isLightTheme(currentList.themeColor) &&
        !isDark;
    return SliverFillRemaining(
      hasScrollBody: false,
      fillOverscroll: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 84),
        child: CustomPaint(
          painter: RuledLinesPainter(
            lineColor: useLightLines
                ? TodoColors.taskViewDividerLight
                : TodoColors.taskViewDividerDark,
            rowHeight: 54.0,
            horizontalInset: 8.0,
          ),
        ),
      ),
    );
  }

  Widget _buildScrollShadow(String? subtitle) {
    final maxTop = subtitle != null ? 144.0 : 116.0;
    return Positioned(
      top: (maxTop - _scrollOffset).clamp(kToolbarHeight, maxTop),
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: (_scrollOffset > 4 && _mode != _TasksViewMode.multiSelecting)
              ? 1.0
              : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 3,
            decoration: TodoColors.horizontalShadowDecoration,
          ),
        ),
      ),
    );
  }

  Widget _buildFab({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required Brightness brightness,
    required bool isDark,
  }) {
    final hideFab = _mode != _TasksViewMode.browsing ||
        currentList.smartType == SmartListType.completed;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: hideFab
          ? const SizedBox.shrink(key: ValueKey('fab_hidden'))
          : FloatingActionButton(
              key: const ValueKey('fab_visible'),
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final currentList = state.selectedList;

    final baseTitle = localizedListTitle(l10n, currentList);
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
    final (:active, :completed) = splitTasksForDisplay(allTasks, currentList);
    final subtitle = currentList.smartType == SmartListType.myDay
        ? DateFormat.MMMMEEEEd().format(DateTime.now())
        : null;

    return PopScope(
      canPop: _mode == _TasksViewMode.browsing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        switch (_mode) {
          case _TasksViewMode.browsing:
            break;
          case _TasksViewMode.reordering:
            _exitReordering();
          case _TasksViewMode.multiSelecting:
            _clearSelection();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(
          l10n: l10n,
          state: state,
          currentList: currentList,
          allTasks: allTasks,
          isDark: isDark,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(currentList, gradient),
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
                        if (_mode == _TasksViewMode.browsing)
                          _buildSliverAppBar(
                            l10n: l10n,
                            state: state,
                            currentList: currentList,
                            listTitle: listTitle,
                            subtitle: subtitle,
                            headerFg: headerFg,
                            gradient: gradient,
                            activeTasksCount: active.length,
                            isDark: isDark,
                          )
                        else if (_mode == _TasksViewMode.multiSelecting ||
                            _mode == _TasksViewMode.reordering)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    listTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: headerFg,
                                      fontWeight: FontWeight.w500,
                                      fontSize: 30,
                                    ),
                                  ),
                                  if (subtitle != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: headerFg.withValues(alpha: 0.92),
                                        fontSize: 20,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        if (currentList.sortOption !=
                                TaskSortOption.defaultOrder &&
                            _mode != _TasksViewMode.reordering)
                          _buildSortBanner(
                            l10n: l10n,
                            currentList: currentList,
                            headerFg: headerFg,
                          ),
                        ..._buildTaskSlivers(
                          l10n: l10n,
                          state: state,
                          currentList: currentList,
                          activeTasks: active,
                          completedTasks: completed,
                          accentColor: accentColor,
                          headerFg: headerFg,
                        ),
                        _buildRuledLinesSliver(currentList, isDark),
                      ],
                    ),
                  ),
                  _buildScrollShadow(subtitle),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: _buildFab(
          l10n: l10n,
          state: state,
          currentList: currentList,
          brightness: brightness,
          isDark: isDark,
        ),
      ),
    );
  }
}
