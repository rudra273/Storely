import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/checkout_settlement.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/theme/app_theme.dart';
import 'package:storely/utils/test_keys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offline checkout payment methods, cash change, completion summary, New Bill and View invoice',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      final originalName = DatabaseHelper.databaseFileName;
      DatabaseHelper.databaseFileName =
          'checkout-payment-completion-device-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      db.isAdminMutationAllowed = () => true;

      try {
        final productId = await db.insertProduct(
          Product(
            name: 'Completion Tea',
            sellingPrice: 118,
            purchasePrice: 80,
            directPriceToggle: true,
            manualPrice: 118,
            quantity: 10,
          ),
        );
        final item = await db.buildBillItemForProduct(
          (await db.getProductById(productId))!,
        );
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

        Future<void> enter(Finder finder, String value) async {
          await waitFor(finder);
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pumpAndSettle();
          await tester.enterText(finder, value);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(finder).controller!.text, value);
        }

        final openCheckout = find.bySemanticsIdentifier(TestKeys.scanBillBtn);

        // 1. Full cash checkout with UPI->Cash reference strip, change due, and draft step recovery.
        await tap(openCheckout);
        await waitFor(find.text('Create Bill'));

        var scope = await db.captureCheckoutScope();
        var draft = (await db.loadCheckoutCart(scope))!;
        expect(draft.state['step'], 'checkout');

        await tap(find.text('Paid full'));
        for (final method in checkoutPaymentMethods) {
          expect(key('checkout-method-$method'), findsOneWidget);
        }

        await tap(key('checkout-method-upi'));
        await enter(key('checkout-reference'), 'TEMP-UPI-REF');
        await tap(key('checkout-method-cash'));
        expect(key('checkout-reference'), findsNothing);
        await enter(key('checkout-cash-received'), '200');
        expect(
          tester.widget<Text>(key('checkout-change-due')).data,
          'Change to return ₹82.00',
        );

        await tap(key('checkout-close'));
        expect(find.text('Create Bill'), findsNothing);
        draft = (await db.loadCheckoutCart(scope))!;
        expect(draft.state['step'], 'items');
        expect(draft.state['raw']['cash'], '200');

        await tap(openCheckout);
        expect(
          tester
              .widget<TextField>(key('checkout-cash-received'))
              .controller!
              .text,
          '200',
        );
        expect(
          tester.widget<Text>(key('checkout-change-due')).data,
          'Change to return ₹82.00',
        );

        await tap(key('checkout-save'));
        await waitFor(find.text('Bill Created!'));
        expect(
          tester.widget<Text>(key('checkout-completion-total')).data,
          '₹118.00',
        );
        expect(
          tester.widget<Text>(key('checkout-completion-received')).data,
          '₹118.00',
        );
        expect(
          tester.widget<Text>(key('checkout-completion-balance')).data,
          '₹0.00',
        );

        var bills = await db.getAllBills();
        expect(bills, hasLength(1));
        expect(bills.single.paymentMethod, 'cash');
        expect(bills.single.transactionReference, isNull);
        expect(bills.single.paidAmount, 118);

        // 2. New Bill -> partial Bank transfer checkout with reference -> View invoice.
        await tap(key('checkout-completion-new'));
        expect(find.text('Bill Created!'), findsNothing);
        expect(await db.loadCartDraft(), isEmpty);

        await tap(find.text('Completion Tea'));
        await tap(openCheckout);
        await waitFor(find.text('Create Bill'));

        await tap(find.text('Partial'));
        await enter(key('checkout-partial-amount'), '50');
        await tap(key('checkout-method-bank'));
        await enter(key('checkout-reference'), 'NEFT-901');
        await tap(key('checkout-close'));
        scope = await db.captureCheckoutScope();
        draft = (await db.loadCheckoutCart(scope))!;
        await db.writeCheckoutState(draft, {
          ...draft.state,
          'raw': {...draft.state['raw'] as Map, 'method': 'bank_transfer'},
        });
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
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
        await tap(openCheckout);
        expect(
          tester.widget<TextField>(key('checkout-reference')).controller!.text,
          'NEFT-901',
        );
        await tap(key('checkout-unassigned-consent'));
        await tap(key('checkout-save'));

        await waitFor(find.text('Bill Created!'));
        expect(find.textContaining('Partial'), findsOneWidget);
        expect(find.textContaining('Bank transfer'), findsOneWidget);
        expect(
          tester.widget<Text>(key('checkout-completion-total')).data,
          '₹118.00',
        );
        expect(
          tester.widget<Text>(key('checkout-completion-received')).data,
          '₹50.00',
        );
        expect(
          tester.widget<Text>(key('checkout-completion-balance')).data,
          '₹68.00',
        );

        bills = await db.getAllBills();
        expect(bills, hasLength(2));
        final partialBill = bills.singleWhere(
          (b) => b.paymentStatus == Bill.statusPartial,
        );
        expect(partialBill.paymentMethod, 'bank');
        expect(partialBill.transactionReference, 'NEFT-901');
        expect(partialBill.paidAmount, 50);
        expect(partialBill.balanceDue, 68);

        await tap(key('checkout-completion-view'));
        await waitFor(find.text('Record payment'));
        expect(find.text('Share bill'), findsOneWidget);
        expect(find.text('₹68.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = originalName;
        db.isAdminMutationAllowed = null;
      }
    },
  );
}
