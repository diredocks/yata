import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Registers [fonts] under [family]; overridable for tests.
typedef SystemFontRegistrar = Future<void> Function(
  String family,
  List<Uint8List> fonts,
);

/// Loads the Android system default font and applies it to the app theme.
///
/// Flutter resolves `sans-serif` through its own font manager, which does not
/// follow runtime OEM font switches (Motorola MyUX / Hello UI, Lenovo ZUI, …).
/// The platform side (see `SystemFontChannel.kt`) locates the file behind the
/// system default and streams its bytes here; [FontLoader] registers them under
/// a timestamped family so the engine cannot reuse the previous font's glyphs.
///
/// Lookups are a no-op returning `null` on iOS, web and desktop.
class SystemFontLoader {
  SystemFontLoader({MethodChannel? channel, SystemFontRegistrar? registrar})
    : _channel = channel ?? const MethodChannel(channelName),
      _registrar = registrar ?? _registerWithEngine;

  /// Same channel name as `SystemFontChannel.kt`.
  static const String channelName = 'top.clickfling.yata/system_font';

  /// Used when a glyph is missing from the loaded system font.
  static const List<String> fontFamilyFallback = <String>[
    'Noto Sans CJK SC',
    'sans-serif',
  ];

  final MethodChannel _channel;
  final SystemFontRegistrar _registrar;

  String? _family;

  /// Registered family, or `null` while the platform font is in use.
  String? get family => _family;

  /// Registers the current system font when it changed since the last call.
  Future<void> refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final payload = await _channel.invokeMapMethod<String, Object?>(
        'getSystemFont',
      );
      if (payload == null || payload['changed'] != true) return;

      final regular = payload['regular'];
      if (regular is! Uint8List || regular.isEmpty) return;

      final bold = payload['bold'];
      final fonts = <Uint8List>[
        regular,
        if (bold is Uint8List && bold.isNotEmpty) bold,
      ];

      final dynamicFamily =
          'SystemDynamicFont_${DateTime.now().microsecondsSinceEpoch}';
      await _registrar(dynamicFamily, fonts);
      _family = dynamicFamily;
    } on MissingPluginException {
      // Unsupported host or headless test without a plugin registrant.
    } on PlatformException catch (error, stack) {
      debugPrint('[SystemFontLoader] ${error.code}: ${error.message}\n$stack');
    } catch (error, stack) {
      debugPrint(
        '[SystemFontLoader] unable to load system font: $error\n$stack',
      );
    }
  }

  /// Returns [theme] with the system font applied, leaving colors, brightness
  /// and the rest of the configuration untouched.
  ThemeData applyTo(ThemeData theme) {
    final family = _family;
    if (family == null) return theme;
    return theme.copyWith(
      textTheme: theme.textTheme.apply(
        fontFamily: family,
        fontFamilyFallback: fontFamilyFallback,
      ),
      primaryTextTheme: theme.primaryTextTheme.apply(
        fontFamily: family,
        fontFamilyFallback: fontFamilyFallback,
      ),
    );
  }
}

Future<void> _registerWithEngine(String family, List<Uint8List> fonts) async {
  final loader = FontLoader(family);
  for (final font in fonts) {
    loader.addFont(Future<ByteData>.value(ByteData.sublistView(font)));
  }
  await loader.load();
}
