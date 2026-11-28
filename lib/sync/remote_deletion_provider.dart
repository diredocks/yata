import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Entities that the sync layer dropped from local state because another
/// device (or a server-side prune / delete-wins conflict) removed them.
/// Local user deletions never reach this provider.
class RemoteDeletionNotice {
  const RemoteDeletionNotice({required this.taskIds, required this.listIds});

  final Set<String> taskIds;
  final Set<String> listIds;
}

class RemoteDeletionNotifier extends Notifier<RemoteDeletionNotice?> {
  /// Accumulated ids removed by sync in this session, queried synchronously by
  /// screens that notice their entity is gone.
  final Set<String> _removedTaskIds = <String>{};
  final Set<String> _removedListIds = <String>{};

  @override
  RemoteDeletionNotice? build() => null;

  void publish({
    Set<String> taskIds = const <String>{},
    Set<String> listIds = const <String>{},
  }) {
    if (taskIds.isEmpty && listIds.isEmpty) return;
    _removedTaskIds.addAll(taskIds);
    _removedListIds.addAll(listIds);
    state = RemoteDeletionNotice(taskIds: taskIds, listIds: listIds);
  }

  bool wasTaskRemoved(String taskId) => _removedTaskIds.contains(taskId);

  void forgetTask(String taskId) => _removedTaskIds.remove(taskId);

  bool wasListRemoved(String listId) => _removedListIds.contains(listId);
}

final remoteDeletionProvider =
    NotifierProvider<RemoteDeletionNotifier, RemoteDeletionNotice?>(
      RemoteDeletionNotifier.new,
    );
