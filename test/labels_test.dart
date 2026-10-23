import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/utils/pdf_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  tearDown(() async {
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
  });

  test('short codes only for products without barcode or code', () async {
    final a = await db.insertProduct(
      Product(name: 'Loose rice', mrp: 50, quantity: 1),
    );
    final b = await db.insertProduct(
      Product(name: 'Soap', mrp: 30, quantity: 1, barcode: '8901234567890'),
    );
    expect(await db.assignShortCodes([a, b]), 1);
    final rice = (await db.getProductById(a))!;
    expect(rice.productCode, matches(RegExp(r'^P[0-9A-F]{7}$')));
    expect(PdfGenerator.barcodeData(rice), rice.productCode);
    expect((await db.getProductById(b))!.productCode, isNull);

    // The scanner finds it by the short code.
    final found = await db.findProductForBilling(
      itemCode: rice.productCode,
      barcode: rice.productCode,
      name: rice.productCode!,
    );
    expect(found!.id, a);
    // Running again changes nothing.
    expect(await db.assignShortCodes([a, b]), 0);
  });

  test('copies and layouts decide the page count', () async {
    final p = Product(
      name: 'चाय पत्ती',
      mrp: 110,
      printedMrp: 120,
      quantity: 3,
    );
    final requests = [
      LabelRequest(p, 5),
      LabelRequest(p.copyWith(name: 'Tea'), 0),
    ];
    expect(PdfGenerator.pageCount(5), 1);
    expect(PdfGenerator.pageCount(5, layout: LabelLayout.roll50x25), 5);
    expect(PdfGenerator.pageCount(25, columns: 3, rows: 8), 2);
    for (final layout in LabelLayout.values) {
      for (final type in [
        PdfGenerator.codeTypeQr,
        PdfGenerator.codeTypeBarcode,
      ]) {
        final bytes = await PdfGenerator.generate(
          requests,
          layout: layout,
          codeType: type,
        );
        expect(bytes.length, greaterThan(500));
      }
    }
  });
}
