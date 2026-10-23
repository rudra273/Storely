import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';

void main() {
  late DatabaseHelper db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = DatabaseHelper.instance;
    await db.close();
    await _deleteStorelyDb();
  });

  tearDown(() async {
    await db.close();
    await _deleteStorelyDb();
  });

  /// Saves a bill the way the billing screen does.
  Future<int> sell(
    int productId,
    double qty, {
    double discount = 0,
    bool paid = true,
    bool registered = false,
  }) async {
    final product = await db.getProductById(productId);
    final cartItem = await db.buildBillItemForProduct(product!);
    cartItem.quantity = qty;
    final item = BillTotals.taxedItem(
      cartItem,
      discountPercent: discount,
      gstRegistered: registered,
      interState: false,
    );
    final t = BillTotals.fromTaxedItems([item], roundOff: false);
    return db.insertBill(
      Bill(
        customerName: 'Customer',
        subtotalAmount: t.subtotal,
        discountPercent: discount,
        discountAmount: t.discountAmount,
        taxableAmount: t.taxableAmount,
        cgstAmount: t.cgstAmount,
        sgstAmount: t.sgstAmount,
        igstAmount: t.igstAmount,
        totalAmount: t.grandTotal,
        itemCount: qty.round(),
        isPaid: paid,
        paidAmount: paid ? t.grandTotal : 0,
      ),
      [item],
    );
  }

  Future<int> product({required bool registered, double gst = 0}) async {
    await db.saveGlobalPricingSettings(
      GlobalPricingSettings(
        defaultGstPercent: gst,
        defaultOverheadCost: 0,
        defaultProfitMarginPercent: 50,
        gstRegistered: registered,
      ),
    );
    return db.insertProduct(
      Product(name: 'Widget', mrp: 0, purchasePrice: 100, quantity: 50),
    );
  }

  test('sales count every bill; collected counts payments', () async {
    final id = await product(registered: false); // price 150, cost 100
    await sell(id, 2, discount: 10); // 270 paid
    await sell(id, 1, paid: false); // 150 unpaid
    final cancelled = await sell(id, 1); // excluded
    await db.cancelBill(cancelled, reason: 'test');

    expect(await db.kpiTotalRevenue(), 420);
    expect(await db.kpiCollected(), 270);
    expect(await db.kpiAverageOrderValue(), 210);
    final unpaid = await db.kpiUnpaidBillsValue();
    expect(unpaid['count'], 1);
    expect(unpaid['total'], 150);
  });

  test('profit is reduced by the bill discount', () async {
    final id = await product(registered: false);
    await sell(id, 2, discount: 10); // (135 - 100) x 2 = 70
    await sell(id, 1); // 50

    expect(await db.kpiGrossProfit(), 120);
    // 120 profit on 420 net revenue.
    expect(await db.kpiGrossMarginPercent(), closeTo(28.57, 0.01));
  });

  test('commission comes from the per-bill percentage', () async {
    final id = await product(registered: false);
    final billId = await sell(id, 2, discount: 10); // profit 70
    await sell(id, 1); // profit 50, no commission
    await db.updateBillProfitCommissionPercent(billId, 10);

    expect(await db.kpiTotalCommissionPaid(), 7);
    expect(await db.kpiNetProfitAfterCommission(), 113);
  });

  test('GST collected includes unpaid bills and excludes GST from profit',
      () async {
    // Registered: pre-GST price 150, 18% GST -> 177 per unit.
    final id = await product(registered: true, gst: 18);
    await sell(id, 1, registered: true);
    await sell(id, 1, registered: true, paid: false);

    expect(await db.kpiTotalRevenue(), 354);
    expect(await db.kpiGstCollected(), 54);
    expect(await db.kpiGrossProfit(), 100);
  });
}

Future<void> _deleteStorelyDb() async {
  final dbPath = await getDatabasesPath();
  await deleteDatabase(p.join(dbPath, 'storely.db'));
}
