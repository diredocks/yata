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
import '../theme/todo_theme.dart';
import 'groups/group_dialogs.dart';
import 'home_account_header.dart';
import 'home_sidebar_lists.dart';
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

  Future<void> _createList() async {
    final l10n = AppLocalizations.of(context);
    final presenter = ref.read(homeViewPresenterProvider);
    final result = await showListEditorDialog(
      context: context,
      dialogTitle: l10n.newList,
      confirmLabel: l10n.create,
    );
    if (result == null) return;
    presenter.addList(
      result.title,
      result.themeColor,
      emoji: result.emoji,
      themePhoto: result.themePhoto,
    );
    final created = ref.read(todoProvider).selectedList;
    widget.onSelectList(created);
  }

  void _createGroup() {
    final presenter = ref.read(homeViewPresenterProvider);
    showCreateGroupDialog(
      context: context,
      onCreate: (title) async {
        final created = presenter.addGroup(title);
        final eligible = ref
            .read(todoProvider)
            .lists
            .where((l) => !l.isSmartList && l.groupId == null)
            .toList();
        if (eligible.isEmpty || !mounted) return;
        final saved = await showGroupListsDialog(
          context: context,
          group: created,
          customLists: eligible,
          onSave: (ids) => presenter.setGroupLists(created.id, ids),
        );
        if (saved != true) {
          presenter.deleteGroup(created.id);
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final activeAccount = ref.watch(
      accountProvider.select((s) => s.activeAccount),
    );
    final presenter = ref.read(homeViewPresenterProvider);
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
                    : HomeSidebarListsView(
                        key: const ValueKey('homeview_lists'),
                        state: state,
                        presenter: presenter,
                        smartLists: smartLists,
                        orderedCustomLists: orderedCustomLists,
                        orderedEntries: orderedEntries,
                        isSidebar: widget.isSidebar,
                        onSelectList: widget.onSelectList,
                      ),
              ),
            ),
            HomeBottomActionBar(
              hidden: _accountMenuExpanded,
              onCreateList: _createList,
              onCreateGroup: _createGroup,
            ),
          ],
        ),
      ),
    );

    if (widget.isSidebar) return content;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: TodoTheme.systemUiOverlayStyleFor(theme.scaffoldBackgroundColor),
      child: content,
    );
  }
}
