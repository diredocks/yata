import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/l10n/app_localizations_en.dart';
import 'package:yata/main.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/list_actions_service.dart';
import 'package:yata/tasksview/list_export_formatter.dart';

class _FakeListActionsService implements ListActionsService {
  _FakeListActionsService();

  final Set<String> pinnedIds = <String>{};

  String? lastSharedSubject;
  String? lastSharedText;
  String? lastPrintedJobName;
  String? lastPrintedHtml;
  String? lastPinnedListId;
  String? lastPinnedLabel;

  @override
  bool get isPrintSupported => true;

  @override
  Future<bool> isShortcutSupported() async => true;

  @override
  Future<bool> isShortcutPinned(String shortcutId) async =>
      pinnedIds.contains(shortcutId);

  @override
  Future<ShortcutPinResult?> pinOrUpdateShortcut({
    required String shortcutId,
    required String listId,
    required String label,
    required int colorArgb,
    String? smartType,
    String? emoji,
  }) async {
    lastPinnedListId = listId;
    lastPinnedLabel = label;
    if (pinnedIds.contains(shortcutId)) {
      return ShortcutPinResult.updated;
    }
    pinnedIds.add(shortcutId);
    return ShortcutPinResult.requested;
  }

  @override
  Future<bool> printHtml({
    required String jobName,
    required String html,
  }) async {
    lastPrintedJobName = jobName;
    lastPrintedHtml = html;
    return true;
  }

  @override
  Future<bool> shareText({
    required String subject,
    required String text,
  }) async {
    lastSharedSubject = subject;
    lastSharedText = text;
    return true;
  }
}

void main() {
  group('list_export_formatter', () {
    final l10n = AppLocalizationsEn();
    final now = DateTime(2026, 11, 26, 10, 0);

    final customList = TodoList(
      id: 'list-1',
      title: 'Groceries',
      emoji: '🛒',
      showCompleted: true,
    );

    final tasks = [
      TaskItem(
        id: 't1',
        listId: 'list-1',
        title: 'Buy milk',
        isImportant: true,
        dueDate: DateTime(2026, 11, 26),
        createdAt: now,
        steps: const [
          TaskStep(id: 's1', title: 'Whole milk', isCompleted: true),
          TaskStep(id: 's2', title: 'Oat milk', isCompleted: false),
        ],
      ),
      TaskItem(
        id: 't2',
        listId: 'list-1',
        title: 'Bake <bread> & cake',
        isCompleted: true,
        completedAt: now,
        createdAt: now,
      ),
    ];

    final state = TodoState(
      lists: [customList],
      groups: const [],
      tasks: tasks,
      selectedListId: customList.id,
    );

    test(
      'formatListForShare formats tasks, steps, due date, and importance',
      () {
        final text = formatListForShare(
          l10n: l10n,
          state: state,
          currentList: customList,
          now: now,
        );

        expect(text, startsWith('🛒 Groceries\n\n'));
        expect(text, contains('\u2002\u2002❏ Buy milk (Today) ✭\n'));
        expect(text, contains('\u2002\u2002\u2002✔ Whole milk\n'));
        expect(text, contains('\u2002\u2002\u2002❏ Oat milk\n'));
        expect(text, contains('${l10n.completed}\n'));
        expect(text, contains('\u2002\u2002✔ Bake <bread> & cake\n'));
      },
    );

    test(
      'formatListForShare omits completed tasks when showCompleted is false',
      () {
        final hiddenCompletedList = customList.copyWith(showCompleted: false);
        final hiddenState = state.copyWith(lists: [hiddenCompletedList]);
        final text = formatListForShare(
          l10n: l10n,
          state: hiddenState,
          currentList: hiddenCompletedList,
          now: now,
        );

        expect(text, contains('Buy milk'));
        expect(text, isNot(contains('Bake <bread> & cake')));
      },
    );

    test('formatListForPrintHtml escapes HTML and renders structure', () {
      final html = formatListForPrintHtml(
        l10n: l10n,
        state: state,
        currentList: customList,
        now: now,
      );

      expect(html, contains('Printed with Yata'));
      expect(html, contains('🛒 Groceries'));
      expect(html, contains('Buy milk'));
      expect(html, contains('Whole milk'));
      expect(html, contains('Bake &lt;bread&gt; &amp; cake'));
      expect(html, contains('<strike>'));
      expect(html, contains('&#9733;'));
    });
  });

  testWidgets(
    'List menu displays Share, Print, and Add/Update Shortcut and invokes service',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': '[{"id":"test","displayName":"Local User","email":"local@yata.app","createdAt":"2026-01-01T00:00:00.000"}]',
        'yata.active_account_id': 'test',
      });
      final prefs = await SharedPreferences.getInstance();
      final fakeService = _FakeListActionsService();

      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            listActionsServiceProvider.overrideWithValue(fakeService),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Open menu on My Day
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Add shortcut to homescreen'), findsOneWidget);
      expect(find.text('Send a copy'), findsOneWidget);
      expect(find.text('Print list'), findsOneWidget);

      // Tap Add shortcut
      await tester.tap(find.text('Add shortcut to homescreen'));
      await tester.pumpAndSettle();
      expect(fakeService.lastPinnedListId, 'my_day');
      expect(fakeService.lastPinnedLabel, 'My Day');

      // Re-open menu: shortcut label should now be "Update homescreen shortcut"
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text('Update homescreen shortcut'), findsOneWidget);

      // Tap Send a copy
      await tester.tap(find.text('Send a copy'));
      await tester.pumpAndSettle();
      expect(fakeService.lastSharedSubject, 'Yata - My Day');
      expect(fakeService.lastSharedText, startsWith('My Day\n\n'));

      // Re-open menu and tap Print list
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Print list'));
      await tester.pumpAndSettle();
      expect(fakeService.lastPrintedJobName, 'Yata');
      expect(fakeService.lastPrintedHtml, contains('My Day'));
    },
  );
}
