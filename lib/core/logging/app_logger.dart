import 'package:flutter/foundation.dart';

/// The single diagnostic log sink of the app.
void appLog(String message, {String label = 'app'}) {
  debugPrint('[$label] $message');
}
