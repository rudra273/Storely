import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/purchase_composer_draft.dart';
import 'package:storely/screens/products_screen.dart';
import 'package:storely/services/cloud_service.dart';

void main() {
  final db = DatabaseHelper.instance;
  late CloudState originalCloud;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    originalCloud = CloudService.instance.state.value;
    await db.close();
    DatabaseHelper.databaseFileName = 'purchase-composer-ui.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
  });
  tearDown(() async {
    db.isAdminMutationAllowed = null;
    CloudService.instance.state.value = originalCloud;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  Future<void> finishSave(WidgetTester tester) async {
    for (var i = 0; i < 15; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      if (find.text('Saving draft…').evaluate().isEmpty) return;
    }
    fail('Draft save did not finish');
  }

  Widget screen(
    PurchaseComposerDraft draft, {
    List<Product> catalog = const [],
    List<Product>? imported,
    PurchaseDraftLine? newLine,
    Future<int> Function(PurchaseComposerDraft)? commit,
  }) => MaterialApp(
    home: NewPurchaseScreen(
      initialDraft: draft,
      catalog: catalog,
      suppliers: const ['Supplier A'],
      addSupplier: () async => 'Inline supplier',
      scanBarcode: (_) async => '222',
      addProduct: (_, _, _) async => newLine,
      editProduct: (line, _, _, _) async => line,
      pickAndParseImport: (_) async => imported,
      commitBatch: commit ?? (_) async => 1,
    ),
  );

  testWidgets(
    'scan chooses stable product and quick restock survives screen restart',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      late PurchaseComposerDraft draft;
      late List<Product> catalog;
      await tester.runAsync(() async {
        await db.insertProduct(
          Product(
            name: 'Tea A',
            barcode: '111',
            quantity: 3,
            sellingPrice: 15,
            purchasePrice: 2,
          ),
        );
        await db.insertProduct(
          Product(
            name: 'Tea B',
            directPriceToggle: true,
            manualPrice: 25,
            barcode: '222',
            quantity: 5,
            sellingPrice: 25,
            purchasePrice: 3,
          ),
        );
        catalog = await db.getAllProducts();
        draft = await db.openPurchaseDraft();
      });
      await tester.pumpWidget(screen(draft, catalog: catalog));
      await tester.tap(find.text('Search or scan existing product'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Scan barcode'));
      await tester.pumpAndSettle();
      expect(find.text('Tea A'), findsNothing);
      await tester.tap(find.text('Tea B'));
      await tester.pumpAndSettle();
      expect(
        find.text('Selling price and product settings stay unchanged.'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).at(0), '1.25');
      await tester.enterText(find.byType(TextFormField).at(1), '0.00501');
      await tester.ensureVisible(find.text('Add to purchase'));
      await tester.tap(find.text('Add to purchase'));
      await tester.pump();
      expect(
        find.text('Enter a number with up to 4 decimal places'),
        findsOneWidget,
      );
      await tester.enterText(find.byType(TextFormField).at(1), '0.005');
      await tester.tap(find.text('Add to purchase'));
      await tester.pumpAndSettle();
      await finishSave(tester);
      expect(find.textContaining('Stock cost subtotal: ₹0.01'), findsOneWidget);
      late PurchaseComposerDraft recovered;
      await tester.runAsync(() async {
        recovered = await db.openPurchaseDraft();
      });
      expect(recovered.lines.single.restockTarget!.uuid, catalog.last.uuid);
      expect(recovered.lines.single.product.purchasePrice, .005);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(screen(recovered, catalog: catalog));
      expect(find.text('Tea B'), findsOneWidget);
      expect(find.textContaining('Draft saved on this device'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('optional supplier edits and inline creation are persisted', (
    tester,
  ) async {
    late PurchaseComposerDraft draft;
    await tester.runAsync(() async {
      draft = await db.openPurchaseDraft();
    });
    await tester.pumpWidget(screen(draft));
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Supplier A').last);
    await tester.pumpAndSettle();
    await finishSave(tester);
    await tester.runAsync(() async {
      expect((await db.openPurchaseDraft()).supplier, 'Supplier A');
    });
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No supplier').last);
    await tester.pumpAndSettle();
    await finishSave(tester);
    await tester.runAsync(() async {
      expect((await db.openPurchaseDraft()).supplier, isNull);
    });
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Supplier (optional)').last);
    await tester.pumpAndSettle();
    await finishSave(tester);
    await tester.runAsync(() async {
      expect((await db.openPurchaseDraft()).supplier, 'Inline supplier');
    });
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'import keeps distinct cost lines and preserves product selling price',
    (tester) async {
      late PurchaseComposerDraft draft;
      late Product product;
      await tester.runAsync(() async {
        await db.insertProduct(
          Product(
            name: 'Tea',
            quantity: 3,
            purchasePrice: 2,
            sellingPrice: 99,
            directPriceToggle: true,
            manualPrice: 99,
          ),
        );
        product = (await db.getAllProducts()).single;
        draft = await db.openPurchaseDraft();
      });
      await tester.pumpWidget(
        screen(
          draft,
          catalog: [product],
          imported: [
            Product(
              name: 'Tea',
              quantity: 2,
              purchasePrice: 4,
              sellingPrice: 1,
              source: ProductSource.imported,
            ),
            Product(
              name: 'Tea',
              quantity: 3,
              purchasePrice: 6,
              sellingPrice: 2,
              source: ProductSource.imported,
            ),
          ],
        ),
      );
      await tester.tap(find.text('Import file'));
      await tester.pumpAndSettle();
      await finishSave(tester);
      await tester.runAsync(() async {
        final saved = await db.openPurchaseDraft();
        expect(saved.lines.length, 2);
        expect(saved.lines.map((l) => l.product.purchasePrice), [4, 6]);
        expect(saved.lines.map((l) => l.product.sellingPrice), [99, 99]);
        expect(saved.importedRows.length, 2);
      });
    },
  );

  testWidgets('incompatible import units reject the entire staged file', (
    tester,
  ) async {
    late PurchaseComposerDraft draft;
    await tester.runAsync(() async {
      draft = await db.openPurchaseDraft();
    });
    await tester.pumpWidget(
      screen(
        draft,
        catalog: [Product(name: 'Rice', uuid: 'rice', quantity: 5, unit: 'kg')],
        imported: [
          Product(name: 'Valid new item', quantity: 1, purchasePrice: 2),
          Product(name: 'Rice', quantity: 1, purchasePrice: 20, unit: 'box'),
        ],
      ),
    );
    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Convert "Rice" to kg'), findsOneWidget);
    await tester.runAsync(() async {
      expect((await db.openPurchaseDraft()).lines, isEmpty);
    });
  });

  testWidgets('conflicting import identifiers require file correction', (
    tester,
  ) async {
    late PurchaseComposerDraft draft;
    await tester.runAsync(() async {
      draft = await db.openPurchaseDraft();
    });
    await tester.pumpWidget(
      screen(
        draft,
        catalog: [
          Product(
            name: 'Rice',
            uuid: 'rice',
            productCode: 'RICE',
            barcode: '111',
            quantity: 5,
          ),
        ],
        imported: [
          Product(
            name: 'Rice',
            productCode: 'RICE',
            barcode: '222',
            quantity: 1,
            purchasePrice: 2,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Import file'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Code/barcode differs'), findsOneWidget);
    await tester.runAsync(() async {
      expect((await db.openPurchaseDraft()).lines, isEmpty);
    });
  });

  testWidgets(
    'failed save keeps recent edits visible and blocks purchase confirmation',
    (tester) async {
      late PurchaseComposerDraft draft;
      await tester.runAsync(() async {
        draft = await db.openPurchaseDraft();
        await db.savePurchaseDraft(draft.copyWith(supplier: 'Newer editor'));
      });
      var confirmations = 0;
      await tester.pumpWidget(
        screen(
          draft,
          newLine: PurchaseDraftLine(
            product: Product(
              name: 'Unsaved tea',
              quantity: 1,
              purchasePrice: 2,
            ),
            quantityAdded: 1,
          ),
          commit: (_) async {
            confirmations++;
            return 1;
          },
        ),
      );
      await tester.tap(find.text('Add new product'));
      await tester.pumpAndSettle();
      await finishSave(tester);
      expect(find.text('Unsaved tea'), findsOneWidget);
      expect(find.textContaining('Draft not saved:'), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save purchase (1)'),
      );
      expect(save.onPressed, isNull);
      expect(confirmations, 0);
      await tester.runAsync(() async {
        expect((await db.openPurchaseDraft()).supplier, 'Newer editor');
      });
    },
  );

  testWidgets(
    'save failure allows deliberate exit and keeps the prior revision',
    (tester) async {
      late PurchaseComposerDraft draft;
      await tester.runAsync(() async {
        draft = await db.openPurchaseDraft();
        await db.savePurchaseDraft(draft.copyWith(supplier: 'Newer editor'));
      });
      final nav = GlobalKey<NavigatorState>();
      final composer =
          (screen(
                    draft,
                    newLine: PurchaseDraftLine(
                      product: Product(
                        name: 'Unsaved',
                        quantity: 1,
                        purchasePrice: 2,
                      ),
                      quantityAdded: 1,
                    ),
                  )
                  as MaterialApp)
              .home!;
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: const Scaffold(body: Text('Home')),
        ),
      );
      nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => composer));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add new product'));
      await tester.pumpAndSettle();
      await finishSave(tester);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving recent edits?'), findsOneWidget);
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      await tester.runAsync(() async {
        expect((await db.openPurchaseDraft()).supplier, 'Newer editor');
      });
    },
  );

  testWidgets(
    'revoked role immediately hides composer costs and keeps saved data',
    (tester) async {
      late PurchaseComposerDraft draft;
      await tester.runAsync(() async {
        draft = await db.savePurchaseDraft(
          (await db.openPurchaseDraft()).copyWith(
            lines: [
              PurchaseDraftLine(
                product: Product(
                  name: 'Private',
                  quantity: 1,
                  purchasePrice: 8,
                ),
                quantityAdded: 1,
              ),
            ],
          ),
        );
      });
      await tester.pumpWidget(screen(draft));
      expect(find.text('Private'), findsOneWidget);
      db.isAdminMutationAllowed = () => false;
      CloudService.instance.state.value = originalCloud.copyWith(
        message: 'Role changed',
      );
      await tester.pump();
      expect(find.text('Private'), findsNothing);
      expect(find.textContaining('Stock cost subtotal:'), findsNothing);
      expect(find.textContaining('Your draft is preserved.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
