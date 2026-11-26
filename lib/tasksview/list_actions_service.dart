import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../core/logging/app_logger.dart';

final _log = appLogFor('ListActionsService');

const String kShortcutChannelName = 'top.clickfling.yata/shortcut';

enum ShortcutPinResult { requested, updated }

String shortcutIdForList(String? accountId, String listId) =>
    '${accountId ?? 'local'}|$listId';

/// Bridges list-level platform actions: Share (via `share_plus`), Print (via
/// `printing`), and Homescreen Shortcut (via Android [kShortcutChannelName]).
class ListActionsService {
  const ListActionsService();

  static const MethodChannel _channel = MethodChannel(kShortcutChannelName);

  static bool get _isFlutterTest =>
      Platform.environment.containsKey('FLUTTER_TEST');

  static bool get _isAndroid =>
      !kIsWeb && !_isFlutterTest && Platform.isAndroid;

  Future<bool> isPrintSupported() async {
    if (_isFlutterTest) return false;
    try {
      final info = await Printing.info();
      // `printing`'s Android plugin omits `canConvertHtml` from `printingInfo()`,
      // leaving `info.canConvertHtml == false` even though `convertHtml` works.
      return info.canPrint;
    } on Object catch (e) {
      _log.warning('isPrintSupported failed: $e');
      return false;
    }
  }

  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException catch (e) {
      _log.warning('$method plugin unavailable: $e');
      return null;
    } on PlatformException catch (e) {
      _log.warning('$method failed: $e');
      return null;
    }
  }

  Future<bool> isShortcutSupported() async =>
      await _invoke<bool>('isShortcutSupported') ?? false;

  Future<bool> isShortcutPinned(String shortcutId) async {
    if (shortcutId.isEmpty) return false;
    return await _invoke<bool>('isShortcutPinned', {
          'shortcutId': shortcutId,
        }) ??
        false;
  }

  Future<ShortcutPinResult?> pinOrUpdateShortcut({
    required String shortcutId,
    required String listId,
    required String label,
    required int colorArgb,
    String? smartType,
    String? emoji,
  }) async {
    final result = await _invoke<String>('pinOrUpdateShortcut', {
      'shortcutId': shortcutId,
      'listId': listId,
      'label': label,
      'colorArgb': colorArgb,
      'smartType': smartType,
      'emoji': emoji,
    });
    return switch (result) {
      'updated' => ShortcutPinResult.updated,
      'requested' => ShortcutPinResult.requested,
      _ => null,
    };
  }

  Future<bool> shareText({
    required String subject,
    required String text,
  }) async {
    if (_isFlutterTest || text.isEmpty) return false;
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: subject.isEmpty ? null : subject),
      );
      return true;
    } on Object catch (e) {
      _log.warning('shareText failed: $e');
      return false;
    }
  }

  Future<bool> printHtml({
    required String jobName,
    required String html,
  }) async {
    if (_isFlutterTest) return false;
    try {
      final info = await Printing.info();
      if (!info.canPrint) return false;
      await Printing.layoutPdf(
        name: jobName,
        // Native WebView HTML->PDF preserves system CJK and emoji fonts
        // without bundling large font assets into the app.
        onLayout: (format) =>
            // ignore: deprecated_member_use
            Printing.convertHtml(format: format, html: html),
      );
      return true;
    } on Object catch (e) {
      _log.warning('printHtml failed: $e');
      return false;
    }
  }
}

final listActionsServiceProvider = Provider<ListActionsService>(
  (_) => const ListActionsService(),
);

final listPrintSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(listActionsServiceProvider).isPrintSupported(),
);

final shortcutSupportedProvider = FutureProvider<bool>(
  (ref) => ref.watch(listActionsServiceProvider).isShortcutSupported(),
);

final shortcutPinnedProvider = FutureProvider.family<bool, String>((
  ref,
  shortcutId,
) async {
  final supported = await ref.watch(shortcutSupportedProvider.future);
  if (!supported) return false;
  return ref.watch(listActionsServiceProvider).isShortcutPinned(shortcutId);
});
