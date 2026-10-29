import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/purchase_composer_draft.dart';

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await db.close();
    DatabaseHelper.databaseFileName = 'purchase-draft-test.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
  });
  tearDown(() async {
    db.assertAdminMutation = null;
    db.isAdminMutationAllowed = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  Future<int> confirm(PurchaseComposerDraft draft) =>
      db.commitProductPurchaseBatch(
        [],
        purchaseDate: draft.date,
        composerDraft: draft,
      );
  PurchaseDraftLine line({
    Product? target,
    double quantity = 2.125,
    double cost = .005,
  }) => PurchaseDraftLine(
    product:
        (target ??
                Product(
                  name: 'Tea',
                  quantity: 0,
                  sellingPrice: 20,
                  unit: 'kg',
                  category: 'Food',
                  supplier: 'Preferred',
                  barcode: '01234',
                ))
            .copyWith(
              quantity: quantity,
              purchasePrice: cost,
              purchaseBatchNo: 'LOT-A',
              purchaseExpiry: DateTime(2027, 1, 1),
            ),
    quantityAdded: quantity,
    restockTarget: target,
  );

  test(
    'one local draft reopens all header, product, lot and import fields without stock',
    () async {
      final empty = await db.openPurchaseDraft();
      expect((await db.openPurchaseDraft()).uuid, empty.uuid);
      final entry = line();
      final saved = await db.savePurchaseDraft(
        empty.copyWith(
          date: DateTime(2026, 1, 1),
          supplier: 'Seller',
          lines: [entry],
          importedRows: [entry.product],
        ),
      );
      await db.close();
      final reopened = await db.openPurchaseDraft();
      expect(reopened.uuid, saved.uuid);
      expect(reopened.revision, 1);
      expect(reopened.toJson(), saved.toJson());
      expect(reopened.lines.single.product.unit, 'kg');
      expect(reopened.lines.single.product.purchaseBatchNo, 'LOT-A');
      expect(await db.getAllProducts(), isEmpty);
      expect(await db.getPurchaseDocuments(), isEmpty);
      expect(await db.hasLocalBusinessDataForCloud(), true);
    },
  );

  test('stale saves and discard cannot overwrite a newer draft', () async {
    final old = await db.openPurchaseDraft();
    final current = await db.savePurchaseDraft(
      old.copyWith(supplier: 'Newest'),
    );
    await expectLater(
      db.savePurchaseDraft(old.copyWith(supplier: 'Stale')),
      throwsStateError,
    );
    await expectLater(db.discardPurchaseDraft(old), throwsStateError);
    expect((await db.openPurchaseDraft()).supplier, 'Newest');
    await db.discardPurchaseDraft(current);
    expect((await db.openPurchaseDraft()).uuid, isNot(old.uuid));
  });

  test(
    'confirmation and draft completion are atomic and replay after reopen is harmless',
    () async {
      final draft = await db.savePurchaseDraft(
        (await db.openPurchaseDraft()).copyWith(lines: [line()]),
      );
      expect(await confirm(draft), 1);
      final receipt = (await db.getPurchaseDocuments()).single;
      expect(receipt.uuid, draft.uuid);
      expect(receipt.subtotal, '0.01');
      await db.close();
      expect(await confirm(draft), 1);
      expect((await db.getAllProducts()).single.quantity, 2.125);
      expect((await db.getPurchaseDocuments()).length, 1);
      expect((await db.openPurchaseDraft()).uuid, isNot(draft.uuid));
      await expectLater(db.savePurchaseDraft(draft), throwsStateError);
    },
  );

  test(
    'restock resolves UUID and preserves current product pricing and metadata',
    () async {
      await db.insertProduct(
        Product(
          name: 'Tea',
          quantity: 5,
          sellingPrice: 20,
          purchasePrice: 4,
          directPriceToggle: true,
          manualPrice: 20,
          unit: 'kg',
          barcode: 'old',
        ),
      );
      final original = (await db.getAllProducts()).single;
      final draft = await db.savePurchaseDraft(
        (await db.openPurchaseDraft()).copyWith(
          lines: [line(target: original.copyWith(id: 9999), cost: 6)],
        ),
      );
      await db.updateProduct(
        original.copyWith(
          sellingPrice: 35,
          manualPrice: 35,
          barcode: 'updated',
          reorderLevel: 7,
        ),
      );
      await confirm(draft);
      final now = (await db.getAllProducts()).single;
      expect(now.quantity, 7.125);
      expect(now.sellingPrice, 35);
      expect(now.manualPrice, 35);
      expect(now.barcode, 'updated');
      expect(now.reorderLevel, 7);
      expect(
        (await db.getPurchaseDocuments()).single.items.single['unit_cost'],
        '6',
      );
    },
  );

  test(
    'deleted restock target rolls back earlier lines and keeps the draft',
    () async {
      await db.insertProduct(
        Product(name: 'Gone', quantity: 1, purchasePrice: 1),
      );
      final target = (await db.getAllProducts()).single;
      final saved = await db.savePurchaseDraft(
        (await db.openPurchaseDraft()).copyWith(
          lines: [
            line(),
            line(target: target),
          ],
        ),
      );
      await db.deleteProduct(target.id!);
      await expectLater(confirm(saved), throwsStateError);
      expect(await db.getAllProducts(), isEmpty);
      expect(await db.getPurchaseDocuments(), isEmpty);
      expect((await db.openPurchaseDraft()).toJson(), saved.toJson());
    },
  );

  test('unit changes and stale confirmation leave stock unchanged', () async {
    await db.insertProduct(
      Product(name: 'Tea', quantity: 1, purchasePrice: 1, unit: 'kg'),
    );
    final product = (await db.getAllProducts()).single;
    final saved = await db.savePurchaseDraft(
      (await db.openPurchaseDraft()).copyWith(lines: [line(target: product)]),
    );
    final latest = await db.savePurchaseDraft(
      saved.copyWith(supplier: 'Updated'),
    );
    await expectLater(confirm(saved), throwsStateError);
    await db.updateProduct(product.copyWith(unit: 'box'));
    await expectLater(confirm(latest), throwsStateError);
    expect((await db.getAllProducts()).single.quantity, 1);
  });

  test(
    'zero-stock setup also cannot be posted twice after a lost acknowledgement',
    () async {
      final draft = await db.savePurchaseDraft(
        (await db.openPurchaseDraft()).copyWith(lines: [line(quantity: 0)]),
      );
      await confirm(draft);
      await confirm(draft);
      expect((await db.getAllProducts()).length, 1);
      expect(await db.getPurchaseDocuments(), isEmpty);
    },
  );

  test(
    'separate rates retain distinct import movements and receipt lines',
    () async {
      await db.insertProduct(
        Product(name: 'Tea', quantity: 5, purchasePrice: 2, unit: 'kg'),
      );
      final target = (await db.getAllProducts()).single;
      final imported = [
        for (final cost in [4.0, 6.0])
          line(
            target: target,
            quantity: 2,
            cost: cost,
          ).product.copyWith(source: ProductSource.imported),
      ];
      final draft = await db.savePurchaseDraft(
        (await db.openPurchaseDraft()).copyWith(
          lines: [
            for (final p in imported)
              PurchaseDraftLine(
                product: p,
                quantityAdded: 2,
                restockTarget: target,
              ),
          ],
          importedRows: imported,
        ),
      );
      await confirm(draft);
      final receipt = (await db.getPurchaseDocuments()).single;
      expect(receipt.items.map((i) => i['unit_cost']), ['4', '6']);
      expect(receipt.subtotal, '20.00');
      expect((await db.getAllProducts()).single.quantity, 9);
      final moves = await (await db.database).query(
        'stock_movements',
        where: 'source_document_uuid = ?',
        whereArgs: [draft.uuid],
      );
      expect(moves.length, 2);
      expect(
        moves.every(
          (m) => m['import_batch_key'] != null && m['source_type'] == 'import',
        ),
        true,
      );
    },
  );

  test('staged tracking edits cannot suppress a restock receipt', () async {
    await db.insertProduct(Product(name: 'Tea', quantity: 5, purchasePrice: 2));
    final target = (await db.getAllProducts()).single;
    final staged = line(target: target);
    final draft = await db.savePurchaseDraft(
      (await db.openPurchaseDraft()).copyWith(
        lines: [
          PurchaseDraftLine(
            product: staged.product.copyWith(trackStock: false),
            quantityAdded: staged.quantityAdded,
            restockTarget: target,
          ),
        ],
      ),
    );
    await confirm(draft);
    expect((await db.getAllProducts()).single.trackStock, true);
    expect((await db.getPurchaseDocuments()).single.uuid, draft.uuid);
  });

  test('changing shops isolates the retained draft', () async {
    final draft = await db.savePurchaseDraft(
      (await db.openPurchaseDraft()).copyWith(lines: [line()]),
    );
    await (await db.database).update(
      'shops',
      {'uuid': 'another-shop'},
      where: 'uuid = ?',
      whereArgs: [draft.shopId],
    );
    expect((await db.openPurchaseDraft()).uuid, isNot(draft.uuid));
    await expectLater(db.savePurchaseDraft(draft), throwsStateError);
    await expectLater(db.discardPurchaseDraft(draft), throwsStateError);
    await expectLater(confirm(draft), throwsStateError);
    expect(await db.getAllProducts(), isEmpty);
  });

  test(
    'staff cannot read, save, discard or confirm the retained draft',
    () async {
      final draft = await db.savePurchaseDraft(
        (await db.openPurchaseDraft()).copyWith(lines: [line()]),
      );
      db.isAdminMutationAllowed = () => false;
      await expectLater(db.openPurchaseDraft(), throwsStateError);
      await expectLater(db.savePurchaseDraft(draft), throwsStateError);
      await expectLater(db.discardPurchaseDraft(draft), throwsStateError);
      await expectLater(confirm(draft), throwsStateError);
      db.isAdminMutationAllowed = null;
      expect((await db.openPurchaseDraft()).toJson(), draft.toJson());
    },
  );

  test(
    'version 23 upgrade adds drafts without inventing purchases or changing stock',
    () async {
      await db.insertProduct(
        Product(name: 'Legacy', quantity: 9, purchasePrice: 2),
      );
      final sql = await db.database;
      await sql.execute('DROP TABLE purchase_drafts');
      await sql.execute('PRAGMA user_version = 23');
      await db.close();
      expect((await db.openPurchaseDraft()).lines, isEmpty);
      expect((await db.getAllProducts()).single.quantity, 9);
      expect(await db.getPurchaseDocuments(), isEmpty);
    },
  );
}
