import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/l10n/app_localizations.dart';
import 'package:storely/screens/products_screen.dart';
import 'package:storely/screens/purchase_history_screen.dart';

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    await db.close();
    DatabaseHelper.databaseFileName = 'purchase-history-ui.db';
    await deleteDatabase(
      p.join(await getDatabasesPath(), DatabaseHelper.databaseFileName),
    );
  });
  tearDown(() async {
    db.isAdminMutationAllowed = null;
    await db.close();
    await deleteDatabase(
      p.join(await getDatabasesPath(), DatabaseHelper.databaseFileName),
    );
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  testWidgets('narrow history shows queued totals and original line details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      await db.commitProductPurchaseBatch([
        ProductPurchaseCommit(
          quantityAdded: 3,
          product: Product(
            name: 'Tea',
            purchasePrice: 2.5,
            quantity: 3,
            unit: 'pcs',
          ),
        ),
      ], purchaseDate: DateTime(2026, 1, 1));
    });
    await tester.pumpWidget(const MaterialApp(home: PurchaseHistoryScreen()));
    for (var i = 0; i < 10 && find.text('₹7.50').evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(find.text('₹7.50'), findsOneWidget);
    expect(find.textContaining('Waiting for document sync'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('No supplier'));
    await tester.pumpAndSettle();
    expect(find.text('Purchase receipt'), findsOneWidget);
    expect(find.textContaining('Tea'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'staff route hides purchase costs without a failed database future',
    (tester) async {
      db.isAdminMutationAllowed = () => false;
      await tester.pumpWidget(const MaterialApp(home: PurchaseHistoryScreen()));
      await tester.pumpAndSettle();
      expect(
        find.text('Purchase history is available to owners and admins.'),
        findsOneWidget,
      );
      expect(find.byType(ListTile), findsNothing);
      expect(find.text('New purchase'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Purchases owns New purchase while Items and Create Item stay decoupled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PurchaseHistoryScreen(),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
      expect(find.text('Purchases'), findsOneWidget);
      expect(find.text('New purchase'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ProductsScreen(),
        ),
      );
      for (var i = 0; i < 10 && find.text('Add item').evaluate().isEmpty; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
      }
      expect(find.text('Add purchase'), findsNothing);
      expect(find.text('New purchase / import'), findsNothing);
      expect(find.byTooltip('Purchase history'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ItemFormScreen(
            categories: const [],
            units: const ['pcs'],
            scanBarcode: (_) async => null,
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 150)),
      );
      await tester.pump();
      expect(find.textContaining('Full purchase entry'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
