import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';

final _log = appLogFor('ListActionsService');

const String kListActionsChannelName = 'top.clickfling.yata/list_actions';

enum ShortcutPinResult { requested, updated }

/// Bridges list-level platform actions (Share, Print, and Homescreen Shortcut)
/// to Android via [kListActionsChannelName], matching `yp/n`, `fq/i`, and
/// `wo/c0` in `mstodo.apk`.
class ListActionsService {
  const ListActionsService();

  static const MethodChannel _channel = MethodChannel(kListActionsChannelName);

  static bool get _isAndroid =>
      !kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      Platform.isAndroid;

  bool get isPrintSupported => _isAndroid;

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
  }) async =>
      await _invoke<bool>('shareText', {'subject': subject, 'text': text}) ??
      false;

  Future<bool> printHtml({
    required String jobName,
    required String html,
  }) async =>
      await _invoke<bool>('printHtml', {'jobName': jobName, 'html': html}) ??
      false;
}

final listActionsServiceProvider = Provider<ListActionsService>(
  (_) => const ListActionsService(),
);
