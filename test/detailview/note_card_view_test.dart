import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/detailview/detail_view_presenter.dart';
import 'package:yata/detailview/note/note_card_view.dart';
import 'package:yata/ui/widgets/task_pickers.dart';
import 'package:yata/l10n/app_localizations.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_models.dart';
import 'package:yata/sync/microsoft/substrate_sync_mappers.dart';
import 'package:yata/ui/widgets/task_list_tile.dart';
import 'package:yata/ui/task_grouping.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';
import 'package:yata/theme/todo_theme.dart';
import 'package:yata/homewidget/home_widget_service.dart';
import 'package:yata/data/preferences.dart';

const _testLocalizationDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  ...GlobalMaterialLocalizations.delegates,
];

Future<BuildContext> _pumpLocalizedContext(
  WidgetTester tester, {
  required Locale locale,
}) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: _testLocalizationDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

Widget _wrapCard({required Locale locale, required Widget child}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: _testLocalizationDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );
}

void main() {
  group('Note and created timestamp formatting', () {
    testWidgets('formats all relative buckets in English matching yp.r.F/j', (
      WidgetTester tester,
    ) async {
      final context = await _pumpLocalizedContext(
        tester,
        locale: const Locale('en'),
      );
      final now = DateTime(2026, 11, 24, 15, 30);

      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(seconds: 40)),
          now: now,
        ),
        'Updated a few moments ago',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(minutes: 1)),
          now: now,
        ),
        'Updated 1 minute ago',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(minutes: 12)),
          now: now,
        ),
        'Updated 12 minutes ago',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(hours: 1)),
          now: now,
        ),
        'Updated 1 hour ago',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(hours: 3)),
          now: now,
        ),
        'Updated 3 hours ago',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          DateTime(2026, 11, 23, 23, 50),
          now: now,
        ),
        'Updated yesterday',
      );

      final earlierSameYear = DateTime(2026, 11, 20, 14, 0);
      expect(
        formatNoteUpdatedDateLabel(context, earlierSameYear, now: now),
        'Updated on ${DateFormat.MMMEd('en').format(earlierSameYear)}',
      );

      final previousYear = DateTime(2025, 11, 20, 14, 0);
      expect(
        formatNoteUpdatedDateLabel(context, previousYear, now: now),
        'Updated on ${DateFormat.yMMMEd('en').format(previousYear)}',
      );

      expect(
        formatCreatedDateLabel(context, earlierSameYear, now: now),
        'Created on ${DateFormat.MMMEd('en').format(earlierSameYear)}',
      );
      expect(
        formatCreatedDateLabel(
          context,
          now.subtract(const Duration(hours: 2)),
          now: now,
        ),
        'Created 2 hours ago',
      );
    });

    testWidgets('formats all relative buckets in Chinese matching yp.r.F/j', (
      WidgetTester tester,
    ) async {
      final context = await _pumpLocalizedContext(
        tester,
        locale: const Locale('zh'),
      );
      final now = DateTime(2026, 11, 24, 15, 30);

      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(seconds: 20)),
          now: now,
        ),
        '更新于 刚刚',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(minutes: 5)),
          now: now,
        ),
        '更新于 5 分钟前',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          now.subtract(const Duration(hours: 2)),
          now: now,
        ),
        '更新于 2 小时前',
      );
      expect(
        formatNoteUpdatedDateLabel(
          context,
          DateTime(2026, 11, 23, 9, 0),
          now: now,
        ),
        '更新于 昨天',
      );

      final earlierSameYear = DateTime(2026, 11, 20, 14, 0);
      expect(
        formatNoteUpdatedDateLabel(context, earlierSameYear, now: now),
        '已在 ${DateFormat.MMMEd('zh').format(earlierSameYear)} 更新',
      );

      final previousYear = DateTime(2025, 11, 20, 14, 0);
      expect(
        formatNoteUpdatedDateLabel(context, previousYear, now: now),
        '已在 ${DateFormat.yMMMEd('zh').format(previousYear)} 更新',
      );

      expect(
        formatCreatedDateLabel(context, earlierSameYear, now: now),
        '创建于 ${DateFormat.MMMEd('zh').format(earlierSameYear)}',
      );
    });

    testWidgets(
      'converts UTC timestamps to local time near midnight boundaries',
      (WidgetTester tester) async {
        final context = await _pumpLocalizedContext(
          tester,
          locale: const Locale('en'),
        );

        final earlyNow = DateTime(2026, 11, 24, 0, 30);
        final earlyTargetLocal = DateTime(2026, 11, 24, 0, 10);
        expect(
          formatNoteUpdatedDateLabel(
            context,
            earlyTargetLocal.toUtc(),
            now: earlyNow,
          ),
          formatNoteUpdatedDateLabel(context, earlyTargetLocal, now: earlyNow),
        );
        expect(
          formatNoteUpdatedDateLabel(
            context,
            earlyTargetLocal.toUtc(),
            now: earlyNow.toUtc(),
          ),
          'Updated 20 minutes ago',
        );

        final prevLateLocal = DateTime(2026, 11, 23, 23, 45);
        expect(
          formatNoteUpdatedDateLabel(
            context,
            prevLateLocal.toUtc(),
            now: earlyNow,
          ),
          'Updated yesterday',
        );
        expect(
          formatCreatedDateLabel(context, prevLateLocal.toUtc(), now: earlyNow),
          'Created yesterday',
        );

        final lateNow = DateTime(2026, 11, 24, 23, 30);
        final lateTargetLocal = DateTime(2026, 11, 24, 22, 0);
        expect(
          formatNoteUpdatedDateLabel(
            context,
            lateTargetLocal.toUtc(),
            now: lateNow,
          ),
          'Updated 1 hour ago',
        );

        final earlierLateLocal = DateTime(2026, 11, 20, 23, 30);
        expect(
          formatNoteUpdatedDateLabel(
            context,
            earlierLateLocal.toUtc(),
            now: lateNow,
          ),
          'Updated on ${DateFormat.MMMEd('en').format(earlierLateLocal)}',
        );
      },
    );
  });

  group('NoteCardView', () {
    testWidgets(
      'displays formatted label for non-empty note with UTC noteUpdatedAt',
      (WidgetTester tester) async {
        final now = DateTime.now();
        final prevYearLocal = DateTime(now.year - 1, 6, 15, 0, 30);

        await tester.pumpWidget(
          _wrapCard(
            locale: const Locale('en'),
            child: NoteCardView(
              task: TaskItem(
                id: 't1',
                listId: 'tasks',
                title: 'Task',
                createdAt: prevYearLocal.toUtc(),
                note: 'Non-empty note',
                noteUpdatedAt: prevYearLocal.toUtc(),
              ),
              cardColor: Colors.white,
              onNoteChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(
            'Updated on ${DateFormat.yMMMEd('en').format(prevYearLocal)}',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'displays relative moments-ago label when updated just now in UTC',
      (WidgetTester tester) async {
        final nowUtc = DateTime.now().toUtc();

        await tester.pumpWidget(
          _wrapCard(
            locale: const Locale('zh'),
            child: NoteCardView(
              task: TaskItem(
                id: 't2',
                listId: 'tasks',
                title: 'Task',
                createdAt: nowUtc,
                note: '刚刚编辑的备注',
                noteUpdatedAt: nowUtc,
              ),
              cardColor: Colors.white,
              onNoteChanged: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('更新于 刚刚'), findsOneWidget);
      },
    );

    testWidgets(
      'hides modification time when note is empty, whitespace-only, or noteUpdatedAt is null',
      (WidgetTester tester) async {
        final now = DateTime.now();

        for (final task in [
          TaskItem(
            id: 'empty_note',
            listId: 'tasks',
            title: 'Task',
            createdAt: now,
            note: '',
            noteUpdatedAt: now,
          ),
          TaskItem(
            id: 'blank_note',
            listId: 'tasks',
            title: 'Task',
            createdAt: now,
            note: '   \n\t ',
            noteUpdatedAt: now,
          ),
          TaskItem(
            id: 'null_timestamp',
            listId: 'tasks',
            title: 'Task',
            createdAt: now,
            note: 'Has text without timestamp',
            noteUpdatedAt: null,
          ),
        ]) {
          await tester.pumpWidget(
            _wrapCard(
              locale: const Locale('en'),
              child: NoteCardView(
                task: task,
                cardColor: Colors.white,
                onNoteChanged: (_) {},
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(find.textContaining('Updated'), findsNothing);
        }
      },
    );
  });

  group('Substrate sync timestamp round-trip', () {
    test('keeps remote CreatedDateTime and BodyLastModifiedTime in UTC and preserves instant on write', () {
      const createdIso = '2026-11-24T06:15:30.1234560Z';
      const bodyModifiedIso = '2026-11-24T06:20:45.6543210Z';

      final remote = RemoteTodoTask.fromJson({
        'Id': 'remote-task-1',
        'ParentFolderId': 'remote-folder-1',
        'Subject': 'Sync timestamps',
        'Body': {'Content': 'Note body', 'ContentType': 'Text'},
        'BodyLastModifiedTime': bodyModifiedIso,
        'CreatedDateTime': createdIso,
        'LastModifiedDateTime': bodyModifiedIso,
      });

      final task = taskFromRemote(
        remote,
        localId: 'local-task-1',
        listId: 'tasks',
        existingSteps: const [],
        idGenerator: (prefix) => '$prefix-1',
      );

      expect(task.createdAt.isUtc, isTrue);
      expect(task.createdAt, DateTime.parse(createdIso));
      expect(task.noteUpdatedAt, isNotNull);
      expect(task.noteUpdatedAt!.isUtc, isTrue);
      expect(task.noteUpdatedAt, DateTime.parse(bodyModifiedIso));

      final payload = buildTaskWritePayload(
        task,
        parentFolderRemoteId: 'remote-folder-1',
        isCreate: false,
        firstDayOfWeek: WeekStart.monday,
      );
      expect(payload['BodyLastModifiedTime'], bodyModifiedIso);
    });
  });

  group('UTC storage and local display alignment', () {
    test('TaskItem, TodoList, ListGroup, and Account serialize instants as UTC and normalize legacy local ISO strings', () {
      final localInstant = DateTime(2026, 11, 24, 15, 30, 45);
      final localDueDate = DateTime(2026, 11, 24);
      final task = TaskItem(
        id: 't_ser',
        listId: 'tasks',
        title: 'Serialize instants',
        createdAt: localInstant,
        dueDate: localDueDate,
        myDayDate: localDueDate,
        postponedDay: localDueDate,
        reminderAt: localInstant,
        note: 'Some note',
        noteUpdatedAt: localInstant,
        completedAt: localInstant,
        orderDateTime: localInstant,
        committedOrder: localInstant,
        updatedAt: localInstant,
        steps: [TaskStep(id: 's1', title: 'Step', orderDateTime: localInstant)],
      );

      final taskJson = task.toJson();
      expect((taskJson['createdAt'] as String), endsWith('Z'));
      expect((taskJson['reminderAt'] as String), endsWith('Z'));
      expect((taskJson['noteUpdatedAt'] as String), endsWith('Z'));
      expect((taskJson['completedAt'] as String), endsWith('Z'));
      expect((taskJson['orderDateTime'] as String), endsWith('Z'));
      expect((taskJson['committedOrder'] as String), endsWith('Z'));
      expect((taskJson['updatedAt'] as String), endsWith('Z'));
      expect(
        ((taskJson['steps'] as List).single as Map)['orderDateTime'] as String,
        endsWith('Z'),
      );
      expect((taskJson['dueDate'] as String).endsWith('Z'), isFalse);
      expect((taskJson['myDayDate'] as String).endsWith('Z'), isFalse);
      expect((taskJson['postponedDay'] as String).endsWith('Z'), isFalse);

      // Legacy local ISO string without trailing Z normalizes to UTC on read.
      final legacyTaskJson = Map<String, dynamic>.from(taskJson)
        ..['createdAt'] = localInstant.toIso8601String()
        ..['noteUpdatedAt'] = localInstant.toIso8601String()
        ..['reminderAt'] = localInstant.toIso8601String()
        ..['completedAt'] = localInstant.toIso8601String();
      final decodedTask = TaskItem.fromJson(legacyTaskJson);
      expect(decodedTask.createdAt.isUtc, isTrue);
      expect(decodedTask.createdAt, localInstant.toUtc());
      expect(decodedTask.noteUpdatedAt!.isUtc, isTrue);
      expect(decodedTask.noteUpdatedAt, localInstant.toUtc());
      expect(decodedTask.reminderAt!.isUtc, isTrue);
      expect(decodedTask.completedAt!.isUtc, isTrue);
      expect(decodedTask.steps.single.orderDateTime!.isUtc, isTrue);
      expect(decodedTask.dueDate!.isUtc, isFalse);
      expect(decodedTask.dueDate, localDueDate);

      final list = TodoList(
        id: 'l1',
        title: 'Work',
        orderDateTime: localInstant,
        updatedAt: localInstant,
      );
      final listJson = list.toJson();
      expect((listJson['orderDateTime'] as String), endsWith('Z'));
      expect((listJson['updatedAt'] as String), endsWith('Z'));
      final decodedList = TodoList.fromJson(
        Map<String, dynamic>.from(listJson)
          ..['orderDateTime'] = localInstant.toIso8601String(),
      );
      expect(decodedList.orderDateTime!.isUtc, isTrue);
      expect(decodedList.orderDateTime, localInstant.toUtc());

      final group = ListGroup(
        id: 'g1',
        title: 'Group',
        orderDateTime: localInstant,
        updatedAt: localInstant,
      );
      final groupJson = group.toJson();
      expect((groupJson['orderDateTime'] as String), endsWith('Z'));
      expect((groupJson['updatedAt'] as String), endsWith('Z'));
      final decodedGroup = ListGroup.fromJson(groupJson);
      expect(decodedGroup.orderDateTime!.isUtc, isTrue);

      final msAccount = MicrosoftAccount(
        id: 'acct_ms',
        displayName: 'Alice',
        lastSyncedAt: localInstant,
      );
      final accountJson = msAccount.toJson();
      expect((accountJson['lastSyncedAt'] as String), endsWith('Z'));
      final decodedAccount = Account.fromJson(
        Map<String, dynamic>.from(accountJson)
          ..['lastSyncedAt'] = localInstant.toIso8601String(),
      ) as MicrosoftAccount;
      expect(decodedAccount.lastSyncedAt!.isUtc, isTrue);
      expect(decodedAccount.lastSyncedAt, localInstant.toUtc());
    });

    test('local mutations store UTC instants and recurring tasks keep local reminder wall-clock time', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final tasksPresenter = container.read(tasksViewPresenterProvider);
      final detailPresenter = container.read(detailViewPresenterProvider);

      final localReminder = DateTime(2026, 11, 24, 9, 30);
      tasksPresenter.addTask(
        title: 'Daily standup',
        targetListId: 'tasks',
        dueDate: DateTime(2026, 11, 24),
        reminderAt: localReminder,
        recurrence: RecurrenceType.daily,
      );

      var task = container.read(todoProvider).tasks.single;
      expect(task.createdAt.isUtc, isTrue);
      expect(task.reminderAt, isNotNull);
      expect(task.reminderAt!.isUtc, isTrue);
      expect(task.reminderAt, localReminder.toUtc());

      detailPresenter.updateTaskNote(task.id, 'Updated note');
      task = container.read(todoProvider).tasks.single;
      expect(task.noteUpdatedAt, isNotNull);
      expect(task.noteUpdatedAt!.isUtc, isTrue);

      final customLocalReminder = DateTime(2026, 11, 24, 21, 15);
      detailPresenter.setTaskReminder(task.id, customLocalReminder);
      task = container.read(todoProvider).tasks.single;
      expect(task.reminderAt!.isUtc, isTrue);
      expect(task.reminderAt, customLocalReminder.toUtc());

      tasksPresenter.setTaskCompleted(task.id, completed: true);
      final tasks = container.read(todoProvider).tasks;
      final completed = tasks.firstWhere((t) => t.isCompleted);
      final next = tasks.firstWhere((t) => !t.isCompleted);
      expect(completed.completedAt, isNotNull);
      expect(completed.completedAt!.isUtc, isTrue);
      expect(next.createdAt.isUtc, isTrue);
      expect(next.dueDate, DateTime(2026, 11, 25));
      expect(next.reminderAt, isNotNull);
      expect(next.reminderAt!.isUtc, isTrue);
      final nextLocalReminder = next.reminderAt!.toLocal();
      expect(nextLocalReminder.year, 2026);
      expect(nextLocalReminder.month, 11);
      expect(nextLocalReminder.day, 25);
      expect(nextLocalReminder.hour, 21);
      expect(nextLocalReminder.minute, 15);
    });

    testWidgets(
      'formatReminderLabel and TaskListTile render UTC reminderAt in local time',
      (WidgetTester tester) async {
        final context = await _pumpLocalizedContext(
          tester,
          locale: const Locale('en'),
        );
        final l10n = AppLocalizations.of(context);
        final now = DateTime.now();

        final todayLateLocal = DateTime(now.year, now.month, now.day, 23, 30);
        expect(
          formatReminderLabel(context, todayLateLocal.toUtc()),
          l10n.remindMeAt(DateFormat.jm().format(todayLateLocal)),
        );

        final tomorrowEarlyLocal = DateTime(
          now.year,
          now.month,
          now.day + 1,
          0,
          30,
        );
        expect(
          formatReminderLabel(context, tomorrowEarlyLocal.toUtc()),
          '${l10n.remindMeAt(DateFormat.jm().format(tomorrowEarlyLocal))}, ${l10n.tomorrow}',
        );

        await tester.pumpWidget(
          _wrapCard(
            locale: const Locale('en'),
            child: TaskListTile(
              task: TaskItem(
                id: 't_tile',
                listId: 'tasks',
                title: 'Reminder task',
                createdAt: now.toUtc(),
                reminderAt: tomorrowEarlyLocal.toUtc(),
              ),
              onTap: () {},
              onToggleCompleted: () {},
              onToggleImportant: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final expectedTimeText = DateFormat.jm().format(tomorrowEarlyLocal);
        expect(find.text(expectedTimeText), findsOneWidget);
        final textWidget = tester.widget<Text>(find.text(expectedTimeText));
        expect(textWidget.style?.color, TodoColors.secondaryTextLight);
      },
    );

    test('HomeWidgetService, TodoState Planned filter, and groupPlannedTasks convert UTC reminderAt to local time', () async {
      final now = DateTime.now();
      final todayEarlyLocal = DateTime(now.year, now.month, now.day, 0, 30);
      final todayNoonLocal = DateTime(now.year, now.month, now.day, 12, 30);
      final tomorrowEarlyLocal = DateTime(
        now.year,
        now.month,
        now.day + 1,
        0,
        15,
      );

      final plannedList = defaultSmartLists().firstWhere(
        (l) => l.smartType == SmartListType.planned,
      );
      final todayTask = TaskItem(
        id: 'today_utc_rem',
        listId: 'tasks',
        title: 'Today early reminder',
        createdAt: now.toUtc(),
        reminderAt: todayEarlyLocal.toUtc(),
      );
      final tomorrowTask = TaskItem(
        id: 'tmr_utc_rem',
        listId: 'tasks',
        title: 'Tomorrow early reminder',
        createdAt: now.toUtc(),
        reminderAt: tomorrowEarlyLocal.toUtc(),
      );

      final todayFiltered = TodoState(
        lists: defaultSmartLists(),
        groups: const [],
        tasks: [todayTask, tomorrowTask],
        selectedListId: plannedList.id,
        plannedDueDateFilter: PlannedDueDateFilter.today,
      ).tasksForList(plannedList);
      expect(todayFiltered.map((t) => t.id), ['today_utc_rem']);

      final grouped = groupPlannedTasks(
        [todayTask, tomorrowTask],
        WeekStart.monday,
        now: DateTime(now.year, now.month, now.day, 10, 0).toUtc(),
      );
      expect(grouped.length, 2);
      expect(grouped[0].bucket, PlannedBucket.today);
      expect(grouped[0].tasks.single.id, 'today_utc_rem');
      expect(grouped[1].bucket, PlannedBucket.tomorrow);
      expect(grouped[1].tasks.single.id, 'tmr_utc_rem');

      final transport = _TestHomeWidgetTransport();
      final widgetService = HomeWidgetService(transport);
      await widgetService.syncWithState(
        TodoState(
          lists: defaultSmartLists(),
          groups: const [],
          tasks: [
            TaskItem(
              id: 'widget_rem',
              listId: 'tasks',
              title: 'Noon reminder',
              createdAt: now.toUtc(),
              reminderAt: todayNoonLocal.toUtc(),
            ),
          ],
          selectedListId: 'tasks',
        ),
        accountId: 'acct_1',
        accountName: 'Test',
      );
      final snapshot = jsonDecode(
        transport.saved[kWidgetSnapshotKey]! as String,
      ) as Map<String, dynamic>;
      final tasksJson = snapshot['tasks'] as List<dynamic>;
      final entry = tasksJson.single as Map<String, dynamic>;
      expect(entry['reminderLabel'], DateFormat.Hm().format(todayNoonLocal));
    });
  });
}

class _TestHomeWidgetTransport implements HomeWidgetTransport {
  final Map<String, Object?> saved = {};

  @override
  Future<T?> getData<T>(String key) async => saved[key] as T?;

  @override
  Future<Uri?> initiallyLaunchedFromHomeWidget() async => null;

  @override
  Future<void> saveData(String key, Object? value) async {
    if (value == null) {
      saved.remove(key);
    } else {
      saved[key] = value;
    }
  }

  @override
  Future<void> updateWidget() async {}

  @override
  Stream<Uri?> get widgetClicked => const Stream.empty();

  @override
  Stream<String> get widgetSyncRequests => const Stream.empty();
}
