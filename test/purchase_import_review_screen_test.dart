import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/purchase_import_review.dart';
import 'package:storely/screens/products_screen.dart';
import 'package:storely/utils/csv_importer.dart';

void main() {
  Future<Future<ReviewedPurchaseImport?>> open(
    WidgetTester tester,
    ImportParseResult parsed, {
    List<Product> catalog = const [],
    bool duplicate = false,
  }) async {
    final nav = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(420, 1300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    final result = nav.currentState!.push<ReviewedPurchaseImport>(
      MaterialPageRoute(
        builder: (_) => PurchaseImportReviewScreen(
          parsed: parsed,
          catalog: catalog,
          fingerprint: 'a' * 64,
          possibleDuplicate: duplicate,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('name-only match and invalid row require explicit decisions', (
    tester,
  ) async {
    final tea = Product(
      name: 'Tea',
      quantity: 2,
      purchasePrice: 3,
      unit: 'pcs',
      source: ProductSource.imported,
    );
    final catalog = Product(
      id: 1,
      uuid: 'tea',
      name: 'Tea',
      quantity: 10,
      purchasePrice: 1,
      unit: 'pcs',
    );
    final result = await open(
      tester,
      ImportParseResult(
        [tea],
        [const ImportRowError(4, 'Missing quantity')],
        rows: [ImportProductRow(2, tea)],
        warnings: const ['Ignored columns: tax'],
      ),
      catalog: [catalog],
    );
    expect(find.text('Ignored columns: tax'), findsOneWidget);
    expect(find.text('Line total: ₹6.00'), findsOneWidget);
    expect(
      find.text('Choose an existing product or create a new product.'),
      findsOneWidget,
    );
    expect(find.textContaining('Missing quantity'), findsOneWidget);
    await tester.tap(find.text('Add reviewed rows'));
    await tester.pumpAndSettle();
    expect(find.text('Review purchase file'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('choice-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Existing: Tea').last);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Row 4: Invalid row'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add reviewed rows'));
    await tester.pumpAndSettle();
    final reviewed = await result;
    expect(reviewed!.rows.single.existing!.uuid, 'tea');
    expect(reviewed.rows.single.number, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'same new code shares identity while different lot costs remain distinct',
    (tester) async {
      final first = Product(
        name: 'Tea',
        productCode: 'T1',
        quantity: 2,
        purchasePrice: 4,
        purchaseBatchNo: 'L1',
        source: ProductSource.imported,
      );
      final second = first.copyWith(
        quantity: 3,
        purchasePrice: 6,
        purchaseBatchNo: 'L2',
      );
      final result = await open(
        tester,
        ImportParseResult(
          [first, second],
          const [],
          rows: [ImportProductRow(2, first), ImportProductRow(5, second)],
        ),
      );
      expect(find.text('Batch: L1'), findsOneWidget);
      expect(find.text('Batch: L2'), findsOneWidget);
      await tester.tap(find.text('Add reviewed rows'));
      await tester.pumpAndSettle();
      final reviewed = await result;
      expect(reviewed!.rows.map((r) => r.number), [2, 5]);
      expect(reviewed.rows.map((r) => r.product.purchasePrice), [4, 6]);
      expect(
        reviewed.rows.first.newProductKey,
        reviewed.rows.last.newProductKey,
      );
    },
  );

  testWidgets(
    'review edits fractional quantity and cost with exact line rounding',
    (tester) async {
      final p = Product(
        name: 'Tea',
        quantity: 1,
        purchasePrice: 1,
        source: ProductSource.imported,
      );
      final result = await open(
        tester,
        ImportParseResult([p], const [], rows: [ImportProductRow(2, p)]),
      );
      await tester.enterText(find.byType(TextField).first, '0');
      await tester.pump();
      await tester.tap(find.text('Add reviewed rows'));
      await tester.pumpAndSettle();
      expect(find.textContaining('positive quantity'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '1.25');
      await tester.enterText(find.byType(TextField).last, '0.005');
      await tester.pump();
      expect(find.text('Line total: ₹0.01'), findsOneWidget);
      await tester.tap(find.text('Add reviewed rows'));
      await tester.pumpAndSettle();
      final reviewed = await result;
      expect(reviewed!.rows.single.product.quantity, 1.25);
      expect(reviewed.rows.single.product.purchasePrice, .005);
    },
  );

  testWidgets(
    'source rows beyond the supported range are blocked during review',
    (tester) async {
      final p = Product(
        name: 'Tea',
        quantity: 1,
        purchasePrice: 1,
        source: ProductSource.imported,
      );
      await open(
        tester,
        ImportParseResult([p], const [], rows: [ImportProductRow(2021, p)]),
      );
      expect(find.textContaining('Row number exceeds 2020'), findsOneWidget);
      await tester.tap(find.text('Add reviewed rows'));
      await tester.pumpAndSettle();
      expect(find.text('Review purchase file'), findsOneWidget);
    },
  );

  testWidgets('repeated file requires affirmative approval', (tester) async {
    final p = Product(
      name: 'Tea',
      quantity: 1,
      purchasePrice: 2,
      source: ProductSource.imported,
    );
    final result = await open(
      tester,
      ImportParseResult([p], const [], rows: [ImportProductRow(2, p)]),
      duplicate: true,
    );
    await tester.tap(find.text('Add reviewed rows'));
    await tester.pumpAndSettle();
    expect(
      find.text('Confirm that this is an intentional repeat.'),
      findsOneWidget,
    );
    await tester.tap(find.text('This file may already be recorded'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add reviewed rows'));
    await tester.pumpAndSettle();
    expect((await result)!.duplicateApproved, true);
  });
  testWidgets(
    'narrow review displays long product and unit names without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final p = Product(
        name: 'Long grain premium basmati rice with a lengthy product name',
        quantity: 2,
        purchasePrice: 4,
        unit: 'kilogram retail pack',
        source: ProductSource.imported,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PurchaseImportReviewScreen(
            parsed: ImportParseResult(
              [p],
              const [],
              rows: [ImportProductRow(2, p)],
            ),
            catalog: const [],
            fingerprint: 'b' * 64,
            possibleDuplicate: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Review purchase file'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
