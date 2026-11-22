import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/task_item.dart';
import '../auth/microsoft_auth_service.dart';

class RemoteTodoList {
  const RemoteTodoList({
    required this.id,
    required this.displayName,
    this.wellknownListName,
    this.isOwner = true,
    this.isShared = false,
  });

  final String id;
  final String displayName;
  final String? wellknownListName;
  final bool isOwner;
  final bool isShared;

  bool get isDefaultList => wellknownListName == 'defaultList';

  factory RemoteTodoList.fromJson(Map<String, dynamic> json) {
    return RemoteTodoList(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? '',
      wellknownListName: json['wellknownListName'] as String?,
      isOwner: json['isOwner'] as bool? ?? true,
      isShared: json['isShared'] as bool? ?? false,
    );
  }
}

class RemoteChecklistItem {
  const RemoteChecklistItem({
    required this.id,
    required this.displayName,
    required this.isChecked,
  });

  final String id;
  final String displayName;
  final bool isChecked;

  factory RemoteChecklistItem.fromJson(Map<String, dynamic> json) {
    return RemoteChecklistItem(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? '',
      isChecked: json['isChecked'] as bool? ?? false,
    );
  }
}

class RemoteTodoTask {
  const RemoteTodoTask({
    required this.id,
    required this.title,
    required this.isCompleted,
    required this.isImportant,
    required this.createdDateTime,
    required this.lastModifiedDateTime,
    this.completedDateTime,
    this.dueDate,
    this.reminderAt,
    this.recurrence = RecurrenceType.none,
    this.note = '',
    this.checklistItems = const [],
  });

  final String id;
  final String title;
  final bool isCompleted;
  final bool isImportant;
  final DateTime createdDateTime;
  final DateTime lastModifiedDateTime;
  final DateTime? completedDateTime;
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final RecurrenceType recurrence;
  final String note;
  final List<RemoteChecklistItem> checklistItems;

  factory RemoteTodoTask.fromJson(Map<String, dynamic> json) {
    final status = json['status'] as String? ?? 'notStarted';
    final importance = json['importance'] as String? ?? 'normal';
    final bodyMap = json['body'] as Map<String, dynamic>?;
    final rawChecklist = json['checklistItems'] as List<dynamic>? ?? const [];

    return RemoteTodoTask(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      isCompleted: status == 'completed',
      isImportant: importance == 'high',
      createdDateTime: _parseIso(json['createdDateTime'] as String?) ??
          DateTime.now().toUtc(),
      lastModifiedDateTime:
          _parseIso(json['lastModifiedDateTime'] as String?) ??
              DateTime.now().toUtc(),
      completedDateTime: _parseDateTimeTimeZone(
        json['completedDateTime'] as Map<String, dynamic>?,
      ),
      dueDate: _parseDateTimeTimeZone(
        json['dueDateTime'] as Map<String, dynamic>?,
      ),
      reminderAt: (json['isReminderOn'] as bool? ?? false)
          ? _parseDateTimeTimeZone(
              json['reminderDateTime'] as Map<String, dynamic>?,
            )
          : null,
      recurrence: _parseRecurrence(
        json['recurrence'] as Map<String, dynamic>?,
      ),
      note: bodyMap?['content'] as String? ?? '',
      checklistItems: rawChecklist
          .map((e) => RemoteChecklistItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static DateTime? _parseIso(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  static DateTime? _parseDateTimeTimeZone(Map<String, dynamic>? map) {
    if (map == null) return null;
    final raw = map['dateTime'] as String?;
    if (raw == null || raw.isEmpty) return null;
    final tz = (map['timeZone'] as String? ?? '').toUpperCase();
    final normalized =
        (tz == 'UTC' && !raw.endsWith('Z')) ? '${raw}Z' : raw;
    return DateTime.tryParse(normalized)?.toLocal();
  }

  static RecurrenceType _parseRecurrence(Map<String, dynamic>? map) {
    if (map == null) return RecurrenceType.none;
    final pattern = map['pattern'] as Map<String, dynamic>?;
    if (pattern == null) return RecurrenceType.none;
    final type = pattern['type'] as String? ?? '';
    switch (type) {
      case 'daily':
        return RecurrenceType.daily;
      case 'weekly':
        final days = (pattern['daysOfWeek'] as List<dynamic>? ?? const [])
            .map((e) => e.toString().toLowerCase())
            .toSet();
        const weekdays = {
          'monday',
          'tuesday',
          'wednesday',
          'thursday',
          'friday',
        };
        if (days.length == 5 && days.containsAll(weekdays)) {
          return RecurrenceType.weekdays;
        }
        return RecurrenceType.weekly;
      case 'absoluteMonthly':
      case 'relativeMonthly':
        return RecurrenceType.monthly;
      case 'absoluteYearly':
      case 'relativeYearly':
        return RecurrenceType.yearly;
      default:
        return RecurrenceType.none;
    }
  }
}

abstract class MicrosoftTodoApi {
  Future<List<RemoteTodoList>> fetchLists(String accessToken);
  Future<RemoteTodoList> createList(String accessToken, String displayName);
  Future<RemoteTodoList> renameList(
    String accessToken,
    String listId,
    String displayName,
  );
  Future<void> deleteList(String accessToken, String listId);

  Future<List<RemoteTodoTask>> fetchTasks(String accessToken, String listId);
  Future<RemoteTodoTask> createTask(
    String accessToken,
    String listId,
    TaskItem task,
  );
  Future<RemoteTodoTask> updateTask(
    String accessToken,
    String listId,
    String taskId,
    TaskItem task,
  );
  Future<void> deleteTask(
    String accessToken,
    String listId,
    String taskId,
  );

  Future<RemoteChecklistItem> createChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    TaskStep step,
  );
  Future<RemoteChecklistItem> updateChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    TaskStep step,
  );
  Future<void> deleteChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    String itemId,
  );
}

class HttpMicrosoftTodoApi implements MicrosoftTodoApi {
  HttpMicrosoftTodoApi({http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final http.Client _http;

  static const _baseUrl = '${MicrosoftAuthConfig.graphBaseUrl}/me/todo';

  Map<String, String> _headers(String accessToken, {bool jsonBody = false}) {
    return {
      'Authorization': 'Bearer $accessToken',
      if (jsonBody) 'Content-Type': 'application/json',
    };
  }

  @override
  Future<List<RemoteTodoList>> fetchLists(String accessToken) async {
    final results = <RemoteTodoList>[];
    String? nextUrl = '$_baseUrl/lists';

    while (nextUrl != null) {
      final response = await _http.get(
        Uri.parse(nextUrl),
        headers: _headers(accessToken),
      );
      final body = _parseResponse(response, 'fetchLists');
      final items = body['value'] as List<dynamic>? ?? const [];
      for (final item in items) {
        results.add(RemoteTodoList.fromJson(item as Map<String, dynamic>));
      }
      nextUrl = body['@odata.nextLink'] as String?;
    }
    return results;
  }

  @override
  Future<RemoteTodoList> createList(
    String accessToken,
    String displayName,
  ) async {
    final response = await _http.post(
      Uri.parse('$_baseUrl/lists'),
      headers: _headers(accessToken, jsonBody: true),
      body: jsonEncode({'displayName': displayName}),
    );
    final body = _parseResponse(response, 'createList');
    return RemoteTodoList.fromJson(body);
  }

  @override
  Future<RemoteTodoList> renameList(
    String accessToken,
    String listId,
    String displayName,
  ) async {
    final response = await _http.patch(
      Uri.parse('$_baseUrl/lists/$listId'),
      headers: _headers(accessToken, jsonBody: true),
      body: jsonEncode({'displayName': displayName}),
    );
    final body = _parseResponse(response, 'renameList');
    return RemoteTodoList.fromJson(body);
  }

  @override
  Future<void> deleteList(String accessToken, String listId) async {
    final response = await _http.delete(
      Uri.parse('$_baseUrl/lists/$listId'),
      headers: _headers(accessToken),
    );
    if (response.statusCode == 404) return;
    _ensureSuccess(response, 'deleteList');
  }

  @override
  Future<List<RemoteTodoTask>> fetchTasks(
    String accessToken,
    String listId,
  ) async {
    final results = <RemoteTodoTask>[];
    String? nextUrl = '$_baseUrl/lists/$listId/tasks?\$expand=checklistItems';

    while (nextUrl != null) {
      final response = await _http.get(
        Uri.parse(nextUrl),
        headers: _headers(accessToken),
      );
      final body = _parseResponse(response, 'fetchTasks');
      final items = body['value'] as List<dynamic>? ?? const [];
      for (final item in items) {
        results.add(RemoteTodoTask.fromJson(item as Map<String, dynamic>));
      }
      nextUrl = body['@odata.nextLink'] as String?;
    }
    return results;
  }

  @override
  Future<RemoteTodoTask> createTask(
    String accessToken,
    String listId,
    TaskItem task,
  ) async {
    final response = await _http.post(
      Uri.parse('$_baseUrl/lists/$listId/tasks'),
      headers: _headers(accessToken, jsonBody: true),
      body: jsonEncode(_taskToGraphPayload(task)),
    );
    final body = _parseResponse(response, 'createTask');
    return RemoteTodoTask.fromJson(body);
  }

  @override
  Future<RemoteTodoTask> updateTask(
    String accessToken,
    String listId,
    String taskId,
    TaskItem task,
  ) async {
    final response = await _http.patch(
      Uri.parse('$_baseUrl/lists/$listId/tasks/$taskId'),
      headers: _headers(accessToken, jsonBody: true),
      body: jsonEncode(_taskToGraphPayload(task)),
    );
    final body = _parseResponse(response, 'updateTask');
    return RemoteTodoTask.fromJson(body);
  }

  @override
  Future<void> deleteTask(
    String accessToken,
    String listId,
    String taskId,
  ) async {
    final response = await _http.delete(
      Uri.parse('$_baseUrl/lists/$listId/tasks/$taskId'),
      headers: _headers(accessToken),
    );
    if (response.statusCode == 404) return;
    _ensureSuccess(response, 'deleteTask');
  }

  @override
  Future<RemoteChecklistItem> createChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    TaskStep step,
  ) async {
    final response = await _http.post(
      Uri.parse('$_baseUrl/lists/$listId/tasks/$taskId/checklistItems'),
      headers: _headers(accessToken, jsonBody: true),
      body: jsonEncode({
        'displayName': step.title,
        'isChecked': step.isCompleted,
      }),
    );
    final body = _parseResponse(response, 'createChecklistItem');
    return RemoteChecklistItem.fromJson(body);
  }

  @override
  Future<RemoteChecklistItem> updateChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    TaskStep step,
  ) async {
    final response = await _http.patch(
      Uri.parse(
        '$_baseUrl/lists/$listId/tasks/$taskId/checklistItems/${step.remoteId}',
      ),
      headers: _headers(accessToken, jsonBody: true),
      body: jsonEncode({
        'displayName': step.title,
        'isChecked': step.isCompleted,
      }),
    );
    final body = _parseResponse(response, 'updateChecklistItem');
    return RemoteChecklistItem.fromJson(body);
  }

  @override
  Future<void> deleteChecklistItem(
    String accessToken,
    String listId,
    String taskId,
    String itemId,
  ) async {
    final response = await _http.delete(
      Uri.parse('$_baseUrl/lists/$listId/tasks/$taskId/checklistItems/$itemId'),
      headers: _headers(accessToken),
    );
    if (response.statusCode == 404) return;
    _ensureSuccess(response, 'deleteChecklistItem');
  }

  Map<String, dynamic> _taskToGraphPayload(TaskItem task) {
    final payload = <String, dynamic>{
      'title': task.title,
      'status': task.isCompleted ? 'completed' : 'notStarted',
      'importance': task.isImportant ? 'high' : 'normal',
      'body': {
        'content': task.note,
        'contentType': 'text',
      },
      'isReminderOn': task.reminderAt != null,
    };

    if (task.dueDate != null) {
      final d = task.dueDate!;
      payload['dueDateTime'] = {
        'dateTime': DateTime.utc(d.year, d.month, d.day).toIso8601String(),
        'timeZone': 'UTC',
      };
    } else {
      payload['dueDateTime'] = null;
    }

    if (task.reminderAt != null) {
      payload['reminderDateTime'] = {
        'dateTime': task.reminderAt!.toUtc().toIso8601String(),
        'timeZone': 'UTC',
      };
    } else {
      payload['reminderDateTime'] = null;
    }

    final recurrencePayload = _recurrenceToGraph(task);
    payload['recurrence'] = recurrencePayload;

    return payload;
  }

  Map<String, dynamic>? _recurrenceToGraph(TaskItem task) {
    if (task.recurrence == RecurrenceType.none) return null;
    final start = (task.dueDate ?? task.createdAt).toUtc();
    final startDate =
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

    final Map<String, dynamic> pattern = switch (task.recurrence) {
      RecurrenceType.none => const {},
      RecurrenceType.daily => {'type': 'daily', 'interval': 1},
      RecurrenceType.weekdays => {
          'type': 'weekly',
          'interval': 1,
          'daysOfWeek': [
            'monday',
            'tuesday',
            'wednesday',
            'thursday',
            'friday',
          ],
        },
      RecurrenceType.weekly => {
          'type': 'weekly',
          'interval': 1,
          'daysOfWeek': [_weekdayName(start.weekday)],
        },
      RecurrenceType.monthly => {
          'type': 'absoluteMonthly',
          'interval': 1,
          'dayOfMonth': start.day,
        },
      RecurrenceType.yearly => {
          'type': 'absoluteYearly',
          'interval': 1,
          'dayOfMonth': start.day,
          'month': start.month,
        },
    };

    return {
      'pattern': pattern,
      'range': {
        'type': 'noEnd',
        'startDate': startDate,
      },
    };
  }

  String _weekdayName(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'monday',
      DateTime.tuesday => 'tuesday',
      DateTime.wednesday => 'wednesday',
      DateTime.thursday => 'thursday',
      DateTime.friday => 'friday',
      DateTime.saturday => 'saturday',
      DateTime.sunday => 'sunday',
      _ => 'monday',
    };
  }

  Map<String, dynamic> _parseResponse(http.Response response, String op) {
    _ensureSuccess(response, op);
    if (response.body.trim().isEmpty) return const {};
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  void _ensureSuccess(http.Response response, String op) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    String message = 'Microsoft To Do $op failed (${response.statusCode})';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'] as Map<String, dynamic>?;
        final msg = error?['message'] as String?;
        if (msg != null && msg.isNotEmpty) {
          message = msg;
        }
      }
    } catch (_) {}
    throw MicrosoftAuthException(
      message,
      requiresRelogin: response.statusCode == 401,
    );
  }
}
