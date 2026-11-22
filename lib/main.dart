import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'l10n/app_localizations.dart';
import 'onboarding/landing_screen.dart';
import 'providers/account_provider.dart';
import 'providers/todo_provider.dart';
import 'ui/controller/main_shell_screen.dart';
import 'theme/todo_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
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

    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: TodoTheme.light(),
      darkTheme: TodoTheme.dark(),
      themeMode: themeMode,
      home: activeAccount == null
          ? const LandingScreen()
          : const MainShellScreen(),
    );
  }
}
