import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/purchase_api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/sync_backend.dart';

void main() {
  Future<PurchaseApiSyncBackend> backend(
    http.Response Function(http.Request) route,
  ) async {
    final api = ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/auth/login') {
          return http.Response(
            jsonEncode({
              'access_token': 'a',
              'refresh_token': 'r',
              'expires_in': 900,
            }),
            200,
          );
        }
        if (request.url.path == '/v1/me') {
          return http.Response(
            jsonEncode({'id': 'u', 'email': 'a@b.com'}),
            200,
          );
        }
        return route(request);
      }),
    );
    await api.login('a@b.com', 'pw');
    return PurchaseApiSyncBackend(api);
  }

  test(
    'publishes original device fields without server audit metadata',
    () async {
      final transport = await backend((request) {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/shops/s/purchase-receipts/native');
        final body = jsonDecode(request.body) as Map;
        expect(body['uuid'], 'receipt');
        expect(body['created_at'], 'device-time');
        expect(body['items'], [
          {'quantity': '1.25', 'unit_cost': '3.50'},
        ]);
        expect(body.containsKey('change_sequence'), false);
        expect(body.containsKey('device_created_at'), false);
        return http.Response(jsonEncode({'uuid': 'receipt'}), 200);
      });
      expect(
        await transport.publishNativePurchase('s', {
          'uuid': 'receipt',
          'created_at': 'device-time',
          'change_sequence': 10,
          'device_created_at': 'audit-time',
          'items': [
            {'quantity': '1.25', 'unit_cost': '3.50'},
          ],
        }),
        {'uuid': 'receipt'},
      );
    },
  );

  test('whole document feed uses sequence and page size', () async {
    final transport = await backend((request) {
      expect(request.url.path, '/v1/shops/s/purchase-receipts/changes');
      expect(request.url.queryParameters, {
        'after_sequence': '42',
        'limit': '25',
      });
      return http.Response(
        jsonEncode([
          {'uuid': 'r', 'change_sequence': 43},
        ]),
        200,
      );
    });
    expect(
      await transport.pullPurchaseDocuments('s', afterSequence: 42, limit: 25),
      [
        {'uuid': 'r', 'change_sequence': 43},
      ],
    );
  });

  for (final status in [403, 409, 422, 408, 429, 503]) {
    test('HTTP $status retains the appropriate retry classification', () async {
      final transport = await backend(
        (_) => http.Response(
          jsonEncode({
            'error': {'code': 'test_error', 'message': 'Review purchase'},
          }),
          status,
        ),
      );
      await expectLater(
        transport.publishNativePurchase('s', {'uuid': 'r'}),
        throwsA(
          status == 408 || status == 429 || status >= 500
              ? isA<ApiException>()
              : isA<SyncRowRejected>(),
        ),
      );
    });
  }
}
