import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils.dart';

/// Maximum allowed size for a custom background image (25 MB), matching the
/// original app's limit.
const int kMaxCustomBackgroundBytes = 25 * 1024 * 1024;

/// Thrown when the user picks an image larger than [kMaxCustomBackgroundBytes].
class CustomBackgroundTooLargeException implements Exception {
  const CustomBackgroundTooLargeException([this.sizeBytes]);

  final int? sizeBytes;

  @override
  String toString() =>
      'CustomBackgroundTooLargeException(sizeBytes: $sizeBytes)';
}

/// Persisted metadata for a user-imported custom background image.
class CustomBackground {
  const CustomBackground({required this.id, required this.filePath});

  final String id;
  final String filePath;

  Map<String, dynamic> toJson() => {'id': id, 'filePath': filePath};

  static CustomBackground? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final filePath = raw['filePath'];
    if (id is! String || id.isEmpty) return null;
    if (filePath is! String || filePath.isEmpty) return null;
    return CustomBackground(id: id, filePath: filePath);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CustomBackground &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          filePath == other.filePath;

  @override
  int get hashCode => Object.hash(id, filePath);
}

/// Copies and deletes custom background image files without compressing them.
class CustomBackgroundService {
  CustomBackgroundService({Future<Directory> Function()? baseDirProvider})
    : _baseDirProvider = baseDirProvider ?? getApplicationDocumentsDirectory;

  static const Uuid _uuid = Uuid();

  final Future<Directory> Function() _baseDirProvider;

  /// Validates that [source] does not exceed [kMaxCustomBackgroundBytes] and
  /// copies it as-is (without compression) into app-private storage.
  Future<CustomBackground> savePickedImage(
    XFile source, {
    required String accountKey,
  }) async {
    final length = await source.length();
    if (length > kMaxCustomBackgroundBytes) {
      throw CustomBackgroundTooLargeException(length);
    }

    final baseDir = await _baseDirProvider();
    final targetDir = Directory(
      p.join(
        baseDir.path,
        'custom_backgrounds',
        sanitizePathSegment(accountKey),
      ),
    );
    await targetDir.create(recursive: true);

    final id = _uuid.v4();
    final ext = p.extension(source.path);
    final fileName = ext.isNotEmpty ? '$id$ext' : id;
    final destPath = p.join(targetDir.path, fileName);

    final sourceFile = File(source.path);
    if (await sourceFile.exists()) {
      await sourceFile.copy(destPath);
    } else {
      final bytes = await source.readAsBytes();
      if (bytes.length > kMaxCustomBackgroundBytes) {
        throw CustomBackgroundTooLargeException(bytes.length);
      }
      await File(destPath).writeAsBytes(bytes, flush: true);
    }

    return CustomBackground(id: id, filePath: destPath);
  }

  /// Deletes the local image file at [filePath] if it exists.
  Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } on FileSystemException {
      // Best-effort cleanup; ignore if the file was already removed.
    }
  }
}
