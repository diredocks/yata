import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yata/data/todo_state.dart';
import 'package:yata/models/default_lists.dart';
import 'package:yata/models/task_item.dart';
import 'package:yata/models/todo_list.dart';
import 'package:yata/widget/home_widget_service.dart';

class _FakeHomeWidgetTransport implements HomeWidgetTransport {
  final Map<String, Object?> saved = {};
  final List<String?> updatedProviders = [];

  @override
  Future<Uri?> initiallyLaunchedFromHomeWidget() async => null;

  @override
  Future<void> saveWidgetData(String id, Object? data) async {
    saved[id] = data;
  }

  @override
  Future<void> updateWidget({String? qualifiedAndroidName}) async {
    updatedProviders.add(qualifiedAndroidName);
  }

  @override
  Stream<Uri?> get widgetClicked => const Stream.empty();
}

void main() {
  group('HomeWidgetAction.fromUri', () {
    test('parses quickAdd, openTask, toggleComplete, and toggleImportant', () {
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

      final complete = HomeWidgetAction.fromUri(
        Uri.parse('yata://widget/toggle_complete?taskId=t2&completed=true'),
      );
      expect(complete?.type, HomeWidgetActionType.toggleComplete);
      expect(complete?.taskId, 't2');
      expect(complete?.flagValue, isTrue);

      final important = HomeWidgetAction.fromUri(
        Uri.parse('yata://widget/toggle_important?taskId=t3&important=false'),
      );
      expect(important?.type, HomeWidgetActionType.toggleImportant);
      expect(important?.taskId, 't3');
      expect(important?.flagValue, isFalse);
    });

    test('returns null for unrelated URIs', () {
      expect(HomeWidgetAction.fromUri(null), isNull);
      expect(
        HomeWidgetAction.fromUri(Uri.parse('https://example.com')),
        isNull,
      );
    });
  });

  group('HomeWidgetService.syncWithState', () {
    test('serializes lists, tasks, and per-list task order', () async {
      final transport = _FakeHomeWidgetTransport();
      final service = HomeWidgetService(transport);
      final now = DateTime(2026, 11, 23, 9, 0);
      final customList = const TodoList(
        id: 'list_work',
        title: 'Work',
        emoji: '💼',
      );
      final lists = [...defaultSmartLists(), customList];
      final tasks = [
        TaskItem(
          id: 't1',
          listId: 'list_work',
          title: 'Finish report',
          createdAt: now,
          isInMyDay: true,
          isImportant: true,
          dueDate: DateTime.now(),
        ),
        TaskItem(
          id: 't2',
          listId: 'tasks',
          title: 'Buy milk',
          createdAt: now,
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
        accountName: 'leo@example.com',
        strings: const HomeWidgetStrings(myDay: '我的一天', today: '今天'),
      );

      expect(transport.updatedProviders, [kAndroidWidgetProviderName]);
      expect(transport.saved['widget_account_name'], 'leo@example.com');
      expect(transport.saved['widget_my_day_label'], '我的一天');

      final listsJson = jsonDecode(
        transport.saved['widget_lists_json']! as String,
      ) as List<dynamic>;
      final workEntry = listsJson.firstWhere((e) => e['id'] == 'list_work');
      expect(workEntry['title'], 'Work');
      expect(workEntry['emoji'], '💼');
      expect(workEntry['activeCount'], 1);
      expect(workEntry['accentColorLight'], isA<int>());
      expect(workEntry['accentColorDark'], isA<int>());

      final myDayEntry = listsJson.firstWhere((e) => e['id'] == 'my_day');
      expect(myDayEntry['title'], '我的一天');

      final listTaskIds = jsonDecode(
        transport.saved['widget_list_task_ids_json']! as String,
      ) as Map<String, dynamic>;
      expect(listTaskIds['my_day'], ['t1']);
      expect(listTaskIds['list_work'], ['t1']);
      expect(listTaskIds['completed'], ['t2']);

      final tasksJson = jsonDecode(
        transport.saved['widget_tasks_json']! as String,
      ) as List<dynamic>;
      final t1Json = tasksJson.firstWhere((e) => e['id'] == 't1');
      expect(t1Json['dueLabel'], '今天');
      expect(t1Json['isImportant'], isTrue);
      expect(t1Json['listTitle'], 'Work');
    });
  });
}
