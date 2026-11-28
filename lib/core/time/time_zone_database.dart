import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// `package:timezone`'s process-wide IANA database, loaded on first access.
///
/// `initializeTimeZones()` must run before any `tz` lookup; funnelling every
/// lookup through this lazy singleton keeps that ordering implicit and lets
/// tests and callers share one populated database.
final tz.LocationDatabase timeZoneDatabase = _loadTimeZoneDatabase();

tz.LocationDatabase _loadTimeZoneDatabase() {
  tz_data.initializeTimeZones();
  return tz.timeZoneDatabase;
}
