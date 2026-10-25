import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/sync_backend.dart';

http.Response json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

/// A signed-in client whose server is [routes].
Future<(ApiSyncBackend, List<String>, Map<String, Object?>)> backendFor(
  Map<String, http.Response Function(http.Request)> routes,
) async {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final client = MockClient((request) async {
    final key = '${request.method} ${request.url.path}';
    calls.add(key);
    bodies[key] = request.body.isEmpty ? null : jsonDecode(request.body);
    if (key == 'POST /v1/auth/login') {
      return json({
        'access_token': 'a',
        'refresh_token': 'r',
        'expires_in': 900,
      });
    }
    if (key == 'GET /v1/me') {
      return json({'id': 'u1', 'email': 'a@b.com', 'email_verified': true});
    }
    final handler = routes[key];
    return handler == null
        ? json({
            'error': {'code': 'x', 'message': 'no route $key'},
          }, 404)
        : handler(request);
  });
  final api = ApiClient(
    baseUrl: Uri.parse('https://api.test'),
    httpClient: client,
    tokens: MemoryTokenStore(),
  );
  await api.login('a@b.com', 'pw');
  calls.clear();
  return (ApiSyncBackend(api), calls, bodies);
}

void main() {
  group('resolveMembershipShopId', () {
    test(
      'an existing member gets their first shop and nothing else is called',
      () async {
        final (backend, calls, _) = await backendFor({
          'GET /v1/shops': (_) => json([
            {'shop_id': 's-old', 'name': 'Old', 'role': 'owner'},
            {'shop_id': 's-new', 'name': 'New', 'role': 'staff'},
          ]),
        });
        expect(await backend.resolveMembershipShopId(), 's-old');
        expect(calls, ['GET /v1/shops']);
      },
    );

    test('an invited person accepts the invite and joins', () async {
      final (backend, calls, bodies) = await backendFor({
        'GET /v1/shops': (_) => json([]),
        'GET /v1/invites/pending': (_) => json([
          {'shop_id': 's-invited', 'role': 'staff'},
        ]),
        'POST /v1/invites/accept': (_) => json({'status': 'joined'}),
      });
      expect(await backend.resolveMembershipShopId(), 's-invited');
      expect(bodies['POST /v1/invites/accept'], {'shop_id': 's-invited'});
      expect(calls, [
        'GET /v1/shops',
        'GET /v1/invites/pending',
        'POST /v1/invites/accept',
      ]);
    });

    test('someone with no shop and no invite is told to register', () async {
      final (backend, _, _) = await backendFor({
        'GET /v1/shops': (_) => json([]),
        'GET /v1/invites/pending': (_) => json([]),
      });
      expect(await backend.resolveMembershipShopId(), isNull);
    });

    test(
      'a failure while accepting an invite is not mistaken for "no shop"',
      () async {
        final (backend, _, _) = await backendFor({
          'GET /v1/shops': (_) => json([]),
          'GET /v1/invites/pending': (_) => json([
            {'shop_id': 's', 'role': 'staff'},
          ]),
          'POST /v1/invites/accept': (_) => json({
            'error': {'code': 'rate_limited', 'message': 'Slow down.'},
          }, 429),
        });
        await expectLater(
          backend.resolveMembershipShopId(),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });

  group('isShopAdmin', () {
    for (final entry in {
      'owner': true,
      'admin': true,
      'staff': false,
    }.entries) {
      test('${entry.key} -> ${entry.value}', () async {
        final (backend, _, _) = await backendFor({
          'GET /v1/shops/s1/role': (_) => json({'role': entry.key}),
        });
        expect(await backend.isShopAdmin('s1'), entry.value);
      });
    }

    test('not a member of that shop is simply not an admin', () async {
      final (backend, _, _) = await backendFor({
        'GET /v1/shops/s1/role': (_) => json({
          'error': {'code': 'not_found', 'message': 'No such shop.'},
        }, 404),
      });
      expect(await backend.isShopAdmin('s1'), isFalse);
    });

    test(
      'an unknown role must throw, never quietly mean "not admin"',
      () async {
        final (backend, _, _) = await backendFor({
          'GET /v1/shops/s1/role': (_) => json({
            'error': {
              'code': 'internal_error',
              'message': 'Something went wrong.',
            },
          }, 500),
        });
        await expectLater(
          backend.isShopAdmin('s1'),
          throwsA(isA<ApiException>()),
        );
      },
    );
  });

  group('pullPage', () {
    test('sends the cursor and returns the rows', () async {
      final (backend, _, bodies) = await backendFor({
        'POST /v1/shops/s1/sync/pull': (_) => json({
          'rows': [
            {
              'uuid': 'p1',
              'server_updated_at': '2026-10-25T09:00:00.123456+00:00',
            },
          ],
        }),
      });
      final rows = await backend.pullPage(
        'products',
        shopId: 's1',
        afterTs: DateTime.utc(2026, 10, 1),
        afterKey: 'k',
        limit: 7,
      );
      expect(rows.single['uuid'], 'p1');
      expect(bodies['POST /v1/shops/s1/sync/pull'], {
        'table': 'products',
        'after_ts': '2026-10-01T00:00:00.000Z',
        'after_key': 'k',
        'limit': 7,
      });
    });

    test('an empty page is an empty list', () async {
      final (backend, _, _) = await backendFor({
        'POST /v1/shops/s1/sync/pull': (_) => json({'rows': []}),
      });
      expect(
        await backend.pullPage(
          'bills',
          shopId: 's1',
          afterTs: DateTime.utc(1970),
          afterKey: '',
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('upsert', () {
    test(
      'uploads under the rows\' shop and returns when all are accepted',
      () async {
        final (backend, _, bodies) = await backendFor({
          'POST /v1/shops/s1/sync/push': (_) =>
              json({'accepted': 1, 'rejected': []}),
        });
        await backend.upsert('customers', [
          {'uuid': 'c1', 'shop_id': 's1', 'name': 'Ravi'},
        ]);
        final sent = bodies['POST /v1/shops/s1/sync/push'] as Map;
        expect(sent['table'], 'customers');
        expect((sent['rows'] as List).single, containsPair('uuid', 'c1'));
      },
    );

    test('the shops table is addressed by its own id', () async {
      final (backend, calls, _) = await backendFor({
        'POST /v1/shops/s1/sync/push': (_) =>
            json({'accepted': 1, 'rejected': []}),
      });
      await backend.upsert('shops', [
        {'uuid': 's1', 'name': 'Sharma'},
      ]);
      expect(calls, ['POST /v1/shops/s1/sync/push']);
    });

    test(
      'a refused row becomes SyncRowRejected with the server\'s reason',
      () async {
        final (backend, _, _) = await backendFor({
          'POST /v1/shops/s1/sync/push': (_) => json({
            'accepted': 0,
            'rejected': [
              {
                'key': 'p1',
                'message': 'Your role is not allowed to change this record.',
              },
            ],
          }),
        });
        await expectLater(
          backend.upsert('products', [
            {'uuid': 'p1', 'shop_id': 's1'},
          ]),
          throwsA(
            isA<SyncRowRejected>().having(
              (e) => e.message,
              'message',
              'Your role is not allowed to change this record.',
            ),
          ),
        );
      },
    );

    test(
      'a network or server failure is NOT a row rejection (it must not become a conflict)',
      () async {
        final (backend, _, _) = await backendFor({
          'POST /v1/shops/s1/sync/push': (_) => json({
            'error': {
              'code': 'internal_error',
              'message': 'Something went wrong.',
            },
          }, 500),
        });
        await expectLater(
          backend.upsert('products', [
            {'uuid': 'p1', 'shop_id': 's1'},
          ]),
          throwsA(isA<ApiException>()),
        );
      },
    );

    test('nothing to upload makes no request', () async {
      final (backend, calls, _) = await backendFor({});
      await backend.upsert('products', []);
      expect(calls, isEmpty);
    });
  });

  test(
    'registerDevice returns the bill-number letter (empty for the first phone)',
    () async {
      final (backend, _, bodies) = await backendFor({
        'POST /v1/devices/register': (_) => json({'code': ''}),
      });
      expect(await backend.registerDevice('s1', 'device-1234'), '');
      expect(bodies['POST /v1/devices/register'], {
        'shop_id': 's1',
        'device_id': 'device-1234',
      });
    },
  );
}
