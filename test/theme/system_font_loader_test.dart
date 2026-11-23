import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yata/theme/system_font_loader.dart';
import 'package:yata/theme/todo_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(SystemFontLoader.channelName);
  final regular = Uint8List.fromList(<int>[1, 2, 3]);
  final bold = Uint8List.fromList(<int>[4, 5]);

  late List<MethodCall> calls;
  late List<(String, int)> registered;

  setUp(() {
    calls = <MethodCall>[];
    registered = <(String, int)>[];
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  void reply(Object? payload) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          return payload;
        });
  }

  SystemFontLoader createLoader() => SystemFontLoader(
    registrar: (family, fonts) async => registered.add((family, fonts.length)),
  );

  test('registers a timestamped family and applies it to the theme', () async {
    reply(<String, Object?>{'changed': true, 'regular': regular, 'bold': bold});
    final loader = createLoader();

    await loader.refresh();

    expect(loader.family, startsWith('SystemDynamicFont_'));
    expect(registered.single, (loader.family, 2));
    expect(calls.single.method, 'getSystemFont');

    final theme = loader.applyTo(TodoTheme.light());
    expect(theme.textTheme.bodyMedium?.fontFamily, loader.family);
    expect(
      theme.textTheme.bodyMedium?.fontFamilyFallback,
      SystemFontLoader.fontFamilyFallback,
    );
    expect(theme.colorScheme.primary, TodoColors.attentionLight);
  });

  test('keeps the registered family when the font did not change', () async {
    reply(<String, Object?>{'changed': true, 'regular': regular});
    final loader = createLoader();
    await loader.refresh();
    final family = loader.family;

    reply(<String, Object?>{'changed': false});
    await loader.refresh();

    expect(family, isNotNull);
    expect(loader.family, family);
    expect(registered, hasLength(1));
  });

  test('ignores a change without font bytes', () async {
    reply(<String, Object?>{'changed': true});
    final loader = createLoader();

    await loader.refresh();

    expect(loader.family, isNull);
    expect(registered, isEmpty);
  });

  test('does nothing on non-Android platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    reply(<String, Object?>{'changed': true, 'regular': regular});
    final loader = createLoader();

    await loader.refresh();

    expect(loader.family, isNull);
    expect(calls, isEmpty);
  });

  test('swallows platform errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'boom');
        });
    final loader = createLoader();

    await loader.refresh();

    expect(loader.family, isNull);
    expect(registered, isEmpty);
  });

  test('prepends the platform declared fallback families', () async {
    reply(<String, Object?>{
      'changed': true,
      'regular': regular,
      'fallbackFamilies': <String>['HYQiHei'],
    });
    final loader = createLoader();

    await loader.refresh();

    final theme = loader.applyTo(TodoTheme.light());
    expect(theme.textTheme.bodyMedium?.fontFamilyFallback, <String>[
      'HYQiHei',
      ...SystemFontLoader.fontFamilyFallback,
    ]);
  });

  test('leaves the theme untouched without a loaded font', () {
    final theme = TodoTheme.dark();

    expect(createLoader().applyTo(theme), same(theme));
  });
}
