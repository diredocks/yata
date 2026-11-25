import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yata/auth/microsoft_auth_service.dart';
import 'package:yata/core/error/app_error.dart';
import 'package:yata/sync/microsoft_todo_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HttpMicrosoftTodoApi', () {
    test('sends Substrate headers, follows NextLink to DeltaLink, retries 429, and classifies errors', () async {
      var pageCall = 0;
      var throttledCalls = 0;

      final mockClient = MockClient((request) async {
        expect(request.headers['X-AnchorMailbox'], 'CID:cid123');
        expect(request.headers['X-FlaggedListEnabled'], 'false');
        expect(request.headers['User-Agent'], contains('Microsoft To-Do'));
        expect(request.headers['X-Todo-Request-Id'], isNotEmpty);
        expect(request.headers['MS-CV'], isNotEmpty);

        if (request.url.path.endsWith('/foldergroups')) {
          pageCall += 1;
          if (pageCall == 1) {
            expect(request.headers['Prefer'], contains('odata.track-changes'));
            return http.Response(
              jsonEncode({
                'Values': [
                  {'Id': 'g1', 'Name': 'Group 1'},
                ],
                'NextLink': 'https://substrate.office.com/todob2/api/v1/foldergroups?page=2',
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 'g2', 'Name': 'Group 2'},
              ],
              'DeltaLink': 'https://substrate.office.com/todob2/api/v1/foldergroups?deltatoken=g-dt',
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/settings')) {
          throttledCalls += 1;
          if (throttledCalls == 1) {
            return http.Response(
              '{"error":{"code":"TooManyRequests","message":"slow down"}}',
              429,
              headers: {'Retry-After': '1'},
            );
          }
          return http.Response(
            jsonEncode({
              'Value': [
                {'Key': 'ConfirmOnDelete', 'Value': 'false'},
              ],
            }),
            200,
          );
        }

        if (request.url.path.endsWith('/tasks/t1') &&
            request.method == 'PATCH') {
          expect(request.headers['If-Match'], 'ck-1');
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'ErrorIrresolvableConflict',
                'message': 'conflict',
              },
            }),
            409,
          );
        }

        if (request.url.path.endsWith('/tasks/t412') &&
            request.method == 'PATCH') {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'PreconditionFailed',
                'message': 'precondition failed',
              },
            }),
            412,
          );
        }

        if (request.url.path.contains('tasks') &&
            request.url.queryParameters['deltatoken'] == 'expired') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'SyncStateInvalid', 'message': 'expired'},
            }),
            410,
          );
        }

        return http.Response('{}', 200);
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'CID:cid123',
      );

      final groups = (await api.fetchFolderGroupsDelta(ctx)).getOrThrow();
      expect(groups.items.length, 2);
      expect(groups.items.first.name, 'Group 1');
      expect(groups.items.last.name, 'Group 2');
      expect(groups.deltaLink, contains('deltatoken=g-dt'));

      final settings = (await api.getSettings(ctx)).getOrThrow();
      expect(settings['ConfirmOnDelete'], 'false');
      expect(throttledCalls, 2);

      final conflict409 = await api.patchTask(ctx, 't1', const {
        'Subject': 'x',
      }, changeKey: 'ck-1');
      expect(conflict409.exceptionOrNull()?.isConflict, isTrue);

      final conflict412 = await api.patchTask(ctx, 't412', const {
        'Subject': 'x',
      }, changeKey: 'ck-stale');
      expect(conflict412.exceptionOrNull()?.isConflict, isTrue);

      final expired410 = await api.fetchTasksDelta(
        ctx,
        folderRemoteId: 'f1',
        deltaLink: 'https://substrate.office.com/todob2/api/v1/tasks?deltatoken=expired',
      );
      expect(expired410.exceptionOrNull()?.isDeltaExpired, isTrue);
    });

    test('parses NDJSON realtime events and tracks own request IDs', () async {
      String? capturedReqId;
      final mockClient = MockClient.streaming((request, _) async {
        expect(request.headers['Long-Polling'], 'true');
        expect(request.headers['Accept-Encoding'], 'identity');
        capturedReqId = request.headers['X-Todo-Request-Id'];
        final body = [
          '{"Type":"KeepAlive"}',
          '',
          'not-json',
          '{"Id":"t1","Type":"Task","Operation":"Updated","RequestId":"other-req"}',
          '{"Id":"t2","Type":"Task","Operation":"Created","RequestId":"$capturedReqId"}',
        ].join('\n');
        return http.StreamedResponse(Stream.value(utf8.encode(body)), 200);
      });

      final api = HttpMicrosoftTodoApi(httpClient: mockClient);
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );
      final events = await api.connectRealtime(ctx).toList();
      expect(events.length, 3);
      expect(events[0].isKeepAlive, isTrue);
      expect(events[1].id, 't1');
      expect(api.isOwnRequestId(events[1].requestId), isFalse);
      expect(events[2].id, 't2');
      expect(api.isOwnRequestId(events[2].requestId), isTrue);
    });

    test('resolves relative NextLink, accepts lowercase nextLink/deltaLink, and stops on NextLink self-loop', () async {
      var pageCall = 0;
      final mockClient = MockClient((request) async {
        pageCall += 1;
        if (pageCall == 1) {
          return http.Response(
            jsonEncode({
              'value': [
                {'Id': 'g1', 'Name': 'Group 1'},
              ],
              'nextLink': 'foldergroups?page=2',
            }),
            200,
          );
        }
        if (pageCall == 2) {
          expect(
            request.url.toString(),
            'https://substrate.office.com/todob2/api/v1/foldergroups?page=2',
          );
          return http.Response(
            jsonEncode({
              'value': [
                {'Id': 'g2', 'Name': 'Group 2'},
              ],
              'nextLink': 'foldergroups?page=2',
              'deltaLink': 'https://substrate.office.com/todob2/api/v1/foldergroups?deltatoken=g-lower',
            }),
            200,
          );
        }
        fail('Should not loop on identical NextLink');
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );
      final groups = (await api.fetchFolderGroupsDelta(ctx)).getOrThrow();
      expect(pageCall, 2);
      expect(groups.items.map((g) => g.name).toList(), ['Group 1', 'Group 2']);
      expect(groups.deltaLink, contains('deltatoken=g-lower'));
    });

    test('two-phase initial/full fetch chains page-1 DeltaLink through NextLink to terminal DeltaLink', () async {
      final requestedUris = <Uri>[];
      final mockClient = MockClient((request) async {
        requestedUris.add(request.url);
        if (requestedUris.length == 1) {
          expect(request.url.queryParameters['parentFolderId'], 'f1');
          expect(request.url.queryParameters['deltatoken'], isNull);
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't1', 'Subject': 'Active 1', 'Status': 'NotStarted'},
              ],
              'DeltaLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=phase1',
            }),
            200,
          );
        }
        if (requestedUris.length == 2) {
          expect(request.url.queryParameters['deltatoken'], 'phase1');
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't2', 'Subject': 'Completed 1', 'Status': 'Completed'},
              ],
              'NextLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&skiptoken=p3',
            }),
            200,
          );
        }
        if (requestedUris.length == 3) {
          expect(request.url.queryParameters['skiptoken'], 'p3');
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't3', 'Subject': 'Completed 2', 'Status': 'Completed'},
              ],
              'DeltaLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=terminal',
            }),
            200,
          );
        }
        fail('Unexpected request #${requestedUris.length}: ${request.url}');
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );

      final res = (await api.fetchTasksDelta(
        ctx,
        folderRemoteId: 'f1',
      )).getOrThrow();

      expect(requestedUris.length, 3);
      expect(res.items.map((t) => t.id).toList(), ['t1', 't2', 't3']);
      expect(res.items.last.isCompleted, isTrue);
      expect(
        res.deltaLink,
        'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=terminal',
      );
    });

    test(
      'two-phase initial/full fetch terminates after empty Phase 2 DeltaLink',
      () async {
        final requestedTokens = <String?>[];
        final mockClient = MockClient((request) async {
          final dt = request.url.queryParameters['deltatoken'];
          requestedTokens.add(dt);
          if (requestedTokens.length == 1) {
            return http.Response(
              jsonEncode({
                'Value': [
                  {'Id': 't1', 'Subject': 'Only Head Task'},
                ],
                'DeltaLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=phase1',
              }),
              200,
            );
          }
          if (requestedTokens.length == 2) {
            return http.Response(
              jsonEncode({
                'Value': const [],
                'DeltaLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=terminal',
              }),
              200,
            );
          }
          fail('Should stop after Phase 2 returns terminal DeltaLink');
        });

        final api = HttpMicrosoftTodoApi(
          httpClient: mockClient,
          delayFn: (_) async {},
        );
        final ctx = SubstrateRequestContext(
          baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
          accessToken: 'tok',
          cid: 'cid1',
        );

        final res = (await api.fetchTasksDelta(
          ctx,
          folderRemoteId: 'f1',
        )).getOrThrow();

        expect(requestedTokens, [null, 'phase1']);
        expect(res.items.map((t) => t.id).toList(), ['t1']);
        expect(res.deltaLink, endsWith('deltatoken=terminal'));
      },
    );

    test('incremental delta fetch with non-null deltaLink stops after one request when DeltaLink is returned', () async {
      var calls = 0;
      final mockClient = MockClient((request) async {
        calls += 1;
        expect(request.url.queryParameters['deltatoken'], 'prev');
        return http.Response(
          jsonEncode({
            'Value': [
              {'Id': 't1', 'Subject': 'Updated Task'},
            ],
            'DeltaLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=next',
          }),
          200,
        );
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );

      final res = (await api.fetchTasksDelta(
        ctx,
        folderRemoteId: 'f1',
        deltaLink: 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=prev',
      )).getOrThrow();

      expect(calls, 1);
      expect(res.items.map((t) => t.id).toList(), ['t1']);
      expect(res.deltaLink, endsWith('deltatoken=next'));
    });

    test('Phase 2 cyclic NextLink without DeltaLink stops without leaking Phase 1 checkpoint DeltaLink', () async {
      var calls = 0;
      final mockClient = MockClient((request) async {
        calls += 1;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't1', 'Subject': 'Task 1'},
              ],
              'DeltaLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=phase1',
            }),
            200,
          );
        }
        if (calls == 2) {
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't2', 'Subject': 'Task 2'},
              ],
              'NextLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&skiptoken=loop',
            }),
            200,
          );
        }
        if (calls == 3) {
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't3', 'Subject': 'Task 3'},
              ],
              'NextLink': 'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&skiptoken=loop',
            }),
            200,
          );
        }
        fail('Should stop on Phase 2 NextLink self-loop');
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );

      final res = (await api.fetchTasksDelta(
        ctx,
        folderRemoteId: 'f1',
      )).getOrThrow();

      expect(calls, 3);
      expect(res.items.map((t) => t.id).toList(), ['t1', 't2', 't3']);
      expect(res.deltaLink, isNull);
    });

    test('resolves relative DeltaLink values to full URIs across Phase 1 and Phase 2', () async {
      final requestedUrls = <String>[];
      final mockClient = MockClient((request) async {
        requestedUrls.add(request.url.toString());
        if (requestedUrls.length == 1) {
          return http.Response(
            jsonEncode({
              'Value': [
                {'Id': 't1', 'Subject': 'Task 1'},
              ],
              'DeltaLink': 'tasks?parentFolderId=f1&deltatoken=rel-p1',
            }),
            200,
          );
        }
        if (requestedUrls.length == 2) {
          return http.Response(
            jsonEncode({
              'Value': const [],
              'DeltaLink': 'tasks?parentFolderId=f1&deltatoken=rel-final',
            }),
            200,
          );
        }
        fail('Unexpected request #${requestedUrls.length}');
      });

      final api = HttpMicrosoftTodoApi(
        httpClient: mockClient,
        delayFn: (_) async {},
      );
      final ctx = SubstrateRequestContext(
        baseUrl: MsaAuthConfig.defaultTodoApiBaseUrl,
        accessToken: 'tok',
        cid: 'cid1',
      );

      final res = (await api.fetchTasksDelta(
        ctx,
        folderRemoteId: 'f1',
      )).getOrThrow();

      expect(requestedUrls, [
        'https://substrate.office.com/todob2/api/v1/tasks?\$expand=LinkedEntities&parentFolderId=f1&maxPageSize=50',
        'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=rel-p1',
      ]);
      expect(
        res.deltaLink,
        'https://substrate.office.com/todob2/api/v1/tasks?parentFolderId=f1&deltatoken=rel-final',
      );
    });
  });
}
