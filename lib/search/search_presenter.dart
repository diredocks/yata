import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_item.dart';
import '../providers/todo_provider.dart';
import '../tasksview/tasks_view_presenter.dart';

/// Presenter for `search/SearchFragment`.
class SearchPresenter {
  SearchPresenter(this._ref);

  final Ref _ref;

  List<TaskItem> search(String query) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];
    final tasks = _ref.read(todoProvider).tasks;
    return tasks
        .where(
          (t) =>
              t.title.toLowerCase().contains(trimmed) ||
              t.note.toLowerCase().contains(trimmed),
        )
        .toList();
  }

  void toggleTaskCompleted(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskCompleted(taskId);
  }

  void toggleTaskImportant(String taskId) {
    _ref.read(tasksViewPresenterProvider).toggleTaskImportant(taskId);
  }
}

final searchPresenterProvider = Provider<SearchPresenter>((ref) {
  return SearchPresenter(ref);
});
