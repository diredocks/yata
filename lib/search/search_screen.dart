import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../data/todo_provider.dart';
import '../tasksview/completion_sound_service.dart';
import '../theme/todo_theme.dart';
import '../tasksview/recyclerview/task_list_tile.dart';
import '../view/delayed_task_completion.dart';
import 'search_presenter.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({
    super.key,
    required this.onOpenTask,
  });

  final void Function(TaskItem task) onOpenTask;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _completionController = DelayedTaskCompletionController();
  late final SearchPresenter _presenter;
  String _query = '';
  bool _showCompleted = true;

  @override
  void initState() {
    super.initState();
    _presenter = ref.read(searchPresenterProvider);
  }

  @override
  void dispose() {
    _completionController.flushAndDispose(_presenter.setTaskCompleted);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final notifier = ref.read(searchPresenterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final trimmed = _query.trim().toLowerCase();
    final results = notifier.search(_query, showCompleted: _showCompleted);

    final bodyBg = theme.scaffoldBackgroundColor;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;

    return Scaffold(
      backgroundColor: bodyBg,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        titleSpacing: 0,
        title: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            border: InputBorder.none,
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
        actions: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: _query.isNotEmpty
                ? IconButton(
                    key: const ValueKey('search_clear_visible'),
                    onPressed: () {
                      _controller.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close),
                  )
                : const SizedBox.shrink(key: ValueKey('search_clear_hidden')),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: l10n.moreOptions,
            onSelected: (value) {
              if (value == 'toggle_completed') {
                setState(() => _showCompleted = !_showCompleted);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'toggle_completed',
                child: ListTile(
                  leading: Icon(
                    _showCompleted
                        ? Icons.visibility_off_outlined
                        : Icons.check_circle_outline,
                  ),
                  title: Text(
                    _showCompleted
                        ? l10n.hideCompletedTasks
                        : l10n.showCompletedTasks,
                  ),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: trimmed.isEmpty
            ? Center(
                key: const ValueKey('search_empty'),
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.search,
                        size: 64,
                        color: theme.disabledColor,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        l10n.searchEmptyPrompt,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : results.isEmpty
                ? Center(
                    key: const ValueKey('search_no_results'),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.searchNoResults,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: secondaryText,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    key: const ValueKey('search_results'),
                    padding: const EdgeInsets.all(8),
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final task = results[index];
                      final listName = state.lists
                          .where((l) => l.id == task.listId)
                          .map(
                            (l) => l.smartType == SmartListType.tasks
                                ? l10n.tasks
                                : l.title,
                          )
                          .firstOrNull;
                      return TaskListTile(
                        key: ValueKey('search_task_${task.id}'),
                        task: _completionController.effectiveTask(task),
                        listName: listName,
                        showMyDayBadge: true,
                        onTap: () => widget.onOpenTask(task),
                        onToggleCompleted: () {
                          if (!task.isCompleted &&
                              !_completionController.isPending(task.id)) {
                            ref
                                .read(completionSoundServiceProvider)
                                .playIfEnabled();
                          }
                          _completionController.toggle(
                            task,
                            onCommit: notifier.setTaskCompleted,
                            onStateChanged: () {
                              if (mounted) setState(() {});
                            },
                          );
                        },
                        onToggleImportant: () =>
                            notifier.toggleTaskImportant(task.id),
                      );
                    },
                  ),
      ),
    );
  }
}
