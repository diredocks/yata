import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'account/account_local_storage.dart';
import 'account/account_provider.dart';
import 'data/todo_provider.dart';
import 'data/todo_repository.dart';
import 'l10n/app_localizations.dart';
import 'onboarding/landing_screen.dart';
import 'theme/system_font_loader.dart';
import 'theme/todo_theme.dart';
import 'view/main_shell_screen.dart';
import 'widget/home_widget_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      !Platform.environment.containsKey('FLUTTER_TEST') &&
      (Platform.isAndroid || Platform.isIOS)) {
    await HomeWidget.registerInteractivityCallback(
      homeWidgetBackgroundCallback,
    );
  }
  final prefs = await SharedPreferences.getInstance();
  final database = TodoDatabase();
  final accountSnapshot = AccountLocalStorage(prefs).load();
  for (final account in accountSnapshot.accounts) {
    await TodoRepository.forAccount(
      prefs,
      accountId: account.id,
      database: database,
    ).preload();
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        todoDatabaseProvider.overrideWithValue(database),
      ],
      child: const YataApp(),
    ),
  );
}

class YataApp extends ConsumerStatefulWidget {
  const YataApp({super.key});

  @override
  ConsumerState<YataApp> createState() => _YataAppState();
}

class _YataAppState extends ConsumerState<YataApp> with WidgetsBindingObserver {
  final SystemFontLoader _systemFonts = SystemFontLoader();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncSystemFont();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncSystemFont();
  }

  Future<void> _syncSystemFont() async {
    final changed = await _systemFonts.refresh();
    if (changed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
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
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            ...GlobalMaterialLocalizations.delegates,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: _systemFonts.applyTo(
            TodoTheme.light(
              dynamicColorScheme: useDynamicColor ? lightDynamic : null,
            ),
          ),
          darkTheme: _systemFonts.applyTo(
            TodoTheme.dark(
              dynamicColorScheme: useDynamicColor ? darkDynamic : null,
            ),
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
