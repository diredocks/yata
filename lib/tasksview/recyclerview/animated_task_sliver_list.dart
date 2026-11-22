import 'package:material_ui/material_ui.dart';
import '../../models/task_item.dart';

/// Animated sliver list for task items that smoothly animates insertions,
/// removals, and in-list moves (e.g. starring to top, sorting, completing),
/// matching `RecyclerView` `DefaultItemAnimator` + `DiffUtil` in the original app.
class AnimatedTaskSliverList extends StatefulWidget {
  const AnimatedTaskSliverList({
    super.key,
    required this.tasks,
    required this.itemBuilder,
  });

  final List<TaskItem> tasks;
  final Widget Function(BuildContext context, TaskItem task) itemBuilder;

  @override
  State<AnimatedTaskSliverList> createState() => _AnimatedTaskSliverListState();
}

class _AnimatedTaskSliverListState extends State<AnimatedTaskSliverList>
    with TickerProviderStateMixin {
  static const _insertDuration = Duration(milliseconds: 220);
  static const _removeDuration = Duration(milliseconds: 200);
  static const _moveDuration = Duration(milliseconds: 250);
  static const _estimatedRowHeight = 56.0;

  final _listKey = GlobalKey<SliverAnimatedListState>();
  late List<TaskItem> _items;
  final Map<String, AnimationController> _moveControllers = {};
  final Map<String, double> _moveOffsets = {};

  @override
  void initState() {
    super.initState();
    _items = List<TaskItem>.of(widget.tasks);
  }

  @override
  void didUpdateWidget(covariant AnimatedTaskSliverList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncDiff(widget.tasks);
  }

  @override
  void dispose() {
    for (final controller in _moveControllers.values) {
      controller.dispose();
    }
    _moveControllers.clear();
    super.dispose();
  }

  void _startMoveAnimation(String taskId, int indexDelta) {
    if (indexDelta == 0) return;
    _moveControllers[taskId]?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: _moveDuration,
    );
    // Clamp offset so large sort jumps still feel crisp and bounded.
    final startDy = (indexDelta * _estimatedRowHeight).clamp(-280.0, 280.0);
    _moveOffsets[taskId] = startDy;
    _moveControllers[taskId] = controller;
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _moveOffsets.remove(taskId);
        _moveControllers.remove(taskId)?.dispose();
      }
    });
    controller.forward();
  }

  void _syncDiff(List<TaskItem> nextTasks) {
    final listState = _listKey.currentState;
    if (listState == null) {
      _items = List<TaskItem>.of(nextTasks);
      return;
    }

    final nextIds = {for (final t in nextTasks) t.id};

    // 1. Remove items no longer present (iterate backwards to keep indices valid).
    for (var i = _items.length - 1; i >= 0; i--) {
      final existing = _items[i];
      if (!nextIds.contains(existing.id)) {
        _items.removeAt(i);
        _moveOffsets.remove(existing.id);
        _moveControllers.remove(existing.id)?.dispose();
        listState.removeItem(
          i,
          (context, animation) => _buildExitingItem(context, existing, animation),
          duration: _removeDuration,
        );
      }
    }

    // 2. Insert new items and update/move existing items to match nextTasks.
    for (var i = 0; i < nextTasks.length; i++) {
      final target = nextTasks[i];
      final currentIndex = _items.indexWhere((t) => t.id == target.id);
      if (currentIndex == -1) {
        _items.insert(i, target);
        listState.insertItem(i, duration: _insertDuration);
      } else if (currentIndex != i) {
        final moved = _items.removeAt(currentIndex);
        _items.insert(i, target);
        _startMoveAnimation(moved.id, currentIndex - i);
      } else {
        _items[i] = target;
      }
    }
  }

  Widget _buildExitingItem(
    BuildContext context,
    TaskItem task,
    Animation<double> animation,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    return IgnorePointer(
      child: KeyedSubtree(
        key: ValueKey('removing_${task.id}'),
        child: SizeTransition(
          sizeFactor: curved,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: curved,
            child: widget.itemBuilder(context, task),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context,
    int index,
    Animation<double> animation,
  ) {
    final task = _items[index];
    Widget child = widget.itemBuilder(context, task);

    final moveController = _moveControllers[task.id];
    final startDy = _moveOffsets[task.id];
    if (moveController != null && startDy != null) {
      final curvedMove = CurvedAnimation(
        parent: moveController,
        curve: Curves.easeOutCubic,
      );
      child = AnimatedBuilder(
        animation: curvedMove,
        builder: (context, inner) {
          final dy = startDy * (1.0 - curvedMove.value);
          return Transform.translate(
            offset: Offset(0, dy),
            child: inner,
          );
        },
        child: child,
      );
    }

    if (animation.status == AnimationStatus.forward || !animation.isCompleted) {
      final curvedIn = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      child = SizeTransition(
        sizeFactor: curvedIn,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: curvedIn,
          child: child,
        ),
      );
    }

    return child;
  }

  @override
  Widget build(BuildContext context) {
    return SliverAnimatedList(
      key: _listKey,
      initialItemCount: _items.length,
      itemBuilder: _buildItem,
    );
  }
}

/// Reorderable sliver list that also animates programmatic up/down arrow swaps.
class AnimatedReorderableTaskSliver extends StatefulWidget {
  const AnimatedReorderableTaskSliver({
    super.key,
    required this.tasks,
    required this.onReorder,
    required this.itemBuilder,
  });

  final List<TaskItem> tasks;
  final void Function(int oldIndex, int newIndex) onReorder;
  final Widget Function(
    BuildContext context,
    int index,
    TaskItem task,
    void Function(int oldIndex, int newIndex) onAnimatedStep,
  ) itemBuilder;

  @override
  State<AnimatedReorderableTaskSliver> createState() =>
      _AnimatedReorderableTaskSliverState();
}

class _AnimatedReorderableTaskSliverState
    extends State<AnimatedReorderableTaskSliver> with TickerProviderStateMixin {
  static const _moveDuration = Duration(milliseconds: 220);
  static const _estimatedRowHeight = 56.0;

  final Map<String, AnimationController> _moveControllers = {};
  final Map<String, double> _moveOffsets = {};

  @override
  void dispose() {
    for (final controller in _moveControllers.values) {
      controller.dispose();
    }
    _moveControllers.clear();
    super.dispose();
  }

  void _startMove(String taskId, int indexDelta) {
    if (indexDelta == 0) return;
    _moveControllers[taskId]?.dispose();
    final controller = AnimationController(
      vsync: this,
      duration: _moveDuration,
    );
    _moveOffsets[taskId] =
        (indexDelta * _estimatedRowHeight).clamp(-280.0, 280.0);
    _moveControllers[taskId] = controller;
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _moveOffsets.remove(taskId);
        _moveControllers.remove(taskId)?.dispose();
      }
    });
    controller.forward();
  }

  void _handleAnimatedStep(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= widget.tasks.length ||
        newIndex < 0 ||
        newIndex >= widget.tasks.length ||
        oldIndex == newIndex) {
      return;
    }
    final movedTask = widget.tasks[oldIndex];
    final displacedTask = widget.tasks[newIndex];
    _startMove(movedTask.id, oldIndex - newIndex);
    _startMove(displacedTask.id, newIndex - oldIndex);
    widget.onReorder(oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: widget.tasks.length,
      onReorderItem: widget.onReorder,
      itemBuilder: (context, index) {
        final task = widget.tasks[index];
        final child = widget.itemBuilder(
          context,
          index,
          task,
          _handleAnimatedStep,
        );
        final moveController = _moveControllers[task.id];
        final startDy = _moveOffsets[task.id];
        if (moveController == null || startDy == null) {
          return child;
        }
        final curved = CurvedAnimation(
          parent: moveController,
          curve: Curves.easeOutCubic,
        );
        return AnimatedBuilder(
          key: ValueKey(task.id),
          animation: curved,
          builder: (context, inner) => Transform.translate(
            offset: Offset(0, startDy * (1.0 - curved.value)),
            child: inner,
          ),
          child: child,
        );
      },
    );
  }
}
