import 'dart:async';

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

  SystemFontLoader createLoader({SystemFontRegistrar? registrar}) =>
      SystemFontLoader(
        registrar:
            registrar ??
            (family, fonts) async => registered.add((family, fonts.length)),
      );

  test('registers a unique family and applies it to the theme', () async {
    reply(<String, Object?>{'changed': true, 'regular': regular, 'bold': bold});
    final loader = createLoader();

    expect(await loader.refresh(), isTrue);

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
    reply(<String, Object?>{
      'changed': true,
      'fingerprint': 'fp-1',
      'regular': regular,
    });
    final loader = createLoader();
    expect(await loader.refresh(), isTrue);
    final family = loader.family;

    reply(<String, Object?>{'changed': false, 'fingerprint': 'fp-1'});
    expect(await loader.refresh(), isFalse);

    expect(family, isNotNull);
    expect(loader.family, family);
    expect(registered, hasLength(1));
  });

  test('tracks lastFingerprint and only commits after registration succeeds', () async {
    var shouldFailRegistration = true;
    final loader = createLoader(
      registrar: (family, fonts) async {
        if (shouldFailRegistration) {
          throw StateError('font load failed');
        }
        registered.add((family, fonts.length));
      },
    );

    reply(<String, Object?>{
      'changed': true,
      'fingerprint': 'fp-1',
      'regular': regular,
    });
    expect(await loader.refresh(), isFalse);
    expect(calls.single.arguments, isNull);
    expect(loader.family, isNull);
    expect(registered, isEmpty);

    shouldFailRegistration = false;
    expect(await loader.refresh(), isTrue);
    expect(calls.last.arguments, isNull);
    expect(registered, hasLength(1));

    reply(<String, Object?>{'changed': false});
    expect(await loader.refresh(), isFalse);
    expect(calls.last.arguments, <String, Object?>{'lastFingerprint': 'fp-1'});

    reply(<String, Object?>{
      'changed': true,
      'fingerprint': 'fp-2',
      'regular': regular,
    });
    expect(await loader.refresh(), isTrue);
    expect(calls.last.arguments, <String, Object?>{'lastFingerprint': 'fp-1'});

    reply(<String, Object?>{'changed': false});
    expect(await loader.refresh(), isFalse);
    expect(calls.last.arguments, <String, Object?>{'lastFingerprint': 'fp-2'});
  });

  test('coalesces concurrent refresh calls onto a single request', () async {
    final gate = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          calls.add(call);
          await gate.future;
          return <String, Object?>{
            'changed': true,
            'fingerprint': 'fp-concurrent',
            'regular': regular,
          };
        });
    final loader = createLoader();

    final first = loader.refresh();
    final second = loader.refresh();
    gate.complete();

    expect(await Future.wait(<Future<bool>>[first, second]), <bool>[true, true]);
    expect(calls, hasLength(1));
    expect(registered, hasLength(1));
  });

  test('generates distinct family names across consecutive changes', () async {
    reply(<String, Object?>{
      'changed': true,
      'fingerprint': 'fp-1',
      'regular': regular,
    });
    final loader = createLoader();
    expect(await loader.refresh(), isTrue);
    final firstFamily = loader.family;

    reply(<String, Object?>{
      'changed': true,
      'fingerprint': 'fp-2',
      'regular': regular,
    });
    expect(await loader.refresh(), isTrue);
    final secondFamily = loader.family;

    expect(firstFamily, isNotNull);
    expect(secondFamily, isNotNull);
    expect(secondFamily, isNot(firstFamily));
  });

  test('ignores a change without font bytes', () async {
    reply(<String, Object?>{'changed': true});
    final loader = createLoader();

    expect(await loader.refresh(), isFalse);

    expect(loader.family, isNull);
    expect(registered, isEmpty);
  });

  test('does nothing on non-Android platforms', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    reply(<String, Object?>{'changed': true, 'regular': regular});
    final loader = createLoader();

    expect(await loader.refresh(), isFalse);

    expect(loader.family, isNull);
    expect(calls, isEmpty);
  });

  test('swallows platform errors', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
          throw PlatformException(code: 'boom');
        });
    final loader = createLoader();

    expect(await loader.refresh(), isFalse);

    expect(loader.family, isNull);
    expect(registered, isEmpty);
  });

  test(
    'deduplicates platform fallbacks and keeps default fallbacks at the end',
    () async {
      reply(<String, Object?>{
        'changed': true,
        'regular': regular,
        'fallbackFamilies': <Object?>[
          '',
          42,
          'sans-serif',
          'HYQiHei',
          'Noto Sans CJK SC',
          'HYQiHei',
          'CustomCJK',
        ],
      });
      final loader = createLoader();

      expect(await loader.refresh(), isTrue);

      final theme = loader.applyTo(TodoTheme.light());
      expect(theme.textTheme.bodyMedium?.fontFamilyFallback, <String>[
        'HYQiHei',
        'CustomCJK',
        ...SystemFontLoader.fontFamilyFallback,
      ]);
    },
  );

  test('leaves the theme untouched without a loaded font', () {
    final theme = TodoTheme.dark();

    expect(createLoader().applyTo(theme), same(theme));
  });
}
