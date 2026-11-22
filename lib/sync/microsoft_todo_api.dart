import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'microsoft_todo_models.dart';
import 'todo_wire_codecs.dart';

export 'microsoft_todo_models.dart';

/// Abstract Substrate To Do v1 API client.
abstract class MicrosoftTodoApi {
  Future<Map<String, String>> getSettings(SubstrateRequestContext ctx);

  Future<void> patchSetting(
    SubstrateRequestContext ctx,
    String key,
    String value,
  );

  Future<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  });

  Future<RemoteFolderGroup> createFolderGroup(
    SubstrateRequestContext ctx, {
    required String name,
    required DateTime orderDateTime,
  });

  Future<RemoteFolderGroup> patchFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  );

  Future<void> deleteFolderGroup(SubstrateRequestContext ctx, String remoteId);

  Future<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  });

  Future<RemoteTodoFolder> createFolder(
    SubstrateRequestContext ctx,
    Map<String, dynamic> payload,
  );

  Future<RemoteTodoFolder> patchFolder(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  );

  Future<void> deleteFolder(SubstrateRequestContext ctx, String remoteId);

  Future<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  });

  Future<RemoteTodoTask> getTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  );

  Future<RemoteTodoTask> createTask(
    SubstrateRequestContext ctx,
    String folderRemoteId,
    Map<String, dynamic> payload,
  );

  Future<RemoteTodoTask> patchTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  });

  Future<void> deleteTask(SubstrateRequestContext ctx, String taskRemoteId);

  Future<RemoteTaskStep> createStep(
    SubstrateRequestContext ctx,
    String taskRemoteId, {
    required String subject,
    required DateTime orderDateTime,
  });

  Future<RemoteTaskStep> patchStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  );

  Future<void> deleteStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
  );

  Stream<RealtimeEvent> connectRealtime(SubstrateRequestContext ctx);

  bool isOwnRequestId(String? requestId);
}

class HttpMicrosoftTodoApi implements MicrosoftTodoApi {
  HttpMicrosoftTodoApi({
    http.Client? httpClient,
    Future<void> Function(Duration)? delayFn,
  }) : _http = httpClient ?? http.Client(),
       _delay = delayFn ?? Future<void>.delayed;

  static const _userAgent = 'Microsoft To-Do/Android/2.178.8840.00.beta';
  static const _requestTimeout = Duration(seconds: 60);
  static const _maxDeltaPages = 200;
  static const _ownRequestHistoryLimit = 200;

  final http.Client _http;
  final Future<void> Function(Duration) _delay;
  final String _cvPrefix = generateUuidV4().substring(0, 16);
  int _cvCounter = 0;

  final Queue<String> _ownRequestOrder = Queue<String>();
  final Set<String> _ownRequestSet = <String>{};

  String _nextRequestId() {
    final id = generateUuidV4();
    _ownRequestOrder.addLast(id);
    _ownRequestSet.add(id);
    while (_ownRequestOrder.length > _ownRequestHistoryLimit) {
      final oldest = _ownRequestOrder.removeFirst();
      _ownRequestSet.remove(oldest);
    }
    return id;
  }

  String _nextMsCv() {
    final c = _cvCounter;
    _cvCounter += 1;
    return '$_cvPrefix.$c';
  }

  @override
  bool isOwnRequestId(String? requestId) {
    if (requestId == null || requestId.isEmpty) return false;
    return _ownRequestSet.contains(requestId.trim());
  }

  Map<String, String> _buildHeaders(
    SubstrateRequestContext ctx, {
    bool trackChanges = false,
    String? ifMatch,
    bool longPolling = false,
  }) {
    final headers = <String, String>{
      'Authorization': 'Bearer ${ctx.accessToken}',
      'X-AnchorMailbox': ctx.anchorMailbox,
      'User-Agent': _userAgent,
      'X-Todo-Request-Id': _nextRequestId(),
      'MS-CV': _nextMsCv(),
      'X-FlaggedListEnabled': 'false',
      'Prefer': trackChanges
          ? 'outlook.timezone=UTC, odata.track-changes'
          : 'outlook.timezone=UTC',
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (ifMatch != null && ifMatch.isNotEmpty) {
      headers['If-Match'] = ifMatch;
    }
    if (longPolling) {
      headers['Long-Polling'] = 'true';
      headers['Accept-Encoding'] = 'identity';
    }
    return headers;
  }

  Future<http.Response> _sendRequest({
    required SubstrateRequestContext ctx,
    required String method,
    required Uri uri,
    bool trackChanges = false,
    String? ifMatch,
    Object? jsonBody,
  }) async {
    Future<http.Response> executeOnce() {
      final headers = _buildHeaders(
        ctx,
        trackChanges: trackChanges,
        ifMatch: ifMatch,
      );
      final encoded = jsonBody == null ? null : jsonEncode(jsonBody);
      return switch (method) {
        'GET' => _http.get(uri, headers: headers).timeout(_requestTimeout),
        'POST' =>
          _http
              .post(uri, headers: headers, body: encoded)
              .timeout(_requestTimeout),
        'PATCH' =>
          _http
              .patch(uri, headers: headers, body: encoded)
              .timeout(_requestTimeout),
        'DELETE' =>
          _http.delete(uri, headers: headers).timeout(_requestTimeout),
        _ => throw ArgumentError('Unsupported HTTP method: $method'),
      };
    }

    var response = await executeOnce();
    final retryDelay = _extractThrottleDelay(response);
    if (retryDelay != null) {
      await _delay(retryDelay);
      response = await executeOnce();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _buildApiException(response);
    }
    return response;
  }

  Duration? _extractThrottleDelay(http.Response response) {
    final status = response.statusCode;
    final retryAfterRaw = _headerCaseInsensitive(
      response.headers,
      'retry-after',
    );
    final rateRemainingRaw = _headerCaseInsensitive(
      response.headers,
      'rate-limit-remaining',
    );

    final retryAfterSecs = retryAfterRaw != null
        ? int.tryParse(retryAfterRaw.trim())
        : null;
    final rateRemaining = rateRemainingRaw != null
        ? int.tryParse(rateRemainingRaw.trim())
        : null;

    final throttled =
        status == 429 ||
        rateRemaining == 0 ||
        (status >= 400 && retryAfterSecs != null);
    if (!throttled) return null;

    if (retryAfterSecs != null && retryAfterSecs > 0) {
      return Duration(seconds: retryAfterSecs.clamp(1, 60));
    }
    return const Duration(seconds: 5);
  }

  String? _headerCaseInsensitive(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
    }
    return null;
  }

  SyncApiException _buildApiException(http.Response response) {
    String? errorCode;
    String message = 'Substrate request failed (${response.statusCode})';

    if (response.body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          final errObj = decoded['error'] ?? decoded['Error'];
          if (errObj is Map) {
            errorCode = (errObj['code'] ?? errObj['Code']) as String?;
            final msg = (errObj['message'] ?? errObj['Message']) as String?;
            if (msg != null && msg.isNotEmpty) {
              message = msg;
            }
          } else {
            errorCode = (decoded['code'] ?? decoded['Code']) as String?;
            final msg = (decoded['message'] ?? decoded['Message']) as String?;
            if (msg != null && msg.isNotEmpty) {
              message = msg;
            }
          }
        }
      } on FormatException catch (_) {}
    }

    final retryAfterRaw = _headerCaseInsensitive(
      response.headers,
      'retry-after',
    );
    final retryAfterSecs = retryAfterRaw != null
        ? int.tryParse(retryAfterRaw.trim())
        : null;

    return SyncApiException(
      statusCode: response.statusCode,
      message: message,
      errorCode: errorCode,
      responseBody: response.body,
      retryAfter: retryAfterSecs != null
          ? Duration(seconds: retryAfterSecs)
          : null,
    );
  }

  Future<Map<String, dynamic>> _getJsonObject({
    required SubstrateRequestContext ctx,
    required Uri uri,
    bool trackChanges = false,
  }) async {
    final response = await _sendRequest(
      ctx: ctx,
      method: 'GET',
      uri: uri,
      trackChanges: trackChanges,
    );
    return _decodeJsonMap(response.body);
  }

  Future<Map<String, dynamic>> _postJsonObject({
    required SubstrateRequestContext ctx,
    required Uri uri,
    required Map<String, dynamic> body,
  }) async {
    final response = await _sendRequest(
      ctx: ctx,
      method: 'POST',
      uri: uri,
      jsonBody: body,
    );
    return _decodeJsonMap(response.body);
  }

  Future<Map<String, dynamic>> _patchJsonObject({
    required SubstrateRequestContext ctx,
    required Uri uri,
    required Map<String, dynamic> body,
    String? ifMatch,
  }) async {
    final response = await _sendRequest(
      ctx: ctx,
      method: 'PATCH',
      uri: uri,
      ifMatch: ifMatch,
      jsonBody: body,
    );
    return _decodeJsonMap(response.body);
  }

  Map<String, dynamic> _decodeJsonMap(String body) {
    if (body.trim().isEmpty) return const {};
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return const {};
  }

  Future<DeltaPageResult<T>> _fetchDeltaPages<T>({
    required SubstrateRequestContext ctx,
    required Uri initialUri,
    required T Function(Map<String, dynamic> json) parser,
    String? deltaLink,
  }) async {
    Uri? nextUri = (deltaLink != null && deltaLink.trim().isNotEmpty)
        ? Uri.parse(deltaLink.trim())
        : initialUri;
    final items = <T>[];
    String? resolvedDeltaLink;
    var pages = 0;

    while (nextUri != null && pages < _maxDeltaPages) {
      pages += 1;
      final page = await _getJsonObject(
        ctx: ctx,
        uri: nextUri,
        trackChanges: true,
      );
      final rawList =
          (page['Value'] ?? page['Values'] ?? page['value'] ?? page['values'])
              as List<dynamic>? ??
          const [];
      for (final raw in rawList) {
        if (raw is Map) {
          items.add(parser(Map<String, dynamic>.from(raw)));
        }
      }
      final delta = (page['DeltaLink'] ?? page['@odata.deltaLink']) as String?;
      if (delta != null && delta.trim().isNotEmpty) {
        resolvedDeltaLink = delta.trim();
      }
      final next = (page['NextLink'] ?? page['@odata.nextLink']) as String?;
      nextUri = (next != null && next.trim().isNotEmpty)
          ? Uri.parse(next.trim())
          : null;
    }

    return DeltaPageResult<T>(items: items, deltaLink: resolvedDeltaLink);
  }

  @override
  Future<Map<String, String>> getSettings(SubstrateRequestContext ctx) async {
    final json = await _getJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri('settings'),
    );
    final rawList =
        (json['Value'] ?? json['Values'] ?? json['value']) as List<dynamic>? ??
        const [];
    final result = <String, String>{};
    for (final entry in rawList) {
      if (entry is Map) {
        final key = entry['Key'] as String?;
        final value = entry['Value'];
        if (key != null && key.isNotEmpty && value != null) {
          result[key] = value.toString();
        }
      }
    }
    return result;
  }

  @override
  Future<void> patchSetting(
    SubstrateRequestContext ctx,
    String key,
    String value,
  ) async {
    await _sendRequest(
      ctx: ctx,
      method: 'PATCH',
      uri: ctx.endpointUri('settings/${Uri.encodeComponent(key)}'),
      jsonBody: {'Value': value},
    );
  }

  @override
  Future<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) {
    return _fetchDeltaPages<RemoteFolderGroup>(
      ctx: ctx,
      initialUri: ctx.endpointUri('foldergroups?maxPageSize=50'),
      deltaLink: deltaLink,
      parser: RemoteFolderGroup.fromJson,
    );
  }

  @override
  Future<RemoteFolderGroup> createFolderGroup(
    SubstrateRequestContext ctx, {
    required String name,
    required DateTime orderDateTime,
  }) async {
    final json = await _postJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri('foldergroups'),
      body: {
        'Name': name,
        'OrderDateTime': formatSubstrateUtcTimestamp(orderDateTime),
      },
    );
    return RemoteFolderGroup.fromJson(json);
  }

  @override
  Future<RemoteFolderGroup> patchFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  ) async {
    final json = await _patchJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri('foldergroups/${Uri.encodeComponent(remoteId)}'),
      body: patch,
    );
    return RemoteFolderGroup.fromJson(json);
  }

  @override
  Future<void> deleteFolderGroup(
    SubstrateRequestContext ctx,
    String remoteId,
  ) async {
    await _sendRequest(
      ctx: ctx,
      method: 'DELETE',
      uri: ctx.endpointUri('foldergroups/${Uri.encodeComponent(remoteId)}'),
    );
  }

  @override
  Future<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta(
    SubstrateRequestContext ctx, {
    String? deltaLink,
  }) {
    return _fetchDeltaPages<RemoteTodoFolder>(
      ctx: ctx,
      initialUri: ctx.endpointUri(
        'taskfolders?\$select=*,AllExtensions/Com_Wunderlist_Import,AllExtensions/Com_Microsoft_Grocery_Configs&maxPageSize=50',
      ),
      deltaLink: deltaLink,
      parser: RemoteTodoFolder.fromJson,
    );
  }

  @override
  Future<RemoteTodoFolder> createFolder(
    SubstrateRequestContext ctx,
    Map<String, dynamic> payload,
  ) async {
    final json = await _postJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri('taskfolders'),
      body: payload,
    );
    return RemoteTodoFolder.fromJson(json);
  }

  @override
  Future<RemoteTodoFolder> patchFolder(
    SubstrateRequestContext ctx,
    String remoteId,
    Map<String, dynamic> patch,
  ) async {
    final json = await _patchJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri(
        'taskfolders/${Uri.encodeComponent(remoteId)}?\$select=*,AllExtensions/Com_Microsoft_Grocery_Configs',
      ),
      body: patch,
    );
    return RemoteTodoFolder.fromJson(json);
  }

  @override
  Future<void> deleteFolder(
    SubstrateRequestContext ctx,
    String remoteId,
  ) async {
    await _sendRequest(
      ctx: ctx,
      method: 'DELETE',
      uri: ctx.endpointUri('taskfolders/${Uri.encodeComponent(remoteId)}'),
    );
  }

  @override
  Future<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta(
    SubstrateRequestContext ctx, {
    required String folderRemoteId,
    String? deltaLink,
  }) {
    final encodedFolderId = Uri.encodeQueryComponent(folderRemoteId);
    return _fetchDeltaPages<RemoteTodoTask>(
      ctx: ctx,
      initialUri: ctx.endpointUri(
        'tasks?\$expand=LinkedEntities&parentFolderId=$encodedFolderId&maxPageSize=50',
      ),
      deltaLink: deltaLink,
      parser: RemoteTodoTask.fromJson,
    );
  }

  @override
  Future<RemoteTodoTask> getTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  ) async {
    final json = await _getJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri('tasks/${Uri.encodeComponent(taskRemoteId)}'),
    );
    return RemoteTodoTask.fromJson(json);
  }

  @override
  Future<RemoteTodoTask> createTask(
    SubstrateRequestContext ctx,
    String folderRemoteId,
    Map<String, dynamic> payload,
  ) async {
    final json = await _postJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri(
        'taskfolders/${Uri.encodeComponent(folderRemoteId)}/tasks',
      ),
      body: payload,
    );
    return RemoteTodoTask.fromJson(json);
  }

  @override
  Future<RemoteTodoTask> patchTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  }) async {
    final json = await _patchJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri('tasks/${Uri.encodeComponent(taskRemoteId)}'),
      body: patch,
      ifMatch: changeKey,
    );
    return RemoteTodoTask.fromJson(json);
  }

  @override
  Future<void> deleteTask(
    SubstrateRequestContext ctx,
    String taskRemoteId,
  ) async {
    await _sendRequest(
      ctx: ctx,
      method: 'DELETE',
      uri: ctx.endpointUri('tasks/${Uri.encodeComponent(taskRemoteId)}'),
    );
  }

  @override
  Future<RemoteTaskStep> createStep(
    SubstrateRequestContext ctx,
    String taskRemoteId, {
    required String subject,
    required DateTime orderDateTime,
  }) async {
    final json = await _postJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri(
        'tasks/${Uri.encodeComponent(taskRemoteId)}/subtasks',
      ),
      body: {
        'Subject': subject,
        'OrderDateTime': formatSubstrateUtcTimestamp(orderDateTime),
      },
    );
    return RemoteTaskStep.fromJson(json);
  }

  @override
  Future<RemoteTaskStep> patchStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  ) async {
    final json = await _patchJsonObject(
      ctx: ctx,
      uri: ctx.endpointUri(
        'tasks/${Uri.encodeComponent(taskRemoteId)}/subtasks/${Uri.encodeComponent(stepRemoteId)}',
      ),
      body: patch,
    );
    return RemoteTaskStep.fromJson(json);
  }

  @override
  Future<void> deleteStep(
    SubstrateRequestContext ctx,
    String taskRemoteId,
    String stepRemoteId,
  ) async {
    await _sendRequest(
      ctx: ctx,
      method: 'DELETE',
      uri: ctx.endpointUri(
        'tasks/${Uri.encodeComponent(taskRemoteId)}/subtasks/${Uri.encodeComponent(stepRemoteId)}',
      ),
    );
  }

  @override
  Stream<RealtimeEvent> connectRealtime(SubstrateRequestContext ctx) async* {
    final request = http.Request('GET', ctx.endpointUri('realtime'));
    request.headers.addAll(_buildHeaders(ctx, longPolling: true));

    final streamed = await _http.send(request).timeout(_requestTimeout);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final body = await streamed.stream.bytesToString();
      throw SyncApiException(
        statusCode: streamed.statusCode,
        message: 'Realtime stream failed (${streamed.statusCode})',
        responseBody: body,
      );
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) {
          yield RealtimeEvent.fromJson(Map<String, dynamic>.from(decoded));
        }
      } on FormatException catch (_) {
        // Ignore non-JSON keepalive / delimiter lines.
      }
    }
  }
}
