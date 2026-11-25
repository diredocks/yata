import 'package:collection/collection.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/task_item.dart';
import '../data/todo_provider.dart';
import '../tasksview/tasks_view_presenter.dart';

/// Presenter for `search/SearchFragment`.
class SearchPresenter {
  SearchPresenter(this._ref);

  final Ref _ref;

  List<TaskItem> search(String query, {bool showCompleted = true}) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];
    final tokens = trimmed.split(RegExp(r'\s+'));

    bool matchesAll(String text) {
      final lower = text.toLowerCase();
      return tokens.every(lower.contains);
    }

    final tasks = _ref.read(todoProvider).tasks;
    final matched = <(TaskItem, DateTime)>[];
    for (final task in tasks) {
      if (!showCompleted && task.isCompleted) continue;
      final titleMatch = matchesAll(task.title);
      final stepMatch = task.steps.any(
        (s) => (showCompleted || !s.isCompleted) && matchesAll(s.title),
      );
      final noteMatch = matchesAll(task.note);
      if (titleMatch || stepMatch || noteMatch) {
        final sortTime = (titleMatch || stepMatch)
            ? task.createdAt
            : (task.noteUpdatedAt ?? task.createdAt);
        matched.add((task, sortTime));
      }
    }
    return matched
        .sortedByCompare((item) => item.$2, (a, b) => b.compareTo(a))
        .map((item) => item.$1)
        .toList();
  }

  void toggleTaskCompleted(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskCompleted(taskId);
  }

  void setTaskCompleted(String taskId, {required bool completed}) {
    _ref
        .read(tasksViewPresenterProvider)
        .setTaskCompleted(taskId, completed: completed);
  }

  void toggleTaskImportant(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskImportant(taskId);
  }
}

final searchPresenterProvider = Provider<SearchPresenter>((ref) {
  return SearchPresenter(ref);
});
