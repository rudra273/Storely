import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/services/gstr1_export.dart';

/// One-line bill at [rate]% on [taxable] per unit x [qty]. Intra-state
/// unless [inter]. Negative [qty] makes a credit note line.
Bill bill(
  String number, {
  double taxable = 100,
  double qty = 1,
  double rate = 18,
  bool inter = false,
  String? gstin,
  String pos = '27',
  bool creditNote = false,
  bool cancelled = false,
  String hsn = '1006',
  String unit = 'kg',
}) {
  final gst = taxable * rate / 100;
  final item = BillItem(
    productName: 'Rice',
    hsnCodeSnapshot: hsn,
    unit: unit,
    mrp: taxable + gst,
    quantity: qty,
    gstPercentSnapshot: rate,
    gstSnapshot: gst,
    taxableValueSnapshot: taxable,
    cgstAmountSnapshot: inter ? 0 : gst / 2,
    sgstAmountSnapshot: inter ? 0 : gst / 2,
    igstAmountSnapshot: inter ? gst : 0,
  );
  final lineGst = gst * qty;
  return Bill(
    billNumber: number,
    customerName: gstin == null ? 'Walk-in' : 'Mehta Traders',
    customerGstin: gstin,
    placeOfSupplyStateCode: pos,
    taxableAmount: taxable * qty,
    cgstAmount: inter ? 0 : lineGst / 2,
    sgstAmount: inter ? 0 : lineGst / 2,
    igstAmount: inter ? lineGst : 0,
    totalAmount: (taxable + gst) * qty,
    itemCount: 1,
    documentType: creditNote ? Bill.documentCreditNote : Bill.documentInvoice,
    createdAt: DateTime(2026, 9, 10),
    deletedAt: cancelled ? DateTime(2026, 9, 11) : null,
    items: [item],
  );
}

void main() {
  final shop = ShopProfile(
    name: 'Sharma Kirana',
    gstin: '27ABCDE1234F1Z5',
    gstScheme: GstScheme.regular,
  );
  const buyer = '27AAAAA0000A1Z5';

  final export = Gstr1Export(
    shop: shop,
    bills: [
      bill('INV/2627/0001', gstin: buyer, qty: 2), // b2b
      bill('INV/2627/0002', qty: 3), // b2cs intra
      bill('INV/2627/0003', taxable: 120000, inter: true, pos: '29'), // b2cl
      bill('INV/2627/0004', taxable: 500, inter: true, pos: '29'), // b2cs
      bill('CN/2627/0001', gstin: buyer, qty: -1, creditNote: true), // cdnr
      bill('CN/2627/0002', qty: -1, creditNote: true), // nets into b2cs
      bill('INV/2627/0005', cancelled: true),
    ],
  );

  test('invoices land in the right sheets', () {
    final b2b = export.b2b();
    expect(b2b, hasLength(2));
    expect(b2b[1][0], buyer);
    expect(b2b[1][2], 'INV/2627/0001');
    expect(b2b[1][3], '10-Sep-2026');
    expect(b2b[1][5], '27-Maharashtra');
    expect(b2b[1][10], 18);
    expect(b2b[1][11], 200);

    final b2cl = export.b2cl();
    expect(b2cl.skip(1).map((r) => r[0]), ['INV/2627/0003']);
    expect(b2cl[1][3], '29-Karnataka');

    final cdnr = export.cdnr();
    expect(cdnr.skip(1).map((r) => r[2]), ['CN/2627/0001']);
    expect(cdnr[1][4], 'C');
    expect(cdnr[1][11], 100);
  });

  test('b2cs sums by place of supply and rate, net of B2C returns', () {
    final rows = {for (final r in export.b2cs().skip(1)) r[1]: r[4]};
    expect(rows['27-Maharashtra'], 200); // 3 sold - 1 returned
    expect(rows['29-Karnataka'], 500);
  });

  test('HSN summaries split B2B and B2C with tax heads', () {
    final b2b = export.hsn(b2b: true);
    expect(b2b, hasLength(2));
    expect(b2b[1][0], '1006');
    expect(b2b[1][2], 'KGS');
    expect(b2b[1][3], 1); // 2 sold - 1 credit note
    expect(b2b[1][6], 100);
    expect(b2b[1][8], 9); // CGST
    expect(b2b[1][9], 9); // SGST

    final b2c = export.hsn(b2b: false);
    final igst = b2c.skip(1).fold<double>(0, (s, r) => s + (r[7] as num));
    expect(igst, closeTo(120000 * 0.18 + 90, 0.01));
  });

  test('docs counts issued and cancelled numbers', () {
    final docs = export.docs();
    expect(docs[1], [
      'Invoices for outward supply',
      'INV/2627/0001',
      'INV/2627/0005',
      5,
      1,
    ]);
    expect(docs[2], ['Credit Note', 'CN/2627/0001', 'CN/2627/0002', 2, 0]);
  });

  test('workbook has all sheets and units map to UQC', () {
    expect(export.sheets().keys, [
      'b2b',
      'b2cl',
      'b2cs',
      'cdnr',
      'hsn(b2b)',
      'hsn(b2c)',
      'docs',
    ]);
    final book = xl.Excel.decodeBytes(export.toXlsx());
    expect(book.tables.keys.toSet(), export.sheets().keys.toSet());
    expect(book.tables['b2b']!.rows[1][2]!.value.toString(), 'INV/2627/0001');
    expect(Gstr1Export.uqcFor('pcs'), 'NOS');
    expect(Gstr1Export.uqcFor('dozen'), 'DOZ');
    expect(Gstr1Export.uqcFor('bundle'), 'OTH');
  });
}
