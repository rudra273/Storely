import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/services/dues_reminder.dart';
import 'package:storely/utils/statement_pdf_generator.dart';

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(p.join(await getDatabasesPath(), 'storely.db'));
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(p.join(await getDatabasesPath(), 'storely.db'));
  });

  Future<int> unpaidBill(double total, DateTime createdAt) => db.insertBill(
    Bill(
      customerName: 'Asha',
      customerPhone: '9876543210',
      totalAmount: total,
      itemCount: 1,
      isPaid: false,
      createdAt: createdAt,
    ),
    [BillItem(productName: 'Item', mrp: total)],
  );

  test('a customer payment settles the oldest bills first', () async {
    final oldest = await unpaidBill(300, DateTime(2026, 9, 1));
    final middle = await unpaidBill(200, DateTime(2026, 9, 15));
    final newest = await unpaidBill(500, DateTime(2026, 10, 1));

    final touched = await db.recordCustomerPayment(
      billIds: [newest, middle, oldest],
      amount: 400,
    );

    expect(touched, 2);
    expect((await db.getBillById(oldest))!.balanceDue, 0);
    expect((await db.getBillById(oldest))!.paymentStatus, Bill.statusPaid);
    expect((await db.getBillById(middle))!.balanceDue, 100);
    expect((await db.getBillById(middle))!.paymentStatus, Bill.statusPartial);
    expect((await db.getBillById(newest))!.balanceDue, 500);
  });

  test('paying more than is due is refused and changes nothing', () async {
    final id = await unpaidBill(300, DateTime(2026, 9, 1));
    await expectLater(
      db.recordCustomerPayment(billIds: [id], amount: 301),
      throwsArgumentError,
    );
    expect((await db.getBillById(id))!.balanceDue, 300);
  });

  test('reminder message and WhatsApp link', () {
    final bills = [
      Bill(
        customerName: 'Asha',
        totalAmount: 300,
        itemCount: 1,
        isPaid: false,
        createdAt: DateTime(2026, 9, 1),
      ),
      Bill(
        customerName: 'Asha',
        totalAmount: 200,
        itemCount: 1,
        paidAmount: 50,
        createdAt: DateTime(2026, 9, 15),
      ),
    ];
    final text = DuesReminder.message(
      customerName: 'Asha',
      shopName: 'Sharma Kirana',
      unpaidBills: bills,
      upiId: 'sharmakirana@okicici',
    );
    expect(text, contains('Namaste Asha'));
    expect(text, contains('₹450.00 on 2 bills (since 01 Sep 2026)'));
    expect(text, contains('Pay by UPI: sharmakirana@okicici'));

    final link = DuesReminder.whatsAppLink('+91 98765 43210', text)!;
    expect(link.host, 'wa.me');
    expect(link.path, '/919876543210');
    expect(link.queryParameters['text'], text);
    expect(DuesReminder.whatsAppLink('98765 43210', 'x')!.path, '/919876543210');
    expect(DuesReminder.whatsAppLink('', 'x'), isNull);
  });

  test('statement PDF renders', () async {
    final bytes = await StatementPdfGenerator.generate(
      customerName: 'आशा Asha',
      customerPhone: '9876543210',
      bills: [
        Bill(
          billNumber: 'INV/2627/0001',
          customerName: 'Asha',
          totalAmount: 300,
          itemCount: 1,
          isPaid: false,
        ),
      ],
      shop: ShopProfile(name: 'Sharma Kirana'),
      settings: BillSettings(upiId: 'sharmakirana@okicici'),
    );
    expect(bytes.length, greaterThan(1000));
  });
}
