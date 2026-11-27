import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../../view/task_checkbox.dart';

class _StepItem {
  _StepItem({required this.step, this.controller});

  TaskStep step;
  AnimationController? controller;
  bool isExiting = false;
}

/// Steps list and add-step row matching `detailview/steps/`
/// (`StepViewHolder` + `AddStepViewHolder`).
class StepsSection extends StatefulWidget {
  const StepsSection({
    super.key,
    required this.task,
    required this.backgroundColor,
    required this.onToggleStepCompleted,
    required this.onRenameStep,
    required this.onPromoteStepToTask,
    required this.onDeleteStep,
    required this.onAddStep,
    this.onReorderSteps,
    this.accentColor,
  });

  final TaskItem task;
  final Color backgroundColor;
  final ValueChanged<String> onToggleStepCompleted;
  final void Function(String stepId, String title) onRenameStep;
  final ValueChanged<String> onPromoteStepToTask;
  final ValueChanged<String> onDeleteStep;
  final ValueChanged<String> onAddStep;
  final void Function(int oldIndex, int newIndex)? onReorderSteps;
  final Color? accentColor;

  @override
  State<StepsSection> createState() => _StepsSectionState();
}

class _StepsSectionState extends State<StepsSection>
    with TickerProviderStateMixin {
  static const _insertDuration = Duration(milliseconds: 220);
  static const _removeDuration = Duration(milliseconds: 220);

  final _stepController = TextEditingController();
  final _stepEditController = TextEditingController();
  final _addStepFocusNode = FocusNode();
  late List<_StepItem> _items;
  String? _syncedTaskId;
  String? _editingStepId;
  bool _isAddStepFocused = false;

  @override
  void initState() {
    super.initState();
    _syncedTaskId = widget.task.id;
    _items = [for (final s in widget.task.steps) _StepItem(step: s)];
    _addStepFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isAddStepFocused = _addStepFocusNode.hasFocus);
      }
    });
  }

  @override
  void didUpdateWidget(covariant StepsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_syncedTaskId != widget.task.id) {
      _disposeControllers();
      _syncedTaskId = widget.task.id;
      _stepController.clear();
      _editingStepId = null;
      _items = [for (final s in widget.task.steps) _StepItem(step: s)];
      return;
    }

    final activeItems = _items.where((e) => !e.isExiting).toList();
    if (_haveSameIdsInOrder(activeItems, widget.task.steps)) {
      for (var i = 0; i < activeItems.length; i++) {
        activeItems[i].step = widget.task.steps[i];
      }
      return;
    }
    _syncDiff(widget.task.steps);
  }

  @override
  void dispose() {
    _disposeControllers();
    _stepController.dispose();
    _stepEditController.dispose();
    _addStepFocusNode.dispose();
    super.dispose();
  }

  void _disposeControllers() {
    for (final item in _items) {
      item.controller?.dispose();
      item.controller = null;
    }
  }

  bool _haveSameIdsInOrder(List<_StepItem> a, List<TaskStep> b) =>
      const IterableEquality<String>().equals(
        a.map((item) => item.step.id),
        b.map((step) => step.id),
      );

  void _syncDiff(List<TaskStep> nextSteps) {
    final nextIds = {for (final s in nextSteps) s.id};
    final exitingWithIndex = <(int index, _StepItem item)>[];

    for (var i = 0; i < _items.length; i++) {
      final entry = _items[i];
      if (entry.isExiting) {
        exitingWithIndex.add((i, entry));
        continue;
      }
      if (!nextIds.contains(entry.step.id)) {
        entry.isExiting = true;
        entry.controller?.dispose();
        final controller = AnimationController(
          vsync: this,
          duration: _removeDuration,
          value: 1.0,
        );
        entry.controller = controller;
        controller.reverse().whenComplete(() {
          if (!mounted) return;
          controller.dispose();
          if (entry.controller == controller) {
            entry.controller = null;
          }
          setState(() {
            _items.remove(entry);
          });
        });
        exitingWithIndex.add((i, entry));
      }
    }

    final existingById = {
      for (final e in _items)
        if (!e.isExiting) e.step.id: e,
    };

    final nextList = <_StepItem>[];
    for (final step in nextSteps) {
      final existing = existingById[step.id];
      if (existing != null) {
        existing.step = step;
        nextList.add(existing);
      } else {
        final controller = AnimationController(
          vsync: this,
          duration: _insertDuration,
        );
        final entry = _StepItem(step: step, controller: controller);
        controller.forward().whenComplete(() {
          if (!mounted) return;
          controller.dispose();
          if (entry.controller == controller) {
            entry.controller = null;
          }
        });
        nextList.add(entry);
      }
    }

    for (final (origIndex, exitingItem) in exitingWithIndex) {
      final insertAt = math.min(origIndex, nextList.length);
      nextList.insert(insertAt, exitingItem);
    }

    _items = nextList;
  }

  void _handleReorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _items.length) return;
    if (newIndex < 0 || newIndex >= _items.length || oldIndex == newIndex) {
      return;
    }
    if (_items[oldIndex].isExiting) return;

    int activeIndexFor(int rawIndex) {
      var active = 0;
      for (var i = 0; i < rawIndex; i++) {
        if (!_items[i].isExiting) active++;
      }
      return active;
    }

    final oldStepIndex = activeIndexFor(oldIndex);
    final moved = _items.removeAt(oldIndex);
    _items.insert(newIndex, moved);
    final newStepIndex = activeIndexFor(newIndex);

    setState(() {});
    widget.onReorderSteps?.call(oldStepIndex, newStepIndex);
  }

  Widget _buildStepRow(BuildContext context, TaskStep step) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final accent =
        widget.accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(width: 8),
            TaskCheckbox(
              isChecked: step.isCompleted,
              onTap: () => widget.onToggleStepCompleted(step.id),
              accentColor: accent,
              size: 18,
              showConfetti: false,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _editingStepId == step.id
                  ? TextField(
                      controller: _stepEditController,
                      autofocus: true,
                      style: theme.textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (val) {
                        widget.onRenameStep(step.id, val);
                        setState(() => _editingStepId = null);
                      },
                      onTapOutside: (_) {
                        widget.onRenameStep(step.id, _stepEditController.text);
                        setState(() => _editingStepId = null);
                      },
                    )
                  : GestureDetector(
                      onTap: () {
                        _stepEditController.text = step.title;
                        setState(() => _editingStepId = step.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          step.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            decoration: step.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                            color: step.isCompleted ? secondaryText : null,
                          ),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 2),
              child: PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: secondaryText),
                onSelected: (action) {
                  if (action == 'promote') {
                    widget.onPromoteStepToTask(step.id);
                  } else if (action == 'delete') {
                    widget.onDeleteStep(step.id);
                  }
                },
                itemBuilder: (_) => [
                  if (!step.isCompleted)
                    PopupMenuItem(
                      value: 'promote',
                      child: ListTile(
                        leading: const Icon(Icons.add),
                        title: Text(l10n.promoteStepToTask),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      leading: const Icon(Icons.delete_outline),
                      title: Text(l10n.deleteStep),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 1, indent: 44),
      ],
    );
  }

  Widget _buildListItem(BuildContext context, int index, bool canDrag) {
    final entry = _items[index];
    final step = entry.step;

    if (entry.isExiting) {
      final animation = entry.controller!;
      final sizeCurve = CurvedAnimation(
        parent: animation,
        curve: Curves.easeInOutCubic,
      );
      final fadeCurve = CurvedAnimation(
        parent: animation,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      );
      return IgnorePointer(
        key: ValueKey('removing_step_${step.id}'),
        child: SizeTransition(
          sizeFactor: sizeCurve,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: fadeCurve,
            child: _buildStepRow(context, step),
          ),
        ),
      );
    }

    Widget row = _buildStepRow(context, step);
    final controller = entry.controller;
    if (controller != null && !controller.isCompleted) {
      final sizeCurve = CurvedAnimation(
        parent: controller,
        curve: Curves.easeOutCubic,
      );
      final fadeCurve = CurvedAnimation(
        parent: controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      );
      row = SizeTransition(
        sizeFactor: sizeCurve,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: fadeCurve, child: row),
      );
    }

    return ReorderableDelayedDragStartListener(
      key: ValueKey('step_${step.id}'),
      index: index,
      enabled: canDrag,
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final accent =
        widget.accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);
    final activeCount = _items.where((e) => !e.isExiting).length;
    final canDrag =
        widget.onReorderSteps != null &&
        _editingStepId == null &&
        activeCount > 1;
    final dragHighlightColor = Color.alphaBlend(
      (isDark ? Colors.white : Colors.black).withValues(
        alpha: isDark ? 0.06 : 0.04,
      ),
      widget.backgroundColor,
    );

    return Material(
      color: widget.backgroundColor,
      child: Column(
        children: [
          ReorderableListView.builder(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            padding: EdgeInsets.zero,
            itemCount: _items.length,
            onReorderItem: _handleReorder,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) {
                  final t = Curves.easeInOut.transform(animation.value);
                  return Material(
                    elevation: lerpDouble(0, 4, t) ?? 4,
                    color: Color.lerp(
                      widget.backgroundColor,
                      dragHighlightColor,
                      t,
                    ),
                    child: child,
                  );
                },
                child: child,
              );
            },
            itemBuilder: (context, index) =>
                _buildListItem(context, index, canDrag),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 12, 8),
            child: Row(
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  child: _isAddStepFocused
                      ? Container(
                          key: const ValueKey('step_circle'),
                          width: 18,
                          height: 18,
                          margin: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: secondaryText,
                              width: 1.6,
                            ),
                          ),
                        )
                      : Icon(
                          Icons.add,
                          key: const ValueKey('step_plus'),
                          size: 22,
                          color: accent,
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: _stepController,
                    focusNode: _addStepFocusNode,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      hintText: l10n.addStepPlaceholder,
                      hintStyle: TextStyle(color: accent),
                      border: InputBorder.none,
                    ),
                    onEditingComplete: () {},
                    onTapOutside: (_) => _addStepFocusNode.unfocus(),
                    onSubmitted: (val) {
                      if (val.trim().isEmpty) {
                        _addStepFocusNode.unfocus();
                        return;
                      }
                      widget.onAddStep(val);
                      _stepController.clear();
                      _addStepFocusNode.requestFocus();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
