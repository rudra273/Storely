import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/home_screen.dart';
import 'package:storely/screens/welcome_screen.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/utils/test_keys.dart';

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'first-invoice-onboarding.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
  });
  tearDown(() async {
    db.isAdminMutationAllowed = null;
    db.assertAdminMutation = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  Bill original() => Bill(
    uuid: 'original',
    totalAmount: 118,
    itemCount: 1,
    paidAmount: 0,
    isPaid: false,
  );
  test(
    'fresh placeholder is incomplete but an explicitly saved My Shop survives reopening',
    () async {
      expect(await db.hasCompletedShopSetup(), isFalse);
      await db.saveShopName('My Shop');
      expect(await db.hasCompletedShopSetup(), isTrue);
      await db.close();
      expect(await db.hasCompletedShopSetup(), isTrue);
    },
  );
  test(
    'milestone counts saved original invoices across dates and cancellation, excluding carts and credit notes',
    () async {
      expect(await db.getFirstInvoiceProgress(), (
        hasProducts: false,
        hasInvoice: false,
      ));
      final item = BillItem(productName: 'Manual', sellingPriceSnapshot: 118);
      await db.holdBill('Held', [item]);
      await db.saveCartDraft([item]);
      await db.insertBill(
        Bill(
          totalAmount: -118,
          itemCount: 1,
          documentType: Bill.documentCreditNote,
          paidAmount: 0,
          isPaid: false,
        ),
        [],
      );
      expect((await db.getFirstInvoiceProgress()).hasInvoice, isFalse);
      final id = await db.insertProduct(
        Product(
          name: 'Tea',
          purchasePrice: 100,
          sellingPrice: 118,
          quantity: 10,
        ),
      );
      expect(await db.getFirstInvoiceProgress(), (
        hasProducts: true,
        hasInvoice: false,
      ));
      final billId = await db.insertBill(original(), []);
      await db.cancelBill(billId, reason: 'Keep first invoice milestone');
      final sql = await db.database;
      await sql.update(
        'products',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(await db.getFirstInvoiceProgress(), (
        hasProducts: false,
        hasInvoice: true,
      ));
    },
  );
  test('milestone ignores another tenant products and invoice rows', () async {
    final sql = await db.database;
    await sql.insert(
      'products',
      Product(
        uuid: 'foreign-product',
        shopId: 'foreign-shop',
        name: 'Foreign',
        quantity: 1,
      ).toMap()..remove('id'),
    );
    await sql.insert(
      'bills',
      Bill(
        uuid: 'foreign-bill',
        shopId: 'foreign-shop',
        billNumber: 'FOREIGN',
        totalAmount: 118,
        itemCount: 1,
      ).toMap()..remove('id'),
    );
    expect(await db.getFirstInvoiceProgress(), (
      hasProducts: false,
      hasInvoice: false,
    ));
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> until(WidgetTester tester, bool Function() ready) async {
    for (var attempt = 0; attempt < 150 && !ready(); attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(ready(), isTrue);
  }

  testWidgets(
    'owner sees saved-data next action, draft does not complete it and staff sees no setup guide',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var add = 0;
      var invoice = 0;
      Future<void> mount(int refresh) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeScreen(
              refreshToken: refresh,
              onNavigate: (_) {},
              onScan: () {},
              onFirstInvoice: () => invoice++,
              onAddProduct: () => add++,
            ),
          ),
        );
        await until(
          tester,
          () =>
              find
                  .bySemanticsIdentifier(TestKeys.homeAddProductBtn)
                  .evaluate()
                  .isNotEmpty &&
              (refresh == 0
                  ? find
                        .byKey(const ValueKey('onboarding-add-product'))
                        .evaluate()
                        .isNotEmpty
                  : refresh < 3
                  ? find
                        .byKey(const ValueKey('onboarding-first-invoice'))
                        .evaluate()
                        .isNotEmpty
                  : find
                        .byKey(const ValueKey('onboarding-guidance'))
                        .evaluate()
                        .isEmpty),
        );
      }

      await mount(0);
      await tester.tap(find.byKey(const ValueKey('onboarding-add-product')));
      expect(add, 1);
      await tester.runAsync(
        () => db.insertProduct(
          Product(
            name: 'Tea',
            purchasePrice: 100,
            sellingPrice: 118,
            quantity: 10,
          ),
        ),
      );
      await mount(1);
      await tester.tap(find.byKey(const ValueKey('onboarding-first-invoice')));
      expect(invoice, 1);
      await tester.runAsync(
        () => db.saveCartDraft([
          BillItem(productName: 'Draft', sellingPriceSnapshot: 118),
        ]),
      );
      await mount(2);
      expect(
        find.byKey(const ValueKey('onboarding-first-invoice')),
        findsOneWidget,
      );
      db.isAdminMutationAllowed = () => false;
      await mount(3);
      expect(find.byKey(const ValueKey('onboarding-guidance')), findsNothing);
      db.isAdminMutationAllowed = () => true;
      await tester.runAsync(() => db.insertBill(original(), []));
      await mount(4);
      expect(find.byKey(const ValueKey('onboarding-guidance')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets(
    'fresh local setup retains name on failure and prevents duplicate save submission',
    (tester) async {
      var completed = 0;
      var calls = 0;
      db.assertAdminMutation = () async {
        calls++;
        throw StateError('Fixture cannot save yet');
      };
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: WelcomeScreen(onComplete: () => completed++),
        ),
      );
      await tester.tap(find.text('Start Fresh'));
      await tester.pumpAndSettle();
      final input = find.descendant(
        of: find.bySemanticsIdentifier(TestKeys.welcomeShopNameField),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(input, 'My Shop');
      await tester.tap(find.bySemanticsIdentifier(TestKeys.welcomeContinueBtn));
      await settle(tester);
      expect(completed, 0);
      expect(tester.widget<TextFormField>(input).controller!.text, 'My Shop');
      expect(calls, 1);
      db.assertAdminMutation = null;
      await tester.tap(find.bySemanticsIdentifier(TestKeys.welcomeContinueBtn));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await until(tester, () => completed == 1);
      expect(completed, 1);
      expect(await tester.runAsync(db.hasCompletedShopSetup), isTrue);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
