import 'dart:io';

import '../../core/logging/app_logger.dart';
import '../../models/task_item.dart';

final _log = appLogFor('Attachments');

Iterable<String> attachmentLocalPaths(Iterable<TaskItem> tasks) => tasks
    .expand((task) => task.attachments)
    .map((attachment) => attachment.localPath)
    .nonNulls
    .where((path) => path.isNotEmpty);

List<String> unreferencedAttachmentPaths(
  List<TaskItem> previousTasks,
  List<TaskItem> nextTasks,
) {
  final orphaned = attachmentLocalPaths(previousTasks).toSet();
  if (orphaned.isEmpty) return const [];
  orphaned.removeAll(attachmentLocalPaths(nextTasks));
  return orphaned.toList(growable: false);
}

Future<void> deleteAttachmentFiles(Iterable<String> paths) async {
  for (final localPath in paths) {
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (await parent.exists() && await parent.list().isEmpty) {
        await parent.delete();
      }
    } on Object catch (e) {
      _log.warning('Failed to delete local attachment cache: $e');
    }
  }
}
