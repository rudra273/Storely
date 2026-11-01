// Runs the real Android SQLite + sync engine against the local TLS development
// API. Enable explicitly with STORELY_SUPPLIER_LIVE=1; never targets production.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/purchase_api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';

void main() {
  test(
    'real API: offline Android payment reconciles with web payment and second device',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final settings = <String, String>{};
      for (final line in File('../storelyapi/.dev-login').readAsLinesSync()) {
        final split = line.indexOf('=');
        if (split > 0) {
          settings[line.substring(0, split)] = line.substring(split + 1);
        }
      }
      final trusted = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates('../storelyapi/certs/ca.crt');
      final api = ApiClient(
        baseUrl: Uri.parse('https://api.storely.localhost'),
        httpClient: IOClient(HttpClient(context: trusted)),
        tokens: MemoryTokenStore(),
      );
      final db = DatabaseHelper.instance;
      final files = ['supplier-live-a.db', 'supplier-live-b.db'];
      try {
        await api.login(
          settings['email']!,
          settings['password']!,
          deviceLabel: 'Supplier payment validation',
        );
        final shops = await api.getJson('/v1/shops');
        final shop =
            ((shops['value'] as List).first as Map)['shop_id'] as String;
        final base = '/v1/shops/$shop';
        final name =
            'Android payments live ${DateTime.now().microsecondsSinceEpoch}';
        final supplier = await api.postJson('$base/suppliers', {'name': name});
        final product = await api.postJson('$base/products', {
          'name': name,
          'selling_price': '60',
          'purchase_price': '40',
          'track_stock': true,
        });
        final productId = (product['product'] as Map)['uuid'];
        final supplierId = supplier['uuid'] as String;
        final receipt = await api.postJson('$base/purchase-receipts', {
          'request_key': 'live-${DateTime.now().microsecondsSinceEpoch}',
          'purchase_date': '2026-10-01',
          'supplier_uuid': supplierId,
          'tax_amount': '20',
          'paid_now': '20',
          'items': [
            {'product_uuid': productId, 'quantity': '2', 'unit_cost': '40'},
          ],
        });
        await db.close();
        DatabaseHelper.databaseFileName = files.first;
        await deleteDatabase(p.join(await getDatabasesPath(), files.first));
        final engine = CloudSyncEngine(
          backend: PurchaseApiSyncBackend(
            api,
            preferredShopId: () async => shop,
          ),
          database: db,
          knownIsAdmin: true,
        );
        await engine.sync(firstSyncMode: FirstSyncMode.startFresh);
        expect((await db.supplierAccounting(supplierId))['balance'], '80.00');
        // This write makes no HTTP request and survives SQLite reopening.
        await db.queueSupplierPayment(supplierId, '30', 'cash', '2026-10-01');
        await db.close();
        expect((await db.pendingSupplierPayments()).length, 1);
        await engine.sync();
        final statement = await api.getJson(
          '$base/suppliers/$supplierId/statement',
        );
        expect(statement['balance_due'], '50.00');
        expect((await db.supplierAccounting(supplierId))['balance'], '50.00');
        await api.postJson('$base/suppliers/$supplierId/payments', {
          'request_key': 'web-${DateTime.now().microsecondsSinceEpoch}',
          'payment_date': '2026-10-01',
          'amount': '50',
          'payment_method': 'upi',
        });
        await engine.sync();
        expect((await db.supplierAccounting(supplierId))['balance'], '0.00');
        await db.close();
        DatabaseHelper.databaseFileName = files.last;
        await deleteDatabase(p.join(await getDatabasesPath(), files.last));
        await engine.sync(firstSyncMode: FirstSyncMode.startFresh);
        final restored = (await db.getPurchaseDocuments(
          limit: 100,
        )).firstWhere((r) => r.uuid == receipt['uuid']);
        expect(restored.paymentStatus, 'paid');
        expect(restored.payments.length, 3);
        final inventory = await api.getJson('$base/products/$productId');
        expect(inventory['product']['quantity'], '2');
        expect(
          (await db.getAllProducts())
              .firstWhere((p) => p.uuid == productId)
              .quantity,
          2,
        );
      } finally {
        await db.close();
        for (final file in files) {
          await deleteDatabase(p.join(await getDatabasesPath(), file));
        }
        DatabaseHelper.databaseFileName = 'storely.db';
        api.dispose();
      }
    },
    skip: Platform.environment['STORELY_SUPPLIER_LIVE'] != '1',
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
