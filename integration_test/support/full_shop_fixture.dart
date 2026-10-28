import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storely/config/cloud_defaults.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_settings.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/expense.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/supplier.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/http_client_factory.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/app_settings_service.dart';
import 'package:storely/services/cloud_service.dart';
import 'package:storely/services/home_section_prefs.dart';
import 'package:storely/services/kpi_prefs.dart';
import 'package:storely/services/portable_preference_keys.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'package:storely/services/sync_status.dart';

const pixelPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aVCsAAAAASUVORK5CYII=';

Future<void> populateFullShop() async {
  final db = DatabaseHelper.instance;
  final profile = (await db.getShopProfile())!;
  await db.saveShopProfile(
    ShopProfile(
      name: profile.name,
      phone: profile.phone,
      address: profile.address,
      email: 'owner@example.com',
      gstin: '29ABCDE1234F1Z5',
      gstScheme: GstScheme.regular,
      createdAt: profile.createdAt,
    ),
  );
  await db.saveBillSettings(
    BillSettings(
      footerText: 'Parity fixture footer',
      shopLogoBase64: pixelPng,
      showDigitalSignature: true,
      digitalSignatureBase64: pixelPng,
      paperSize: 'a5',
      upiId: 'fixture@bank',
      bankDetails: 'Fixture account',
      termsText: 'Fixture terms',
      roundOffTotal: false,
    ),
  );
  await db.saveSupplierProfile(
    SupplierProfile(
      name: 'Fixture Supplier',
      phone: '+919111111111',
      email: 'supplier@example.com',
      address: 'Supplier address',
      notes: 'Supplier note',
    ),
  );
  final productId = await db.insertProduct(
    Product(
      name: 'Parity Rice',
      productCode: 'PARITY-RICE',
      barcode: '8901234567890',
      hsnCode: '1006',
      hsnType: 'hsn',
      category: 'Grains',
      supplier: 'Fixture Supplier',
      unit: 'kg',
      gstPercent: 5,
      purchasePrice: 80.25,
      sellingPrice: 105.75,
      directPriceToggle: true,
      manualPrice: 105.75,
      printedMrp: 120,
      quantity: 25.5,
      purchaseBatchNo: 'BATCH-PARITY',
      purchaseExpiry: DateTime(2027, 3, 31),
      reorderLevel: 2.25,
    ),
  );
  Future<int> sale(String name, double quantity, {double paid = 0}) async {
    final item = await db.buildBillItemForProduct(
      (await db.getProductById(productId))!,
    );
    item.quantity = quantity;
    final taxed = BillTotals.taxedItem(
      item,
      discountPercent: 3.5,
      gstRegistered: true,
      interState: false,
    );
    final totals = BillTotals.fromTaxedItems([taxed], roundOff: false);
    return db.insertBill(
      Bill(
        customerName: name,
        customerPhone: '+919222222222',
        subtotalAmount: totals.subtotal,
        discountPercent: 3.5,
        discountAmount: totals.discountAmount,
        taxableAmount: totals.taxableAmount,
        cgstAmount: totals.cgstAmount,
        sgstAmount: totals.sgstAmount,
        totalAmount: totals.grandTotal,
        itemCount: 1,
        paidAmount: paid,
        isPaid: paid >= totals.grandTotal,
        paymentMethod: 'upi',
      ),
      [taxed],
    );
  }

  final billId = await sale('Parity Customer', 2, paid: 25.25);
  await db.recordBillPayment(
    billId,
    amount: 10.10,
    paymentMethod: 'bank',
    paymentReference: 'PARITY-PAYMENT',
    notes: 'Part payment',
  );
  final bill = (await db.getBillById(billId))!;
  await db.createCreditNote(
    billId: billId,
    quantities: {bill.items.first.uuid: 0.5},
    settlement: 'refund',
    refundMethod: 'cash',
    reason: 'Fixture return',
  );
  final cancelled = await sale('Cancelled customer', 1);
  await db.cancelBill(cancelled, reason: 'Fixture cancellation');
  await db.saveExpense(
    Expense(
      date: DateTime.now(),
      amount: 321.45,
      category: 'Rent',
      paymentMethod: 'bank',
      notes: 'Parity rent',
    ),
  );
  final heldItem = await db.buildBillItemForProduct(
    (await db.getProductById(productId))!,
  );
  heldItem.quantity = 1.25;
  await db.holdBill('Parity held cart', [heldItem]);
  await db.saveCartDraft([heldItem]);
  await AppSettingsService.instance.setThemePreference(AppThemePreference.dark);
  await AppSettingsService.instance.setLanguage(AppLanguage.hindi);
  await AppSettingsService.instance.setBillingSearchFirst(true);
  await HomeSectionPrefs.instance.setUnpaidCount(7);
  await HomeSectionPrefs.instance.setUnpaidSort(UnpaidBillsSort.highest);
  await HomeSectionPrefs.instance.setUnpaidHidden(true);
  await HomeSectionPrefs.instance.setAttentionCount(9);
  await HomeSectionPrefs.instance.setAttentionHidden(true);
  await KpiPrefs.instance.setEnabled(
    kpiCatalogue.first.id,
    !kpiCatalogue.first.defaultOn,
  );
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('app_lock_enabled', true);
  await prefs.setString('printer_mac', 'AA:BB:CC:DD:EE:FF');
}

Future<Map<String, List<Map<String, dynamic>>>> snapshotBusiness() async {
  final helper = DatabaseHelper.instance;
  final snapshot = <String, List<Map<String, dynamic>>>{};
  const derived = <String, Set<String>>{
    'products': {'quantity_cache'},
    'customers': {'total_purchase_amount', 'bill_count', 'last_purchase_at'},
    'bills': {
      'paid_amount',
      'balance_due',
      'payment_status',
      'is_paid',
      'payment_method',
    },
    'invoice_series': {'next_sequence', 'last_sequence_key'},
  };
  for (final table in CloudSyncEngine.syncedTables) {
    final rows = await helper.cloudExportRows(table);
    for (final row in rows) {
      for (final field in derived[table] ?? <String>{}) {
        row.remove(field);
      }
      if (table == 'held_bills') {
        row['items_json'] = jsonDecode(row['items_json'] as String);
      }
    }
    rows.sort(
      (a, b) => (a['uuid'] ?? a['key']).toString().compareTo(
        (b['uuid'] ?? b['key']).toString(),
      ),
    );
    snapshot[table] = rows;
  }
  return snapshot;
}

class _WebHeaders extends http.BaseClient {
  _WebHeaders(this.inner, this.key);
  final http.Client inner;
  final String key;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Idempotency-Key'] = key;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

/// Same emulator, clean SQLite database and distinct device identity: no copy of
/// the source database, sync cursors, printer pairing, app lock or credentials.
Future<void> verifyCleanRestore(
  String runId,
  String email,
  String password,
) async {
  final helper = DatabaseHelper.instance;
  final service = CloudService.instance;
  final sourceFile = DatabaseHelper.databaseFileName;
  final before = await snapshotBusiness();
  for (final table in CloudSyncEngine.syncedTables) {
    expect(
      before[table],
      isNotEmpty,
      reason: 'The restore fixture must populate $table.',
    );
  }
  final sourceCustomers = await helper.getAllCustomers();
  final sourceProducts = await helper.getAllProducts();
  final sourceDevice = await helper.localDeviceId();
  final sourceShop = await helper.currentShopId();
  final sourceStock = sourceProducts
      .firstWhere((p) => p.name == 'Parity Rice')
      .quantity;
  final prefs = await SharedPreferences.getInstance();
  for (final key in portablePreferenceKeys) {
    await prefs.remove(key);
  }
  await prefs.setBool('app_lock_enabled', false);
  await prefs.remove('printer_mac');
  await SyncStatus.instance.refresh();
  await helper.close();
  DatabaseHelper.databaseFileName = 'premium_restore_$runId.db';
  try {
    final clean = await helper.database;
    // Force different integer identities to prove UUID relationships are rebuilt.
    await clean.rawInsert(
      "INSERT INTO sqlite_sequence(name,seq) VALUES('products',500)",
    );
    service.state.value = service.state.value.copyWith(clearLastSyncedAt: true);
    await service.syncNow(reason: 'Clean restore fixture');
    expect(service.state.value.error, isNull);
    expect(await helper.getSyncConflicts(), isEmpty);
    expect(await helper.currentShopId(), sourceShop);
    expect(await helper.localDeviceId(), isNot(sourceDevice));
    final restored = await snapshotBusiness();
    for (final table in CloudSyncEngine.syncedTables) {
      expect(
        restored[table],
        before[table],
        reason:
            'Every stored field/relationship in $table must survive restore.',
      );
    }
    final restoredCustomers = await helper.getAllCustomers();
    for (final customer in sourceCustomers) {
      final restoredCustomer = restoredCustomers.singleWhere(
        (c) => c.uuid == customer.uuid,
      );
      expect(restoredCustomer.billCount, customer.billCount);
      expect(
        restoredCustomer.totalPurchaseAmount,
        closeTo(customer.totalPurchaseAmount, 0.000001),
      );
      expect(restoredCustomer.lastPurchaseAt, customer.lastPurchaseAt);
    }
    final restoredProducts = await helper.getAllProducts();
    final product = restoredProducts.firstWhere((p) => p.name == 'Parity Rice');
    expect(product.id, greaterThan(500));
    expect(product.quantity, closeTo(sourceStock, 0.000001));
    final local = await helper.database;
    for (final movement in await local.query(
      'stock_movements',
      where: "source_document_type = 'bill'",
    )) {
      final billRows = await local.query(
        'bills',
        where: 'uuid = ?',
        whereArgs: [movement['source_document_uuid']],
      );
      expect(billRows, isNotEmpty);
      expect(movement['source_document_id'], billRows.single['id']);
    }
    for (final bill in await helper.getAllBills()) {
      for (final item in bill.items) {
        if (item.productUuid != null) {
          final matches = restoredProducts
              .where((p) => p.uuid == item.productUuid)
              .toList();
          expect(matches, isNotEmpty);
          expect(item.productId, matches.single.id);
        }
      }
    }
    final backups = await helper.getHeldBills();
    expect(backups.length, 2); // the held cart AND the source device draft
    expect(backups.every((c) => c.readOnly), isTrue);
    expect(backups.first.items.first.productId, product.id);
    expect(
      await helper.loadCartDraft(),
      isEmpty,
    ); // no automatic second checkout
    await expectLater(
      helper.takeHeldBill(backups.first.id),
      throwsA(isA<StateError>()),
    );
    expect(prefs.getString('app_language'), 'hi');
    expect(prefs.getString('app_theme_preference'), 'dark');
    expect(prefs.getInt('home_unpaid_count'), 7);
    expect(prefs.getBool('app_lock_enabled'), false);
    expect(prefs.getString('printer_mac'), isNull);
    // Recomputed financial summaries still reconcile from durable payments.
    final bills = await helper.getAllBills();
    for (final bill in bills) {
      expect(
        bill.paidAmount + bill.balanceDue,
        closeTo(bill.totalAmount, 0.005),
      );
    }
    final line = await helper.buildBillItemForProduct(product);
    final newBill = await helper.insertBill(
      Bill(
        customerName: 'Second device',
        subtotalAmount: line.subtotal,
        totalAmount: line.subtotal,
        itemCount: 1,
      ),
      [line],
    );
    final made = (await helper.getBillById(newBill))!;
    final oldNumbers = before['bills']!.map((r) => r['bill_number']).toSet();
    expect(oldNumbers.contains(made.billNumber), isFalse);
    await service.syncNow(reason: 'Second device bill');
    expect(service.state.value.error, isNull);
    expect(await helper.getSyncConflicts(), isEmpty);
    // The same domain REST endpoints used by web read mobile data and write rows
    // that are pulled by the phone. A separate session models another client.
    final web = ApiClient(
      baseUrl: Uri.parse(CloudDefaults.apiUrl),
      httpClient: _WebHeaders(createApiHttpClient(), 'web-parity-$runId'),
      tokens: MemoryTokenStore(),
    );
    try {
      await web.login(email, password, deviceLabel: 'Restore web fixture');
      final list = await web.getJson('/v1/shops/$sourceShop/products');
      expect(
        (list['items'] as List).any((p) => p['uuid'] == product.uuid),
        isTrue,
      );
      await web.patchJson('/v1/shops/$sourceShop/products/${product.uuid}', {
        'name': 'Parity Rice Web',
      });
      final webBill = await web.postJson('/v1/shops/$sourceShop/bills', {
        'items': [
          {'product_uuid': product.uuid, 'quantity': '0.25'},
        ],
        'customer_name': 'Web fixture',
        'payment': {'amount': '0', 'method': 'cash'},
      });
      expect(webBill, isNotEmpty);
      await service.syncNow(reason: 'Pull web changes');
      expect(
        (await helper.getAllProducts()).any((p) => p.name == 'Parity Rice Web'),
        isTrue,
      );
      expect(
        (await helper.getAllBills()).any(
          (b) => b.customerName == 'Web fixture',
        ),
        isTrue,
      );
    } finally {
      web.dispose();
    }
  } finally {
    await SyncStatus.instance.refresh();
    await helper.close();
    DatabaseHelper.databaseFileName = sourceFile;
  }
  await service.syncNow(
    reason: 'Original device sees restored-device/web changes',
  );
  expect(service.state.value.error, isNull);
  expect(
    (await helper.getAllProducts()).any((p) => p.name == 'Parity Rice Web'),
    isTrue,
  );
}
