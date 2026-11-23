import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../account/account_provider.dart';
import '../data/todo_provider.dart';
import '../detailview/recurrence/task_pickers.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../sync/sync_provider.dart';
import '../theme/theme_picker_sheet.dart';
import '../theme/todo_theme.dart';
import '../view/delayed_task_completion.dart';
import 'completion_sound_service.dart';
import 'recyclerview/animated_task_sliver_list.dart';
import 'recyclerview/ruled_lines_painter.dart';
import 'recyclerview/swipeable_task_card.dart';
import 'recyclerview/task_list_tile.dart';
import 'renamelist/list_editor_dialog.dart';
import 'richentry/task_entry_sheet.dart';
import 'tasks_action_presenter.dart';
import 'tasks_view_bars.dart';
import 'tasks_view_dialogs.dart';
import 'tasks_view_grouping.dart';
import 'tasks_view_presenter.dart';

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
  TasksViewMode _mode = TasksViewMode.browsing;
  double _scrollOffset = 0.0;
  bool _isSnappingHeader = false;
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<Set<String>> _selectionNotifier = ValueNotifier(const {});
  Set<String> get _multiSelectedIds => _selectionNotifier.value;
  String? _draggingTaskId;
  int? _dragStartIndex;
  double? _dragPointerStartY;
  final Set<String> _collapsedPlannedBuckets = {};
  final Set<String> _collapsedCompletedListBuckets = {};
  final _completionController = DelayedTaskCompletionController();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  late final TasksViewPresenter _presenter;

  @override
  void initState() {
    super.initState();
    _presenter = ref.read(tasksViewPresenterProvider);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _selectionNotifier.dispose();
    _completionController.flushAndDispose(_presenter.setTaskCompleted);
    super.dispose();
  }

  void _snapHeaderIfNeeded(double collapseDelta) {
    if (_isSnappingHeader ||
        collapseDelta <= 0 ||
        !_scrollController.hasClients) {
      return;
    }
    final offset = _scrollController.offset;
    if (offset <= 0.5 || offset >= collapseDelta - 0.5) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final target = (offset >= collapseDelta / 2 ? collapseDelta : 0.0).clamp(
      0.0,
      maxScroll,
    );
    if ((target - offset).abs() <= 0.5) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients || _isSnappingHeader) {
        return;
      }
      _isSnappingHeader = true;
      _scrollController
          .animateTo(
            target,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _isSnappingHeader = false);
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients || _scrollController.offset <= 0) {
      return;
    }
    _isSnappingHeader = true;
    _scrollController
        .animateTo(
          0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _isSnappingHeader = false);
  }

  void _enterReordering() {
    _selectionNotifier.value = const {};
    setState(() {
      _mode = TasksViewMode.reordering;
    });
  }

  void _exitReordering() {
    setState(() => _mode = TasksViewMode.browsing);
  }

  void _toggleSelection(String taskId) {
    final next = Set<String>.from(_multiSelectedIds);
    if (!next.remove(taskId)) {
      next.add(taskId);
    }
    _selectionNotifier.value = Set<String>.unmodifiable(next);
    setState(() {
      _mode = next.isEmpty
          ? TasksViewMode.browsing
          : TasksViewMode.multiSelecting;
    });
  }

  void _clearSelection() {
    _selectionNotifier.value = const {};
    setState(() {
      _mode = TasksViewMode.browsing;
    });
  }

  void _selectAll(List<TaskItem> tasks) {
    final next = Set<String>.from(_multiSelectedIds)
      ..addAll(tasks.map((t) => t.id));
    _selectionNotifier.value = Set<String>.unmodifiable(next);
    setState(() {
      _mode = next.isEmpty
          ? TasksViewMode.browsing
          : TasksViewMode.multiSelecting;
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
        onSubmit:
            ({
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

  Future<void> _confirmDeleteList(TodoList list, bool confirmRequired) async {
    final l10n = AppLocalizations.of(context);
    if (confirmRequired) {
      final confirmed = await showTasksConfirmDialog(
        context: context,
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

  Future<void> _batchCopyToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final picked = await pickTargetListSheet(
      context: context,
      state: state,
      sheetTitle: l10n.copyTasks,
    );
    if (picked == null || !mounted) return;
    ref
        .read(tasksActionPresenterProvider)
        .batchCopyToList(_multiSelectedIds, picked);
    _clearSelection();
  }

  Future<void> _batchMoveToList(TodoState state) async {
    final l10n = AppLocalizations.of(context);
    final picked = await pickTargetListSheet(
      context: context,
      state: state,
      sheetTitle: l10n.moveToList,
    );
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
    final hasCompleted = state.tasks.any(
      (t) => t.listId == currentList.id && t.isCompleted,
    );

    var keepCompleted = false;
    if (hasCompleted) {
      final choice = await promptKeepCompletedOnDuplicate(context);
      if (choice == null) return;
      keepCompleted = choice;
    }

    notifier.duplicateList(currentList.id, keepCompleted: keepCompleted);
    if (!mounted) return;
    _scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(l10n.duplicateListSuccess)),
    );
  }

  Future<void> _batchDelete(bool confirmRequired) async {
    final l10n = AppLocalizations.of(context);
    if (confirmRequired) {
      final confirmed = await showTasksConfirmDialog(
        context: context,
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

  Future<void> _handleMenuAction(
    ListMenuAction action,
    TodoState state,
    TodoList currentList,
  ) async {
    final notifier = ref.read(tasksViewPresenterProvider);
    final l10n = AppLocalizations.of(context);
    switch (action) {
      case ListMenuAction.rename:
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
      case ListMenuAction.sort:
        await showTasksSortSheet(
          context: context,
          currentList: currentList,
          onSelectSortOption: (option) =>
              notifier.setListSortOption(currentList.id, option),
        );
      case ListMenuAction.groupBy:
        await showPlannedGroupSheet(
          context: context,
          currentOption: state.plannedGroupOption,
          onSelectGroupOption: notifier.setPlannedGroupOption,
        );
      case ListMenuAction.reorder:
        if (currentList.sortOption != TaskSortOption.defaultOrder) {
          notifier.setListSortOption(
            currentList.id,
            TaskSortOption.defaultOrder,
          );
        }
        _enterReordering();
      case ListMenuAction.changeTheme:
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
      case ListMenuAction.duplicate:
        await _duplicateListWithPrompt(state, currentList);
      case ListMenuAction.delete:
        await _confirmDeleteList(currentList, state.confirmBeforeDeleting);
    }
  }

  void _handleMultiSelectAction(
    MultiSelectAction action,
    TodoState state,
    List<TaskItem> allTasks,
  ) {
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    switch (action) {
      case MultiSelectAction.selectOrClearAll:
        final allSelected =
            allTasks.isNotEmpty &&
            allTasks.every((t) => _multiSelectedIds.contains(t.id));
        if (allSelected) {
          _clearSelection();
        } else {
          _selectAll(allTasks);
        }
      case MultiSelectAction.important:
        actionPresenter.batchMarkImportant(_multiSelectedIds);
        _clearSelection();
      case MultiSelectAction.move:
        _batchMoveToList(state);
      case MultiSelectAction.copy:
        _batchCopyToList(state);
      case MultiSelectAction.delete:
        _batchDelete(state.confirmBeforeDeleting);
    }
  }

  void _swipeDeleteTask(TaskItem task, List<TaskItem> allStateTasks) {
    final l10n = AppLocalizations.of(context);
    final presenter = ref.read(tasksViewPresenterProvider);
    final originalIndex = allStateTasks.indexWhere((t) => t.id == task.id);
    ref.read(tasksActionPresenterProvider).batchDeleteTasks({task.id});
    final messenger = _scaffoldMessengerKey.currentState;
    messenger?.clearSnackBars();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(l10n.taskDeleted),
        persist: false,
        duration: const Duration(seconds: 4),
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
    bool enableLongPress = true,
  }) {
    final notifier = ref.read(tasksViewPresenterProvider);
    final actionPresenter = ref.read(tasksActionPresenterProvider);
    final displayTask = _completionController.effectiveTask(task);
    final isCompletedSmartList =
        state.selectedList.smartType == SmartListType.completed;
    return SwipeableTaskCard(
      key: ValueKey('task_${task.id}'),
      enabled: _mode == TasksViewMode.browsing,
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
        isMultiSelecting: _mode == TasksViewMode.multiSelecting,
        isMultiSelected: _multiSelectedIds.contains(task.id),
        onTap: () {
          if (_mode == TasksViewMode.multiSelecting) {
            _toggleSelection(task.id);
          } else {
            widget.onOpenTask(task);
          }
        },
        onLongPress: enableLongPress ? () => _toggleSelection(task.id) : null,
        onToggleCompleted: () {
          if (!task.isCompleted && !_completionController.isPending(task.id)) {
            ref.read(completionSoundServiceProvider).playIfEnabled();
          }
          _completionController.toggle(
            task,
            instant: isCompletedSmartList,
            onCommit: notifier.setTaskCompleted,
            onStateChanged: () {
              if (mounted) setState(() {});
            },
          );
        },
        onToggleImportant: () => notifier.toggleTaskImportant(task.id),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar({
    required AppLocalizations l10n,
    required TodoState state,
    required TodoList currentList,
    required List<TaskItem> allTasks,
    required bool isDark,
    required SystemUiOverlayStyle overlayStyle,
  }) {
    return switch (_mode) {
      TasksViewMode.browsing => null,
      TasksViewMode.reordering => buildReorderingAppBar(
        l10n: l10n,
        isDark: isDark,
        overlayStyle: overlayStyle,
        onExitReordering: _exitReordering,
      ),
      TasksViewMode.multiSelecting => buildMultiSelectAppBar(
        l10n: l10n,
        state: state,
        currentList: currentList,
        allTasks: allTasks,
        multiSelectedIds: _multiSelectedIds,
        isDark: isDark,
        overlayStyle: overlayStyle,
        onClearSelection: _clearSelection,
        onBatchAddToMyDay: () {
          ref
              .read(tasksActionPresenterProvider)
              .batchAddToMyDay(_multiSelectedIds);
          _clearSelection();
        },
        onBatchPickDueDate: () => _batchPickDueDate(state.startOfWeek),
        onSelectAction: (action) =>
            _handleMultiSelectAction(action, state, allTasks),
      ),
    };
  }

  Widget _buildBackground(TodoList currentList, Color backgroundColor) {
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
          : SizedBox.expand(
              key: const ValueKey('bg_color'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                color: backgroundColor,
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
      if (_mode == TasksViewMode.reordering)
        _buildReorderableSliver(
          l10n: l10n,
          state: state,
          currentList: currentList,
          activeTasks: activeTasks,
          accentColor: accentColor,
        )
      else if (currentList.smartType == SmartListType.planned &&
          currentList.sortOption == TaskSortOption.defaultOrder)
        ...switch (state.plannedGroupOption) {
          PlannedGroupOption.byDueDate => _buildPlannedBucketSlivers(
            l10n: l10n,
            state: state,
            currentList: currentList,
            activeTasks: activeTasks,
            accentColor: accentColor,
            headerFg: headerFg,
          ),
          PlannedGroupOption.byList => _buildListBucketSlivers(
            l10n: l10n,
            state: state,
            currentList: currentList,
            activeTasks: activeTasks,
            accentColor: accentColor,
            headerFg: headerFg,
          ),
          PlannedGroupOption.ungroup => [
            _buildFlatTaskSliver(
              l10n: l10n,
              state: state,
              currentList: currentList,
              activeTasks: activeTasks,
              accentColor: accentColor,
            ),
          ],
        }
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
    final showOriginList =
        currentList.isSmartList && currentList.smartType != SmartListType.tasks;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: AnimatedReorderableTaskSliver(
        tasks: activeTasks,
        onReorder: (oldIndex, newIndex) =>
            notifier.reorderActiveTasks(activeTasks, oldIndex, newIndex),
        itemBuilder: (context, index, task, onAnimatedStep) {
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
                        ? () => onAnimatedStep(index, index - 1)
                        : null,
                    icon: const Icon(Icons.keyboard_arrow_up),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    onPressed: index < activeTasks.length - 1
                        ? () => onAnimatedStep(index, index + 1)
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
          child: TasksBucketPill(
            label: plannedBucketLabel(l10n, group.bucket),
            count: group.tasks.length,
            isExpanded: !_collapsedPlannedBuckets.contains(group.bucket.name),
            onTap: () =>
                _toggleBucket(_collapsedPlannedBuckets, group.bucket.name),
            currentList: currentList,
            headerFg: headerFg,
          ),
        ),
        CollapsibleTaskBucketSliver(
          key: ValueKey('planned_${group.bucket.name}'),
          isExpanded: !_collapsedPlannedBuckets.contains(group.bucket.name),
          tasks: group.tasks,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemBuilder: (context, task) => _buildTaskTile(
            task: task,
            state: state,
            accentColor: accentColor,
            showMyDayBadge: true,
            originListName: resolveOriginListName(
              l10n,
              state.lists,
              task.listId,
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
          child: TasksBucketPill(
            label: group.title,
            count: group.tasks.length,
            isExpanded: !_collapsedCompletedListBuckets.contains(group.listId),
            onTap: () =>
                _toggleBucket(_collapsedCompletedListBuckets, group.listId),
            currentList: currentList,
            headerFg: headerFg,
          ),
        ),
        CollapsibleTaskBucketSliver(
          key: ValueKey('bucket_${currentList.id}_${group.listId}'),
          isExpanded: !_collapsedCompletedListBuckets.contains(group.listId),
          tasks: group.tasks,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemBuilder: (context, task) => _buildTaskTile(
            task: task,
            state: state,
            accentColor: accentColor,
            showMyDayBadge: true,
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
    final showOriginList =
        currentList.isSmartList && currentList.smartType != SmartListType.tasks;
    final canDragReorder =
        supportsTaskReordering(currentList, activeTasks.length) &&
        (_mode == TasksViewMode.browsing || _draggingTaskId != null);

    if (canDragReorder) {
      final notifier = ref.read(tasksViewPresenterProvider);
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: AnimatedReorderableTaskSliver(
          key: ValueKey('flat_reorder_${currentList.id}'),
          tasks: activeTasks,
          proxyDecorator: (child, index, animation) {
            final task = activeTasks[index];
            return ValueListenableBuilder<Set<String>>(
              valueListenable: _selectionNotifier,
              builder: (context, selectedIds, _) => Material(
                elevation: 4,
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                child: HeroMode(
                  enabled: false,
                  child: _buildTaskTile(
                    task: task,
                    state: state,
                    accentColor: accentColor,
                    showMyDayBadge: !isMyDay,
                    originListName: showOriginList
                        ? resolveOriginListName(l10n, state.lists, task.listId)
                        : null,
                    enableLongPress: false,
                  ),
                ),
              ),
            );
          },
          onReorderStart: (index) {
            final taskId = activeTasks[index].id;
            _draggingTaskId = taskId;
            _dragStartIndex = index;
            _toggleSelection(taskId);
          },
          onReorder: (oldIndex, newIndex) {
            _draggingTaskId = null;
            _dragStartIndex = null;
            _dragPointerStartY = null;
            notifier.reorderActiveTasks(activeTasks, oldIndex, newIndex);
            if (_mode == TasksViewMode.multiSelecting && mounted) {
              _clearSelection();
            }
          },
          onReorderEnd: (insertIndex) {
            final startIndex = _dragStartIndex;
            final adjustedNew =
                startIndex != null && insertIndex > startIndex
                ? insertIndex - 1
                : insertIndex;
            final willReorder =
                startIndex != null && adjustedNew != startIndex;
            if (willReorder) {
              // Keep _draggingTaskId non-null until onReorder fires after the
              // drop animation so AnimatedReorderableTaskSliver stays mounted.
              if (_mode == TasksViewMode.multiSelecting && mounted) {
                _clearSelection();
              }
              return;
            }
            _draggingTaskId = null;
            _dragStartIndex = null;
            _dragPointerStartY = null;
            if (mounted) setState(() {});
          },
          itemBuilder: (context, index, task, _) =>
              ReorderableDelayedDragStartListener(
                key: ValueKey('drag_${task.id}'),
                index: index,
                child: _buildTaskTile(
                  task: task,
                  state: state,
                  accentColor: accentColor,
                  showMyDayBadge: !isMyDay,
                  originListName: showOriginList
                      ? resolveOriginListName(l10n, state.lists, task.listId)
                      : null,
                  enableLongPress: false,
                ),
              ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: AnimatedTaskSliverList(
        key: ValueKey('flat_${currentList.id}'),
        tasks: activeTasks,
        itemBuilder: (context, task) => _buildTaskTile(
          task: task,
          state: state,
          accentColor: accentColor,
          showMyDayBadge: !isMyDay,
          originListName: showOriginList
              ? resolveOriginListName(l10n, state.lists, task.listId)
              : null,
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
    final hasCompleted = completedTasks.isNotEmpty;
    final completedExpanded = state.isCompletedExpanded(currentList.id);
    final showItems = hasCompleted && completedExpanded;
    return [
      SliverToBoxAdapter(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: AnimatedOpacity(
            opacity: hasCompleted ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
            child: hasCompleted
                ? TasksBucketPill(
                    label: l10n.completed,
                    count: completedTasks.length,
                    isExpanded: completedExpanded,
                    onTap: () => ref
                        .read(todoProvider.notifier)
                        .setCompletedExpanded(
                          currentList.id,
                          !completedExpanded,
                        ),
                    currentList: currentList,
                    headerFg: headerFg,
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ),
      CollapsibleTaskBucketSliver(
        key: ValueKey('completed_${currentList.id}'),
        isExpanded: showItems,
        tasks: completedTasks,
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
        itemBuilder: (context, task) {
          final showOriginList =
              currentList.isSmartList &&
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
      ),
    ];
  }

  Widget _buildRuledLinesSliver(
    TodoList currentList,
    bool isDark, {
    required double collapseDelta,
  }) {
    final useLightLines =
        currentList.themePhoto == null &&
        TodoColors.isLightTheme(currentList.themeColor) &&
        !isDark;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            (constraints.viewportMainAxisExtent +
                    collapseDelta -
                    constraints.precedingScrollExtent)
                .clamp(84.0, double.infinity);
        return SliverFillRemaining(
          hasScrollBody: false,
          fillOverscroll: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: CustomPaint(
              painter: RuledLinesPainter(
                lineColor: useLightLines
                    ? TodoColors.taskViewDividerLight
                    : TodoColors.taskViewDividerDark,
                rowHeight: 66.0,
                horizontalInset: 8.0,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the overscroll indicator for the task list around [child].
  ///
  /// [child] contains both the scroll view and the header shadow overlay. The
  /// indicator has to sit above that stack, otherwise the Android stretch
  /// overscroll effect only transforms the scroll view while the shadow stays
  /// put and appears to float over the list. The scroll view would add its own
  /// indicator internally, so that one is suppressed.
  Widget _buildOverscrollIndicator(BuildContext context, Widget child) {
    final behavior = ScrollConfiguration.of(context);
    return behavior.buildOverscrollIndicator(
      context,
      NotificationListener<OverscrollIndicatorNotification>(
        onNotification: (notification) {
          notification.disallowIndicator();
          return false;
        },
        child: child,
      ),
      ScrollableDetails.vertical(
        controller: _scrollController,
        decorationClipBehavior: Clip.hardEdge,
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
          opacity: (_scrollOffset > 4 && _mode != TasksViewMode.multiSelecting)
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
    final hideFab =
        _mode != TasksViewMode.browsing ||
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
    final notifier = ref.read(tasksViewPresenterProvider);

    final baseTitle = localizedListTitle(l10n, currentList);
    final listTitle =
        (currentList.emoji != null && currentList.emoji!.isNotEmpty)
        ? '${currentList.emoji!} $baseTitle'
        : baseTitle;
    final accentColor = currentList.themePhoto != null
        ? TodoColors.photoFabBackgroundFor(currentList.themePhoto!)
        : TodoColors.accentFor(currentList.themeColor, brightness: brightness);
    final backgroundColor = TodoColors.backgroundColorFor(
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
    final overlayStyle = switch (_mode) {
      TasksViewMode.browsing =>
        currentList.themePhoto != null
            ? TodoTheme.systemUiOverlayStyleForBrightness(Brightness.dark)
            : TodoTheme.systemUiOverlayStyleFor(backgroundColor),
      TasksViewMode.reordering ||
      TasksViewMode.multiSelecting => TodoTheme.systemUiOverlayStyleFor(
        isDark
            ? TodoColors.primaryBackgroundDark
            : TodoColors.secondaryTextLight,
      ),
    };

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: _mode == TasksViewMode.browsing,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          switch (_mode) {
            case TasksViewMode.browsing:
              break;
            case TasksViewMode.reordering:
              _exitReordering();
            case TasksViewMode.multiSelecting:
              _clearSelection();
          }
        },
        child: ScaffoldMessenger(
          key: _scaffoldMessengerKey,
          child: Scaffold(
            appBar: _buildAppBar(
              l10n: l10n,
              state: state,
              currentList: currentList,
              allTasks: allTasks,
              isDark: isDark,
              overlayStyle: overlayStyle,
            ),
            body: Stack(
              fit: StackFit.expand,
              children: [
                _buildBackground(currentList, backgroundColor),
                SafeArea(
                  bottom: false,
                  child: _buildOverscrollIndicator(
                    context,
                    Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.depth != 0) return false;
                            final offset = notification.metrics.pixels;
                            if ((offset - _scrollOffset).abs() > 0.5) {
                              setState(() => _scrollOffset = offset);
                            }
                            if (notification is ScrollEndNotification) {
                              final collapseDelta =
                                  (subtitle != null ? 144.0 : 116.0) -
                                  kToolbarHeight;
                              _snapHeaderIfNeeded(collapseDelta);
                            }
                            return false;
                          },
                          child: Builder(
                            builder: (context) {
                              final isMicrosoft = ref.watch(
                                accountProvider.select(
                                  (s) => s.activeAccount?.isMicrosoft ?? false,
                                ),
                              );
                              final scrollView = Listener(
                                onPointerDown: (event) =>
                                    _dragPointerStartY = event.position.dy,
                                onPointerMove: (event) {
                                  if (_draggingTaskId != null &&
                                      _mode == TasksViewMode.multiSelecting &&
                                      _dragPointerStartY != null &&
                                      (event.position.dy - _dragPointerStartY!)
                                              .abs() >
                                          18) {
                                    _clearSelection();
                                  }
                                },
                                child: CustomScrollView(
                                  controller: _scrollController,
                                  physics: isMicrosoft
                                      ? const AlwaysScrollableScrollPhysics()
                                      : null,
                                  slivers: [
                                  if (_mode == TasksViewMode.browsing)
                                    TasksSliverAppBar(
                                      l10n: l10n,
                                      currentList: currentList,
                                      listTitle: listTitle,
                                      subtitle: subtitle,
                                      headerFg: headerFg,
                                      backgroundColor: backgroundColor,
                                      activeTasksCount: active.length,
                                      isDark: isDark,
                                      overlayStyle: overlayStyle,
                                      onBackPressed: widget.onBackPressed,
                                      onScrollToTop: _scrollToTop,
                                      onSelectMenuAction: (action) =>
                                          _handleMenuAction(
                                            action,
                                            state,
                                            currentList,
                                          ),
                                    )
                                  else if (_mode ==
                                          TasksViewMode.multiSelecting ||
                                      _mode == TasksViewMode.reordering)
                                    SliverToBoxAdapter(
                                      child: SizedBox(
                                        height: subtitle != null ? 88.0 : 60.0,
                                        child: Stack(
                                          children: [
                                            Align(
                                              alignment: AlignmentDirectional
                                                  .bottomStart,
                                              child: Padding(
                                                padding:
                                                    EdgeInsetsDirectional.only(
                                                      start:
                                                          widget.onBackPressed !=
                                                              null
                                                          ? 16.0
                                                          : 15.0,
                                                      bottom: subtitle != null
                                                          ? 42.0
                                                          : 16.0,
                                                      end: 56,
                                                    ),
                                                child: Transform.scale(
                                                  scale: 1.5,
                                                  alignment:
                                                      AlignmentDirectional
                                                          .bottomStart,
                                                  child: DefaultTextStyle(
                                                    style:
                                                        Theme.of(context)
                                                            .primaryTextTheme
                                                            .titleLarge ??
                                                        const TextStyle(),
                                                    child: Text(
                                                      listTitle,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: headerFg,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                        fontSize: 20,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                            if (subtitle != null)
                                              Align(
                                                alignment: AlignmentDirectional
                                                    .bottomStart,
                                                child: Padding(
                                                  padding:
                                                      EdgeInsetsDirectional.only(
                                                        start:
                                                            widget.onBackPressed !=
                                                                null
                                                            ? 16.0
                                                            : 15.0,
                                                        bottom: 10.0,
                                                        end: 56,
                                                      ),
                                                  child: Text(
                                                    subtitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: headerFg
                                                          .withValues(
                                                            alpha: 0.92,
                                                          ),
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.w400,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  if (currentList.sortOption !=
                                          TaskSortOption.defaultOrder &&
                                      _mode != TasksViewMode.reordering)
                                    TasksSortBanner(
                                      l10n: l10n,
                                      currentList: currentList,
                                      headerFg: headerFg,
                                      onToggleSortDirection: () =>
                                          notifier.toggleListSortDirection(
                                            currentList.id,
                                          ),
                                      onClearSort: () =>
                                          notifier.setListSortOption(
                                            currentList.id,
                                            TaskSortOption.defaultOrder,
                                          ),
                                    ),
                                  if (currentList.smartType ==
                                          SmartListType.planned &&
                                      _mode == TasksViewMode.browsing)
                                    TasksPlannedFilterBanner(
                                      l10n: l10n,
                                      currentList: currentList,
                                      currentFilter: state.plannedDueDateFilter,
                                      headerFg: headerFg,
                                      onTap: () => showPlannedFilterSheet(
                                        context: context,
                                        currentFilter:
                                            state.plannedDueDateFilter,
                                        onSelectFilter:
                                            notifier.setPlannedDueDateFilter,
                                      ),
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
                                  _buildRuledLinesSliver(
                                    currentList,
                                    isDark,
                                    collapseDelta:
                                        (subtitle != null ? 144.0 : 116.0) -
                                        kToolbarHeight,
                                  ),
                                  ],
                                ),
                              );
                              if (!isMicrosoft ||
                                  _mode == TasksViewMode.reordering) {
                                return scrollView;
                              }
                              return RefreshIndicator(
                                onRefresh: () =>
                                    ref.read(syncProvider.notifier).syncNow(),
                                color: accentColor,
                                backgroundColor: isDark
                                    ? TodoColors.primaryBackgroundDark
                                    : TodoColors.primaryBackgroundLight,
                                child: scrollView,
                              );
                            },
                          ),
                        ),
                        _buildScrollShadow(subtitle),
                      ],
                    ),
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
        ),
      ),
    );
  }
}
