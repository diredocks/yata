import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';
import 'tasks_view_bars.dart';
import 'tasks_view_widgets.dart';

/// Scrollable body of [TasksViewScreen] combining the collapsing header,
/// task slivers, ruled lines, scroll shadow, and optional pull-to-refresh.
class TasksViewScrollBody extends StatelessWidget {
  const TasksViewScrollBody({
    super.key,
    required this.l10n,
    required this.state,
    required this.currentList,
    required this.listTitle,
    required this.subtitle,
    required this.headerFg,
    required this.backgroundColor,
    required this.accentColor,
    required this.activeTasksCount,
    required this.isDark,
    required this.isMicrosoft,
    required this.mode,
    required this.scrollOffset,
    required this.scrollController,
    required this.nestedScrollKey,
    required this.overlayStyle,
    required this.hasBackButton,
    required this.taskSlivers,
    required this.onBackPressed,
    required this.onScrollToTop,
    required this.onSelectMenuAction,
    required this.onToggleSortDirection,
    required this.onClearSort,
    required this.onOpenPlannedFilter,
    required this.onScrollOffsetChanged,
    required this.onScrollEnd,
    required this.onPointerDown,
    required this.onPointerMove,
    required this.onPointerEnd,
    required this.onRefresh,
  });

  final AppLocalizations l10n;
  final TodoState state;
  final TodoList currentList;
  final String listTitle;
  final String? subtitle;
  final Color headerFg;
  final Color backgroundColor;
  final Color accentColor;
  final int activeTasksCount;
  final bool isDark;
  final bool isMicrosoft;
  final TasksViewMode mode;
  final double scrollOffset;
  final ScrollController scrollController;
  final GlobalKey<NestedScrollViewState> nestedScrollKey;
  final SystemUiOverlayStyle overlayStyle;
  final bool hasBackButton;
  final List<Widget> taskSlivers;

  final VoidCallback? onBackPressed;
  final VoidCallback onScrollToTop;
  final void Function(ListMenuAction action) onSelectMenuAction;
  final VoidCallback onToggleSortDirection;
  final VoidCallback onClearSort;
  final VoidCallback onOpenPlannedFilter;
  final ValueChanged<double> onScrollOffsetChanged;
  final ValueChanged<double> onScrollEnd;
  final ValueChanged<double> onPointerDown;
  final void Function(double pointerY, double visibleTop) onPointerMove;
  final VoidCallback onPointerEnd;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final scrollBehavior = ScrollConfiguration.of(context);
    final topPadding = MediaQuery.paddingOf(context).top;
    final physics = isMicrosoft ? const AlwaysScrollableScrollPhysics() : null;

    final nestedScroll = NotificationListener<ScrollNotification>(
      onNotification: (notification) => _handleScrollNotification(notification),
      child: ScrollConfiguration(
        behavior: scrollBehavior.copyWith(overscroll: false),
        child: NestedScrollView(
          key: nestedScrollKey,
          controller: scrollController,
          physics: physics,
          headerSliverBuilder: (headerContext, _) => [
            _buildHeaderSliver(headerContext),
          ],
          body: Builder(
            builder: (bodyContext) =>
                _buildInnerScrollView(bodyContext, scrollBehavior, physics),
          ),
        ),
      ),
    );

    final scrollWithShadow = Stack(
      children: [
        nestedScroll,
        TasksScrollShadow(
          subtitle: subtitle,
          scrollOffset: scrollOffset,
          visible: mode == TasksViewMode.browsing,
        ),
      ],
    );

    if (!isMicrosoft || mode == TasksViewMode.reordering) {
      return scrollWithShadow;
    }

    return RefreshIndicator(
      edgeOffset: topPadding,
      notificationPredicate: _refreshNotificationPredicate,
      onRefresh: onRefresh,
      color: accentColor,
      backgroundColor: isDark
          ? TodoColors.primaryBackgroundDark
          : TodoColors.primaryBackgroundLight,
      child: scrollWithShadow,
    );
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final offset = notification.metrics.pixels;
    if ((offset - scrollOffset).abs() > 0.5) {
      onScrollOffsetChanged(offset);
    }
    if (notification is ScrollEndNotification) {
      final collapseDelta = (subtitle != null ? 144.0 : 116.0) - kToolbarHeight;
      onScrollEnd(collapseDelta);
    }
    return false;
  }

  bool _refreshNotificationPredicate(ScrollNotification notification) {
    if (notification.depth > 1) return false;
    // Ignore outer header expand/collapse scroll updates so pulling down while
    // the header is collapsed expands the header first before triggering refresh.
    if (notification is ScrollUpdateNotification &&
        notification.depth == 0 &&
        notification.metrics.pixels >= 0) {
      return false;
    }
    return true;
  }

  Widget _buildHeaderSliver(BuildContext headerContext) {
    return SliverOverlapAbsorber(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(headerContext),
      sliver: mode == TasksViewMode.browsing
          ? TasksSliverAppBar(
              l10n: l10n,
              currentList: currentList,
              listTitle: listTitle,
              subtitle: subtitle,
              headerFg: headerFg,
              backgroundColor: backgroundColor,
              activeTasksCount: activeTasksCount,
              isDark: isDark,
              overlayStyle: overlayStyle,
              onBackPressed: onBackPressed,
              onScrollToTop: onScrollToTop,
              onSelectMenuAction: onSelectMenuAction,
            )
          : TasksCollapsedHeaderSliver(
              listTitle: listTitle,
              subtitle: subtitle,
              headerFg: headerFg,
              hasBackButton: hasBackButton,
            ),
    );
  }

  Widget _buildInnerScrollView(
    BuildContext bodyContext,
    ScrollBehavior scrollBehavior,
    ScrollPhysics? physics,
  ) {
    final topPadding = MediaQuery.paddingOf(bodyContext).top;
    final collapsedHeight = kToolbarHeight + topPadding;
    final expandedHeight = (subtitle != null ? 144.0 : 116.0) + topPadding;
    final visibleTop = mode == TasksViewMode.browsing
        ? (expandedHeight - scrollOffset).clamp(collapsedHeight, expandedHeight)
        : collapsedHeight;

    final showSortBanner =
        currentList.sortOption != TaskSortOption.defaultOrder &&
        mode != TasksViewMode.reordering;
    final showPlannedFilterBanner =
        currentList.smartType == SmartListType.planned &&
        mode == TasksViewMode.browsing;

    return ScrollConfiguration(
      behavior: scrollBehavior,
      child: Listener(
        onPointerDown: (event) => onPointerDown(event.position.dy),
        onPointerMove: (event) => onPointerMove(event.position.dy, visibleTop),
        onPointerUp: (_) => onPointerEnd(),
        onPointerCancel: (_) => onPointerEnd(),
        child: CustomScrollView(
          physics: physics,
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(
                bodyContext,
              ),
            ),
            if (showSortBanner)
              TasksSortBanner(
                l10n: l10n,
                currentList: currentList,
                headerFg: headerFg,
                onToggleSortDirection: onToggleSortDirection,
                onClearSort: onClearSort,
              ),
            if (showPlannedFilterBanner)
              TasksPlannedFilterBanner(
                l10n: l10n,
                currentList: currentList,
                currentFilter: state.plannedDueDateFilter,
                headerFg: headerFg,
                onTap: onOpenPlannedFilter,
              ),
            ...taskSlivers,
            TasksRuledLinesSliver(isDark: isDark),
          ],
        ),
      ),
    );
  }
}
