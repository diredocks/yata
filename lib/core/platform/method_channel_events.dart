import 'dart:async';

import 'package:flutter/services.dart';

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
