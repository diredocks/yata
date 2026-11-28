/// Reduces [raw] to a single safe path component.
///
/// Anything outside `[a-zA-Z0-9_-]` becomes `_`, so separators, `.`/`..` and
/// other illegal characters can never address a parent directory.
String sanitizePathSegment(String raw, {String fallback = 'default'}) {
  final cleaned = raw.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  return cleaned.isEmpty ? fallback : cleaned;
}
