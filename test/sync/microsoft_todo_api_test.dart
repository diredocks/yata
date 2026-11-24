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
  });
}
