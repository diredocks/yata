import 'package:material_ui/material_ui.dart';

import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';
import '../../view/task_checkbox.dart';

/// Header section matching `detailview/header/DetailsHeaderView` (`detailview_header.xml`).
class DetailsHeaderView extends StatefulWidget {
  const DetailsHeaderView({
    super.key,
    required this.task,
    required this.originListTitle,
    required this.backgroundColor,
    required this.onToggleCompleted,
    required this.onToggleImportant,
    required this.onTitleSubmitted,
    this.accentColor,
    this.onClose,
  });

  final TaskItem task;
  final String originListTitle;
  final Color backgroundColor;
  final VoidCallback onToggleCompleted;
  final VoidCallback onToggleImportant;
  final ValueChanged<String> onTitleSubmitted;
  final Color? accentColor;
  final VoidCallback? onClose;

  @override
  State<DetailsHeaderView> createState() => _DetailsHeaderViewState();
}

class _DetailsHeaderViewState extends State<DetailsHeaderView> {
  final _titleController = TextEditingController();
  String? _syncedTaskId;
  bool _isEditingTitle = false;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _syncController() {
    if (_syncedTaskId != widget.task.id) {
      _syncedTaskId = widget.task.id;
      _titleController.text = widget.task.title;
      _isEditingTitle = false;
    }
  }

  void _commitTitle(String value) {
    widget.onTitleSubmitted(value);
    setState(() => _isEditingTitle = false);
  }

  @override
  Widget build(BuildContext context) {
    _syncController();
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
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: Row(
              children: [
                IconButton(
                  onPressed:
                      widget.onClose ?? () => Navigator.of(context).pop(),
                  icon: Icon(
                    widget.onClose != null ? Icons.close : Icons.arrow_back,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.originListTitle,
                    style: theme.textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TaskCheckbox(
                  isChecked: widget.task.isCompleted,
                  onTap: widget.onToggleCompleted,
                  accentColor: accent,
                  size: 24,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _isEditingTitle
                      ? TextField(
                          controller: _titleController,
                          autofocus: true,
                          maxLines: null,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            decoration: widget.task.isCompleted
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: _commitTitle,
                          onTapOutside: (_) =>
                              _commitTitle(_titleController.text),
                        )
                      : GestureDetector(
                          onTap: () {
                            _titleController.text = widget.task.title;
                            setState(() => _isEditingTitle = true);
                          },
                          child: Text(
                            widget.task.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              decoration: widget.task.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                ),
                IconButton(
                  onPressed: widget.onToggleImportant,
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutBack,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: anim,
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      widget.task.isImportant ? Icons.star : Icons.star_outline,
                      key: ValueKey('header_star_${widget.task.isImportant}'),
                      color: widget.task.isImportant ? accent : secondaryText,
                    ),
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
