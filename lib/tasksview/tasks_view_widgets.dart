import 'package:material_ui/material_ui.dart';

import '../l10n/app_localizations.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';
import 'recyclerview/ruled_lines_painter.dart';
import 'tasks_view_bars.dart';

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
    final photo = currentList.themePhoto;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: photo != null
          ? SizedBox.expand(
              key: ValueKey('bg_photo_${photo.name}'),
              child: Image.asset(
                TodoColors.photoAssetFor(photo),
                fit: BoxFit.cover,
              ),
            )
          : SizedBox.expand(
              key: const ValueKey('bg_color'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                color: backgroundColor,
              ),
            ),
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
    final isDark = brightness == Brightness.dark;
    final photo = currentList.themePhoto;

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
              backgroundColor: photo != null
                  ? TodoColors.photoFabBackgroundFor(photo)
                  : TodoColors.fabBackgroundFor(
                      currentList.themeColor,
                      brightness: brightness,
                    ),
              foregroundColor: photo != null
                  ? (isDark ? Colors.black : Colors.white)
                  : TodoColors.fabForegroundFor(
                      currentList.themeColor,
                      brightness: brightness,
                    ),
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
