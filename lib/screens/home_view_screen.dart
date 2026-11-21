import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import '../widgets/list_theme_picker.dart';
import '../widgets/persona_avatar.dart';

class HomeViewScreen extends ConsumerWidget {
  const HomeViewScreen({
    super.key,
    required this.onSelectList,
    required this.onOpenSearch,
    required this.onOpenSettings,
    this.isSidebar = false,
  });

  final void Function(TodoList list) onSelectList;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSettings;
  final bool isSidebar;

  String _localizedListTitle(AppLocalizations l10n, TodoList list) {
    return switch (list.smartType) {
      SmartListType.myDay => l10n.myDay,
      SmartListType.important => l10n.important,
      SmartListType.planned => l10n.planned,
      SmartListType.all => l10n.all,
      SmartListType.completed => l10n.completedList,
      SmartListType.tasks => l10n.tasks,
      null => list.title,
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(todoProvider);
    final notifier = ref.read(todoProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final smartLists = state.lists
        .where((l) => l.isSmartList && state.isSmartListVisible(l))
        .toList();
    final customLists = state.lists.where((l) => !l.isSmartList).toList();
    final ungroupedLists =
        customLists.where((l) => l.groupId == null).toList();

    return Material(
      color: isDark
          ? TodoColors.primaryBackgroundDark
          : TodoColors.primaryBackgroundLight,
      child: SafeArea(
        child: Column(
          children: [
            // Header (homeview_header_collapsed.xml)
            InkWell(
              onTap: onOpenSettings,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    PersonaAvatar(name: l10n.userName, size: 36),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  l10n.userName,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down, size: 16),
                            ],
                          ),
                          Text(
                            l10n.userSubtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isDark
                                  ? TodoColors.secondaryTextDark
                                  : TodoColors.secondaryTextLight,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onOpenSearch,
                      icon: Icon(
                        Icons.search,
                        color: isDark
                            ? TodoColors.attentionDark
                            : TodoColors.attentionLight,
                      ),
                      tooltip: l10n.search,
                    ),
                  ],
                ),
              ),
            ),

            // Lists (Smart lists + divider + groups & custom lists)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final list in smartLists)
                    _HomeListTile(
                      title: _localizedListTitle(l10n, list),
                      icon: list.icon,
                      iconColor: TodoColors.accentFor(list.themeColor),
                      count: state.activeCountForList(list),
                      isSelected:
                          isSidebar && state.selectedListId == list.id,
                      onTap: () => onSelectList(list),
                    ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Divider(height: 1),
                  ),
                  for (final group in state.groups) ...[
                    _GroupHeaderTile(
                      group: group,
                      onTap: () => notifier.toggleGroupExpanded(group.id),
                      onModifyLists: () => showGroupListsDialog(
                        context: context,
                        group: group,
                        customLists: customLists,
                        onSave: (ids) => notifier.setGroupLists(group.id, ids),
                      ),
                      onRename: () => showRenameGroupDialog(
                        context: context,
                        initialTitle: group.title,
                        onRename: (title) =>
                            notifier.renameGroup(group.id, title),
                      ),
                      onUngroup: () => notifier.deleteGroup(group.id),
                    ),
                    if (group.isExpanded)
                      for (final list in state.lists
                          .where((l) => l.groupId == group.id))
                        _HomeListTile(
                          title: list.title,
                          icon: list.icon,
                          iconColor: TodoColors.accentFor(list.themeColor),
                          count: state.activeCountForList(list),
                          isSelected:
                              isSidebar && state.selectedListId == list.id,
                          isGrouped: true,
                          onTap: () => onSelectList(list),
                        ),
                  ],
                  for (final list in ungroupedLists)
                    _HomeListTile(
                      title: list.title,
                      icon: list.icon,
                      iconColor: TodoColors.accentFor(list.themeColor),
                      count: state.activeCountForList(list),
                      isSelected:
                          isSidebar && state.selectedListId == list.id,
                      onTap: () => onSelectList(list),
                    ),
                ],
              ),
            ),

            // Footer (home_view_footer.xml)
            const Divider(height: 1),
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => showCreateListDialog(
                        context: context,
                        onCreate: (title, color) {
                          notifier.addList(title, color);
                          final created = ref.read(todoProvider).selectedList;
                          onSelectList(created);
                        },
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add,
                              color: isDark
                                  ? TodoColors.attentionDark
                                  : TodoColors.attentionLight,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              l10n.newList,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: isDark
                                    ? TodoColors.attentionDark
                                    : TodoColors.attentionLight,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => showCreateGroupDialog(
                      context: context,
                      onCreate: notifier.addGroup,
                    ),
                    icon: Icon(
                      Icons.create_new_folder_outlined,
                      color: isDark
                          ? TodoColors.attentionDark
                          : TodoColors.attentionLight,
                    ),
                    tooltip: l10n.newGroup,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeListTile extends StatelessWidget {
  const _HomeListTile({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.count,
    required this.onTap,
    this.isSelected = false,
    this.isGrouped = false,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final int count;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isGrouped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : TodoColors.blue100.withValues(alpha: 0.08);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Material(
        color: isSelected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 46),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isGrouped) ...[
                  Container(
                    width: 2,
                    height: 20,
                    margin: const EdgeInsets.only(left: 4, right: 12),
                    color: theme.dividerColor,
                  ),
                ],
                Icon(icon, size: 22, color: iconColor),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontSize: 15,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (count > 0)
                  Text(
                    '$count',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? TodoColors.secondaryTextDark
                          : TodoColors.secondaryTextLight,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupHeaderTile extends StatelessWidget {
  const _GroupHeaderTile({
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
              Icon(Icons.folder_outlined, size: 22, color: secondaryColor),
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
                    child: Text(l10n.modifyGroupLists),
                  ),
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l10n.renameGroup),
                  ),
                  PopupMenuItem(
                    value: 'ungroup',
                    child: Text(l10n.ungroupLists),
                  ),
                ],
              ),
              Icon(
                group.isExpanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                size: 20,
                color: secondaryColor,
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}
