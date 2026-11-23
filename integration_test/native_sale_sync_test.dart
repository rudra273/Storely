// Opt-in real Android SQLite -> TLS API atomic-sale transport regression.
// Supply disposable fixture credentials with --dart-define-from-file; never use
// a real merchant shop. This test does not alter the default shipping flag.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/held_bill.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/api_sync_backend.dart';
import 'package:storely/services/api/http_client_factory.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:uuid/uuid.dart';

class _LostResponseBackend extends ApiSyncBackend {
  _LostResponseBackend(super.api);
  bool loseNext = false;
  int capabilityChecks = 0;
  final attempts = <(String, String)>[];

  @override
  Future<bool> supportsNativeSale(CheckoutScope scope) async {
    capabilityChecks++;
    return super.supportsNativeSale(scope);
  }

  @override
  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
    attempts.add((attemptId, jsonEncode(request)));
    final response = await super.postNativeSale(scope, attemptId, request);
    if (loseNext) {
      loseNext = false;
      throw TimeoutException('Injected loss after real server commit');
    }
    return response;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native sale negotiates, posts, and replays after lost response',
    (tester) async {
      expect(nativeSalePostingEnabled, isTrue);
      const email = String.fromEnvironment('NATIVE_TEST_EMAIL');
      const password = String.fromEnvironment('NATIVE_TEST_PASSWORD');
      const shop = String.fromEnvironment('NATIVE_TEST_SHOP');
      expect(email.startsWith('first-invoice-'), isTrue);
      expect(password, isNotEmpty);
      expect(shop, isNotEmpty);
      final helper = DatabaseHelper.instance;
      final originalFile = DatabaseHelper.databaseFileName;
      await helper.close();
      DatabaseHelper.databaseFileName = 'native-sale-${const Uuid().v4()}.db';
      final testPath = await DatabaseHelper.databasePath();
      final api = ApiClient(
        baseUrl: Uri.parse(const String.fromEnvironment('STORELY_API_URL')),
        httpClient: createApiHttpClient(),
        tokens: MemoryTokenStore(),
      );
      try {
        final login = await api.login(email, password);
        final owner = login.user!.id;
        await helper.adoptCloudShopId(shop);
        await helper.bindCloudUserData(owner);
        final backend = _LostResponseBackend(api);
        Future<CloudSyncResult> sync() => CloudSyncEngine(
          backend: backend,
          database: helper,
          knownIsAdmin: true,
          isUserDataScopeCurrent: () => api.user?.id == owner,
        ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
        expect((await sync()).conflicts, isEmpty);
        expect(backend.capabilityChecks, 1);
        final scope = await helper.captureCheckoutScope();
        expect(scope.shopId, shop);
        expect(scope.owner, owner);
        expect(
          await helper.getCloudSyncState('native_sale_scope'),
          jsonEncode([shop, owner, scope.deviceId]),
        );
        final productId = await helper.insertProduct(
          Product(
            name: 'Native transport test product',
            purchasePrice: 100,
            sellingPrice: 100,
            manualPrice: 100,
            directPriceToggle: true,
            gstPercent: 0,
            quantity: 10,
          ),
        );
        expect((await sync()).conflicts, isEmpty);
        final product = (await helper.getProductById(productId))!;
        final item = await helper.buildBillItemForProduct(product);
        expect(item.sellingPriceSnapshot, 100);
        final cart = await helper.saveCartDraft([item], expectedScope: scope);
        final invoiceUuid = const Uuid().v4();
        final attemptId = const Uuid().v4();
        await helper.insertReviewedCheckout(
          attemptId: attemptId,
          expectedShopId: shop,
          expectedOwner: owner,
          baseline: await helper.captureSettingsEditBaseline(),
          cartSnapshot: HeldBill.encodeItems([item]),
          originDeviceId: scope.deviceId,
          expectedCart: cart,
          bill: Bill(
            uuid: invoiceUuid,
            shopId: shop,
            deviceId: scope.deviceId,
            totalAmount: 100,
            paidAmount: 100,
            isPaid: true,
            itemCount: 1,
          ),
          items: [item],
        );
        final pending = (await helper.pendingNativeSales(scope)).single;
        expect(pending.attemptId, attemptId);
        expect(pending.billUuid, invoiceUuid);
        final frozen = jsonDecode(pending.request) as Map<String, dynamic>;
        expect(frozen['lines'], hasLength(1));
        expect(frozen['payment_uuid'], isNotNull);
        expect((await helper.getProductById(productId))!.quantity, 9);
        backend.loseNext = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        expect(
          (await helper.pendingNativeSales(scope)).single.request,
          pending.request,
        );
        final committed = await api.getJson(
          '/v1/shops/$shop/bills/$invoiceUuid',
        );
        expect(committed['bill']['uuid'], invoiceUuid);
        expect(committed['bill']['bill_number'], frozen['invoice_number']);
        expect(
          committed['items'].single['uuid'],
          frozen['lines'].single['line_uuid'],
        );
        expect(committed['payments'].single['uuid'], frozen['payment_uuid']);

        // Reopen real on-device SQLite and reconstruct the engine. The original
        // transport payload/key must survive; a second local invoice is not made.
        final cursorBeforeReplay = await helper.getCloudSyncState(
          'pull_cursor:stock_movements',
        );
        await helper.close();
        expect((await sync()).conflicts, isEmpty);
        expect(
          await helper.getCloudSyncState('pull_cursor:stock_movements'),
          cursorBeforeReplay,
          reason: 'A skipped reserved movement must not advance the cursor.',
        );
        expect(backend.attempts, hasLength(2));
        expect(backend.attempts[0], backend.attempts[1]);
        expect(backend.attempts.first.$1, attemptId);
        expect(await helper.pendingNativeSales(scope), isEmpty);
        expect(
          (await helper.getAllBills()).where((b) => b.uuid == invoiceUuid),
          hasLength(1),
        );
        expect((await sync()).conflicts, isEmpty);
        expect(backend.attempts, hasLength(2));
        final cloud = await api.postJson('/v1/shops/$shop/sync/pull', {
          'table': 'stock_movements',
          'after_ts': '1970-01-01T00:00:00Z',
          'after_key': '',
          'limit': 500,
        });
        final moves = (cloud['rows'] as List)
            .where((row) => row['source_document_uuid'] == invoiceUuid)
            .toList();
        expect(moves, hasLength(1));
        expect(moves.single['uuid'], frozen['lines'].single['movement_uuid']);
        expect(num.parse(moves.single['quantity_delta'].toString()), -1);
        final caughtUp = DateTime.parse(
          (await helper.getCloudSyncState('pull_cursor:stock_movements'))!,
        );
        expect(
          caughtUp.isBefore(
            DateTime.parse(moves.single['server_updated_at'].toString()),
          ),
          isFalse,
          reason: 'The post-ack sync must catch up to the committed movement.',
        );
        final local = await helper.database;
        expect(
          await local.query(
            'stock_movements',
            where: 'source_document_uuid = ?',
            whereArgs: [invoiceUuid],
          ),
          hasLength(1),
        );
        expect((await helper.getProductById(productId))!.quantity, 9);
        final after = await api.getJson('/v1/shops/$shop/bills/$invoiceUuid');
        expect(after['items'], hasLength(1));
        expect(after['payments'], hasLength(1));
      } finally {
        api.dispose();
        await helper.close();
        await deleteDatabase(testPath);
        DatabaseHelper.databaseFileName = originalFile;
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
