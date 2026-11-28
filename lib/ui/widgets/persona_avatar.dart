import 'dart:convert';

import 'package:material_ui/material_ui.dart';

import '../../theme/todo_theme.dart';

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

  static final Map<String, MemoryImage> _imageCache = {};

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.first.isEmpty) return 'U';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  MemoryImage? _resolveImageProvider() {
    final raw = avatarBase64;
    if (raw == null || raw.isEmpty) return null;
    final cached = _imageCache[raw];
    if (cached != null) return cached;
    final decoded = MemoryImage(base64Decode(raw));
    if (_imageCache.length >= 16) {
      _imageCache.remove(_imageCache.keys.first);
    }
    _imageCache[raw] = decoded;
    return decoded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final imageProvider = _resolveImageProvider();

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

    if (imageProvider == null) return fallback;

    return ClipOval(
      child: Image(
        image: imageProvider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => fallback,
      ),
    );
  }
}
