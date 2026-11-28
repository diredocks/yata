import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/data/state/todo_provider.dart';
import 'package:yata/data/db/todo_repository.dart';
import 'package:yata/models/account.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/homewidget/home_widget_sync.dart';
import 'package:yata/data/preferences.dart';
import 'package:yata/data/db/todo_database.dart';

class CommittedSnapshotRecord {
  const CommittedSnapshotRecord({
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

class FakeHomeWidgetTransport implements HomeWidgetTransport {
  final Map<String, Object?> storage = {};
  final List<CommittedSnapshotRecord> commits = [];
  final StreamController<Uri?> clickedController =
      StreamController<Uri?>.broadcast();
  final StreamController<String> syncRequestsController =
      StreamController<String>.broadcast();
  int updateCalls = 0;
  Uri? initialLaunchUri;
  Future<void> Function()? onSaveSnapshotHook;
  Object? getDataError;
  Object? initialLaunchUriError;

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
  Future<T?> getData<T>(String key) async {
    if (getDataError != null) throw getDataError!;
    return storage[key] as T?;
  }

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
        CommittedSnapshotRecord(
          snapshotJson: snapshotJson,
          ackedOpId: storage[kWidgetAckedOpIdKey] as int? ?? 0,
          isRefreshing: storage[kWidgetIsRefreshingKey] as bool?,
        ),
      );
    }
  }

  @override
  Future<Uri?> initiallyLaunchedFromHomeWidget() async {
    if (initialLaunchUriError != null) throw initialLaunchUriError!;
    return initialLaunchUri;
  }

  @override
  Stream<Uri?> get widgetClicked => clickedController.stream;

  @override
  Stream<String> get widgetSyncRequests => syncRequestsController.stream;

  Future<void> closeStreams() async {
    await clickedController.close();
    await syncRequestsController.close();
  }
}

class WidgetTestHarness {
  const WidgetTestHarness({
    required this.container,
    required this.transport,
    required this.prefs,
    required this.db,
  });

  final ProviderContainer container;
  final FakeHomeWidgetTransport transport;
  final SharedPreferences prefs;
  final TodoDatabase db;
}

Future<WidgetTestHarness> createWidgetTestHarness({
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
  final transport = FakeHomeWidgetTransport();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      todoDatabaseProvider.overrideWithValue(db),
      homeWidgetServiceProvider.overrideWithValue(HomeWidgetService(transport)),
    ],
  );
  addTearDown(() async {
    await container.read(todoRepositoryProvider).flushPendingWrites();
    container.dispose();
    await db.close();
    await transport.closeStreams();
  });
  return WidgetTestHarness(
    container: container,
    transport: transport,
    prefs: prefs,
    db: db,
  );
}
