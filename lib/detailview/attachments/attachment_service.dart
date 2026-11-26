import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:result_dart/result_dart.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../account/account_provider.dart';
import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/todo_settings_store.dart';
import '../../models/account.dart';
import '../../models/task_item.dart';
import '../../sync/sync_provider.dart';

final _log = appLogFor('Attachments');

/// 25 MB cumulative limit per task, matching `FileHelper.l` (`26214400` bytes).
const int kMaxTaskAttachmentTotalBytes = 25 * 1024 * 1024;

final attachmentServiceProvider = Provider<AttachmentService>((ref) {
  return AttachmentService(ref);
});

/// Handles local caching, size validation, remote download, and opening
/// attachments via `open_file` or `url_launcher`.
class AttachmentService {
  AttachmentService(
    this._ref, {
    Future<Directory> Function()? storageRootProvider,
    String? Function()? accountIdProvider,
    Future<OpenResult> Function(String filePath, {String? type})? openFileFn,
    Future<bool> Function(Uri uri)? launchUrlFn,
  }) : _storageRootProvider =
           storageRootProvider ?? getApplicationSupportDirectory,
       _accountIdProvider =
           accountIdProvider ??
           (() => _ref.read(accountProvider).activeAccountId),
       _openFileFn = openFileFn ?? _defaultOpenFile,
       _launchUrlFn = launchUrlFn ?? _defaultLaunchUrl;

  final Ref _ref;
  final Future<Directory> Function() _storageRootProvider;
  final String? Function() _accountIdProvider;
  final Future<OpenResult> Function(String filePath, {String? type})
  _openFileFn;
  final Future<bool> Function(Uri uri) _launchUrlFn;

  static Future<OpenResult> _defaultOpenFile(String filePath, {String? type}) {
    return OpenFile.open(filePath, type: type);
  }

  static Future<bool> _defaultLaunchUrl(Uri uri) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static String sanitizeFileName(String raw) {
    final base = p.basename(raw.trim());
    final cleaned = base.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    return cleaned.isEmpty ? 'attachment' : cleaned;
  }

  static String formatFileSize(int bytes) {
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

  static String? guessContentType(String fileName) {
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
      '.docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
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

  bool exceedsTaskSizeLimit(TaskItem task, int newFileBytes) {
    final existingTotal = task.attachments.fold<int>(
      0,
      (sum, a) => sum + a.size,
    );
    return existingTotal + newFileBytes > kMaxTaskAttachmentTotalBytes;
  }

  static String sanitizePathSegment(String raw, {String fallback = 'default'}) {
    final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  String _resolveAccountId([String? explicitAccountId]) {
    if (explicitAccountId != null && explicitAccountId.isNotEmpty) {
      return explicitAccountId;
    }
    final provided = _accountIdProvider();
    if (provided != null && provided.isNotEmpty) {
      return provided;
    }
    return 'default';
  }

  Future<String> _resolveTargetPath({
    required String attachmentId,
    required String fileName,
    String? accountId,
  }) async {
    final root = await _storageRootProvider();
    final safeAccountId = sanitizePathSegment(
      _resolveAccountId(accountId),
      fallback: 'default',
    );
    final safeId = sanitizePathSegment(attachmentId, fallback: 'att');
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
    required String attachmentId,
    required String sourcePath,
    required String fileName,
    String? accountId,
  }) async {
    final sourceFile = File(sourcePath);
    final targetPath = await _resolveTargetPath(
      attachmentId: attachmentId,
      fileName: fileName,
      accountId: accountId,
    );
    await sourceFile.copy(targetPath);
    final size = await File(targetPath).length();
    return (localPath: targetPath, size: size);
  }

  /// Writes [bytes] into app-private per-account attachment storage and returns
  /// the path.
  Future<String> saveAttachmentBytes({
    required String attachmentId,
    required String fileName,
    required Uint8List bytes,
    String? accountId,
  }) async {
    final targetPath = await _resolveTargetPath(
      attachmentId: attachmentId,
      fileName: fileName,
      accountId: accountId,
    );
    await File(targetPath).writeAsBytes(bytes, flush: true);
    return targetPath;
  }

  /// Deletes the local cached file (and its parent attachment directory if empty).
  Future<void> deleteLocalCache(String? localPath) async {
    if (localPath == null || localPath.isEmpty) return;
    try {
      final file = File(localPath);
      if (await file.exists()) {
        await file.delete();
      }
      final parent = file.parent;
      if (await parent.exists() && (await parent.list().isEmpty)) {
        await parent.delete();
      }
    } catch (e) {
      _log.warning('Failed to delete local attachment cache: $e');
    }
  }

  /// Deletes local cache files for [removedAttachments] that are not still
  /// referenced by any task in [remainingTasks].
  Future<void> deleteUnreferencedCaches(
    Iterable<TaskAttachment> removedAttachments, {
    required Iterable<TaskItem> remainingTasks,
  }) async {
    final referencedPaths = <String>{
      for (final task in remainingTasks)
        for (final att in task.attachments)
          if (att.localPath != null && att.localPath!.isNotEmpty)
            att.localPath!,
    };
    final pathsToDelete = <String>{
      for (final att in removedAttachments)
        if (att.localPath != null &&
            att.localPath!.isNotEmpty &&
            !referencedPaths.contains(att.localPath))
          att.localPath!,
    };
    for (final path in pathsToDelete) {
      await deleteLocalCache(path);
    }
  }

  /// Deletes the entire local attachment directory for [accountId].
  Future<void> deleteAccountAttachments(String accountId) async {
    try {
      final root = await _storageRootProvider();
      final safeAccountId = sanitizePathSegment(accountId, fallback: 'default');
      final accountDir = Directory(
        p.join(root.path, 'attachments', safeAccountId),
      );
      if (await accountDir.exists()) {
        await accountDir.delete(recursive: true);
      }
    } catch (e) {
      _log.warning('Failed to delete account attachments: $e');
    }
  }

  /// Downloads a remote attachment using the active Microsoft account context
  /// and saves it to local cache.
  AsyncAppResult<String> downloadAttachment(TaskAttachment attachment) async {
    final webLink = attachment.webLink;
    if (webLink == null || webLink.trim().isEmpty) {
      return const Failure(
        AppError.unknown(message: 'Attachment has no download URL'),
      );
    }
    final activeAccount = _ref.read(accountProvider).activeAccount;
    if (activeAccount is! MicrosoftAccount) {
      return const Failure(
        AppError.auth(
          message: 'No active Microsoft account for attachment download',
        ),
      );
    }
    final prefs = _ref.read(sharedPreferencesProvider);
    final settings = TodoSettingsStore(prefs, accountId: activeAccount.id);
    final syncService = _ref.read(cloudSyncServiceProvider);

    final ctxResult = await syncService.resolveContext(activeAccount, settings);
    if (ctxResult.isError()) {
      return Failure(ctxResult.exceptionOrNull()!);
    }
    final ctx = ctxResult.getOrThrow();

    final bytesResult = await syncService.todoApi.downloadAttachment(
      ctx,
      webLink,
    );
    if (bytesResult.isError()) {
      return Failure(bytesResult.exceptionOrNull()!);
    }
    final bytes = bytesResult.getOrThrow();
    final savedPath = await saveAttachmentBytes(
      attachmentId: attachment.id,
      fileName: attachment.displayName,
      bytes: bytes,
      accountId: activeAccount.id,
    );
    return Success(savedPath);
  }

  /// Opens a local file using `open_file` or a web link using `url_launcher`.
  Future<AppResult<Unit>> openAttachment(TaskAttachment attachment) async {
    if (attachment.isLinkOnly && attachment.webLink != null) {
      final uri = Uri.tryParse(attachment.webLink!);
      if (uri != null) {
        final launched = await _launchUrlFn(uri);
        if (launched) return const Success(unit);
      }
      return const Failure(AppError.unknown(message: 'Failed to open link'));
    }

    final localPath = attachment.localPath;
    if (localPath == null ||
        localPath.isEmpty ||
        !await File(localPath).exists()) {
      return const Failure(
        AppError.unknown(message: 'Attachment is not cached locally'),
      );
    }

    final result = await _openFileFn(localPath, type: attachment.contentType);
    if (result.type == ResultType.done) {
      return const Success(unit);
    }
    _log.warning('OpenFile failed: ${result.type} ${result.message}');
    return Failure(
      AppError.unknown(
        message: result.message.isNotEmpty
            ? result.message
            : 'Unable to open file (${result.type.name})',
      ),
    );
  }
}
