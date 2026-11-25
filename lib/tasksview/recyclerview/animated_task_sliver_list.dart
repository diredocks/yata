import 'package:collection/collection.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import '../../models/task_item.dart';

/// Animated sliver list for task items that smoothly animates insertions,
/// removals, and in-list moves (e.g. starring to top, sorting, completing,
/// collapsing/expanding buckets), matching `RecyclerView` `DefaultItemAnimator`
/// + `DiffUtil` in the original app.
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
  static const _removeDuration = Duration(milliseconds: 220);

  final _listKey = GlobalKey<SliverAnimatedListState>();
  late List<TaskItem> _items;
  late final _FlipCoordinator _flipCoordinator;

  @override
  void initState() {
    super.initState();
    _items = List<TaskItem>.of(widget.tasks);
    _flipCoordinator = _FlipCoordinator(
      vsync: this,
      ancestorProvider: () =>
          Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedTaskSliverList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_haveSameIdsInOrder(_items, widget.tasks)) {
      _items = List<TaskItem>.of(widget.tasks);
      return;
    }
    _flipCoordinator.capturePositions();
    _syncDiff(widget.tasks);
  }

  @override
  void dispose() {
    _flipCoordinator.dispose();
    super.dispose();
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
        _flipCoordinator.cancelAnimation(existing.id);
        listState.removeItem(
          i,
          (context, animation) =>
              _buildExitingItem(context, existing, animation),
          duration: _removeDuration,
        );
      }
    }

    // 2. Insert new items and reorder/update existing items to match nextTasks.
    for (var i = 0; i < nextTasks.length; i++) {
      final target = nextTasks[i];
      final currentIndex = _items.indexWhere((t) => t.id == target.id);
      if (currentIndex == -1) {
        _items.insert(i, target);
        listState.insertItem(i, duration: _insertDuration);
      } else if (currentIndex != i) {
        _items.removeAt(currentIndex);
        _items.insert(i, target);
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
    // Fade out during the first ~130ms (matching DefaultItemAnimator.removeDuration)
    // as animation goes 1.0 -> 0.0, while row height collapses smoothly over 220ms.
    final sizeCurve = CurvedAnimation(
      parent: animation,
      curve: Curves.easeInOutCubic,
    );
    final fadeCurve = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
    );
    return IgnorePointer(
      child: KeyedSubtree(
        key: ValueKey('removing_${task.id}'),
        child: SizeTransition(
          sizeFactor: sizeCurve,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: fadeCurve,
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
    Widget child = _FlipItem(
      key: ValueKey('flip_${task.id}'),
      id: task.id,
      coordinator: _flipCoordinator,
      child: widget.itemBuilder(context, task),
    );

    if (animation.status == AnimationStatus.forward || !animation.isCompleted) {
      final sizeCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      final fadeCurve = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      );
      child = SizeTransition(
        sizeFactor: sizeCurve,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: fadeCurve, child: child),
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

/// Bucket sliver that expands and collapses with a single GPU-composited
/// `SliverFadeTransition` (matching `RecyclerView` `DefaultItemAnimator`
/// without per-item `SizeTransition` relayouts), while delegating in-place
/// task additions, removals, and reorders to `AnimatedTaskSliverList`.
class CollapsibleTaskBucketSliver extends StatefulWidget {
  const CollapsibleTaskBucketSliver({
    super.key,
    required this.isExpanded,
    required this.tasks,
    required this.padding,
    required this.itemBuilder,
  });

  final bool isExpanded;
  final List<TaskItem> tasks;
  final EdgeInsetsGeometry padding;
  final Widget Function(BuildContext context, TaskItem task) itemBuilder;

  @override
  State<CollapsibleTaskBucketSliver> createState() =>
      _CollapsibleTaskBucketSliverState();
}

class _CollapsibleTaskBucketSliverState
    extends State<CollapsibleTaskBucketSliver>
    with SingleTickerProviderStateMixin {
  static const _fadeDuration = Duration(milliseconds: 150);

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late List<TaskItem> _renderedTasks;

  bool get _shouldShow => widget.isExpanded && widget.tasks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _fadeDuration,
      value: _shouldShow ? 1.0 : 0.0,
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _renderedTasks = _shouldShow ? List<TaskItem>.of(widget.tasks) : const [];
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted && !_shouldShow) {
        setState(() {
          _renderedTasks = const [];
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant CollapsibleTaskBucketSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasShowing = oldWidget.isExpanded && oldWidget.tasks.isNotEmpty;
    if (_shouldShow) {
      _renderedTasks = widget.tasks;
      if (!wasShowing || _controller.status == AnimationStatus.reverse) {
        _controller.forward();
      }
    } else if (_renderedTasks.isNotEmpty) {
      if (wasShowing || _controller.status == AnimationStatus.forward) {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_renderedTasks.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverFadeTransition(
      opacity: _opacity,
      sliver: SliverPadding(
        padding: widget.padding,
        sliver: AnimatedTaskSliverList(
          tasks: _renderedTasks,
          itemBuilder: widget.itemBuilder,
        ),
      ),
    );
  }
}

/// Reorderable sliver list that smoothly animates programmatic up/down arrow
/// swaps as well as drag-and-drop reorders.
class AnimatedReorderableTaskSliver extends StatefulWidget {
  const AnimatedReorderableTaskSliver({
    super.key,
    required this.tasks,
    required this.onReorder,
    required this.itemBuilder,
    this.proxyDecorator,
    this.onReorderStart,
    this.onReorderEnd,
  });

  final List<TaskItem> tasks;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ReorderItemProxyDecorator? proxyDecorator;
  final void Function(int index)? onReorderStart;
  final void Function(int index)? onReorderEnd;
  final Widget Function(
    BuildContext context,
    int index,
    TaskItem task,
    void Function(int oldIndex, int newIndex) onAnimatedStep,
  )
  itemBuilder;

  @override
  State<AnimatedReorderableTaskSliver> createState() =>
      _AnimatedReorderableTaskSliverState();
}

class _AnimatedReorderableTaskSliverState
    extends State<AnimatedReorderableTaskSliver>
    with TickerProviderStateMixin {
  late final _FlipCoordinator _flipCoordinator;

  @override
  void initState() {
    super.initState();
    _flipCoordinator = _FlipCoordinator(
      vsync: this,
      ancestorProvider: () =>
          Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedReorderableTaskSliver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_haveSameIdsInOrder(oldWidget.tasks, widget.tasks)) {
      _flipCoordinator.capturePositions();
    }
  }

  @override
  void dispose() {
    _flipCoordinator.dispose();
    super.dispose();
  }

  void _handleAnimatedStep(int oldIndex, int newIndex) {
    if (oldIndex < 0 ||
        oldIndex >= widget.tasks.length ||
        newIndex < 0 ||
        newIndex >= widget.tasks.length ||
        oldIndex == newIndex) {
      return;
    }
    _flipCoordinator.capturePositions();
    widget.onReorder(oldIndex, newIndex);
  }

  @override
  Widget build(BuildContext context) {
    return SliverReorderableList(
      itemCount: widget.tasks.length,
      onReorderItem: widget.onReorder,
      onReorderStart: widget.onReorderStart,
      onReorderEnd: widget.onReorderEnd,
      proxyDecorator: widget.proxyDecorator,
      itemBuilder: (context, index) {
        final task = widget.tasks[index];
        return _FlipItem(
          key: ValueKey(task.id),
          id: task.id,
          coordinator: _flipCoordinator,
          child: widget.itemBuilder(context, index, task, _handleAnimatedStep),
        );
      },
    );
  }
}

bool _haveSameIdsInOrder(List<TaskItem> a, List<TaskItem> b) =>
    identical(a, b) ||
    const IterableEquality<String>().equals(
      a.map((task) => task.id),
      b.map((task) => task.id),
    );

class _CapturedPosition {
  const _CapturedPosition({required this.laidOutY, required this.visualY});

  final double laidOutY;
  final double visualY;
}

/// Coordinates pixel-exact FLIP (First-Last-Invert-Play) vertical move
/// animations across items in a sliver list without widget-tree rebuilds.
class _FlipCoordinator {
  _FlipCoordinator({required this.vsync, required this.ancestorProvider});

  static const _moveDuration = Duration(milliseconds: 250);
  static const _maxAnimateDelta = 2000.0;

  final TickerProvider vsync;
  final RenderBox? Function() ancestorProvider;

  final Map<String, _RenderFlipItem> _renderItems = {};
  final Map<String, _CapturedPosition> _pendingPositions = {};
  final Map<String, AnimationController> _controllers = {};
  bool _postFrameCleanupScheduled = false;

  void register(String id, _RenderFlipItem renderObject) {
    _renderItems[id] = renderObject;
  }

  void unregister(String id, _RenderFlipItem renderObject) {
    if (_renderItems[id] == renderObject) {
      _renderItems.remove(id);
    }
  }

  void capturePositions() {
    final ancestor = ancestorProvider();
    for (final entry in _renderItems.entries) {
      final renderItem = entry.value;
      if (!renderItem.attached || !renderItem.hasSize) continue;
      final laidOutY = renderItem
          .localToGlobal(Offset.zero, ancestor: ancestor)
          .dy;
      _pendingPositions[entry.key] = _CapturedPosition(
        laidOutY: laidOutY,
        visualY: laidOutY + renderItem.currentOffsetY,
      );
    }
    if (_pendingPositions.isNotEmpty && !_postFrameCleanupScheduled) {
      _postFrameCleanupScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _postFrameCleanupScheduled = false;
        _pendingPositions.clear();
      });
    }
  }

  void consumePendingAndMaybeStart(String id, _RenderFlipItem renderItem) {
    final captured = _pendingPositions.remove(id);
    if (captured == null || !renderItem.attached || !renderItem.hasSize) {
      return;
    }
    final ancestor = ancestorProvider();
    final newY = renderItem.localToGlobal(Offset.zero, ancestor: ancestor).dy;

    final existingController = _controllers[id];
    if (existingController != null &&
        existingController.isAnimating &&
        (newY - captured.laidOutY).abs() <= 0.5) {
      // Target position didn't change on an unrelated rebuild; keep animating.
      return;
    }

    final deltaY = captured.visualY - newY;
    if (deltaY.abs() <= 0.5 || deltaY.abs() > _maxAnimateDelta) {
      return;
    }

    existingController?.dispose();
    final controller = AnimationController(
      vsync: vsync,
      duration: _moveDuration,
    );
    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    _controllers[id] = controller;
    renderItem.currentOffsetY = deltaY;

    controller.addListener(() {
      final target = _renderItems[id];
      if (target != null && target.attached) {
        target.currentOffsetY = deltaY * (1.0 - curved.value);
        target.markNeedsPaint();
      }
    });
    controller.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        if (_controllers[id] == controller) {
          _controllers.remove(id);
        }
        controller.dispose();
        final target = _renderItems[id];
        if (target != null && target.attached) {
          target.currentOffsetY = 0.0;
          target.markNeedsPaint();
        }
      }
    });
    controller.forward();
  }

  void cancelAnimation(String id) {
    _pendingPositions.remove(id);
    _controllers.remove(id)?.dispose();
    final renderItem = _renderItems[id];
    if (renderItem != null) {
      renderItem.currentOffsetY = 0.0;
    }
  }

  void dispose() {
    _pendingPositions.clear();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _controllers.clear();
    _renderItems.clear();
  }
}

class _FlipItem extends SingleChildRenderObjectWidget {
  const _FlipItem({
    super.key,
    required this.id,
    required this.coordinator,
    required super.child,
  });

  final String id;
  final _FlipCoordinator coordinator;

  @override
  _RenderFlipItem createRenderObject(BuildContext context) {
    return _RenderFlipItem(id: id, coordinator: coordinator);
  }

  @override
  void updateRenderObject(BuildContext context, _RenderFlipItem renderObject) {
    renderObject.update(id: id, coordinator: coordinator);
  }
}

class _RenderFlipItem extends RenderProxyBox {
  _RenderFlipItem({required this._id, required this._coordinator});

  String _id;
  _FlipCoordinator _coordinator;
  double currentOffsetY = 0.0;

  void update({required String id, required _FlipCoordinator coordinator}) {
    if (_id != id || _coordinator != coordinator) {
      _coordinator.unregister(_id, this);
      _id = id;
      _coordinator = coordinator;
      if (attached) {
        _coordinator.register(_id, this);
      }
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _coordinator.register(_id, this);
  }

  @override
  void detach() {
    _coordinator.unregister(_id, this);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _coordinator.consumePendingAndMaybeStart(_id, this);
    final child = this.child;
    if (child == null) return;
    if (currentOffsetY != 0.0) {
      context.paintChild(child, offset + Offset(0.0, currentOffsetY));
    } else {
      context.paintChild(child, offset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (currentOffsetY == 0.0) {
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintOffset(
      offset: Offset(0.0, currentOffsetY),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return super.hitTestChildren(result, position: transformed);
      },
    );
  }
}
