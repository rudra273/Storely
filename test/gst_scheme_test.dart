import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/utils/bill_pdf_generator.dart';

void main() {
  group('document title', () {
    final defaults = BillSettings();

    test('GST bill is a tax invoice', () {
      expect(
        defaults.documentTitle(billHasGst: true, gstScheme: GstScheme.regular),
        'TAX INVOICE',
      );
    });

    test('composition and tax-free regular bills are bills of supply', () {
      expect(
        defaults.documentTitle(
          billHasGst: false,
          gstScheme: GstScheme.composition,
        ),
        'BILL OF SUPPLY',
      );
      expect(
        defaults.documentTitle(billHasGst: false, gstScheme: GstScheme.regular),
        'BILL OF SUPPLY',
      );
    });

    test('unregistered shop issues a plain bill', () {
      expect(
        defaults.documentTitle(
          billHasGst: false,
          gstScheme: GstScheme.unregistered,
        ),
        'BILL',
      );
    });

    test('custom title always wins', () {
      final custom = BillSettings(invoiceTitle: 'Estimate');
      expect(
        custom.documentTitle(billHasGst: true, gstScheme: GstScheme.regular),
        'ESTIMATE',
      );
    });
  });

  group('GST scheme persistence', () {
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

    test('composition scheme saves and does not charge GST', () async {
      await db.saveShopProfile(
        ShopProfile(
          name: 'Kirana',
          gstin: '27AAAAA0000A1Z5',
          gstScheme: GstScheme.composition,
        ),
      );
      final profile = await db.getShopProfile();
      expect(profile!.gstScheme, GstScheme.composition);
      expect(profile.gstRegistered, isFalse);
      expect((await db.getGlobalPricingSettings()).gstRegistered, isFalse);

      final bytes = await BillPdfGenerator.generate(
        bill: Bill(
          customerName: 'Walk-in',
          totalAmount: 100,
          itemCount: 1,
          items: [BillItem(productName: 'Rice', mrp: 100)],
        ),
        shop: profile,
      );
      expect(bytes.length, greaterThan(1000));
    });

    test('older data with only gst_registered reads as regular', () async {
      await db.saveGlobalPricingSettings(
        const GlobalPricingSettings(
          defaultGstPercent: 18,
          defaultOverheadCost: 0,
          defaultProfitMarginPercent: 0,
          gstRegistered: true,
        ),
      );
      await db.saveShopName('Old Shop');
      final profile = await db.getShopProfile();
      expect(profile!.gstScheme, GstScheme.regular);
      expect(profile.gstRegistered, isTrue);
    });
  });
}

Future<void> _deleteStorelyDb() async {
  final dbPath = await getDatabasesPath();
  await deleteDatabase(p.join(dbPath, 'storely.db'));
}
