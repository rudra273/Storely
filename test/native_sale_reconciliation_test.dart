import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/held_bill.dart';
import 'package:storely/models/native_sale_posting.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/shared/sync_status_widgets.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:storely/services/sync/native_sale_sync_backend.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_sync_backend.dart';

class ReconciliationBackend extends FakeSyncBackend
    implements NativeSaleSyncBackend {
  bool supported = true;
  bool loseResponse = false;
  bool wrongReceipt = false;
  bool wrongSnapshot = false;
  bool omitProof = false;
  List<Map<String, dynamic>> stockShortages = const [];
  List<Map<String, dynamic>> termsMismatches = const [];
  List<Map<String, dynamic>> snapshotMismatches = const [];
  List<String> identityConflicts = const [];
  List<String> blockingReasons = const [];
  bool canReconcile = true;
  Future<void> Function()? duringInspect;
  Future<void> Function()? duringReconcile;
  Future<void> Function()? duringPost;

  final sentPosts = <(String, String)>[];
  final sentReconciles =
      <(String, String, bool, bool, String)>[]; // attemptId, req, shortage, snap, reason
  final committed = <String, Map<String, dynamic>>{};

  Map<String, dynamic> _buildReceipt(Map<String, dynamic> request) {
    final lines = (request['lines'] as List).cast<Map>();
    final base = {
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
        if (request['payment_uuid'] != null) {'uuid': request['payment_uuid']},
      ],
    };
    return {
      ...base,
      if (wrongReceipt) 'payments': const <Map<String, dynamic>>[],
      if (omitProof) 'native_sale_snapshot_verified': null,
      if (wrongSnapshot)
        'items': [
          for (final item in base['items'] as List)
            {...item as Map, 'unit': 'Different Cloud Unit'},
        ],
    };
  }

  @override
  Future<bool> supportsNativeSale(CheckoutScope scope) async => supported;

  @override
  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
    sentPosts.add((attemptId, jsonEncode(request)));
    final receipt = committed.putIfAbsent(
      attemptId,
      () => _buildReceipt(request),
    );
    if (loseResponse) throw TimeoutException('response lost after commit');
    await duringPost?.call();
    return _applyMutations(receipt);
  }

  Map<String, dynamic> _applyMutations(Map<String, dynamic> receipt) => {
    ...receipt,
    if (wrongReceipt) 'payments': const <Map<String, dynamic>>[],
    if (omitProof) 'native_sale_snapshot_verified': null,
    if (wrongSnapshot)
      'items': [
        for (final item in receipt['items'] as List)
          {...item as Map, 'unit': 'Different Cloud Unit'},
      ],
  };

  @override
  Future<Map<String, dynamic>> inspectNativeSaleReconciliation(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
    await duringInspect?.call();
    final existing = committed[attemptId];
    if (existing != null) {
      return {
        'status': 'already_committed',
        'operation_committed': true,
        'invoice_uuid': request['invoice_uuid'],
        'committed_bill': _applyMutations(existing),
        'stock_shortages': const <Map<String, dynamic>>[],
        'terms_mismatches': const <Map<String, dynamic>>[],
        'snapshot_mismatches': const <Map<String, dynamic>>[],
        'identity_conflicts': const <String>[],
        'blocking_reasons': const <String>[],
        'can_reconcile': false,
      };
    }
    final status = identityConflicts.isNotEmpty
        ? 'identity_conflict'
        : blockingReasons.isNotEmpty
        ? 'blocked'
        : (stockShortages.isNotEmpty ||
              termsMismatches.isNotEmpty ||
              snapshotMismatches.isNotEmpty)
        ? 'needs_reconciliation'
        : 'ready';
    return {
      'status': status,
      'operation_committed': false,
      'invoice_uuid': request['invoice_uuid'],
      'committed_bill': null,
      'stock_shortages': stockShortages,
      'terms_mismatches': termsMismatches,
      'snapshot_mismatches': snapshotMismatches,
      'identity_conflicts': identityConflicts,
      'blocking_reasons': blockingReasons,
      'can_reconcile': canReconcile,
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
  }) async {
    sentReconciles.add((
      attemptId,
      jsonEncode(request),
      allowStockShortage,
      acceptRecordedSnapshot,
      reason,
    ));
    await duringReconcile?.call();
    final receipt = committed.putIfAbsent(
      attemptId,
      () => _buildReceipt(request),
    );
    return _applyMutations(receipt);
  }
}

void main() {
  final helper = DatabaseHelper.instance;
  late ReconciliationBackend server;
  late CheckoutScope scope;
  late int productId;
  var current = true;

  CloudSyncEngine engine() => CloudSyncEngine(
    backend: server,
    database: helper,
    knownIsAdmin: true,
    isUserDataScopeCurrent: () => current,
  );

  Future<String> checkoutReserved() async {
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
    final sql = await helper.database;
    final row = (await sql.query(
      'checkout_acceptances',
      where: 'bill_uuid = ?',
      whereArgs: [invoice],
    )).single;
    if (row['native_sale_state'] == null) {
      final request = nativeSaleRequest(row['posting_snapshot'] as String)!;
      await sql.update(
        'checkout_acceptances',
        {
          'native_sale_request': jsonEncode(request),
          'native_sale_state': 'pending',
        },
        where: 'bill_uuid = ?',
        whereArgs: [invoice],
      );
    }
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

  Future<int> dirtyOf(String table, String where, List<Object?> args) async {
    final sql = await helper.database;
    final rows = await sql.query(
      table,
      columns: ['sync_dirty'],
      where: where,
      whereArgs: args,
    );
    return (rows.single['sync_dirty'] as num).toInt();
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    current = true;
    DatabaseHelper.databaseFileName = 'native-sale-reconciliation.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await helper.setCloudSyncState('preference_owner', 'owner-1');
    scope = await helper.captureCheckoutScope();
    server = ReconciliationBackend()..memberShopId = scope.shopId;
    productId = await helper.insertProduct(
      Product(name: 'Basmati Rice', sellingPrice: 120, quantity: 10),
    );
    await engine().sync(firstSyncMode: FirstSyncMode.uploadExisting);
  });

  tearDown(() async {
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  test(
    'lost response + local edit: inspect sees already_committed and confirm keeps edited bill dirty',
    () async {
      final invoice = await checkoutReserved();
      server.loseResponse = true;
      await expectLater(engine().sync(), throwsA(isA<TimeoutException>()));
      expect(server.committed, hasLength(1));
      expect(await stateOf(invoice), 'pending');

      server.loseResponse = false;
      final sql = await helper.database;
      await sql.update(
        'bills',
        {'customer_name': 'Updated Customer', 'sync_dirty': 1},
        where: 'uuid = ?',
        whereArgs: [invoice],
      );

      final syncResult = await engine().sync();
      expect(syncResult.conflicts.single.table, CloudSyncEngine.nativeSaleConflictTable);
      expect(await stateOf(invoice), 'reconcile');

      final report = await engine().inspectReservedNativeSale(
        server,
        scope,
        invoice,
      );
      expect(report.serverStatus, 'already_committed');
      expect(report.operationCommitted, isTrue);
      expect(report.localDiff.hasEdits, isTrue);
      expect(report.localDiff.changedBillFields, contains('customer_name'));
      expect(
        report.localDiff.summaryLines,
        contains('Customer details changed'),
      );

      await engine().resolveReservedNativeSale(server, scope, report);

      expect(await stateOf(invoice), 'posted');
      // Edited bill row stays dirty so the customer update syncs next.
      expect(await dirtyOf('bills', 'uuid = ?', [invoice]), 1);
      // Unmodified original child rows are acknowledged clean.
      expect(await dirtyOf('bill_items', 'bill_uuid = ?', [invoice]), 0);
      expect(await dirtyOf('bill_payments', 'bill_uuid = ?', [invoice]), 0);
      expect(
        await dirtyOf(
          'stock_movements',
          "source_document_type = 'bill' AND source_document_uuid = ?",
          [invoice],
        ),
        0,
      );
      expect(await helper.getSyncConflicts(), isEmpty);
    },
  );

  test(
    'local edit before send: postOriginalBeforeLocalEdits posts frozen request and next sync pushes edit',
    () async {
      final invoice = await checkoutReserved();
      final pending = (await helper.pendingNativeSaleForBill(scope, invoice))!;
      final originalRequest = pending.request;

      final sql = await helper.database;
      await sql.update(
        'bills',
        {'customer_name': 'Edited Before Send', 'sync_dirty': 1},
        where: 'uuid = ?',
        whereArgs: [invoice],
      );

      final report = await engine().inspectReservedNativeSale(
        server,
        scope,
        invoice,
      );
      expect(report.serverStatus, 'ready');
      expect(report.localDiff.hasEdits, isTrue);

      await engine().resolveReservedNativeSale(
        server,
        scope,
        report,
        postOriginalBeforeLocalEdits: true,
      );

      expect(server.sentPosts, hasLength(1));
      expect(server.sentPosts.single, (pending.attemptId, originalRequest));
      expect(await stateOf(invoice), 'posted');
      expect(await dirtyOf('bills', 'uuid = ?', [invoice]), 1);
      expect(await dirtyOf('bill_items', 'bill_uuid = ?', [invoice]), 0);

      // Next sync uploads the local bill edit cleanly via row sync.
      final next = await engine().sync();
      expect(next.conflicts, isEmpty);
      expect(await dirtyOf('bills', 'uuid = ?', [invoice]), 0);
      expect(server.row('bills', invoice)?['customer_name'], 'Edited Before Send');
    },
  );

  test(
    'stock shortage & snapshot mismatch: reconcile posts frozen request with original attemptId and flags',
    () async {
      final invoice = await checkoutReserved();
      final pending = (await helper.pendingNativeSaleForBill(scope, invoice))!;
      server.stockShortages = [
        {
          'product_uuid': 'prod-1',
          'product_name': 'Basmati Rice',
          'recorded_quantity': '2',
          'available_quantity': '1',
          'shortage_quantity': '1',
        },
      ];
      server.snapshotMismatches = [
        {
          'field': 'unit_name',
          'line_uuid': 'line-1',
          'recorded': 'kg',
          'current': 'bag',
        },
      ];

      final report = await engine().inspectReservedNativeSale(
        server,
        scope,
        invoice,
      );
      expect(report.serverStatus, 'needs_reconciliation');
      expect(report.hasStockShortages, isTrue);
      expect(report.hasSnapshotOrTermsMismatches, isTrue);
      expect(report.canReconcile, isTrue);

      await expectLater(
        engine().resolveReservedNativeSale(
          server,
          scope,
          report,
          allowStockShortage: true,
          acceptRecordedSnapshot: true,
          reason: 'no',
        ),
        throwsArgumentError,
      );
      expect(await stateOf(invoice), 'pending');

      await engine().resolveReservedNativeSale(
        server,
        scope,
        report,
        allowStockShortage: true,
        acceptRecordedSnapshot: true,
        reason: 'Offline sale during stock update',
      );

      expect(server.sentReconciles, hasLength(1));
      expect(server.sentReconciles.single, (
        pending.attemptId,
        pending.request,
        true,
        true,
        'Offline sale during stock update',
      ));
      expect(await stateOf(invoice), 'posted');
      expect(await dirtyOf('bills', 'uuid = ?', [invoice]), 0);
      expect(await dirtyOf('bill_items', 'bill_uuid = ?', [invoice]), 0);
    },
  );

  test(
    'mismatched receipt or snapshot during confirm/reconcile refuses to release reservation',
    () async {
      final invoice = await checkoutReserved();
      server.loseResponse = true;
      await expectLater(engine().sync(), throwsA(isA<TimeoutException>()));
      server.loseResponse = false;

      // Mismatched receipt (missing payment) on already_committed
      server.wrongReceipt = true;
      var report = await engine().inspectReservedNativeSale(
        server,
        scope,
        invoice,
      );
      await expectLater(
        engine().resolveReservedNativeSale(server, scope, report),
        throwsFormatException,
      );
      expect(await stateOf(invoice), 'pending');

      // Mismatched snapshot on already_committed
      server.wrongReceipt = false;
      server.wrongSnapshot = true;
      report = await engine().inspectReservedNativeSale(server, scope, invoice);
      await expectLater(
        engine().resolveReservedNativeSale(server, scope, report),
        throwsFormatException,
      );
      expect(await stateOf(invoice), 'pending');

      // Missing snapshot proof on reconcile
      final invoice2 = await checkoutReserved();
      server.wrongSnapshot = false;
      server.omitProof = true;
      server.stockShortages = [
        {
          'product_uuid': 'prod-1',
          'product_name': 'Basmati Rice',
          'recorded_quantity': '1',
          'available_quantity': '0',
          'shortage_quantity': '1',
        },
      ];
      final report2 = await engine().inspectReservedNativeSale(
        server,
        scope,
        invoice2,
      );
      await expectLater(
        engine().resolveReservedNativeSale(
          server,
          scope,
          report2,
          allowStockShortage: true,
          reason: 'Approve shortage',
        ),
        throwsFormatException,
      );
      expect(await stateOf(invoice2), 'pending');
    },
  );

  test(
    'account switch mid-reconciliation aborts safely without mutating reservation',
    () async {
      final invoice = await checkoutReserved();
      server.stockShortages = [
        {
          'product_uuid': 'prod-1',
          'product_name': 'Basmati Rice',
          'recorded_quantity': '1',
          'available_quantity': '0',
          'shortage_quantity': '1',
        },
      ];
      final report = await engine().inspectReservedNativeSale(
        server,
        scope,
        invoice,
      );
      server.duringReconcile = () async {
        current = false;
      };

      await expectLater(
        engine().resolveReservedNativeSale(
          server,
          scope,
          report,
          allowStockShortage: true,
          reason: 'Approve shortage',
        ),
        throwsStateError,
      );
      expect(await stateOf(invoice), 'pending');
      expect(await dirtyOf('bills', 'uuid = ?', [invoice]), 1);
    },
  );

  testWidgets(
    'Review & reconcile dialog displays shortages/edits and requires checkboxes + reason before enabling submit',
    (tester) async {
      final sale = PendingNativeSale({
        'attempt_id': 'attempt-1',
        'bill_uuid': 'bill-1',
        'native_sale_request': jsonEncode({
          'invoice_uuid': 'bill-1',
          'invoice_number': 'INV-0042',
          'total_amount': '240.00',
        }),
        'native_sale_state': 'reconcile',
        'posting_snapshot': '{}',
      });
      final report = NativeSaleReconciliationReport(
        sale: sale,
        serverStatus: 'needs_reconciliation',
        operationCommitted: false,
        committedBill: null,
        stockShortages: const [
          {
            'product_uuid': 'prod-1',
            'product_name': 'Basmati Rice',
            'recorded_quantity': '2',
            'available_quantity': '1',
            'shortage_quantity': '1',
          },
        ],
        termsMismatches: const [],
        snapshotMismatches: const [
          {
            'field': 'unit_name',
            'line_uuid': 'line-1',
            'recorded': 'kg',
            'current': 'bag',
          },
        ],
        identityConflicts: const [],
        blockingReasons: const [],
        canReconcile: true,
        localDiff: const NativeSaleLocalDiff(
          changedBillFields: ['customer_name'],
          addedPaymentsCount: 1,
        ),
      );

      bool resolvedCalled = false;
      String? capturedReason;
      bool capturedShortage = false;
      bool capturedSnapshot = false;
      bool capturedLocalEdits = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showNativeSaleReconciliationDialog(
                  context,
                  billUuid: 'bill-1',
                  inspect: (_) async => report,
                  resolve:
                      (
                        r, {
                        allowStockShortage = false,
                        acceptRecordedSnapshot = false,
                        postOriginalBeforeLocalEdits = false,
                        reason,
                      }) async {
                        resolvedCalled = true;
                        capturedReason = reason;
                        capturedShortage = allowStockShortage;
                        capturedSnapshot = acceptRecordedSnapshot;
                        capturedLocalEdits = postOriginalBeforeLocalEdits;
                      },
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reconcile INV-0042'), findsOneWidget);
      expect(find.textContaining('Basmati Rice'), findsOneWidget);
      expect(find.textContaining('Customer details changed'), findsOneWidget);
      expect(
        find.textContaining('1 payment added after checkout'),
        findsOneWidget,
      );

      FilledButton submitButton() => tester.widget<FilledButton>(
        find.byKey(const ValueKey('reconcile-submit-button')),
      );

      // Disabled initially.
      expect(submitButton().onPressed, isNull);

      // Check all three required checkboxes, still disabled without reason.
      for (final key in const [
        ValueKey('reconcile-allow-shortage'),
        ValueKey('reconcile-accept-snapshot'),
        ValueKey('reconcile-post-original-first'),
      ]) {
        await tester.ensureVisible(find.byKey(key));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(key));
      }
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // Enter too-short reason -> still disabled.
      final reasonField = find.byKey(const ValueKey('reconcile-reason-field'));
      await tester.ensureVisible(reasonField);
      await tester.pumpAndSettle();
      await tester.enterText(reasonField, 'ok');
      await tester.pump();
      expect(submitButton().onPressed, isNull);

      // Enter valid reason -> enabled.
      await tester.enterText(reasonField, 'Approved offline sale');
      await tester.pump();
      expect(submitButton().onPressed, isNotNull);

      await tester.tap(find.byKey(const ValueKey('reconcile-submit-button')));
      await tester.pumpAndSettle();

      expect(resolvedCalled, isTrue);
      expect(capturedShortage, isTrue);
      expect(capturedSnapshot, isTrue);
      expect(capturedLocalEdits, isTrue);
      expect(capturedReason, 'Approved offline sale');
    },
  );
}
