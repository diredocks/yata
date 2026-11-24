import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../account/account_provider.dart';
import '../account/manage_accounts_screen.dart';
import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../onboarding/landing_screen.dart';
import '../tasksview/renamelist/list_editor_dialog.dart';
import '../tasksview/tasks_view_grouping.dart';
import '../theme/todo_theme.dart';
import 'groups/group_dialogs.dart';
import 'groups/group_header_tile.dart';
import 'home_account_header.dart';
import 'home_list_tile.dart';
import 'home_view_ordering.dart';
import 'home_view_presenter.dart';

class HomeViewScreen extends ConsumerStatefulWidget {
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

  @override
  ConsumerState<HomeViewScreen> createState() => _HomeViewScreenState();
}

class _HomeViewScreenState extends ConsumerState<HomeViewScreen> {
  bool _accountMenuExpanded = false;

  Future<void> _openAddAccount() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const LandingScreen(isAddingAccount: true),
      ),
    );
  }

  Future<void> _openManageAccounts() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const ManageAccountsScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final accountState = ref.watch(accountProvider);
    final activeAccount = accountState.activeAccount;
    final notifier = ref.read(homeViewPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    final displayName = activeAccount?.displayName ?? l10n.userName;
    final displayEmail = (activeAccount?.email.isNotEmpty ?? false)
        ? activeAccount!.email
        : l10n.userSubtitle;

    final smartLists = state.lists
        .where((l) => l.isSmartList && state.isSmartListVisible(l))
        .toList();
    final orderedCustomLists = sortCustomListsByOrder(
      state.lists.where((l) => !l.isSmartList).toList(),
    );
    final orderedEntries = buildOrderedHomeSidebarEntries(
      groups: state.groups,
      lists: state.lists,
    );

    final collapsedAvatarSize = widget.isSidebar ? 32.0 : 38.0;

    final content = Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            HomeAccountHeader(
              displayName: displayName,
              displayEmail: displayEmail,
              activeAccount: activeAccount,
              expanded: _accountMenuExpanded,
              collapsedAvatarSize: collapsedAvatarSize,
              onToggleExpanded: () =>
                  setState(() => _accountMenuExpanded = !_accountMenuExpanded),
              onCollapse: () => setState(() => _accountMenuExpanded = false),
              onOpenSearch: widget.onOpenSearch,
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.03),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _accountMenuExpanded
                    ? HomeAccountMenuList(
                        key: const ValueKey('homeview_accounts'),
                        onSwitchAccount: (accountId) async {
                          setState(() => _accountMenuExpanded = false);
                          await ref
                              .read(accountProvider.notifier)
                              .switchAccount(accountId);
                        },
                        onAddAccount: _openAddAccount,
                        onManageAccounts: _openManageAccounts,
                        onOpenSettings: widget.onOpenSettings,
                      )
                    : CustomScrollView(
                        key: const ValueKey('homeview_lists'),
                        slivers: [
                          SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final list = smartLists[index];
                              return HomeListTile(
                                title: localizedListTitle(l10n, list),
                                icon: list.icon,
                                iconColor: TodoColors.accentFor(
                                  list.themeColor,
                                ),
                                count: state.activeCountForList(list),
                                isSelected:
                                    widget.isSidebar &&
                                    state.selectedListId == list.id,
                                onTap: () => widget.onSelectList(list),
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
                              proxyDecorator: (child, index, animation) =>
                                  Material(
                                    elevation: 4,
                                    color: theme.scaffoldBackgroundColor,
                                    borderRadius: BorderRadius.circular(6),
                                    child: child,
                                  ),
                              onReorderItem: (oldIndex, newIndex) =>
                                  notifier.reorderTopLevelEntries(
                                    orderedEntries,
                                    oldIndex,
                                    newIndex,
                                  ),
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
                                        iconColor: TodoColors.accentFor(
                                          list.themeColor,
                                        ),
                                        count: state.activeCountForList(list),
                                        isSelected:
                                            widget.isSidebar &&
                                            state.selectedListId == list.id,
                                        onTap: () => widget.onSelectList(list),
                                      ),
                                    ),
                                  HomeGroupEntry(:final group, lists: final memberLists) => Column(
                                    key: ValueKey(entry.stableKey),
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ReorderableDelayedDragStartListener(
                                        index: index,
                                        child: GroupHeaderTile(
                                          group: group,
                                          onTap: () => notifier
                                              .toggleGroupExpanded(group.id),
                                          onModifyLists: () =>
                                              showGroupListsDialog(
                                                context: context,
                                                group: group,
                                                customLists: orderedCustomLists
                                                    .where(
                                                      (l) =>
                                                          l.groupId == null ||
                                                          l.groupId == group.id,
                                                    )
                                                    .toList(),
                                                onSave: (ids) =>
                                                    notifier.setGroupLists(
                                                      group.id,
                                                      ids,
                                                    ),
                                              ),
                                          onRename: () => showRenameGroupDialog(
                                            context: context,
                                            initialTitle: group.title,
                                            onRename: (title) => notifier
                                                .renameGroup(group.id, title),
                                          ),
                                          onUngroup: () =>
                                              notifier.deleteGroup(group.id),
                                        ),
                                      ),
                                      ClipRect(
                                        child: AnimatedSize(
                                          duration: const Duration(
                                            milliseconds: 200,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          alignment: Alignment.topCenter,
                                          child: group.isExpanded
                                              ? (memberLists.length >= 2
                                                    ? ReorderableListView.builder(
                                                        shrinkWrap: true,
                                                        primary: false,
                                                        physics:
                                                            const NeverScrollableScrollPhysics(),
                                                        buildDefaultDragHandles:
                                                            false,
                                                        proxyDecorator:
                                                            (
                                                              child,
                                                              idx,
                                                              anim,
                                                            ) => Material(
                                                              elevation: 4,
                                                              color: theme
                                                                  .scaffoldBackgroundColor,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                              child: child,
                                                            ),
                                                        itemCount:
                                                            memberLists.length,
                                                        onReorderItem: (o, n) =>
                                                            notifier
                                                                .reorderGroupLists(
                                                                  group.id,
                                                                  memberLists,
                                                                  o,
                                                                  n,
                                                                ),
                                                        itemBuilder: (ctx, memberIdx) {
                                                          final list =
                                                              memberLists[memberIdx];
                                                          return ReorderableDelayedDragStartListener(
                                                            key: ValueKey(
                                                              'group_member_${list.id}',
                                                            ),
                                                            index: memberIdx,
                                                            child: HomeListTile(
                                                              title: list.title,
                                                              emoji: list.emoji,
                                                              icon: list.icon,
                                                              iconColor:
                                                                  TodoColors.accentFor(
                                                                    list.themeColor,
                                                                  ),
                                                              count: state
                                                                  .activeCountForList(
                                                                    list,
                                                                  ),
                                                              isSelected:
                                                                  widget
                                                                      .isSidebar &&
                                                                  state.selectedListId ==
                                                                      list.id,
                                                              isGrouped: true,
                                                              onTap: () => widget
                                                                  .onSelectList(
                                                                    list,
                                                                  ),
                                                            ),
                                                          );
                                                        },
                                                      )
                                                    : Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          for (final list
                                                              in memberLists)
                                                            HomeListTile(
                                                              title: list.title,
                                                              emoji: list.emoji,
                                                              icon: list.icon,
                                                              iconColor:
                                                                  TodoColors.accentFor(
                                                                    list.themeColor,
                                                                  ),
                                                              count: state
                                                                  .activeCountForList(
                                                                    list,
                                                                  ),
                                                              isSelected:
                                                                  widget
                                                                      .isSidebar &&
                                                                  state.selectedListId ==
                                                                      list.id,
                                                              isGrouped: true,
                                                              onTap: () => widget
                                                                  .onSelectList(
                                                                    list,
                                                                  ),
                                                            ),
                                                        ],
                                                      ))
                                              : const SizedBox(
                                                  width: double.infinity,
                                                ),
                                        ),
                                      ),
                                    ],
                                  ),
                                };
                              },
                            ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                        ],
                      ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: _accountMenuExpanded
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
                                    final created = ref
                                        .read(todoProvider)
                                        .selectedList;
                                    widget.onSelectList(created);
                                  }
                                },
                                child: Container(
                                  constraints: const BoxConstraints(
                                    minHeight: 46,
                                  ),
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
                                          style: theme.textTheme.bodyLarge
                                              ?.copyWith(
                                                fontSize: 15,
                                                color:
                                                    TodoColors.homeViewIconColor(
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
                                final eligible = ref
                                    .read(todoProvider)
                                    .lists
                                    .where(
                                      (l) =>
                                          !l.isSmartList && l.groupId == null,
                                    )
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
                              color: TodoColors.homeViewIconColor(
                                theme.brightness,
                              ),
                            ),
                            tooltip: l10n.newGroup,
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );

    if (widget.isSidebar) {
      return content;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: TodoTheme.systemUiOverlayStyleFor(theme.scaffoldBackgroundColor),
      child: content,
    );
  }
}
