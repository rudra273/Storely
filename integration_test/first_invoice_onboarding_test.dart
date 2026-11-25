import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/main.dart' show AppGate;
import 'package:storely/l10n/l10n.dart';
import 'package:storely/services/app_settings_service.dart';
import 'package:storely/services/home_section_prefs.dart';
import 'package:storely/services/kpi_prefs.dart';
import 'package:storely/theme/app_theme.dart';
import 'package:storely/utils/test_keys.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'fresh offline shop reaches its first invoice through existing Home actions and recovers a failed save',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      final originalName = DatabaseHelper.databaseFileName;
      final previousAdmin = db.isAdminMutationAllowed;
      final previousGuard = db.assertAdminMutation;
      DatabaseHelper.databaseFileName =
          'first-invoice-onboarding-device-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      db.isAdminMutationAllowed = () => true;
      db.assertAdminMutation = null;
      SharedPreferences.setMockInitialValues({});
      await AppSettingsService.instance.load();
      await HomeSectionPrefs.instance.load();
      await KpiPrefs.instance.load();
      Finder key(String value) => find.byKey(ValueKey(value));
      Future<void> wait(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
      }

      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await wait(finder);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> enter(Finder finder, String value) async {
        await wait(finder);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
        await tester.enterText(finder, value);
        await tester.pumpAndSettle();
      }

      try {
        expect(await db.hasCompletedShopSetup(), isFalse);
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const AppGate(),
          ),
        );
        await tap(find.text('Start Fresh'));
        final shopField = find.descendant(
          of: find.bySemanticsIdentifier(TestKeys.welcomeShopNameField),
          matching: find.byType(TextFormField),
        );
        await enter(shopField, 'My Shop');
        await tap(find.bySemanticsIdentifier(TestKeys.welcomeContinueBtn));
        await wait(key('onboarding-add-product'));
        expect(await db.hasCompletedShopSetup(), isTrue);
        expect((await db.getAllProducts()), isEmpty);
        await tap(key('onboarding-add-product'));
        await enter(key('quick-add-name'), 'Onboarding Tea');
        await enter(key('quick-add-price'), '118');
        await enter(key('quick-add-qty'), '10');
        await tap(key('quick-add-save'));
        await wait(key('onboarding-first-invoice'));
        final product = (await db.getAllProducts()).single;
        expect(product.quantity, 10);
        await tap(key('onboarding-first-invoice'));
        await wait(key('checkout-product-search'));
        await tap(find.text('Onboarding Tea').first);
        await tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        await enter(key('checkout-customer'), 'First Customer');
        await tap(find.text('Partial'));
        await enter(key('checkout-partial-amount'), '50');
        await tap(key('checkout-unassigned-consent'));
        await tap(key('checkout-close'));
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tap(key('checkout-keep-exit'));
        await wait(key('onboarding-first-invoice'));
        expect((await db.getFirstInvoiceProgress()).hasInvoice, isFalse);
        await tap(key('onboarding-first-invoice'));
        await tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
        expect(
          tester.widget<TextField>(key('checkout-customer')).controller!.text,
          'First Customer',
        );
        expect(
          tester
              .widget<TextField>(key('checkout-partial-amount'))
              .controller!
              .text,
          '50',
        );
        final sql = await db.database;
        await sql.execute(
          "CREATE TRIGGER first_invoice_reject BEFORE INSERT ON checkout_acceptances BEGIN SELECT RAISE(ABORT, 'isolated first invoice failure'); END",
        );
        await tap(key('checkout-save'));
        expect((await db.getFirstInvoiceProgress()).hasInvoice, isFalse);
        expect((await db.getAllBills()), isEmpty);
        expect(
          tester.widget<TextField>(key('checkout-customer')).controller!.text,
          'First Customer',
        );
        final pending =
            (await db.loadCheckoutCart(
                  await db.captureCheckoutScope(),
                ))!.state['pending']
                as Map;
        final attempt = pending['attempt_id'];
        await sql.execute('DROP TRIGGER first_invoice_reject');
        await tap(key('checkout-save'));
        await wait(find.text('Bill Created!'));
        expect(
          (await sql.query('checkout_acceptances')).single['attempt_id'],
          attempt,
        );
        final bill = (await db.getAllBills()).single;
        expect(bill.totalAmount, 118);
        expect(bill.paidAmount, 50);
        expect(bill.balanceDue, 68);
        expect((await db.getProductById(product.id!))!.quantity, 9);
        expect(await db.loadCartDraft(), isEmpty);
        await tap(key('checkout-completion-done'));
        await tester.pumpAndSettle();
        expect(key('onboarding-guidance'), findsNothing);
        expect((await db.getFirstInvoiceProgress()).hasInvoice, isTrue);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await db.close();
        expect(await db.hasCompletedShopSetup(), isTrue);
        expect((await db.getFirstInvoiceProgress()).hasInvoice, isTrue);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = originalName;
        db.isAdminMutationAllowed = previousAdmin;
        db.assertAdminMutation = previousGuard;
      }
    },
  );
}
