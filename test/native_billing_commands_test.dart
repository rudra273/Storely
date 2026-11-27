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

class NativeBillingBackend extends FakeSyncBackend
    implements NativeSaleSyncBackend, NativeBillingCommandSyncBackend {
  bool saleSupported = true;
  bool billingCommandsSupported = true;
  bool loseResponse = false;
  bool rejectCommand = false;
  bool wrongReceipt = false;

  final callOrder = <String>[];
  final sentSales = <(String, String)>[];
  final sentPayments = <(String, String, String)>[];
  final sentCancels = <(String, String, String)>[];
  final sentCreditNotes = <(String, String, String)>[];
  final committedCommands = <String, Map<String, dynamic>>{};

  @override
  Future<bool> supportsNativeSale(CheckoutScope scope) async => saleSupported;

  @override
  Future<bool> supportsNativeBillingCommands(CheckoutScope scope) async =>
      billingCommandsSupported;

  @override
  Future<Map<String, dynamic>> postNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async {
    callOrder.add('sale');
    sentSales.add((attemptId, jsonEncode(request)));
    final lines = (request['lines'] as List).cast<Map>();
    return {
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
  }

  @override
  Future<Map<String, dynamic>> inspectNativeSaleReconciliation(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request,
  ) async => const {};

  @override
  Future<Map<String, dynamic>> reconcileNativeSale(
    CheckoutScope scope,
    String attemptId,
    Map<String, dynamic> request, {
    required bool allowStockShortage,
    required bool acceptRecordedSnapshot,
    required String reason,
  }) => postNativeSale(scope, attemptId, request);

  @override
  Future<Map<String, dynamic>> postNativePayment(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  ) async {
    callOrder.add('payment');
    sentPayments.add((commandId, billUuid, jsonEncode(request)));
    if (rejectCommand) throw SyncRowRejected('Payment exceeds balance due.');
    final receipt = committedCommands.putIfAbsent(
      commandId,
      () => {
        'bill': {'uuid': billUuid},
        'payments': [
          {'uuid': request['payment_uuid']},
        ],
      },
    );
    if (loseResponse) throw TimeoutException('response lost after commit');
    if (wrongReceipt) {
      return {
        'bill': {'uuid': billUuid},
        'payments': const [],
      };
    }
    return receipt;
  }

  @override
  Future<Map<String, dynamic>> postNativeCancel(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  ) async {
    callOrder.add('cancel');
    sentCancels.add((commandId, billUuid, jsonEncode(request)));
    if (rejectCommand) throw SyncRowRejected('Invoice has open credit notes.');
    final receipt = committedCommands.putIfAbsent(
      commandId,
      () => {
        'bill': {'uuid': billUuid, 'cancelled': true},
      },
    );
    if (loseResponse) throw TimeoutException('response lost after commit');
    if (wrongReceipt) {
      return {
        'bill': {'uuid': billUuid, 'cancelled': false},
      };
    }
    return receipt;
  }

  @override
  Future<Map<String, dynamic>> postNativeCreditNote(
    CheckoutScope scope,
    String commandId,
    String billUuid,
    Map<String, dynamic> request,
  ) async {
    callOrder.add('credit_note');
    sentCreditNotes.add((commandId, billUuid, jsonEncode(request)));
    if (rejectCommand) throw SyncRowRejected('Return quantity exceeds sold.');
    final lines = (request['lines'] as List).cast<Map>();
    final receipt = committedCommands.putIfAbsent(
      commandId,
      () => {
        'bill': {
          'uuid': request['credit_note_uuid'],
          'bill_number': request['credit_note_number'],
        },
        'items': [
          for (final line in lines) {'uuid': line['line_uuid']},
        ],
      },
    );
    if (loseResponse) throw TimeoutException('response lost after commit');
    if (wrongReceipt) {
      return {
        'bill': {
          'uuid': request['credit_note_uuid'],
          'bill_number': request['credit_note_number'],
        },
        'items': const [],
      };
    }
    return receipt;
  }
}

void main() {
  final helper = DatabaseHelper.instance;
  late NativeBillingBackend server;
  late CheckoutScope scope;
  late int productId;
  var current = true;

  Future<CloudSyncResult> sync({FirstSyncMode? mode}) => CloudSyncEngine(
    backend: server,
    database: helper,
    knownIsAdmin: true,
    isUserDataScopeCurrent: () => current,
  ).sync(firstSyncMode: mode);

  Future<({int billId, String billUuid, String itemUuid})> checkout({
    double quantity = 2,
    double paidAmount = 0,
    String? customerPhone = '9876543210',
  }) async {
    final item = await helper.buildBillItemForProduct(
      (await helper.getProductById(productId))!,
    )..quantity = quantity;
    final draft = await helper.saveCartDraft([item], expectedScope: scope);
    final invoiceUuid = const Uuid().v4();
    final total = item.lineAmount;
    final paid = paidAmount.clamp(0, total).toDouble();
    final billId = await helper.insertReviewedCheckout(
      attemptId: const Uuid().v4(),
      expectedShopId: scope.shopId,
      expectedOwner: scope.owner,
      originDeviceId: scope.deviceId,
      baseline: await helper.captureSettingsEditBaseline(),
      cartSnapshot: HeldBill.encodeItems([item]),
      expectedCart: draft,
      bill: Bill(
        uuid: invoiceUuid,
        shopId: scope.shopId,
        deviceId: scope.deviceId,
        customerName: 'Test Customer',
        customerPhone: customerPhone,
        subtotalAmount: item.subtotal,
        taxableAmount: item.totalTaxableValue,
        totalAmount: total,
        itemCount: 1,
        isPaid: paid >= total - 0.005,
        paidAmount: paid,
        balanceDue: total - paid,
        paymentStatus: paid <= 0.005
            ? Bill.statusUnpaid
            : paid >= total - 0.005
            ? Bill.statusPaid
            : Bill.statusPartial,
      ),
      items: [item],
    );
    final saved = (await helper.getBillById(billId))!;
    return (
      billId: billId,
      billUuid: invoiceUuid,
      itemUuid: saved.items.single.uuid,
    );
  }

  Future<List<Map<String, Object?>>> allCommands() async {
    final sql = await helper.database;
    return sql.query('native_billing_commands', orderBy: 'rowid ASC');
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    current = true;
    DatabaseHelper.databaseFileName = 'native-billing-commands.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await helper.setCloudSyncState('preference_owner', 'original-owner');
    scope = await helper.captureCheckoutScope();
    server = NativeBillingBackend()..memberShopId = scope.shopId;
    productId = await helper.insertProduct(
      Product(name: 'Widget', sellingPrice: 100, quantity: 20),
    );
  });

  tearDown(() async {
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  test('useCloudCopy refuses native_billing_commands conflicts', () async {
    await expectLater(
      CloudSyncEngine.useCloudCopy(
        helper,
        const SyncConflict(
          table: CloudSyncEngine.nativeBillingCommandConflictTable,
          key: 'cmd-1',
          message: 'Payment exceeds balance due.',
        ),
      ),
      throwsStateError,
    );
  });

  test('local-only mode (no owner) enqueues zero native billing commands', () async {
    await helper.clearCloudSyncState('preference_owner');
    final billId = await helper.insertBill(
      Bill(
        uuid: const Uuid().v4(),
        shopId: scope.shopId,
        totalAmount: 200,
        itemCount: 1,
        isPaid: false,
        paidAmount: 0,
        balanceDue: 200,
        paymentStatus: Bill.statusUnpaid,
      ),
      [
        await helper.buildBillItemForProduct(
          (await helper.getProductById(productId))!,
        )..quantity = 2,
      ],
    );
    await helper.recordBillPayment(billId, amount: 50, paymentMethod: 'cash');
    final bill = (await helper.getBillById(billId))!;
    await helper.createCreditNote(
      billId: billId,
      quantities: {bill.items.single.uuid: 1},
      settlement: DatabaseBills.creditNoteSettleRefund,
      refundMethod: 'cash',
      reason: 'Damaged',
    );
    expect(await allCommands(), isEmpty);
  });

  test(
    'flag-off or unsupported server enqueues zero native billing commands',
    () async {
      server.billingCommandsSupported = false;
      await sync(mode: FirstSyncMode.uploadExisting);
      final sale = await checkout(quantity: 2, paidAmount: 0);
      await helper.recordBillPayment(
        sale.billId,
        amount: 50,
        paymentMethod: 'upi',
      );
      await helper.createCreditNote(
        billId: sale.billId,
        quantities: {sale.itemUuid: 1},
        settlement: DatabaseBills.creditNoteSettleRefund,
        refundMethod: 'cash',
      );
      expect(await allCommands(), isEmpty);
      await sync();
      expect(server.sentPayments, isEmpty);
      expect(server.sentCreditNotes, isEmpty);
    },
  );

  group('opt-in native billing commands', skip: !nativeSalePostingEnabled, () {
    setUp(() async {
      await sync(mode: FirstSyncMode.uploadExisting);
    });

    test(
      'recordBillPayment enqueues atomically, hides from legacy push, replays on lost response, and preserves reservation on rejection',
      () async {
        final sale = await checkout(quantity: 2, paidAmount: 0);
        await sync();
        expect(server.sentSales, hasLength(1));

        await helper.recordBillPayment(
          sale.billId,
          amount: 100,
          paymentMethod: 'upi',
          paymentReference: 'UTR123',
          notes: 'Partial',
        );
        final commands = await allCommands();
        expect(commands, hasLength(1));
        expect(commands.single['command_type'], 'payment');
        expect(commands.single['bill_uuid'], sale.billUuid);
        expect(commands.single['state'], 'pending');

        // Lost response -> payment row stays hidden from legacy row sync and
        // replays the exact same commandId after reopen.
        server.loseResponse = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        expect(server.rows('bill_payments'), isEmpty);
        expect((await allCommands()).single['state'], 'pending');

        await helper.close();
        server.loseResponse = false;
        server.rejectCommand = true;
        var result = await sync();
        expect(result.conflicts, hasLength(1));
        expect(
          result.conflicts.single.table,
          CloudSyncEngine.nativeBillingCommandConflictTable,
        );
        expect(result.conflicts.single.key, commands.single['command_id']);
        expect((await allCommands()).single['state'], 'pending');
        expect(
          (await allCommands()).single['last_error'],
          contains('balance due'),
        );
        expect(server.rows('bill_payments'), isEmpty);

        // Wrong receipt keeps reservation.
        server.rejectCommand = false;
        server.wrongReceipt = true;
        result = await sync();
        expect(result.conflicts, hasLength(1));
        expect((await allCommands()).single['state'], 'pending');

        // Valid replay acknowledges and clears sync_dirty.
        server.wrongReceipt = false;
        result = await sync();
        expect(result.conflicts, isEmpty);
        expect((await allCommands()).single['state'], 'posted');
        expect((await allCommands()).single['last_error'], isNull);
        expect(server.rows('bill_payments'), isEmpty);
        // Same commandId used across all attempts.
        final ids = server.sentPayments.map((e) => e.$1).toSet();
        expect(ids, {commands.single['command_id']});
        expect(await helper.pendingSyncCounts(), isEmpty);
      },
    );

    test(
      'cancelBill enqueues atomically, hides void movement & cancelled bill from legacy push, verifies cancelled receipt, and replays after lost response',
      () async {
        final sale = await checkout(quantity: 2, paidAmount: 200);
        await sync();

        await helper.cancelBill(sale.billId, reason: 'Wrong item');
        final commands = await allCommands();
        expect(commands, hasLength(1));
        expect(commands.single['command_type'], 'cancel');
        expect(commands.single['bill_uuid'], sale.billUuid);
        expect(commands.single['state'], 'pending');
        final reserved =
            jsonDecode(commands.single['reserved_uuids_json'] as String) as Map;
        expect(
          reserved['stock_movements'],
          contains('void-${sale.billUuid}-${sale.itemUuid}'),
        );

        server.loseResponse = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        expect(server.row('bills', sale.billUuid), isNull);
        expect(
          server.row(
            'stock_movements',
            'void-${sale.billUuid}-${sale.itemUuid}',
          ),
          isNull,
        );

        server.loseResponse = false;
        server.wrongReceipt = true;
        var result = await sync();
        expect(result.conflicts, hasLength(1));
        expect((await allCommands()).single['state'], 'pending');

        server.wrongReceipt = false;
        result = await sync();
        expect(result.conflicts, isEmpty);
        expect((await allCommands()).single['state'], 'posted');
        expect(server.sentCancels.map((e) => e.$1).toSet(), {
          commands.single['command_id'],
        });
        expect(server.row('bills', sale.billUuid), isNull);
        expect(
          server.row(
            'stock_movements',
            'void-${sale.billUuid}-${sale.itemUuid}',
          ),
          isNull,
        );
      },
    );

    test(
      'createCreditNote (refund) enqueues with exact UUIDs, hides rows from legacy push, and replays after lost response',
      () async {
        final sale = await checkout(quantity: 3, paidAmount: 300);
        await sync();

        final cnId = await helper.createCreditNote(
          billId: sale.billId,
          quantities: {sale.itemUuid: 1},
          settlement: DatabaseBills.creditNoteSettleRefund,
          refundMethod: 'upi',
          reason: 'Customer return',
        );
        final cn = (await helper.getBillById(cnId))!;
        final commands = await allCommands();
        expect(commands, hasLength(1));
        expect(commands.single['command_type'], 'credit_note');
        expect(commands.single['bill_uuid'], sale.billUuid);
        expect(commands.single['target_uuid'], cn.uuid);
        final req =
            jsonDecode(commands.single['request_json'] as String) as Map;
        expect(req['credit_note_uuid'], cn.uuid);
        expect(req['credit_note_number'], cn.billNumber);
        expect(req['settlement'], 'refund');
        expect(req['refund_method'], 'upi');
        expect(req['note_payment_uuid'], isNotNull);
        expect(req['invoice_adjustment_payment_uuid'], isNull);
        final reqLines = (req['lines'] as List).cast<Map>();
        expect(reqLines.single['line_uuid'], cn.items.single.uuid);
        expect(reqLines.single['original_item_uuid'], sale.itemUuid);
        expect(reqLines.single['movement_uuid'], isNotNull);

        server.loseResponse = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        expect(server.row('bills', cn.uuid), isNull);
        expect(server.rows('bill_payments'), isEmpty);

        server.loseResponse = false;
        final result = await sync();
        expect(result.conflicts, isEmpty);
        expect((await allCommands()).single['state'], 'posted');
        expect(server.sentCreditNotes, hasLength(2));
        expect(server.sentCreditNotes.first, server.sentCreditNotes.last);
        expect(server.row('bills', cn.uuid), isNull);
      },
    );

    test(
      'createCreditNote (adjust) enqueues with both payment UUIDs and hides rows from legacy push',
      () async {
        final sale = await checkout(quantity: 3, paidAmount: 0);
        await sync();

        final cnId = await helper.createCreditNote(
          billId: sale.billId,
          quantities: {sale.itemUuid: 1},
          settlement: DatabaseBills.creditNoteSettleAdjust,
          reason: 'Partial return',
        );
        final cn = (await helper.getBillById(cnId))!;
        final commands = await allCommands();
        expect(commands, hasLength(1));
        final req =
            jsonDecode(commands.single['request_json'] as String) as Map;
        expect(req['settlement'], 'adjust');
        expect(req['note_payment_uuid'], isNotNull);
        expect(req['invoice_adjustment_payment_uuid'], isNotNull);
        final reserved =
            jsonDecode(commands.single['reserved_uuids_json'] as String) as Map;
        expect(reserved['bills'], containsAll([cn.uuid, sale.billUuid]));
        expect((reserved['bill_payments'] as List), hasLength(2));

        server.loseResponse = true;
        await expectLater(sync(), throwsA(isA<TimeoutException>()));
        expect(server.row('bills', cn.uuid), isNull);
        expect(server.rows('bill_payments'), isEmpty);

        server.loseResponse = false;
        final result = await sync();
        expect(result.conflicts, isEmpty);
        expect((await allCommands()).single['state'], 'posted');
        expect(server.sentCreditNotes, hasLength(2));
        expect(server.sentCreditNotes.first, server.sentCreditNotes.last);
      },
    );

    test(
      'offline sale + offline payment delivers sale first via postNativeSale then payment via postNativePayment',
      () async {
        final sale = await checkout(quantity: 2, paidAmount: 0);
        await helper.recordBillPayment(
          sale.billId,
          amount: 100,
          paymentMethod: 'cash',
        );

        server.callOrder.clear();
        final result = await sync();
        expect(result.conflicts, isEmpty);
        expect(server.callOrder, ['sale', 'payment']);
        expect(server.sentSales, hasLength(1));
        expect(server.sentPayments, hasLength(1));
        expect(server.row('bills', sale.billUuid), isNull);
        expect(server.rows('bill_payments'), isEmpty);
        expect(await helper.pendingSyncCounts(), isEmpty);
      },
    );

    test('startFresh is blocked while pending billing commands exist', () async {
      final sale = await checkout(quantity: 2, paidAmount: 0);
      await sync();
      await helper.recordBillPayment(
        sale.billId,
        amount: 100,
        paymentMethod: 'cash',
      );
      await CloudSyncEngine.resetProgress(helper);
      await expectLater(
        sync(mode: FirstSyncMode.startFresh),
        throwsStateError,
      );
    });
  });
}
