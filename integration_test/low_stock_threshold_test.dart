import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/home_screen.dart';
import 'package:storely/screens/store_screen.dart';
import 'package:storely/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Store and Home edit the same offline low-stock threshold', (
    tester,
  ) async {
    final db = DatabaseHelper.instance;
    await db.close();
    final originalName = DatabaseHelper.databaseFileName;
    DatabaseHelper.databaseFileName = 'low-stock-threshold-validation.db';
    final path = await DatabaseHelper.databasePath();
    await deleteDatabase(path);
    try {
      await db.saveShopName('Stock fixture');
      for (final product in [
        Product(name: 'On alert boundary', quantity: 5.5001),
        Product(name: 'Above alert boundary', quantity: 5.5002),
        Product(name: 'Zero reorder override', quantity: 1, reorderLevel: 0),
        Product(name: 'Untracked service', quantity: 0, trackStock: false),
      ]) {
        await db.insertProduct(product);
      }

      Future<void> open(Widget screen) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: screen,
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder target) async {
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> enter(Finder target, String text) async {
        await tap(target);
        await tester.enterText(target, text);
        await tester.pumpAndSettle();
        expect(tester.widget<EditableText>(target).controller.text, text);
      }

      await open(const StoreScreen());
      final alertSetting = find.text('Low-stock alert');
      await tester.scrollUntilVisible(alertSetting, 250);
      await tap(alertSetting);
      final storeInput = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(storeInput).controller.text, '5');
      await enter(storeInput, '5.50001');
      final save = find.widgetWithText(FilledButton, 'Save');
      await tap(save);
      expect(
        tester.widget<EditableText>(storeInput).controller.text,
        '5.50001',
      );
      expect(await db.getLowStockThreshold(), 5);
      await enter(storeInput, '5.5001');
      await tap(save);
      expect(find.byType(AlertDialog), findsNothing);
      expect(await db.getLowStockThreshold(), 5.5001);

      final home = HomeScreen(
        onNavigate: (_) {},
        onScan: () {},
        onAddProduct: () {},
      );
      await open(home);
      final attention = find.widgetWithText(SectionHeader, 'Needs Attention');
      await tester.scrollUntilVisible(
        find.text('On alert boundary'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Above alert boundary'), findsNothing);
      expect(find.text('Zero reorder override'), findsNothing);
      expect(find.text('Untracked service'), findsNothing);

      await tap(
        find.descendant(of: attention, matching: find.byType(IconButton)),
      );
      final homeInput = find.descendant(
        of: find.byType(Dialog),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(homeInput).controller.text, '5.5001');
      await enter(homeInput, '5.5002');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(await db.getLowStockThreshold(), 5.5002);
      await tap(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(IconButton),
        ),
      );
      expect(find.text('On alert boundary'), findsOneWidget);
      expect(find.text('Above alert boundary'), findsOneWidget);

      await db.close();
      expect(await db.getLowStockThreshold(), 5.5002);
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
