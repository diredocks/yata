import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:yata/data/lists/custom_background_service.dart';

void main() {
  late Directory tempDir;
  late CustomBackgroundService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('custom_bg_test_');
    service = CustomBackgroundService(baseDirProvider: () async => tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('savePickedImage copies file without compression', () async {
    final sourceFile = File(p.join(tempDir.path, 'source.png'));
    final bytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
    await sourceFile.writeAsBytes(bytes, flush: true);

    final saved = await service.savePickedImage(
      XFile(sourceFile.path),
      accountKey: 'acct_1',
    );

    expect(saved.id, isNotEmpty);
    expect(
      saved.filePath,
      startsWith(p.join(tempDir.path, 'custom_backgrounds', 'acct_1')),
    );
    expect(saved.filePath, endsWith('.png'));
    expect(await File(saved.filePath).readAsBytes(), equals(bytes));
  });

  test(
    'savePickedImage throws CustomBackgroundTooLargeException over 25 MB',
    () async {
      final fakeLargeXFile = _OversizedXFile(
        p.join(tempDir.path, 'huge.jpg'),
        fakeLength: kMaxCustomBackgroundBytes + 1,
      );

      await expectLater(
        service.savePickedImage(fakeLargeXFile, accountKey: 'acct_1'),
        throwsA(isA<CustomBackgroundTooLargeException>()),
      );
    },
  );

  test('deleteFile removes existing file and ignores missing file', () async {
    final target = File(p.join(tempDir.path, 'to_delete.webp'));
    await target.writeAsBytes([1, 2, 3]);
    expect(await target.exists(), isTrue);

    await service.deleteFile(target.path);
    expect(await target.exists(), isFalse);

    // Deleting again should not throw.
    await service.deleteFile(target.path);
  });
}

class _OversizedXFile extends XFile {
  _OversizedXFile(super.path, {required this.fakeLength});

  final int fakeLength;

  @override
  Future<int> length() async => fakeLength;
}
