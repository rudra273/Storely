import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/theme/app_theme.dart';
import 'package:storely/utils/test_keys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'E03.3A emulator: line discount + fixed doc discount + exclusive tax + up ₹5 round-off',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      final originalName = DatabaseHelper.databaseFileName;
      DatabaseHelper.databaseFileName =
          'billing-controls-device-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      db.isAdminMutationAllowed = () => true;

      try {
        await db.saveShopProfile(
          ShopProfile(
            name: 'E03.3A Control Shop',
            gstScheme: GstScheme.regular,
            gstin: '27AAPFU0939F1ZV',
          ),
        );
        final productId = await db.insertProduct(
          Product(
            name: 'Control Tea',
            sellingPrice: 100,
            purchasePrice: 70,
            gstPercent: 18,
            directPriceToggle: true,
            manualPrice: 100,
            quantity: 10,
          ),
        );
        final item = (await db.buildBillItemForProduct(
          (await db.getProductById(productId))!,
        ))..quantity = 2;
        await db.saveCartDraft([item]);

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
          while (finder.evaluate().isEmpty &&
              DateTime.now().isBefore(deadline)) {
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

        // 1. Open per-line controls sheet and set 10% line discount
        await tap(key('cart-item-edit-0'));
        await waitFor(key('line-discount-value'));
        await tester.enterText(key('line-discount-value'), '10');
        await tester.pumpAndSettle();
        await tap(key('line-controls-apply'));

        // 2. Open checkout sheet
        await tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        await waitFor(key('checkout-discount-mode'));

        // 3. Switch doc discount to fixed ₹10
        await tap(find.descendant(of: key('checkout-discount-mode'), matching: find.text('₹')));
        await tester.enterText(key('checkout-discount'), '10');
        await tester.pumpAndSettle();

        // 4. Switch doc tax mode to Exclusive
        await tap(find.text('Tax exclusive'));

        // 5. Set round-off mode to Up and increment to ₹5
        await tap(key('checkout-round-off-mode-up'));
        await tap(key('checkout-round-off-increment-5.00'));

        // 6. Verify preview total is ₹205.00
        await waitFor(key('checkout-grand-total'));
        final totalWidget = tester.widget<Text>(key('checkout-grand-total'));
        expect(totalWidget.data, contains('205'));

        // 7. Select Paid full and save
        await tap(find.text('Paid full'));
        await tap(key('checkout-save'));

        // 8. Verify saved SQLite bill & line match exact oracle
        final bills = await db.getAllBills();
        expect(bills, hasLength(1));
        final saved = bills.single;
        expect(saved.subtotalAmount, 200.00);
        expect(saved.discountMode, 'amount');
        expect(saved.discountValue, 10.00);
        expect(saved.discountAmount, 30.00);
        expect(saved.taxMode, 'exclusive');
        expect(saved.taxableAmount, 170.00);
        expect(saved.cgstAmount, 15.30);
        expect(saved.sgstAmount, 15.30);
        expect(saved.igstAmount, 0.00);
        expect(saved.roundOffMode, 'up');
        expect(saved.roundOffIncrement, 5.00);
        expect(saved.roundOffAmount, 4.40);
        expect(saved.totalAmount, 205.00);

        expect(saved.items, hasLength(1));
        expect(saved.items.single.discountMode, 'percent');
        expect(saved.items.single.discountValue, 10.00);
        expect(saved.items.single.discountAmount, 20.00);
      } finally {
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = originalName;
      }
    },
  );
}
