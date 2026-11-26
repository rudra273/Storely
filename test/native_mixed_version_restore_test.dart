import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/held_bill.dart';
import 'package:storely/models/native_sale_posting.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/backup_service.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:storely/services/sync/native_sale_sync_backend.dart';
import 'package:storely/services/sync/sync_backend.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_sync_backend.dart';

class _MixedVersionBackend extends FakeSyncBackend
    implements NativeSaleSyncBackend, NativeBillingCommandSyncBackend {
  bool saleSupported = true;
  bool billingCommandsSupported = true;

  final callOrder = <String>[];
  final sentSales = <(String, String)>[];
  final sentPayments = <(String, String, String)>[];
  final sentCancels = <(String, String, String)>[];
  final sentCreditNotes = <(String, String, String)>[];

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
    return {
      'bill': {'uuid': billUuid},
      'payments': [
        {'uuid': request['payment_uuid']},
      ],
    };
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
    return {
      'bill': {'uuid': billUuid, 'cancelled': true},
    };
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
    final lines = (request['lines'] as List).cast<Map>();
    return {
      'bill': {
        'uuid': request['credit_note_uuid'],
        'bill_number': request['credit_note_number'],
      },
      'items': [
        for (final line in lines) {'uuid': line['line_uuid']},
      ],
    };
  }
}

void main() {
  final helper = DatabaseHelper.instance;
  late _MixedVersionBackend server;
  late CheckoutScope scope;
  late Directory work;
  late int productId;

  Future<CloudSyncResult> sync({
    FirstSyncMode? mode,
    SyncBackend? backend,
  }) => CloudSyncEngine(
    backend: backend ?? server,
    database: helper,
    knownIsAdmin: true,
    isUserDataScopeCurrent: () => true,
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

  /// Seeds a realistic reserved native sale + reserved native payment command
  /// directly in SQLite so downgrade/flag-off/restore/isolation paths can be
  /// verified regardless of the compile-time `STORELY_NATIVE_SALE_POSTING` flag.
  Future<
    ({
      String saleAttemptId,
      String saleBillUuid,
      String saleItemUuid,
      String saleRequestJson,
      String paymentCommandId,
      String followUpBillUuid,
      String followUpPaymentUuid,
      String paymentRequestJson,
      String paymentReservedJson,
    })
  >
  seedPendingSaleAndPaymentReservations() async {
    final reservedSale = await checkout(quantity: 2, paidAmount: 200);
    final sql = await helper.database;
    final saleAcceptance = (await sql.query(
      'checkout_acceptances',
      where: 'bill_uuid = ?',
      whereArgs: [reservedSale.billUuid],
    )).single;
    final saleAttemptId = saleAcceptance['attempt_id'] as String;
    final saleSnapshot = saleAcceptance['posting_snapshot'] as String;
    final saleReq = nativeSaleRequest(saleSnapshot)!;
    final saleRequestJson = jsonEncode(saleReq);
    await sql.update(
      'checkout_acceptances',
      {
        'native_sale_request': saleRequestJson,
        'native_sale_state': 'pending',
      },
      where: 'attempt_id = ?',
      whereArgs: [saleAttemptId],
    );

    final followUpSale = await checkout(quantity: 2, paidAmount: 0);
    await helper.recordBillPayment(
      followUpSale.billId,
      amount: 75,
      paymentMethod: 'upi',
      paymentReference: 'UTR-SEED-1',
    );
    final paymentRow = (await sql.query(
      'bill_payments',
      where: 'bill_uuid = ?',
      whereArgs: [followUpSale.billUuid],
    )).single;
    final followUpPaymentUuid = paymentRow['uuid'] as String;
    final paymentCommandId = const Uuid().v4();
    final paymentRequestJson = jsonEncode({
      'payment_uuid': followUpPaymentUuid,
      'device_id': scope.deviceId,
      'received_at': paymentRow['received_at'],
      'amount': '75.00',
      'method': 'upi',
      'reference': 'UTR-SEED-1',
      'notes': null,
    });
    final paymentReservedJson = jsonEncode({
      'bill_payments': [followUpPaymentUuid],
      'bills': [followUpSale.billUuid],
    });
    await sql.insert('native_billing_commands', {
      'command_id': paymentCommandId,
      'shop_id': scope.shopId,
      'owner': scope.owner!,
      'device_id': scope.deviceId,
      'command_type': 'payment',
      'bill_uuid': followUpSale.billUuid,
      'target_uuid': followUpPaymentUuid,
      'request_json': paymentRequestJson,
      'reserved_uuids_json': paymentReservedJson,
      'state': 'pending',
      'last_error': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    return (
      saleAttemptId: saleAttemptId,
      saleBillUuid: reservedSale.billUuid,
      saleItemUuid: reservedSale.itemUuid,
      saleRequestJson: saleRequestJson,
      paymentCommandId: paymentCommandId,
      followUpBillUuid: followUpSale.billUuid,
      followUpPaymentUuid: followUpPaymentUuid,
      paymentRequestJson: paymentRequestJson,
      paymentReservedJson: paymentReservedJson,
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    DatabaseHelper.databaseFileName = 'native-mixed-version-restore.db';
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    work = await Directory.systemTemp.createTemp('storely_mixed_version_test');
    await helper.setCloudSyncState('preference_owner', 'original-owner');
    scope = await helper.captureCheckoutScope();
    server = _MixedVersionBackend()..memberShopId = scope.shopId;
    productId = await helper.insertProduct(
      Product(name: 'Rice', sellingPrice: 100, quantity: 30),
    );
  });

  tearDown(() async {
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
    if (work.existsSync()) {
      await work.delete(recursive: true);
    }
  });

  test(
    'pre-native_billing_commands SQLite schema upgrade preserves all checkout_acceptances',
    () async {
      final legacyBill = await checkout(quantity: 1, paidAmount: 100);
      final prooflessBill = await checkout(quantity: 1, paidAmount: 100);
      final strictBill = await checkout(quantity: 1, paidAmount: 100);

      final raw = await helper.database;

      // (a) Legacy null-snapshot row.
      await raw.update(
        'checkout_acceptances',
        {
          'posting_snapshot': null,
          'native_sale_request': null,
          'native_sale_state': null,
        },
        where: 'bill_uuid = ?',
        whereArgs: [legacyBill.billUuid],
      );

      // (b) Proofless v1 pending row (no line snapshot).
      final prooflessRow = (await raw.query(
        'checkout_acceptances',
        where: 'bill_uuid = ?',
        whereArgs: [prooflessBill.billUuid],
      )).single;
      final prooflessReq = nativeSaleRequest(
        prooflessRow['posting_snapshot'] as String,
      )!;
      for (final line in (prooflessReq['lines'] as List).cast<Map>()) {
        line.remove('snapshot');
      }
      await raw.update(
        'checkout_acceptances',
        {
          'native_sale_request': jsonEncode(prooflessReq),
          'native_sale_state': 'pending',
        },
        where: 'bill_uuid = ?',
        whereArgs: [prooflessBill.billUuid],
      );

      // (c) Strict v1 pending row (with line snapshot).
      final strictRow = (await raw.query(
        'checkout_acceptances',
        where: 'bill_uuid = ?',
        whereArgs: [strictBill.billUuid],
      )).single;
      final strictReq = nativeSaleRequest(
        strictRow['posting_snapshot'] as String,
      )!;
      await raw.update(
        'checkout_acceptances',
        {
          'native_sale_request': jsonEncode(strictReq),
          'native_sale_state': 'pending',
        },
        where: 'bill_uuid = ?',
        whereArgs: [strictBill.billUuid],
      );

      final beforeRows = await raw.query(
        'checkout_acceptances',
        orderBy: 'bill_id ASC',
      );
      expect(beforeRows, hasLength(3));

      // Simulate an older schema before `native_billing_commands` existed.
      await raw.execute('DROP INDEX IF EXISTS idx_native_billing_commands_pending');
      await raw.execute('DROP TABLE IF EXISTS native_billing_commands');
      await raw.execute('PRAGMA user_version = 27');
      await helper.close();

      // Reopen via DatabaseHelper.instance.database to run upgrade + ensureSchema.
      final upgraded = await helper.database;

      final tableCheck = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'native_billing_commands'",
      );
      expect(tableCheck, hasLength(1));

      final indexCheck = await upgraded.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_native_billing_commands_pending'",
      );
      expect(indexCheck, hasLength(1));

      final versionCheck = await upgraded.rawQuery('PRAGMA user_version');
      expect(versionCheck.single.values.first, 28);

      final afterRows = await upgraded.query(
        'checkout_acceptances',
        orderBy: 'bill_id ASC',
      );
      expect(afterRows, hasLength(3));

      for (var i = 0; i < 3; i++) {
        expect(afterRows[i]['attempt_id'], beforeRows[i]['attempt_id']);
        expect(
          afterRows[i]['posting_snapshot'],
          beforeRows[i]['posting_snapshot'],
        );
        expect(
          afterRows[i]['native_sale_request'],
          beforeRows[i]['native_sale_request'],
        );
        expect(
          afterRows[i]['native_sale_state'],
          beforeRows[i]['native_sale_state'],
        );
      }

      // Explicitly verify the 3 distinct shapes survived.
      expect(afterRows[0]['posting_snapshot'], isNull);
      expect(afterRows[0]['native_sale_request'], isNull);
      expect(afterRows[0]['native_sale_state'], isNull);

      expect(afterRows[1]['native_sale_state'], 'pending');
      final decodedProofless =
          jsonDecode(afterRows[1]['native_sale_request'] as String) as Map;
      expect(
        ((decodedProofless['lines'] as List).single as Map)['snapshot'],
        isNull,
      );

      expect(afterRows[2]['native_sale_state'], 'pending');
      final decodedStrict =
          jsonDecode(afterRows[2]['native_sale_request'] as String) as Map;
      expect(
        ((decodedStrict['lines'] as List).single as Map)['snapshot'],
        isNotNull,
      );
    },
  );

  test(
    'downgraded or flag-off build never leaks reserved sales or billing commands into legacy row sync',
    () async {
      final seeded = await seedPendingSaleAndPaymentReservations();

      // Plain FakeSyncBackend does not implement NativeSaleSyncBackend or
      // NativeBillingCommandSyncBackend (simulates a downgraded/legacy build).
      final legacy = FakeSyncBackend()..memberShopId = scope.shopId;
      final result = await sync(
        mode: FirstSyncMode.uploadExisting,
        backend: legacy,
      );
      expect(result.conflicts, isEmpty);

      // Zero reserved rows pushed to legacy backend.
      expect(legacy.row('bills', seeded.saleBillUuid), isNull);
      expect(legacy.row('bills', seeded.followUpBillUuid), isNull);
      expect(
        legacy
            .rows('bill_items')
            .where((row) => row['bill_uuid'] == seeded.saleBillUuid),
        isEmpty,
      );
      expect(
        legacy
            .rows('bill_payments')
            .where(
              (row) =>
                  row['bill_uuid'] == seeded.saleBillUuid ||
                  row['uuid'] == seeded.followUpPaymentUuid,
            ),
        isEmpty,
      );
      expect(
        legacy
            .rows('stock_movements')
            .where((row) => row['source_document_uuid'] == seeded.saleBillUuid),
        isEmpty,
      );

      // Both reservations remain pending.
      final pendingSales = await helper.pendingNativeSales(scope);
      expect(pendingSales, hasLength(1));
      expect(pendingSales.single.attemptId, seeded.saleAttemptId);
      expect(pendingSales.single.state, 'pending');

      final pendingCmds = await helper.pendingNativeBillingCommands(scope);
      expect(pendingCmds, hasLength(1));
      expect(pendingCmds.single.commandId, seeded.paymentCommandId);
      expect(pendingCmds.single.state, 'pending');
    },
  );

  test(
    'BackupService backup and restore preserves reservations, operation keys, and cross-account isolation',
    () async {
      final seeded = await seedPendingSaleAndPaymentReservations();

      final backupFile = await BackupService.createBackupFile(workDir: work);
      final (_, dbBytes) = await BackupService.readBackup(
        await backupFile.readAsBytes(),
        workDir: work,
      );

      // Wipe reservations and mutate the active database.
      final sql = await helper.database;
      await sql.delete('checkout_acceptances');
      await sql.delete('native_billing_commands');
      await helper.insertProduct(Product(name: 'Temp Sugar', mrp: 45, quantity: 5));
      expect(await helper.pendingNativeSales(scope), isEmpty);
      expect(await helper.pendingNativeBillingCommands(scope), isEmpty);

      // Restore from backup and reopen.
      await BackupService.restore(dbBytes, keepDir: work);

      final restoredSales = await helper.pendingNativeSales(scope);
      expect(restoredSales, hasLength(1));
      expect(restoredSales.single.attemptId, seeded.saleAttemptId);
      expect(restoredSales.single.billUuid, seeded.saleBillUuid);
      expect(restoredSales.single.request, seeded.saleRequestJson);
      expect(restoredSales.single.state, 'pending');

      final restoredCmds = await helper.pendingNativeBillingCommands(scope);
      expect(restoredCmds, hasLength(1));
      expect(restoredCmds.single.commandId, seeded.paymentCommandId);
      expect(restoredCmds.single.billUuid, seeded.followUpBillUuid);
      expect(restoredCmds.single.requestJson, seeded.paymentRequestJson);
      expect(restoredCmds.single.reservedUuidsJson, seeded.paymentReservedJson);
      expect(restoredCmds.single.state, 'pending');

      // Cross-account isolation after restore: switch preference_owner.
      await helper.setCloudSyncState('preference_owner', 'different-owner');
      final result = await sync(mode: FirstSyncMode.uploadExisting);
      expect(result.conflicts, isEmpty);
      expect(server.sentSales, isEmpty);
      expect(server.sentPayments, isEmpty);
      expect(server.sentCancels, isEmpty);
      expect(server.sentCreditNotes, isEmpty);
      expect(server.row('bills', seeded.saleBillUuid), isNull);
      expect(server.row('bills', seeded.followUpBillUuid), isNull);
      expect(
        server
            .rows('bill_payments')
            .where(
              (row) =>
                  row['bill_uuid'] == seeded.saleBillUuid ||
                  row['uuid'] == seeded.followUpPaymentUuid,
            ),
        isEmpty,
      );

      // Original owner's reservations remain untouched in SQLite.
      await helper.setCloudSyncState('preference_owner', 'original-owner');
      expect(
        (await helper.pendingNativeSales(scope)).single.attemptId,
        seeded.saleAttemptId,
      );
      expect(
        (await helper.pendingNativeBillingCommands(scope)).single.commandId,
        seeded.paymentCommandId,
      );
    },
  );

  group(
    'opt-in native mixed-version, backup/restore & isolation',
    skip: !nativeSalePostingEnabled,
    () {
      setUp(() async {
        await sync(mode: FirstSyncMode.uploadExisting);
      });

      test(
        'full SQLite backup and restore preserves live sale, payment, and credit note reservations and delivers them in order',
        () async {
          final sale = await checkout(quantity: 3, paidAmount: 0);
          await helper.recordBillPayment(
            sale.billId,
            amount: 100,
            paymentMethod: 'upi',
            paymentReference: 'UTR-BACKUP-1',
          );
          final cnId = await helper.createCreditNote(
            billId: sale.billId,
            quantities: {sale.itemUuid: 1},
            settlement: DatabaseBills.creditNoteSettleRefund,
            refundMethod: 'cash',
            reason: 'Damaged unit',
          );
          final cn = (await helper.getBillById(cnId))!;

          final originalSale = (await helper.pendingNativeSales(scope)).single;
          final originalCmds = await helper.pendingNativeBillingCommands(scope);
          expect(originalCmds, hasLength(2));
          expect(originalCmds[0].commandType, 'payment');
          expect(originalCmds[1].commandType, 'credit_note');

          // Backup via BackupService, wipe active DB, and restore.
          final backupFile = await BackupService.createBackupFile(workDir: work);
          final (_, dbBytes) = await BackupService.readBackup(
            await backupFile.readAsBytes(),
            workDir: work,
          );

          final sql = await helper.database;
          await sql.delete('checkout_acceptances');
          await sql.delete('native_billing_commands');
          expect(await helper.pendingNativeSales(scope), isEmpty);
          expect(await helper.pendingNativeBillingCommands(scope), isEmpty);

          await BackupService.restore(dbBytes, keepDir: work);

          final restoredSale = (await helper.pendingNativeSales(scope)).single;
          final restoredCmds = await helper.pendingNativeBillingCommands(scope);
          expect(restoredSale.attemptId, originalSale.attemptId);
          expect(restoredSale.billUuid, originalSale.billUuid);
          expect(restoredSale.request, originalSale.request);
          expect(restoredCmds, hasLength(2));
          for (var i = 0; i < 2; i++) {
            expect(restoredCmds[i].commandId, originalCmds[i].commandId);
            expect(restoredCmds[i].commandType, originalCmds[i].commandType);
            expect(restoredCmds[i].requestJson, originalCmds[i].requestJson);
            expect(
              restoredCmds[i].reservedUuidsJson,
              originalCmds[i].reservedUuidsJson,
            );
          }

          // Sync delivers all 3 commands in order with exact original keys.
          server.callOrder.clear();
          final result = await sync();
          expect(result.conflicts, isEmpty);
          expect(server.callOrder, ['sale', 'payment', 'credit_note']);
          expect(server.sentSales.single, (
            originalSale.attemptId,
            originalSale.request,
          ));
          expect(server.sentPayments.single, (
            originalCmds[0].commandId,
            sale.billUuid,
            originalCmds[0].requestJson,
          ));
          expect(server.sentCreditNotes.single, (
            originalCmds[1].commandId,
            sale.billUuid,
            originalCmds[1].requestJson,
          ));

          // Zero reserved rows leaked into legacy row sync, reservations cleared.
          expect(server.row('bills', sale.billUuid), isNull);
          expect(server.row('bills', cn.uuid), isNull);
          expect(server.rows('bill_payments'), isEmpty);
          expect(await helper.pendingNativeSales(scope), isEmpty);
          expect(await helper.pendingNativeBillingCommands(scope), isEmpty);
          expect(await helper.pendingSyncCounts(), isEmpty);
        },
      );

      test(
        'mixed-version server capability loss replays previously reserved commands and falls back new writes to legacy row sync',
        () async {
          final reservedSale = await checkout(quantity: 2, paidAmount: 0);
          await helper.recordBillPayment(
            reservedSale.billId,
            amount: 50,
            paymentMethod: 'cash',
          );
          final pendingSale = (await helper.pendingNativeSales(scope)).single;
          final pendingPayment =
              (await helper.pendingNativeBillingCommands(scope)).single;

          // Server stops advertising native capabilities.
          server.saleSupported = false;
          server.billingCommandsSupported = false;

          // Previously reserved commands still replay via their original endpoints.
          server.callOrder.clear();
          var result = await sync();
          expect(result.conflicts, isEmpty);
          expect(server.callOrder, ['sale', 'payment']);
          expect(server.sentSales.single.$1, pendingSale.attemptId);
          expect(server.sentPayments.single.$1, pendingPayment.commandId);
          expect(server.row('bills', reservedSale.billUuid), isNull);
          expect(await helper.pendingNativeSales(scope), isEmpty);
          expect(await helper.pendingNativeBillingCommands(scope), isEmpty);

          // New checkout and new payment created after capability loss fall
          // back cleanly to legacy row sync.
          final legacySale = await checkout(quantity: 1, paidAmount: 0);
          await helper.recordBillPayment(
            legacySale.billId,
            amount: 40,
            paymentMethod: 'upi',
          );
          expect(await helper.pendingNativeSales(scope), isEmpty);
          expect(await helper.pendingNativeBillingCommands(scope), isEmpty);

          server.callOrder.clear();
          result = await sync();
          expect(result.conflicts, isEmpty);
          expect(server.callOrder, isEmpty);
          expect(server.sentSales, hasLength(1));
          expect(server.sentPayments, hasLength(1));
          expect(server.row('bills', legacySale.billUuid), isNotNull);
          expect(
            server
                .rows('bill_payments')
                .where((row) => row['bill_uuid'] == legacySale.billUuid),
            hasLength(1),
          );
        },
      );

      test(
        'cross-account isolation after restore keeps original owner live reservations hidden from new owner sync',
        () async {
          final sale = await checkout(quantity: 2, paidAmount: 0);
          await helper.recordBillPayment(
            sale.billId,
            amount: 60,
            paymentMethod: 'cash',
          );
          final originalSale = (await helper.pendingNativeSales(scope)).single;
          final originalCmd =
              (await helper.pendingNativeBillingCommands(scope)).single;

          final backupFile = await BackupService.createBackupFile(workDir: work);
          final (_, dbBytes) = await BackupService.readBackup(
            await backupFile.readAsBytes(),
            workDir: work,
          );
          await BackupService.restore(dbBytes, keepDir: work);

          // Switch active owner on the restored DB.
          await helper.setCloudSyncState('preference_owner', 'other-user');
          final result = await sync();
          expect(result.conflicts, isEmpty);
          expect(server.sentSales, isEmpty);
          expect(server.sentPayments, isEmpty);
          expect(server.row('bills', sale.billUuid), isNull);
          expect(server.rows('bill_payments'), isEmpty);

          // Switch back to original owner -> reservations still pending and deliverable.
          await helper.setCloudSyncState('preference_owner', 'original-owner');
          expect(
            (await helper.pendingNativeSales(scope)).single.attemptId,
            originalSale.attemptId,
          );
          expect(
            (await helper.pendingNativeBillingCommands(scope)).single.commandId,
            originalCmd.commandId,
          );
        },
      );
    },
  );
}
