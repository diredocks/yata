import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n/app_localizations.dart';
import 'onboarding/landing_screen.dart';
import 'account/account_provider.dart';
import 'data/todo_provider.dart';
import 'view/main_shell_screen.dart';
import 'theme/todo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const YataApp(),
    ),
  );
}

class YataApp extends ConsumerWidget {
  const YataApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeAccount = ref.watch(
      accountProvider.select((s) => s.activeAccount),
    );
    final themeMode = activeAccount == null
        ? ThemeMode.system
        : ref.watch(todoProvider.select((s) => s.themeMode));
    final useDynamicColor = activeAccount == null
        ? true
        : ref.watch(todoProvider.select((s) => s.useDynamicColor));

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: TodoTheme.light(
            dynamicColorScheme: useDynamicColor ? lightDynamic : null,
          ),
          darkTheme: TodoTheme.dark(
            dynamicColorScheme: useDynamicColor ? darkDynamic : null,
          ),
          themeMode: themeMode,
          home: activeAccount == null
              ? const LandingScreen()
              : const MainShellScreen(),
        );
      },
    );
  }
}
