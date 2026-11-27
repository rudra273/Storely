// Opt-in real Android SQLite -> TLS API reconciliation regression.
// Supply disposable fixture credentials with --dart-define-from-file; never use
// a real merchant shop. This test does not alter the default shipping flag.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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

class _TestApiClient extends http.BaseClient {
  _TestApiClient(this.inner);
  final http.Client inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    const host = String.fromEnvironment('NATIVE_TEST_API_HOST');
    if (host.isNotEmpty) request.headers['host'] = host;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

class _ReconcileTestBackend extends ApiSyncBackend {
  _ReconcileTestBackend(super.api);
  bool loseNext = false;

  @override
  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
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
    'reconciles stock shortage, snapshot drift, lost response and local edits',
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
      DatabaseHelper.databaseFileName =
          'native-reconcile-${const Uuid().v4()}.db';
      final testPath = await DatabaseHelper.databasePath();
      final api = ApiClient(
        baseUrl: Uri.parse(const String.fromEnvironment('STORELY_API_URL')),
        httpClient: _TestApiClient(createApiHttpClient()),
        tokens: MemoryTokenStore(),
      );

      try {
        final login = await api.login(email, password);
        final owner = login.user!.id;
        await helper.adoptCloudShopId(shop);
        await helper.bindCloudUserData(owner);
        final backend = _ReconcileTestBackend(api);

        CloudSyncEngine engine() => CloudSyncEngine(
          backend: backend,
          database: helper,
          knownIsAdmin: true,
          isUserDataScopeCurrent: () => api.user?.id == owner,
        );

        Future<CloudSyncResult> sync() =>
            engine().sync(firstSyncMode: FirstSyncMode.uploadExisting);

        expect((await sync()).conflicts, isEmpty);
        final scope = await helper.captureCheckoutScope();

        final productId = await helper.insertProduct(
          Product(
            name: 'Reconcile test rice',
            hsnCode: '1001',
            purchasePrice: 100,
            sellingPrice: 100,
            manualPrice: 100,
            directPriceToggle: true,
            gstPercent: 0,
            quantity: 1,
          ),
        );
        expect((await sync()).conflicts, isEmpty);
        final product = (await helper.getProductById(productId))!;

        // 1. Offline sale of qty 1.
        final item1 = await helper.buildBillItemForProduct(product);
        final cart1 = await helper.saveCartDraft([item1], expectedScope: scope);
        final invoice1 = const Uuid().v4();
        final attempt1 = const Uuid().v4();
        await helper.insertReviewedCheckout(
          attemptId: attempt1,
          expectedShopId: shop,
          expectedOwner: owner,
          baseline: await helper.captureSettingsEditBaseline(),
          cartSnapshot: HeldBill.encodeItems([item1]),
          originDeviceId: scope.deviceId,
          expectedCart: cart1,
          bill: Bill(
            uuid: invoice1,
            shopId: shop,
            deviceId: scope.deviceId,
            subtotalAmount: 100,
            taxableAmount: 100,
            totalAmount: 100,
            paidAmount: 100,
            isPaid: true,
            itemCount: 1,
          ),
          items: [item1],
        );

        // Cloud stock drops to 0 via another sale AND cost/HSN drift.
        await api.postJson(
          '/v1/shops/$shop/bills',
          {
            'items': [
              {'product_uuid': product.uuid, 'quantity': '1'},
            ],
            'discount_percent': '0',
            'bill_type': 'b2c',
            'payment': {'amount': '100.00', 'method': 'cash'},
          },
          idempotencyKey: const Uuid().v4(),
        );
        await api.patchJson('/v1/shops/$shop/products/${product.uuid}', {
          'purchase_price': '85',
          'hsn_code': '2002',
          'selling_price': '100',
          'price_mode': 'fixed',
        });

        // Automatic sync rejects and keeps reservation.
        final rejected = await sync();
        expect(rejected.conflicts, hasLength(1));
        expect(
          rejected.conflicts.single.table,
          CloudSyncEngine.nativeSaleConflictTable,
        );

        // Inspect shows BOTH stock shortage and snapshot mismatch.
        final report1 = await engine().inspectReservedNativeSale(
          backend,
          scope,
          invoice1,
        );
        expect(report1.serverStatus, 'needs_reconciliation');
        expect(report1.canReconcile, isTrue);
        expect(report1.stockShortages, hasLength(1));
        expect(
          num.parse(report1.stockShortages.single['shortage_quantity'].toString()),
          1,
        );
        expect(report1.snapshotMismatches, isNotEmpty);

        // Explicitly reconcile with auditable reason.
        await engine().resolveReservedNativeSale(
          backend,
          scope,
          report1,
          allowStockShortage: true,
          acceptRecordedSnapshot: true,
          reason: 'Emulator E03.2 shortage and snapshot reconciliation',
        );
        expect(await helper.pendingNativeSales(scope), isEmpty);
        expect((await sync()).conflicts, isEmpty);

        final detail1 = await api.getJson('/v1/shops/$shop/bills/$invoice1');
        expect(detail1['bill']['uuid'], invoice1);
        expect(detail1['items'].single['hsn_code'], '1001');
        expect(num.parse(detail1['items'].single['cost'].toString()), 100);
        expect(
          (detail1['history'] as List).any(
            (row) => row['action'] == 'native_sale_reconciled',
          ),
          isTrue,
        );
        final prodAfter1 = await api.getJson(
          '/v1/shops/$shop/products/${product.uuid}',
        );
        expect(num.parse(prodAfter1['product']['quantity'].toString()), -1);

        // 2. Second product with qty 5 for lost-response commit + local edit.
        final productId2 = await helper.insertProduct(
          Product(
            name: 'Reconcile lost-response item',
            hsnCode: '3003',
            purchasePrice: 80,
            sellingPrice: 100,
            manualPrice: 100,
            directPriceToggle: true,
            gstPercent: 0,
            quantity: 5,
          ),
        );
        expect((await sync()).conflicts, isEmpty);
        final restocked = (await helper.getProductById(productId2))!;
        final item2 = await helper.buildBillItemForProduct(restocked);
        final cart2 = await helper.saveCartDraft([item2], expectedScope: scope);
        final invoice2 = const Uuid().v4();
        final attempt2 = const Uuid().v4();
        await helper.insertReviewedCheckout(
          attemptId: attempt2,
          expectedShopId: shop,
          expectedOwner: owner,
          baseline: await helper.captureSettingsEditBaseline(),
          cartSnapshot: HeldBill.encodeItems([item2]),
          originDeviceId: scope.deviceId,
          expectedCart: cart2,
          bill: Bill(
            uuid: invoice2,
            shopId: shop,
            deviceId: scope.deviceId,
            subtotalAmount: 100,
            taxableAmount: 100,
            totalAmount: 100,
            paidAmount: 100,
            isPaid: true,
            itemCount: 1,
          ),
          items: [item2],
        );

        backend.loseNext = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));

        // Edit the pending invoice locally after server already committed.
        final sql = await helper.database;
        await sql.update(
          'bills',
          {
            'customer_name': 'Post-Commit Edit',
            'sync_dirty': 1,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'uuid = ?',
          whereArgs: [invoice2],
        );
        final localEditConflict = await sync();
        expect(localEditConflict.conflicts, hasLength(1));

        final report2 = await engine().inspectReservedNativeSale(
          backend,
          scope,
          invoice2,
        );
        expect(report2.serverStatus, 'already_committed');
        expect(report2.operationCommitted, isTrue);
        expect(report2.localDiff.hasEdits, isTrue);

        await engine().resolveReservedNativeSale(backend, scope, report2);
        expect(await helper.pendingNativeSales(scope), isEmpty);
        expect((await sync()).conflicts, isEmpty);

        final detail2 = await api.getJson('/v1/shops/$shop/bills/$invoice2');
        expect(detail2['bill']['customer_name'], 'Post-Commit Edit');
        expect(detail2['items'], hasLength(1));
        expect(detail2['payments'], hasLength(1));
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
