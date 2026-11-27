import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
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
  static const Color cardDark = Color(0xFF1A1A1A);
  static const Color selectedCardLight = Color(0xFFEFF6FC);
  static const Color selectedCardDark = Color(0xFF34373D);

  static const Color primaryTextLight = Color(0xFF34373D);
  static const Color secondaryTextLight = Color(0xFF767678);
  static const Color primaryTextDark = Color(0xFFF3F3F3);
  static const Color secondaryTextDark = Color(0xFFA6A6A8);

  static const Color dividerLight = Color(0x1F000000);
  static const Color dividerDark = Color(0x1FFFFFFF);
  static const Color taskViewDividerLight = Color(0x14000000);
  static const Color taskViewDividerDark = Color(0x14FFFFFF);

  static const Color overdueRed = Color(0xFFD92C2C);

  /// Matches `@color/homeview_icon_color` (attention in light, secondary_text in dark).
  static Color homeViewIconColor(Brightness brightness) {
    return brightness == Brightness.dark ? secondaryTextDark : attentionLight;
  }

  /// Matches `@color/detailview_background` (white in light, #1A1A1A in dark).
  static Color detailHeaderBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? secondaryBackgroundDark
        : primaryBackgroundLight;
  }

  /// Matches `@color/detailview_rv_background` (#FAFAFA in light, #080808 in dark).
  static Color detailBodyBackground(Brightness brightness) {
    return brightness == Brightness.dark
        ? primaryBackgroundDark
        : secondaryBackgroundLight;
  }

  /// Matches `res/drawable/default_shadow_horizontal.xml` (3dp top-to-bottom fade).
  static const BoxDecoration horizontalShadowDecoration = BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0x1A000000), Color(0x0D000000), Color(0x00000000)],
    ),
  );

  static bool isLightTheme(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.lightBlue ||
      ListThemeColor.lightRose ||
      ListThemeColor.lightTeal ||
      ListThemeColor.lightGreen ||
      ListThemeColor.lightPurple ||
      ListThemeColor.lightRed ||
      ListThemeColor.lightGrey => true,
      _ => false,
    };
  }

  static Color backgroundColorFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark) {
      return primaryBackgroundDark;
    }
    return swatchColorFor(themeColor);
  }

  static Color headerForegroundFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark) {
      return isLightTheme(themeColor)
          ? _lightNightFor(themeColor)
          : _darkBottomFor(themeColor);
    }
    if (!isLightTheme(themeColor)) return Colors.white;
    return accentFor(themeColor);
  }

  static Color swatchColorFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark) {
      return accentFor(themeColor, brightness: Brightness.dark);
    }
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

  static Color accentFor(
    ListThemeColor themeColor, {
    Brightness brightness = Brightness.light,
  }) {
    if (brightness == Brightness.dark) {
      return isLightTheme(themeColor)
          ? _lightNightFor(themeColor)
          : _darkBottomFor(themeColor);
    }
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
      ListThemeColor.blue ||
      ListThemeColor.lightBlue => const Color(0xFF788CDE),
      ListThemeColor.rose ||
      ListThemeColor.lightRose => const Color(0xFFE46C8C),
      ListThemeColor.teal ||
      ListThemeColor.lightTeal => const Color(0xFF479E98),
      ListThemeColor.green ||
      ListThemeColor.lightGreen => const Color(0xFF4AA079),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple => const Color(0xFFBC7ABC),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFE46B67),
      ListThemeColor.grey ||
      ListThemeColor.lightGrey => const Color(0xFF8795A0),
    };
  }

  static Color _lightBottomFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue ||
      ListThemeColor.lightBlue => const Color(0xFFDFEDF9),
      ListThemeColor.rose ||
      ListThemeColor.lightRose => const Color(0xFFFFE4E9),
      ListThemeColor.teal ||
      ListThemeColor.lightTeal => const Color(0xFFD4F1EF),
      ListThemeColor.green ||
      ListThemeColor.lightGreen => const Color(0xFFD5F1E5),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple => const Color(0xFFF2E7F9),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFF9E8DE),
      ListThemeColor.grey ||
      ListThemeColor.lightGrey => const Color(0xFFE7ECF0),
    };
  }

  static Color _lightTopFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue ||
      ListThemeColor.lightBlue => const Color(0xFF3063AB),
      ListThemeColor.rose ||
      ListThemeColor.lightRose => const Color(0xFFAC395D),
      ListThemeColor.teal ||
      ListThemeColor.lightTeal => const Color(0xFF166F6B),
      ListThemeColor.green ||
      ListThemeColor.lightGreen => const Color(0xFF1E704D),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple => const Color(0xFF7D5294),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFA84329),
      ListThemeColor.grey ||
      ListThemeColor.lightGrey => const Color(0xFF586570),
    };
  }

  static Color _lightNightFor(ListThemeColor themeColor) {
    return switch (themeColor) {
      ListThemeColor.blue ||
      ListThemeColor.lightBlue => const Color(0xFFA0CBF1),
      ListThemeColor.rose ||
      ListThemeColor.lightRose => const Color(0xFFF5B6C2),
      ListThemeColor.teal ||
      ListThemeColor.lightTeal => const Color(0xFF8BD3CE),
      ListThemeColor.green ||
      ListThemeColor.lightGreen => const Color(0xFF9AD2BA),
      ListThemeColor.purple ||
      ListThemeColor.lightPurple => const Color(0xFFD6BDE7),
      ListThemeColor.red || ListThemeColor.lightRed => const Color(0xFFECBDA2),
      ListThemeColor.grey ||
      ListThemeColor.lightGrey => const Color(0xFFBAC8D4),
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
    return isLightTheme(themeColor) ? Colors.white : _lightTopFor(themeColor);
  }

  static String photoAssetFor(ListThemePhoto photo) {
    final fileName = switch (photo) {
      ListThemePhoto.beach => 'photo_beach.webp',
      ListThemePhoto.desert => 'photo_desert.webp',
      ListThemePhoto.fern => 'photo_fern.webp',
      ListThemePhoto.field => 'photo_field.webp',
      ListThemePhoto.gradient => 'photo_gradient.webp',
      ListThemePhoto.lighthouse => 'photo_lighthouse.webp',
      ListThemePhoto.safari => 'photo_safari.webp',
      ListThemePhoto.sea => 'photo_sea.webp',
      ListThemePhoto.tvTower => 'photo_tv_tower.webp',
    };
    return 'assets/themes/$fileName';
  }

  static Color listAccentFor(
    TodoList list, {
    Brightness brightness = Brightness.light,
  }) {
    if (list.customBackgroundPath != null) {
      return customPhotoFabBackgroundFor(brightness: brightness);
    }
    if (list.themePhoto != null) {
      return photoFabBackgroundFor(list.themePhoto!);
    }
    return accentFor(list.themeColor, brightness: brightness);
  }

  /// Neutral dark-grey FAB/accent matching `CustomThemeDefaults.kt` (`dark_grey_top` / `dark_grey_bottom`).
  static Color customPhotoFabBackgroundFor({
    Brightness brightness = Brightness.light,
  }) {
    return brightness == Brightness.dark
        ? const Color(0xFF5A5A5A)
        : const Color(0xFF3E3E3E);
  }

  /// Resolves the floating button background and foreground colors for [list].
  static ({Color background, Color foreground}) fabColorsFor(
    TodoList list, {
    Brightness brightness = Brightness.light,
  }) {
    final isDark = brightness == Brightness.dark;
    final customPath = list.customBackgroundPath;
    final photo = list.themePhoto;
    final hasPhotoBg = customPath != null || photo != null;
    final background = customPath != null
        ? customPhotoFabBackgroundFor(brightness: brightness)
        : photo != null
        ? photoFabBackgroundFor(photo)
        : fabBackgroundFor(list.themeColor, brightness: brightness);
    final foreground = hasPhotoBg
        ? (isDark ? Colors.black : Colors.white)
        : fabForegroundFor(list.themeColor, brightness: brightness);
    return (background: background, foreground: foreground);
  }

  /// Exact photo FAB colors from mstodo.apk (`colors.xml` `image_*_fab_color`).
  static Color photoFabBackgroundFor(ListThemePhoto photo) {
    return switch (photo) {
      ListThemePhoto.beach => const Color(0xFF8888B4),
      ListThemePhoto.desert => const Color(0xFF377D95),
      ListThemePhoto.fern => const Color(0xFF397946),
      ListThemePhoto.field => const Color(0xFF4C7999),
      ListThemePhoto.gradient => const Color(0xFFCD415E),
      ListThemePhoto.lighthouse => const Color(0xFF488399),
      ListThemePhoto.safari => const Color(0xFF5674AF),
      ListThemePhoto.sea => const Color(0xFF37807B),
      ListThemePhoto.tvTower => const Color(0xFF437D8A),
    };
  }
}

class TodoTheme {
  TodoTheme._();

  /// Returns a [SystemUiOverlayStyle] whose status bar icon brightness contrasts
  /// with a background of [backgroundBrightness].
  static SystemUiOverlayStyle systemUiOverlayStyleForBrightness(
    Brightness backgroundBrightness,
  ) {
    final isDarkBg = backgroundBrightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDarkBg ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDarkBg ? Brightness.dark : Brightness.light,
    );
  }

  /// Returns a [SystemUiOverlayStyle] whose status bar icon brightness contrasts
  /// with [backgroundColor].
  static SystemUiOverlayStyle systemUiOverlayStyleFor(Color backgroundColor) {
    return systemUiOverlayStyleForBrightness(
      ThemeData.estimateBrightnessForColor(backgroundColor),
    );
  }

  static const PageTransitionsTheme _pageTransitionsTheme =
      PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        },
      );

  static ThemeData light({ColorScheme? dynamicColorScheme}) {
    if (dynamicColorScheme != null) {
      final scheme = dynamicColorScheme.harmonized();
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        pageTransitionsTheme: _pageTransitionsTheme,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        dividerColor: scheme.outlineVariant,
        dividerTheme: DividerThemeData(
          color: scheme.outlineVariant,
          thickness: 1,
          space: 1,
        ),
        cardColor: scheme.surfaceContainerLow,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );
    }
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TodoColors.attentionLight,
        brightness: Brightness.light,
        primary: TodoColors.attentionLight,
        surface: TodoColors.primaryBackgroundLight,
      ),
      scaffoldBackgroundColor: TodoColors.primaryBackgroundLight,
      dividerColor: TodoColors.dividerLight,
      dividerTheme: const DividerThemeData(
        color: TodoColors.dividerLight,
        thickness: 1,
        space: 1,
      ),
      cardColor: TodoColors.primaryBackgroundLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: TodoColors.primaryBackgroundLight,
        foregroundColor: TodoColors.primaryTextLight,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
    );
  }

  static ThemeData dark({ColorScheme? dynamicColorScheme}) {
    if (dynamicColorScheme != null) {
      final scheme = dynamicColorScheme.harmonized();
      return ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        pageTransitionsTheme: _pageTransitionsTheme,
        colorScheme: scheme,
        scaffoldBackgroundColor: scheme.surface,
        dividerColor: scheme.outlineVariant,
        dividerTheme: DividerThemeData(
          color: scheme.outlineVariant,
          thickness: 1,
          space: 1,
        ),
        cardColor: scheme.surfaceContainerLow,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );
    }
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      pageTransitionsTheme: _pageTransitionsTheme,
      colorScheme: ColorScheme.fromSeed(
        seedColor: TodoColors.attentionDark,
        brightness: Brightness.dark,
        primary: TodoColors.attentionDark,
        surface: TodoColors.primaryBackgroundDark,
      ),
      scaffoldBackgroundColor: TodoColors.primaryBackgroundDark,
      dividerColor: TodoColors.dividerDark,
      dividerTheme: const DividerThemeData(
        color: TodoColors.dividerDark,
        thickness: 1,
        space: 1,
      ),
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
