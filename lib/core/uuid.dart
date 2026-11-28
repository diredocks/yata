import 'package:uuid/uuid.dart';

const Uuid _uuid = Uuid();

/// Generates a random RFC-4122 version 4 UUID string.
String generateUuidV4() => _uuid.v4();
