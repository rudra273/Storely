import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/purchase_api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/sync_backend.dart';
import 'package:storely/services/sync/purchase_sync_backend.dart';

void main() {
  Future<PurchaseApiSyncBackend> backend(
    http.Response Function(http.Request) route, {
    http.Response Function(http.Request)? capabilitiesRoute,
  }) async {
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
        if (request.url.path == '/v1/auth/refresh') {
          return http.Response(
            jsonEncode({
              'error': {'code': 'invalid_token', 'message': 'Sign in again.'},
            }),
            401,
          );
        }
        if (request.url.path.endsWith('/capabilities')) {
          return capabilitiesRoute?.call(request) ??
              http.Response(
                jsonEncode({
                  'error': {'code': 'http_404', 'message': 'Not Found'},
                }),
                404,
              );
        }
        return route(request);
      }),
    );
    await api.login('a@b.com', 'pw');
    return PurchaseApiSyncBackend(api);
  }

  Map<String, dynamic> capabilities({int proof = 1}) => {
    'contract_version': 1,
    'shop_id': 's',
    'role': 'owner',
    'features': {
      'operation_lookup': 1,
      'supplier_payment_proof': proof,
      'supplier_payment_binding': 2,
      'product_expected_updated_at': 1,
    },
  };

  test(
    'fresh capability negotiation can disable proof without using cached support',
    () async {
      var checks = 0;
      var proofs = 0;
      final transport = await backend(
        (request) {
          proofs++;
          return http.Response(
            jsonEncode({
              'contract_version': 1,
              'status': 'not_found',
              'uuid': null,
              'request_binding_version': null,
            }),
            200,
          );
        },
        capabilitiesRoute: (request) {
          expect(request.method, 'GET');
          checks++;
          return http.Response(
            jsonEncode(capabilities(proof: checks == 1 ? 1 : 0)),
            200,
          );
        },
      );
      expect(
        (await transport.recoverSupplierPayment('s', 'vendor', {})).status,
        SupplierPaymentRecoveryStatus.notFound,
      );
      expect(
        (await transport.recoverSupplierPayment('s', 'vendor', {})).status,
        SupplierPaymentRecoveryStatus.unsupported,
      );
      expect(checks, 2);
      expect(proofs, 1);
    },
  );

  test(
    'capability role is metadata and never substitutes for command authorization',
    () async {
      var proofs = 0;
      final transport = await backend(
        (_) {
          proofs++;
          return http.Response(
            jsonEncode({
              'error': {'code': 'no_permission', 'message': 'Denied'},
            }),
            403,
          );
        },
        capabilitiesRoute: (_) => http.Response(
          jsonEncode({...capabilities(), 'role': 'staff'}),
          200,
        ),
      );
      await expectLater(
        transport.recoverSupplierPayment('s', 'vendor', {}),
        throwsA(isA<ApiException>()),
      );
      expect(proofs, 1);
    },
  );

  test(
    'capability identity/version errors fail before proof or payment dispatch',
    () async {
      for (final invalid in [
        {...capabilities(), 'contract_version': 2},
        {...capabilities(), 'shop_id': 'other-shop'},
        {...capabilities(), 'role': 'invalid'},
        {...capabilities(), 'features': null},
        {
          ...capabilities(),
          'features': {'supplier_payment_proof': 2},
        },
        {
          ...capabilities(),
          'features': {'supplier_payment_proof': '1'},
        },
      ]) {
        var proofs = 0;
        final transport = await backend((_) {
          proofs++;
          throw StateError('No dispatch');
        }, capabilitiesRoute: (_) => http.Response(jsonEncode(invalid), 200));
        await expectLater(
          transport.recoverSupplierPayment('s', 'vendor', {}),
          throwsFormatException,
        );
        expect(proofs, 0);
      }
    },
  );

  test(
    'capability access and network failures never become unsupported service',
    () async {
      for (final status in [401, 403, 404, 429, 503]) {
        var dispatches = 0;
        final transport = await backend(
          (_) {
            dispatches++;
            throw StateError('No dispatch');
          },
          capabilitiesRoute: (_) => http.Response(
            jsonEncode({
              'error': {'code': 'not_found', 'message': 'Denied'},
            }),
            status,
          ),
        );
        await expectLater(
          transport.recoverSupplierPayment('s', 'vendor', {}),
          throwsA(isA<ApiException>()),
        );
        expect(dispatches, 0);
      }
      final transport = await backend(
        (_) => throw StateError('No dispatch'),
        capabilitiesRoute: (_) => throw StateError('Network unavailable'),
      );
      await expectLater(
        transport.recoverSupplierPayment('s', 'vendor', {}),
        throwsStateError,
      );
    },
  );

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

  test(
    'payment recovery posts the exact body to its supplier and accepts bound proof',
    () async {
      final payload = {
        'request_key': 'stable-key',
        'amount': '4.00',
        'payment_date': '2026-10-01',
      };
      final transport = await backend((request) {
        expect(request.method, 'POST');
        expect(
          request.url.path,
          '/v1/shops/s/suppliers/vendor/payments/recover',
        );
        expect(jsonDecode(request.body), payload);
        return http.Response(
          jsonEncode({
            'contract_version': 1,
            'status': 'committed',
            'uuid': 'payment-id',
            'request_binding_version': 2,
          }),
          200,
        );
      });
      final result = await transport.recoverSupplierPayment(
        's',
        'vendor',
        payload,
      );
      expect(result.status, SupplierPaymentRecoveryStatus.committed);
      expect(result.uuid, 'payment-id');
    },
  );

  test(
    'payment recovery supports v1 proof, not-found and only route fallback',
    () async {
      for (final (body, status, expected) in [
        (
          {
            'contract_version': 1,
            'status': 'committed',
            'uuid': 'p',
            'request_binding_version': 1,
          },
          200,
          SupplierPaymentRecoveryStatus.committed,
        ),
        (
          {
            'contract_version': 1,
            'status': 'not_found',
            'uuid': null,
            'request_binding_version': null,
          },
          200,
          SupplierPaymentRecoveryStatus.notFound,
        ),
        (
          {
            'error': {'code': 'http_404', 'message': 'Not Found'},
          },
          404,
          SupplierPaymentRecoveryStatus.unsupported,
        ),
        (
          {
            'error': {'code': 'http_405', 'message': 'Method Not Allowed'},
          },
          405,
          SupplierPaymentRecoveryStatus.unsupported,
        ),
      ]) {
        final transport = await backend(
          (_) => http.Response(jsonEncode(body), status),
        );
        expect(
          (await transport.recoverSupplierPayment('s', 'vendor', {
            'request_key': 'key',
          })).status,
          expected,
        );
      }
    },
  );

  test(
    'payment recovery refuses malformed proof and never converts denial to not-found',
    () async {
      for (final body in [
        {'contract_version': 1, 'status': 'not_found'},
        {
          'contract_version': 2,
          'status': 'committed',
          'uuid': 'p',
          'request_binding_version': 2,
        },
        {
          'contract_version': 1,
          'status': 'committed',
          'uuid': '',
          'request_binding_version': 2,
        },
        {
          'contract_version': 1,
          'status': 'committed',
          'uuid': 'p',
          'request_binding_version': null,
        },
        {
          'contract_version': 1,
          'status': 'not_found',
          'uuid': 'p',
          'request_binding_version': null,
        },
      ]) {
        final transport = await backend(
          (_) => http.Response(jsonEncode(body), 200),
        );
        await expectLater(
          transport.recoverSupplierPayment('s', 'vendor', {}),
          throwsFormatException,
        );
      }
      for (final status in [403, 404, 409, 429, 503]) {
        final transport = await backend(
          (_) => http.Response(
            jsonEncode({
              'error': {'code': 'not_found', 'message': 'Denied'},
            }),
            status,
          ),
        );
        await expectLater(
          transport.recoverSupplierPayment('s', 'vendor', {}),
          throwsA(isA<ApiException>()),
        );
      }
    },
  );

  for (final status in [403, 409, 422, 408, 429, 503]) {
    test(
      'supplier HTTP $status preserves conflict versus retry classification',
      () async {
        final transport = await backend(
          (_) => http.Response(
            jsonEncode({
              'error': {'code': 'test_error', 'message': 'Review payment'},
            }),
            status,
          ),
        );
        await expectLater(
          transport.publishSupplierPayment('s', 'supplier', {
            'request_key': 'stable-key',
          }),
          throwsA(
            status == 408 || status == 429 || status >= 500
                ? isA<ApiException>()
                : isA<SyncRowRejected>().having(
                    (e) => e.isConflict,
                    'isConflict',
                    status == 409,
                  ),
          ),
        );
      },
    );
  }

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
