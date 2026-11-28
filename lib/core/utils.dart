import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

String generateUuidV4() => _uuid.v4();

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String localDateKey(DateTime date) => date.toIso8601String().substring(0, 10);

String sanitizePathSegment(String raw, {String fallback = 'default'}) {
  final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return cleaned.isEmpty ? fallback : cleaned;
}
