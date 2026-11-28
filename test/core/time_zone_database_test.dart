import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:yata/core/time/local_timezone.dart';
import 'package:yata/core/time/time_zone_database.dart';

void main() {
  test('loads the shared IANA database on first access', () {
    expect(timeZoneDatabase.locations, isNotEmpty);
    expect(timeZoneDatabase.locations, contains('Asia/Shanghai'));
    expect(identical(timeZoneDatabase, tz.timeZoneDatabase), isTrue);
  });

  test('resolves the device zone against the loaded database', () {
    final reference = DateTime.utc(2026, 1, 1);
    expect(resolveLocalIanaTimeZone(reference: reference), isNotEmpty);
    expect(
      parseDateTimeInTimeZone('2026-01-01T08:00:00', 'Asia/Shanghai'),
      DateTime.utc(2026, 1, 1),
    );
  });
}
