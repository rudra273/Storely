import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/reports_screens.dart';
import 'package:storely/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Stock value shows the shop GST cost basis', (tester) async {
    final db = DatabaseHelper.instance;
    await db.close();
    final original = DatabaseHelper.databaseFileName;
    DatabaseHelper.databaseFileName = 'stock-valuation-device-validation.db';
    final path = await DatabaseHelper.databasePath();
    await deleteDatabase(path);
    try {
      Future<void> settings(String scheme) async {
        await db.saveShopProfile(
          ShopProfile(name: 'Valuation Shop', gstScheme: scheme),
        );
        await db.saveGlobalPricingSettings(
          GlobalPricingSettings(
            defaultGstPercent: 18,
            defaultOverheadCost: 5,
            defaultProfitMarginPercent: 0,
            gstRegistered: scheme == GstScheme.regular,
          ),
        );
      }

      await settings(GstScheme.composition);
      await db.insertProduct(
        Product(
          name: 'Valuation Rice',
          purchasePrice: 100,
          quantity: 10,
          directPriceToggle: true,
          manualPrice: 140,
        ),
      );

      Future<void> showValue(String value) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StockValueScreen(),
          ),
        );
        final total = find.text(value);
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (total.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(total, findsWidgets);
        expect(find.text('Valuation Rice'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }

      await showValue('₹1,230.00');
      await settings(GstScheme.regular);
      await showValue('₹1,050.00');
    } finally {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await db.close();
      await deleteDatabase(path);
      DatabaseHelper.databaseFileName = original;
    }
  });
}
