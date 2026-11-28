import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:http/http.dart' as http;
import 'package:result_dart/result_dart.dart';

import '../../auth/microsoft_auth_service.dart';
import '../../core/error/app_error.dart';
import '../../core/logging/app_logger.dart';
import '../../core/result/app_result.dart';
import '../../data/todo_repository.dart';
import '../../models/account.dart';
import '../../core/network/http_guard.dart';
import 'microsoft_todo_models.dart';
import 'todo_wire_codecs.dart';

export 'microsoft_todo_models.dart';

final _log = appLogFor('SyncApi');
final _realtimeLog = appLogFor('SyncRealtime');

typedef SubstrateContextResolver =
    AsyncAppResult<SubstrateRequestContext> Function({bool forceRefreshToken});

/// Resolves valid MSA bearer token, CID, and discovered Substrate base URL
/// (caching the endpoint URL in SQLite [repository]).
AsyncAppResult<SubstrateRequestContext> resolveSubstrateContext({
  required MicrosoftAuthClient authClient,
  required AuthTokenStorage tokenStorage,
  required MicrosoftAccount account,
  required TodoRepository repository,
  bool forceRefreshToken = false,
}) =>
    _resolveTokens(
      authClient: authClient,
      tokenStorage: tokenStorage,
      account: account,
      forceRefreshToken: forceRefreshToken,
    ).flatMap((tokens) {
      final cid = tokens.userId.isNotEmpty
          ? tokens.userId
          : account.microsoftUserId;
      return _resolveBaseUrl(
        authClient: authClient,
        repository: repository,
        cid: cid,
      ).map(
        (baseUrl) => SubstrateRequestContext(
          baseUrl: baseUrl,
          accessToken: tokens.accessToken,
          cid: cid,
        ),
      );
    });

AsyncAppResult<MicrosoftAuthTokens> _resolveTokens({
  required MicrosoftAuthClient authClient,
  required AuthTokenStorage tokenStorage,
  required MicrosoftAccount account,
  required bool forceRefreshToken,
}) async {
  if (!forceRefreshToken) {
    return authClient.ensureValidTokens(
      accountId: account.id,
      storage: tokenStorage,
      fallbackCid: account.microsoftUserId,
    );
  }
  final stored = await tokenStorage.loadTokens(account.id);
  if (stored == null || stored.refreshToken.isEmpty) {
    return const Failure(
      AppError.auth(
        message: 'Refresh token unavailable; please sign in again.',
        code: 'no_refresh_token',
        requiresReauth: true,
      ),
    );
  }
  final refreshed = await authClient.refreshTokens(
    refreshToken: stored.refreshToken,
    fallbackUserId: stored.userId.isNotEmpty
        ? stored.userId
        : account.microsoftUserId,
  );
  if (refreshed.isSuccess()) {
    await tokenStorage.saveTokens(account.id, refreshed.getOrNull()!);
  }
  return refreshed;
}

AsyncAppResult<String> _resolveBaseUrl({
  required MicrosoftAuthClient authClient,
  required TodoRepository repository,
  required String cid,
}) async {
  final cached = repository.loadCachedEndpointUrl();
  if (cached != null) return Success(cached);
  final discovered = await guardApiCall(
    () => authClient.discoverTodoEndpoint(cid),
    operation: 'discoverEndpoint',
  );
  if (discovered.isSuccess()) {
    await repository.saveCachedEndpointUrl(discovered.getOrNull()!);
  }
  return discovered;
}

/// Abstract Substrate To Do v1 API client returning [AsyncAppResult].
abstract class MicrosoftTodoApi {
  AsyncAppResult<Map<String, String>> getSettings();

  AsyncAppResult<Unit> patchSetting(String key, String value);

  AsyncAppResult<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta({
    String? deltaLink,
  });

  AsyncAppResult<RemoteFolderGroup> createFolderGroup({
    required String name,
    required DateTime orderDateTime,
  });

  AsyncAppResult<RemoteFolderGroup> patchFolderGroup(
    String remoteId,
    Map<String, dynamic> patch,
  );

  AsyncAppResult<Unit> deleteFolderGroup(String remoteId);

  AsyncAppResult<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta({
    String? deltaLink,
  });

  AsyncAppResult<RemoteTodoFolder> createFolder(Map<String, dynamic> payload);

  AsyncAppResult<RemoteTodoFolder> patchFolder(
    String remoteId,
    Map<String, dynamic> patch,
  );

  AsyncAppResult<Unit> deleteFolder(String remoteId);

  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta({
    required String folderRemoteId,
    String? deltaLink,
  });

  AsyncAppResult<RemoteTodoTask> getTask(String taskRemoteId);

  AsyncAppResult<RemoteTodoTask> createTask(
    String folderRemoteId,
    Map<String, dynamic> payload,
  );

  AsyncAppResult<RemoteTodoTask> patchTask(
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  });

  AsyncAppResult<Unit> deleteTask(String taskRemoteId);

  AsyncAppResult<RemoteTaskStep> createStep(
    String taskRemoteId, {
    required String subject,
    required DateTime orderDateTime,
  });

  AsyncAppResult<RemoteTaskStep> patchStep(
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  );

  AsyncAppResult<Unit> deleteStep(String taskRemoteId, String stepRemoteId);

  AsyncAppResult<RemoteFileUpload> uploadAttachment(
    String taskRemoteId, {
    required String fileName,
    required List<int> bytes,
    String? contentType,
  });

  AsyncAppResult<Uint8List> downloadAttachment(String webLink);

  AsyncAppResult<Unit> deleteLinkedEntity(
    String taskRemoteId,
    String entityRemoteId,
  );

  Stream<RealtimeEvent> connectRealtime();

  bool isOwnRequestId(String? requestId);
}

class HttpMicrosoftTodoApi implements MicrosoftTodoApi {
  HttpMicrosoftTodoApi({
    required SubstrateContextResolver contextResolver,
    http.Client? httpClient,
    Future<void> Function(Duration)? delayFn,
  }) : _resolveContext = contextResolver,
       _http = httpClient ?? http.Client(),
       _delay = delayFn ?? Future<void>.delayed;

  HttpMicrosoftTodoApi.withStaticContext(
    SubstrateRequestContext context, {
    http.Client? httpClient,
    Future<void> Function(Duration)? delayFn,
  }) : this(
         contextResolver: ({bool forceRefreshToken = false}) async =>
             Success(context),
         httpClient: httpClient,
         delayFn: delayFn,
       );

  static const _userAgent = 'Microsoft To-Do/Android/2.178.8840.00.beta';
  static const _requestTimeout = Duration(seconds: 60);
  static const _maxDeltaPages = 200;
  static const _ownRequestHistoryLimit = 200;

  final SubstrateContextResolver _resolveContext;
  final http.Client _http;
  final Future<void> Function(Duration) _delay;
  final String _cvPrefix = generateUuidV4().substring(0, 16);
  int _cvCounter = 0;

  final Queue<String> _ownRequestOrder = Queue<String>();
  final Set<String> _ownRequestSet = <String>{};
  DateTime? _throttleUntil;

  Future<void> _awaitThrottleGate() async {
    final until = _throttleUntil;
    if (until == null) return;
    final remaining = until.difference(DateTime.now());
    if (remaining > Duration.zero) {
      await _delay(remaining);
    }
    if (_throttleUntil == until) {
      _throttleUntil = null;
    }
  }

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

  AsyncAppResult<T> _runWithAuthRetry<T extends Object>(
    AsyncAppResult<T> Function(SubstrateRequestContext ctx) run,
  ) async {
    AsyncAppResult<T> attempt({required bool forceRefreshToken}) =>
        _resolveContext(forceRefreshToken: forceRefreshToken).flatMap(run);

    final firstAttempt = await attempt(forceRefreshToken: false);
    if (firstAttempt.exceptionOrNull() is! AuthError) {
      return firstAttempt;
    }

    final retried = await attempt(forceRefreshToken: true);
    return retried.mapError(
      (error) => error is AuthError
          ? AppError.auth(
              message: error.message,
              code: error.code,
              requiresReauth: true,
            )
          : error,
    );
  }

  AsyncAppResult<http.Response> _sendWithThrottleRetry({
    required Future<http.Response> Function() executeOnce,
    required String operation,
    Set<int> acceptedStatusCodes = const {},
  }) => guardApiCall(() async {
    await _awaitThrottleGate();
    var response = await executeOnce();
    final retryDelay = _extractThrottleDelay(response);
    if (retryDelay != null) {
      final nextUntil = DateTime.now().add(retryDelay);
      if (_throttleUntil == null || nextUntil.isAfter(_throttleUntil!)) {
        _throttleUntil = nextUntil;
      }
      await _delay(retryDelay);
      if (_throttleUntil == nextUntil) {
        _throttleUntil = null;
      }
      response = await executeOnce();
    }

    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        !acceptedStatusCodes.contains(response.statusCode)) {
      throw _buildApiError(response);
    }
    return response;
  }, operation: operation);

  AsyncAppResult<http.Response> _sendRequest({
    required String method,
    required Uri Function(SubstrateRequestContext ctx) uriFor,
    bool trackChanges = false,
    String? ifMatch,
    Object? jsonBody,
    Set<int> acceptedStatusCodes = const {},
  }) => _runWithAuthRetry((ctx) {
    final uri = uriFor(ctx);
    return _sendWithThrottleRetry(
      operation: '$method ${uri.path}',
      acceptedStatusCodes: acceptedStatusCodes,
      executeOnce: () {
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
      },
    );
  });

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
    return headers.entries
        .firstWhereOrNull((entry) => equalsIgnoreAsciiCase(entry.key, name))
        ?.value;
  }

  AppError _buildApiError(http.Response response) {
    final decoded = tryDecodeJsonMap(response.body);
    final errObj = asJsonMap(decoded?['error'] ?? decoded?['Error']) ?? decoded;
    final innerObj = asJsonMap(
      errObj?['innerError'] ?? errObj?['innererror'] ?? errObj?['InnerError'],
    );
    final errorCode =
        (innerObj?['code'] ?? innerObj?['Code']) as String? ??
        (errObj?['code'] ?? errObj?['Code']) as String?;
    final rawMessage = (errObj?['message'] ?? errObj?['Message']) as String?;
    final message = (rawMessage != null && rawMessage.isNotEmpty)
        ? rawMessage
        : 'Substrate request failed (${response.statusCode})';

    return appErrorFromHttpStatus(
      statusCode: response.statusCode,
      message: message,
      errorCode: errorCode,
    );
  }

  AsyncAppResult<Map<String, dynamic>> _requestJson({
    required String method,
    required String relativePath,
    Map<String, dynamic>? body,
    String? ifMatch,
    bool trackChanges = false,
  }) => _sendRequest(
    method: method,
    uriFor: (ctx) => ctx.endpointUri(relativePath),
    jsonBody: body,
    ifMatch: ifMatch,
    trackChanges: trackChanges,
  ).map((response) => _decodeJsonMap(response.body));

  AsyncAppResult<Unit> _deleteResource(String relativePath) => _sendRequest(
    method: 'DELETE',
    uriFor: (ctx) => ctx.endpointUri(relativePath),
  ).map((_) => unit);

  Map<String, dynamic> _decodeJsonMap(String body) =>
      tryDecodeJsonMap(body) ?? const {};

  AsyncAppResult<DeltaPageResult<T>> _fetchDeltaPages<T>({
    required String initialRelativePath,
    required T Function(Map<String, dynamic> json) parser,
    String? deltaLink,
  }) async {
    final usedDelta = deltaLink != null && deltaLink.trim().isNotEmpty;
    Uri? nextUri = usedDelta ? Uri.parse(deltaLink.trim()) : null;
    final visitedUris = <Uri>{};
    final items = <T>[];
    String? resolvedDeltaLink;
    String? folderParam;
    Uri? firstPageUri;
    var pages = 0;

    while ((pages == 0 || nextUri != null) && pages < _maxDeltaPages) {
      pages += 1;
      late Uri currentUri;
      final pageResult = await _sendRequest(
        method: 'GET',
        uriFor: (ctx) {
          currentUri = nextUri ?? ctx.endpointUri(initialRelativePath);
          return currentUri;
        },
        trackChanges: true,
      ).map((response) => _decodeJsonMap(response.body));
      if (pageResult.isError()) {
        return Failure(pageResult.exceptionOrNull()!);
      }
      firstPageUri ??= currentUri;
      folderParam ??= currentUri.queryParameters['parentFolderId'];
      visitedUris.add(currentUri);

      final page = pageResult.getOrThrow();
      final rawList =
          (page['Value'] ?? page['Values'] ?? page['value'] ?? page['values'])
              as List<dynamic>? ??
          const [];
      for (final raw in rawList) {
        if (raw is Map) {
          items.add(parser(Map<String, dynamic>.from(raw)));
        }
      }
      final rawDelta =
          (page['DeltaLink'] ?? page['@odata.deltaLink'] ?? page['deltaLink'])
              as String?;
      final trimmedDelta = rawDelta?.trim();
      final hasDelta = trimmedDelta != null && trimmedDelta.isNotEmpty;

      final rawNext =
          (page['NextLink'] ?? page['@odata.nextLink'] ?? page['nextLink'])
              as String?;
      final trimmedNext = rawNext?.trim();
      final hasNext = trimmedNext != null && trimmedNext.isNotEmpty;

      final step = _resolveNextDeltaUri(
        currentUri: currentUri,
        visitedUris: visitedUris,
        isInitialFirstPage: !usedDelta && pages == 1,
        nextLink: hasNext ? trimmedNext : null,
        deltaLink: hasDelta ? trimmedDelta : null,
      );
      nextUri = step.nextUri;
      if (step.terminalDeltaLink != null) {
        resolvedDeltaLink = step.terminalDeltaLink;
      }
    }

    final folderHint = folderParam != null
        ? ' folder=${shortSyncId(folderParam)}'
        : '';
    _log.fine(
      'fetchDelta ${firstPageUri?.path ?? initialRelativePath}$folderHint '
      'mode=${usedDelta ? "delta" : "full"} '
      'pages=$pages items=${items.length} hasDeltaLink=${resolvedDeltaLink != null}',
    );

    return Success(
      DeltaPageResult<T>(items: items, deltaLink: resolvedDeltaLink),
    );
  }

  ({Uri? nextUri, String? terminalDeltaLink}) _resolveNextDeltaUri({
    required Uri currentUri,
    required Set<Uri> visitedUris,
    required bool isInitialFirstPage,
    required String? nextLink,
    required String? deltaLink,
  }) {
    if (isInitialFirstPage) {
      // Mirror MS To Do GswSync.g() -> h(): on an initial/full fetch, page 1
      // only returns the head page + a checkpoint DeltaLink (or NextLink);
      // unconditionally chain into f(nextLink ?? deltaLink) to drain all pages.
      final continuation = nextLink ?? deltaLink;
      if (continuation == null) return (nextUri: null, terminalDeltaLink: null);
      final resolved = currentUri.resolve(continuation);
      if (visitedUris.contains(resolved)) {
        return (
          nextUri: null,
          terminalDeltaLink: deltaLink != null
              ? currentUri.resolve(deltaLink).toString()
              : null,
        );
      }
      return (nextUri: resolved, terminalDeltaLink: null);
    }
    if (deltaLink != null) {
      return (
        nextUri: null,
        terminalDeltaLink: currentUri.resolve(deltaLink).toString(),
      );
    }
    if (nextLink == null) return (nextUri: null, terminalDeltaLink: null);
    final resolved = currentUri.resolve(nextLink);
    return (
      nextUri: visitedUris.contains(resolved) ? null : resolved,
      terminalDeltaLink: null,
    );
  }

  @override
  AsyncAppResult<Map<String, String>> getSettings() {
    return _requestJson(method: 'GET', relativePath: 'settings').map((json) {
      final rawList =
          (json['Value'] ?? json['Values'] ?? json['value'])
              as List<dynamic>? ??
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
    });
  }

  @override
  AsyncAppResult<Unit> patchSetting(String key, String value) => _sendRequest(
    method: 'PATCH',
    uriFor: (ctx) => ctx.endpointUri('settings/${Uri.encodeComponent(key)}'),
    jsonBody: {'Value': value},
  ).map((_) => unit);

  @override
  AsyncAppResult<DeltaPageResult<RemoteFolderGroup>> fetchFolderGroupsDelta({
    String? deltaLink,
  }) => _fetchDeltaPages<RemoteFolderGroup>(
    initialRelativePath: 'foldergroups?maxPageSize=50',
    deltaLink: deltaLink,
    parser: RemoteFolderGroup.fromJson,
  );

  @override
  AsyncAppResult<RemoteFolderGroup> createFolderGroup({
    required String name,
    required DateTime orderDateTime,
  }) => _requestJson(
    method: 'POST',
    relativePath: 'foldergroups',
    body: {
      'Name': name,
      'OrderDateTime': formatSubstrateUtcTimestamp(orderDateTime),
    },
  ).map(RemoteFolderGroup.fromJson);

  @override
  AsyncAppResult<RemoteFolderGroup> patchFolderGroup(
    String remoteId,
    Map<String, dynamic> patch,
  ) => _requestJson(
    method: 'PATCH',
    relativePath: 'foldergroups/${Uri.encodeComponent(remoteId)}',
    body: patch,
  ).map(RemoteFolderGroup.fromJson);

  @override
  AsyncAppResult<Unit> deleteFolderGroup(String remoteId) =>
      _deleteResource('foldergroups/${Uri.encodeComponent(remoteId)}');

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoFolder>> fetchFoldersDelta({
    String? deltaLink,
  }) => _fetchDeltaPages<RemoteTodoFolder>(
    initialRelativePath: 'taskfolders?\$select=*,AllExtensions/Com_Wunderlist_Import,AllExtensions/Com_Microsoft_Grocery_Configs&maxPageSize=50',
    deltaLink: deltaLink,
    parser: RemoteTodoFolder.fromJson,
  );

  @override
  AsyncAppResult<RemoteTodoFolder> createFolder(Map<String, dynamic> payload) =>
      _requestJson(
        method: 'POST',
        relativePath: 'taskfolders',
        body: payload,
      ).map(RemoteTodoFolder.fromJson);

  @override
  AsyncAppResult<RemoteTodoFolder> patchFolder(
    String remoteId,
    Map<String, dynamic> patch,
  ) => _requestJson(
    method: 'PATCH',
    relativePath:
        'taskfolders/${Uri.encodeComponent(remoteId)}?\$select=*,AllExtensions/Com_Microsoft_Grocery_Configs',
    body: patch,
  ).map(RemoteTodoFolder.fromJson);

  @override
  AsyncAppResult<Unit> deleteFolder(String remoteId) =>
      _deleteResource('taskfolders/${Uri.encodeComponent(remoteId)}');

  @override
  AsyncAppResult<DeltaPageResult<RemoteTodoTask>> fetchTasksDelta({
    required String folderRemoteId,
    String? deltaLink,
  }) {
    final encodedFolderId = Uri.encodeQueryComponent(folderRemoteId);
    return _fetchDeltaPages<RemoteTodoTask>(
      initialRelativePath:
          'tasks?\$expand=LinkedEntities&parentFolderId=$encodedFolderId&maxPageSize=50',
      deltaLink: deltaLink,
      parser: RemoteTodoTask.fromJson,
    );
  }

  @override
  AsyncAppResult<RemoteTodoTask> getTask(String taskRemoteId) => _requestJson(
    method: 'GET',
    relativePath: 'tasks/${Uri.encodeComponent(taskRemoteId)}',
  ).map(RemoteTodoTask.fromJson);

  @override
  AsyncAppResult<RemoteTodoTask> createTask(
    String folderRemoteId,
    Map<String, dynamic> payload,
  ) =>
      _sendRequest(
        method: 'POST',
        uriFor: (ctx) => ctx.endpointUri(
          'taskfolders/${Uri.encodeComponent(folderRemoteId)}/tasks',
        ),
        jsonBody: payload,
        acceptedStatusCodes: const {409},
      ).flatMap((response) async {
        if (response.statusCode == 409) {
          final existing = _tryParseCreatedTaskConflict(response.body);
          if (existing != null) {
            return Success(existing);
          }
          return Failure(_buildApiError(response));
        }
        return Success(RemoteTodoTask.fromJson(_decodeJsonMap(response.body)));
      });

  /// Aligns with MS To Do's `CreatedTaskAlreadyExistsOperator`: when a task
  /// POST returns HTTP 409 whose body is the existing task (not an error
  /// payload), treat it as the created task instead of failing.
  RemoteTodoTask? _tryParseCreatedTaskConflict(String body) {
    final decoded = tryDecodeJsonMap(body);
    if (decoded == null) return null;
    if (decoded['error'] != null || decoded['Error'] != null) {
      _log.info(
        'Error object received in payload along with 409 on task create',
      );
      return null;
    }
    try {
      final task = RemoteTodoTask.fromJson(decoded);
      if (task.id.isEmpty) {
        _log.warning('409 task create payload has empty online Id');
        return null;
      }
      _log.info(
        'Task received in payload along with 409 on task create '
        'id=${shortSyncId(task.id)}',
      );
      return task;
    } on TypeError {
      return null;
    }
  }

  @override
  AsyncAppResult<RemoteTodoTask> patchTask(
    String taskRemoteId,
    Map<String, dynamic> patch, {
    String? changeKey,
  }) => _requestJson(
    method: 'PATCH',
    relativePath: 'tasks/${Uri.encodeComponent(taskRemoteId)}',
    body: patch,
    ifMatch: changeKey,
  ).map(RemoteTodoTask.fromJson);

  @override
  AsyncAppResult<Unit> deleteTask(String taskRemoteId) =>
      _deleteResource('tasks/${Uri.encodeComponent(taskRemoteId)}');

  @override
  AsyncAppResult<RemoteTaskStep> createStep(
    String taskRemoteId, {
    required String subject,
    required DateTime orderDateTime,
  }) => _requestJson(
    method: 'POST',
    relativePath: 'tasks/${Uri.encodeComponent(taskRemoteId)}/subtasks',
    body: {
      'Subject': subject,
      'OrderDateTime': formatSubstrateUtcTimestamp(orderDateTime),
    },
  ).map(RemoteTaskStep.fromJson);

  @override
  AsyncAppResult<RemoteTaskStep> patchStep(
    String taskRemoteId,
    String stepRemoteId,
    Map<String, dynamic> patch,
  ) => _requestJson(
    method: 'PATCH',
    relativePath:
        'tasks/${Uri.encodeComponent(taskRemoteId)}/subtasks/${Uri.encodeComponent(stepRemoteId)}',
    body: patch,
  ).map(RemoteTaskStep.fromJson);

  @override
  AsyncAppResult<Unit> deleteStep(
    String taskRemoteId,
    String stepRemoteId,
  ) => _deleteResource(
    'tasks/${Uri.encodeComponent(taskRemoteId)}/subtasks/${Uri.encodeComponent(stepRemoteId)}',
  );

  @override
  AsyncAppResult<RemoteFileUpload> uploadAttachment(
    String taskRemoteId, {
    required String fileName,
    required List<int> bytes,
    String? contentType,
  }) => _runWithAuthRetry(
    (ctx) => _sendWithThrottleRetry(
      operation: 'uploadAttachment',
      executeOnce: () async {
        final uri = ctx.endpointUri(
          'tasks/${Uri.encodeComponent(taskRemoteId)}/attachments',
        );
        final request = http.MultipartRequest('POST', uri);
        final headers = _buildHeaders(ctx)..remove('Content-Type');
        request.headers.addAll(headers);
        request.fields['jsonMetadata'] = jsonEncode({'Name': fileName});
        request.files.add(
          http.MultipartFile.fromBytes('attachment', bytes, filename: fileName),
        );
        final streamed = await _http.send(request).timeout(_requestTimeout);
        return http.Response.fromStream(streamed);
      },
    ),
  ).map((response) => RemoteFileUpload.fromJson(_decodeJsonMap(response.body)));

  Uri _resolveAttachmentDownloadUri(
    SubstrateRequestContext ctx,
    String webLink,
  ) {
    final trimmed = webLink.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return Uri.parse(trimmed);
    }
    final base = Uri.parse(ctx.baseUrl);
    final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    return Uri.parse('${base.scheme}://${base.authority}$path');
  }

  @override
  AsyncAppResult<Uint8List> downloadAttachment(String webLink) =>
      _runWithAuthRetry(
        (ctx) => _sendWithThrottleRetry(
          operation: 'downloadAttachment',
          executeOnce: () {
            final uri = _resolveAttachmentDownloadUri(ctx, webLink);
            final headers = _buildHeaders(ctx)
              ..remove('Content-Type')
              ..['Accept'] = '*/*';
            return _http.get(uri, headers: headers).timeout(_requestTimeout);
          },
        ),
      ).map((response) => response.bodyBytes);

  @override
  AsyncAppResult<Unit> deleteLinkedEntity(
    String taskRemoteId,
    String entityRemoteId,
  ) => _deleteResource(
    'tasks/${Uri.encodeComponent(taskRemoteId)}/linkedentities/${Uri.encodeComponent(entityRemoteId)}',
  );

  Future<http.StreamedResponse> _openRealtimeStream(
    SubstrateRequestContext ctx,
  ) {
    final request = http.Request('GET', ctx.endpointUri('realtime'));
    request.headers.addAll(_buildHeaders(ctx, longPolling: true));
    return _http.send(request).timeout(_requestTimeout);
  }

  @override
  Stream<RealtimeEvent> connectRealtime() async* {
    _realtimeLog.info('connecting GET realtime');
    var ctx = (await _resolveContext(forceRefreshToken: false))
        .fold((value) => value, (error) => throw error);
    var streamed = await _openRealtimeStream(ctx);
    if (streamed.statusCode == 401) {
      await streamed.stream.drain<void>().catchError((_) {});
      ctx = (await _resolveContext(forceRefreshToken: true)).fold(
        (value) => value,
        (error) => throw error is AuthError
            ? AppError.auth(
                message: error.message,
                code: error.code,
                requiresReauth: true,
              )
            : error,
      );
      streamed = await _openRealtimeStream(ctx);
    }
    _realtimeLog.info('connected status=${streamed.statusCode}');
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      await streamed.stream.drain<void>().catchError((_) {});
      throw appErrorFromHttpStatus(
        statusCode: streamed.statusCode,
        message: 'Realtime stream failed (${streamed.statusCode})',
      );
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      final decoded = tryDecodeJsonMap(line);
      if (decoded == null) continue;
      final event = RealtimeEvent.fromJson(decoded);
      if (!event.isKeepAlive) {
        _realtimeLog.fine(
          'recv type=${event.type} op=${event.operation} '
          'id=${shortSyncId(event.id)} req=${event.requestId} '
          'hasPayload=${event.payload != null} '
          'keys=${event.payload?.keys.toList()}',
        );
      }
      yield event;
    }
    _realtimeLog.info('stream closed');
  }
}
