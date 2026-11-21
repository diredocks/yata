import 'package:material_ui/material_ui.dart';
import '../../l10n/app_localizations.dart';
import '../../models/todo_list.dart';
import '../../theme/todo_theme.dart';

/// Group header row matching `homeview/groups/GroupViewHolder`.
class GroupHeaderTile extends StatelessWidget {
  const GroupHeaderTile({
    super.key,
    required this.group,
    required this.onTap,
    required this.onModifyLists,
    required this.onRename,
    required this.onUngroup,
  });

  final ListGroup group;
  final VoidCallback onTap;
  final VoidCallback onModifyLists;
  final VoidCallback onRename;
  final VoidCallback onUngroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final secondaryColor =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          padding: const EdgeInsets.only(left: 12, right: 4),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 22,
                color: TodoColors.homeViewIconColor(theme.brightness),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  group.title,
                  style: theme.textTheme.bodyLarge?.copyWith(fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_horiz, size: 18, color: secondaryColor),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  if (value == 'modify') onModifyLists();
                  if (value == 'rename') onRename();
                  if (value == 'ungroup') onUngroup();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'modify',
                    child: ListTile(
                      leading: const Icon(Icons.format_list_bulleted),
                      title: Text(l10n.modifyGroupLists),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: ListTile(
                      leading: const Icon(Icons.drive_file_rename_outline),
                      title: Text(l10n.renameGroup),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                  PopupMenuItem(
                    value: 'ungroup',
                    child: ListTile(
                      leading: const Icon(Icons.folder_off_outlined),
                      title: Text(l10n.ungroupLists),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                  ),
                ],
              ),
              AnimatedRotation(
                turns: group.isExpanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 20,
                  color: secondaryColor,
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
