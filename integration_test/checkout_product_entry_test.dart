import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/theme/app_theme.dart';
import 'package:storely/utils/test_keys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('product editor returns exact saved product to offline checkout', (
    tester,
  ) async {
    final db = DatabaseHelper.instance;
    await db.close();
    final originalName = DatabaseHelper.databaseFileName;
    DatabaseHelper.databaseFileName = 'checkout-product-entry-validation.db';
    final path = await DatabaseHelper.databasePath();
    await deleteDatabase(path);
    try {
      final id = await db.insertProduct(
        Product(
          name: 'Checkout Rice',
          sellingPrice: 118,
          purchasePrice: 100,
          directPriceToggle: true,
          manualPrice: 118,
          quantity: 10,
        ),
      );
      final original = (await db.getProductById(id))!;
      final originalItem = await db.buildBillItemForProduct(original);
      originalItem.quantity = 2;
      await db.saveCartDraft([originalItem]);
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ScanScreen(initialMode: BillingEntryMode.manual),
        ),
      );
      await tester.pumpAndSettle();

      Finder key(String id) => find.byKey(ValueKey(id));
      Future<void> waitFor(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsOneWidget);
      }

      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await waitFor(finder);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      String input(Finder finder) => tester
          .widget<EditableText>(
            find.descendant(of: finder, matching: find.byType(EditableText)),
          )
          .controller
          .text;
      Future<void> enter(Finder finder, String text) async {
        await waitFor(finder);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await tester.enterText(finder, text);
        await tester.pumpAndSettle();
        expect(input(finder), text);
      }

      final openCheckout = find.bySemanticsIdentifier(TestKeys.scanBillBtn);
      await tap(openCheckout);
      await enter(key('checkout-customer'), 'Product entry customer');
      await enter(key('checkout-discount'), '10');
      await tap(find.text('Partial'));
      await enter(key('checkout-partial-amount'), '50.001');
      await tap(key('checkout-close'));
      expect(find.text('Create Bill'), findsNothing);

      const missing = 'CHECKOUT-MISSING-102';
      const corrected = 'CHECKOUT-CORRECTED-103';
      final search = key('checkout-product-search');
      final create = key('checkout-create-product');
      Future<void> openProduct() async {
        await enter(search, missing);
        await tester.testTextInput.receiveAction(TextInputAction.search);
        await tester.pumpAndSettle();
        await tap(create);
        await waitFor(key('quick-add-barcode'));
        expect(input(key('quick-add-barcode')), missing);
      }

      await openProduct();
      await tap(key('quick-add-cancel'));
      expect(key('quick-add-name'), findsNothing);
      var scope = await db.captureCheckoutScope();
      var draft = (await db.loadCheckoutCart(scope))!;
      expect(draft.cart.items.single.productUuid, original.uuid);
      expect(draft.cart.items.single.quantity, 2);
      expect(draft.state['raw']['partial'], '50.001');

      await openProduct();
      await enter(key('quick-add-name'), 'Checkout catalog addition');
      await enter(key('quick-add-price'), '20');
      await enter(key('quick-add-qty'), '3');
      await enter(key('quick-add-barcode'), corrected);
      await tap(key('quick-add-save'));
      await waitFor(openCheckout);
      expect(key('quick-add-name'), findsNothing);
      scope = await db.captureCheckoutScope();
      final saved = (await db.getAllProducts()).singleWhere(
        (p) => p.barcode == corrected,
      );
      draft = (await db.loadCheckoutCart(scope))!;
      expect(draft.cart.items.map((item) => item.productUuid), [original.uuid, saved.uuid]);
      expect(draft.cart.items.map((item) => item.quantity), [2, 1]);
      expect(draft.state['raw']['name'], 'Product entry customer');
      expect(draft.state['raw']['discount'], '10');
      expect(draft.state['raw']['partial'], '50.001');
      expect(saved.quantity, 3);
      expect(await db.getAllBills(), isEmpty);
      await tap(openCheckout);
      expect(input(key('checkout-customer')), 'Product entry customer');
      expect(input(key('checkout-discount')), '10');
      expect(key('checkout-partial-amount'), findsNothing);
      final settlement = tester.widget<SegmentedButton<String>>(
        find.byWidgetPredicate(
          (widget) =>
              widget is SegmentedButton<String> &&
              widget.segments.any((segment) => segment.value == 'partial'),
        ),
      );
      expect(settlement.selected, isEmpty);
      await tap(find.text('Partial'));
      expect(input(key('checkout-partial-amount')), '50.001');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
      await deleteDatabase(path);
      DatabaseHelper.databaseFileName = originalName;
    }
  });
}
