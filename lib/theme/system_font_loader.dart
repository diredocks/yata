import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

typedef SystemFontRegistrar = Future<void> Function(
  String family,
  List<Uint8List> fonts,
);

class SystemFontLoader {
  SystemFontLoader({MethodChannel? channel, SystemFontRegistrar? registrar})
    : _channel = channel ?? const MethodChannel(channelName),
      _registrar = registrar ?? _registerWithEngine;

  static const String channelName = 'top.clickfling.yata/system_font';

  static const List<String> fontFamilyFallback = <String>[
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  final MethodChannel _channel;
  final SystemFontRegistrar _registrar;

  String? _family;
  String? _fingerprint;
  List<String> _fontFamilyFallback = fontFamilyFallback;
  int _generation = 0;
  Future<bool>? _inFlight;

  String? get family => _family;

  Future<bool> refresh() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Future<bool>.value(false);
    }
    return _inFlight ??= _refresh().whenComplete(() => _inFlight = null);
  }

  Future<bool> _refresh() async {
    try {
      final args = _fingerprint == null
          ? null
          : <String, Object?>{'lastFingerprint': _fingerprint};
      final payload = await _channel.invokeMapMethod<String, Object?>(
        'getSystemFont',
        args,
      );
      if (payload == null || payload['changed'] != true) return false;

      final regular = payload['regular'];
      if (regular is! Uint8List || regular.isEmpty) return false;

      final bold = payload['bold'];
      final fonts = <Uint8List>[
        regular,
        if (bold is Uint8List && bold.isNotEmpty) bold,
      ];

      final dynamicFamily =
          'SystemDynamicFont_${DateTime.now().microsecondsSinceEpoch}_${++_generation}';
      await _registrar(dynamicFamily, fonts);

      final fingerprint = payload['fingerprint'];
      _family = dynamicFamily;
      _fingerprint = fingerprint is String && fingerprint.isNotEmpty
          ? fingerprint
          : null;
      _fontFamilyFallback = _mergeFallbacks(payload['fallbackFamilies']);
      return true;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error, stack) {
      debugPrint('[SystemFontLoader] ${error.code}: ${error.message}\n$stack');
      return false;
    } catch (error, stack) {
      debugPrint(
        '[SystemFontLoader] unable to load system font: $error\n$stack',
      );
      return false;
    }
  }

  ThemeData applyTo(ThemeData theme) {
    final family = _family;
    if (family == null) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: family,
        fontFamilyFallback: _fontFamilyFallback,
      ),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: family,
        fontFamilyFallback: _fontFamilyFallback,
      ),
    );
  }
}

List<String> _mergeFallbacks(Object? value) {
  if (value is! List || value.isEmpty) {
    return SystemFontLoader.fontFamilyFallback;
  }
  final merged = <String>[];
  for (final name in value) {
    if (name is String &&
        name.isNotEmpty &&
        !SystemFontLoader.fontFamilyFallback.contains(name) &&
        !merged.contains(name)) {
      merged.add(name);
    }
  }
  if (merged.isEmpty) {
    return SystemFontLoader.fontFamilyFallback;
  }
  return List<String>.unmodifiable(<String>[
    ...merged,
    ...SystemFontLoader.fontFamilyFallback,
  ]);
}

Future<void> _registerWithEngine(String family, List<Uint8List> fonts) async {
  final loader = FontLoader(family);
  for (final font in fonts) {
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(font)));
  }
  await loader.load();
}
