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
  testWidgets('reopens, swaps, and posts a complete offline checkout', (
    tester,
  ) async {
    final db = DatabaseHelper.instance;
    await db.close();
    final originalName = DatabaseHelper.databaseFileName;
    DatabaseHelper.databaseFileName = 'checkout-draft-device-validation.db';
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
      final secondId = await db.insertProduct(
        Product(
          name: 'Second Checkout Product',
          sellingPrice: 80,
          purchasePrice: 60,
          directPriceToggle: true,
          manualPrice: 80,
          quantity: 10,
        ),
      );
      final item = await db.buildBillItemForProduct(
        (await db.getProductById(id))!,
      );
      await db.saveCartDraft([item]);

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

      Future<void> enter(Finder finder, String value) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await tester.enterText(finder, value);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(finder).controller!.text, value);
      }

      Future<void> mount() async {
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
      }

      Future<void> openCheckout() async {
        await tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        await waitFor(find.text('Create Bill'));
      }

      final name = find.byKey(const ValueKey('checkout-customer'));
      final amount = find.byKey(const ValueKey('checkout-partial-amount'));
      final consent = find.byKey(const ValueKey('checkout-unassigned-consent'));
      final save = find.byKey(const ValueKey('checkout-save'));
      final close = find.byKey(const ValueKey('checkout-close'));
      void assertDraft() {
        expect(tester.widget<TextField>(name).controller!.text, 'Draft One');
        expect(tester.widget<TextField>(amount).controller!.text, '50.001');
      }

      await mount();
      await openCheckout();
      await enter(name, 'Draft One');
      await tap(find.text('Partial'));
      await enter(amount, '50.001');
      await tap(close);
      await openCheckout();
      assertDraft();
      await tap(close);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
      await mount();
      await openCheckout();
      assertDraft();
      await tap(close);
      await tap(find.byKey(const ValueKey('checkout-hold')));
      await tap(find.text('Second Checkout Product'));
      await openCheckout();
      await enter(name, 'Draft Two');
      await tap(close);
      await tap(find.byKey(const ValueKey('checkout-held-list')));
      final heldCart = find.byWidgetPredicate(
        (widget) =>
            widget is ListTile &&
            widget.title is Text &&
            (widget.title as Text).data!.contains('Checkout Rice'),
      );
      await tap(heldCart);
      await openCheckout();
      assertDraft();
      expect(await db.getAllBills(), isEmpty);
      expect((await db.getProductById(id))!.quantity, 10);
      await enter(amount, '50');
      await tap(consent);
      await tap(save);
      await waitFor(find.text('Bill Created!'));
      final bill = (await db.getAllBills()).single;
      expect(bill.customerName, 'Draft One');
      expect(bill.totalAmount, 118);
      expect(bill.paidAmount, 50);
      expect(bill.balanceDue, 68);
      expect((await db.getProductById(id))!.quantity, 9);
      expect(await db.loadCartDraft(), isEmpty);
      expect((await db.getProductById(secondId))!.quantity, 10);
      final heldAfterSave = (await db.getHeldBills()).single;
      expect(heldAfterSave.items.single.productName, 'Second Checkout Product');
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
