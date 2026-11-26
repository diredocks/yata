import 'dart:io';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';
import 'recyclerview/ruled_lines_painter.dart';
import 'tasks_view_bars.dart';

/// Returns whether [globalX] falls within the left/right screen edge zones
/// reserved for mobile system back-swipe gestures.
bool isInScreenEdgeZone(
  BuildContext context,
  double globalX, {
  double minEdgeWidth = 32.0,
}) {
  final mediaQuery = MediaQuery.maybeOf(context);
  if (mediaQuery == null) return false;
  final screenWidth = mediaQuery.size.width;
  if (screenWidth <= 0) return false;
  final gestureInsets = mediaQuery.systemGestureInsets;
  final leftEdge = math.max(minEdgeWidth, gestureInsets.left);
  final rightEdge = math.max(minEdgeWidth, gestureInsets.right);
  return globalX <= leftEdge || globalX >= screenWidth - rightEdge;
}

/// Animated photo or color backdrop for [TasksViewScreen].
class TasksViewBackground extends StatelessWidget {
  const TasksViewBackground({
    super.key,
    required this.currentList,
    required this.backgroundColor,
  });

  final TodoList currentList;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final customPath = currentList.customBackgroundPath;
    final photo = currentList.themePhoto;
    final Widget child;
    if (customPath != null) {
      child = SizedBox.expand(
        key: ValueKey('bg_custom_$customPath'),
        child: Image.file(
          File(customPath),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(color: backgroundColor),
        ),
      );
    } else if (photo != null) {
      child = SizedBox.expand(
        key: ValueKey('bg_photo_${photo.name}'),
        child: Image.asset(TodoColors.photoAssetFor(photo), fit: BoxFit.cover),
      );
    } else {
      child = SizedBox.expand(
        key: const ValueKey('bg_color'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          color: backgroundColor,
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: child,
    );
  }
}

/// Floating action button for adding tasks in browsing mode.
class TasksViewFab extends StatelessWidget {
  const TasksViewFab({
    super.key,
    required this.mode,
    required this.currentList,
    required this.l10n,
    required this.brightness,
    required this.onPressed,
  });

  final TasksViewMode mode;
  final TodoList currentList;
  final AppLocalizations l10n;
  final Brightness brightness;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final hideFab =
        mode != TasksViewMode.browsing ||
        currentList.smartType == SmartListType.completed;
    final fabColors = TodoColors.fabColorsFor(
      currentList,
      brightness: brightness,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => ScaleTransition(
        scale: anim,
        child: FadeTransition(opacity: anim, child: child),
      ),
      child: hideFab
          ? const SizedBox.shrink(key: ValueKey('fab_hidden'))
          : FloatingActionButton(
              key: const ValueKey('fab_visible'),
              onPressed: onPressed,
              backgroundColor: fabColors.background,
              foregroundColor: fabColors.foreground,
              tooltip: l10n.addTaskPlaceholder,
              child: const Icon(Icons.add),
            ),
    );
  }
}

/// Static list title header shown when not in browsing mode (reordering / multi-select).
class TasksCollapsedHeaderSliver extends StatelessWidget {
  const TasksCollapsedHeaderSliver({
    super.key,
    required this.listTitle,
    required this.subtitle,
    required this.headerFg,
    required this.hasBackButton,
  });

  final String listTitle;
  final String? subtitle;
  final Color headerFg;
  final bool hasBackButton;

  @override
  Widget build(BuildContext context) {
    final startPadding = hasBackButton ? 16.0 : 15.0;
    final baseTitleStyle =
        Theme.of(context).primaryTextTheme.titleLarge ?? const TextStyle();

    return SliverToBoxAdapter(
      child: SizedBox(
        height: subtitle != null ? 88.0 : 60.0,
        child: Stack(
          children: [
            Align(
              alignment: AlignmentDirectional.bottomStart,
              child: Padding(
                padding: EdgeInsetsDirectional.only(
                  start: startPadding,
                  bottom: subtitle != null ? 42.0 : 16.0,
                  end: 56,
                ),
                child: Transform.scale(
                  scale: 1.5,
                  alignment: AlignmentDirectional.bottomStart,
                  child: DefaultTextStyle(
                    style: baseTitleStyle,
                    child: Text(
                      listTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: headerFg,
                        fontWeight: FontWeight.w500,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (subtitle != null)
              Align(
                alignment: AlignmentDirectional.bottomStart,
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: startPadding,
                    bottom: 10.0,
                    end: 56,
                  ),
                  child: Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: headerFg.withValues(alpha: 0.92),
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Subtle horizontal drop shadow pinned below the collapsing header on scroll.
class TasksScrollShadow extends StatelessWidget {
  const TasksScrollShadow({
    super.key,
    required this.subtitle,
    required this.scrollOffset,
    required this.visible,
  });

  final String? subtitle;
  final double scrollOffset;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final maxTop = subtitle != null ? 144.0 : 116.0;
    return Positioned(
      top: (maxTop - scrollOffset).clamp(kToolbarHeight, maxTop) + topPadding,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: (scrollOffset > 4 && visible) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 3,
            decoration: TodoColors.horizontalShadowDecoration,
          ),
        ),
      ),
    );
  }
}

/// Notebook-style ruled lines filling the remaining viewport below tasks.
class TasksRuledLinesSliver extends StatelessWidget {
  const TasksRuledLinesSliver({
    super.key,
    required this.isDark,
    this.collapseDelta = 0.0,
  });

  final bool isDark;
  final double collapseDelta;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final minHeight =
            (constraints.viewportMainAxisExtent +
                    collapseDelta -
                    constraints.precedingScrollExtent)
                .clamp(84.0, double.infinity);
        return SliverFillRemaining(
          hasScrollBody: false,
          fillOverscroll: true,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: CustomPaint(
              painter: RuledLinesPainter(
                lineColor: isDark
                    ? TodoColors.taskViewDividerDark
                    : TodoColors.taskViewDividerLight,
                rowHeight: 66.0,
                horizontalInset: 8.0,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Returns whether [smartType] displays an illustrated empty state when empty,
/// matching `TasksViewFragment.K0` in the original app.
bool hasSmartListEmptyState(SmartListType? smartType) {
  return switch (smartType) {
    SmartListType.tasks ||
    SmartListType.important ||
    SmartListType.planned ||
    SmartListType.all ||
    SmartListType.completed => true,
    SmartListType.myDay || null => false,
  };
}

/// Illustrated empty state matching `list_empty_state.xml` and
/// `TasksViewFragment.p7`/`q7` in the original app.
class SmartListEmptyState extends StatelessWidget {
  const SmartListEmptyState({
    super.key,
    required this.l10n,
    required this.currentList,
    required this.textColor,
    required this.isDark,
  });

  final AppLocalizations l10n;
  final TodoList currentList;
  final Color textColor;
  final bool isDark;

  String? _assetName() {
    final suffix = isDark ? 'dark' : 'light';
    return switch (currentList.smartType) {
      SmartListType.tasks =>
        'assets/images/empty_state/illustration_tasks_empty_state_$suffix.png',
      SmartListType.important =>
        'assets/images/empty_state/illustration_important_empty_state_$suffix.png',
      SmartListType.planned =>
        'assets/images/empty_state/illustration_planned_empty_state_$suffix.png',
      SmartListType.all =>
        'assets/images/empty_state/illustration_all_empty_state_$suffix.png',
      SmartListType.completed =>
        'assets/images/empty_state/illustration_completed_empty_state_$suffix.png',
      SmartListType.myDay || null => null,
    };
  }

  String? _message() {
    return switch (currentList.smartType) {
      SmartListType.tasks => l10n.emptyStateTasksList,
      SmartListType.important => l10n.emptyStateImportantList,
      SmartListType.planned => l10n.emptyStatePlannedList,
      SmartListType.all => l10n.emptyStateAllList,
      SmartListType.completed => l10n.emptyStateCompletedList,
      SmartListType.myDay || null => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final asset = _assetName();
    final message = _message();
    if (asset == null || message == null) {
      return const SizedBox.shrink();
    }
    final hasPhotoBg =
        currentList.customBackgroundPath != null ||
        currentList.themePhoto != null;

    return Center(
      child: Container(
        key: ValueKey('smart_list_empty_state_${currentList.smartType!.name}'),
        width: 256,
        padding: const EdgeInsets.all(32),
        decoration: hasPhotoBg
            ? BoxDecoration(
                color: const Color(0x99323232),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 150, height: 150, fit: BoxFit.contain),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: textColor, fontSize: 16, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}
