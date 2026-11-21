import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/theme/app_theme.dart';
import 'package:storely/utils/test_keys.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('offline checkout requires deliberate reconciled settlement', (
    tester,
  ) async {
    final db = DatabaseHelper.instance;
    await db.close();
    DatabaseHelper.databaseFileName =
        'checkout-settlement-device-validation.db';
    final path = p.join(
      await getDatabasesPath(),
      DatabaseHelper.databaseFileName,
    );
    await deleteDatabase(path);
    db.isAdminMutationAllowed = () => true;
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
      var round = 0;
      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> openCheckout() async {
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpAndSettle();
        final product = (await db.getProductById(id))!;
        await db.saveCartDraft([await db.buildBillItemForProduct(product)]);
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(round++),
            theme: StorelyTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ScanScreen(initialMode: BillingEntryMode.manual),
          ),
        );
        await tester.pumpAndSettle();
        final checkout = find.bySemanticsIdentifier(TestKeys.scanBillBtn);
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (checkout.evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(checkout, findsOneWidget);
        await tap(checkout);
        final choice = tester.widget<SegmentedButton<String>>(
          find.byWidgetPredicate(
            (widget) =>
                widget is SegmentedButton<String> &&
                widget.segments.any((segment) => segment.value == 'partial'),
          ),
        );
        expect(choice.selected, isEmpty, reason: 'No inherited settlement');
      }

      final save = find.byKey(const ValueKey('checkout-save'));
      final consent = find.byKey(const ValueKey('checkout-unassigned-consent'));
      await openCheckout();
      await binding.convertFlutterSurfaceToImage();
      await tap(save);
      expect(await db.getAllBills(), isEmpty);
      expect(
        find.textContaining('Choose full, partial or unpaid'),
        findsOneWidget,
      );
      await tap(find.text('Partial'));
      final amount = find.byKey(const ValueKey('checkout-partial-amount'));
      for (final invalid in ['0', '-1', '118', '119', '50.001']) {
        await tester.ensureVisible(amount);
        await tester.tap(amount);
        await tester.pumpAndSettle();
        await tester.enterText(amount, invalid);
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(amount).controller!.text, invalid);
        final checkbox = tester.widget<CheckboxListTile>(consent);
        if (checkbox.value != true) await tap(consent);
        await tap(save);
        expect(await db.getAllBills(), isEmpty, reason: invalid);
        expect(amount, findsOneWidget);
      }
      await tester.ensureVisible(amount);
      await tester.tap(amount);
      await tester.pumpAndSettle();
      await tester.enterText(amount, '50');
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(amount).controller!.text, '50');
      expect(tester.widget<CheckboxListTile>(consent).value, isFalse);
      await tap(consent);
      final external = (await getExternalStorageDirectory())!;
      await File(
        p.join(external.path, 'checkout-partial.png'),
      ).writeAsBytes(await binding.takeScreenshot('checkout-partial'));
      await tap(save);
      var bills = await db.getAllBills();
      expect(bills, hasLength(1));
      expect(bills.single.totalAmount, 118);
      expect(bills.single.paidAmount, 50);
      expect(bills.single.balanceDue, 68);

      await openCheckout();
      await tap(find.text('Paid full'));
      await tap(save);
      bills = await db.getAllBills();
      expect(bills, hasLength(2));
      expect(bills.where((bill) => bill.paidAmount == 118), hasLength(1));

      await openCheckout();
      await tap(find.text('Unpaid'));
      await tap(save);
      expect(await db.getAllBills(), hasLength(2));
      await tap(consent);
      await File(
        p.join(external.path, 'checkout-unpaid.png'),
      ).writeAsBytes(await binding.takeScreenshot('checkout-unpaid'));
      await tap(save);
      bills = await db.getAllBills();
      expect(bills, hasLength(3));
      final unpaid = bills.singleWhere((bill) => bill.paidAmount == 0);
      expect(unpaid.balanceDue, 118);
      expect((await db.getProductById(id))!.quantity, 7);
      expect(await db.loadCartDraft(), isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();
    } finally {
      await db.close();
      await deleteDatabase(path);
      DatabaseHelper.databaseFileName = 'storely.db';
      db.isAdminMutationAllowed = null;
    }
  });
}
