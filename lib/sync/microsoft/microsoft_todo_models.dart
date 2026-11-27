import 'dart:convert';

import '../../auth/microsoft_auth_service.dart';
import '../../models/task_item.dart';
import '../../models/todo_list.dart';
import 'todo_wire_codecs.dart';

/// Per-request routing & auth context for Substrate To Do v1 API calls.
class SubstrateRequestContext {
  SubstrateRequestContext({
    required String baseUrl,
    required this.accessToken,
    required String cid,
  }) : baseUrl = _normalizeBaseUrl(baseUrl),
       cid = MsaAuthConfig.normalizeCid(cid);

  /// Discovered Substrate To Do `/api/v1/` base URL (guaranteed trailing `/`).
  final String baseUrl;
  final String accessToken;

  /// Normalized personal MSA CID (without `CID:` prefix).
  final String cid;

  String get anchorMailbox => MsaAuthConfig.anchorMailboxForCid(cid);

  Uri endpointUri(String relativePath) {
    final cleaned = relativePath.startsWith('/')
        ? relativePath.substring(1)
        : relativePath;
    return Uri.parse('$baseUrl$cleaned');
  }

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return MsaAuthConfig.defaultTodoApiBaseUrl;
    }
    return trimmed.endsWith('/') ? trimmed : '$trimmed/';
  }
}

class RemoteFolderGroup {
  const RemoteFolderGroup({
    required this.id,
    required this.name,
    this.orderDateTime,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final DateTime? orderDateTime;
  final bool isDeleted;

  factory RemoteFolderGroup.fromJson(Map<String, dynamic> json) {
    final reason = (json['Reason'] as String?)?.toLowerCase();
    return RemoteFolderGroup(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      orderDateTime: parseSubstrateTimestamp(json['OrderDateTime'] as String?),
      isDeleted: reason == 'deleted',
    );
  }
}

class RemoteTodoFolder {
  const RemoteTodoFolder({
    required this.id,
    required this.name,
    this.isDefaultFolder = false,
    this.folderType,
    this.parentFolderGroupId,
    this.themeColor,
    this.themeBackground,
    this.showCompletedTasks = true,
    this.sortOption = TaskSortOption.defaultOrder,
    this.sortAscending = false,
    this.orderDateTime,
    this.isDeleted = false,
  });

  final String id;
  final String name;
  final bool isDefaultFolder;
  final String? folderType;
  final String? parentFolderGroupId;
  final String? themeColor;
  final String? themeBackground;
  final bool showCompletedTasks;
  final TaskSortOption sortOption;
  final bool sortAscending;
  final DateTime? orderDateTime;
  final bool isDeleted;

  bool get isIgnoredSpecialFolder =>
      folderType == 'com.microsoft.outlook.email.flagged' ||
      folderType == 'com.microsoft.planner';

  factory RemoteTodoFolder.fromJson(Map<String, dynamic> json) {
    final reason = (json['Reason'] as String?)?.toLowerCase();
    final sortOption = decodeSortType(json['SortType']);
    final sortAscending = parseWireBool(
      json['SortAscending'],
      fallback: sortOption.defaultAscending,
    );
    return RemoteTodoFolder(
      id: json['Id'] as String? ?? '',
      name: json['Name'] as String? ?? '',
      isDefaultFolder: json['IsDefaultFolder'] as bool? ?? false,
      folderType: json['FolderType'] as String?,
      parentFolderGroupId: json['ParentFolderGroupId'] as String?,
      themeColor: json['ThemeColor'] as String?,
      themeBackground: json['ThemeBackground'] as String?,
      showCompletedTasks: json['ShowCompletedTasks'] as bool? ?? true,
      sortOption: sortOption,
      sortAscending: sortAscending,
      orderDateTime: parseSubstrateTimestamp(json['OrderDateTime'] as String?),
      isDeleted: reason == 'deleted',
    );
  }
}

class RemoteTaskStep {
  const RemoteTaskStep({
    required this.id,
    required this.subject,
    this.isCompleted = false,
    this.orderDateTime,
  });

  final String id;
  final String subject;
  final bool isCompleted;
  final DateTime? orderDateTime;

  factory RemoteTaskStep.fromJson(Map<String, dynamic> json) {
    return RemoteTaskStep(
      id: json['Id'] as String? ?? '',
      subject: json['Subject'] as String? ?? '',
      isCompleted: json['IsCompleted'] as bool? ?? false,
      orderDateTime: parseSubstrateTimestamp(json['OrderDateTime'] as String?),
    );
  }
}

class RemoteLinkedEntity {
  const RemoteLinkedEntity({
    required this.id,
    required this.displayName,
    this.entityType = 'file',
    this.entitySubType,
    this.webLink,
    this.applicationName,
    this.size = 0,
    this.contentType,
    this.lastModifiedDateTime,
  });

  final String id;
  final String displayName;
  final String entityType;
  final String? entitySubType;
  final String? webLink;
  final String? applicationName;
  final int size;
  final String? contentType;
  final DateTime? lastModifiedDateTime;

  factory RemoteLinkedEntity.fromJson(Map<String, dynamic> json) {
    final rawPreview = json['Preview'];
    final previewMap =
        asJsonMap(rawPreview) ??
        (rawPreview is String ? tryDecodeJsonMap(rawPreview) : null);

    return RemoteLinkedEntity(
      id: json['Id'] as String? ?? '',
      displayName: json['DisplayName'] as String? ?? '',
      entityType: json['EntityType'] as String? ?? 'file',
      entitySubType: json['EntitySubType'] as String?,
      webLink: json['WebLink'] as String?,
      applicationName: json['ApplicationName'] as String?,
      size: (previewMap?['Size'] as num?)?.toInt() ?? 0,
      contentType: previewMap?['ContentType'] as String?,
      lastModifiedDateTime: parseSubstrateTimestamp(
        previewMap?['LastModifiedDateTime'] as String?,
      ),
    );
  }
}

class RemoteFileUpload {
  const RemoteFileUpload({
    required this.id,
    this.size = 0,
    this.contentType,
    this.lastModifiedDateTime,
  });

  final String id;
  final int size;
  final String? contentType;
  final DateTime? lastModifiedDateTime;

  factory RemoteFileUpload.fromJson(Map<String, dynamic> json) {
    return RemoteFileUpload(
      id: json['Id'] as String? ?? '',
      size: (json['Size'] as num?)?.toInt() ?? 0,
      contentType: json['ContentType'] as String?,
      lastModifiedDateTime: parseSubstrateTimestamp(
        json['LastModifiedDateTime'] as String?,
      ),
    );
  }
}

enum RemoteTaskStatus {
  notStarted,
  inProgress,
  waitingOnOthers,
  completed,
  deferred,
  unknown;

  static RemoteTaskStatus parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'notstarted' => RemoteTaskStatus.notStarted,
        'inprogress' => RemoteTaskStatus.inProgress,
        'waitingonothers' => RemoteTaskStatus.waitingOnOthers,
        'completed' => RemoteTaskStatus.completed,
        'deferred' => RemoteTaskStatus.deferred,
        _ => RemoteTaskStatus.unknown,
      };
}

enum RemoteTaskImportance {
  low,
  normal,
  high,
  unknown;

  static RemoteTaskImportance parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'low' => RemoteTaskImportance.low,
        'normal' => RemoteTaskImportance.normal,
        'high' => RemoteTaskImportance.high,
        _ => RemoteTaskImportance.unknown,
      };
}

class RemoteTodoTask {
  const RemoteTodoTask({
    required this.id,
    required this.subject,
    this.changeKey,
    this.parentFolderId,
    this.bodyContent = '',
    this.bodyContentType,
    this.bodyLastModifiedTime,
    this.orderDateTime,
    this.dueDate,
    this.reminderDateTime,
    this.isReminderOn = false,
    this.completedDateTime,
    this.status = 'NotStarted',
    this.importance = 'Normal',
    this.isIgnored = false,
    this.committedDay,
    this.committedOrder,
    this.postponedDay,
    this.createdDateTime,
    this.lastModifiedDateTime,
    this.recurrence = RecurrenceType.none,
    this.rawRecurrence,
    this.uncommittedDue = false,
    this.subtasks = const [],
    this.linkedEntities = const [],
    this.isDeleted = false,
  });

  final String id;
  final String? changeKey;
  final String? parentFolderId;
  final String subject;
  final String bodyContent;
  final String? bodyContentType;
  final DateTime? bodyLastModifiedTime;
  final DateTime? orderDateTime;
  final DateTime? dueDate;
  final DateTime? reminderDateTime;
  final bool isReminderOn;
  final DateTime? completedDateTime;
  final String status;
  final String importance;
  final bool isIgnored;
  final DateTime? committedDay;
  final DateTime? committedOrder;
  final DateTime? postponedDay;
  final DateTime? createdDateTime;
  final DateTime? lastModifiedDateTime;
  final RecurrenceType recurrence;
  final Map<String, dynamic>? rawRecurrence;
  final bool uncommittedDue;
  final List<RemoteTaskStep> subtasks;
  final List<RemoteLinkedEntity> linkedEntities;
  final bool isDeleted;

  RemoteTaskStatus get parsedStatus => RemoteTaskStatus.parse(status);

  RemoteTaskImportance get parsedImportance =>
      RemoteTaskImportance.parse(importance);

  bool get isCompleted => parsedStatus == RemoteTaskStatus.completed;

  bool get isImportant => parsedImportance == RemoteTaskImportance.high;

  bool get hasRecurrence =>
      recurrence != RecurrenceType.none ||
      (rawRecurrence != null && rawRecurrence!.isNotEmpty);

  String get plainTextNote =>
      stripHtmlToPlainText(bodyContent, contentType: bodyContentType);

  factory RemoteTodoTask.fromJson(Map<String, dynamic> json) {
    final reason = (json['Reason'] as String?)?.toLowerCase();
    final bodyMap = asJsonMap(json['Body']);
    final bodyContent = (bodyMap?['Content'] as String?) ?? '';
    final bodyContentType = bodyMap?['ContentType'] as String?;
    final recurrenceMap = asJsonMap(json['Recurrence']);
    final subtasksRaw = json['Subtasks'] as List<dynamic>?;
    final subtasks = subtasksRaw == null
        ? const <RemoteTaskStep>[]
        : subtasksRaw
              .whereType<Map>()
              .map((m) => RemoteTaskStep.fromJson(Map<String, dynamic>.from(m)))
              .toList();
    final linkedRaw = json['LinkedEntities'] as List<dynamic>?;
    final linkedEntities = linkedRaw == null
        ? const <RemoteLinkedEntity>[]
        : linkedRaw
              .whereType<Map>()
              .map(
                (m) =>
                    RemoteLinkedEntity.fromJson(Map<String, dynamic>.from(m)),
              )
              .toList();

    return RemoteTodoTask(
      id: json['Id'] as String? ?? '',
      changeKey: json['ChangeKey'] as String?,
      parentFolderId: json['ParentFolderId'] as String?,
      subject: json['Subject'] as String? ?? '',
      bodyContent: bodyContent,
      bodyContentType: bodyContentType,
      bodyLastModifiedTime: parseSubstrateTimestamp(
        json['BodyLastModifiedTime'] as String?,
      ),
      orderDateTime: parseSubstrateTimestamp(json['OrderDateTime'] as String?),
      dueDate: parseSubstrateDay(json['DueDate'] ?? json['DueDateTime']),
      reminderDateTime: parseSubstrateDateTimeTimeZone(
        asJsonMap(json['ReminderDateTime']),
      ),
      isReminderOn: json['IsReminderOn'] as bool? ?? false,
      completedDateTime: parseSubstrateDateTimeTimeZone(
        asJsonMap(json['CompletedDateTime']),
      ),
      status: json['Status'] as String? ?? 'NotStarted',
      importance: json['Importance'] as String? ?? 'Normal',
      isIgnored: json['IsIgnored'] as bool? ?? false,
      committedDay: parseSubstrateDay(json['CommittedDay']),
      committedOrder: parseSubstrateTimestamp(
        json['CommittedOrder'] as String?,
      ),
      postponedDay: parseSubstrateDay(json['PostponedDay']),
      createdDateTime: parseSubstrateTimestamp(
        json['CreatedDateTime'] as String?,
      ),
      lastModifiedDateTime: parseSubstrateTimestamp(
        json['LastModifiedDateTime'] as String?,
      ),
      recurrence: decodeSubstrateRecurrence(recurrenceMap),
      rawRecurrence: normalizeRawRecurrence(recurrenceMap),
      uncommittedDue: json['UncommittedDue'] as bool? ?? false,
      subtasks: subtasks,
      linkedEntities: linkedEntities,
      isDeleted: reason == 'deleted',
    );
  }
}

class DeltaPageResult<T> {
  const DeltaPageResult({required this.items, this.deltaLink});

  final List<T> items;
  final String? deltaLink;
}

enum RealtimeEventEntityType {
  task,
  taskFolder,
  folderGroup,
  setting,
  keepAlive,
  unknown;

  static RealtimeEventEntityType parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'task' => RealtimeEventEntityType.task,
        'taskfolder' => RealtimeEventEntityType.taskFolder,
        'foldergroup' => RealtimeEventEntityType.folderGroup,
        'setting' => RealtimeEventEntityType.setting,
        'keepalive' => RealtimeEventEntityType.keepAlive,
        _ => RealtimeEventEntityType.unknown,
      };
}

enum RealtimeEventOperation {
  created,
  updated,
  deleted,
  unsupported;

  static RealtimeEventOperation parse(String? raw) =>
      switch (raw?.trim().toLowerCase()) {
        'created' => RealtimeEventOperation.created,
        'updated' => RealtimeEventOperation.updated,
        'deleted' => RealtimeEventOperation.deleted,
        _ => RealtimeEventOperation.unsupported,
      };
}

class RealtimeEvent {
  const RealtimeEvent({
    this.id,
    required this.type,
    this.operation,
    this.requestId,
    this.payload,
  });

  final String? id;
  final String type;
  final String? operation;
  final String? requestId;
  final Map<String, dynamic>? payload;

  RealtimeEventEntityType get entityType => RealtimeEventEntityType.parse(type);

  RealtimeEventOperation get op => RealtimeEventOperation.parse(operation);

  bool get isKeepAlive => entityType == RealtimeEventEntityType.keepAlive;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    return RealtimeEvent(
      id: json['Id'] as String?,
      type: json['Type'] as String? ?? '',
      operation: json['Operation'] as String?,
      requestId: json['RequestId'] as String?,
      payload: asJsonMap(json['Payload']),
    );
  }
}

Map<String, dynamic>? asJsonMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

/// Safely decodes a JSON object string into a map, returning `null` on empty
/// input, non-object JSON, or malformed syntax.
Map<String, dynamic>? tryDecodeJsonMap(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  try {
    return asJsonMap(jsonDecode(trimmed));
  } on FormatException {
    return null;
  }
}
