import 'package:material_ui/material_ui.dart';

import '../../data/todo_provider.dart';
import '../../models/todo_list.dart';
import '../../theme/todo_theme.dart';
import '../home_list_tile.dart';
import 'group_dialogs.dart';
import 'group_header_tile.dart';

/// Collapsible, reorderable group entry in the home sidebar/drawer.
class HomeGroupEntryTile extends StatelessWidget {
  const HomeGroupEntryTile({
    super.key,
    required this.index,
    required this.group,
    required this.memberLists,
    required this.orderedCustomLists,
    required this.state,
    required this.isSidebar,
    required this.onToggleExpanded,
    required this.onSetGroupLists,
    required this.onRenameGroup,
    required this.onDeleteGroup,
    required this.onReorderGroupLists,
    required this.onSelectList,
  });

  final int index;
  final ListGroup group;
  final List<TodoList> memberLists;
  final List<TodoList> orderedCustomLists;
  final TodoState state;
  final bool isSidebar;
  final VoidCallback onToggleExpanded;
  final void Function(Set<String> ids) onSetGroupLists;
  final void Function(String title) onRenameGroup;
  final VoidCallback onDeleteGroup;
  final void Function(int oldIndex, int newIndex) onReorderGroupLists;
  final void Function(TodoList list) onSelectList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ReorderableDelayedDragStartListener(
          index: index,
          child: GroupHeaderTile(
            group: group,
            onTap: onToggleExpanded,
            onModifyLists: () => showGroupListsDialog(
              context: context,
              group: group,
              customLists: orderedCustomLists
                  .where((l) => l.groupId == null || l.groupId == group.id)
                  .toList(),
              onSave: onSetGroupLists,
            ),
            onRename: () => showRenameGroupDialog(
              context: context,
              initialTitle: group.title,
              onRename: onRenameGroup,
            ),
            onUngroup: onDeleteGroup,
          ),
        ),
        ClipRect(
          child: AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: group.isExpanded
                ? _buildExpandedMembers(theme)
                : const SizedBox(width: double.infinity),
          ),
        ),
      ],
    );
  }

  Widget _buildExpandedMembers(ThemeData theme) {
    if (memberLists.length < 2) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final list in memberLists) _buildMemberTile(theme, list),
        ],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      primary: false,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      proxyDecorator: (child, idx, anim) => Material(
        elevation: 4,
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(6),
        child: child,
      ),
      itemCount: memberLists.length,
      onReorderItem: onReorderGroupLists,
      itemBuilder: (ctx, memberIdx) {
        final list = memberLists[memberIdx];
        return ReorderableDelayedDragStartListener(
          key: ValueKey('group_member_${list.id}'),
          index: memberIdx,
          child: _buildMemberTile(theme, list),
        );
      },
    );
  }

  Widget _buildMemberTile(ThemeData theme, TodoList list) {
    return HomeListTile(
      title: list.title,
      emoji: list.emoji,
      icon: list.icon,
      iconColor: TodoColors.listAccentFor(list, brightness: theme.brightness),
      count: state.activeCountForList(list),
      isSelected: isSidebar && state.selectedListId == list.id,
      isGrouped: true,
      onTap: () => onSelectList(list),
    );
  }
}
