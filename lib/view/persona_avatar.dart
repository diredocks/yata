import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import '../theme/todo_theme.dart';

class PersonaAvatar extends StatelessWidget {
  const PersonaAvatar({
    super.key,
    required this.name,
    this.size = 36,
    this.avatarBase64,
  });

  final String name;
  final double size;
  final String? avatarBase64;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Uint8List? get _decodedBytes {
    final raw = avatarBase64;
    if (raw == null || raw.isEmpty) return null;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bytes = _decodedBytes;

    final fallback = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? TodoColors.attentionDark : TodoColors.blue100,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    if (bytes == null) return fallback;

    return ClipOval(
      child: Image.memory(
        bytes,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
