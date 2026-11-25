import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/screens/bills_screen.dart';
import 'package:storely/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('returns a fractional quantity through the Bills screen', (
    tester,
  ) async {
    final db = DatabaseHelper.instance;
    await db.close();
    final original = DatabaseHelper.databaseFileName;
    DatabaseHelper.databaseFileName = 'return-quantity-device-validation.db';
    final path = await DatabaseHelper.databasePath();
    await deleteDatabase(path);
    try {
      await db.saveBillSettings(BillSettings(roundOffTotal: false));
      final invoice = await db.insertBill(
        Bill(
          customerName: 'Fractional Buyer',
          totalAmount: 20,
          paidAmount: 20,
          itemCount: 1,
        ),
        [
          BillItem(
            productName: 'Loose item',
            quantity: 2,
            sellingPriceSnapshot: 10,
            taxableValueSnapshot: 10,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const BillsScreen(),
        ),
      );
      Future<void> waitFor(Finder finder) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(finder, findsWidgets);
      }

      Future<void> tap(Finder finder) async {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await waitFor(finder);
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      await tap(find.text('Fractional Buyer').first);
      await tap(find.text('Return', findRichText: true));
      final originalBill = (await db.getBillById(invoice))!;
      final line = originalBill.items.single;
      final field = find.byKey(ValueKey('return-quantity-${line.uuid}'));
      final submit = find.widgetWithText(FilledButton, 'Issue Credit Note');
      await waitFor(field);
      for (final invalid in ['0.1251', '2.001']) {
        await tester.enterText(field, invalid);
        await tester.pumpAndSettle();
        expect(tester.widget<FilledButton>(submit).onPressed, isNull);
        expect(tester.widget<TextField>(field).controller!.text, invalid);
      }
      await tester.enterText(field, '0.12500');
      await tap(submit);
      await waitFor(find.textContaining(' issued'));
      final credit = (await db.getAllBills()).singleWhere(
        (bill) => bill.isCreditNote,
      );
      expect(credit.items.single.quantity, -0.125);
      expect((await db.returnableQuantities(invoice))[line.uuid], 1.875);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await db.close();
      await deleteDatabase(path);
      DatabaseHelper.databaseFileName = original;
    }
  });
}
