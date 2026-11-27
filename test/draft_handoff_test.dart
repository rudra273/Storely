import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/cloud/api_cloud_backend.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/utils/test_keys.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response _failure(int status, String code, String message) => _json({
  'error': {'code': code, 'message': message},
}, status);

const _tokens = {'access_token': 'tok-1', 'refresh_token': 'ref-1', 'expires_in': 900};
const _me = {'id': 'u1', 'email': 'owner@shop.test', 'email_verified': true};

class _HandoffServerHarness {
  final calls = <String>[];
  final bodies = <String, Object?>{};
  final routes = <String, http.Response Function(http.Request)>{};
  late final ApiClient api;
  late final ApiCloudBackend backend;

  _HandoffServerHarness({String deviceLabel = 'Counter Phone'}) {
    routes['POST /v1/auth/login'] = (_) => _json(_tokens);
    routes['GET /v1/me'] = (_) => _json(_me);
    api = ApiClient(
      baseUrl: Uri.parse('https://api.test'),
      httpClient: MockClient((request) async {
        final key = '${request.method} ${request.url.path}';
        calls.add(key);
        bodies[key] = request.body.isEmpty ? null : jsonDecode(request.body);
        final handler = routes[key];
        if (handler == null) {
          return _failure(404, 'not_found', 'no route $key');
        }
        return handler(request);
      }),
      tokens: MemoryTokenStore(),
    );
    backend = ApiCloudBackend(api, deviceLabel: deviceLabel);
  }

  Future<void> signIn() async {
    final user = await backend.signIn('owner@shop.test', 'pw');
    CloudService.instance.setBackendForTesting(backend);
    CloudService.instance.state.value = CloudState(
      config: const CloudConfig.api('https://api.test'),
      user: user,
      membership: CloudMembership.member,
      shopRole: 'owner',
    );
  }

  void dispose() {
    api.dispose();
  }
}

Future<void> _settleIo(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openScanScreen(
  WidgetTester tester, {
  Bill? duplicateFromBill,
}) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ScanScreen(
        initialMode: BillingEntryMode.manual,
        duplicateFromBill: duplicateFromBill,
      ),
    ),
  );
  await _settleIo(tester);
}

void main() {
  final db = DatabaseHelper.instance;
  late CloudState originalCloudState;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    originalCloudState = CloudService.instance.state.value;
    CloudService.instance.setBackendForTesting(null);
    CloudService.instance.state.value = const CloudState();
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'draft-handoff-test.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveBillSettings(BillSettings());
  });

  tearDown(() async {
    CloudService.instance.setBackendForTesting(null);
    CloudService.instance.state.value = originalCloudState;
    db.onDatabaseChanged = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  group('CloudService draft handoff API client', () {
    test('publish, list, claim, 409 conflict, and discard', () async {
      final shopId = await db.currentShopId();
      final harness = _HandoffServerHarness(deviceLabel: 'Cashier Phone');
      addTearDown(harness.dispose);
      await harness.signIn();

      var claimedOnce = false;
      harness.routes['POST /v1/shops/$shopId/draft-handoffs'] = (request) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        return _json({
          'uuid': 'h-1',
          'source_device_label': body['source_device_label'],
          'label': body['label'],
          'item_count': (body['items'] as List).length,
          'items': body['items'],
          'metadata': body['metadata'],
          'status': 'available',
          'claimed_by_device': null,
          'claimed_at': null,
          'created_at': '2026-11-27T10:00:00Z',
        }, 201);
      };
      harness.routes['GET /v1/shops/$shopId/draft-handoffs'] = (_) => _json({
        'items': [
          {
            'uuid': 'h-1',
            'source_device_label': 'Web POS',
            'label': 'Walk-in cart',
            'item_count': 2,
            'status': 'available',
            'created_at': '2026-11-27T10:00:00Z',
          },
        ],
      });
      harness.routes['POST /v1/shops/$shopId/draft-handoffs/h-1/claim'] =
          (request) {
            if (claimedOnce) {
              return _failure(
                409,
                'draft_already_claimed',
                'Draft handoff already claimed',
              );
            }
            claimedOnce = true;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            return _json({
              'uuid': 'h-1',
              'source_device_label': 'Web POS',
              'label': 'Walk-in cart',
              'item_count': 1,
              'items': [
                {
                  'name': 'Web Tea Pack',
                  'price': 85.0,
                  'qty': 2,
                  'gst_percent': 5.0,
                },
              ],
              'metadata': {
                'version': 1,
                'raw': {'name': 'Riya', 'notes': 'Pack separately'},
              },
              'status': 'claimed',
              'claimed_by_device': body['device_label'],
              'claimed_at': '2026-11-27T10:01:00Z',
              'created_at': '2026-11-27T10:00:00Z',
            });
          };
      harness.routes['DELETE /v1/shops/$shopId/draft-handoffs/h-2'] = (_) =>
          http.Response('', 204);
      harness.routes['DELETE /v1/shops/$shopId/draft-handoffs/h-1'] = (_) =>
          _failure(409, 'draft_already_claimed', 'Already claimed');

      final published = await CloudService.instance.publishDraftHandoff(
        label: 'Counter cart',
        items: [
          BillItem(
            productName: 'Sugar 1kg',
            quantity: 2,
            sellingPriceSnapshot: 50,
          ).toMap(0),
        ],
        metadata: {
          'version': 1,
          'raw': {'name': 'Asha'},
        },
      );
      expect(published.uuid, 'h-1');
      expect(published.sourceDeviceLabel, 'Cashier Phone');
      expect(published.itemCount, 1);

      final listed = await CloudService.instance.listDraftHandoffs();
      expect(listed, hasLength(1));
      expect(listed.single.uuid, 'h-1');
      expect(listed.single.sourceDeviceLabel, 'Web POS');
      expect(listed.single.itemCount, 2);

      final claimed = await CloudService.instance.claimDraftHandoff('h-1');
      expect(claimed.status, 'claimed');
      expect(claimed.claimedByDevice, 'Cashier Phone');
      final hydratedItems = claimed.toBillItems();
      expect(hydratedItems, hasLength(1));
      expect(hydratedItems.single.productName, 'Web Tea Pack');
      expect(hydratedItems.single.quantity, 2);
      expect(hydratedItems.single.sellingPriceSnapshot, 85);

      await expectLater(
        CloudService.instance.claimDraftHandoff('h-1'),
        throwsA(
          isA<DraftHandoffAlreadyClaimedException>().having(
            (e) => e.message,
            'message',
            'This cart was already claimed on another device.',
          ),
        ),
      );

      await CloudService.instance.discardDraftHandoff('h-2');
      expect(
        harness.calls,
        contains('DELETE /v1/shops/$shopId/draft-handoffs/h-2'),
      );

      await expectLater(
        CloudService.instance.discardDraftHandoff('h-1'),
        throwsA(isA<DraftHandoffAlreadyClaimedException>()),
      );
    });
  });

  group('ScanScreen & _HeldBillsSheet draft handoff UI', () {
    testWidgets('local-only mode hides cloud handoff UI completely', (
      tester,
    ) async {
      await _openScanScreen(
        tester,
        duplicateFromBill: Bill(
          uuid: 'orig-1',
          totalAmount: 100,
          itemCount: 1,
          items: [
            BillItem(
              productName: 'Local Milk',
              quantity: 1,
              sellingPriceSnapshot: 100,
            ),
          ],
        ),
      );

      // Local-only mode: no Send to another device button and no Held button when 0 held bills.
      expect(
        find.byKey(const ValueKey('checkout-send-handoff')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('checkout-held-list')), findsNothing);

      // Hold the bill locally and verify _HeldBillsSheet hides Cloud handoffs.
      await tester.tap(find.byKey(const ValueKey('checkout-hold')));
      await _settleIo(tester);

      expect(find.byKey(const ValueKey('checkout-held-list')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('checkout-held-list')));
      await _settleIo(tester);

      expect(find.text('Cloud handoffs'), findsNothing);
      expect(find.textContaining('Local Milk'), findsWidgets);

      await tester.pumpWidget(const SizedBox());
      await _settleIo(tester);
    });

    testWidgets(
      'Send to another device publishes cart + metadata and clears local cart',
      (tester) async {
        final shopId = (await tester.runAsync(db.currentShopId))!;
        final harness = _HandoffServerHarness(deviceLabel: 'Front Phone');
        addTearDown(harness.dispose);
        await tester.runAsync(harness.signIn);

        Map<String, dynamic>? publishedBody;
        harness.routes['GET /v1/shops/$shopId/draft-handoffs'] = (_) =>
            _json({'items': []});
        harness.routes['POST /v1/shops/$shopId/draft-handoffs'] = (request) {
          publishedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return _json({
            'uuid': 'h-pub-1',
            'source_device_label': publishedBody!['source_device_label'],
            'label': publishedBody!['label'],
            'item_count': (publishedBody!['items'] as List).length,
            'items': publishedBody!['items'],
            'metadata': publishedBody!['metadata'],
            'status': 'available',
            'created_at': '2026-11-27T10:00:00Z',
          }, 201);
        };

        // Pre-populate a saved draft with checkout metadata so we verify metadata upload.
        final scope = (await tester.runAsync(() async {
          final scope = await db.captureCheckoutScope();
          final savedCart = await db.saveCartDraft(
            [
              BillItem(
                productName: 'Basmati Rice',
                quantity: 2,
                sellingPriceSnapshot: 120,
              ),
            ],
            expectedScope: scope,
          );
          await db.writeCheckoutState(savedCart!, {
            'version': 1,
            'raw': {'name': 'Kiran', 'notes': 'Deliver evening'},
          });
          return scope;
        }))!;

        await _openScanScreen(tester);
        expect(find.text('Basmati Rice'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('checkout-send-handoff')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const ValueKey('checkout-send-handoff')));
        await _settleIo(tester);

        expect(publishedBody, isNotNull);
        expect(publishedBody!['source_device_label'], 'Front Phone');
        expect((publishedBody!['items'] as List), hasLength(1));
        expect(
          ((publishedBody!['metadata'] as Map)['raw'] as Map)['name'],
          'Kiran',
        );
        expect(find.text('Basmati Rice'), findsNothing);
        expect(
          find.textContaining('Sent to another device:'),
          findsOneWidget,
        );

        final afterCart = await tester.runAsync(
          () => db.loadCheckoutCart(scope),
        );
        expect(afterCart, isNull);

        await tester.pumpWidget(const SizedBox());
        await _settleIo(tester);
      },
    );

    testWidgets(
      'Cloud handoffs: Take over hydrates cart + metadata, 409 shows conflict and refreshes, Discard removes item',
      (tester) async {
        final setup = (await tester.runAsync(() async {
          final shopId = await db.currentShopId();
          final productId = await db.insertProduct(
            Product(
              uuid: 'prod-coffee-uuid',
              name: 'Filter Coffee',
              sellingPrice: 150,
              quantity: 10,
            ),
          );
          return (shopId: shopId, productId: productId);
        }))!;
        final shopId = setup.shopId;
        final productId = setup.productId;

        final harness = _HandoffServerHarness(deviceLabel: 'Billing Phone');
        addTearDown(harness.dispose);
        await tester.runAsync(harness.signIn);

        final available = <Map<String, dynamic>>[
          {
            'uuid': 'h-conflict',
            'source_device_label': 'Web Desk',
            'label': 'Stale Cart',
            'item_count': 1,
            'status': 'available',
            'created_at': '2026-11-27T10:05:00Z',
          },
          {
            'uuid': 'h-discard',
            'source_device_label': 'Web Desk',
            'label': 'Old Cart',
            'item_count': 1,
            'status': 'available',
            'created_at': '2026-11-27T10:04:00Z',
          },
          {
            'uuid': 'h-claim',
            'source_device_label': 'Web Desk',
            'label': 'Active Cart',
            'item_count': 1,
            'status': 'available',
            'created_at': '2026-11-27T10:03:00Z',
          },
        ];

        harness.routes['GET /v1/shops/$shopId/draft-handoffs'] = (_) =>
            _json({'items': List<Map<String, dynamic>>.from(available)});
        harness.routes['POST /v1/shops/$shopId/draft-handoffs/h-conflict/claim'] =
            (_) {
              available.removeWhere((row) => row['uuid'] == 'h-conflict');
              return _failure(
                409,
                'draft_already_claimed',
                'Already claimed on another device',
              );
            };
        harness.routes['DELETE /v1/shops/$shopId/draft-handoffs/h-discard'] =
            (_) {
              available.removeWhere((row) => row['uuid'] == 'h-discard');
              return http.Response('', 204);
            };
        harness.routes['POST /v1/shops/$shopId/draft-handoffs/h-claim/claim'] =
            (_) {
              available.removeWhere((row) => row['uuid'] == 'h-claim');
              return _json({
                'uuid': 'h-claim',
                'source_device_label': 'Web Desk',
                'label': 'Active Cart',
                'item_count': 1,
                'items': [
                  {
                    'product_uuid': 'prod-coffee-uuid',
                    'product_name': 'Filter Coffee',
                    'selling_price_snapshot': 150.0,
                    'quantity': 3.0,
                  },
                ],
                'metadata': {
                  'version': 1,
                  'raw': {'name': 'Meera', 'notes': 'Extra hot'},
                },
                'status': 'claimed',
                'claimed_by_device': 'Billing Phone',
                'claimed_at': '2026-11-27T10:06:00Z',
                'created_at': '2026-11-27T10:03:00Z',
              });
            };

        await _openScanScreen(tester);

        // Open Held / Cloud handoffs sheet.
        await tester.tap(find.byKey(const ValueKey('checkout-held-list')));
        await _settleIo(tester);

        expect(find.text('Cloud handoffs'), findsOneWidget);
        expect(find.text('Stale Cart'), findsOneWidget);
        expect(find.text('Old Cart'), findsOneWidget);
        expect(find.text('Active Cart'), findsOneWidget);

        // 1) 409 draft_already_claimed shows clear message and refreshes list.
        await tester.tap(find.byKey(const ValueKey('handoff-claim-h-conflict')));
        await _settleIo(tester);
        expect(
          find.text('This cart was already claimed on another device.'),
          findsOneWidget,
        );
        expect(find.text('Stale Cart'), findsNothing);

        // 2) Discard removes the discarded handoff.
        await tester.tap(
          find.byKey(const ValueKey('handoff-discard-h-discard')),
        );
        await _settleIo(tester);
        expect(find.text('Old Cart'), findsNothing);

        // 3) Take over claims and hydrates cart items + checkout metadata.
        await tester.tap(find.byKey(const ValueKey('handoff-claim-h-claim')));
        await _settleIo(tester);

        expect(find.text('Filter Coffee'), findsNWidgets(2));
        expect(
          find.text('Took over cart from Web Desk'),
          findsOneWidget,
        );

        final hydratedCart = await tester.runAsync(() async {
          final scope = await db.captureCheckoutScope();
          return db.loadCheckoutCart(scope);
        });
        expect(hydratedCart, isNotNull);
        expect(hydratedCart!.cart.items.single.productId, productId);
        expect(hydratedCart.cart.items.single.quantity, 3);
        expect((hydratedCart.state['raw'] as Map)['name'], 'Meera');

        // Open checkout sheet and verify customer metadata hydrated into form.
        await tester.tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        await _settleIo(tester);
        expect(find.text('Meera'), findsOneWidget);

        await tester.pumpWidget(const SizedBox());
        await _settleIo(tester);
      },
    );
  });
}
