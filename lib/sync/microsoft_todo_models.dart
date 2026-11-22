import '../auth/microsoft_auth_service.dart';
import '../models/task_item.dart';
import '../models/todo_list.dart';
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

/// Exception thrown by Substrate v1 API calls with decoded error codes.
class SyncApiException implements Exception {
  const SyncApiException({
    required this.statusCode,
    required this.message,
    this.errorCode,
    this.responseBody,
    this.retryAfter,
  });

  final int statusCode;
  final String message;
  final String? errorCode;
  final String? responseBody;
  final Duration? retryAfter;

  bool get isAuthError => statusCode == 401;

  bool get isNotFound =>
      statusCode == 404 ||
      errorCode == 'ErrorItemNotFound' ||
      errorCode == 'itemNotFound' ||
      errorCode == 'ParentFolderDoesNotContainTaskWithGivenId';

  bool get isConflict =>
      statusCode == 409 ||
      statusCode == 412 ||
      errorCode == 'ErrorIrresolvableConflict';

  bool get isDeltaExpired =>
      statusCode == 410 ||
      errorCode == 'SyncStateNotFound' ||
      errorCode == 'SyncStateInvalid' ||
      errorCode == 'resyncRequired';

  bool get isThrottled => statusCode == 429;

  bool get isFolderGroupNotEmpty => errorCode == 'FolderGroupNotEmpty';

  bool get isCantDeleteDefaultFolder => errorCode == 'CantDeleteDefaultFolder';

  @override
  String toString() {
    final codePart = errorCode != null ? ' [$errorCode]' : '';
    return 'SyncApiException($statusCode$codePart): $message';
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
    this.subtasks = const [],
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
  final List<RemoteTaskStep> subtasks;
  final bool isDeleted;

  bool get isCompleted => status.toLowerCase() == 'completed';

  bool get isImportant => importance.toLowerCase() == 'high';

  String get plainTextNote =>
      stripHtmlToPlainText(bodyContent, contentType: bodyContentType);

  factory RemoteTodoTask.fromJson(Map<String, dynamic> json) {
    final reason = (json['Reason'] as String?)?.toLowerCase();
    final bodyMap = asJsonMap(json['Body']);
    final bodyContent = (bodyMap?['Content'] as String?) ?? '';
    final bodyContentType = bodyMap?['ContentType'] as String?;
    final subtasksRaw = json['Subtasks'] as List<dynamic>?;
    final subtasks = subtasksRaw == null
        ? const <RemoteTaskStep>[]
        : subtasksRaw
              .whereType<Map>()
              .map((m) => RemoteTaskStep.fromJson(Map<String, dynamic>.from(m)))
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
      recurrence: decodeSubstrateRecurrence(asJsonMap(json['Recurrence'])),
      subtasks: subtasks,
      isDeleted: reason == 'deleted',
    );
  }
}

class DeltaPageResult<T> {
  const DeltaPageResult({required this.items, this.deltaLink});

  final List<T> items;
  final String? deltaLink;
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

  bool get isKeepAlive => type.trim().toLowerCase() == 'keepalive';

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
