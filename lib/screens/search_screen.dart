import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../l10n/app_localizations.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
import '../providers/todo_provider.dart';
import '../theme/todo_theme.dart';
import '../widgets/task_list_tile.dart';

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
  String _query = '';
  bool _showCompleted = true;

  @override
  void initState() {
    super.initState();
    _showCompleted = ref.read(todoProvider).showCompleted;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todoProvider);
    final notifier = ref.read(todoProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final trimmed = _query.trim().toLowerCase();
    final results = trimmed.isEmpty
        ? const <TaskItem>[]
        : state.tasks.where((task) {
            if (!_showCompleted && task.isCompleted) return false;
            final matchesTitle = task.title.toLowerCase().contains(trimmed);
            final matchesNote = task.note.toLowerCase().contains(trimmed);
            final matchesStep = task.steps.any(
              (s) => s.title.toLowerCase().contains(trimmed),
            );
            return matchesTitle || matchesNote || matchesStep;
          }).toList();

    final bodyBg = isDark
        ? TodoColors.primaryBackgroundDark
        : TodoColors.secondaryBackgroundLight;
    final secondaryText =
        isDark ? TodoColors.secondaryTextDark : TodoColors.secondaryTextLight;

    return Scaffold(
      backgroundColor: bodyBg,
      appBar: AppBar(
        backgroundColor: isDark
            ? TodoColors.secondaryBackgroundDark
            : TodoColors.primaryBackgroundLight,
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
          if (_query.isNotEmpty)
            IconButton(
              onPressed: () {
                _controller.clear();
                setState(() => _query = '');
              },
              icon: const Icon(Icons.close),
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
      body: trimmed.isEmpty
          ? Center(
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
                      task: task,
                      listName: listName,
                      showMyDayBadge: true,
                      onTap: () => widget.onOpenTask(task),
                      onToggleCompleted: () =>
                          notifier.toggleTaskCompleted(task.id),
                      onToggleImportant: () =>
                          notifier.toggleTaskImportant(task.id),
                    );
                  },
                ),
    );
  }
}
