import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/invoice_numbering.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(p.join(await getDatabasesPath(), 'storely.db'));
    // Registered shop, 5% GST, price = cost 100 + 50% margin = 150 + GST.
    await db.saveGlobalPricingSettings(
      const GlobalPricingSettings(
        defaultGstPercent: 5,
        defaultOverheadCost: 0,
        defaultProfitMarginPercent: 50,
        gstRegistered: true,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(p.join(await getDatabasesPath(), 'storely.db'));
  });

  Future<int> product() => db.insertProduct(
    Product(name: 'Rice', mrp: 0, purchasePrice: 100, quantity: 10),
  );

  /// A 3-unit invoice the way checkout saves it. 157.50 each incl. 5% GST.
  Future<Bill> sell(int productId, {bool paid = true}) async {
    final cart = await db.buildBillItemForProduct(
      (await db.getProductById(productId))!,
    );
    cart.quantity = 3;
    final item = BillTotals.taxedItem(
      cart,
      discountPercent: 0,
      gstRegistered: true,
      interState: false,
    );
    final t = BillTotals.fromTaxedItems([item], roundOff: true);
    final id = await db.insertBill(
      Bill(
        customerName: 'Asha',
        customerPhone: '9876543210',
        subtotalAmount: t.subtotal,
        taxableAmount: t.taxableAmount,
        cgstAmount: t.cgstAmount,
        sgstAmount: t.sgstAmount,
        roundOffAmount: t.roundOffAmount,
        totalAmount: t.grandTotal,
        itemCount: 1,
        isPaid: paid,
        paidAmount: paid ? t.grandTotal : 0,
      ),
      [item],
    );
    return (await db.getBillById(id))!;
  }

  test('a refund credit note returns stock and nets sales and GST', () async {
    final productId = await product();
    final bill = await sell(productId); // 472.50 -> 473 after round-off
    final line = bill.items.single;

    final cnId = await db.createCreditNote(
      billId: bill.id!,
      quantities: {line.uuid: 1},
      settlement: DatabaseBills.creditNoteSettleRefund,
      reason: 'Damaged bag',
    );
    final cn = (await db.getBillById(cnId))!;

    final fy = InvoiceNumbering.financialYear(DateTime.now());
    expect(cn.billNumber, 'CN/$fy/0001');
    expect(cn.isCreditNote, isTrue);
    expect(cn.originalBillNumber, bill.billNumber);
    expect(cn.items.single.quantity, -1);
    expect(cn.items.single.originalItemUuid, line.uuid);
    expect(cn.totalAmount, -158); // 157.50 rounded
    expect(cn.taxableAmount, -150);
    expect(cn.cgstAmount + cn.sgstAmount, closeTo(-7.5, 1e-9));
    expect(cn.paymentStatus, Bill.statusPaid);
    expect(cn.balanceDue, 0);

    expect((await db.getProductById(productId))!.quantity, 8);
    expect((await db.returnableQuantities(bill.id!))[line.uuid], 2);
    expect(await db.kpiTotalRevenue(), 473 - 158);
    expect(await db.kpiCollected(), 473 - 158);
    expect(await db.kpiGstCollected(), closeTo(22.5 - 7.5, 0.011));
    expect(await db.kpiGrossProfit(), 100); // 2 units x 50
    expect(await db.getTodayBillCount(), 1, reason: 'credit notes are not bills');
  });

  test('cannot return more than was sold minus earlier returns', () async {
    final bill = await sell(await product());
    final line = bill.items.single;
    await db.createCreditNote(
      billId: bill.id!,
      quantities: {line.uuid: 2},
      settlement: DatabaseBills.creditNoteSettleRefund,
    );
    await expectLater(
      db.createCreditNote(
        billId: bill.id!,
        quantities: {line.uuid: 2},
        settlement: DatabaseBills.creditNoteSettleRefund,
      ),
      throwsArgumentError,
    );
  });

  test('adjusting against dues reduces what the customer owes', () async {
    final bill = await sell(await product(), paid: false); // owes 473
    final cnId = await db.createCreditNote(
      billId: bill.id!,
      quantities: {bill.items.single.uuid: 1},
      settlement: DatabaseBills.creditNoteSettleAdjust,
    );
    final original = (await db.getBillById(bill.id!))!;
    expect(original.balanceDue, 473 - 158);
    expect(original.paymentStatus, Bill.statusPartial);
    expect((await db.getBillById(cnId))!.paymentStatus, Bill.statusPaid);
    expect(await db.kpiCollected(), 0, reason: 'no cash moved');
    expect((await db.kpiUnpaidBillsValue())['total'], 473 - 158);
  });

  test('adjustment larger than the dues is refused', () async {
    final bill = await sell(await product(), paid: false);
    await db.recordBillPayment(bill.id!, amount: 400); // owes 73
    await expectLater(
      db.createCreditNote(
        billId: bill.id!,
        quantities: {bill.items.single.uuid: 1},
        settlement: DatabaseBills.creditNoteSettleAdjust,
      ),
      throwsArgumentError,
    );
  });

  test('an invoice with a credit note cannot be cancelled until the credit '
      'note is; cancelling the credit note undoes it', () async {
    final productId = await product();
    final bill = await sell(productId, paid: false);
    final cnId = await db.createCreditNote(
      billId: bill.id!,
      quantities: {bill.items.single.uuid: 1},
      settlement: DatabaseBills.creditNoteSettleAdjust,
    );
    await expectLater(
      db.cancelBill(bill.id!, reason: 'x'),
      throwsA(isA<StateError>()),
    );

    await db.cancelBill(cnId, reason: 'Issued by mistake');
    expect((await db.getProductById(productId))!.quantity, 7);
    expect((await db.getBillById(bill.id!))!.balanceDue, 473);
    expect(
      (await db.returnableQuantities(bill.id!))[bill.items.single.uuid],
      3,
    );
    await db.cancelBill(bill.id!, reason: 'Now allowed');
    expect((await db.getProductById(productId))!.quantity, 10);
  });

  test('only admins can issue credit notes', () async {
    final bill = await sell(await product());
    db.assertAdminMutation = () async =>
        throw StateError('Only shop admins can do this');
    addTearDown(() => db.assertAdminMutation = null);
    await expectLater(
      db.createCreditNote(
        billId: bill.id!,
        quantities: {bill.items.single.uuid: 1},
        settlement: DatabaseBills.creditNoteSettleRefund,
      ),
      throwsA(isA<StateError>()),
    );
  });
}
