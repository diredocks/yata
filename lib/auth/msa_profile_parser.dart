import 'package:http/http.dart' as http;

String? _cleanNonNullString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.toLowerCase() == 'null') return null;
  return trimmed;
}

String? _firstCleanString(Map<dynamic, dynamic> map, Iterable<String> keys) {
  for (final key in keys) {
    final cleaned = _cleanNonNullString(map[key]);
    if (cleaned != null) return cleaned;
  }
  return null;
}

String? _joinGivenAndFamily(
  Map<dynamic, dynamic> map, {
  required Iterable<String> givenKeys,
  required Iterable<String> familyKeys,
}) {
  final given = _firstCleanString(map, givenKeys) ?? '';
  final family = _firstCleanString(map, familyKeys) ?? '';
  final joined = '$given $family'.trim();
  return joined.isEmpty ? null : joined;
}

/// Extracts display name from Graph `/me` or Substrate `/profile/v1.0/me/profile` JSON.
String? extractMsaProfileDisplayName(Map<String, dynamic> json) {
  final direct = _firstCleanString(json, const ['displayName', 'DisplayName']);
  if (direct != null) return direct;

  final topJoined = _joinGivenAndFamily(
    json,
    givenKeys: const ['givenName', 'GivenName'],
    familyKeys: const ['surname', 'Surname', 'lastName'],
  );
  if (topJoined != null) return topJoined;

  final names = (json['names'] ?? json['Names']) as List<dynamic>?;
  if (names != null && names.isNotEmpty && names.first is Map) {
    final first = names.first as Map;
    return _firstCleanString(first, const ['displayName', 'DisplayName']) ??
        _joinGivenAndFamily(
          first,
          givenKeys: const ['givenName', 'First'],
          familyKeys: const ['lastName', 'surname', 'Last'],
        );
  }
  return null;
}

/// Extracts primary email from Graph `/me` or Substrate `/profile/v1.0/me/profile` JSON.
String? extractMsaProfileEmail(Map<String, dynamic> json) {
  final direct = _firstCleanString(json, const [
    'mail',
    'Mail',
    'userPrincipalName',
    'UserPrincipalName',
    'EmailAddress',
    'email',
  ]);
  if (direct != null) return direct;

  final accounts = (json['accounts'] ?? json['Accounts']) as List<dynamic>?;
  if (accounts != null && accounts.isNotEmpty && accounts.first is Map) {
    final fromAccount = _firstCleanString(accounts.first as Map, const [
      'passportMemberName',
      'userPrincipalName',
      'emailAddress',
      'EmailAddress',
    ]);
    if (fromAccount != null) return fromAccount;
  }

  for (final listKey in const ['EmailAddresses', 'Emails', 'emails']) {
    final list = json[listKey] as List<dynamic>?;
    if (list == null || list.isEmpty) continue;
    final first = list.first;
    final candidate = first is Map
        ? _firstCleanString(first, const [
            'Address',
            'address',
            'EmailAddress',
          ])
        : _cleanNonNullString(first);
    if (candidate != null) return candidate;
  }
  return null;
}

bool _startsWithBytes(List<int> bytes, List<int> prefix, [int offset = 0]) {
  if (bytes.length < offset + prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[offset + i] != prefix[i]) return false;
  }
  return true;
}

/// Checks whether [resp] is a non-empty 200 image response by Content-Type or
/// magic bytes (JPEG, PNG, GIF, WebP).
bool isValidImageResponse(http.Response resp) {
  if (resp.statusCode != 200 || resp.bodyBytes.isEmpty) return false;
  final contentType = resp.headers['content-type']?.toLowerCase() ?? '';
  if (contentType.startsWith('image/')) return true;
  final b = resp.bodyBytes;
  return _startsWithBytes(b, const [0xFF, 0xD8, 0xFF]) || // JPEG
      _startsWithBytes(b, const [0x89, 0x50, 0x4E, 0x47]) || // PNG
      _startsWithBytes(b, const [0x47, 0x49, 0x46, 0x38]) || // GIF8
      (_startsWithBytes(b, const [0x52, 0x49, 0x46, 0x46]) && // RIFF....WEBP
          _startsWithBytes(b, const [0x57, 0x45, 0x42, 0x50], 8));
}
