import 'package:material_ui/material_ui.dart';
import '../models/todo_list.dart';

class TodoColors {
  TodoColors._();

  static const Color attentionLight = Color(0xFF1174E4);
  static const Color attentionDark = Color(0xFF0F93FF);
  static const Color blue100 = Color(0xFF0078D4);

  static const Color primaryBackgroundLight = Color(0xFFFFFFFF);
  static const Color secondaryBackgroundLight = Color(0xFFFAFAFA);
  static const Color primaryBackgroundDark = Color(0xFF080808);
  static const Color secondaryBackgroundDark = Color(0xFF1A1A1A);
  static const Color cardDark = Color(0xFF222222);
  static const Color selectedCardLight = Color(0xFFEFF6FC);
  static const Color selectedCardDark = Color(0xFF34373D);

  static const Color primaryTextLight = Color(0xFF34373D);
  static const Color secondaryTextLight = Color(0xFF767678);
  static const Color primaryTextDark = Color(0xFFF3F3F3);
  static const Color secondaryTextDark = Color(0xFFA6A6A8);

  static const Color dividerLight = Color(0x14000000);
  static const Color dividerDark = Color(0x14FFFFFF);

  static const Color overdueRed = Color(0xFFD92C2C);

  static bool isLightTheme(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.lightBlue ||
      ListThemeColor.lightRose ||
      ListThemeColor.lightTeal ||
      ListThemeColor.lightGreen ||
      ListThemeColor.lightPurple ||
      ListThemeColor.lightRed ||
      ListThemeColor.lightGrey =>
        true,
      _ => false,
    };
  }

  static LinearGradient gradientFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark && isLightTheme(themeColor)) {
      return const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF121212), Color(0xFF1A1A1A)],
      );
    }

    final (top, bottom) = switch (themeColor) {
      ListThemeColor.blue => (
          const Color(0xFF5C70BE),
          const Color(0xFF788CDE),
        ),
      ListThemeColor.rose => (
          const Color(0xFFC14C6C),
          const Color(0xFFE46C8C),
        ),
      ListThemeColor.teal => (
          const Color(0xFF25817C),
          const Color(0xFF479E98),
        ),
      ListThemeColor.green => (
          const Color(0xFF2A835D),
          const Color(0xFF4AA079),
        ),
      ListThemeColor.purple => (
          const Color(0xFF9D5D9F),
          const Color(0xFFBC7ABC),
        ),
      ListThemeColor.red => (
          const Color(0xFFC24F4A),
          const Color(0xFFE46B67),
        ),
      ListThemeColor.grey => (
          const Color(0xFF687681),
          const Color(0xFF8795A0),
        ),
      ListThemeColor.lightBlue => (
          const Color(0xFFDFEDF9),
          const Color(0xFFDFEDF9),
        ),
      ListThemeColor.lightRose => (
          const Color(0xFFFFE4E9),
          const Color(0xFFFFE4E9),
        ),
      ListThemeColor.lightTeal => (
          const Color(0xFFD4F1EF),
          const Color(0xFFD4F1EF),
        ),
      ListThemeColor.lightGreen => (
          const Color(0xFFD5F1E5),
          const Color(0xFFD5F1E5),
        ),
      ListThemeColor.lightPurple => (
          const Color(0xFFF2E7F9),
          const Color(0xFFF2E7F9),
        ),
      ListThemeColor.lightRed => (
          const Color(0xFFF9E8DE),
          const Color(0xFFF9E8DE),
        ),
      ListThemeColor.lightGrey => (
          const Color(0xFFE7ECF0),
          const Color(0xFFE7ECF0),
        ),
    };
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [top, bottom],
    );
  }

  static Color headerForegroundFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (!isLightTheme(themeColor)) return Colors.white;
    if (brightness == Brightness.dark) {
      return switch (themeColor) {
        ListThemeColor.lightBlue => const Color(0xFFA0CBF1),
        ListThemeColor.lightRose => const Color(0xFFF5B6C2),
        ListThemeColor.lightTeal => const Color(0xFF8BD3CE),
        ListThemeColor.lightGreen => const Color(0xFF9AD2BA),
        ListThemeColor.lightPurple => const Color(0xFFD6BDE7),
        ListThemeColor.lightRed => const Color(0xFFECBDA2),
        ListThemeColor.lightGrey => const Color(0xFFBAC8D4),
        _ => Colors.white,
      };
    }
    return accentFor(themeColor);
  }

  static Color swatchColorFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.lightBlue => const Color(0xFFDFEDF9),
      ListThemeColor.lightRose => const Color(0xFFFFE4E9),
      ListThemeColor.lightTeal => const Color(0xFFD4F1EF),
      ListThemeColor.lightGreen => const Color(0xFFD5F1E5),
      ListThemeColor.lightPurple => const Color(0xFFF2E7F9),
      ListThemeColor.lightRed => const Color(0xFFF9E8DE),
      ListThemeColor.lightGrey => const Color(0xFFE7ECF0),
      _ => accentFor(themeColor),
    };
  }

  static Color accentFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue => const Color(0xFF5C70BE),
      ListThemeColor.rose => const Color(0xFFC14C6C),
      ListThemeColor.teal => const Color(0xFF25817C),
      ListThemeColor.green => const Color(0xFF2A835D),
      ListThemeColor.purple => const Color(0xFF9D5D9F),
      ListThemeColor.red => const Color(0xFFC24F4A),
      ListThemeColor.grey => const Color(0xFF687681),
      ListThemeColor.lightBlue => const Color(0xFF3063AB),
      ListThemeColor.lightRose => const Color(0xFFAC395D),
      ListThemeColor.lightTeal => const Color(0xFF166F6B),
      ListThemeColor.lightGreen => const Color(0xFF1E704D),
      ListThemeColor.lightPurple => const Color(0xFF7D5294),
      ListThemeColor.lightRed => const Color(0xFFA84329),
      ListThemeColor.lightGrey => const Color(0xFF586570),
    };
  }

  static Color _darkBottomFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue || ListThemeColor.lightBlue => const Color(0xFF788CDE),
      ListThemeColor.rose || ListThemeColor.lightRose => const Color(0xFFE46C8C),
      ListThemeColor.teal || ListThemeColor.lightTeal => const Color(0xFF479E98),
      ListThemeColor.green ||
      ListThemeColor.lightGreen =>
        const Color(0xFF4AA079),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple =>
        const Color(0xFFBC7ABC),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFE46B67),
      ListThemeColor.grey || ListThemeColor.lightGrey => const Color(0xFF8795A0),
    };
  }

  static Color _lightBottomFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue || ListThemeColor.lightBlue => const Color(0xFFDFEDF9),
      ListThemeColor.rose || ListThemeColor.lightRose => const Color(0xFFFFE4E9),
      ListThemeColor.teal || ListThemeColor.lightTeal => const Color(0xFFD4F1EF),
      ListThemeColor.green ||
      ListThemeColor.lightGreen =>
        const Color(0xFFD5F1E5),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple =>
        const Color(0xFFF2E7F9),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFF9E8DE),
      ListThemeColor.grey || ListThemeColor.lightGrey => const Color(0xFFE7ECF0),
    };
  }

  static Color _lightTopFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue || ListThemeColor.lightBlue => const Color(0xFF3063AB),
      ListThemeColor.rose || ListThemeColor.lightRose => const Color(0xFFAC395D),
      ListThemeColor.teal || ListThemeColor.lightTeal => const Color(0xFF166F6B),
      ListThemeColor.green ||
      ListThemeColor.lightGreen =>
        const Color(0xFF1E704D),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple =>
        const Color(0xFF7D5294),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFA84329),
      ListThemeColor.grey || ListThemeColor.lightGrey => const Color(0xFF586570),
    };
  }

  static Color _lightNightFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue || ListThemeColor.lightBlue => const Color(0xFFA0CBF1),
      ListThemeColor.rose || ListThemeColor.lightRose => const Color(0xFFF5B6C2),
      ListThemeColor.teal || ListThemeColor.lightTeal => const Color(0xFF8BD3CE),
      ListThemeColor.green ||
      ListThemeColor.lightGreen =>
        const Color(0xFF9AD2BA),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple =>
        const Color(0xFFD6BDE7),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFECBDA2),
      ListThemeColor.grey || ListThemeColor.lightGrey => const Color(0xFFBAC8D4),
    };
  }

  /// Exact FAB background color from mstodo.apk (arrays.xml index 6).
  static Color fabBackgroundFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark) {
      return isLightTheme(themeColor)
          ? _lightNightFor(themeColor)
          : _darkBottomFor(themeColor);
    }
    return isLightTheme(themeColor)
        ? _lightTopFor(themeColor)
        : _lightBottomFor(themeColor);
  }

  /// Exact FAB icon tint color from mstodo.apk (arrays.xml index 7).
  static Color fabForegroundFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark) {
      return Colors.black;
    }
    return isLightTheme(themeColor)
        ? Colors.white
        : _lightTopFor(themeColor);
  }
}

class TodoTheme {
  TodoTheme._();

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TodoColors.attentionLight,
        brightness: Brightness.light,
        primary: TodoColors.attentionLight,
        surface: TodoColors.primaryBackgroundLight,
      ),
      scaffoldBackgroundColor: TodoColors.primaryBackgroundLight,
      dividerColor: TodoColors.dividerLight,
      cardColor: TodoColors.primaryBackgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: TodoColors.primaryBackgroundLight,
        foregroundColor: TodoColors.primaryTextLight,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TodoColors.attentionDark,
        brightness: Brightness.dark,
        primary: TodoColors.attentionDark,
        surface: TodoColors.primaryBackgroundDark,
      ),
      scaffoldBackgroundColor: TodoColors.primaryBackgroundDark,
      dividerColor: TodoColors.dividerDark,
      cardColor: TodoColors.cardDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: TodoColors.primaryBackgroundDark,
        foregroundColor: TodoColors.primaryTextDark,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }
}
