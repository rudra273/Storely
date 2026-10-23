import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';
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

  test('bill corrections are recorded in the audit trail', () async {
    db.auditActor = () => 'owner@shop.in';
    addTearDown(() => db.auditActor = null);
    final productId = await product();
    final bill = await sell(productId, paid: false); // 473 due

    await db.recordBillPayment(bill.id!, amount: 100, paymentMethod: 'upi');
    await db.updateBillCustomerDetails(
      bill.id!,
      customerName: 'Asha Devi',
      customerPhone: '9876543210',
      isB2b: false,
    );
    await db.updateBillPaidStatus(bill.id!, false); // reverses the 100
    await db.createCreditNote(
      billId: bill.id!,
      quantities: {bill.items.single.uuid: 1},
      settlement: DatabaseBills.creditNoteSettleAdjust,
      reason: 'Torn bag',
    );
    await db.updateBillProfitCommissionPercent(bill.id!, 5);

    final log = await db.getBillAudit(bill.uuid);
    expect(log.map((e) => e.action), [
      AuditAction.payment,
      AuditAction.edited,
      AuditAction.markedUnpaid,
      AuditAction.creditNote,
      AuditAction.commission,
    ]);
    expect(log[0].details, contains('100.00 UPI'));
    expect(log[1].details, 'Name: Asha → Asha Devi');
    expect(log[2].details, contains('100.00 of payments reversed'));
    expect(log[3].details, contains('Torn bag'));
    expect(log.every((e) => e.actor == 'owner@shop.in'), isTrue);
  });

  test('cancelling logs the reason; new bills log nothing', () async {
    final productId = await product();
    final bill = await sell(productId);
    expect(await db.getBillAudit(bill.uuid), isEmpty);
    await db.cancelBill(bill.id!, reason: 'Wrong customer');
    final log = await db.getBillAudit(bill.uuid);
    expect(log.single.action, AuditAction.cancelled);
    expect(log.single.details, startsWith('Wrong customer'));
    expect(log.single.actor, 'This phone');
  });
}
