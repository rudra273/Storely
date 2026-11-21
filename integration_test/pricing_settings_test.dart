import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/screens/pricing_screen.dart';
import 'package:storely/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'offline pricing edits and product writes honor the shop scheme',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      final originalName = DatabaseHelper.databaseFileName;
      DatabaseHelper.databaseFileName = 'pricing-settings-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      try {
        await db.saveShopProfile(
          ShopProfile(
            name: 'Pricing fixture',
            gstScheme: GstScheme.composition,
          ),
        );
        final shopId = (await db.getShopProfile())!.uuid;
        final sql = await db.database;
        Future<void> setRaw(String key, String value) async {
          await sql.update(
            'app_settings',
            {'value': value},
            where: 'shop_id = ? AND key = ?',
            whereArgs: [shopId, key],
          );
        }

        // Older sync data can carry a flag that conflicts with the profile.
        await setRaw('gst_registered', '1');
        final messages = GlobalKey<ScaffoldMessengerState>();
        Future<void> openPricing() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await tester.pumpWidget(
            MaterialApp(
              scaffoldMessengerKey: messages,
              theme: StorelyTheme.light(),
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const PricingScreen(),
            ),
          );
          await tester.pumpAndSettle();
        }

        Finder input(String label) => find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        final overhead = input('Default Overhead ₹');
        final margin = input('Default Profit Margin %');
        final save = find.widgetWithText(FilledButton, 'Save Defaults');
        Future<void> enter(Finder field, String text) async {
          await tester.ensureVisible(field);
          await tester.tap(field);
          await tester.pumpAndSettle();
          await tester.enterText(field, text);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field).controller!.text, text);
        }

        Future<void> saveDefaults() async {
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pumpAndSettle();
          await tester.ensureVisible(save);
          await tester.tap(save);
          await tester.pumpAndSettle();
        }

        await openPricing();
        await enter(overhead, '10');
        await enter(margin, '12.3456');
        await saveDefaults();
        expect(find.textContaining('at most 3 decimal places'), findsOneWidget);
        final rejected = await db.getGlobalPricingSettings();
        expect(rejected.defaultOverheadCost, 0);
        expect(rejected.defaultProfitMarginPercent, 0);
        expect(tester.widget<TextField>(margin).controller!.text, '12.3456');

        messages.currentState!.removeCurrentSnackBar();
        await tester.pumpAndSettle();
        await enter(margin, '12.345');
        await saveDefaults();
        final saved = await db.getGlobalPricingSettings();
        final feedback = find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(Text),
        );
        expect(
          saved.defaultOverheadCost,
          10,
          reason: tester
              .widgetList<Text>(feedback)
              .map((text) => text.data)
              .join(', '),
        );
        expect(saved.defaultProfitMarginPercent, 12.345);
        await openPricing();
        expect(tester.widget<TextField>(margin).controller!.text, '12.345');

        final compositionProduct = Product(
          name: 'Composition',
          purchasePrice: 1000,
          quantity: 0,
        );
        final composition = await db.resolveProductPrice(compositionProduct);
        expect(composition.gstRegistered, isFalse);
        expect(composition.sellingPrice, closeTo(1336.90550, 0.000001));
        final compositionId = await db.insertProduct(compositionProduct);
        expect(
          (await db.getProductById(compositionId))!.sellingPrice,
          closeTo(1336.90550, 0.000001),
        );

        await setRaw('gst_scheme', GstScheme.regular);
        await setRaw('gst_registered', '0');
        final regularProduct = Product(
          name: 'Regular',
          purchasePrice: 1000,
          quantity: 0,
        );
        final regular = await db.resolveProductPrice(regularProduct);
        expect(regular.gstRegistered, isTrue);
        expect(regular.sellingPrice, closeTo(1338.92771, 0.000001));
        final regularId = await db.insertProduct(regularProduct);
        expect(
          (await db.getProductById(regularId))!.sellingPrice,
          closeTo(1338.92771, 0.000001),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = originalName;
      }
    },
  );
}
