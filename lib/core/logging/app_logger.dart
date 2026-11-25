import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

const Duration _duplicateWindow = Duration(seconds: 3);
const int _maxTrackedMessages = 256;

class _MessageHistory {
  _MessageHistory(this.lastPrintedAt);

  DateTime lastPrintedAt;
  int suppressed = 0;
}

final Map<String, _MessageHistory> _history = <String, _MessageHistory>{};

@visibleForTesting
DateTime Function() appLogClock = DateTime.now;

bool _sinkInstalled = false;

/// App logger for [label]; installs the `debugPrint` sink on first use.
///
/// [Logger.root] defaults to [Level.INFO], so `fine` needs
/// `Logger.root.level = Level.ALL;` while debugging.
Logger appLogFor(String label) {
  if (!_sinkInstalled) {
    _sinkInstalled = true;
    Logger.root.onRecord.listen(_emit);
  }
  return Logger(label);
}

@visibleForTesting
void resetAppLogCollapse() => _history.clear();

void _emit(LogRecord record) {
  final buffer = StringBuffer(record.toString());
  if (record.error != null) buffer.write(' (${record.error})');
  if (record.stackTrace != null) buffer.write('\n${record.stackTrace}');

  final line = _collapse(buffer.toString());
  if (line != null) debugPrint(line);
}

/// Prints a repeated line once per [_duplicateWindow]; the next printed
/// occurrence reports how many were collapsed as `(xN)`.
String? _collapse(String line) {
  final now = appLogClock();
  final history = _history[line];
  if (history == null) {
    if (_history.length >= _maxTrackedMessages) _history.clear();
    _history[line] = _MessageHistory(now);
    return line;
  }
  if (now.difference(history.lastPrintedAt) < _duplicateWindow) {
    history.suppressed += 1;
    return null;
  }
  final suppressed = history.suppressed;
  history
    ..lastPrintedAt = now
    ..suppressed = 0;
  return suppressed == 0 ? line : '$line (x${suppressed + 1})';
}
