import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:yata/core/logging/app_logger.dart';

void main() {
  final messages = <String>[];
  late void Function(String? message, {int? wrapWidth}) originalPrint;

  setUp(() {
    messages.clear();
    resetAppLogCollapse();
    appLogClock = DateTime.now;
    Logger.root.level = Level.INFO;
    originalPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      messages.add(message ?? '');
    };
  });

  tearDown(() {
    debugPrint = originalPrint;
    Logger.root.level = Level.INFO;
  });

  test('prints [LEVEL] label: message', () {
    appLogFor('Sync').info('start');
    appLogFor('SyncEngine').severe('failed');

    expect(messages, ['[INFO] Sync: start', '[SEVERE] SyncEngine: failed']);
  });

  test('appends error and stack trace', () {
    appLogFor('NotificationTransport')
        .warning('error', 'boom', StackTrace.fromString('#0 main'));

    expect(
      messages.single,
      '[WARNING] NotificationTransport: error (boom)\n#0 main',
    );
  });

  test('gates fine on the root level', () {
    final log = appLogFor('SyncEngine');
    log.fine('patch task=1');
    expect(messages, isEmpty);

    Logger.root.level = Level.ALL;
    log.fine('patch task=1');

    expect(messages, ['[FINE] SyncEngine: patch task=1']);
  });

  test('collapses identical repeats', () {
    for (var i = 0; i < 5; i++) {
      appLogFor('SyncRealtime').info('stream done');
    }

    expect(messages, ['[INFO] SyncRealtime: stream done']);
  });

  test('reports collapsed repeats after the window', () {
    var now = DateTime.utc(2026, 1, 1);
    appLogClock = () => now;
    final log = appLogFor('SyncRealtime');

    for (var i = 0; i < 4; i++) {
      log.info('stream error=timeout');
    }
    now = now.add(const Duration(seconds: 30));
    log.info('stream error=timeout');

    expect(messages, [
      '[INFO] SyncRealtime: stream error=timeout',
      '[INFO] SyncRealtime: stream error=timeout (x4)',
    ]);
  });

  test('collapses per line, not across labels', () {
    var now = DateTime.utc(2026, 1, 1);
    appLogClock = () => now;

    appLogFor('SyncRealtime').info('done');
    appLogFor('Sync').info('done');
    now = now.add(const Duration(seconds: 30));
    appLogFor('Sync').info('done');

    expect(messages, [
      '[INFO] SyncRealtime: done',
      '[INFO] Sync: done',
      '[INFO] Sync: done',
    ]);
  });
}
