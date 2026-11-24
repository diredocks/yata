/// JSON converters that normalize instant timestamps to UTC (`Z` suffix)
/// on both serialization and deserialization.
DateTime utcDateTimeFromJson(String raw) => DateTime.parse(raw).toUtc();

String utcDateTimeToJson(DateTime value) => value.toUtc().toIso8601String();

DateTime? nullableUtcDateTimeFromJson(String? raw) =>
    raw == null ? null : DateTime.parse(raw).toUtc();

String? nullableUtcDateTimeToJson(DateTime? value) =>
    value?.toUtc().toIso8601String();
