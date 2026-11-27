import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/core/result/app_result.dart';
import 'package:yata/data/todo_provider.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/sync/microsoft/microsoft_todo_api.dart';
import 'package:yata/sync/sync_provider.dart';
import 'package:yata/tasksview/tasks_view_presenter.dart';

import '../helpers/microsoft_sync_fakes.dart';

/// A local edit must cost one PATCH plus at most one task delta for the affected
/// folder — never a settings/group/folder pull plus a pull for every list.
///
///   flutter test test/perf/sync_trigger_cost_test.dart --reporter expanded
const _listCount = 12;
const _taskCountPerList = 20;

DateTime get _now => DateTime.utc(2026, 11, 22, 12);

List<TodoList> _seedLists() => [
  for (var i = 0; i < _listCount; i++)
    TodoList(
      id: 'list_$i',
      title: 'List $i',
      remoteId: 'rf-$i',
      orderDateTime: _now.subtract(Duration(minutes: i)),
    ),
];

List<TaskItem> _seedTasks() => [
  for (var i = 0; i < _listCount; i++)
    for (var j = 0; j < _taskCountPerList; j++)
      TaskItem(
        id: 'task_${i}_$j',
        listId: 'list_$i',
        title: 'Task $i-$j',
        createdAt: _now.subtract(Duration(minutes: i * 100 + j)),
        remoteId: 'rt_${i}_$j',
        orderDateTime: _now.subtract(Duration(minutes: i * 100 + j)),
        changeKey: 'ck_${i}_$j',
      ),
];

FakeSubstrateApi _fakeApi() {
  final api = FakeSubstrateApi();
  api.onFetchGroupsDelta = (dl) =>
      const DeltaPageResult(items: [], deltaLink: 'dl-groups');
  api.onFetchFoldersDelta = (dl) => DeltaPageResult(
    items: [
      for (var i = 0; i < _listCount; i++)
        RemoteTodoFolder(
          id: 'rf-$i',
          name: 'List $i',
          orderDateTime: _now.subtract(Duration(minutes: i)),
        ),
    ],
    deltaLink: 'dl-folders',
  );
  api.onFetchTasksDelta = (folderRemoteId, dl) =>
      DeltaPageResult(items: const [], deltaLink: 'dl-tasks-$folderRemoteId');
  api.onPatchTask = (remoteId, patch, changeKey) async {
    final parts = remoteId.split('_');
    return RemoteTodoTask(
      id: remoteId,
      subject: 'Task ${parts[1]}-${parts[2]}',
      status: patch['Status'] as String? ?? 'NotStarted',
      parentFolderId: 'rf-${parts[1]}',
      changeKey: 'ck-after-$remoteId',
      orderDateTime: _now,
    );
  };
  return api;
}

Future<SyncTestHarness> _harness(String accountId, {FakeSubstrateApi? api}) {
  return createSyncTestHarness(
    accountId: accountId,
    api: api ?? _fakeApi(),
    lists: _seedLists(),
    tasks: _seedTasks(),
    groupsDeltaLink: 'dl-groups',
    foldersDeltaLink: 'dl-folders',
    taskDeltaLinks: {
      for (var i = 0; i < _listCount; i++) 'rf-$i': 'dl-tasks-rf-$i',
    },
  );
}

/// Waits until the sync pass triggered by a local edit has settled.
Future<void> _waitForSync(SyncTestHarness h) async {
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!h.container.read(syncProvider).isSyncing && i > 40) return;
  }
}

/// Fake with a fixed per-request round-trip cost.
class _LatencyApi extends FakeSubstrateApi {
  _LatencyApi(this.latency);

  final Duration latency;

  Future<T> _rtt<T>(Future<T> Function() inner) async {
    await Future<void>.delayed(latency);
    return inner();
  }

  @override
  AsyncAppResult<Map<String, String>> getSettings(
    SubstrateRequestContext ctx,
  ) => _rtt(() => super.getSettings(ctx));

  @override
  AsyncAppResult<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) => _rtt(() => super.fetchFolderGroupsDelta(ctx, deltaLink: deltaLink));

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) => _rtt(() => super.fetchFoldersDelta(ctx, deltaLink: deltaLink));

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  }) => _rtt(
    () => super.fetchTasksDelta(
      ctx,
      folderRemoteId: folderRemoteId,
      deltaLink: deltaLink,
    ),
  );

  @override
  AsyncAppResult<RemoteTodoTask> patchTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  }) => _rtt(
    () => super.patchTask(ctx, taskRemoteId, patch, changeKey: changeKey),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'one completion toggle pushes once and pulls only that folder',
    () async {
      final api = _fakeApi();
      final h = await _harness('acct_trigger_cost', api: api);
      await h.container.read(syncProvider.notifier).syncNow(reason: 'warmup');
      await pumpEventQueue();
      api.callLog.clear();

      h.container
          .read(tasksViewPresenterProvider)
          .toggleTaskCompleted('task_0_0');
      await _waitForSync(h);

      expect(api.callLog, [
        'PATCH tasks/rt_0_0(ifMatch=ck_0_0)',
        'GET tasks(rf-0,dl-tasks-rf-0)',
      ]);
      // The follow-up ledger is consumed by the pull.
      expect(h.repository.loadPendingTaskFolderPulls(), isEmpty);
      // ignore: avoid_print
      print('=== one completion toggle === ${api.callLog}');
    },
  );

  test('a reorder-only edit pushes once and pulls nothing', () async {
    final api = _fakeApi();
    final h = await _harness('acct_trigger_reorder', api: api);
    await h.container.read(syncProvider.notifier).syncNow(reason: 'warmup');
    await pumpEventQueue();
    api.callLog.clear();

    final presenter = h.container.read(tasksViewPresenterProvider);
    final state = h.container.read(todoProvider);
    final visible = state
        .tasksForList(state.lists.firstWhere((l) => l.id == 'list_0'))
        .toList();
    expect(visible.length, greaterThan(2));
    presenter.reorderActiveTasks(visible, 0, 2);
    await _waitForSync(h);

    expect(api.callLog, ['PATCH tasks/${visible[0].remoteId}(ifMatch=null)']);
    // ignore: avoid_print
    print('=== reorder === ${api.callLog}');
  });

  test('three quick toggles coalesce into a single pass', () async {
    final api = _fakeApi();
    final h = await _harness('acct_trigger_burst', api: api);
    await h.container.read(syncProvider.notifier).syncNow(reason: 'warmup');
    await pumpEventQueue();
    api.callLog.clear();

    final presenter = h.container.read(tasksViewPresenterProvider);
    presenter.toggleTaskCompleted('task_0_0');
    presenter.toggleTaskCompleted('task_0_1');
    presenter.toggleTaskCompleted('task_0_2');
    await _waitForSync(h);

    expect(
      api.callLog.where((c) => c.startsWith('PATCH tasks/')).length,
      3,
      reason: api.callLog.join(', '),
    );
    expect(api.callLog.where((c) => c.startsWith('GET tasks(')).toList(), [
      'GET tasks(rf-0,dl-tasks-rf-0)',
    ]);
    expect(api.callLog.length, 4, reason: api.callLog.join(', '));
  });

  test('wall clock for one local toggle with 120ms RTT', () async {
    final api = _LatencyApi(const Duration(milliseconds: 120));
    final base = _fakeApi();
    api.onFetchGroupsDelta = base.onFetchGroupsDelta;
    api.onFetchFoldersDelta = base.onFetchFoldersDelta;
    api.onFetchTasksDelta = base.onFetchTasksDelta;
    api.onPatchTask = base.onPatchTask;

    final h = await _harness('acct_trigger_latency', api: api);
    await h.container.read(syncProvider.notifier).syncNow(reason: 'warmup');
    await pumpEventQueue();
    api.callLog.clear();

    final sw = Stopwatch()..start();
    h.container
        .read(tasksViewPresenterProvider)
        .toggleTaskCompleted('task_0_0');
    while (sw.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!h.container.read(syncProvider).isSyncing &&
          api.callLog.length >= 2) {
        break;
      }
    }
    sw.stop();

    expect(api.callLog.length, 2, reason: api.callLog.join(', '));
    // ignore: avoid_print
    print('''
=== wall clock, 1 completion toggle, $_listCount lists, RTT=120ms ===
sync finished after : ${sw.elapsedMilliseconds} ms
API calls           : ${api.callLog.length}
''');
    expect(sw.elapsedMilliseconds, lessThan(2000));
  });
}
