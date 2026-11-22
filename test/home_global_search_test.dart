import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/customer.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/home_screen.dart';
import 'package:storely/screens/products_screen.dart';
import 'package:storely/screens/customers_screen.dart';
import 'package:storely/services/home_search.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/theme/app_theme.dart';
import 'support/home_search_fixture.dart';

void main() {
  test('literal fields, phone-shaped query, alias and shared cap', () {
    final phone = Customer(
      name: 'Alice',
      phone: '+91 (555) 123-4567',
      totalPurchaseAmount: 0,
      billCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    expect(HomeSearchQuery('555 123').customer(phone), isTrue);
    expect(HomeSearchQuery('Alice555').customer(phone), isFalse);
    expect(HomeSearchQuery('GST 123').customer(phone), isFalse);
    expect(HomeSearchQuery('+-()').customer(phone), isFalse);
    expect(
      HomeSearchQuery(
        'BAR-a',
      ).product(Product(quantity: 0, name: 'Tea', barcode: 'bar-A')),
      isTrue,
    );
    expect(
      HomeSearchQuery(
        'tools',
      ).product(Product(quantity: 0, name: 'Tea', category: 'Tools')),
      isTrue,
    );
    final supplier = Product(
      quantity: 0,
      name: 'Tea',
      supplier: 'Secret Vendor',
    );
    expect(HomeSearchQuery('secret').product(supplier), isTrue);
    expect(
      HomeSearchQuery('secret').product(supplier, allowSupplier: false),
      isFalse,
    );
    final bill = Bill(
      billNumber: 'SHOP-LOCAL-local-123',
      totalAmount: 1,
      itemCount: 0,
    );
    expect(HomeSearchQuery('INV-123').bill(bill), isTrue);
    expect(HomeSearchQuery('SHOP-LOCAL-local-123').bill(bill), isTrue);
    expect(
      HomeSearchQuery('INV-123').bill(
        Bill(billNumber: 'XSHOP-LOCAL-local-123', totalAmount: 1, itemCount: 0),
      ),
      isFalse,
    );
    final cappedPhone = '1' * 60;
    final capped = HomeSearchQuery('$cappedPhone X');
    expect(capped.text, cappedPhone);
    expect(capped.phoneDigits, cappedPhone);
  });
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.close();
    DatabaseHelper.databaseFileName = 'home-search-test.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    db.isAdminMutationAllowed = () => true;
  });
  tearDown(() async {
    db.isAdminMutationAllowed = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });
  test(
    'search projection rejects deleted and foreign related names without changing legacy reads',
    () async {
      await seedHomeSearchFixture();
      final shop = await db.currentShopId();
      final sql = await db.database;
      await sql.update(
        'categories',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'shop_id = ?',
        whereArgs: [shop],
      );
      await sql.update(
        'suppliers',
        {'shop_id': 'foreign-shop'},
        where: 'shop_id = ?',
        whereArgs: [shop],
      );
      final search = await db.getProductsForHomeSearch(shop);
      expect(search.length, 6);
      expect(
        search.every((p) => p.category == null && p.supplier == null),
        isTrue,
      );
      final legacy = (await db.getAllProducts()).where((p) => p.shopId == shop);
      expect(
        legacy.every(
          (p) => p.category == 'Tools' && p.supplier == 'Secret Vendor',
        ),
        isTrue,
      );
      final scope = await db.captureCheckoutScope();
      expect(await isCurrentHomeSearchScope(scope), isTrue);
      expect(
        await isCurrentHomeSearchScope(
          CheckoutScope('other-shop', scope.owner, scope.deviceId),
        ),
        isFalse,
      );
      expect(
        await isCurrentHomeSearchScope(
          CheckoutScope(shop, 'other-owner', scope.deviceId),
        ),
        isFalse,
      );
    },
  );

  Future<void> ready(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 200 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(finder, findsWidgets);
  }

  testWidgets(
    'five results per type exclude foreign tenant and retain exact destination identity',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.runAsync(seedHomeSearchFixture);
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            onNavigate: (_) => fail('Must open exact detail'),
            onScan: () {},
            onAddProduct: () {},
          ),
        ),
      );
      await ready(tester, find.byIcon(Icons.search_rounded));
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      final search = find.byKey(const ValueKey('home-global-search'));
      await tester.enterText(search, 'Match');
      await ready(tester, find.text('Match Product A'));
      expect(find.text('Match Product F'), findsNothing);
      expect(find.text('MATCH-A'), findsNothing);
      expect(
        find.byWidgetPredicate((w) => w is Text && w.data == 'MATCH-F'),
        findsOneWidget,
      );
      expect(find.text('Match Customer A'), findsOneWidget);
      expect(find.text('Match Customer F'), findsNothing);
      expect(find.textContaining('Foreign'), findsNothing);
      expect(find.textContaining('Due '), findsNothing);
      expect(
        await tester.runAsync(() async {
          final sql = await db.database;
          return sql.query(
            'customers',
            where: 'phone = ?',
            whereArgs: ['5559999999'],
          );
        }),
        isEmpty,
      );
      await tester.ensureVisible(
        find.byWidgetPredicate((w) => w is Text && w.data == 'MATCH-F'),
      );
      await tester.tap(
        find.byWidgetPredicate((w) => w is Text && w.data == 'MATCH-F'),
      );
      await ready(tester, find.text('Buyer F'));
      expect(find.text('Buyer E'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets('missing scoped targets do not reprice or open stale details', (
    tester,
  ) async {
    await tester.runAsync(seedHomeSearchFixture);
    final scope = (await tester.runAsync(db.captureCheckoutScope))!;
    await tester.runAsync(() async {
      final sql = await db.database;
      await sql.update(
        'products',
        {'selling_price': 999},
        where: 'uuid = ?',
        whereArgs: ['product-A'],
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: StorelyTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ProductsScreen(
          initialProductUuid: 'foreign-product',
          searchScope: scope,
        ),
      ),
    );
    await ready(
      tester,
      find.textContaining('This product is no longer available.'),
    );
    expect(find.text('Edit Product'), findsNothing);
    expect(find.text('Match Foreign Product'), findsNothing);
    expect(
      await tester.runAsync(() async {
        final sql = await db.database;
        return (await sql.query(
          'products',
          where: 'uuid = ?',
          whereArgs: ['product-A'],
        )).single['selling_price'];
      }),
      999,
    );
    await tester.pumpWidget(
      MaterialApp(
        key: const ValueKey('customer-missing'),
        theme: StorelyTheme.light(),
        home: CustomersScreen(
          initialCustomerUuid: 'foreign-customer',
          searchScope: scope,
        ),
      ),
    );
    await ready(
      tester,
      find.textContaining('This customer is no longer available.'),
    );
    expect(find.text('Match Foreign Customer'), findsNothing);
    expect(find.text('Customer'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('a deleted invoice cannot open a stale Home result', (
    tester,
  ) async {
    await tester.runAsync(seedHomeSearchFixture);
    await tester.pumpWidget(
      MaterialApp(
        theme: StorelyTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(
          onNavigate: (_) => fail('No generic route'),
          onScan: () {},
          onAddProduct: () {},
        ),
      ),
    );
    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('home-global-search')),
      'MATCH-F',
    );
    await ready(
      tester,
      find.byWidgetPredicate((w) => w is Text && w.data == 'MATCH-F'),
    );
    await tester.runAsync(() async {
      final sql = await db.database;
      await sql.update(
        'bills',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'uuid = ?',
        whereArgs: ['bill-F'],
      );
    });
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Text && w.data == 'MATCH-F'),
    );
    await ready(tester, find.text('This invoice is no longer available.'));
    expect(find.text('Buyer F'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  });
  testWidgets(
    'staff product search opens safe read-only details and excludes supplier matching',
    (tester) async {
      await tester.runAsync(seedHomeSearchFixture);
      db.isAdminMutationAllowed = () => false;
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            onNavigate: (_) => fail('No catalog route for staff'),
            onScan: () {},
            onAddProduct: () {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      final search = find.byKey(const ValueKey('home-global-search'));
      await tester.enterText(search, 'Secret Vendor');
      await ready(
        tester,
        find.text('No matching products, bills, or customers'),
      );
      await tester.enterText(search, 'CODE-A');
      await ready(tester, find.text('Match Product A'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match Product A'));
      await ready(tester, find.text('Code: CODE-A'));
      expect(find.text('Barcode: BAR-A'), findsOneWidget);
      expect(find.text('Edit Product'), findsNothing);
      expect(find.byType(ProductsScreen), findsNothing);
      expect(find.textContaining('Secret Vendor'), findsNothing);
      expect(find.textContaining('Purchase'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
  testWidgets(
    'account scope mismatch prevents opening a previously loaded product',
    (tester) async {
      await tester.runAsync(seedHomeSearchFixture);
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            onNavigate: (_) => fail('No stale navigation'),
            onScan: () {},
            onAddProduct: () {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('home-global-search')),
        'CODE-A',
      );
      await ready(tester, find.text('Match Product A'));
      await tester.runAsync(
        () => db.setCloudSyncState('preference_owner', 'different-owner'),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Match Product A'));
      await ready(tester, find.text('Shop changed. Search again.'));
      expect(find.byType(ProductsScreen), findsNothing);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
    },
  );

  testWidgets(
    'role changes clear search immediately while ordinary sync state keeps query',
    (tester) async {
      final cloud = CloudService.instance;
      final originalState = cloud.state.value;
      await tester.runAsync(seedHomeSearchFixture);
      await tester.pumpWidget(
        MaterialApp(
          theme: StorelyTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(
            onNavigate: (_) {},
            onScan: () {},
            onAddProduct: () {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.search_rounded));
      await tester.pump();
      final search = find.byKey(const ValueKey('home-global-search'));
      await tester.enterText(search, 'Secret Vendor');
      await ready(tester, find.text('Match Product A'));
      cloud.state.value = originalState.copyWith(phase: CloudSyncPhase.syncing);
      await tester.pump();
      expect(
        tester.widget<TextField>(search).controller!.text,
        'Secret Vendor',
      );
      db.isAdminMutationAllowed = () => false;
      cloud.state.value = originalState.copyWith(shopRole: 'staff');
      await tester.pump();
      expect(tester.widget<TextField>(search).controller!.text, isEmpty);
      expect(find.text('Match Product A'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 25; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      cloud.state.value = originalState;
    },
  );
}
