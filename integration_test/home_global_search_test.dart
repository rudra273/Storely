import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/screens/home_screen.dart';
import 'package:storely/services/home_section_prefs.dart';
import 'package:storely/theme/app_theme.dart';
import '../test/support/home_search_fixture.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'offline Home search selects exact product invoice and customer',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      final originalName = DatabaseHelper.databaseFileName;
      final originalAdmin = db.isAdminMutationAllowed;
      final originalGuard = db.assertAdminMutation;
      DatabaseHelper.databaseFileName = 'home-search-device-validation.db';
      final path = await DatabaseHelper.databasePath();
      await deleteDatabase(path);
      SharedPreferences.setMockInitialValues({});
      await HomeSectionPrefs.instance.load();
      db.isAdminMutationAllowed = () => true;
      db.assertAdminMutation = null;
      Finder label(String text) => find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == text,
      );
      final search = find.byKey(const ValueKey('home-global-search'));
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

      Future<void> query(String value) async {
        await wait(search);
        await tester.ensureVisible(search);
        await tester.tap(search);
        await tester.pumpAndSettle();
        await tester.enterText(search, value);
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
      }

      try {
        await seedHomeSearchFixture();
        await tester.pumpWidget(
          MaterialApp(
            theme: StorelyTheme.light(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeScreen(
              onNavigate: (_) => fail('Must select exact record'),
              onScan: () {},
              onAddProduct: () {},
            ),
          ),
        );
        await tap(find.byIcon(Icons.search_rounded));
        await query('Match');
        await wait(label('Match Product A'));
        expect(label('Match Product F'), findsNothing);
        expect(label('MATCH-A'), findsNothing);
        expect(label('MATCH-F'), findsOneWidget);
        expect(label('Match Customer A'), findsOneWidget);
        expect(label('Match Customer F'), findsNothing);
        expect(find.textContaining('Foreign'), findsNothing);
        await tap(label('Match Product A'));
        await wait(label('Edit Product'));
        final productNames = tester
            .widgetList<TextFormField>(find.byType(TextFormField))
            .map((field) => field.controller?.text)
            .toList();
        expect(productNames, contains('Match Product A'));
        expect(productNames, contains('CODE-A'));
        expect(productNames, isNot(contains('CODE-B')));
        await tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await query('MATCH-F');
        await wait(label('MATCH-F'));
        await tap(label('MATCH-F'));
        await wait(label('Buyer F'));
        expect(label('Buyer E'), findsNothing);
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        await query('Match Customer A');
        await tap(label('Match Customer A'));
        await wait(label('Customer'));
        await wait(label('Road A'));
        expect(label('GSTIN GST-A'), findsOneWidget);
        expect(label('Road B'), findsNothing);
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
        await query('Buyer555');
        await wait(label('No matching products, bills, or customers'));
        await query('+555 (000) 0000');
        await wait(label('Match Customer A'));
        expect(find.textContaining('Foreign'), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = originalName;
        db.isAdminMutationAllowed = originalAdmin;
        db.assertAdminMutation = originalGuard;
      }
    },
  );
}
