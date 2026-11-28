import 'dart:async';

import 'package:flutter/services.dart';

/// Broadcasts platform-to-Dart calls of a single [method] on [channel].
///
/// The method call handler is installed on first access to [stream], so hosts
/// that never listen (desktop, tests without the plugin) install nothing.
class MethodChannelEvents<T> {
  MethodChannelEvents({
    required this.channel,
    required this.method,
    required this.decode,
  });

  final MethodChannel channel;
  final String method;
  final T Function(Object? arguments) decode;

  Stream<T>? _stream;

  Stream<T> get stream {
    final existing = _stream;
    if (existing != null) return existing;
    final controller = StreamController<T>.broadcast();
    channel.setMethodCallHandler((call) async {
      if (call.method == method) {
        controller.add(decode(call.arguments));
      }
      return null;
    });
    return _stream = controller.stream;
  }
}
