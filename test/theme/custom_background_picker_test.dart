import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/data/lists/custom_background_service.dart';
import 'package:yata/ui/widgets/theme_picker_sheet.dart';
import 'package:yata/data/preferences.dart';

// Valid 1x1 transparent PNG.
final _tinyPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  late Directory tempDir;
  late File sourceFile;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'test',
    });
    tempDir = await Directory.systemTemp.createTemp('custom_bg_picker_');
    sourceFile = File(p.join(tempDir.path, 'bg.png'));
    await sourceFile.writeAsBytes(_tinyPngBytes, flush: true);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<ProviderContainer> pumpSheet(
    WidgetTester tester, {
    required Future<XFile?> Function() pickImage,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final service = CustomBackgroundService(
      baseDirProvider: () async => tempDir,
    );
    late ProviderContainer container;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          customBackgroundServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              final lists = ref.watch(todoProvider.select((s) => s.lists));
              final currentList = lists.first;
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () => showThemePickerBottomSheet(
                      context: context,
                      currentColor: currentList.themeColor,
                      currentPhoto: currentList.themePhoto,
                      currentCustomBackgroundPath:
                          currentList.customBackgroundPath,
                      pickImage: pickImage,
                      onSelectTheme: (color, photo, customPath) {
                        ref
                            .read(tasksViewPresenterProvider)
                            .changeListTheme(
                              currentList.id,
                              color,
                              themePhoto: photo,
                              customBackgroundPath: customPath,
                            );
                      },
                    ),
                    child: const Text('Open Theme'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open Theme'));
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('adds custom background and deletes it on long press', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      pickImage: () async => XFile(sourceFile.path),
    );

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('add_custom_background_button')),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (container.read(todoProvider).customBackgrounds.isNotEmpty) break;
    }
    await tester.pump(const Duration(milliseconds: 300));

    final stateAfterAdd = container.read(todoProvider);
    expect(stateAfterAdd.customBackgrounds, hasLength(1));
    final added = stateAfterAdd.customBackgrounds.first;
    expect(File(added.filePath).existsSync(), isTrue);
    expect(stateAfterAdd.lists.first.customBackgroundPath, added.filePath);

    // Long-press to delete.
    await tester.longPress(find.byKey(ValueKey('custom_theme_${added.id}')));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Delete background?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump();
      if (!File(added.filePath).existsSync()) break;
    }
    await tester.pump(const Duration(milliseconds: 300));

    final stateAfterDelete = container.read(todoProvider);
    expect(stateAfterDelete.customBackgrounds, isEmpty);
    expect(stateAfterDelete.lists.first.customBackgroundPath, isNull);
    expect(File(added.filePath).existsSync(), isFalse);
  });

  testWidgets('shows error dialog when picked image exceeds 25 MB', (
    tester,
  ) async {
    final container = await pumpSheet(
      tester,
      pickImage: () async => _OversizedXFile(
        p.join(tempDir.path, 'huge.png'),
        fakeLength: kMaxCustomBackgroundBytes + 1,
      ),
    );

    await tester.tap(find.text('Custom'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('add_custom_background_button')),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Could not set image as background. Image needs to be smaller than 25 MB.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Done'));
    await tester.pump(const Duration(milliseconds: 300));

    final state = container.read(todoProvider);
    expect(state.customBackgrounds, isEmpty);
    expect(state.lists.first.customBackgroundPath, isNull);
  });
}

class _OversizedXFile extends XFile {
  _OversizedXFile(super.path, {required this.fakeLength});

  final int fakeLength;

  @override
  Future<int> length() async => fakeLength;
}
