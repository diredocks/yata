import 'package:material_ui/material_ui.dart';

import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../tasksview/tasks_view_grouping.dart';
import '../theme/todo_theme.dart';
import 'groups/home_group_entry_tile.dart';
import 'home_list_tile.dart';
import 'home_view_ordering.dart';
import 'home_view_presenter.dart';

/// Scrollable smart lists and reorderable custom lists/groups in [HomeViewScreen].
class HomeSidebarListsView extends StatelessWidget {
  const HomeSidebarListsView({
    super.key,
    required this.state,
    required this.presenter,
    required this.smartLists,
    required this.orderedCustomLists,
    required this.orderedEntries,
    required this.isSidebar,
    required this.onSelectList,
  });

  final TodoState state;
  final HomeViewPresenter presenter;
  final List<TodoList> smartLists;
  final List<TodoList> orderedCustomLists;
  final List<HomeSidebarEntry> orderedEntries;
  final bool isSidebar;
  final void Function(TodoList list) onSelectList;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return CustomScrollView(
      slivers: [
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final list = smartLists[index];
            return HomeListTile(
              title: localizedListTitle(l10n, list),
              icon: list.icon,
              iconColor: TodoColors.listAccentFor(
                list,
                brightness: theme.brightness,
              ),
              count: state.activeCountForList(list),
              isSelected: isSidebar && state.selectedListId == list.id,
              onTap: () => onSelectList(list),
            );
          }, childCount: smartLists.length),
        ),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 0, 12),
            child: Divider(height: 1),
          ),
        ),
        if (orderedEntries.isNotEmpty)
          SliverReorderableList(
            itemCount: orderedEntries.length,
            proxyDecorator: (child, index, animation) => Material(
              elevation: 4,
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(6),
              child: child,
            ),
            onReorderItem: (oldIndex, newIndex) => presenter
                .reorderTopLevelEntries(orderedEntries, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final entry = orderedEntries[index];
              return switch (entry) {
                HomeListEntry(:final list) =>
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(entry.stableKey),
                    index: index,
                    child: HomeListTile(
                      title: list.title,
                      emoji: list.emoji,
                      icon: list.icon,
                      iconColor: TodoColors.listAccentFor(
                        list,
                        brightness: theme.brightness,
                      ),
                      count: state.activeCountForList(list),
                      isSelected: isSidebar && state.selectedListId == list.id,
                      onTap: () => onSelectList(list),
                    ),
                  ),
                HomeGroupEntry(:final group, lists: final memberLists) =>
                  HomeGroupEntryTile(
                    key: ValueKey(entry.stableKey),
                    index: index,
                    group: group,
                    memberLists: memberLists,
                    orderedCustomLists: orderedCustomLists,
                    state: state,
                    isSidebar: isSidebar,
                    onToggleExpanded: () =>
                        presenter.toggleGroupExpanded(group.id),
                    onSetGroupLists: (ids) =>
                        presenter.setGroupLists(group.id, ids),
                    onRenameGroup: (title) =>
                        presenter.renameGroup(group.id, title),
                    onDeleteGroup: () => presenter.deleteGroup(group.id),
                    onReorderGroupLists: (o, n) => presenter.reorderGroupLists(
                      group.id,
                      memberLists,
                      o,
                      n,
                    ),
                    onSelectList: onSelectList,
                  ),
              };
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
      ],
    );
  }
}

/// Bottom "New list" and "New group" action bar in [HomeViewScreen].
class HomeBottomActionBar extends StatelessWidget {
  const HomeBottomActionBar({
    super.key,
    required this.hidden,
    required this.onCreateList,
    required this.onCreateGroup,
  });

  final bool hidden;
  final VoidCallback onCreateList;
  final VoidCallback onCreateGroup;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final iconColor = TodoColors.homeViewIconColor(theme.brightness);

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: hidden
          ? const SizedBox(width: double.infinity)
          : ConstrainedBox(
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
                        onTap: onCreateList,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 46),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.add, size: 22, color: iconColor),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Text(
                                  l10n.newList,
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    fontSize: 15,
                                    color: iconColor,
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
                    onPressed: onCreateGroup,
                    icon: Icon(
                      Icons.create_new_folder_outlined,
                      color: iconColor,
                    ),
                    tooltip: l10n.newGroup,
                  ),
                ],
              ),
            ),
    );
  }
}
