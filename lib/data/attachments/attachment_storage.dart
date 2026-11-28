import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';

final _log = appLogFor('Attachments');

final attachmentStorageProvider = Provider<AttachmentStorage>((ref) {
  return AttachmentStorage();
});

/// App-private, per-account attachment layout on disk.
///
/// Owned by the data layer because deleting an account must remove exactly the
/// bytes written here. The detail view borrows it to stage and open files, but
/// does not own the layout.
class AttachmentStorage {
  AttachmentStorage({Future<Directory> Function()? storageRootProvider})
    : _storageRootProvider =
          storageRootProvider ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _storageRootProvider;

  static String sanitizeFileName(String raw) {
    final base = p.basename(raw.trim());
    final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  static String _sanitizeSegment(String raw, String fallback) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  Future<String> resolveTargetPath({
    required String accountId,
    required String attachmentId,
    required String fileName,
  }) async {
    final root = await _storageRootProvider();
    final safeAccountId = _sanitizeSegment(accountId, 'default');
    final safeId = _sanitizeSegment(attachmentId, 'att');
    final safeName = sanitizeFileName(fileName);
    final dir = Directory(
      p.join(root.path, 'attachments', safeAccountId, safeId),
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return p.join(dir.path, safeName);
  }

  /// Copies [sourcePath] into app-private per-account attachment storage and
  /// returns the stored path and byte size.
  Future<({String localPath, int size})> stageLocalFile({
    required String accountId,
    required String attachmentId,
    required String sourcePath,
    required String fileName,
  }) async {
    final sourceFile = File(sourcePath);
    final targetPath = await resolveTargetPath(
      accountId: accountId,
      attachmentId: attachmentId,
      fileName: fileName,
    );
    await sourceFile.copy(targetPath);
    final size = await File(targetPath).length();
    return (localPath: targetPath, size: size);
  }

  /// Writes [bytes] into app-private per-account attachment storage and returns
  /// the path.
  Future<String> saveBytes({
    required String accountId,
    required String attachmentId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final targetPath = await resolveTargetPath(
      accountId: accountId,
      attachmentId: attachmentId,
      fileName: fileName,
    );
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  /// Deletes the entire local attachment directory for [accountId].
  Future<void> deleteAccountAttachments(String accountId) async {
    try {
      final root = await _storageRootProvider();
      final safeAccountId = _sanitizeSegment(accountId, 'default');
      final accountDir = Directory(
        p.join(root.path, 'attachments', safeAccountId),
      );
      if (accountDir.existsSync()) {
        accountDir.deleteSync(recursive: true);
      }
    } catch (e) {
      _log.warning('Failed to delete account attachments: $e');
    }
  }
}
