import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:storely/screens/premium_request_screen.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/cloud/premium_request_service.dart';

class ReceiptMemory implements PremiumReceiptStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async {
    value = v;
  }
}

ApiClient client(http.Client transport) => ApiClient(
  baseUrl: Uri.parse('https://api.test'),
  httpClient: transport,
  tokens: MemoryTokenStore(),
);

void main() {
  test(
    'lost submission response retries exactly the durable request, with no business records',
    () async {
      final store = ReceiptMemory();
      final bodies = <Map<String, dynamic>>[];
      final api = client(
        MockClient((request) async {
          expect(store.value, isNotNull); // persisted before HTTP
          expect(request.headers['authorization'], isNull);
          expect(request.url.query, isEmpty);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          bodies.add(body);
          expect(body.keys.toSet(), {
            'id',
            'receipt_secret',
            'local_shop_id',
            'shop_name',
            'contact_name',
            'phone',
            'contact_consent',
          });
          if (bodies.length == 1) throw http.ClientException('No connection');
          return http.Response(
            jsonEncode({'id': body['id'], 'status': 'pending'}),
            201,
          );
        }),
      );
      var service = PremiumRequestService(api: api, store: store);
      expect(await service.load(), isNull);
      expect(bodies, isEmpty);
      await expectLater(
        service.submit(
          shopId: 'shop-local-123',
          shopName: 'My shop',
          contactName: 'Owner',
          phone: '+919876543210',
        ),
        throwsA(isA<http.ClientException>()),
      );
      expect(
        (await service.load())!['response'],
        isNull,
      ); // not falsely pending
      service = PremiumRequestService(api: api, store: store); // app restart
      await service.submit(
        shopId: 'shop-local-123',
        shopName: 'Changed display',
        contactName: 'Changed name',
        phone: '+919111111111',
      );
      expect(bodies[1], bodies[0]);
      expect((await service.load())!['response']['status'], 'pending');
      expect((await service.load())!['upload_user'], isNull);
      api.dispose();
    },
  );

  test(
    'saved request cannot send its receipt to a different API origin',
    () async {
      final store = ReceiptMemory()
        ..value = jsonEncode({
          'api_origin': 'https://old.test',
          'body': {'receipt_secret': 'private'},
        });
      var calls = 0;
      final api = client(
        MockClient((request) async {
          calls++;
          return http.Response('{}', 200);
        }),
      );
      final service = PremiumRequestService(api: api, store: store);
      await expectLater(service.refresh(), throwsA(isA<StateError>()));
      expect(calls, 0);
      api.dispose();
    },
  );

  test('status uses the saved private receipt without an account', () async {
    final store = ReceiptMemory();
    final api = client(
      MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/status')) {
          expect(body.keys, ['receipt_secret']);
          expect(request.headers['authorization'], isNull);
          return http.Response(jsonEncode({'status': 'approved'}), 200);
        }
        return http.Response(jsonEncode({'status': 'pending'}), 201);
      }),
    );
    final service = PremiumRequestService(api: api, store: store);
    await service.submit(
      shopId: 'shop-local-123',
      shopName: 'Shop',
      contactName: 'Owner',
      phone: '+919876543210',
    );
    await service.refresh();
    expect((await service.load())!['response']['status'], 'approved');
    expect(
      (await service.load())!['upload_user'],
      isNull,
    ); // approval isn't upload consent
    api.dispose();
  });

  test(
    'sync selects this local shop when the account owns multiple shops',
    () async {
      final api = client(
        MockClient(
          (request) async => http.Response(
            jsonEncode([
              {'shop_id': 'older-shop'},
              {'shop_id': 'this-local-shop'},
            ]),
            200,
          ),
        ),
      );
      api.adoptUser(const ApiUser(id: 'user', email: 'owner@example.com'));
      // Auth needs tokens; login is handled by this fixture's first refresh.
      final transport = MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'access_token': 'a',
              'refresh_token': 'r',
              'expires_in': 900,
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/me')) {
          return http.Response('{"id":"u","email":"owner@example.com"}', 200);
        }
        return http.Response(
          '[{"shop_id":"older-shop"},{"shop_id":"this-local-shop"}]',
          200,
        );
      });
      final authed = client(transport);
      await authed.login('owner@example.com', 'test-password');
      final backend = ApiSyncBackend(
        authed,
        preferredShopId: () async => 'this-local-shop',
      );
      expect(await backend.resolveMembershipShopId(), 'this-local-shop');
      api.dispose();
      authed.dispose();
    },
  );

  testWidgets('request UI stays not sent when offline and preserves a retry', (
    tester,
  ) async {
    final store = ReceiptMemory();
    var calls = 0;
    final api = client(
      MockClient((request) async {
        calls++;
        throw http.ClientException('Offline');
      }),
    );
    final service = PremiumRequestService(api: api, store: store);
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumRequestScreen(
          requests: service,
          shopId: 'shop-local-123',
          shopName: 'Local Shop',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField).at(0), 'Owner');
    await tester.enterText(find.byType(TextFormField).at(1), '+919876543210');
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.ensureVisible(find.text('Send premium request'));
    await tester.tap(find.text('Send premium request'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Not sent — retry your saved request'), findsOneWidget);
    expect(find.text('Retry saved request'), findsOneWidget);
    expect(find.text('Request: pending'), findsNothing);
    api.dispose();
  });
}
