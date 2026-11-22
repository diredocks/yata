import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../accounts/manage_accounts_screen.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../onboarding/landing_screen.dart';
import '../providers/account_provider.dart';
import '../providers/todo_provider.dart';
import '../tasksview/renamelist/list_editor_dialog.dart';
import '../theme/todo_theme.dart';
import '../view/persona_avatar.dart';
import 'groups/group_dialogs.dart';
import 'groups/group_header_tile.dart';
import 'home_list_tile.dart';
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

  Future<void> _openAddAccount() async {
    setState(() => _accountMenuExpanded = false);
    await Navigator.of(context).push(
      MaterialPageRoute<bool>(
        builder: (_) => const LandingScreen(isAddingAccount: true),
      ),
    );
  }

  Future<void> _openManageAccounts() async {
    setState(() => _accountMenuExpanded = false);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ManageAccountsScreen(),
      ),
    );
  }

  void _openSettings() {
    setState(() => _accountMenuExpanded = false);
    widget.onOpenSettings();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final accountState = ref.watch(accountProvider);
    final activeAccount = accountState.activeAccount;
    final notifier = ref.read(homeViewPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final displayName = activeAccount?.displayName ?? l10n.userName;
    final displayEmail = (activeAccount?.email.isNotEmpty ?? false)
        ? activeAccount!.email
        : l10n.userSubtitle;

    final smartLists = state.lists
        .where((l) => l.isSmartList && state.isSmartListVisible(l))
        .toList();
    final customLists = state.lists.where((l) => !l.isSmartList).toList();
    final ungroupedLists =
        customLists.where((l) => l.groupId == null).toList();

    final collapsedAvatarSize = widget.isSidebar ? 32.0 : 38.0;

    return Material(
      color: isDark
          ? TodoColors.primaryBackgroundDark
          : TodoColors.primaryBackgroundLight,
      child: SafeArea(
        child: Column(
          children: [
            // Animated Header: morphs smoothly between homeview_header_collapsed.xml and homeview_header.xml
            TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _accountMenuExpanded ? 1.0 : 0.0),
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) {
                final headerHeight = lerpDouble(62, 148, t)!;
                final avatarSize = lerpDouble(collapsedAvatarSize, 64, t)!;
                final avatarLeft = lerpDouble(12, 16, t)!;
                final avatarTop = lerpDouble(12, 16, t)!;
                final textLeft = lerpDouble(
                  12 + collapsedAvatarSize + 12,
                  16,
                  t,
                )!;
                final textTop = lerpDouble(12, 88, t)!;
                final textRight = lerpDouble(52, 16, t)!;
                final nameFontSize = lerpDouble(14, 17, t)!;
                final searchOpacity = (1.0 - t * 2.0).clamp(0.0, 1.0);
                final closeOpacity = ((t - 0.5) * 2.0).clamp(0.0, 1.0);

                return InkWell(
                  onTap: () => setState(
                    () => _accountMenuExpanded = !_accountMenuExpanded,
                  ),
                  child: SizedBox(
                    height: headerHeight,
                    width: double.infinity,
                    child: Stack(
                      children: [
                        Positioned(
                          left: avatarLeft,
                          top: avatarTop,
                          child: PersonaAvatar(
                            name: displayName,
                            size: avatarSize,
                          ),
                        ),
                        Positioned(
                          left: textLeft,
                          top: textTop,
                          right: textRight,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      style:
                                          theme.textTheme.titleSmall?.copyWith(
                                        fontSize: nameFontSize,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Transform.rotate(
                                    angle: t * math.pi,
                                    child: const Icon(
                                      Icons.keyboard_arrow_down,
                                      size: 16,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                displayEmail,
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
                        if (t < 0.99)
                          Positioned(
                            right: 4,
                            top: lerpDouble(7, 12, t)!,
                            child: IgnorePointer(
                              ignoring: _accountMenuExpanded,
                              child: Opacity(
                                opacity: searchOpacity,
                                child: IconButton(
                                  onPressed: widget.onOpenSearch,
                                  icon: Icon(
                                    Icons.search,
                                    color: TodoColors.homeViewIconColor(
                                      theme.brightness,
                                    ),
                                  ),
                                  tooltip: l10n.search,
                                ),
                              ),
                            ),
                          ),
                        if (t > 0.01)
                          Positioned(
                            right: 4,
                            top: lerpDouble(7, 12, t)!,
                            child: IgnorePointer(
                              ignoring: !_accountMenuExpanded,
                              child: Opacity(
                                opacity: closeOpacity,
                                child: IconButton(
                                  onPressed: () => setState(
                                    () => _accountMenuExpanded = false,
                                  ),
                                  icon: Icon(
                                    Icons.close,
                                    color: TodoColors.homeViewIconColor(
                                      theme.brightness,
                                    ),
                                  ),
                                  tooltip: l10n.cancel,
                                ),
                              ),
                            ),
                          ),
                        if (t > 0.01)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Opacity(
                              opacity: t,
                              child: const Divider(height: 1),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Body: AnimatedSwitcher between Account Switcher and Lists
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
                    ? ListView(
                        key: const ValueKey('homeview_accounts'),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final account in accountState.accounts)
                            ListTile(
                              leading: PersonaAvatar(
                                name: account.displayName,
                                size: 38,
                              ),
                              title: Text(
                                account.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: account.id == activeAccount?.id
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                              ),
                              subtitle: Text(
                                account.email,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? TodoColors.secondaryTextDark
                                      : TodoColors.secondaryTextLight,
                                ),
                              ),
                              trailing: account.id == activeAccount?.id
                                  ? Icon(
                                      Icons.check,
                                      size: 18,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                              onTap: () async {
                                setState(() => _accountMenuExpanded = false);
                                await ref
                                    .read(accountProvider.notifier)
                                    .switchAccount(account.id);
                              },
                            ),
                          ListTile(
                            leading: const SizedBox(
                              width: 38,
                              child: Icon(Icons.add, size: 22),
                            ),
                            title: Text(l10n.addAccount),
                            onTap: _openAddAccount,
                          ),
                          ListTile(
                            leading: const SizedBox(
                              width: 38,
                              child: Icon(
                                Icons.manage_accounts_outlined,
                                size: 22,
                              ),
                            ),
                            title: Text(l10n.manageAccounts),
                            onTap: _openManageAccounts,
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            child: Divider(height: 1),
                          ),
                          ListTile(
                            leading: const SizedBox(
                              width: 38,
                              child: Icon(Icons.settings_outlined, size: 22),
                            ),
                            title: Text(l10n.settings),
                            onTap: _openSettings,
                          ),
                        ],
                      )
                    : ListView(
                        key: const ValueKey('homeview_lists'),
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          for (final list in smartLists)
                            HomeListTile(
                              title: _localizedListTitle(l10n, list),
                              icon: list.icon,
                              iconColor: TodoColors.accentFor(list.themeColor),
                              count: state.activeCountForList(list),
                              isSelected: widget.isSidebar &&
                                  state.selectedListId == list.id,
                              onTap: () => widget.onSelectList(list),
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
                                      isSelected: widget.isSidebar &&
                                          state.selectedListId == list.id,
                                      isGrouped: true,
                                      onTap: () => widget.onSelectList(list),
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
                          widget.isSidebar && state.selectedListId == list.id,
                      onTap: () => widget.onSelectList(list),
                    ),
                ],
              ),
              ),
            ),

            // Footer (home_view_footer.xml) with smooth collapse when switching accounts
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
                            final created =
                                ref.read(todoProvider).selectedList;
                            widget.onSelectList(created);
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
            ),
          ],
        ),
      ),
    );
  }
}
