/// Formats long Substrate / Exchange IDs compactly for diagnostic logs.
String shortSyncId(String? id) {
  if (id == null) return 'null';
  final trimmed = id.trim();
  if (trimmed.isEmpty) return 'empty';
  if (trimmed.length <= 20) return trimmed;
  return '${trimmed.substring(0, 8)}..${trimmed.substring(trimmed.length - 8)}';
}

/// Formats an optional timestamp in UTC ISO-8601 form for diagnostic logs.
String formatSyncTimestamp(DateTime? dt) =>
    dt?.toUtc().toIso8601String() ?? 'null';
