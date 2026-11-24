import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../../view/task_checkbox.dart';

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
    this.accentColor,
  });

  final TaskItem task;
  final Color backgroundColor;
  final ValueChanged<String> onToggleStepCompleted;
  final void Function(String stepId, String title) onRenameStep;
  final ValueChanged<String> onPromoteStepToTask;
  final ValueChanged<String> onDeleteStep;
  final ValueChanged<String> onAddStep;
  final Color? accentColor;

  @override
  State<StepsSection> createState() => _StepsSectionState();
}

class _StepsSectionState extends State<StepsSection> {
  static const _insertDuration = Duration(milliseconds: 220);
  static const _removeDuration = Duration(milliseconds: 220);

  final _stepController = TextEditingController();
  final _stepEditController = TextEditingController();
  final _addStepFocusNode = FocusNode();
  GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<TaskStep> _items;
  String? _syncedTaskId;
  String? _editingStepId;
  bool _isAddStepFocused = false;

  @override
  void initState() {
    super.initState();
    _syncedTaskId = widget.task.id;
    _items = List<TaskStep>.of(widget.task.steps);
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
      _syncedTaskId = widget.task.id;
      _stepController.clear();
      _editingStepId = null;
      _listKey = GlobalKey<AnimatedListState>();
      _items = List<TaskStep>.of(widget.task.steps);
      return;
    }
    if (_haveSameIdsInOrder(_items, widget.task.steps)) {
      _items = List<TaskStep>.of(widget.task.steps);
      return;
    }
    _syncDiff(widget.task.steps);
  }

  @override
  void dispose() {
    _stepController.dispose();
    _stepEditController.dispose();
    _addStepFocusNode.dispose();
    super.dispose();
  }

  bool _haveSameIdsInOrder(List<TaskStep> a, List<TaskStep> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _syncDiff(List<TaskStep> nextSteps) {
    final listState = _listKey.currentState;
    if (listState == null) {
      _items = List<TaskStep>.of(nextSteps);
      return;
    }

    final nextIds = {for (final s in nextSteps) s.id};

    // 1. Remove steps no longer present (iterate backwards to keep indices valid).
    for (var i = _items.length - 1; i >= 0; i--) {
      final existing = _items[i];
      if (!nextIds.contains(existing.id)) {
        _items.removeAt(i);
        listState.removeItem(
          i,
          (context, animation) =>
              _buildExitingItem(context, existing, animation),
          duration: _removeDuration,
        );
      }
    }

    // 2. Insert new steps and reorder/update existing steps to match nextSteps.
    for (var i = 0; i < nextSteps.length; i++) {
      final target = nextSteps[i];
      final currentIndex = _items.indexWhere((s) => s.id == target.id);
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

  Widget _buildExitingItem(
    BuildContext context,
    TaskStep step,
    Animation<double> animation,
  ) {
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
        key: ValueKey('removing_step_${step.id}'),
        child: SizeTransition(
          sizeFactor: sizeCurve,
          alignment: Alignment.topCenter,
          child: FadeTransition(
            opacity: fadeCurve,
            child: _buildStepRow(context, step),
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
    final step = _items[index];
    Widget child = KeyedSubtree(
      key: ValueKey('step_${step.id}'),
      child: _buildStepRow(context, step),
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
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText = isDark
        ? TodoColors.secondaryTextDark
        : TodoColors.secondaryTextLight;
    final accent =
        widget.accentColor ??
        (isDark ? TodoColors.attentionDark : TodoColors.attentionLight);

    return Material(
      color: widget.backgroundColor,
      child: Column(
        children: [
          AnimatedList(
            key: _listKey,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            initialItemCount: _items.length,
            itemBuilder: _buildItem,
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
