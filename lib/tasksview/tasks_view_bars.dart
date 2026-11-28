import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../data/state/todo_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../theme/todo_theme.dart';
import 'tasks_view_dialogs.dart';

enum TasksViewMode { browsing, reordering, multiSelecting }

enum ListMenuAction {
  rename,
  sort,
  groupBy,
  reorder,
  addShortcut,
  changeTheme,
  sendCopy,
  duplicate,
  printList,
  delete,
}

enum MultiSelectAction { selectOrClearAll, important, move, copy, delete }

PopupMenuItem<T> buildTasksPopupMenuItem<T>({
  required T value,
  required IconData icon,
  required String label,
  Color? color,
}) {
  return PopupMenuItem<T>(
    value: value,
    child: ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: color != null ? TextStyle(color: color) : null),
      contentPadding: EdgeInsets.zero,
      dense: true,
    ),
  );
}

bool supportsListReordering(TodoList list) {
  final isCustom = !list.isSmartList;
  return (isCustom ||
          list.smartType == SmartListType.myDay ||
          list.smartType == SmartListType.tasks) &&
      list.sortOption == TaskSortOption.defaultOrder;
}

bool supportsTaskReordering(TodoList list, int activeTasksCount) {
  return supportsListReordering(list) && activeTasksCount >= 2;
}

List<PopupMenuEntry<ListMenuAction>> buildListMenuItems(
  AppLocalizations l10n,
  TodoList list,
  int activeTasksCount, {
  required bool showShortcut,
  required bool isShortcutPinned,
  required bool showPrint,
}) {
  final isCustom = !list.isSmartList;
  final supportsSort =
      isCustom ||
      list.smartType == SmartListType.myDay ||
      list.smartType == SmartListType.important ||
      list.smartType == SmartListType.all ||
      list.smartType == SmartListType.completed ||
      list.smartType == SmartListType.tasks;
  final supportsReorder = supportsTaskReordering(list, activeTasksCount);

  return [
    if (isCustom)
      buildTasksPopupMenuItem(
        value: ListMenuAction.rename,
        icon: Icons.edit_outlined,
        label: l10n.renameList,
      ),
    if (supportsSort)
      buildTasksPopupMenuItem(
        value: ListMenuAction.sort,
        icon: Icons.sort,
        label: l10n.sortBy,
      ),
    if (list.smartType == SmartListType.planned)
      buildTasksPopupMenuItem(
        value: ListMenuAction.groupBy,
        icon: Icons.view_agenda_outlined,
        label: l10n.groupBy,
      ),
    if (supportsReorder)
      buildTasksPopupMenuItem(
        value: ListMenuAction.reorder,
        icon: Icons.reorder,
        label: l10n.reorderTasks,
      ),
    if (showShortcut)
      buildTasksPopupMenuItem(
        value: ListMenuAction.addShortcut,
        icon: Icons.add_to_home_screen_outlined,
        label: isShortcutPinned ? l10n.updateShortcut : l10n.addShortcut,
      ),
    buildTasksPopupMenuItem(
      value: ListMenuAction.changeTheme,
      icon: Icons.palette_outlined,
      label: l10n.changeTheme,
    ),
    buildTasksPopupMenuItem(
      value: ListMenuAction.sendCopy,
      icon: Icons.share_outlined,
      label: l10n.sendCopy,
    ),
    if (isCustom)
      buildTasksPopupMenuItem(
        value: ListMenuAction.duplicate,
        icon: Icons.copy_outlined,
        label: l10n.duplicateList,
      ),
    if (showPrint)
      buildTasksPopupMenuItem(
        value: ListMenuAction.printList,
        icon: Icons.print_outlined,
        label: l10n.printList,
      ),
    if (isCustom) ...[
      const PopupMenuDivider(),
      buildTasksPopupMenuItem(
        value: ListMenuAction.delete,
        icon: Icons.delete_outline,
        label: l10n.deleteList,
        color: TodoColors.overdueRed,
      ),
    ],
  ];
}

PreferredSizeWidget buildReorderingAppBar({
  required AppLocalizations l10n,
  required bool isDark,
  required SystemUiOverlayStyle overlayStyle,
  required VoidCallback onExitReordering,
}) {
  return AppBar(
    systemOverlayStyle: overlayStyle,
    backgroundColor: isDark
        ? TodoColors.primaryBackgroundDark
        : TodoColors.secondaryTextLight,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    scrolledUnderElevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.25),
    leading: IconButton(
      onPressed: onExitReordering,
      icon: const Icon(Icons.arrow_back),
    ),
    title: Text(l10n.reorderTasks),
    actions: [
      IconButton(
        tooltip: l10n.done,
        onPressed: onExitReordering,
        icon: const Icon(Icons.check),
      ),
    ],
  );
}

PreferredSizeWidget buildMultiSelectAppBar({
  required AppLocalizations l10n,
  required TodoState state,
  required TodoList currentList,
  required List<TaskItem> allTasks,
  required Set<String> multiSelectedIds,
  required bool isDark,
  required SystemUiOverlayStyle overlayStyle,
  required VoidCallback onClearSelection,
  required VoidCallback onBatchAddToMyDay,
  required VoidCallback onBatchPickDueDate,
  required ValueChanged<MultiSelectAction> onSelectAction,
}) {
  final selectedTasks = state.tasks
      .where((t) => multiSelectedIds.contains(t.id))
      .toList();
  final canBatchAddToMyDay =
      currentList.smartType != SmartListType.myDay &&
      selectedTasks.any((t) => !t.isInMyDay);
  final canBatchMarkImportant =
      currentList.smartType != SmartListType.important &&
      selectedTasks.any((t) => !t.isImportant);
  final allSelected =
      allTasks.isNotEmpty &&
      allTasks.every((t) => multiSelectedIds.contains(t.id));

  return AppBar(
    systemOverlayStyle: overlayStyle,
    backgroundColor: isDark
        ? TodoColors.primaryBackgroundDark
        : TodoColors.secondaryTextLight,
    foregroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 4,
    scrolledUnderElevation: 4,
    shadowColor: Colors.black.withValues(alpha: 0.25),
    leading: IconButton(
      onPressed: onClearSelection,
      icon: const Icon(Icons.close),
    ),
    title: Text('${multiSelectedIds.length}'),
    actions: [
      if (canBatchAddToMyDay)
        IconButton(
          tooltip: l10n.addToMyDay,
          onPressed: onBatchAddToMyDay,
          icon: const Icon(Icons.wb_sunny_outlined),
        ),
      IconButton(
        tooltip: l10n.addDueDate,
        onPressed: onBatchPickDueDate,
        icon: const Icon(Icons.calendar_today_outlined),
      ),
      PopupMenuButton<MultiSelectAction>(
        icon: const Icon(Icons.more_vert),
        tooltip: l10n.moreOptions,
        onSelected: onSelectAction,
        itemBuilder: (_) => [
          buildTasksPopupMenuItem(
            value: MultiSelectAction.selectOrClearAll,
            icon: allSelected ? Icons.deselect_outlined : Icons.select_all,
            label: allSelected ? l10n.clearAll : l10n.selectAll,
          ),
          if (canBatchMarkImportant)
            buildTasksPopupMenuItem(
              value: MultiSelectAction.important,
              icon: Icons.star_outline,
              label: l10n.important,
            ),
          buildTasksPopupMenuItem(
            value: MultiSelectAction.move,
            icon: Icons.drive_file_move_outlined,
            label: l10n.moveToList,
          ),
          buildTasksPopupMenuItem(
            value: MultiSelectAction.copy,
            icon: Icons.copy_outlined,
            label: l10n.copyTasks,
          ),
          buildTasksPopupMenuItem(
            value: MultiSelectAction.delete,
            icon: Icons.delete_outline,
            label: l10n.delete,
          ),
        ],
      ),
    ],
  );
}

class TasksSliverAppBar extends StatelessWidget {
  const TasksSliverAppBar({
    super.key,
    required this.l10n,
    required this.currentList,
    required this.listTitle,
    required this.subtitle,
    required this.headerFg,
    required this.backgroundColor,
    required this.activeTasksCount,
    required this.showShortcut,
    required this.isShortcutPinned,
    required this.showPrint,
    required this.isDark,
    required this.overlayStyle,
    required this.onBackPressed,
    required this.onScrollToTop,
    required this.onSelectMenuAction,
  });

  final AppLocalizations l10n;
  final TodoList currentList;
  final String listTitle;
  final String? subtitle;
  final Color headerFg;
  final Color backgroundColor;
  final int activeTasksCount;
  final bool showShortcut;
  final bool isShortcutPinned;
  final bool showPrint;
  final bool isDark;
  final SystemUiOverlayStyle overlayStyle;
  final VoidCallback? onBackPressed;
  final VoidCallback onScrollToTop;
  final ValueChanged<ListMenuAction> onSelectMenuAction;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      systemOverlayStyle: overlayStyle,
      backgroundColor: Colors.transparent,
      foregroundColor: headerFg,
      expandedHeight: subtitle != null ? 144 : 116,
      pinned: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      leading: onBackPressed != null
          ? IconButton(
              onPressed: onBackPressed,
              icon: Icon(Icons.arrow_back, color: headerFg),
            )
          : null,
      automaticallyImplyLeading: onBackPressed != null,
      actions: [
        PopupMenuButton<ListMenuAction>(
          icon: Icon(Icons.more_vert, color: headerFg),
          tooltip: l10n.moreOptions,
          onSelected: onSelectMenuAction,
          itemBuilder: (_) => buildListMenuItems(
            l10n,
            currentList,
            activeTasksCount,
            showShortcut: showShortcut,
            isShortcutPinned: isShortcutPinned,
            showPrint: showPrint,
          ),
        ),
      ],
      flexibleSpace: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onDoubleTap: onScrollToTop,
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                child:
                    (currentList.customBackgroundPath != null ||
                        currentList.themePhoto != null)
                    ? Stack(
                        key: ValueKey(
                          currentList.customBackgroundPath != null
                              ? 'header_custom_${currentList.customBackgroundPath}'
                              : 'header_photo_${currentList.themePhoto!.name}',
                        ),
                        fit: StackFit.expand,
                        children: [
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final fullHeight = MediaQuery.sizeOf(context)
                                  .height;
                              return OverflowBox(
                                minWidth: constraints.maxWidth,
                                maxWidth: constraints.maxWidth,
                                minHeight: fullHeight,
                                maxHeight: fullHeight,
                                alignment: Alignment.topCenter,
                                child: currentList.customBackgroundPath != null
                                    ? Image.file(
                                        File(currentList.customBackgroundPath!),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) =>
                                            Container(color: backgroundColor),
                                      )
                                    : Image.asset(
                                        TodoColors.photoAssetFor(
                                          currentList.themePhoto!,
                                        ),
                                        fit: BoxFit.cover,
                                      ),
                              );
                            },
                          ),
                          Container(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.35 : 0.12,
                            ),
                          ),
                        ],
                      )
                    : SizedBox.expand(
                        key: const ValueKey('header_color'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          color: backgroundColor,
                        ),
                      ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final topPadding = MediaQuery.paddingOf(context).top;
                  final collapsedHeight = kToolbarHeight + topPadding;
                  final expandedHeight =
                      (subtitle != null ? 144.0 : 116.0) + topPadding;
                  final denom = expandedHeight - collapsedHeight;
                  final t = ((expandedHeight - constraints.maxHeight) / denom)
                      .clamp(0.0, 1.0);
                  final startPad = onBackPressed != null
                      ? 16.0 + 40.0 * t
                      : 15.0;
                  final bottomPad = subtitle != null ? 42.0 - 26.0 * t : 16.0;
                  final subtitleSize = 20.0 - 7.0 * t;

                  return FlexibleSpaceBar(
                    expandedTitleScale: 1.5,
                    titlePadding: EdgeInsetsDirectional.only(
                      start: startPad,
                      bottom: bottomPad,
                      end: 56,
                    ),
                    title: Text(
                      listTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: headerFg,
                        fontWeight: FontWeight.w500,
                        fontSize: 20,
                      ),
                    ),
                    background: subtitle != null
                        ? Align(
                            alignment: AlignmentDirectional.bottomStart,
                            child: Padding(
                              padding: EdgeInsetsDirectional.only(
                                start: startPad,
                                bottom: 10.0 - 4.0 * t,
                                end: 56,
                              ),
                              child: Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: headerFg.withValues(alpha: 0.92),
                                  fontSize: subtitleSize,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                          )
                        : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color tasksBannerBackgroundColor(BuildContext context, TodoList currentList) {
  if (currentList.customBackgroundPath != null ||
      currentList.themePhoto != null) {
    return Colors.black.withValues(alpha: 0.35);
  }
  if (Theme.of(context).brightness == Brightness.dark) {
    return Colors.white.withValues(alpha: 0.10);
  }
  return TodoColors.isLightTheme(currentList.themeColor)
      ? Colors.white.withValues(alpha: 0.72)
      : Colors.black.withValues(alpha: 0.25);
}

class TasksSortBanner extends StatelessWidget {
  const TasksSortBanner({
    super.key,
    required this.l10n,
    required this.currentList,
    required this.headerFg,
    required this.onToggleSortDirection,
    required this.onClearSort,
  });

  final AppLocalizations l10n;
  final TodoList currentList;
  final Color headerFg;
  final VoidCallback onToggleSortDirection;
  final VoidCallback onClearSort;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 32),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: tasksBannerBackgroundColor(context, currentList),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: onToggleSortDirection,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                l10n.sortedBy(
                                  sortOptionLabel(l10n, currentList.sortOption),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: headerFg,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: currentList.sortAscending ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeInOut,
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                color: headerFg,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                InkWell(
                  onTap: onClearSort,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 20, color: headerFg),
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

class TasksPlannedFilterBanner extends StatelessWidget {
  const TasksPlannedFilterBanner({
    super.key,
    required this.l10n,
    required this.currentList,
    required this.currentFilter,
    required this.headerFg,
    required this.onTap,
  });

  final AppLocalizations l10n;
  final TodoList currentList;
  final PlannedDueDateFilter currentFilter;
  final Color headerFg;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 32),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: tasksBannerBackgroundColor(context, currentList),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.filter_list, size: 18, color: headerFg),
                    const SizedBox(width: 6),
                    Text(
                      plannedFilterLabel(l10n, currentFilter),
                      style: TextStyle(
                        color: headerFg,
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.keyboard_arrow_down, size: 18, color: headerFg),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TasksBucketPill extends StatelessWidget {
  const TasksBucketPill({
    super.key,
    required this.label,
    required this.count,
    required this.isExpanded,
    required this.onTap,
    required this.currentList,
    required this.headerFg,
  });

  final String label;
  final int count;
  final bool isExpanded;
  final VoidCallback onTap;
  final TodoList currentList;
  final Color headerFg;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: tasksBannerBackgroundColor(context, currentList),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedRotation(
                    turns: isExpanded ? 0.25 : 0.0,
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.fastOutSlowIn,
                    child: Icon(
                      Icons.keyboard_arrow_right,
                      color: headerFg,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: headerFg,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: headerFg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
