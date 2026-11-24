import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/data/todo_repository.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/theme/todo_theme.dart';
import 'package:yata/widget/home_widget_sync.dart';

class _CommittedSnapshotRecord {
  const _CommittedSnapshotRecord({
    required this.snapshotJson,
    required this.ackedOpId,
    required this.isRefreshing,
  });

  final String snapshotJson;
  final int ackedOpId;
  final bool? isRefreshing;

  Map<String, dynamic> get decoded =>
      jsonDecode(snapshotJson) as Map<String, dynamic>;
}

class _FakeHomeWidgetTransport implements HomeWidgetTransport {
  final Map<String, Object?> storage = {};
  final List<_CommittedSnapshotRecord> commits = [];
  final StreamController<Uri?> clickedController =
      StreamController<Uri?>.broadcast();
  final StreamController<String> syncRequestsController =
      StreamController<String>.broadcast();
  int updateCalls = 0;
  Uri? initialLaunchUri;
  Future<void> Function()? onSaveSnapshotHook;

  void setPendingOps(List<WidgetPendingOp> ops) {
    storage[kWidgetPendingOpsKey] = jsonEncode([
      for (final op in ops)
        {
          'opId': op.opId,
          'type': op.type.wireName,
          'taskId': op.taskId,
          'value': op.value,
          'accountId': op.accountId,
          'timestampMs': op.timestampMs,
        },
    ]);
  }

  @override
  Future<T?> getData<T>(String key) async => storage[key] as T?;

  @override
  Future<void> saveData(String key, Object? value) async {
    if (key == kWidgetSnapshotKey && onSaveSnapshotHook != null) {
      await onSaveSnapshotHook!();
    }
    if (value == null) {
      storage.remove(key);
    } else {
      storage[key] = value;
    }
  }

  @override
  Future<void> updateWidget() async {
    updateCalls += 1;
    final snapshotJson = storage[kWidgetSnapshotKey] as String?;
    if (snapshotJson != null) {
      commits.add(
        _CommittedSnapshotRecord(
          snapshotJson: snapshotJson,
          ackedOpId: storage[kWidgetAckedOpIdKey] as int? ?? 0,
          isRefreshing: storage[kWidgetIsRefreshingKey] as bool?,
        ),
      );
    }
  }

  @override
  Future<Uri?> initiallyLaunchedFromHomeWidget() async => initialLaunchUri;

  @override
  Stream<Uri?> get widgetClicked => clickedController.stream;

  @override
  Stream<String> get widgetSyncRequests => syncRequestsController.stream;

  Future<void> closeStreams() async {
    await clickedController.close();
    await syncRequestsController.close();
  }
}

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
      final transport = _FakeHomeWidgetTransport();
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
      final transport = _FakeHomeWidgetTransport();
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
      final transport = _FakeHomeWidgetTransport();
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
      final transport = _FakeHomeWidgetTransport()
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

  group('WidgetEventProcessor & lifecycle sync', () {
    Future<ProviderContainer> createContainer({
      required List<Account> accounts,
      required String? activeAccountId,
      List<TaskItem> initialTasks = const [],
    }) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': jsonEncode(accounts.map((a) => a.toJson()).toList()),
        'yata.active_account_id': ?activeAccountId,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      if (activeAccountId != null && initialTasks.isNotEmpty) {
        final repo = TodoRepository.forAccount(
          prefs,
          accountId: activeAccountId,
          database: db,
        );
        await repo.saveTasks(initialTasks);
      }
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          todoDatabaseProvider.overrideWithValue(db),
        ],
      );
      addTearDown(() async {
        await container.read(todoRepositoryProvider).flushPendingWrites();
        container.dispose();
        await db.close();
      });
      return container;
    }

    final localAccount = LocalAccount(
      id: 'acct_a',
      displayName: 'Alice',
      email: 'alice@example.com',
      createdAt: DateTime.utc(2026, 11, 24),
    );
    final msAccount = MicrosoftAccount(
      id: 'acct_ms',
      displayName: 'Bob',
      email: 'bob@outlook.com',
      createdAt: DateTime.utc(2026, 11, 24),
      microsoftUserId: 'ms_cid_1',
    );

    test('applies unacked ops, skips already-acked & cross-account ops, and handles recurrence', () async {
      final alreadyAckedTask = TaskItem(
        id: 't0',
        listId: 'tasks',
        title: 'Already acked',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final recurring = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Daily standup',
        createdAt: DateTime.utc(2026, 11, 24, 8),
        dueDate: DateTime(2026, 11, 24),
        recurrence: RecurrenceType.daily,
      );
      final otherTask = TaskItem(
        id: 't2',
        listId: 'tasks',
        title: 'Write docs',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final crossAcctTask = TaskItem(
        id: 't3',
        listId: 'tasks',
        title: 'Do not touch',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final container = await createContainer(
        accounts: [localAccount],
        activeAccountId: 'acct_a',
        initialTasks: [alreadyAckedTask, recurring, otherTask, crossAcctTask],
      );

      final transport = _FakeHomeWidgetTransport();
      transport.storage[kWidgetAckedOpIdKey] = 1;
      transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't0',
          value: true,
          accountId: 'acct_a',
        ),
        const WidgetPendingOp(
          opId: 2,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
          accountId: 'acct_a',
        ),
        const WidgetPendingOp(
          opId: 3,
          type: WidgetPendingOpType.toggleImportant,
          taskId: 't3',
          value: true,
          accountId: 'acct_other',
        ),
        const WidgetPendingOp(
          opId: 4,
          type: WidgetPendingOpType.toggleImportant,
          taskId: 't2',
          value: true,
          accountId: 'acct_a',
        ),
      ]);

      final result = await WidgetEventProcessor(
        widgetService: HomeWidgetService(transport),
        read: container.read,
        strings: const HomeWidgetStrings(),
        isBackground: false,
        runCloudSync: () async {},
        scheduleBackgroundedAppCloudSync: () {},
      ).process();

      expect(result.didMutate, isTrue);
      final tasks = container.read(todoProvider).tasks;
      expect(tasks.firstWhere((t) => t.id == 't0').isCompleted, isFalse);
      expect(tasks.where((t) => t.title == 'Daily standup'), hasLength(2));
      expect(tasks.firstWhere((t) => t.id == 't1').isCompleted, isTrue);
      expect(tasks.firstWhere((t) => t.id == 't2').isImportant, isTrue);
      expect(tasks.firstWhere((t) => t.id == 't3').isImportant, isFalse);
      expect(transport.storage[kWidgetAckedOpIdKey], 4);
      expect(transport.commits.single.ackedOpId, 4);
    });

    test('clears widget data when signed out', () async {
      final container = await createContainer(
        accounts: const [],
        activeAccountId: null,
      );
      final transport = _FakeHomeWidgetTransport();
      transport.storage[kWidgetSnapshotKey] = '{"version":1}';
      transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
        ),
      ]);

      await WidgetEventProcessor(
        widgetService: HomeWidgetService(transport),
        read: container.read,
        strings: const HomeWidgetStrings(),
        isBackground: false,
        runCloudSync: () async {},
        scheduleBackgroundedAppCloudSync: () {},
      ).process();

      expect(transport.storage[kWidgetSnapshotKey], isNull);
      expect(transport.storage[kWidgetPendingOpsKey], isNull);
      expect(transport.updateCalls, 1);
      expect(transport.commits, isEmpty);
    });

    test('refreshRequested always clears refreshing even if cloud sync throws', () async {
      final container = await createContainer(
        accounts: [localAccount],
        activeAccountId: 'acct_a',
      );
      final transport = _FakeHomeWidgetTransport();
      transport.storage[kWidgetRefreshRequestedKey] = true;
      transport.storage[kWidgetIsRefreshingKey] = true;

      final result = await WidgetEventProcessor(
        widgetService: HomeWidgetService(transport),
        read: container.read,
        strings: const HomeWidgetStrings(),
        isBackground: true,
        runCloudSync: () async {
          throw StateError('network down');
        },
        scheduleBackgroundedAppCloudSync: () {},
      ).process();

      expect(result.didSync, isFalse);
      expect(transport.storage[kWidgetRefreshRequestedKey], isFalse);
      expect(transport.storage[kWidgetIsRefreshingKey], isFalse);
      expect(transport.commits.last.isRefreshing, isFalse);
    });

    test('background mutation runs cloud sync while backgrounded foreground app schedules debounced sync', () async {
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Sync me',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );

      final containerBg = await createContainer(
        accounts: [msAccount],
        activeAccountId: 'acct_ms',
        initialTasks: [task],
      );
      final bgTransport = _FakeHomeWidgetTransport()
        ..setPendingOps([
          const WidgetPendingOp(
            opId: 1,
            type: WidgetPendingOpType.toggleComplete,
            taskId: 't1',
            value: true,
            accountId: 'acct_ms',
          ),
        ]);
      var bgCloudSyncCalls = 0;
      await WidgetEventProcessor(
        widgetService: HomeWidgetService(bgTransport),
        read: containerBg.read,
        strings: const HomeWidgetStrings(),
        isBackground: true,
        runCloudSync: () async {
          bgCloudSyncCalls += 1;
        },
        scheduleBackgroundedAppCloudSync: () {},
      ).process();
      expect(bgCloudSyncCalls, 1);

      final containerFgPaused = await createContainer(
        accounts: [msAccount],
        activeAccountId: 'acct_ms',
        initialTasks: [task],
      );
      final fgTransport = _FakeHomeWidgetTransport()
        ..setPendingOps([
          const WidgetPendingOp(
            opId: 1,
            type: WidgetPendingOpType.toggleComplete,
            taskId: 't1',
            value: true,
            accountId: 'acct_ms',
          ),
        ]);
      var scheduledDebouncedCalls = 0;
      var fgDirectSyncCalls = 0;
      await WidgetEventProcessor(
        widgetService: HomeWidgetService(fgTransport),
        read: containerFgPaused.read,
        strings: const HomeWidgetStrings(),
        isBackground: false,
        isAppForeground: false,
        runCloudSync: () async {
          fgDirectSyncCalls += 1;
        },
        scheduleBackgroundedAppCloudSync: () {
          scheduledDebouncedCalls += 1;
        },
      ).process();
      expect(fgDirectSyncCalls, 0);
      expect(scheduledDebouncedCalls, 1);
    });

    test('TodoRepository.flushPendingWrites waits for queued SQLite writes', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repo = TodoRepository.forAccount(
        prefs,
        accountId: 'acct_flush',
        database: db,
      );
      final task = TaskItem(
        id: 't_flush',
        listId: 'tasks',
        title: 'Persist me',
        createdAt: DateTime.utc(2026, 11, 24),
      );

      unawaited(repo.saveTasks([task]));
      await repo.flushPendingWrites();

      final rows = await db.selectTaskItemRecords('acct_flush');
      expect(rows, hasLength(1));
      expect(rows.single.id, 't_flush');
    });
  });

  group('HomeWidgetSyncController & homeWidgetAutoSyncProvider', () {
    Future<({
      ProviderContainer container,
      _FakeHomeWidgetTransport transport,
      SharedPreferences prefs,
      TodoDatabase db,
    })> createSyncHarness({
      List<Account> accounts = const [],
      String? activeAccountId,
      List<TaskItem> initialTasks = const [],
      Map<String, Object> extraPrefs = const {},
    }) async {
      SharedPreferences.setMockInitialValues({
        'yata.accounts': jsonEncode(accounts.map((a) => a.toJson()).toList()),
        'yata.active_account_id': ?activeAccountId,
        ...extraPrefs,
      });
      final prefs = await SharedPreferences.getInstance();
      final db = TodoDatabase(NativeDatabase.memory());
      if (activeAccountId != null && initialTasks.isNotEmpty) {
        final repo = TodoRepository.forAccount(
          prefs,
          accountId: activeAccountId,
          database: db,
        );
        await repo.saveTasks(initialTasks);
        await repo.flushPendingWrites();
      }
      final transport = _FakeHomeWidgetTransport();
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          todoDatabaseProvider.overrideWithValue(db),
          homeWidgetServiceProvider.overrideWithValue(
            HomeWidgetService(transport),
          ),
        ],
      );
      addTearDown(() async {
        await container.read(todoRepositoryProvider).flushPendingWrites();
        container.dispose();
        await db.close();
        await transport.closeStreams();
      });
      return (
        container: container,
        transport: transport,
        prefs: prefs,
        db: db,
      );
    }

    test(
      'autoSync clears when signed out without loading tasks, syncs on task mutation and account switch, and clears on sign-out',
      () async {
        final h = await createSyncHarness();
        h.container.listen<void>(homeWidgetAutoSyncProvider, (_, _) {});
        await pumpEventQueue();

        expect(h.container.read(todoProvider.exists), isFalse);
        expect(h.transport.updateCalls, 1);
        expect(h.transport.storage[kWidgetSnapshotKey], isNull);

        final accounts = h.container.read(accountProvider.notifier);
        final alice = await accounts.signInLocal(
          'Alice',
          fallbackName: 'Alice',
          fallbackEmail: 'alice@example.com',
        );
        await pumpEventQueue();
        h.container.read(tasksViewPresenterProvider).addTask(title: 'Alice task');
        await pumpEventQueue();

        final aliceSnapshot =
            jsonDecode(h.transport.storage[kWidgetSnapshotKey]! as String)
                as Map<String, dynamic>;
        expect(aliceSnapshot['accountName'], 'Alice');
        expect(
          (aliceSnapshot['tasks'] as List).map((t) => t['title']),
          ['Alice task'],
        );

        final bob = await accounts.signInLocal(
          'Bob',
          fallbackName: 'Bob',
          fallbackEmail: 'bob@example.com',
        );
        await pumpEventQueue();

        final bobSnapshot =
            jsonDecode(h.transport.storage[kWidgetSnapshotKey]! as String)
                as Map<String, dynamic>;
        expect(bobSnapshot['accountName'], 'Bob');
        expect(bobSnapshot['tasks'], isEmpty);

        await accounts.switchAccount(alice.id);
        await pumpEventQueue();
        final backToAliceSnapshot =
            jsonDecode(h.transport.storage[kWidgetSnapshotKey]! as String)
                as Map<String, dynamic>;
        expect(backToAliceSnapshot['accountName'], 'Alice');
        expect(
          (backToAliceSnapshot['tasks'] as List).map((t) => t['title']),
          ['Alice task'],
        );

        await accounts.signOut(alice.id);
        await accounts.signOut(bob.id);
        await pumpEventQueue();

        expect(h.transport.storage[kWidgetSnapshotKey], isNull);
      },
    );

    test('bootstrap drains pending ops, pushes snapshot, and consumes initial URI once', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
        createdAt: DateTime.utc(2026, 11, 24),
      );
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Buy coffee',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createSyncHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [task],
      );
      h.transport
        ..setPendingOps([
          const WidgetPendingOp(
            opId: 3,
            type: WidgetPendingOpType.toggleComplete,
            taskId: 't1',
            value: true,
            accountId: 'acct_a',
          ),
        ])
        ..initialLaunchUri = Uri.parse('yata://widget/open_list?listId=tasks');

      final controller = h.container.read(homeWidgetSyncProvider);
      final action = await controller.bootstrap();

      expect(action?.type, HomeWidgetActionType.openList);
      expect(action?.listId, 'tasks');
      expect(
        h.container.read(todoProvider).tasks.single.isCompleted,
        isTrue,
      );
      expect(h.transport.storage[kWidgetAckedOpIdKey], 3);
      expect(h.transport.commits, isNotEmpty);

      final secondAction = await controller.bootstrap();
      expect(secondAction, isNull);
    });

    test('widgetClicked drains pending ops before emitting action, and widgetSyncRequests runs sync', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
        createdAt: DateTime.utc(2026, 11, 24),
      );
      final task = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Review PR',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createSyncHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [task],
      );
      final controller = h.container.read(homeWidgetSyncProvider);

      h.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 1,
          type: WidgetPendingOpType.toggleImportant,
          taskId: 't1',
          value: true,
          accountId: 'acct_a',
        ),
      ]);
      h.transport.syncRequestsController.add('toggle');
      await pumpEventQueue();

      expect(h.container.read(todoProvider).tasks.single.isImportant, isTrue);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 1);

      h.transport.setPendingOps([
        const WidgetPendingOp(
          opId: 2,
          type: WidgetPendingOpType.toggleComplete,
          taskId: 't1',
          value: true,
          accountId: 'acct_a',
        ),
      ]);
      final emittedFuture = controller.actions.first;
      h.transport.clickedController.add(
        Uri.parse('yata://widget/open_task?taskId=t1'),
      );
      final emitted = await emittedFuture;

      expect(emitted.type, HomeWidgetActionType.openTask);
      expect(emitted.taskId, 't1');
      expect(h.container.read(todoProvider).tasks.single.isCompleted, isTrue);
      expect(h.transport.storage[kWidgetAckedOpIdKey], 2);
    });

    test('syncFromWidget reloads prefs and invalidates todoProvider when background mutated', () async {
      final account = LocalAccount(
        id: 'acct_a',
        displayName: 'Alice',
        email: 'alice@example.com',
        createdAt: DateTime.utc(2026, 11, 24),
      );
      final initialTask = TaskItem(
        id: 't1',
        listId: 'tasks',
        title: 'Before bg update',
        createdAt: DateTime.utc(2026, 11, 24, 8),
      );
      final h = await createSyncHarness(
        accounts: [account],
        activeAccountId: 'acct_a',
        initialTasks: [initialTask],
        extraPrefs: {kWidgetLastMutationMsKey: 100},
      );
      final controller = h.container.read(homeWidgetSyncProvider);
      expect(h.container.read(todoProvider).tasks.single.title, 'Before bg update');

      // Simulate another isolate persisting a modified task row and bumping timestamp.
      final bgRepo = TodoRepository.forAccount(
        h.prefs,
        accountId: 'acct_a',
        database: h.db,
      );
      await bgRepo.saveTasks([
        initialTask.copyWith(title: 'Updated in background'),
      ]);
      await bgRepo.flushPendingWrites();
      await h.prefs.setInt(kWidgetLastMutationMsKey, 200);

      await controller.syncFromWidget(reason: 'resume');

      expect(
        h.container.read(todoProvider).tasks.single.title,
        'Updated in background',
      );
      final snapshot =
          jsonDecode(h.transport.storage[kWidgetSnapshotKey]! as String)
              as Map<String, dynamic>;
      expect(
        (snapshot['tasks'] as List).single['title'],
        'Updated in background',
      );
    });
  });
}
