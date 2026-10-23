import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/expense.dart';
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
  Future<Bill> sell(
    int productId, {
    bool paid = true,
    DateTime? createdAt,
  }) async {
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
        createdAt: createdAt,
      ),
      [item],
    );
    return (await db.getBillById(id))!;
  }

  String today() => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> scenario() async {
    final productId = await product();
    final paid = await sell(productId); // taxable 450, cost 300, total 473
    await sell(productId, paid: false); // 473 owed
    await db.createCreditNote(
      billId: paid.id!,
      quantities: {paid.items.single.uuid: 1},
      settlement: DatabaseBills.creditNoteSettleRefund,
    );
    await db.saveExpense(
      Expense(date: DateTime.now(), amount: 200, category: 'Tea & snacks'),
    );
    await db.saveExpense(
      Expense(
        date: DateTime.now(),
        amount: 500,
        category: 'Rent',
        paymentMethod: 'upi',
      ),
    );
  }

  test('day book: bills, money in and out, net cash', () async {
    await scenario();
    final book = await db.dayBook(today());
    expect(book.bills, hasLength(3));
    expect(book.paymentsByMethod['cash'], closeTo(473 - 158, 0.01));
    expect(book.totalExpenses, 700);
    // Cash in 473, refund 158, tea 200 (rent was UPI).
    expect(book.netCash, closeTo(115, 0.01));
  });

  test('P&L is net of returns and expenses, ex-GST', () async {
    await scenario();
    final pl = await db.profitAndLoss(from: today(), to: today());
    expect(pl.sales, closeTo(750, 0.01));
    expect(pl.costOfGoods, closeTo(500, 0.01));
    expect(pl.grossProfit, closeTo(250, 0.01));
    expect(pl.gstCollected, closeTo(37.5, 0.01));
    expect(pl.expenses, 700);
    expect(pl.netProfit, closeTo(-450, 0.01));
    expect(pl.expensesByCategory.keys.first, 'Rent');
  });

  test('receivables ageing buckets and stock valuation', () async {
    final productId = await product();
    await sell(productId, paid: false);
    await sell(
      productId,
      paid: false,
      createdAt: DateTime.now().subtract(const Duration(days: 40)),
    );
    final ageing = await db.receivablesAgeing();
    expect(ageing, hasLength(1));
    expect(ageing.single.customerName, 'Asha');
    expect(ageing.single.buckets[0], closeTo(473, 0.01));
    expect(ageing.single.buckets[2], closeTo(473, 0.01));
    expect(ageing.single.total, closeTo(946, 0.01));

    final stock = await db.stockValuation();
    expect(stock.single.quantity, 4);
    expect(stock.single.costValue, 400);
  });

  test('tax summary is net of credit notes, by rate', () async {
    await scenario();
    final rows = await db.taxSummary(from: today(), to: today());
    expect(rows.single.rate, 5);
    expect(rows.single.taxable, closeTo(750, 0.01));
    expect(rows.single.cgst, closeTo(18.75, 0.02));
    expect(rows.single.sgst, closeTo(18.75, 0.02));
    expect(rows.single.igst, 0);
  });

  test('purchase register lists stock received with cost', () async {
    final id = await product(); // 10 opening stock at 100
    final rice = (await db.getProductById(id))!;
    await db.restockProduct(
      rice.copyWith(purchasePrice: 110, purchaseBatchNo: 'R7'),
      quantityAdded: 5,
      purchaseDate: DateTime.now(),
    );
    final rows = await db.purchaseRegister(from: today(), to: today());
    expect(rows, hasLength(2));
    final restock = rows.firstWhere((r) => r.batchNo == 'R7');
    expect(restock.quantity, 5);
    expect(restock.unitCost, 110);
    expect(restock.amount, 550);
    expect(rows.fold<double>(0, (s, r) => s + r.amount), 1550);
  });
}
