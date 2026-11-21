import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../models/task_item.dart';
import '../../theme/todo_theme.dart';

/// Note editor card matching `detailview/note/NoteCardView` (`detailview_note.xml`).
class NoteCardView extends StatefulWidget {
  const NoteCardView({
    super.key,
    required this.task,
    required this.cardColor,
    required this.onNoteChanged,
  });

  final TaskItem task;
  final Color cardColor;
  final ValueChanged<String> onNoteChanged;

  @override
  State<NoteCardView> createState() => _NoteCardViewState();
}

class _NoteCardViewState extends State<NoteCardView> {
  final _noteController = TextEditingController();
  String? _syncedTaskId;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _syncController() {
    if (_syncedTaskId != widget.task.id) {
      _syncedTaskId = widget.task.id;
      _noteController.text = widget.task.note;
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncController();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;

    return Card(
      color: widget.cardColor,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 132),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextField(
                controller: _noteController,
                minLines: 4,
                maxLines: null,
                decoration: InputDecoration(
                  hintText: l10n.addNotePlaceholder,
                  border: InputBorder.none,
                ),
                onChanged: widget.onNoteChanged,
              ),
              if (widget.task.noteUpdatedAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.updatedOn(
                    DateFormat.MMMd()
                        .add_jm()
                        .format(widget.task.noteUpdatedAt!),
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
