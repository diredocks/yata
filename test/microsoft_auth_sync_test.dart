import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/main.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/account/account_provider.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/sync/microsoft_todo_api.dart';
import 'package:yata/tasksview/tasks_action_presenter.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

class _FakeMicrosoftAuthClient implements MicrosoftAuthClient {
  _FakeMicrosoftAuthClient({
    required this.profile,
    this.initialTokens,
  });

  final MicrosoftUserProfile profile;
  MicrosoftAuthTokens? initialTokens;
  int refreshCount = 0;
  Completer<MicrosoftSignInResult>? pollCompleter;

  MicrosoftAuthTokens get _defaultTokens =>
      initialTokens ??
      MicrosoftAuthTokens(
        accessToken: 'access_token_1',
        refreshToken: 'refresh_token_1',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        clientId: 'test_client_id',
      );

  @override
  Future<MicrosoftDeviceCodePrompt> startDeviceCodeFlow({
    String? loginHint,
    String? clientId,
  }) async {
    return const MicrosoftDeviceCodePrompt(
      deviceCode: 'dev_code_123',
      userCode: 'ABCD-1234',
      verificationUri: 'https://microsoft.com/devicelogin',
      expiresIn: 600,
      interval: 1,
      message: 'Enter ABCD-1234',
    );
  }

  @override
  Future<MicrosoftSignInResult> pollDeviceCodeToken(
    MicrosoftDeviceCodePrompt prompt, {
    String? clientId,
    bool Function()? isCancelled,
  }) async {
    if (pollCompleter != null) {
      return pollCompleter!.future;
    }
    return MicrosoftSignInResult(
      profile: profile,
      tokens: _defaultTokens,
    );
  }

  @override
  Future<MicrosoftSignInResult?> signInWithPkceLoopback({
    String? loginHint,
    String? clientId,
    required Future<void> Function(String authUrl) openBrowser,
    bool Function()? isCancelled,
  }) async {
    return MicrosoftSignInResult(
      profile: profile,
      tokens: _defaultTokens,
    );
  }

  @override
  Future<MicrosoftAuthTokens> refreshTokens(MicrosoftAuthTokens current) async {
    refreshCount += 1;
    return MicrosoftAuthTokens(
      accessToken: 'refreshed_access_token_$refreshCount',
      refreshToken: current.refreshToken,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      clientId: current.clientId,
    );
  }

  @override
  Future<MicrosoftUserProfile> fetchUserProfile(String accessToken) async {
    return profile;
  }
}

class _FakeMicrosoftTodoApi implements MicrosoftTodoApi {
  final Map<String, RemoteTodoList> lists = {};
  final Map<String, Map<String, RemoteTodoTask>> tasksByList = {};
  final List<String> deletedListIds = [];
  final List<String> deletedTaskIds = [];
  int _counter = 0;

  String _nextId(String prefix) {
    _counter += 1;
    return '${prefix}_$_counter';
  }

  @override
  Future<List<RemoteTodoList>> fetchLists(String accessToken) async {
    return lists.values.toList();
  }

  @override
  Future<RemoteTodoList> createList(
    String accessToken,
    String displayName,
  ) async {
    final id = _nextId('remote_list');
    final created = RemoteTodoList(id: id, displayName: displayName);
    lists[id] = created;
    tasksByList[id] = {};
    return created;
  }

  @override
  Future<RemoteTodoList> renameList(
    String accessToken,
    String listId,
    String displayName,
  ) async {
    final existing = lists[listId]!;
    final updated = RemoteTodoList(
      id: listId,
      displayName: displayName,
      wellknownListName: existing.wellknownListName,
    );
    lists[listId] = updated;
    return updated;
  }

  @override
  Future<void> deleteList(String accessToken, String listId) async {
    deletedListIds.add(listId);
    lists.remove(listId);
    tasksByList.remove(listId);
  }

  @override
  Future<List<RemoteTodoTask>> fetchTasks(
    String accessToken,
    String listId,
  ) async {
    return (tasksByList[listId] ?? const {}).values.toList();
  }

  @override
  Future<RemoteTodoTask> createTask(
    String accessToken,
    String listId,
    TaskItem task,
  ) async {
    final id = _nextId('remote_task');
    final now = DateTime.now().toUtc();
    final created = RemoteTodoTask(
      id: id,
      title: task.title,
      isCompleted: task.isCompleted,
      isImportant: task.isImportant,
      createdDateTime: task.createdAt,
      lastModifiedDateTime: now,
      dueDate: task.dueDate,
      reminderAt: task.reminderAt,
      recurrence: task.recurrence,
      note: task.note,
    );
    tasksByList.putIfAbsent(listId, () => {})[id] = created;
    return created;
  }

  @override
  Future<RemoteTodoTask> updateTask(
    String accessToken,
    String listId,
    String taskId,
    TaskItem task,
  ) async {
    final now = DateTime.now().toUtc();
    final existing = tasksByList[listId]![taskId]!;
    final updated = RemoteTodoTask(
      id: taskId,
      title: task.title,
      isCompleted: task.isCompleted,
      isImportant: task.isImportant,
      createdDateTime: existing.createdDateTime,
      lastModifiedDateTime: now,
      dueDate: task.dueDate,
      reminderAt: task.reminderAt,
      recurrence: task.recurrence,
      note: task.note,
      checklistItems: existing.checklistItems,
    );
    tasksByList[listId]![taskId] = updated;
    return updated;
  }

  @override
  Future<void> deleteTask(
    String accessToken,
    String listId,
    String taskId,
  ) async {
    deletedTaskIds.add(taskId);
    tasksByList[listId]?.remove(taskId);
  }

  @override
  Future<RemoteChecklistItem> createChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    TaskStep step,
  ) async {
    final id = _nextId('remote_step');
    final item = RemoteChecklistItem(
      id: id,
      displayName: step.title,
      isChecked: step.isCompleted,
    );
    final existing = tasksByList[listId]![taskId]!;
    tasksByList[listId]![taskId] = RemoteTodoTask(
      id: existing.id,
      title: existing.title,
      isCompleted: existing.isCompleted,
      isImportant: existing.isImportant,
      createdDateTime: existing.createdDateTime,
      lastModifiedDateTime: existing.lastModifiedDateTime,
      checklistItems: [...existing.checklistItems, item],
    );
    return item;
  }

  @override
  Future<RemoteChecklistItem> updateChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    TaskStep step,
  ) async {
    return RemoteChecklistItem(
      id: step.remoteId!,
      displayName: step.title,
      isChecked: step.isCompleted,
    );
  }

  @override
  Future<void> deleteChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    String itemId,
  ) async {}
}

void main() {
  testWidgets(
    'Microsoft sign-in shows device code dialog, authenticates, and syncs lists/tasks bidirectionally',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final authClient = _FakeMicrosoftAuthClient(
        profile: const MicrosoftUserProfile(
          id: 'ms_user_001',
          displayName: 'Alex Mercer',
          email: 'alex@outlook.com',
        ),
      );
      authClient.pollCompleter = Completer<MicrosoftSignInResult>();

      final todoApi = _FakeMicrosoftTodoApi();
      todoApi.lists['default_remote'] = const RemoteTodoList(
        id: 'default_remote',
        displayName: 'Tasks',
        wellknownListName: 'defaultList',
      );
      todoApi.lists['work_remote'] = const RemoteTodoList(
        id: 'work_remote',
        displayName: 'Work',
      );
      todoApi.tasksByList['default_remote'] = {
        't1': RemoteTodoTask(
          id: 't1',
          title: 'Cloud default task',
          isCompleted: false,
          isImportant: true,
          createdDateTime: DateTime.utc(2026, 11, 20),
          lastModifiedDateTime: DateTime.utc(2026, 11, 20),
          checklistItems: const [
            RemoteChecklistItem(
              id: 's1',
              displayName: 'Remote step 1',
              isChecked: false,
            ),
          ],
        ),
      };
      todoApi.tasksByList['work_remote'] = {
        't2': RemoteTodoTask(
          id: 't2',
          title: 'Prepare slides',
          isCompleted: false,
          isImportant: false,
          createdDateTime: DateTime.utc(2026, 11, 20),
          lastModifiedDateTime: DateTime.utc(2026, 11, 20),
        ),
      };

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            microsoftAuthClientProvider.overrideWithValue(authClient),
            microsoftTodoApiProvider.overrideWithValue(todoApi),
          ],
          child: const YataApp(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Sign in -> Device code dialog appears
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Sign in with Microsoft'), findsOneWidget);
      expect(find.text('ABCD-1234'), findsOneWidget);

      // Complete browser sign-in
      authClient.pollCompleter!.complete(
        MicrosoftSignInResult(
          profile: authClient.profile,
          tokens: MicrosoftAuthTokens(
            accessToken: 'access_1',
            refreshToken: 'refresh_1',
            expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
            clientId: 'test_client_id',
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Entered MainShellScreen with Microsoft account and synced cloud data
      final container = ProviderScope.containerOf(
        tester.element(find.byType(YataApp)),
      );
      final activeAccount = container.read(accountProvider).activeAccount!;
      expect(activeAccount, isA<MicrosoftAccount>());
      final msAccount = activeAccount as MicrosoftAccount;
      expect(msAccount.displayName, 'Alex Mercer');
      expect(msAccount.email, 'alex@outlook.com');
      expect(msAccount.lastSyncedAt, isNotNull);

      final todoState = container.read(todoProvider);
      expect(todoState.lists.any((l) => l.title == 'Work'), isTrue);
      expect(
        todoState.tasks.any((t) => t.title == 'Cloud default task'),
        isTrue,
      );
      expect(
        todoState.tasks
            .firstWhere((t) => t.title == 'Cloud default task')
            .steps
            .single
            .title,
        'Remote step 1',
      );
      expect(
        todoState.tasks.any((t) => t.title == 'Prepare slides'),
        isTrue,
      );

      // Create a local task in 'tasks' and sync -> pushed to remote API
      container.read(tasksViewPresenterProvider).addTask(
            title: 'Local pushed task',
            targetListId: 'tasks',
          );
      await tester.pump();
      await container.read(syncProvider.notifier).syncNow();
      await tester.pumpAndSettle();

      expect(
        todoApi.tasksByList['default_remote']!.values
            .any((t) => t.title == 'Local pushed task'),
        isTrue,
      );

      // Delete the synced task locally and sync -> deleted on remote API
      final pushedLocalTask = container
          .read(todoProvider)
          .tasks
          .firstWhere((t) => t.title == 'Local pushed task');
      expect(pushedLocalTask.remoteId, isNotNull);
      container
          .read(tasksActionPresenterProvider)
          .batchDeleteTasks({pushedLocalTask.id});
      await tester.pump();
      await container.read(syncProvider.notifier).syncNow();
      await tester.pumpAndSettle();

      expect(todoApi.deletedTaskIds, contains(pushedLocalTask.remoteId));
      expect(
        todoApi.tasksByList['default_remote']!.values
            .any((t) => t.title == 'Local pushed task'),
        isFalse,
      );
    },
  );

  test(
    'CloudSyncService refreshes expired tokens automatically and reuses existing Microsoft account on re-login',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final authClient = _FakeMicrosoftAuthClient(
        profile: const MicrosoftUserProfile(
          id: 'ms_user_002',
          displayName: 'Sam Rivera',
          email: 'sam@live.com',
        ),
        initialTokens: MicrosoftAuthTokens(
          accessToken: 'expired_token',
          refreshToken: 'refresh_token_abc',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          clientId: 'test_client_id',
        ),
      );
      final todoApi = _FakeMicrosoftTodoApi();
      todoApi.lists['default_remote'] = const RemoteTodoList(
        id: 'default_remote',
        displayName: 'Tasks',
        wellknownListName: 'defaultList',
      );

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          microsoftAuthClientProvider.overrideWithValue(authClient),
          microsoftTodoApiProvider.overrideWithValue(todoApi),
        ],
      );
      addTearDown(container.dispose);

      final signInResult = await authClient.pollDeviceCodeToken(
        await authClient.startDeviceCodeFlow(),
      );
      final firstAccount = await container
          .read(accountProvider.notifier)
          .signInMicrosoft(signInResult);

      // Sync should detect expired token and refresh it
      final ok = await container.read(syncProvider.notifier).syncNow();
      expect(ok, isTrue);
      expect(authClient.refreshCount, 1);
      expect(
        container.read(authTokenStorageProvider).load(firstAccount.id)?.accessToken,
        'refreshed_access_token_1',
      );

      // Re-signing in with same Microsoft user ID reuses the existing account
      final secondAccount = await container
          .read(accountProvider.notifier)
          .signInMicrosoft(signInResult);
      expect(secondAccount.id, firstAccount.id);
      expect(container.read(accountProvider).accounts.length, 1);
    },
  );
}
