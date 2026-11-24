import 'dart:async';

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
import 'renamelist/list_editor_dialog.dart';
import 'richentry/task_entry_sheet.dart';
import 'tasks_action_presenter.dart';
import 'tasks_view_bars.dart';
import 'tasks_view_dialogs.dart';
import 'tasks_view_grouping.dart';
import 'tasks_view_presenter.dart';
import 'tasks_view_scroll_body.dart';
import 'tasks_view_slivers.dart';
import 'tasks_view_widgets.dart';

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

class _TasksViewScreenState extends ConsumerState<TasksViewScreen>
    with WidgetsBindingObserver {
  TasksViewMode _mode = TasksViewMode.browsing;
  double _scrollOffset = 0.0;
  bool _isSnappingHeader = false;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<NestedScrollViewState> _nestedScrollKey =
      GlobalKey<NestedScrollViewState>();
  final ValueNotifier<Set<String>> _selectionNotifier = ValueNotifier(const {});
  Set<String> get _multiSelectedIds => _selectionNotifier.value;
  String? _draggingTaskId;
  int? _dragStartIndex;
  double? _dragPointerStartY;
  double? _dragPointerY;
  double _dragVisibleTop = 0.0;
  Timer? _dragAutoScrollTimer;
  final Set<String> _collapsedPlannedBuckets = {};
  final Set<String> _collapsedCompletedListBuckets = {};
  final _completionController = DelayedTaskCompletionController();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  late final TasksViewPresenter _presenter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _presenter = ref.read(tasksViewPresenterProvider);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _completionController.flush(_presenter.setTaskCompleted);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopDragAutoScroll();
    _scrollController.dispose();
    _selectionNotifier.dispose();
    _completionController.flush(_presenter.setTaskCompleted);
    super.dispose();
  }

  void _stopDragAutoScroll() {
    _dragAutoScrollTimer?.cancel();
    _dragAutoScrollTimer = null;
    _dragPointerY = null;
  }

  void _updateDragAutoScroll(double pointerY, double visibleTop) {
    _dragPointerY = pointerY;
    _dragVisibleTop = visibleTop;
    const edgeThreshold = 64.0;
    if (_draggingTaskId == null || pointerY >= visibleTop + edgeThreshold) {
      _dragAutoScrollTimer?.cancel();
      _dragAutoScrollTimer = null;
      return;
    }
    _dragAutoScrollTimer ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _performDragAutoScrollStep(edgeThreshold),
    );
  }

  void _performDragAutoScrollStep(double edgeThreshold) {
    final y = _dragPointerY;
    if (!mounted || _draggingTaskId == null || y == null) {
      _stopDragAutoScroll();
      return;
    }
    final proximity = ((_dragVisibleTop + edgeThreshold - y) / edgeThreshold)
        .clamp(0.0, 1.0);
    if (proximity <= 0.0) return;
    final step = 4.0 + 10.0 * proximity;
    final inner = _nestedScrollKey.currentState?.innerController;
    if (inner != null && inner.hasClients && inner.offset > 0) {
      inner.jumpTo(
        (inner.offset - step).clamp(0.0, inner.position.maxScrollExtent),
      );
    } else if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(
        (_scrollController.offset - step).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        ),
      );
    }
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
    final inner = _nestedScrollKey.currentState?.innerController;
    if (inner != null && inner.hasClients && inner.offset > 0) {
      inner.animateTo(
        0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
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
    setState(() => _mode = TasksViewMode.reordering);
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
    setState(() => _mode = TasksViewMode.browsing);
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

  void _toggleTaskCompleted(TaskItem task, TodoList currentList) {
    final notifier = ref.read(tasksViewPresenterProvider);
    if (!task.isCompleted && !_completionController.isPending(task.id)) {
      ref.read(completionSoundServiceProvider).playIfEnabled();
    }
    _completionController.toggle(
      task,
      instant: currentList.smartType == SmartListType.completed,
      onCommit: notifier.setTaskCompleted,
      onStateChanged: () {
        if (mounted) setState(() {});
      },
    );
  }

  void _handleDragReorderStart(int index, String taskId) {
    _draggingTaskId = taskId;
    _dragStartIndex = index;
    _toggleSelection(taskId);
  }

  void _handleDragReorderComplete(
    List<TaskItem> activeTasks,
    int oldIndex,
    int newIndex,
  ) {
    _draggingTaskId = null;
    _dragStartIndex = null;
    _dragPointerStartY = null;
    _stopDragAutoScroll();
    ref
        .read(tasksViewPresenterProvider)
        .reorderActiveTasks(activeTasks, oldIndex, newIndex);
    if (_mode == TasksViewMode.multiSelecting && mounted) {
      _clearSelection();
    }
  }

  void _handleDragReorderEnd(int insertIndex) {
    _stopDragAutoScroll();
    final startIndex = _dragStartIndex;
    final adjustedNew = startIndex != null && insertIndex > startIndex
        ? insertIndex - 1
        : insertIndex;
    final willReorder = startIndex != null && adjustedNew != startIndex;
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
  }

  void _handlePointerMove(double pointerY, double visibleTop) {
    if (_draggingTaskId == null) return;
    _updateDragAutoScroll(pointerY, visibleTop);
    if (_mode == TasksViewMode.multiSelecting &&
        _dragPointerStartY != null &&
        (pointerY - _dragPointerStartY!).abs() > 18) {
      _clearSelection();
    }
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

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final isMicrosoft = ref.watch(
      accountProvider.select((s) => s.activeAccount?.isMicrosoft ?? false),
    );
    final l10n = AppLocalizations.of(context);
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final currentList = state.selectedList;
    final notifier = ref.read(tasksViewPresenterProvider);
    final actionPresenter = ref.read(tasksActionPresenterProvider);

    final baseTitle = localizedListTitle(l10n, currentList);
    final listTitle =
        (currentList.emoji != null && currentList.emoji!.isNotEmpty)
        ? '${currentList.emoji!} $baseTitle'
        : baseTitle;
    final accentColor = TodoColors.listAccentFor(
      currentList,
      brightness: brightness,
    );
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

    final taskSlivers = TasksSliverBuilder(
      l10n: l10n,
      state: state,
      currentList: currentList,
      accentColor: accentColor,
      headerFg: headerFg,
      mode: _mode,
      multiSelectedIds: _multiSelectedIds,
      selectionNotifier: _selectionNotifier,
      draggingTaskId: _draggingTaskId,
      collapsedPlannedBuckets: _collapsedPlannedBuckets,
      collapsedCompletedListBuckets: _collapsedCompletedListBuckets,
      completionController: _completionController,
      onToggleBucket: _toggleBucket,
      onToggleCompletedExpanded: (listId, expanded) => ref
          .read(todoProvider.notifier)
          .setCompletedExpanded(listId, expanded),
      onOpenTask: widget.onOpenTask,
      onToggleSelection: _toggleSelection,
      onSwipeMyDay: (task) =>
          actionPresenter.batchSetMyDay({task.id}, !task.isInMyDay),
      onSwipeDelete: (task) => _swipeDeleteTask(task, state.tasks),
      onToggleCompleted: (task) => _toggleTaskCompleted(task, currentList),
      onToggleImportant: (task) => notifier.toggleTaskImportant(task.id),
      onReorderActiveTasks: notifier.reorderActiveTasks,
      onDragReorderStart: _handleDragReorderStart,
      onDragReorderComplete: _handleDragReorderComplete,
      onDragReorderEnd: _handleDragReorderEnd,
    ).build(activeTasks: active, completedTasks: completed);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: PopScope(
        canPop: _mode == TasksViewMode.browsing,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_mode == TasksViewMode.reordering) {
            _exitReordering();
          } else if (_mode == TasksViewMode.multiSelecting) {
            _clearSelection();
          }
        },
        child: ScaffoldMessenger(
          key: _scaffoldMessengerKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TasksViewBackground(
                currentList: currentList,
                backgroundColor: backgroundColor,
              ),
              Scaffold(
                backgroundColor: Colors.transparent,
                appBar: _buildAppBar(
                  l10n: l10n,
                  state: state,
                  currentList: currentList,
                  allTasks: allTasks,
                  isDark: isDark,
                  overlayStyle: overlayStyle,
                ),
                body: SafeArea(
                  top: false,
                  child: TasksViewScrollBody(
                    l10n: l10n,
                    state: state,
                    currentList: currentList,
                    listTitle: listTitle,
                    subtitle: subtitle,
                    headerFg: headerFg,
                    backgroundColor: backgroundColor,
                    accentColor: accentColor,
                    activeTasksCount: active.length,
                    isDark: isDark,
                    isMicrosoft: isMicrosoft,
                    mode: _mode,
                    scrollOffset: _scrollOffset,
                    scrollController: _scrollController,
                    nestedScrollKey: _nestedScrollKey,
                    overlayStyle: overlayStyle,
                    hasBackButton: widget.onBackPressed != null,
                    taskSlivers: taskSlivers,
                    onBackPressed: widget.onBackPressed,
                    onScrollToTop: _scrollToTop,
                    onSelectMenuAction: (action) =>
                        _handleMenuAction(action, state, currentList),
                    onToggleSortDirection: () =>
                        notifier.toggleListSortDirection(currentList.id),
                    onClearSort: () => notifier.setListSortOption(
                      currentList.id,
                      TaskSortOption.defaultOrder,
                    ),
                    onOpenPlannedFilter: () => showPlannedFilterSheet(
                      context: context,
                      currentFilter: state.plannedDueDateFilter,
                      onSelectFilter: notifier.setPlannedDueDateFilter,
                    ),
                    onScrollOffsetChanged: (offset) =>
                        setState(() => _scrollOffset = offset),
                    onScrollEnd: _snapHeaderIfNeeded,
                    onPointerDown: (y) => _dragPointerStartY = y,
                    onPointerMove: _handlePointerMove,
                    onPointerEnd: _stopDragAutoScroll,
                    onRefresh: () => ref
                        .read(syncProvider.notifier)
                        .syncNow(
                          forceFullSync: true,
                          reason: 'pull_to_refresh',
                        ),
                  ),
                ),
                floatingActionButton: TasksViewFab(
                  mode: _mode,
                  currentList: currentList,
                  l10n: l10n,
                  brightness: brightness,
                  onPressed: () => _openAddTaskSheet(state),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
