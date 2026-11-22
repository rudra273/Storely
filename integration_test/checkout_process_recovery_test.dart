// Host orchestrator: integration_test/support/checkout_process_recovery.py.
// Each stage runs in a separate Android process against the same isolated DB.
import 'dart:convert';

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

const stage = String.fromEnvironment('CHECKOUT_PROCESS_STAGE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('checkout survives actual Android process death: $stage', (
    tester,
  ) async {
    expect(['prepare', 'restore', 'verify'], contains(stage));
    final db = DatabaseHelper.instance;
    await db.close();
    DatabaseHelper.databaseFileName = 'checkout-process-recovery.db';
    final path = await DatabaseHelper.databasePath();
    if (stage == 'prepare') {
      await deleteDatabase(
        path,
      ); // Only this dedicated fixture, never storely.db.
      await db.insertProduct(
        Product(
          name: 'Process Recovery Rice',
          sellingPrice: 118,
          purchasePrice: 100,
          manualPrice: 118,
          directPriceToggle: true,
          quantity: 10,
        ),
      );
    }
    db.isAdminMutationAllowed = () => true;
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
    Future<void> tap(Finder finder) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    Future<void> enter(String id, String text) async {
      final finder = key(id);
      await tester.ensureVisible(finder);
      await tester.enterText(finder, text);
      await tester.pumpAndSettle();
    }

    final product = (await db.getAllProducts()).single;
    if (stage == 'prepare') {
      await tap(find.text('Process Recovery Rice'));
      await tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
      await enter('checkout-customer', 'Process Survivor');
      await tap(find.text('Partial'));
      await enter('checkout-partial-amount', '50.001');
      await tap(key('checkout-method-bank'));
      await enter('checkout-reference', 'SURVIVE-REF');
      final draft = (await db.loadCheckoutCart(
        await db.captureCheckoutScope(),
      ))!;
      expect(draft.state['step'], 'checkout');
      expect((draft.state['raw'] as Map)['name'], 'Process Survivor');
      expect((draft.state['raw'] as Map)['partial'], '50.001');
      expect(await db.getAllBills(), isEmpty);
      debugPrint('CHECKOUT_PROCESS_READY prepare');
    } else if (stage == 'restore') {
      // ScanScreen remains on its normal item route. Opening checkout restores
      // the saved step/fields; startup navigation itself is not changed.
      final draft = (await db.loadCheckoutCart(
        await db.captureCheckoutScope(),
      ))!;
      expect(draft.state['step'], 'checkout');
      await tap(find.bySemanticsIdentifier(TestKeys.scanBillBtn));
      expect(
        tester.widget<TextField>(key('checkout-customer')).controller!.text,
        'Process Survivor',
      );
      expect(
        tester
            .widget<TextField>(key('checkout-partial-amount'))
            .controller!
            .text,
        '50.001',
      );
      expect(
        tester.widget<TextField>(key('checkout-reference')).controller!.text,
        'SURVIVE-REF',
      );
      await tap(key('checkout-save'));
      expect(find.textContaining('at most two decimal places'), findsOneWidget);
      expect(await db.getAllBills(), isEmpty);
      expect((await db.getProductById(product.id!))!.quantity, 10);
      await enter('checkout-partial-amount', '50');
      await tap(key('checkout-unassigned-consent'));
      await tap(key('checkout-save'));
      expect(find.text('Bill Created!'), findsOneWidget);
      final bill = (await db.getAllBills()).single;
      expect(bill.customerName, 'Process Survivor');
      expect(bill.paidAmount, 50);
      expect(bill.balanceDue, 68);
      expect(bill.transactionReference, 'SURVIVE-REF');
      expect((await db.getProductById(product.id!))!.quantity, 9);
      debugPrint('CHECKOUT_PROCESS_READY restore');
    } else {
      expect(await db.loadCartDraft(), isEmpty);
      final bills = await db.getAllBills();
      expect(bills, hasLength(1));
      expect(bills.single.paidAmount, 50);
      expect(bills.single.balanceDue, 68);
      expect((await db.getProductById(product.id!))!.quantity, 9);
      final connection = await db.database;
      final acceptance = (await connection.query(
        'checkout_acceptances',
      )).single;
      final snapshot =
          jsonDecode(acceptance['posting_snapshot'] as String) as Map;
      expect(snapshot['invoice']['uuid'], bills.single.uuid);
      expect((snapshot['payments'] as List).single['amount'], 50);
      expect((snapshot['movements'] as List).single['quantity_delta'], -1);
      expect(
        Sqflite.firstIntValue(
          await connection.rawQuery('SELECT count(*) FROM bill_payments'),
        ),
        1,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
      await deleteDatabase(path);
      DatabaseHelper.databaseFileName = 'storely.db';
      db.isAdminMutationAllowed = null;
      return;
    }
    // Leave the running UI untouched until the host kills Android's process.
    await Future<void>.delayed(const Duration(minutes: 3));
    fail('Host did not force-stop the prepared process');
  });
}
