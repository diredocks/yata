import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/theme/todo_theme.dart';
import 'package:yata/widget/home_widget_service.dart';

import '../helpers/home_widget_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HomeWidgetAction.fromUri', () {
    test('parses launch widget URI actions', () {
      final add = HomeWidgetAction.fromUri(
        Uri.parse('yata://widget/add?listId=my_day'),
      );
      expect(add?.type, HomeWidgetActionType.quickAdd);
      expect(add?.listId, 'my_day');

      final openList = HomeWidgetAction.fromUri(
        Uri.parse('yata://widget/open_list?listId=tasks'),
      );
      expect(openList?.type, HomeWidgetActionType.openList);
      expect(openList?.listId, 'tasks');

      final open = HomeWidgetAction.fromUri(
        Uri.parse('yata://widget/open_task?taskId=t1&listId=tasks'),
      );
      expect(open?.type, HomeWidgetActionType.openTask);
      expect(open?.taskId, 't1');
      expect(open?.listId, 'tasks');
    });

    test('returns null for legacy and unrelated URIs', () {
      expect(HomeWidgetAction.fromUri(null), isNull);
      expect(
        HomeWidgetAction.fromUri(Uri.parse('https://example.com')),
        isNull,
      );
      expect(
        HomeWidgetAction.fromUri(
          Uri.parse('yata://widget/toggle_complete?taskId=t2&completed=true'),
        ),
        isNull,
      );
      expect(
        HomeWidgetAction.fromUri(
          Uri.parse('yata://widget/toggle_important?taskId=t3&important=false'),
        ),
        isNull,
      );
      expect(
        HomeWidgetAction.fromUri(Uri.parse('yata://widget/refresh')),
        isNull,
      );
    });
  });

  group('HomeWidgetSnapshotSerializer & HomeWidgetService', () {
    test('serializes atomic snapshot with photo accent, sortOption, and metadata', () async {
      final transport = FakeHomeWidgetTransport();
      final service = HomeWidgetService(transport);
      final now = DateTime(2026, 11, 24, 9, 0);
      const customList = TodoList(
        id: 'list_work',
        title: 'Work',
        emoji: '💼',
        themePhoto: ListThemePhoto.beach,
        sortOption: TaskSortOption.dueDate,
      );
      final lists = [...defaultSmartLists(), customList];
      final tasks = [
        TaskItem(
          id: 't1',
          listId: 'list_work',
          title: 'Finish report',
          createdAt: now.toUtc(),
          isInMyDay: true,
          isImportant: true,
          dueDate: DateTime(2026, 11, 24),
          reminderAt: DateTime(2026, 11, 24, 14, 30).toUtc(),
        ),
        TaskItem(
          id: 't2',
          listId: 'tasks',
          title: 'Overdue item',
          createdAt: now.toUtc(),
          dueDate: DateTime(2026, 11, 23),
        ),
        TaskItem(
          id: 't3',
          listId: 'tasks',
          title: 'Buy milk',
          createdAt: now.toUtc(),
          isCompleted: true,
        ),
      ];
      final state = TodoState(
        lists: lists,
        groups: const [],
        tasks: tasks,
        selectedListId: 'my_day',
      );

      await service.syncWithState(
        state,
        accountId: 'acct_1',
        accountName: 'leo@example.com',
        strings: const HomeWidgetStrings(
          localeName: 'zh',
          myDay: '我的一天',
          today: '今天',
          yesterday: '昨天',
        ),
        now: now,
      );

      expect(transport.commits, hasLength(1));
      final snapshot = transport.commits.single.decoded;
      expect(snapshot['version'], 1);
      expect(snapshot['accountId'], 'acct_1');
      expect(snapshot['accountName'], 'leo@example.com');
      expect(snapshot['dateKey'], '2026-11-24');
      expect(snapshot['locale'], 'zh');
      expect(snapshot['myDayLabel'], '我的一天');
      expect(snapshot['todayLabel'], '今天');
      expect(snapshot['yesterdayLabel'], '昨天');
      expect(snapshot['moveStarredToTop'], isTrue);

      final listsJson = snapshot['lists'] as List<dynamic>;
      final workEntry = listsJson.firstWhere((e) => e['id'] == 'list_work');
      expect(workEntry['title'], 'Work');
      expect(workEntry['emoji'], '💼');
      expect(workEntry['activeCount'], 1);
      expect(workEntry['sortOption'], 'dueDate');
      expect(
        workEntry['accentColorLight'],
        TodoColors.listAccentFor(customList, brightness: Brightness.light)
            .toARGB32(),
      );
      expect(
        workEntry['accentColorDark'],
        TodoColors.listAccentFor(customList, brightness: Brightness.dark)
            .toARGB32(),
      );

      final myDayEntry = listsJson.firstWhere((e) => e['id'] == 'my_day');
      expect(myDayEntry['title'], '我的一天');

      final listTaskIds = snapshot['listTaskIds'] as Map<String, dynamic>;
      expect(listTaskIds['my_day'], ['t1']);
      expect(listTaskIds['list_work'], ['t1']);
      expect(listTaskIds['completed'], ['t3']);

      final tasksJson = snapshot['tasks'] as List<dynamic>;
      final t1Json = tasksJson.firstWhere((e) => e['id'] == 't1');
      expect(t1Json['dueLabel'], '今天');
      expect(t1Json['dueDateYmd'], '2026-11-24');
      expect(t1Json['reminderAtMs'], isA<int>());
      expect(t1Json['isOverdue'], isFalse);
      expect(t1Json['isImportant'], isTrue);
      expect(t1Json['listTitle'], 'Work');

      final t2Json = tasksJson.firstWhere((e) => e['id'] == 't2');
      expect(t2Json['dueLabel'], '昨天');
      expect(t2Json['isOverdue'], isTrue);
    });

    test('coalesces overlapping syncs to latest snapshot and preserves flags', () async {
      final transport = FakeHomeWidgetTransport();
      final firstGate = Completer<void>();
      var callCount = 0;
      transport.onSaveSnapshotHook = () async {
        callCount += 1;
        if (callCount == 1) {
          await firstGate.future;
        }
      };

      final service = HomeWidgetService(transport);
      final baseState = TodoState(
        lists: defaultSmartLists(),
        groups: const [],
        tasks: const [],
        selectedListId: 'my_day',
      );
      final s1 = baseState.copyWith(
        tasks: [
          TaskItem(
            id: 't1',
            listId: 'tasks',
            title: 'First',
            createdAt: DateTime.utc(2026, 11, 24, 9),
          ),
        ],
      );
      final s2 = baseState.copyWith(
        tasks: [
          TaskItem(
            id: 't2',
            listId: 'tasks',
            title: 'Second',
            createdAt: DateTime.utc(2026, 11, 24, 9),
          ),
        ],
      );
      final s3 = baseState.copyWith(
        tasks: [
          TaskItem(
            id: 't3',
            listId: 'tasks',
            title: 'Third',
            createdAt: DateTime.utc(2026, 11, 24, 9),
          ),
        ],
      );

      final now = DateTime(2026, 11, 24, 9);
      final f1 = service.syncWithState(s1, accountId: 'a', now: now);
      await Future<void>.delayed(Duration.zero);
      final f2 = service.syncWithState(
        s2,
        accountId: 'a',
        ackedOpId: 4,
        now: now,
      );
      final f3 = service.syncWithState(
        s3,
        accountId: 'a',
        clearRefreshing: true,
        now: now,
      );

      firstGate.complete();
      await Future.wait([f1, f2, f3]);

      expect(transport.commits, hasLength(2));
      expect(
        (transport.commits[0].decoded['tasks'] as List).single['title'],
        'First',
      );
      expect(
        (transport.commits[1].decoded['tasks'] as List).single['title'],
        'Third',
      );
      expect(transport.commits[1].ackedOpId, 4);
      expect(transport.commits[1].isRefreshing, isFalse);
    });

    test('deduplicates identical states unless ackedOpId, clearRefreshing, force, or cleared', () async {
      final transport = FakeHomeWidgetTransport();
      final service = HomeWidgetService(transport);
      final state = TodoState(
        lists: defaultSmartLists(),
        groups: const [],
        tasks: const [],
        selectedListId: 'my_day',
      );
      final now = DateTime(2026, 11, 24, 9);

      await service.syncWithState(state, accountId: 'a', now: now);
      await service.syncWithState(state, accountId: 'a', now: now);
      expect(transport.commits, hasLength(1));

      await service.syncWithState(state, accountId: 'a', ackedOpId: 1, now: now);
      expect(transport.commits, hasLength(2));

      await service.syncWithState(
        state,
        accountId: 'a',
        clearRefreshing: true,
        now: now,
      );
      expect(transport.commits, hasLength(3));

      await service.syncWithState(state, accountId: 'a', force: true, now: now);
      expect(transport.commits, hasLength(4));

      await service.clearWidgetData();
      expect(transport.storage[kWidgetSnapshotKey], isNull);
      expect(transport.updateCalls, 5);

      await service.syncWithState(state, accountId: 'a', now: now);
      expect(transport.commits, hasLength(5));
    });

    test('consumeInitialLaunchUri returns launch URI once and resolves system strings', () async {
      final transport = FakeHomeWidgetTransport()
        ..initialLaunchUri = Uri.parse('yata://widget/add?listId=tasks');
      final service = HomeWidgetService(transport);

      expect(
        await service.consumeInitialLaunchUri(),
        Uri.parse('yata://widget/add?listId=tasks'),
      );
      expect(await service.consumeInitialLaunchUri(), isNull);

      final zhFromList = await HomeWidgetService.resolveSystemStrings(
        locales: const [Locale('ja', 'JP'), Locale('zh', 'CN')],
      );
      expect(zhFromList.localeName, 'zh');
      expect(zhFromList.myDay, '我的一天');
      expect(zhFromList.today, '今天');

      final fallbackToEn = HomeWidgetStrings.fromLocales(
        const [Locale('fr', 'FR')],
      );
      expect(fallbackToEn.localeName, 'en');
      expect(fallbackToEn.myDay, 'My Day');
      expect(fallbackToEn.today, 'Today');
    });
  });
}
