import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/screens/store_screen.dart';
import 'package:storely/theme/app_theme.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Store settings search uses aliases and existing editors without changing settings',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      final original = DatabaseHelper.databaseFileName;
      DatabaseHelper.databaseFileName = 'settings-search-device-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      SharedPreferences.setMockInitialValues({});
      Finder label(String text) =>
          find.byWidgetPredicate((w) => w is Text && w.data == text);
      final search = find.byKey(const ValueKey('store-settings-search'));
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
        await Scrollable.ensureVisible(
          finder.evaluate().single,
          alignment: 0.5,
        );
        await tester.pumpAndSettle();
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> query(String text) async {
        await wait(search);
        await tester.ensureVisible(search);
        await tester.tap(search);
        await tester.pumpAndSettle();
        await tester.enterText(search, text);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      try {
        await db.saveShopName('Private Sapphire Shop');
        final baseline = await db.captureSettingsEditBaseline();
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const StoreScreen(),
          ),
        );
        await query('Private Sapphire Shop');
        expect(label('No matching settings'), findsOneWidget);
        await query('threshold');
        expect(label('Low-stock alert'), findsOneWidget);
        expect(label('Pricing Defaults'), findsNothing);
        await tap(label('Low-stock alert'));
        await wait(label('Needs Attention'));
        await tap(label('Cancel'));
        await query('footer');
        await tap(label('Bill Settings'));
        await wait(label('Bill Settings'));
        expect(find.byType(StoreScreen), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await query('theme');
        await tap(label('App Settings'));
        await wait(label('App Settings'));
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await query('');
        expect(label('Bill Settings'), findsOneWidget);
        expect(label('Pricing Defaults'), findsOneWidget);
        expect(
          (await db.captureSettingsEditBaseline()).toLocalMap(),
          baseline.toLocalMap(),
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = original;
      }
    },
  );
}
