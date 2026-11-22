import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in the system browser on desktop and Android.
Future<bool> launchExternalUrl(String url) async {
  if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) {
    return false;
  }
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}
