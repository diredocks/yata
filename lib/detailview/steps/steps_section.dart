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
  });

  final TaskItem task;
  final Color backgroundColor;
  final ValueChanged<String> onToggleStepCompleted;
  final void Function(String stepId, String title) onRenameStep;
  final ValueChanged<String> onPromoteStepToTask;
  final ValueChanged<String> onDeleteStep;
  final ValueChanged<String> onAddStep;

  @override
  State<StepsSection> createState() => _StepsSectionState();
}

class _StepsSectionState extends State<StepsSection> {
  final _stepController = TextEditingController();
  final _stepEditController = TextEditingController();
  final _addStepFocusNode = FocusNode();
  String? _syncedTaskId;
  String? _editingStepId;
  bool _isAddStepFocused = false;

  @override
  void initState() {
    super.initState();
    _addStepFocusNode.addListener(() {
      if (mounted) {
        setState(() => _isAddStepFocused = _addStepFocusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _stepController.dispose();
    _stepEditController.dispose();
    _addStepFocusNode.dispose();
    super.dispose();
  }

  void _syncTask() {
    if (_syncedTaskId != widget.task.id) {
      _syncedTaskId = widget.task.id;
      _stepController.clear();
      _editingStepId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncTask();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;
    final accent =
        isDark ? TodoColors.attentionDark : TodoColors.attentionLight;

    return Material(
      color: widget.backgroundColor,
      child: Column(
        children: [
          for (final step in widget.task.steps) ...[
            Row(
              children: [
                const SizedBox(width: 8),
                TaskCheckbox(
                  isChecked: step.isCompleted,
                  onTap: () => widget.onToggleStepCompleted(step.id),
                  size: 18,
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
                            widget.onRenameStep(
                              step.id,
                              _stepEditController.text,
                            );
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
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: secondaryText,
                    ),
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
            const Divider(height: 1, indent: 66, endIndent: 16),
          ],
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
                    decoration: InputDecoration(
                      hintText: l10n.addStepPlaceholder,
                      hintStyle: TextStyle(color: accent),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (val) {
                      widget.onAddStep(val);
                      _stepController.clear();
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
