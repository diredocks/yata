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
  // On mobile (< 600px), toggle between HomeView (lists) and TasksView.
  bool _showingTasksOnMobile = false;

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
      setState(() => _showingTasksOnMobile = true);
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
      if (_showingTasksOnMobile) {
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && _showingTasksOnMobile) {
              setState(() => _showingTasksOnMobile = false);
            }
          },
          child: TasksViewScreen(
            onBackPressed: () => setState(() => _showingTasksOnMobile = false),
            onOpenTask: (task) => _handleOpenTask(task, false),
          ),
        );
      }

      return HomeViewScreen(
        onSelectList: (list) => _handleSelectList(list, false),
        onOpenSearch: _openSearch,
        onOpenSettings: _openSettings,
      );
    }

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
          if (isExtraWide && state.selectedTaskId != null) ...[
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
        ],
      ),
    );
  }
}
