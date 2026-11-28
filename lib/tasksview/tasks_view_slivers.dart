import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../view/delayed_task_completion.dart';
import 'recyclerview/animated_task_sliver_list.dart';
import 'recyclerview/swipeable_task_card.dart';
import 'recyclerview/task_list_tile.dart';
import 'tasks_view_bars.dart';
import 'tasks_view_dialogs.dart';
import 'tasks_view_grouping.dart';
import 'tasks_view_widgets.dart';

/// Builds the task slivers (active, grouped, reorderable, completed) for [TasksViewScreen].
class TasksSliverBuilder {
  const TasksSliverBuilder({
    required this.l10n,
    required this.state,
    required this.currentList,
    required this.accentColor,
    required this.headerFg,
    required this.isDark,
    required this.mode,
    required this.multiSelectedIds,
    required this.selectionNotifier,
    required this.draggingTaskId,
    this.swipedTaskIds = const {},
    required this.collapsedPlannedBuckets,
    required this.collapsedCompletedListBuckets,
    required this.completionController,
    required this.onToggleBucket,
    required this.onToggleCompletedExpanded,
    required this.onOpenTask,
    required this.onToggleSelection,
    required this.onSwipeMyDay,
    required this.onSwipeDelete,
    required this.onToggleCompleted,
    required this.onToggleImportant,
    required this.onReorderActiveTasks,
    required this.onDragReorderStart,
    required this.onDragReorderComplete,
    required this.onDragReorderEnd,
  });

  final AppLocalizations l10n;
  final TodoState state;
  final TodoList currentList;
  final Color accentColor;
  final Color headerFg;
  final bool isDark;
  final TasksViewMode mode;
  final Set<String> multiSelectedIds;
  final ValueListenable<Set<String>> selectionNotifier;
  final String? draggingTaskId;
  final Set<String> swipedTaskIds;
  final Set<String> collapsedPlannedBuckets;
  final Set<String> collapsedCompletedListBuckets;
  final DelayedTaskCompletionController completionController;

  final void Function(Set<String> collapsed, String key) onToggleBucket;
  final void Function(String listId, bool expanded) onToggleCompletedExpanded;
  final void Function(TaskItem task) onOpenTask;
  final void Function(String taskId) onToggleSelection;
  final void Function(TaskItem task) onSwipeMyDay;
  final void Function(TaskItem task) onSwipeDelete;
  final void Function(TaskItem task) onToggleCompleted;
  final void Function(TaskItem task) onToggleImportant;
  final void Function(List<TaskItem> tasks, int oldIndex, int newIndex)
  onReorderActiveTasks;
  final void Function(int index, String taskId) onDragReorderStart;
  final void Function(List<TaskItem> tasks, int oldIndex, int newIndex)
  onDragReorderComplete;
  final void Function(int insertIndex) onDragReorderEnd;

  bool get _showMyDayBadge => currentList.smartType != SmartListType.myDay;

  bool get _showOriginList =>
      currentList.isSmartList && currentList.smartType != SmartListType.tasks;

  String? _originListNameFor(TaskItem task, {bool force = false}) {
    if (!force && !_showOriginList) return null;
    return resolveOriginListName(l10n, state.lists, task.listId);
  }

  /// Returns all slivers for [activeTasks] and [completedTasks].
  List<Widget> build({
    required List<TaskItem> activeTasks,
    required List<TaskItem> completedTasks,
  }) {
    if (activeTasks.isEmpty &&
        completedTasks.isEmpty &&
        hasSmartListEmptyState(currentList.smartType)) {
      return [
        ..._buildActiveSlivers(activeTasks),
        SliverFillRemaining(
          hasScrollBody: false,
          child: SmartListEmptyState(
            l10n: l10n,
            currentList: currentList,
            textColor: headerFg,
            isDark: isDark,
          ),
        ),
      ];
    }

    return [
      ..._buildActiveSlivers(activeTasks),
      ..._buildCompletedBucketSlivers(completedTasks),
    ];
  }

  List<Widget> _buildActiveSlivers(List<TaskItem> activeTasks) {
    if (mode == TasksViewMode.reordering) {
      return [_buildReorderableSliver(activeTasks)];
    }

    final isDefaultOrder =
        currentList.sortOption == TaskSortOption.defaultOrder;
    if (currentList.smartType == SmartListType.planned && isDefaultOrder) {
      return switch (state.plannedGroupOption) {
        PlannedGroupOption.byDueDate => _buildPlannedBucketSlivers(activeTasks),
        PlannedGroupOption.byList => _buildListBucketSlivers(activeTasks),
        PlannedGroupOption.ungroup => [_buildFlatTaskSliver(activeTasks)],
      };
    }

    final isBucketedSmartList =
        currentList.smartType == SmartListType.completed ||
        currentList.smartType == SmartListType.all;
    if (isBucketedSmartList && isDefaultOrder) {
      return _buildListBucketSlivers(activeTasks);
    }

    return [_buildFlatTaskSliver(activeTasks)];
  }

  Widget _buildTaskTile(
    TaskItem task, {
    String? originListName,
    bool showMyDayBadge = true,
    bool enableLongPress = true,
    Set<String>? selectedIdsOverride,
  }) {
    final displayTask = completionController.effectiveTask(task);
    final selectedIds = selectedIdsOverride ?? multiSelectedIds;
    final isMultiSelecting = selectedIdsOverride != null
        ? selectedIdsOverride.isNotEmpty
        : mode == TasksViewMode.multiSelecting;
    return SwipeableTaskCard(
      key: ValueKey('task_${task.id}'),
      enabled: mode == TasksViewMode.browsing,
      isInMyDay: task.isInMyDay,
      accentColor: accentColor,
      onSwipeRight: () => onSwipeMyDay(task),
      onSwipeLeft: () => onSwipeDelete(task),
      child: TaskListTile(
        task: displayTask,
        listName: originListName,
        showMyDayBadge: showMyDayBadge,
        accentColor: accentColor,
        isSelected: state.selectedTaskId == task.id,
        isMultiSelecting: isMultiSelecting,
        isMultiSelected: selectedIds.contains(task.id),
        onTap: () {
          if (mode == TasksViewMode.multiSelecting) {
            onToggleSelection(task.id);
          } else {
            onOpenTask(task);
          }
        },
        onLongPress: enableLongPress ? () => onToggleSelection(task.id) : null,
        onToggleCompleted: () => onToggleCompleted(task),
        onToggleImportant: () => onToggleImportant(task),
      ),
    );
  }

  Widget _buildReorderableSliver(List<TaskItem> activeTasks) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: AnimatedReorderableTaskSliver(
        tasks: activeTasks,
        onReorder: (oldIndex, newIndex) =>
            onReorderActiveTasks(activeTasks, oldIndex, newIndex),
        itemBuilder: (context, index, task, onAnimatedStep) =>
            _ReorderableModeTaskTile(
              key: ValueKey(task.id),
              task: task,
              index: index,
              totalCount: activeTasks.length,
              originListName: _originListNameFor(task),
              showMyDayBadge: _showMyDayBadge,
              accentColor: accentColor,
              onAnimatedStep: onAnimatedStep,
            ),
      ),
    );
  }

  List<Widget> _buildPlannedBucketSlivers(List<TaskItem> activeTasks) {
    final groups = groupPlannedTasks(activeTasks, state.startOfWeek);
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: TasksBucketPill(
            label: plannedBucketLabel(l10n, group.bucket),
            count: group.tasks.length,
            isExpanded: !collapsedPlannedBuckets.contains(group.bucket.name),
            onTap: () =>
                onToggleBucket(collapsedPlannedBuckets, group.bucket.name),
            currentList: currentList,
            headerFg: headerFg,
          ),
        ),
        CollapsibleTaskBucketSliver(
          key: ValueKey('planned_${group.bucket.name}'),
          isExpanded: !collapsedPlannedBuckets.contains(group.bucket.name),
          tasks: group.tasks,
          swipedTaskIds: swipedTaskIds,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemBuilder: (context, task) => _buildTaskTile(
            task,
            originListName: _originListNameFor(task, force: true),
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildListBucketSlivers(List<TaskItem> activeTasks) {
    final groups = groupTasksByList(l10n, activeTasks, state.lists);
    return [
      for (final group in groups) ...[
        SliverToBoxAdapter(
          child: TasksBucketPill(
            label: group.title,
            count: group.tasks.length,
            isExpanded: !collapsedCompletedListBuckets.contains(group.listId),
            onTap: () =>
                onToggleBucket(collapsedCompletedListBuckets, group.listId),
            currentList: currentList,
            headerFg: headerFg,
          ),
        ),
        CollapsibleTaskBucketSliver(
          key: ValueKey('bucket_${currentList.id}_${group.listId}'),
          isExpanded: !collapsedCompletedListBuckets.contains(group.listId),
          tasks: group.tasks,
          swipedTaskIds: swipedTaskIds,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemBuilder: (context, task) => _buildTaskTile(task),
        ),
      ],
    ];
  }

  Widget _buildFlatTaskSliver(List<TaskItem> activeTasks) {
    if (!supportsListReordering(currentList)) {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        sliver: AnimatedTaskSliverList(
          key: ValueKey('flat_${currentList.id}'),
          tasks: activeTasks,
          swipedTaskIds: swipedTaskIds,
          itemBuilder: (context, task) => _buildTaskTile(
            task,
            showMyDayBadge: _showMyDayBadge,
            originListName: _originListNameFor(task),
          ),
        ),
      );
    }

    final dragEnabled =
        (mode == TasksViewMode.browsing || draggingTaskId != null) &&
        activeTasks.length >= 2;

    Widget buildDragTile(TaskItem task, {Set<String>? selectedIds}) =>
        _buildTaskTile(
          task,
          showMyDayBadge: _showMyDayBadge,
          originListName: _originListNameFor(task),
          enableLongPress: !dragEnabled,
          selectedIdsOverride: selectedIds,
        );

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      sliver: AnimatedReorderableTaskSliver(
        key: ValueKey('flat_reorder_${currentList.id}'),
        tasks: activeTasks,
        swipedTaskIds: swipedTaskIds,
        proxyDecorator: (child, index, animation) {
          final task = activeTasks[index];
          return ValueListenableBuilder<Set<String>>(
            valueListenable: selectionNotifier,
            builder: (context, selectedIds, _) => Material(
              elevation: 4,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: HeroMode(
                enabled: false,
                child: buildDragTile(task, selectedIds: selectedIds),
              ),
            ),
          );
        },
        onReorderStart: (index) =>
            onDragReorderStart(index, activeTasks[index].id),
        onReorder: (oldIndex, newIndex) =>
            onDragReorderComplete(activeTasks, oldIndex, newIndex),
        onReorderEnd: onDragReorderEnd,
        itemBuilder: (context, index, task, _) =>
            ReorderableDelayedDragStartListener(
              key: ValueKey('drag_${task.id}'),
              index: index,
              enabled: dragEnabled && index >= 0,
              child: buildDragTile(task),
            ),
      ),
    );
  }

  List<Widget> _buildCompletedBucketSlivers(List<TaskItem> completedTasks) {
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
                    onTap: () => onToggleCompletedExpanded(
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
        swipedTaskIds: swipedTaskIds,
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
        itemBuilder: (context, task) => _buildTaskTile(
          task,
          showMyDayBadge: _showMyDayBadge,
          originListName: _originListNameFor(task),
        ),
      ),
    ];
  }
}

class _ReorderableModeTaskTile extends StatelessWidget {
  const _ReorderableModeTaskTile({
    super.key,
    required this.task,
    required this.index,
    required this.totalCount,
    required this.originListName,
    required this.showMyDayBadge,
    required this.accentColor,
    required this.onAnimatedStep,
  });

  final TaskItem task;
  final int index;
  final int totalCount;
  final String? originListName;
  final bool showMyDayBadge;
  final Color accentColor;
  final void Function(int from, int to) onAnimatedStep;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: TaskListTile(
        task: task,
        listName: originListName,
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
              onPressed: index < totalCount - 1
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
  }
}
