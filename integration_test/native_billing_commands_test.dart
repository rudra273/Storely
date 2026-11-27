// Opt-in real Android SQLite -> TLS API atomic billing follow-up commands regression.
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

class _FollowUpBackend extends ApiSyncBackend {
  _FollowUpBackend(super.api);
  bool loseNextPayment = false;
  bool loseNextCancel = false;
  bool loseNextCreditNote = false;

  @override
  Future<Map<String, dynamic>> postNativePayment(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  ) async {
    final res = await super.postNativePayment(
      scope,
      commandId,
      billUuid,
      request,
    );
    if (loseNextPayment) {
      loseNextPayment = false;
      throw TimeoutException('Injected lost payment response');
    }
    return res;
  }

  @override
  Future<Map<String, dynamic>> postNativeCancel(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  ) async {
    final res = await super.postNativeCancel(
      scope,
      commandId,
      billUuid,
      request,
    );
    if (loseNextCancel) {
      loseNextCancel = false;
      throw TimeoutException('Injected lost cancel response');
    }
    return res;
  }

  @override
  Future<Map<String, dynamic>> postNativeCreditNote(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  ) async {
    final res = await super.postNativeCreditNote(
      scope,
      commandId,
      billUuid,
      request,
    );
    if (loseNextCreditNote) {
      loseNextCreditNote = false;
      throw TimeoutException('Injected lost credit note response');
    }
    return res;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'delivers offline payment, credit note and cancellation atomically with replay',
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
          'native-billing-cmds-${const Uuid().v4()}.db';
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
        final backend = _FollowUpBackend(api);

        Future<CloudSyncResult> sync() => CloudSyncEngine(
          backend: backend,
          database: helper,
          knownIsAdmin: true,
          isUserDataScopeCurrent: () => api.user?.id == owner,
        ).sync(firstSyncMode: FirstSyncMode.uploadExisting);

        expect((await sync()).conflicts, isEmpty);
        final scope = await helper.captureCheckoutScope();

        final productId = await helper.insertProduct(
          Product(
            name: 'FollowUp Rice',
            hsnCode: '1001',
            purchasePrice: 80,
            sellingPrice: 100,
            manualPrice: 100,
            directPriceToggle: true,
            gstPercent: 0,
            quantity: 10,
          ),
        );
        expect((await sync()).conflicts, isEmpty);
        final product = (await helper.getProductById(productId))!;

        // 1. Create an unpaid invoice offline (qty 2, total 200), then sync it.
        final item1 = await helper.buildBillItemForProduct(product)
          ..quantity = 2;
        final cart1 = await helper.saveCartDraft([item1], expectedScope: scope);
        final invoice1 = const Uuid().v4();
        final billId1 = await helper.insertReviewedCheckout(
          attemptId: const Uuid().v4(),
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
            customerName: 'Credit Buyer',
            customerPhone: '9876543210',
            subtotalAmount: 200,
            taxableAmount: 200,
            totalAmount: 200,
            paidAmount: 0,
            balanceDue: 200,
            isPaid: false,
            itemCount: 2,
          ),
          items: [item1],
        );

        // Record an offline payment (₹50 bank) and an offline credit note (qty 1, adjust ₹100)
        // BEFORE syncing the invoice!
        await helper.recordBillPayment(
          billId1,
          amount: 50,
          paymentMethod: 'bank',
          paymentReference: 'NEFT-101',
          notes: 'Offline part payment',
        );
        final savedItems = await (await helper.database).query(
          'bill_items',
          where: 'bill_id = ?',
          whereArgs: [billId1],
        );
        final noteId = await helper.createCreditNote(
          billId: billId1,
          quantities: {savedItems.single['uuid'] as String: 1},
          settlement: 'adjust',
          reason: 'Returned 1 unit offline',
        );
        final localNote = (await helper.getBillById(noteId))!;

        // Lose response on payment, then replay cleanly.
        backend.loseNextPayment = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        // Sale committed and acknowledged; payment committed on server but needs replay;
        // credit note still pending behind it.
        backend.loseNextCreditNote = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        // Final sync replays credit note cleanly and clears all queues.
        expect((await sync()).conflicts, isEmpty);
        expect(await helper.pendingNativeSales(scope), isEmpty);
        expect(await helper.pendingNativeBillingCommands(scope), isEmpty);

        final cloudBill1 = await api.getJson('/v1/shops/$shop/bills/$invoice1');
        expect(num.parse(cloudBill1['bill']['paid_amount'].toString()), 150);
        expect(num.parse(cloudBill1['bill']['balance_due'].toString()), 50);
        expect(cloudBill1['payments'], hasLength(2));
        expect(cloudBill1['credit_notes'], hasLength(1));
        expect(cloudBill1['credit_notes'].single['uuid'], localNote.uuid);

        final cloudProd1 = await api.getJson(
          '/v1/shops/$shop/products/${product.uuid}',
        );
        // 10 - 2 sold + 1 returned = 9
        expect(num.parse(cloudProd1['product']['quantity'].toString()), 9);

        // 2. Second invoice -> sync -> cancel offline -> lost response -> replay.
        final item2 = await helper.buildBillItemForProduct(
          (await helper.getProductById(productId))!,
        );
        final cart2 = await helper.saveCartDraft([item2], expectedScope: scope);
        final invoice2 = const Uuid().v4();
        final billId2 = await helper.insertReviewedCheckout(
          attemptId: const Uuid().v4(),
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
        expect((await sync()).conflicts, isEmpty);

        await helper.cancelBill(billId2, reason: 'Offline cancel test');
        backend.loseNextCancel = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        expect((await sync()).conflicts, isEmpty);
        expect(await helper.pendingNativeBillingCommands(scope), isEmpty);

        final cloudBill2 = await api.getJson('/v1/shops/$shop/bills/$invoice2');
        expect(cloudBill2['bill']['cancelled'], isTrue);
        final cloudProd2 = await api.getJson(
          '/v1/shops/$shop/products/${product.uuid}',
        );
        // 9 - 1 sold + 1 voided = 9
        expect(num.parse(cloudProd2['product']['quantity'].toString()), 9);
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
