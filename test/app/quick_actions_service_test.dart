import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quick_actions/quick_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/app/quick_actions_service.dart';
import 'package:yata/data/preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/search/search_screen.dart';
import 'package:yata/tasksview/richentry/task_entry_sheet.dart';

class _FakeQuickActionsTransport implements QuickActionsTransport {
  _FakeQuickActionsTransport({this.supported = true, this.throwOnSet = false});

  final bool supported;
  final bool throwOnSet;
  void Function(String type)? onAction;
  int initializeCalls = 0;
  int setShortcutCalls = 0;
  int clearCalls = 0;
  List<ShortcutItem> lastItems = const <ShortcutItem>[];

  @override
  bool get isSupported => supported;

  @override
  Future<void> initialize(void Function(String type) onAction) async {
    initializeCalls++;
    this.onAction = onAction;
  }

  @override
  Future<void> setShortcutItems(List<ShortcutItem> items) async {
    if (throwOnSet) {
      throw StateError('platform error');
    }
    setShortcutCalls++;
    lastItems = items;
  }

  @override
  Future<void> clearShortcutItems() async {
    clearCalls++;
    lastItems = const <ShortcutItem>[];
  }

  void trigger(String type) => onAction?.call(type);
}

void main() {
  group('QuickActionsService', () {
    test(
      'registers search and new_task shortcuts and avoids redundant updates',
      () async {
        final transport = _FakeQuickActionsTransport();
        final service = QuickActionsService(transport);
        addTearDown(service.dispose);

        final result = await service.initialize(
          searchLabel: 'Search tasks',
          newTaskLabel: 'New task',
        );
        expect(result.isSuccess(), isTrue);
        expect(transport.initializeCalls, 1);
        expect(transport.setShortcutCalls, 1);
        expect(
          transport.lastItems.map((i) => (i.type, i.localizedTitle, i.icon)),
          [
            ('new_task', 'New task', 'ic_shortcut_add'),
            ('search', 'Search tasks', 'ic_shortcut_search'),
          ],
        );

        // Identical labels should not re-invoke platform channel.
        await service.updateShortcuts(
          searchLabel: 'Search tasks',
          newTaskLabel: 'New task',
        );
        expect(transport.setShortcutCalls, 1);

        // Changed labels should update shortcuts.
        await service.updateShortcuts(
          searchLabel: '搜索任务',
          newTaskLabel: '添加新任务',
        );
        expect(transport.setShortcutCalls, 2);
        expect(transport.lastItems.first.localizedTitle, '添加新任务');
      },
    );

    test(
      'emits recognized actions and buffers pending action before listener',
      () async {
        final transport = _FakeQuickActionsTransport();
        final service = QuickActionsService(transport);
        addTearDown(service.dispose);

        await service.initialize(
          searchLabel: 'Search tasks',
          newTaskLabel: 'New task',
        );

        // Trigger before any listener is attached -> buffered as pending.
        transport.trigger('search');
        expect(service.consumePendingAction(), QuickActionType.search);
        expect(service.consumePendingAction(), isNull);

        final received = <QuickActionType>[];
        final sub = service.actions.listen(received.add);
        addTearDown(sub.cancel);

        transport.trigger('unknown_action');
        transport.trigger('new_task');
        transport.trigger('search');
        await Future<void>.delayed(Duration.zero);

        expect(received, [QuickActionType.newTask, QuickActionType.search]);
      },
    );

    test(
      'skips transport when unsupported and guards transport failures',
      () async {
        final unsupported = _FakeQuickActionsTransport(supported: false);
        final unsupportedService = QuickActionsService(unsupported);
        addTearDown(unsupportedService.dispose);

        final unsupportedRes = await unsupportedService.initialize(
          searchLabel: 'Search tasks',
          newTaskLabel: 'New task',
        );
        expect(unsupportedRes.isSuccess(), isTrue);
        expect(unsupported.initializeCalls, 0);
        expect(unsupported.setShortcutCalls, 0);

        final failing = _FakeQuickActionsTransport(throwOnSet: true);
        final failingService = QuickActionsService(failing);
        addTearDown(failingService.dispose);

        final failingRes = await failingService.initialize(
          searchLabel: 'Search tasks',
          newTaskLabel: 'New task',
        );
        expect(failingRes.isError(), isTrue);
      },
    );
  });

  group('MainShellScreen quick actions integration', () {
    testWidgets('registers shortcuts and handles search & new_task actions', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts':
            '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
        'yata.active_account_id': 'test',
      });
      final prefs = await SharedPreferences.getInstance();
      final transport = _FakeQuickActionsTransport();

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            quickActionsTransportProvider.overrideWithValue(transport),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(transport.initializeCalls, 1);
      expect(transport.lastItems.map((i) => i.type), ['new_task', 'search']);

      // Trigger search quick action -> opens SearchScreen.
      transport.trigger('search');
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsOneWidget);

      // Trigger new_task quick action while on SearchScreen -> pops to root and opens TaskEntrySheet.
      transport.trigger('new_task');
      await tester.pumpAndSettle();
      expect(find.byType(SearchScreen), findsNothing);
      expect(find.byType(TaskEntrySheet), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Quick action task');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Verify the task can be found via search quick action.
      transport.trigger('search');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Quick action task');
      await tester.pumpAndSettle();
      expect(find.text('Quick action task'), findsWidgets);
    });
  });
}
