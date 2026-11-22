import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _browserChannel = MethodChannel('top.clickfling.yata/browser');

/// Opens [url] in the system browser on desktop and Android.
Future<bool> launchExternalUrl(String url) async {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
    return false;
  }
  try {
    if (Platform.isAndroid) {
      final result = await _browserChannel.invokeMethod<bool>('openUrl', {
        'url': url,
      });
      return result ?? false;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [url], mode: ProcessStartMode.detached);
      return true;
    }
    if (Platform.isWindows) {
      await Process.start('cmd', [
        '/c',
        'start',
        '',
        url,
      ], mode: ProcessStartMode.detached);
      return true;
    }
  } catch (_) {
    return false;
  }
  return false;
}
