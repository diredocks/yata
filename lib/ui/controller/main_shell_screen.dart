import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../detailview/detail_view_screen.dart';
import '../../homeview/home_view_screen.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import '../../providers/todo_provider.dart';
import '../../search/search_screen.dart';
import '../../settings/settings_screen.dart';
import '../../tasksview/tasks_view_screen.dart';

class MainShellScreen extends ConsumerStatefulWidget {
  const MainShellScreen({super.key});

  @override
  ConsumerState<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends ConsumerState<MainShellScreen> {
  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (ctx) => SearchScreen(
          onOpenTask: (task) {
            Navigator.of(ctx).push(
              MaterialPageRoute<void>(
                builder: (_) => DetailViewScreen(taskId: task.id),
              ),
            );
          },
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  void _handleSelectList(TodoList list, bool isWide) {
    ref.read(todoProvider.notifier).selectList(list.id);
    if (!isWide) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (routeCtx) => TasksViewScreen(
            onBackPressed: () => Navigator.of(routeCtx).pop(),
            onOpenTask: (task) => _handleOpenTask(task, false),
          ),
        ),
      );
    }
  }

  void _handleOpenTask(TaskItem task, bool isWide) {
    if (isWide) {
      ref.read(todoProvider.notifier).selectTask(task.id);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DetailViewScreen(taskId: task.id),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 600;
    final isExtraWide = width >= 960;

    if (!isWide) {
      return HomeViewScreen(
        onSelectList: (list) => _handleSelectList(list, false),
        onOpenSearch: _openSearch,
        onOpenSettings: _openSettings,
      );
    }

    final showDetail = isExtraWide && state.selectedTaskId != null;

    // Wide layout (tablet / desktop, inspired by activity_main_duo.xml)
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: HomeViewScreen(
              isSidebar: true,
              onSelectList: (list) => _handleSelectList(list, true),
              onOpenSearch: _openSearch,
              onOpenSettings: _openSettings,
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: TasksViewScreen(
              onOpenTask: (task) => _handleOpenTask(task, isExtraWide),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                ...previousChildren,
                ?currentChild,
              ],
            ),
            transitionBuilder: (child, animation) => SizeTransition(
              axis: Axis.horizontal,
              alignment: AlignmentDirectional.centerStart,
              sizeFactor: animation,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            ),
            child: showDetail
                ? Row(
                    key: ValueKey('detail_${state.selectedTaskId}'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: 360,
                        child: DetailViewScreen(
                          taskId: state.selectedTaskId!,
                          onClose: () =>
                              ref.read(todoProvider.notifier).selectTask(null),
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(key: ValueKey('detail_empty')),
          ),
        ],
      ),
    );
  }
}
