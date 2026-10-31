import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/purchase_composer_draft.dart';
import 'package:storely/models/purchase_import_review.dart';
import 'package:storely/utils/csv_importer.dart';

Future<ImportParseResult> parse(String content) =>
    CsvImporter.parseBytesDetailed(
      Uint8List.fromList(utf8.encode(content)),
      fileName: 'file.csv',
    );

void main() {
  test(
    'CSV keeps original row numbers, invalid rows and separate lot fields',
    () async {
      final file = await parse(
        '\nproduct_name,quantity,purchase_price,batch_no,expiry_date\n'
        'Tea,2,1.25,A,2027-01-01\n\nBad,not a quantity,4,,\nTea,3,2.5,B,2027-02-02\n',
      );
      expect(file.rows.map((r) => r.number), [3, 6]);
      expect(file.errors.single.row, 5);
      expect(file.rows.map((r) => r.product.purchaseBatchNo), ['A', 'B']);
      expect(file.rows.last.product.purchaseExpiry, DateTime(2027, 2, 2));
      final invalid = await parse(
        'product_name,quantity,purchase_price,expiry_date\nTea,1,2,2026-02-30\n',
      );
      expect(invalid.errors.single.message, contains('valid YYYY-MM-DD'));
    },
  );

  test(
    'XLSX row numbers include blank lines and date cells normalize',
    () async {
      final book = xl.Excel.createExcel();
      final sheet = book.tables[book.getDefaultSheet()]!;
      sheet.appendRow([
        xl.TextCellValue('product_name'),
        xl.TextCellValue('quantity'),
        xl.TextCellValue('purchase_price'),
        xl.TextCellValue('expiry_date'),
      ]);
      sheet.appendRow([
        xl.TextCellValue('A'),
        xl.IntCellValue(1),
        xl.IntCellValue(2),
        xl.DateCellValue(year: 2027, month: 1, day: 2),
      ]);
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 3))
          .value = xl.TextCellValue(
        'B',
      );
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 3))
          .value = xl.IntCellValue(
        2,
      );
      sheet
          .cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 3))
          .value = xl.IntCellValue(
        3,
      );
      final result = await CsvImporter.parseBytesDetailed(
        Uint8List.fromList(book.encode()!),
        fileName: 'stock.xlsx',
      );
      expect(result.rows.map((r) => r.number), [2, 4]);
      expect(result.rows.first.product.purchaseExpiry, DateTime(2027, 1, 2));
    },
  );

  test(
    'local fingerprint ignores filename, aliases, row order and decimal spelling',
    () async {
      final a = await parse(
        'product_name,quantity,purchase_price,batch_no\nTea,2.0,1.50,L1\nRice,3,7,L2\n',
      );
      final b = await parse(
        'name,qty,cost,batch\nRice,3.000,7.0,L2\nTea,2,1.5,L1\n',
      );
      final c = await parse(
        'name,qty,cost,batch\nRice,3,7,L2\nTea,2,1.5,DIFFERENT\n',
      );
      expect(purchaseImportFingerprint(a), purchaseImportFingerprint(b));
      expect(purchaseImportFingerprint(a), isNot(purchaseImportFingerprint(c)));
    },
  );

  group('atomic reviewed import', () {
    final db = DatabaseHelper.instance;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      await db.close();
      DatabaseHelper.databaseFileName = 'purchase-import-review.db';
      await deleteDatabase(await DatabaseHelper.databasePath());
    });
    tearDown(() async {
      await db.close();
      await deleteDatabase(await DatabaseHelper.databasePath());
      DatabaseHelper.databaseFileName = 'storely.db';
    });
    Future<int> confirm(PurchaseComposerDraft d) => db
        .commitProductPurchaseBatch([], purchaseDate: d.date, composerDraft: d);
    final key = 'a' * 64;

    test(
      'multiple lots create one product and keep source row numbers on the sync wire',
      () async {
        final p = Product(
          name: 'Tea',
          productCode: 'T1',
          quantity: 2,
          purchasePrice: 4,
          unit: 'kg',
          purchaseBatchNo: 'LOT-1',
          source: ProductSource.imported,
        );
        final q = p.copyWith(
          quantity: 3,
          purchasePrice: 6,
          purchaseBatchNo: 'LOT-2',
        );
        final initial = await db.openPurchaseDraft();
        final draft = await db.savePurchaseDraft(
          initial.copyWith(
            lines: [
              PurchaseDraftLine(
                product: p,
                quantityAdded: 2,
                importKey: key,
                importRowNumber: 4,
                newProductKey: 'group',
              ),
              PurchaseDraftLine(
                product: q,
                quantityAdded: 3,
                importKey: key,
                importRowNumber: 8,
                newProductKey: 'group',
              ),
            ],
          ),
        );
        await db.close();
        final recovered = await db.openPurchaseDraft();
        expect(recovered.toJson(), draft.toJson());
        await confirm(recovered);
        final products = await db.getAllProducts();
        expect(products.length, 1);
        expect(products.single.quantity, 5);
        final doc = (await db.getPurchaseDocuments()).single;
        expect(doc.items.map((l) => l['product_uuid']).toSet(), {
          products.single.uuid,
        });
        expect(doc.items.map((l) => l['batch_no']), ['LOT-1', 'LOT-2']);
        expect(doc.subtotal, '26.00');
        final movements = (await db.cloudDirtyRows(
          'stock_movements',
        )).where((m) => m['source_document_uuid'] == draft.uuid).toList();
        expect(movements.map((m) => m['import_row_number']), [4, 8]);
        expect(
          movements.every(
            (m) => m['import_batch_key'] == 'mobile-import-v1:$key',
          ),
          true,
        );
        await confirm(recovered);
        expect((await db.getAllProducts()).single.quantity, 5);
      },
    );

    test(
      'linked new rows with conflicting metadata roll back completely',
      () async {
        final a = Product(
          name: 'Tea',
          productCode: 'T1',
          quantity: 2,
          purchasePrice: 4,
          unit: 'kg',
        );
        final b = a.copyWith(quantity: 3, purchasePrice: 5, unit: 'box');
        final draft = await db.savePurchaseDraft(
          (await db.openPurchaseDraft()).copyWith(
            lines: [
              PurchaseDraftLine(
                product: a,
                quantityAdded: 2,
                importKey: key,
                importRowNumber: 2,
                newProductKey: 'group',
              ),
              PurchaseDraftLine(
                product: b,
                quantityAdded: 3,
                importKey: key,
                importRowNumber: 3,
                newProductKey: 'group',
              ),
            ],
          ),
        );
        await expectLater(confirm(draft), throwsStateError);
        expect(await db.getAllProducts(), isEmpty);
        expect(await db.getPurchaseDocuments(), isEmpty);
        expect((await db.openPurchaseDraft()).uuid, draft.uuid);
      },
    );

    test(
      'duplicate is rechecked at confirmation and can be deliberately approved',
      () async {
        final p = Product(
          name: 'Tea',
          productCode: 'T1',
          quantity: 2,
          purchasePrice: 4,
          source: ProductSource.imported,
        );
        final first = await db.savePurchaseDraft(
          (await db.openPurchaseDraft()).copyWith(
            lines: [
              PurchaseDraftLine(
                product: p,
                quantityAdded: 2,
                importKey: key,
                importRowNumber: 2,
                newProductKey: 'first',
              ),
            ],
          ),
        );
        await confirm(first);
        expect(await db.hasPurchaseImportFingerprint(key), true);
        final target = (await db.getAllProducts()).single;
        final next = await db.savePurchaseDraft(
          (await db.openPurchaseDraft()).copyWith(
            lines: [
              PurchaseDraftLine(
                product: target.copyWith(
                  quantity: 2,
                  purchasePrice: 4,
                  source: ProductSource.imported,
                ),
                quantityAdded: 2,
                restockTarget: target,
                importKey: key,
                importRowNumber: 2,
              ),
            ],
          ),
        );
        await expectLater(confirm(next), throwsStateError);
        expect((await db.getAllProducts()).single.quantity, 2);
        final approved = await db.savePurchaseDraft(
          next.copyWith(
            lines: [
              PurchaseDraftLine(
                product: next.lines.single.product,
                quantityAdded: 2,
                restockTarget: target,
                importKey: key,
                importRowNumber: 2,
                duplicateApproved: true,
              ),
            ],
          ),
        );
        await confirm(approved);
        expect((await db.getAllProducts()).single.quantity, 4);
      },
    );
  });
}
