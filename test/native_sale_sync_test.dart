import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/held_bill.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:storely/services/sync/native_sale_sync_backend.dart';
import 'package:storely/services/sync/sync_backend.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_sync_backend.dart';

class NativeBackend extends FakeSyncBackend implements NativeSaleSyncBackend {
  bool supported = true;
  bool loseResponse = false;
  bool reject = false;
  bool wrongReceipt = false;
  Future<void> Function()? duringPost;
  final sent = <(String, String)>[];
  final committed = <String, Map<String, dynamic>>{};

  @override
  Future<bool> supportsNativeSale(CheckoutScope scope) async => supported;

  @override
  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
    sent.add((attemptId, jsonEncode(request)));
    if (reject) throw SyncRowRejected('The recorded price differs.');
    final receipt = committed.putIfAbsent(
      attemptId,
      () => {
        'bill': {
          'uuid': request['invoice_uuid'],
          'bill_number': request['invoice_number'],
        },
        'items': [
          for (final line in request['lines'] as List)
            {'uuid': line['line_uuid']},
        ],
        'payments': [
          if (request['payment_uuid'] != null)
            {'uuid': request['payment_uuid']},
        ],
      },
    );
    if (loseResponse) throw TimeoutException('response lost after commit');
    await duringPost?.call();
    return wrongReceipt ? {...receipt, 'payments': []} : receipt;
  }
}

void main() {
  final helper = DatabaseHelper.instance;
  late NativeBackend server;
  late CheckoutScope scope;
  late int productId;
  var current = true;

  Future<CloudSyncResult> sync({FirstSyncMode? mode, SyncBackend? backend}) =>
      CloudSyncEngine(
        backend: backend ?? server,
        database: helper,
        knownIsAdmin: true,
        isUserDataScopeCurrent: () => current,
      ).sync(firstSyncMode: mode);

  Future<String> checkout() async {
    final item = await helper.buildBillItemForProduct(
      (await helper.getProductById(productId))!,
    );
    final draft = await helper.saveCartDraft([item], expectedScope: scope);
    final invoice = const Uuid().v4();
    await helper.insertReviewedCheckout(
      attemptId: const Uuid().v4(),
      expectedShopId: scope.shopId,
      expectedOwner: scope.owner,
      originDeviceId: scope.deviceId,
      baseline: await helper.captureSettingsEditBaseline(),
      cartSnapshot: HeldBill.encodeItems([item]),
      expectedCart: draft,
      bill: Bill(
        uuid: invoice,
        shopId: scope.shopId,
        deviceId: scope.deviceId,
        subtotalAmount: item.subtotal,
        taxableAmount: item.totalTaxableValue,
        totalAmount: item.lineAmount,
        itemCount: 1,
      ),
      items: [item],
    );
    return invoice;
  }

  Future<String?> stateOf(String invoice) async {
    final sql = await helper.database;
    final rows = await sql.query(
      'checkout_acceptances',
      where: 'bill_uuid = ?',
      whereArgs: [invoice],
    );
    return rows.single['native_sale_state'] as String?;
  }

  void verifyNotSentAsRows(String invoice, {bool posted = false}) {
    expect(server.row('bills', invoice), isNull);
    expect(server.rows('bill_items'), isEmpty);
    expect(server.rows('bill_payments'), isEmpty);
    expect(
      server
          .rows('stock_movements')
          .where((row) => row['source_document_uuid'] == invoice),
      isEmpty,
    );
    if (posted) {
      expect(server.rows('held_bills').single['deleted_at'], isNotNull);
    } else {
      expect(server.rows('held_bills'), isEmpty);
    }
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    current = true;
    DatabaseHelper.databaseFileName = 'native-sale-sync.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await helper.setCloudSyncState('preference_owner', 'original-owner');
    scope = await helper.captureCheckoutScope();
    server = NativeBackend()..memberShopId = scope.shopId;
    productId = await helper.insertProduct(
      Product(name: 'Test rice', sellingPrice: 100, quantity: 8),
    );
  });
  tearDown(() async {
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  test('a sale saved before negotiation stays on row sync', () async {
    final invoice = await checkout();
    await sync(mode: FirstSyncMode.uploadExisting);
    expect(await stateOf(invoice), isNull);
    expect(server.row('bills', invoice), isNotNull);
    expect(server.sent, isEmpty);
  });

  test('unsupported device keeps new checkouts on row sync', () async {
    server.supported = false;
    await sync(mode: FirstSyncMode.uploadExisting);
    final invoice = await checkout();
    await sync();
    expect(await stateOf(invoice), isNull);
    expect(server.row('bills', invoice), isNotNull);
    expect(server.sent, isEmpty);
  });

  group('opt-in native delivery', skip: !nativeSalePostingEnabled, () {
    setUp(() async {
      await sync(mode: FirstSyncMode.uploadExisting);
    });

    test(
      'reopen after lost response and replay the original command',
      () async {
        final invoice = await checkout();
        expect(await stateOf(invoice), 'pending');
        server.loseResponse = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        verifyNotSentAsRows(invoice);
        expect(await stateOf(invoice), 'pending');
        await helper.close();
        server.loseResponse = false;
        server.supported = false;
        expect((await sync()).conflicts, isEmpty);
        expect(server.sent, hasLength(2));
        expect(server.sent.first, server.sent.last);
        expect(server.committed, hasLength(1));
        expect(await stateOf(invoice), 'posted');
        verifyNotSentAsRows(invoice, posted: true);
        expect(await helper.pendingSyncCounts(), isEmpty);
        expect(await helper.getCloudSyncState('pull_cursor:bills'), isNull);
      },
    );

    test('rejection and unexpected receipt keep the reservation', () async {
      final invoice = await checkout();
      server.reject = true;
      var result = await sync();
      expect(result.conflicts.single.key, invoice);
      expect(result.conflicts.single.message, contains('price differs'));
      expect(await stateOf(invoice), 'pending');
      server.reject = false;
      server.wrongReceipt = true;
      result = await sync();
      expect(result.conflicts.single.message, contains('identities'));
      expect(await stateOf(invoice), 'pending');
      verifyNotSentAsRows(invoice);
      await expectLater(
        CloudSyncEngine.useCloudCopy(helper, result.conflicts.single),
        throwsStateError,
      );
    });

    test(
      'legacy backend and another local owner cannot upload reserved rows',
      () async {
        final invoice = await checkout();
        await helper.setCloudSyncState('preference_owner', 'new-owner');
        final legacy = FakeSyncBackend()..memberShopId = scope.shopId;
        await sync(backend: legacy);
        expect(legacy.rows('bills'), isEmpty);
        expect(legacy.rows('bill_items'), isEmpty);
        expect(legacy.rows('bill_payments'), isEmpty);
        expect(
          legacy
              .rows('stock_movements')
              .where((row) => row['source_document_uuid'] == invoice),
          isEmpty,
        );
        await sync();
        expect(server.sent, isEmpty);
        expect(await stateOf(invoice), 'pending');
        verifyNotSentAsRows(invoice);
      },
    );

    test(
      'edit before sending requires reconciliation without posting',
      () async {
        final invoice = await checkout();
        final sql = await helper.database;
        await sql.update(
          'bills',
          {'customer_name': 'Edited'},
          where: 'uuid = ?',
          whereArgs: [invoice],
        );
        expect((await sync()).conflicts.single.message, contains('changed'));
        expect(server.sent, isEmpty);
        expect(await stateOf(invoice), 'reconcile');
        verifyNotSentAsRows(invoice);
      },
    );

    test(
      'edit during delivery preserves the original and local edit',
      () async {
        final invoice = await checkout();
        server.duringPost = () async {
          final sql = await helper.database;
          await sql.update(
            'bills',
            {'customer_name': 'Edited'},
            where: 'uuid = ?',
            whereArgs: [invoice],
          );
        };
        expect(
          (await sync()).conflicts.single.message,
          contains('server accepted'),
        );
        expect(server.committed, hasLength(1));
        expect(await stateOf(invoice), 'reconcile');
        verifyNotSentAsRows(invoice);
        expect(await helper.unsyncedBillUuids(), contains(invoice));
      },
    );
  });
}
