import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/gst_states.dart';
import 'package:storely/utils/upi.dart';

void main() {
  test('UPI link is NPCI-shaped and URL-encoded', () {
    final link = Upi.paymentLink(
      upiId: 'sharmakirana@okicici',
      payeeName: 'Sharma & Sons Kirana',
      amount: 1242,
      note: 'Bill INV/2627/0012',
      reference: 'INV/2627/0012',
    );
    expect(
      link,
      'upi://pay?pa=sharmakirana%40okicici&pn=Sharma%20%26%20Sons%20Kirana'
      '&am=1242.00&cu=INR&tn=Bill%20INV%2F2627%2F0012&tr=INV%2F2627%2F0012',
    );
    final uri = Uri.parse(link);
    expect(uri.queryParameters['pn'], 'Sharma & Sons Kirana');
    expect(uri.queryParameters['am'], '1242.00');
  });

  test('UPI ids are validated', () {
    expect(Upi.isValidId('sharmakirana@okicici'), isTrue);
    expect(Upi.isValidId('98220.12345@ybl'), isTrue);
    expect(Upi.isValidId('sharma kirana@ok'), isFalse);
    expect(Upi.isValidId('no-at-sign'), isFalse);
    expect(Upi.isValidId('@okicici'), isFalse);
  });

  test('GST state labels', () {
    expect(gstStateCode('27AAAAA0000A1Z5'), '27');
    expect(gstStateLabel('27'), '27 - Maharashtra');
    expect(gstStateLabel('36'), '36 - Telangana');
    expect(gstStateCode('x'), isNull);
  });

  test('invoice v2 settings save and load', () async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = DatabaseHelper.instance;
    await db.close();
    await deleteDatabase(p.join(await getDatabasesPath(), 'storely.db'));

    final current = await db.getBillSettings();
    await db.saveBillSettings(
      current.copyWith(
        paperSize: BillSettings.paperA5,
        upiId: 'shop@okhdfc',
        showUpiQr: false,
        showAmountInWords: false,
        showHsnSummary: false,
        termsText: 'No returns on sale items',
        bankDetails: 'A/c 123 · IFSC HDFC0001',
      ),
    );
    final saved = await db.getBillSettings();
    expect(saved.paperSize, BillSettings.paperA5);
    expect(saved.upiId, 'shop@okhdfc');
    expect(saved.showUpiQr, isFalse);
    expect(saved.showAmountInWords, isFalse);
    expect(saved.showHsnSummary, isFalse);
    expect(saved.termsText, 'No returns on sale items');
    expect(saved.bankDetails, 'A/c 123 · IFSC HDFC0001');
    await db.close();
    await deleteDatabase(p.join(await getDatabasesPath(), 'storely.db'));
  });
}
