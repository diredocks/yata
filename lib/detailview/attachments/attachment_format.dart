import 'package:path/path.dart' as p;

import '../../models/task_item.dart';

/// 25 MB cumulative limit per task, matching `FileHelper.l` (`26214400` bytes).
const int kMaxTaskAttachmentTotalBytes = 25 * 1024 * 1024;

bool exceedsTaskSizeLimit(TaskItem task, int newFileBytes) {
  final existingTotal = task.attachments.fold<int>(0, (sum, a) => sum + a.size);
  return existingTotal + newFileBytes > kMaxTaskAttachmentTotalBytes;
}

String formatFileSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unitIndex = 0;
  while (value >= 1024 && unitIndex < units.length - 1) {
    value /= 1024;
    unitIndex++;
  }
  final formatted = value >= 10 || unitIndex == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$formatted ${units[unitIndex]}';
}

String? guessContentType(String fileName) {
  final ext = p.extension(fileName).toLowerCase();
  return switch (ext) {
    '.jpg' || '.jpeg' => 'image/jpeg',
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.bmp' => 'image/bmp',
    '.pdf' => 'application/pdf',
    '.txt' => 'text/plain',
    '.csv' => 'text/csv',
    '.json' => 'application/json',
    '.doc' => 'application/msword',
    '.docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    '.xls' => 'application/vnd.ms-excel',
    '.xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    '.ppt' => 'application/vnd.ms-powerpoint',
    '.pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    '.zip' => 'application/zip',
    '.mp3' => 'audio/mpeg',
    '.mp4' => 'video/mp4',
    _ => null,
  };
}
