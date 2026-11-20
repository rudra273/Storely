import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/l10n/l10n.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/product.dart';
import 'package:storely/screens/scan_screen.dart';
import 'package:storely/utils/checkout_code.dart';
import 'package:storely/utils/test_keys.dart';

Future<void> settleIo(WidgetTester tester) async {
  for (var n = 0; n < 8; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitForFinder(WidgetTester tester, Finder finder) async {
  for (var n = 0; n < 25 && finder.evaluate().isEmpty; n++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await settleIo(tester);
}

Future<void> enterField(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  await tester.enterText(finder, text);
  await settleIo(tester);
}

Future<void> submitSearchCode(WidgetTester tester, String raw) async {
  final search = find.byKey(const ValueKey('checkout-product-search'));
  await tester.ensureVisible(search);
  await tester.tap(search);
  await tester.pump();
  await tester.enterText(search, raw);
  await tester.pump();
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await settleIo(tester);
}

String fieldText(WidgetTester tester, Finder finder) => tester
    .widget<EditableText>(
      find.descendant(of: finder, matching: find.byType(EditableText)),
    )
    .controller
    .text;

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db.onDatabaseChanged = null;
    db.assertAdminMutation = null;
    db.isAdminMutationAllowed = null;
    await db.close();
    DatabaseHelper.databaseFileName = 'checkout-product-entry.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    await db.saveBillSettings(BillSettings());
  });

  tearDown(() async {
    db.onDatabaseChanged = null;
    db.assertAdminMutation = null;
    db.isAdminMutationAllowed = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  group('checkoutBarcodeCandidate', () {
    test('accepts valid trimmed product codes up to 64 characters', () {
      expect(checkoutBarcodeCandidate('SKU123'), 'SKU123');
      expect(checkoutBarcodeCandidate('  SKU-101_a.2  '), 'SKU-101_a.2');
      expect(checkoutBarcodeCandidate('A'), 'A');
      expect(checkoutBarcodeCandidate('8901234567890'), '8901234567890');
      expect(checkoutBarcodeCandidate('A' * 64), 'A' * 64);
      expect(
        checkoutBarcodeCandidate('G1234567890123456789012345678901'),
        'G1234567890123456789012345678901',
      );
    });

    test('rejects invalid formats, UUIDs, URLs, JSON and control chars', () {
      expect(checkoutBarcodeCandidate(''), isNull);
      expect(checkoutBarcodeCandidate('   '), isNull);
      expect(checkoutBarcodeCandidate('A' * 65), isNull);
      expect(checkoutBarcodeCandidate('.SKU'), isNull);
      expect(checkoutBarcodeCandidate('-SKU'), isNull);
      expect(checkoutBarcodeCandidate('_SKU'), isNull);
      expect(checkoutBarcodeCandidate('SKU 123'), isNull);
      expect(checkoutBarcodeCandidate('https://storely.app/p/1'), isNull);
      expect(checkoutBarcodeCandidate('{"uuid":"123"}'), isNull);
      expect(checkoutBarcodeCandidate('[1,2,3]'), isNull);
      expect(
        checkoutBarcodeCandidate('0123456789abcdef0123456789abcdef'),
        isNull,
      );
      expect(
        checkoutBarcodeCandidate('123e4567-e89b-12d3-a456-426614174000'),
        isNull,
      );
      expect(
        checkoutBarcodeCandidate('123E4567-E89B-12D3-A456-426614174000'),
        isNull,
      );
      for (final control in [
        'SKU\n1',
        'SKU\r1',
        'SKU\t1',
        'SKU\x001',
        'SKU\x1f1',
        'SKU\x7f1',
        'SKU\x801',
        'SKU\x9f1',
      ]) {
        expect(checkoutBarcodeCandidate(control), isNull);
      }
    });
  });

  group('resolveCheckoutProduct', () {
    test(
      'resolves case-insensitive barcode/code, structured labels and exact full name',
      () async {
        final scope = await db.captureCheckoutScope();
        final id = await db.insertProduct(
          Product(
            name: 'Whole Wheat Flour',
            productCode: 'Code-Mix-99',
            barcode: 'Bar-Case-01',
            sellingPrice: 60,
            quantity: 10,
          ),
        );
        final product = (await db.getProductById(id))!;

        expect(
          (await db.resolveCheckoutProduct('bar-case-01', scope))?.uuid,
          product.uuid,
        );
        expect(
          (await db.resolveCheckoutProduct('  CODE-MIX-99 ', scope))?.uuid,
          product.uuid,
        );
        expect(
          (await db.resolveCheckoutProduct(product.uuid, scope))?.uuid,
          product.uuid,
        );
        expect(
          await db.resolveCheckoutProduct(product.uuid.toUpperCase(), scope),
          isNull,
        );
        expect(
          (await db.resolveCheckoutProduct(
            jsonEncode({'uuid': product.uuid}),
            scope,
          ))?.uuid,
          product.uuid,
        );
        expect(
          (await db.resolveCheckoutProduct(
            jsonEncode({'barcode': 'BAR-CASE-01'}),
            scope,
          ))?.uuid,
          product.uuid,
        );
        expect(
          (await db.resolveCheckoutProduct(
            jsonEncode({'code': 'code-mix-99'}),
            scope,
          ))?.uuid,
          product.uuid,
        );
        expect(
          (await db.resolveCheckoutProduct(
            jsonEncode({'id': id, 'name': 'Ignored'}),
            scope,
          ))?.uuid,
          product.uuid,
        );
        expect(
          await db.resolveCheckoutProduct(
            jsonEncode({'uuid': 'missing-uuid', 'name': 'Whole Wheat Flour'}),
            scope,
          ),
          isNull,
        );
        expect(
          (await db.resolveCheckoutProduct('whole wheat flour', scope))?.uuid,
          product.uuid,
        );
        expect(await db.resolveCheckoutProduct('Wheat', scope), isNull);
      },
    );

    test(
      'handles ambiguous codes, duplicate names, malformed JSON and scope mismatches',
      () async {
        final scope = await db.captureCheckoutScope();
        await db.insertProduct(
          Product(
            name: 'Sugar',
            barcode: 'AMB-01',
            sellingPrice: 40,
            quantity: 5,
          ),
        );
        await db.insertProduct(
          Product(
            name: 'Sugar',
            productCode: 'amb-01',
            sellingPrice: 45,
            quantity: 5,
          ),
        );

        await expectLater(
          db.resolveCheckoutProduct('AMB-01', scope),
          throwsStateError,
        );
        await expectLater(
          db.resolveCheckoutProduct('sugar', scope),
          throwsStateError,
        );
        expect(await db.resolveCheckoutProduct('{broken json', scope), isNull);
        expect(await db.resolveCheckoutProduct('[broken json', scope), isNull);
        await expectLater(
          db.resolveCheckoutProduct('[1, 2, 3]', scope),
          throwsFormatException,
        );

        final wrongShopScope = CheckoutScope(
          'other-shop',
          scope.owner,
          scope.deviceId,
        );
        await expectLater(
          db.resolveCheckoutProduct('{broken json', wrongShopScope),
          throwsStateError,
        );

        await db.setCloudSyncState('preference_owner', 'other-owner');
        await expectLater(
          db.resolveCheckoutProduct('AMB-01', scope),
          throwsStateError,
        );
      },
    );
  });

  group('insertProductForCheckout & productForCheckoutReturn', () {
    test(
      'returns exact UUID with edited barcode, saves zero-stock tracked product and enforces guards',
      () async {
        final scope = await db.captureCheckoutScope();
        await db.insertProduct(
          Product(
            name: 'Existing Rice',
            barcode: 'Existing-BC',
            sellingPrice: 118,
            quantity: 10,
          ),
        );

        final saved = await db.insertProductForCheckout(
          Product(
            name: 'Edited Barcode Item',
            barcode: 'EDITED-BC-01',
            sellingPrice: 35,
            quantity: 4,
          ),
          scope,
        );
        expect(saved.uuid, isNotEmpty);
        expect(saved.barcode, 'EDITED-BC-01');
        expect(saved.shopId, scope.shopId);

        final returned = await db.productForCheckoutReturn(saved.uuid, scope);
        expect(returned.uuid, saved.uuid);
        expect(returned.barcode, 'EDITED-BC-01');

        await expectLater(
          db.insertProductForCheckout(
            Product(
              name: 'Duplicate Barcode',
              barcode: 'existing-bc',
              sellingPrice: 15,
              quantity: 1,
            ),
            scope,
          ),
          throwsArgumentError,
        );

        final zero = await db.insertProductForCheckout(
          Product(
            name: 'Zero Stock Tracked',
            barcode: 'ZERO-BC-01',
            sellingPrice: 50,
            quantity: 0,
            trackStock: true,
          ),
          scope,
        );
        expect(zero.trackStock, isTrue);
        expect(zero.quantity, 0);

        final wrongScope = CheckoutScope(
          'other-shop',
          scope.owner,
          scope.deviceId,
        );
        await expectLater(
          db.insertProductForCheckout(
            Product(name: 'Wrong Scope', sellingPrice: 20, quantity: 1),
            wrongScope,
          ),
          throwsStateError,
        );
        await expectLater(
          db.insertProductForCheckout(
            Product(
              shopId: 'other-shop',
              name: 'Wrong Product Shop',
              sellingPrice: 20,
              quantity: 1,
            ),
            scope,
          ),
          throwsStateError,
        );
        await expectLater(
          db.productForCheckoutReturn(saved.uuid, wrongScope),
          throwsStateError,
        );

        db.isAdminMutationAllowed = () => false;
        try {
          await expectLater(
            db.insertProductForCheckout(
              Product(name: 'Staff Attempt', sellingPrice: 10, quantity: 1),
              scope,
            ),
            throwsStateError,
          );
          await expectLater(
            db.productForCheckoutReturn(saved.uuid, scope),
            throwsStateError,
          );
        } finally {
          db.isAdminMutationAllowed = null;
        }
      },
    );
  });

  group('ScanScreen catalog entry from checkout', () {
    Future<Product> seedRiceWithDraft(
      WidgetTester tester, {
      String? barcode,
    }) async {
      final result = await tester.runAsync(() async {
        final id = await db.insertProduct(
          Product(
            name: 'Checkout Rice',
            barcode: barcode,
            sellingPrice: 118,
            purchasePrice: 100,
            directPriceToggle: true,
            manualPrice: 118,
            quantity: 10,
          ),
        );
        final original = (await db.getProductById(id))!;
        final item = await db.buildBillItemForProduct(original);
        item.quantity = 2;
        await db.saveCartDraft([item]);
        return original;
      });
      return result!;
    }

    Future<CheckoutCart> loadActiveDraft(WidgetTester tester) async {
      final draft = await tester.runAsync(
        () async => db.loadCheckoutCart(await db.captureCheckoutScope()),
      );
      return draft!;
    }

    Future<void> mountScanScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1000, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ScanScreen(initialMode: BillingEntryMode.manual),
        ),
      );
      await settleIo(tester);
    }

    Future<void> unmountScanScreen(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await settleIo(tester);
    }

    Future<void> saveRawCheckoutEntries(WidgetTester tester) async {
      await tapVisible(tester, find.bySemanticsIdentifier(TestKeys.scanBillBtn));
      await enterField(
        tester,
        find.byKey(const ValueKey('checkout-customer')),
        'Asha Raw',
      );
      await enterField(
        tester,
        find.byKey(const ValueKey('checkout-discount')),
        '10',
      );
      await tapVisible(tester, find.text('Partial'));
      await enterField(
        tester,
        find.byKey(const ValueKey('checkout-partial-amount')),
        '50.001',
      );
      await tapVisible(tester, find.byKey(const ValueKey('checkout-close')));
      expect(find.text('Create Bill'), findsNothing);
    }

    testWidgets(
      'cancel from quick-add preserves existing cart and raw checkout fields',
      (tester) async {
        final original = await seedRiceWithDraft(tester);
        await mountScanScreen(tester);
        await saveRawCheckoutEntries(tester);

        await submitSearchCode(tester, 'MISSING-CANCEL-101');
        expect(find.text('Product not found'), findsOneWidget);
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-create-product')),
        );
        expect(
          fieldText(tester, find.byKey(const ValueKey('quick-add-barcode'))),
          'MISSING-CANCEL-101',
        );

        await tapVisible(tester, find.byKey(const ValueKey('quick-add-cancel')));
        expect(find.byKey(const ValueKey('quick-add-name')), findsNothing);

        final draft = await loadActiveDraft(tester);
        expect(draft.cart.items.single.productUuid, original.uuid);
        expect(draft.cart.items.single.quantity, 2);
        expect(draft.state['raw']['name'], 'Asha Raw');
        expect(draft.state['raw']['discount'], '10');
        expect(draft.state['raw']['partial'], '50.001');
        expect(draft.state['raw']['settlement'], Bill.statusPartial);
        expect(await tester.runAsync(db.getAllProducts), hasLength(1));

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        expect(
          fieldText(tester, find.byKey(const ValueKey('checkout-customer'))),
          'Asha Raw',
        );
        expect(
          fieldText(
            tester,
            find.byKey(const ValueKey('checkout-partial-amount')),
          ),
          '50.001',
        );

        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'save with edited barcode adds exact UUID, preserves quantities/raw fields and resets settlement',
      (tester) async {
        final original = await seedRiceWithDraft(tester);
        await mountScanScreen(tester);
        await saveRawCheckoutEntries(tester);

        await submitSearchCode(tester, 'MISSING-102');
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-create-product')),
        );
        expect(
          fieldText(tester, find.byKey(const ValueKey('quick-add-barcode'))),
          'MISSING-102',
        );

        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-name')),
          'Edited Dal',
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-price')),
          '20',
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-qty')),
          '3',
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-barcode')),
          'EDITED-103',
        );
        await tapVisible(tester, find.byKey(const ValueKey('quick-add-save')));
        expect(find.byKey(const ValueKey('quick-add-name')), findsNothing);

        final products = (await tester.runAsync(db.getAllProducts))!;
        final saved = products.singleWhere((p) => p.barcode == 'EDITED-103');
        expect(saved.quantity, 3);

        final draft = await loadActiveDraft(tester);
        expect(draft.cart.items.map((item) => item.productUuid), [
          original.uuid,
          saved.uuid,
        ]);
        expect(draft.cart.items.map((item) => item.quantity), [2, 1]);
        expect(draft.state['raw']['name'], 'Asha Raw');
        expect(draft.state['raw']['discount'], '10');
        expect(draft.state['raw']['partial'], '50.001');

        await tapVisible(
          tester,
          find.bySemanticsIdentifier(TestKeys.scanBillBtn),
        );
        expect(
          fieldText(tester, find.byKey(const ValueKey('checkout-customer'))),
          'Asha Raw',
        );
        expect(
          fieldText(tester, find.byKey(const ValueKey('checkout-discount'))),
          '10',
        );
        expect(
          find.byKey(const ValueKey('checkout-partial-amount')),
          findsNothing,
        );
        final settlement = tester
            .widgetList<SegmentedButton<String>>(
              find.byType(SegmentedButton<String>),
            )
            .where(
              (widget) => widget.segments.any(
                (segment) => segment.value == Bill.statusPaid,
              ),
            )
            .single;
        expect(settlement.selected, isEmpty);

        await tapVisible(tester, find.text('Partial'));
        expect(
          fieldText(
            tester,
            find.byKey(const ValueKey('checkout-partial-amount')),
          ),
          '50.001',
        );

        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'zero-stock tracked product stays in catalog, is not added to cart and shows snackbar',
      (tester) async {
        final original = await seedRiceWithDraft(tester);
        await mountScanScreen(tester);

        await submitSearchCode(tester, 'ZERO-STOCK-01');
        await tapVisible(
          tester,
          find.byKey(const ValueKey('checkout-create-product')),
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-name')),
          'Zero Stock Sugar',
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-price')),
          '45',
        );
        await enterField(
          tester,
          find.byKey(const ValueKey('quick-add-qty')),
          '0',
        );
        await tapVisible(tester, find.byKey(const ValueKey('quick-add-save')));
        final zeroSnack = find.text(
          'Product saved. Add stock before adding it to this bill.',
        );
        await waitForFinder(tester, zeroSnack);

        expect(find.byKey(const ValueKey('quick-add-name')), findsNothing);
        expect(zeroSnack, findsOneWidget);
        final products = (await tester.runAsync(db.getAllProducts))!;
        final zero = products.singleWhere((p) => p.barcode == 'ZERO-STOCK-01');
        expect(zero.trackStock, isTrue);
        expect(zero.quantity, 0);
        expect(find.text('Zero Stock Sugar'), findsOneWidget);

        final draft = await loadActiveDraft(tester);
        expect(draft.cart.items.single.productUuid, original.uuid);
        expect(draft.cart.items.single.quantity, 2);

        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'partial name match shows suggestion snackbar and does not open create dialog',
      (tester) async {
        await tester.runAsync(() async {
          await db.insertProduct(
            Product(name: 'Basmati Rice', sellingPrice: 120, quantity: 5),
          );
          await db.insertProduct(
            Product(name: 'Brown Rice', sellingPrice: 110, quantity: 5),
          );
        });
        await mountScanScreen(tester);

        await submitSearchCode(tester, 'Rice');
        expect(
          find.text('2 products match "Rice". Choose one from the list.'),
          findsOneWidget,
        );
        expect(find.text('Product not found'), findsNothing);
        expect(
          find.byKey(const ValueKey('checkout-create-product')),
          findsNothing,
        );

        await submitSearchCode(tester, 'Basmati');
        expect(
          find.text('1 products match "Basmati". Choose one from the list.'),
          findsOneWidget,
        );
        expect(find.text('Product not found'), findsNothing);

        await submitSearchCode(tester, '[1, 2, 3]');
        expect(
          find.text('Product not found. Search the catalog for this label.'),
          findsOneWidget,
        );
        expect(find.text('Product not found'), findsNothing);

        await unmountScanScreen(tester);
      },
    );

    testWidgets(
      'staff user cannot open create dialog for unmatched valid barcode',
      (tester) async {
        db.isAdminMutationAllowed = () => false;
        await seedRiceWithDraft(tester);
        await mountScanScreen(tester);

        await submitSearchCode(tester, 'STAFF-MISSING-01');
        expect(
          find.text(
            'No product matches "STAFF-MISSING-01". Only a shop owner or admin can add new products.',
          ),
          findsOneWidget,
        );
        expect(find.text('Product not found'), findsNothing);
        expect(
          find.byKey(const ValueKey('checkout-create-product')),
          findsNothing,
        );

        await unmountScanScreen(tester);
      },
    );

    testWidgets('pending checkout save blocks scan and code entry', (
      tester,
    ) async {
      final original = await seedRiceWithDraft(tester, barcode: 'RICE-01');
      await tester.runAsync(() async {
        final scope = await db.captureCheckoutScope();
        final cart = (await db.loadCheckoutCart(scope))!;
        await db.writeCheckoutState(cart, {
          'version': 1,
          'pending': {'attempt_id': 'pending-attempt'},
        });
      });

      await mountScanScreen(tester);

      await submitSearchCode(tester, 'NEW-BLOCKED-01');
      expect(
        find.text(
          'Recover the pending checkout before changing, holding or discarding its cart.',
        ),
        findsOneWidget,
      );
      expect(find.text('Product not found'), findsNothing);

      await submitSearchCode(tester, 'RICE-01');
      expect(
        find.text(
          'Recover the pending checkout before changing, holding or discarding its cart.',
        ),
        findsOneWidget,
      );
      final after = await loadActiveDraft(tester);
      expect(after.cart.items.single.productUuid, original.uuid);
      expect(after.cart.items.single.quantity, 2);

      await unmountScanScreen(tester);
    });
  });
}
