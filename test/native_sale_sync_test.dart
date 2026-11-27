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
  bool omitProof = false;
  bool wrongSnapshot = false;
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
    final lines = (request['lines'] as List).cast<Map>();
    final receipt = committed.putIfAbsent(
      attemptId,
      () => {
        if (lines.any((line) => line['snapshot'] != null))
          'native_sale_snapshot_verified': 1,
        'bill': {
          'uuid': request['invoice_uuid'],
          'bill_number': request['invoice_number'],
        },
        'items': [
          for (final line in lines)
            {
              'uuid': line['line_uuid'],
              'hsn_code': line['snapshot']?['hsn_code_snapshot'],
              'unit': line['snapshot']?['unit_name'],
            },
        ],
        'payments': [
          if (request['payment_uuid'] != null)
            {'uuid': request['payment_uuid']},
        ],
      },
    );
    if (loseResponse) throw TimeoutException('response lost after commit');
    await duringPost?.call();
    return {
      ...receipt,
      if (wrongReceipt) 'payments': [],
      if (omitProof) 'native_sale_snapshot_verified': null,
      if (wrongSnapshot)
        'items': [
          for (final item in receipt['items'] as List)
            {...item as Map, 'unit': 'Changed cloud unit'},
        ],
    };
  }

  @override
  Future<Map<String, dynamic>> inspectNativeSaleReconciliation(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
    final existing = committed[attemptId];
    return {
      'status': existing != null ? 'already_committed' : 'ready',
      'operation_committed': existing != null,
      'invoice_uuid': request['invoice_uuid'],
      'committed_bill': existing,
      'stock_shortages': const <Map<String, dynamic>>[],
      'terms_mismatches': const <Map<String, dynamic>>[],
      'snapshot_mismatches': const <Map<String, dynamic>>[],
      'identity_conflicts': const <String>[],
      'blocking_reasons': const <String>[],
      'can_reconcile': true,
    };
  }

  @override
  Future<Map<String, dynamic>> reconcileNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request, {
    required bool allowStockShortage,
    required bool acceptRecordedSnapshot,
    required String reason,
  }) => postNativeSale(scope, attemptId, request);
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

  test(
    'the previous enrollment marker cannot select new strict commands',
    () async {
      await helper.setCloudSyncState(
        'native_sale_scope',
        jsonEncode([scope.shopId, scope.owner, scope.deviceId]),
      );
      final invoice = await checkout();
      expect(await stateOf(invoice), isNull);
    },
  );

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
      'snapshot proof and returned visible fields are required before acknowledgement',
      () async {
        final invoice = await checkout();
        server.omitProof = true;
        expect((await sync()).conflicts.single.message, contains('snapshots'));
        expect(await stateOf(invoice), 'pending');
        verifyNotSentAsRows(invoice);

        server.omitProof = false;
        server.wrongSnapshot = true;
        expect((await sync()).conflicts.single.message, contains('snapshots'));
        expect(await stateOf(invoice), 'pending');
        verifyNotSentAsRows(invoice);

        server.wrongSnapshot = false;
        expect((await sync()).conflicts, isEmpty);
        expect(await stateOf(invoice), 'posted');
        expect(server.sent.toSet(), hasLength(1));
        verifyNotSentAsRows(invoice, posted: true);
      },
    );

    test(
      'a pending proofless command from the prior build replays unchanged',
      () async {
        final invoice = await checkout();
        final pending = (await helper.pendingNativeSales(scope)).single;
        final v1 = jsonDecode(pending.request) as Map<String, dynamic>;
        for (final line in (v1['lines'] as List).cast<Map>()) {
          line.remove('snapshot');
        }
        final saved = jsonEncode(v1);
        final sql = await helper.database;
        await sql.update(
          'checkout_acceptances',
          {'native_sale_request': saved},
          where: 'attempt_id = ?',
          whereArgs: [pending.attemptId],
        );
        await helper.close();
        server.supported = false;
        expect((await sync()).conflicts, isEmpty);
        expect(server.sent.single, (pending.attemptId, saved));
        expect(await stateOf(invoice), 'posted');
        verifyNotSentAsRows(invoice, posted: true);
      },
    );

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
