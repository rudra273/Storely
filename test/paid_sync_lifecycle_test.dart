import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';

import 'support/fake_sync_backend.dart';

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final paused in ['free', 'expired', 'suspended', 'scheduled']) {
    test(
      '$paused preserves local billing and queue; renewal uploads once',
      () async {
        final previousFile = DatabaseHelper.databaseFileName;
        await db.close();
        DatabaseHelper.databaseFileName = 'paid_lifecycle_$paused.db';
        final file = p.join(
          await getDatabasesPath(),
          DatabaseHelper.databaseFileName,
        );
        if (File(file).existsSync()) await deleteDatabase(file);
        final server = FakeSyncBackend();
        var active = false;
        final calls = <String>[];
        http.Response response(Object value) => http.Response(
          jsonEncode(value),
          200,
          headers: {'content-type': 'application/json'},
        );
        final api = ApiClient(
          baseUrl: Uri.parse('https://api.test'),
          tokens: MemoryTokenStore(),
          httpClient: MockClient((request) async {
            final path = request.url.path;
            calls.add(path);
            final body = request.body.isEmpty
                ? <String, dynamic>{}
                : jsonDecode(request.body) as Map<String, dynamic>;
            if (path.endsWith('/login')) {
              return response({
                'access_token': 'a',
                'refresh_token': 'r',
                'expires_in': 900,
              });
            }
            if (path == '/v1/me') {
              return response({'id': 'owner', 'email': 'owner@example.com'});
            }
            if (path == '/v1/shops') {
              return response([
                {'shop_id': server.memberShopId, 'role': 'owner'},
              ]);
            }
            if (path.endsWith('/entitlement')) {
              return response({
                'cloud_sync': active,
                'effective_status': active ? 'active' : paused,
              });
            }
            if (path == '/v1/devices/register') {
              return response({
                'code': await server.registerDevice(
                  body['shop_id'] as String,
                  body['device_id'] as String,
                ),
              });
            }
            if (path.endsWith('/pull')) {
              return response({
                'rows': await server.pullPage(
                  body['table'] as String,
                  shopId: server.memberShopId!,
                  afterTs: DateTime.parse(body['after_ts'] as String),
                  afterKey: body['after_key'] as String,
                  limit: body['limit'] as int,
                ),
              });
            }
            if (path.endsWith('/push')) {
              final rows = (body['rows'] as List)
                  .map((r) => Map<String, dynamic>.from(r as Map))
                  .toList();
              await server.upsert(body['table'] as String, rows);
              return response({'accepted': rows.length, 'rejected': []});
            }
            throw StateError('Unexpected test route $path');
          }),
        );
        try {
          await api.login('owner@example.com', 'test-password');
          server.memberShopId = await db.currentShopId();
          await db.insertProduct(
            Product(
              name: 'Offline rice',
              mrp: 0,
              purchasePrice: 100,
              quantity: 10,
            ),
          );
          final product = (await db.getAllProducts()).single;
          final item = await db.buildBillItemForProduct(product);
          final id = await db.insertBill(
            Bill(
              customerName: 'Offline buyer',
              subtotalAmount: item.subtotal,
              totalAmount: item.subtotal,
              itemCount: 1,
              isPaid: true,
            ),
            [item],
          );
          final bill = (await db.getBillById(id))!;
          final pending = await db.pendingSyncCounts();
          final engine = CloudSyncEngine(
            backend: ApiSyncBackend(api),
            database: db,
            knownIsAdmin: true,
          );
          calls.clear();
          await expectLater(
            engine.sync(firstSyncMode: FirstSyncMode.uploadExisting),
            throwsA(
              isA<ApiException>().having(
                (e) => e.code,
                'code',
                'premium_required',
              ),
            ),
          );
          expect(
            calls.every(
              (path) => path == '/v1/shops' || path.endsWith('/entitlement'),
            ),
            isTrue,
          );
          expect(await db.pendingSyncCounts(), pending);
          expect((await db.getBillById(id))!.uuid, bill.uuid);
          expect(server.uploads, 0);
          active = true;
          await engine.sync(firstSyncMode: FirstSyncMode.uploadExisting);
          expect(await db.pendingSyncCounts(), isEmpty);
          expect(
            server
                .rows('bills')
                .where((row) => row['uuid'] == bill.uuid)
                .length,
            1,
          );
          expect((await db.getBillById(id))!.billNumber, bill.billNumber);
          await engine.sync();
          expect(
            server
                .rows('bills')
                .where((row) => row['uuid'] == bill.uuid)
                .length,
            1,
          );
        } finally {
          api.dispose();
          await db.close();
          await deleteDatabase(file);
          DatabaseHelper.databaseFileName = previousFile;
        }
      },
    );
  }
}
