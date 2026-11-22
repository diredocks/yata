import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/settings/settings_screen.dart';

void main() {
  testWidgets('SettingsScreen displays version from PackageInfo',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'yata.accounts':
          '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
      'yata.active_account_id': 'test',
    });
    final prefs = await SharedPreferences.getInstance();

    PackageInfo.setMockInitialValues(
      appName: 'Yata',
      packageName: 'top.clickfling.yata',
      version: '2.3.4',
      buildNumber: '42',
      buildSignature: '',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('2.3.4+42'), 300);
    expect(find.text('2.3.4+42'), findsOneWidget);
  });
}
