import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/screens/supplier_payments_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native supplier screen saves an offline payment and preserves it after reopen',
    (tester) async {
      final db = DatabaseHelper.instance;
      await db.close();
      DatabaseHelper.databaseFileName = 'supplier-payment-device-validation.db';
      final path = p.join(
        await getDatabasesPath(),
        DatabaseHelper.databaseFileName,
      );
      await deleteDatabase(path);
      db.isAdminMutationAllowed = () => true;
      try {
        await db.commitProductPurchaseBatch(
          [
            ProductPurchaseCommit(
              product: Product(
                name: 'Device payment fixture',
                purchasePrice: 50,
                quantity: 2,
              ),
              quantityAdded: 2,
            ),
          ],
          purchaseDate: DateTime(2026, 10, 1),
          usePurchaseSupplier: true,
          purchaseSupplier: 'Device payment supplier',
        );
        final receipt = (await db.getPurchaseDocuments()).single;
        final payload = {
          ...receipt.toJson(),
          'total': '100.00',
          'payment_status': 'unpaid',
          'paid_amount': '0.00',
          'balance_due': '100.00',
        };
        expect(
          await db.importPurchaseDocument(
            payload,
            shopId: await db.currentShopId(),
          ),
          isNull,
        );
        final supplier = (await db.getSupplierProfiles()).single;
        await tester.pumpWidget(
          MaterialApp(home: SupplierPaymentsScreen(supplier: supplier)),
        );
        await tester.pumpAndSettle();
        expect(find.text('Balance due: ₹100.00'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '40');
        await tester.ensureVisible(find.text('Save payment on this device'));
        await tester.tap(find.text('Save payment on this device'));
        await tester.pumpAndSettle();
        expect(find.text('Balance due: ₹60.00'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));
        await tester.pumpAndSettle();
        await db.close();
        final queued = await db.pendingSupplierPayments();
        expect(queued.length, 1);
        expect(
          (jsonDecode(queued.single['payload'] as String) as Map)['amount'],
          '40.00',
        );
        expect((await db.getAllProducts()).single.quantity, 2);
      } finally {
        await db.close();
        await deleteDatabase(path);
        DatabaseHelper.databaseFileName = 'storely.db';
        db.isAdminMutationAllowed = null;
      }
    },
  );
}
