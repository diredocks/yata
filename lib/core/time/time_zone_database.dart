import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final tz.LocationDatabase timeZoneDatabase = _loadTimeZoneDatabase();

tz.LocationDatabase _loadTimeZoneDatabase() {
  tz_data.initializeTimeZones();
  return tz.timeZoneDatabase;
}
