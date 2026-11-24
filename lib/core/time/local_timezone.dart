import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

bool _tzInitialized = false;

void _ensureTimeZonesInitialized() {
  if (_tzInitialized) return;
  tz_data.initializeTimeZones();
  _tzInitialized = true;
}

const Map<String, String> _windowsToIana = {
  'utc': 'UTC',
  'coordinated universal time': 'UTC',
  'gmt standard time': 'Europe/London',
  'greenwich standard time': 'Atlantic/Reykjavik',
  'w. europe standard time': 'Europe/Berlin',
  'central europe standard time': 'Europe/Budapest',
  'romance standard time': 'Europe/Paris',
  'central european standard time': 'Europe/Warsaw',
  'e. europe standard time': 'Europe/Bucharest',
  'fle standard time': 'Europe/Kyiv',
  'russian standard time': 'Europe/Moscow',
  'arabian standard time': 'Asia/Dubai',
  'india standard time': 'Asia/Kolkata',
  'se asia standard time': 'Asia/Bangkok',
  'china standard time': 'Asia/Shanghai',
  'taipei standard time': 'Asia/Taipei',
  'singapore standard time': 'Asia/Singapore',
  'tokyo standard time': 'Asia/Tokyo',
  'korea standard time': 'Asia/Seoul',
  'aus eastern standard time': 'Australia/Sydney',
  'new zealand standard time': 'Pacific/Auckland',
  'eastern standard time': 'America/New_York',
  'central standard time': 'America/Chicago',
  'mountain standard time': 'America/Denver',
  'pacific standard time': 'America/Los_Angeles',
  'alaskan standard time': 'America/Anchorage',
  'hawaiian standard time': 'Pacific/Honolulu',
};

const List<String> _preferredCanonicalIanaZones = [
  'UTC',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Asia/Singapore',
  'Asia/Kolkata',
  'Asia/Dubai',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Paris',
  'Europe/Moscow',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Australia/Sydney',
  'Pacific/Auckland',
];

/// Resolves the device's current local timezone as an IANA identifier
/// (e.g. `Asia/Shanghai`, `America/Los_Angeles`, or `UTC`).
String resolveLocalIanaTimeZone({DateTime? reference}) {
  _ensureTimeZonesInitialized();
  final now = reference ?? DateTime.now();
  final locations = tz.timeZoneDatabase.locations;
  final rawName = now.timeZoneName.trim();
  if (rawName.isNotEmpty) {
    if (locations.containsKey(rawName)) {
      return rawName;
    }
    final winMapped = _windowsToIana[rawName.toLowerCase()];
    if (winMapped != null && locations.containsKey(winMapped)) {
      return winMapped;
    }
  }

  final targetOffset = now.timeZoneOffset;
  final epochMs = now.millisecondsSinceEpoch;
  if (targetOffset == Duration.zero &&
      (rawName.isEmpty || rawName.toUpperCase() == 'UTC')) {
    return 'UTC';
  }

  for (final candidate in _preferredCanonicalIanaZones) {
    final loc = locations[candidate];
    if (loc == null) continue;
    final zone = loc.timeZone(epochMs);
    if (zone.offset == targetOffset &&
        (rawName.isEmpty ||
            zone.abbreviation.toLowerCase() == rawName.toLowerCase())) {
      return candidate;
    }
  }

  if (rawName.isNotEmpty) {
    for (final loc in locations.values) {
      if (loc.name.startsWith('Etc/')) continue;
      final zone = loc.timeZone(epochMs);
      if (zone.offset == targetOffset &&
          zone.abbreviation.toLowerCase() == rawName.toLowerCase()) {
        return loc.name;
      }
    }
  }

  for (final candidate in _preferredCanonicalIanaZones) {
    final loc = locations[candidate];
    if (loc != null && loc.timeZone(epochMs).offset == targetOffset) {
      return candidate;
    }
  }

  for (final loc in locations.values) {
    if (loc.name.startsWith('Etc/')) continue;
    if (loc.timeZone(epochMs).offset == targetOffset) {
      return loc.name;
    }
  }

  return 'UTC';
}

tz.Location? _lookupLocation(String timeZoneId) {
  _ensureTimeZonesInitialized();
  final trimmed = timeZoneId.trim();
  if (trimmed.isEmpty) return null;
  final locations = tz.timeZoneDatabase.locations;
  final direct = locations[trimmed];
  if (direct != null) return direct;

  final winMapped = _windowsToIana[trimmed.toLowerCase()];
  if (winMapped != null && locations.containsKey(winMapped)) {
    return locations[winMapped];
  }

  final targetLower = trimmed.toLowerCase();
  for (final entry in locations.entries) {
    if (entry.key.toLowerCase() == targetLower) {
      return entry.value;
    }
  }
  return null;
}

/// Converts a wall-clock ISO datetime string without explicit offset in
/// [timeZoneId] (IANA or Windows name) into a UTC [DateTime].
DateTime? parseDateTimeInTimeZone(
  String rawIsoWithoutOffset,
  String timeZoneId,
) {
  final loc = _lookupLocation(timeZoneId);
  if (loc == null) return null;

  var cleaned = rawIsoWithoutOffset.trim();
  if (cleaned.endsWith('Z') || cleaned.endsWith('z')) {
    cleaned = cleaned.substring(0, cleaned.length - 1);
  }
  final parsed = DateTime.tryParse(cleaned);
  if (parsed == null) return null;

  final zoned = tz.TZDateTime(
    loc,
    parsed.year,
    parsed.month,
    parsed.day,
    parsed.hour,
    parsed.minute,
    parsed.second,
    parsed.millisecond,
    parsed.microsecond,
  );
  return zoned.toUtc();
}
