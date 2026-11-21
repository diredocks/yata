import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../tasksview/renamelist/list_editor_dialog.dart';
import '../theme/todo_theme.dart';
import '../view/persona_avatar.dart';
import 'groups/group_dialogs.dart';
import 'groups/group_header_tile.dart';
import 'home_list_tile.dart';
import 'home_view_presenter.dart';

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
    final notifier = ref.read(homeViewPresenterProvider);
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
                    PersonaAvatar(
                      name: l10n.userName,
                      size: isSidebar ? 32 : 38,
                    ),
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
                        color: TodoColors.homeViewIconColor(theme.brightness),
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
                    HomeListTile(
                      title: _localizedListTitle(l10n, list),
                      icon: list.icon,
                      iconColor: TodoColors.accentFor(list.themeColor),
                      count: state.activeCountForList(list),
                      isSelected:
                          isSidebar && state.selectedListId == list.id,
                      onTap: () => onSelectList(list),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 12, 0, 12),
                    child: Divider(height: 1),
                  ),
                  for (final group in state.groups) ...[
                    GroupHeaderTile(
                      group: group,
                      onTap: () => notifier.toggleGroupExpanded(group.id),
                      onModifyLists: () => showGroupListsDialog(
                        context: context,
                        group: group,
                        customLists: customLists
                            .where(
                              (l) => l.groupId == null || l.groupId == group.id,
                            )
                            .toList(),
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
                    ClipRect(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: group.isExpanded
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final list in state.lists
                                      .where((l) => l.groupId == group.id))
                                    HomeListTile(
                                      title: list.title,
                                      emoji: list.emoji,
                                      icon: list.icon,
                                      iconColor:
                                          TodoColors.accentFor(list.themeColor),
                                      count: state.activeCountForList(list),
                                      isSelected: isSidebar &&
                                          state.selectedListId == list.id,
                                      isGrouped: true,
                                      onTap: () => onSelectList(list),
                                    ),
                                ],
                              )
                            : const SizedBox(width: double.infinity),
                      ),
                    ),
                  ],
                  for (final list in ungroupedLists)
                    HomeListTile(
                      title: list.title,
                      emoji: list.emoji,
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
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () async {
                          final result = await showListEditorDialog(
                            context: context,
                            dialogTitle: l10n.newList,
                            confirmLabel: l10n.create,
                          );
                          if (result != null) {
                            notifier.addList(
                              result.title,
                              result.themeColor,
                              emoji: result.emoji,
                              themePhoto: result.themePhoto,
                            );
                            final created =
                                ref.read(todoProvider).selectedList;
                            onSelectList(created);
                          }
                        },
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 46),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.add,
                                size: 22,
                                color: TodoColors.homeViewIconColor(
                                  theme.brightness,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  l10n.newList,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontSize: 15,
                                    color: TodoColors.homeViewIconColor(
                                      theme.brightness,
                                    ),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => showCreateGroupDialog(
                      context: context,
                      onCreate: (title) async {
                        final created = notifier.addGroup(title);
                        if (created == null || !context.mounted) return;
                        final eligible = ref
                            .read(todoProvider)
                            .lists
                            .where((l) => !l.isSmartList && l.groupId == null)
                            .toList();
                        if (eligible.isEmpty) return;
                        final saved = await showGroupListsDialog(
                          context: context,
                          group: created,
                          customLists: eligible,
                          onSave: (ids) =>
                              notifier.setGroupLists(created.id, ids),
                        );
                        if (saved != true) {
                          notifier.deleteGroup(created.id);
                        }
                      },
                    ),
                    icon: Icon(
                      Icons.create_new_folder_outlined,
                      color: TodoColors.homeViewIconColor(theme.brightness),
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
