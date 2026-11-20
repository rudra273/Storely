import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/held_bill.dart';
import 'package:storely/models/bill_settings.dart';

void main() {
  final helper = DatabaseHelper.instance;
  late SettingsEditBaseline baseline;
  late Bill bill;
  late List<BillItem> items;
  late String device;
  Future<int> save({Bill? request, String? shop, String? owner}) =>
      helper.insertReviewedCheckout(
        attemptId: 'stable-attempt',
        expectedShopId: shop ?? baseline.shopId,
        expectedOwner: owner,
        baseline: baseline,
        bill: request ?? bill,
        items: items,
        cartSnapshot: HeldBill.encodeItems(items),
        originDeviceId: device,
      );
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await helper.close();
    DatabaseHelper.databaseFileName = 'checkout-acceptance.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await helper.saveBillSettings(BillSettings());
    baseline = await helper.captureSettingsEditBaseline();
    device = await helper.localDeviceId();
    items = [
      BillItem(
        productName: 'Offline item',
        quantity: 1,
        mrp: 100,
        sellingPriceSnapshot: 100,
      ),
    ];
    bill = Bill(
      uuid: 'frozen-bill',
      shopId: baseline.shopId,
      customerName: 'Walk-in',
      totalAmount: 100,
      itemCount: 1,
      isPaid: false,
      paidAmount: 25,
      paymentMethod: 'cash',
    );
    await helper.saveCartDraft(items);
  });
  tearDown(() async {
    helper.onDatabaseChanged = null;
    await helper.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  test(
    'acceptance survives reopen and recovers before stale settings guard',
    () async {
      final id = await save();
      expect(await helper.loadCartDraft(), isEmpty);
      await helper.close();
      final sql = await helper.database;
      await sql.update('bill_settings', {'footer_text': 'later settings'});
      expect(await save(), id);
      expect(await helper.getAllBills(), hasLength(1));
      expect(await sql.query('bill_payments'), hasLength(1));
      final result = await helper.getBillById(id);
      expect(result!.paidAmount, 25);
      expect(result.balanceDue, 75);
    },
  );
  test(
    'reviewed adapter rejects excess payment instead of legacy clamping',
    () async {
      final invalid = Bill.fromMap({
        ...bill.toMap(),
        'paid_amount': 100.01,
      }, items);
      await expectLater(save(request: invalid), throwsFormatException);
      expect(await helper.getAllBills(), isEmpty);
      expect(await helper.loadCartDraft(), hasLength(1));
    },
  );
  test('changed body cannot reuse acceptance', () async {
    await save();
    final changed = Bill.fromMap({
      ...bill.toMap(),
      'customer_name': 'Changed',
    }, items);
    await expectLater(save(request: changed), throwsStateError);
    expect(await helper.getAllBills(), hasLength(1));
  });
  test('owner and tenant checked before accepted replay', () async {
    await save();
    await helper.setCloudSyncState('preference_owner', 'new-owner');
    await expectLater(save(), throwsStateError);
    await expectLater(
      save(owner: 'new-owner', shop: 'other-shop'),
      throwsStateError,
    );
  });
  test(
    'stale reviewed context rejects before effects and retains draft',
    () async {
      final sql = await helper.database;
      await sql.update('bill_settings', {'round_off_total': 0});
      await expectLater(save(), throwsA(isA<CheckoutReviewChanged>()));
      expect(await helper.getAllBills(), isEmpty);
      expect(await helper.loadCartDraft(), hasLength(1));
    },
  );
  test('late ledger failure rolls back bill payment and cart consume', () async {
    final sql = await helper.database;
    await sql.execute(
      "CREATE TRIGGER fail_checkout BEFORE INSERT ON checkout_acceptances BEGIN SELECT RAISE(ABORT, 'test late failure'); END",
    );
    await expectLater(save(), throwsA(isA<DatabaseException>()));
    expect(await helper.getAllBills(), isEmpty);
    expect(await sql.query('bill_payments'), isEmpty);
    expect(await helper.loadCartDraft(), hasLength(1));
    await sql.execute('DROP TRIGGER fail_checkout');
    await save();
    expect(await helper.getAllBills(), hasLength(1));
  });
  test('different newer cart is not consumed', () async {
    await helper.saveCartDraft([
      BillItem(productName: 'Other cart', quantity: 1, mrp: 10),
    ]);
    await save();
    expect((await helper.loadCartDraft()).single.productName, 'Other cart');
  });
  test(
    'stale accepted local ID cannot resolve to a different invoice',
    () async {
      final id = await save();
      final sql = await helper.database;
      await sql.update(
        'bills',
        {'uuid': 'replacement'},
        where: 'id = ?',
        whereArgs: [id],
      );
      await expectLater(save(), throwsStateError);
    },
  );
  test(
    'start fresh marking and reopen retain exact acceptance with invoice',
    () async {
      final id = await save();
      await helper.markAllCloudRowsClean();
      await helper.close();
      expect(await save(), id);
      expect(await helper.getAllBills(), hasLength(1));
    },
  );
  test(
    'v26 upgrade creates empty ledger without changing existing invoices',
    () async {
      await helper.insertBill(bill, items);
      var sql = await helper.database;
      await sql.execute('DROP TABLE checkout_acceptances');
      await sql.execute('PRAGMA user_version = 26');
      await helper.close();
      sql = await helper.database;
      expect(await sql.getVersion(), 28);
      expect(await sql.query('checkout_acceptances'), isEmpty);
      expect(await helper.getAllBills(), hasLength(1));
    },
  );
}
