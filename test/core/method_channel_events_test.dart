import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yata/core/platform/method_channel_events.dart';

const _channelName = 'test/method_channel_events';

Future<void> _send(String method, [Object? arguments]) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        _channelName,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(_channelName);

  test('decodes calls for its own method only', () async {
    final events = MethodChannelEvents<int>(
      channel: channel,
      method: 'next',
      decode: (arguments) => arguments as int,
    );
    final received = <int>[];
    final subscription = events.stream.listen(received.add);
    addTearDown(subscription.cancel);

    await _send('next', 1);
    await _send('other', 2);
    await _send('next', 3);

    expect(received, [1, 3]);
  });

  test('broadcasts to every listener from one installed handler', () async {
    final events = MethodChannelEvents<void>(
      channel: channel,
      method: 'focus',
      decode: (_) {},
    );
    var first = 0;
    var second = 0;
    final subscriptions = [
      events.stream.listen((_) => first++),
      events.stream.listen((_) => second++),
    ];
    addTearDown(() => Future.wait(subscriptions.map((s) => s.cancel())));

    await _send('focus');

    expect((first, second), (1, 1));
  });

  test('installs no handler until the stream is read', () async {
    final events = MethodChannelEvents<String>(
      channel: channel,
      method: 'ping',
      decode: (arguments) => arguments as String? ?? '',
    );

    await _send('ping', 'ignored');
    final received = <String>[];
    final subscription = events.stream.listen(received.add);
    addTearDown(subscription.cancel);
    await _send('ping', 'delivered');

    expect(received, ['delivered']);
  });
}
