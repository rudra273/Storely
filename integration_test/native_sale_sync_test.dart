// Opt-in real Android SQLite -> TLS API atomic-sale transport regression.
// Supply disposable fixture credentials with --dart-define-from-file; never use
// a real merchant shop. This test does not alter the default shipping flag.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:http/http.dart' as http;
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

// adb reverse can expose the TLS proxy on loopback; preserve its API virtual host.
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

class _LostResponseBackend extends ApiSyncBackend {
  _LostResponseBackend(super.api);
  bool loseNext = false;
  int capabilityChecks = 0;
  final attempts = <(String, String)>[];
  final receipts = <Map<String, dynamic>>[];

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
    receipts.add(response);
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
    'strict native sale rejects drift and preserves snapshots on replay',
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
        httpClient: _TestApiClient(createApiHttpClient()),
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
          jsonEncode([shop, owner, scope.deviceId, 1]),
        );
        final productId = await helper.insertProduct(
          Product(
            name: 'Native transport test product',
            hsnCode: '1001',
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
        final snapshot = frozen['lines'].single['snapshot'] as Map;
        expect(snapshot['hsn_code_snapshot'], '1001');
        expect(snapshot['purchase_price_snapshot'], '100.000000000');
        expect(snapshot['cost_snapshot'], '100.000000000');
        expect(snapshot['profit_snapshot'], '0.000000000');
        Future<void> changeCatalog(String cost, String hsn) async {
          await api.patchJson('/v1/shops/$shop/products/${product.uuid}', {
            'purchase_price': cost,
            'hsn_code': hsn,
            'selling_price': '100',
            'price_mode': 'fixed',
          });
          final current = await api.getJson(
            '/v1/shops/$shop/products/${product.uuid}',
          );
          expect(
            num.parse(current['product']['selling_price'].toString()),
            100,
          );
        }

        // A same-price change is invisible to aggregate total validation.
        // Strict posting must reject it without consuming the operation key or
        // adding any invoice, item, payment or sale movement in the cloud.
        await changeCatalog('90', '2002');
        final rejected = await sync();
        expect(rejected.conflicts, hasLength(1));
        expect(
          rejected.conflicts.single.table,
          CloudSyncEngine.nativeSaleConflictTable,
        );
        expect(backend.receipts, isEmpty);
        expect(
          (await helper.pendingNativeSales(scope)).single.request,
          pending.request,
        );
        await expectLater(
          api.getJson('/v1/shops/$shop/bills/$invoiceUuid'),
          throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
        );
        for (final table in [
          'bills',
          'bill_items',
          'bill_payments',
          'stock_movements',
        ]) {
          final remote = await api.postJson('/v1/shops/$shop/sync/pull', {
            'table': table,
            'after_ts': '1970-01-01T00:00:00Z',
            'after_key': '',
            'limit': 500,
          });
          expect(
            (remote['rows'] as List).where(
              (row) =>
                  row['uuid'] == invoiceUuid ||
                  row['bill_uuid'] == invoiceUuid ||
                  row['source_document_uuid'] == invoiceUuid,
            ),
            isEmpty,
            reason: 'Rejected strict sale must not post $table.',
          );
        }
        final stockAfterRefusal = await api.getJson(
          '/v1/shops/$shop/products/${product.uuid}',
        );
        expect(
          num.parse(stockAfterRefusal['product']['quantity'].toString()),
          10,
        );
        await changeCatalog('100', '1001');
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
        expect(backend.receipts.single['native_sale_snapshot_verified'], 1);
        expect(committed['items'].single['hsn_code'], '1001');
        expect(num.parse(committed['items'].single['cost'].toString()), 100);
        await changeCatalog('80', '3003');

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
        expect(backend.attempts, hasLength(3));
        expect(backend.attempts[0], backend.attempts[1]);
        expect(backend.attempts[1], backend.attempts[2]);
        expect(backend.receipts, hasLength(2));
        expect(backend.receipts.last['native_sale_snapshot_verified'], 1);
        expect(backend.attempts.first.$1, attemptId);
        expect(await helper.pendingNativeSales(scope), isEmpty);
        expect(
          (await helper.getAllBills()).where((b) => b.uuid == invoiceUuid),
          hasLength(1),
        );
        expect((await sync()).conflicts, isEmpty);
        expect(backend.attempts, hasLength(3));
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
        expect(after['items'].single['hsn_code'], '1001');
        expect(num.parse(after['items'].single['cost'].toString()), 100);
        expect(num.parse(after['items'].single['profit'].toString()), 0);
        final rawLines = await api.postJson('/v1/shops/$shop/sync/pull', {
          'table': 'bill_items',
          'after_ts': '1970-01-01T00:00:00Z',
          'after_key': '',
          'limit': 500,
        });
        final remoteLine = (rawLines['rows'] as List).singleWhere(
          (row) => row['uuid'] == frozen['lines'].single['line_uuid'],
        );
        for (final field in [
          'hsn_code_snapshot',
          'hsn_type_snapshot',
          'unit_name',
        ]) {
          expect(remoteLine[field], snapshot[field], reason: field);
        }
        for (final field in [
          'purchase_price_snapshot',
          'cost_snapshot',
          'profit_snapshot',
        ]) {
          expect(
            num.parse(remoteLine[field].toString()),
            num.parse(snapshot[field].toString()),
            reason: field,
          );
        }
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
