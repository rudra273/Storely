// The phone's real CloudSyncEngine against the real Storely API: real users,
// roles, email codes, TLS and database rules. Skipped unless these are set:
//
//   STORELY_LIVE_API   https://api.storely.localhost
//   STORELY_LIVE_CA    path to the development CA certificate (certs/ca.crt)
//   STORELY_LIVE_MAIL  http://127.0.0.1:8025   (Mailpit, to read email codes)
//
// Run it with `make test-mobile` in the storelyapi repo, which also raises the
// API's rate limits for the length of the run.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/bill_totals.dart';
import 'package:storely/models/pricing.dart';
import 'package:storely/models/expense.dart';
import 'package:storely/models/invoice_numbering.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/models/shop_profile.dart';
import 'package:storely/services/gstr1_export.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/api_sync_backend.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';

const _password = 'Correct-Horse-Battery-Staple-42';

class _Account {
  final String email;
  _Account(this.email);
}

void main() {
  final apiUrl = Platform.environment['STORELY_LIVE_API'];
  final caPath = Platform.environment['STORELY_LIVE_CA'];
  final mailUrl = Platform.environment['STORELY_LIVE_MAIL'];
  final configured = apiUrl != null && caPath != null && mailUrl != null;
  final skip = configured
      ? null
      : 'set STORELY_LIVE_API, STORELY_LIVE_CA and STORELY_LIVE_MAIL (make test-mobile)';

  final db = DatabaseHelper.instance;
  final apis = <String, ApiClient>{};
  late SecurityContext trustedContext;
  final plain = http.Client();
  final rng = Random.secure();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    if (configured) {
      trustedContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificates(caPath);
    }
  });

  Future<void> deleteDevices() async {
    await db.close();
    final dir = await getDatabasesPath();
    for (final name in ['a.db', 'b.db', 'c.db', 'storely.db']) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) await deleteDatabase(file.path);
    }
  }

  setUp(() async {
    apis.clear();
    await deleteDevices();
  });

  tearDown(() async {
    await deleteDevices();
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  ApiClient newClient() => ApiClient(
    baseUrl: Uri.parse(apiUrl!),
    httpClient: IOClient(HttpClient(context: trustedContext)),
    tokens: MemoryTokenStore(),
    userAgent: 'StorelyLiveTest',
  );

  Future<String> emailCode(String email) async {
    for (var i = 0; i < 40; i++) {
      final search = await plain.get(
        Uri.parse('$mailUrl/api/v1/search?query=to:$email'),
      );
      final messages = (jsonDecode(search.body)['messages'] as List?) ?? [];
      if (messages.isNotEmpty) {
        final message = await plain.get(
          Uri.parse('$mailUrl/api/v1/message/${messages.first['ID']}'),
        );
        final match = RegExp(
          r'\b(\d{6})\b',
        ).firstMatch(jsonDecode(message.body)['Text'] as String);
        if (match != null) return match.group(1)!;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('no email for $email');
  }

  /// A real account: sign up, read the code from the inbox, verify.
  Future<_Account> newAccount() async {
    final email = 'live-${rng.nextInt(1 << 32).toRadixString(16)}@example.com';
    final api = newClient();
    await api.signUp(email, _password);
    await api.verifyEmail(email, await emailCode(email));
    api.dispose();
    return _Account(email);
  }

  /// Signs [account] in on [device] (each device has its own session).
  Future<ApiClient> signIn(String device, _Account account) async {
    final api = newClient();
    final result = await api.login(
      account.email,
      _password,
      deviceLabel: 'live $device',
    );
    expect(result.needsMfa, isFalse);
    return apis[device] = api;
  }

  /// Runs [body] with device [name]'s database open.
  Future<T> on<T>(String name, Future<T> Function() body) async {
    await db.close();
    DatabaseHelper.databaseFileName = '$name.db';
    try {
      return await body();
    } finally {
      await db.close();
    }
  }

  Future<CloudSyncResult> sync(
    String device, {
    FirstSyncMode? mode,
    int pageSize = CloudSyncEngine.defaultPageSize,
    bool? forceAdmin,
  }) => CloudSyncEngine(
    backend: ApiSyncBackend(apis[device]!),
    database: db,
    knownIsAdmin: forceAdmin, // null = ask the server, like the app does
    pageSize: pageSize,
  ).sync(firstSyncMode: mode);

  Future<int> addProduct(String name, {double qty = 10}) => db.insertProduct(
    Product(name: name, mrp: 0, purchasePrice: 100, quantity: qty),
  );

  Future<Product> productNamed(String name) async =>
      (await db.getAllProducts()).firstWhere((p) => p.name == name);

  Future<int> sell(
    String productName, {
    double qty = 1,
    bool paid = true,
  }) async {
    final item = await db.buildBillItemForProduct(
      await productNamed(productName),
    );
    item.quantity = qty;
    return db.insertBill(
      Bill(
        customerName: 'Walk-in',
        subtotalAmount: item.subtotal,
        totalAmount: item.subtotal,
        itemCount: qty.round(),
        isPaid: paid,
      ),
      [item],
    );
  }

  /// What the app's "Register your shop" button does.
  Future<String> registerShop(String device) async {
    final profile = await db.getShopProfile();
    final shopId = await db.currentShopId();
    await apis[device]!.postJson('/v1/shops', {
      'name': profile?.name ?? 'My Shop',
      'shop_id': shopId,
      'phone': profile?.phone,
      'email': profile?.email,
      'gstin': profile?.gstin,
      'address': profile?.address,
    });
    return shopId;
  }

  /// The owner's phone: signs in, registers its shop, uploads its data.
  Future<String> ownerUploads(String device, _Account owner) async {
    await signIn(device, owner);
    expect((await sync(device)).needsRegistration, isTrue);
    final shopId = await registerShop(device);
    // The app only asks "upload or start fresh?" when there is data to upload.
    if (await db.hasLocalBusinessDataForCloud()) {
      expect((await sync(device)).needsFirstSyncChoice, isTrue);
    }
    final done = await sync(device, mode: FirstSyncMode.uploadExisting);
    expect(done.conflicts, isEmpty);
    expect(done.syncedAt, isNotNull);
    return shopId;
  }

  Future<void> invite(
    String device,
    String shopId,
    _Account who,
    String role,
  ) async {
    await apis[device]!.postJson('/v1/shops/$shopId/invites', {
      'email': who.email,
      'role': role,
    });
  }

  /// A phone joins by invitation: signs in and syncs.
  Future<void> joins(String device, _Account account) async {
    await signIn(device, account);
    final result = await sync(device);
    expect(result.conflicts, isEmpty, reason: device);
    expect(result.syncedAt, isNotNull, reason: '$device should have synced');
  }

  Future<List<Map<String, dynamic>>> serverRows(
    String device,
    String shopId,
    String table,
  ) async {
    final backend = ApiSyncBackend(apis[device]!);
    final rows = <Map<String, dynamic>>[];
    var afterTs = DateTime.utc(1970);
    var afterKey = '';
    final keyColumn = table == 'app_settings' ? 'key' : 'uuid';
    while (true) {
      final page = await backend.pullPage(
        table,
        shopId: shopId,
        afterTs: afterTs,
        afterKey: afterKey,
        limit: 500,
      );
      rows.addAll(page);
      if (page.length < 500) return rows;
      afterTs = DateTime.parse(page.last['server_updated_at'].toString());
      afterKey = page.last[keyColumn].toString();
    }
  }

  test('a joining device receives the catalog and stock', () async {
    final owner = await newAccount();
    final staff = await newAccount();
    late String shopId;
    await on('a', () async {
      await addProduct('Rice');
      await sell('Rice', qty: 3);
      shopId = await ownerUploads('a', owner);
      await invite('a', shopId, staff, 'staff');
    });
    await on('b', () async {
      await joins('b', staff);
      expect(await db.currentShopId(), shopId);
      expect((await productNamed('Rice')).quantity, 7);
      expect(await db.getAllBills(), hasLength(1));
    });
  }, skip: skip);

  test(
    'a bill uploaded late by an offline phone still reaches others',
    () async {
      final owner = await newAccount();
      final staff = await newAccount();
      late String shopId;
      await on('a', () async {
        await addProduct('Rice');
        shopId = await ownerUploads('a', owner);
        await invite('a', shopId, staff, 'staff');
      });
      await on('b', () => joins('b', staff));
      await on('b', () => sell('Rice')); // B offline
      await on('a', () => sync('a')); // A syncs: nothing yet
      await on('b', () => sync('b')); // B comes online
      await on('a', () async {
        await sync('a');
        expect(await db.getAllBills(), hasLength(1));
        expect((await productNamed('Rice')).quantity, 9);
      });
    },
    skip: skip,
  );

  test(
    "a sale on one phone does not revert another phone's product edit",
    () async {
      final owner = await newAccount();
      final staff = await newAccount();
      late String shopId;
      await on('a', () async {
        await addProduct('Rice');
        shopId = await ownerUploads('a', owner);
        await invite('a', shopId, staff, 'staff');
      });
      await on('b', () => joins('b', staff));
      await on('a', () async {
        final rice = await productNamed('Rice');
        await db.updateProduct(rice.copyWith(name: 'Basmati Rice'));
        await sync('a');
      });
      await on('b', () async {
        await sell('Rice'); // sold under the old name, before pulling
        await sync('b');
        expect((await db.getAllProducts()).single.name, 'Basmati Rice');
      });
      expect(
        (await serverRows('a', shopId, 'products')).single['name'],
        'Basmati Rice',
      );
      await on('a', () async {
        await sync('a');
        final product = (await db.getAllProducts()).single;
        expect(product.name, 'Basmati Rice');
        expect(product.quantity, 9);
      });
    },
    skip: skip,
  );

  test(
    'products made and changed on the web reach phones with stock rebuilt from the ledger',
    () async {
      final owner = await newAccount();
      final staff = await newAccount();
      late String shopId;
      await on('a', () async {
        await addProduct('Rice');
        shopId = await ownerUploads('a', owner);
        await invite('a', shopId, staff, 'staff');
      });
      await on('b', () => joins('b', staff));

      // The owner works in the web app (same API, same account, no phone involved).
      final web = await signIn('web', owner);
      final made = await web.postJson('/v1/shops/$shopId/products', {
        'name': 'Web Sugar',
        'product_code': 'WS1',
        'selling_price': '48.50',
        'purchase_price': '40',
        'opening_quantity': '12',
      });
      final sugar = (made['product'] as Map)['uuid'] as String;
      await web.postJson(
        '/v1/shops/$shopId/products/$sugar/stock-adjustments',
        {'delta': '-2.5', 'reason': 'damage'},
      );
      await web.patchJson('/v1/shops/$shopId/products/$sugar', {
        'selling_price': '51',
      });
      final rice = (await serverRows(
        'web',
        shopId,
        'products',
      )).firstWhere((r) => r['name'] == 'Rice')['uuid'];
      await web.deleteJson('/v1/shops/$shopId/products/$rice');

      for (final device in ['a', 'b']) {
        await on(device, () async {
          final result = await sync(device);
          expect(result.conflicts, isEmpty, reason: device);
          final product = await productNamed('Web Sugar');
          expect(product.quantity, 9.5, reason: '$device: 12 in, 2.5 out');
          expect(
            product.sellingPrice,
            51,
            reason: '$device: the web price edit',
          );
          expect(
            (await db.getAllProducts()).any((p) => p.name == 'Rice'),
            isFalse,
            reason: '$device: the web deletion',
          );
        });
      }
    },
    skip: skip,
  );

  test('every web report matches the phone for the same shop data', () async {
    final owner = await newAccount();
    late String shopId;
    final now = DateTime.now();
    DateTime ago(int days, [int hour = 11]) => DateTime(
      now.year,
      now.month,
      now.day,
      hour,
    ).subtract(Duration(days: days));
    String day(DateTime d) => d.toIso8601String().substring(0, 10);

    await on('a', () async {
      await db.saveGlobalPricingSettings(
        const GlobalPricingSettings(
          defaultGstPercent: 5,
          defaultOverheadCost: 0,
          defaultProfitMarginPercent: 50,
          gstRegistered: true,
        ),
      );
      await db.saveShopProfile(
        ShopProfile(
          name: 'Parity Traders',
          gstin: '27ABCDE1234F1Z5',
          gstRegistered: true,
        ),
      );
      await db.insertProduct(
        Product(
          name: 'Rice',
          mrp: 0,
          purchasePrice: 100,
          quantity: 20,
          category: 'Grains',
          unit: 'kg',
          reorderLevel: 8,
        ),
        purchaseDate: ago(40),
      );
      await db.insertProduct(
        Product(
          name: 'Oil',
          mrp: 0,
          purchasePrice: 90,
          quantity: 15,
          category: 'Oils',
          unit: 'l',
          gstPercent: 12,
        ),
        purchaseDate: ago(35),
      );
      await db.insertProduct(
        Product(
          name: 'Soap',
          mrp: 0,
          purchasePrice: 10.5,
          quantity: 3,
          unit: 'pc',
        ),
        purchaseDate: ago(30),
      );
      await db.insertProduct(
        Product(
          name: 'Milk',
          mrp: 0,
          purchasePrice: 22.35,
          quantity: 12,
          unit: 'l',
          purchaseBatchNo: 'M1',
          purchaseExpiry: now.add(const Duration(days: 4)),
        ),
        purchaseDate: ago(5),
      );
      await db.insertProduct(
        Product(
          name: 'Curd',
          mrp: 0,
          purchasePrice: 31.2,
          quantity: 6,
          unit: 'pc',
          purchaseBatchNo: 'C1',
          purchaseExpiry: now.subtract(const Duration(days: 3)),
        ),
        purchaseDate: ago(9),
      );
      final rice = (await db.getAllProducts()).firstWhere(
        (p) => p.name == 'Rice',
      );
      await db.restockProduct(rice, quantityAdded: 7.5, purchaseDate: ago(12));

      Future<Bill> sale(
        String name, {
        double qty = 1,
        int daysAgo = 0,
        bool paid = true,
        double partial = 0,
        double discount = 0,
        bool inter = false,
        String customer = 'Asha',
        String? phone = '9876543210',
        String method = 'cash',
        String? gstin,
      }) async {
        final product = (await db.getAllProducts()).firstWhere(
          (p) => p.name == name,
        );
        final cart = await db.buildBillItemForProduct(product);
        cart.quantity = qty;
        final item = BillTotals.taxedItem(
          cart,
          discountPercent: discount,
          gstRegistered: true,
          interState: inter,
        );
        final t = BillTotals.fromTaxedItems([item], roundOff: true);
        final id = await db.insertBill(
          Bill(
            customerName: customer,
            customerPhone: phone,
            billType: gstin == null ? Bill.typeB2c : Bill.typeB2b,
            customerGstin: gstin,
            placeOfSupplyStateCode: inter ? '29' : null,
            subtotalAmount: t.subtotal,
            discountAmount: t.discountAmount,
            discountPercent: discount,
            taxableAmount: t.taxableAmount,
            cgstAmount: t.cgstAmount,
            sgstAmount: t.sgstAmount,
            igstAmount: t.igstAmount,
            roundOffAmount: t.roundOffAmount,
            totalAmount: t.grandTotal,
            itemCount: 1,
            isPaid: paid,
            paymentMethod: method,
            paidAmount: paid ? t.grandTotal : partial,
            createdAt: ago(daysAgo, 9 + (daysAgo % 8)),
          ),
          [item],
        );
        return (await db.getBillById(id))!;
      }

      final b1 = await sale('Rice', qty: 3, daysAgo: 0);
      await sale('Oil', qty: 2, daysAgo: 0, method: 'upi', discount: 10);
      await sale(
        'Rice',
        qty: 2.5,
        daysAgo: 1,
        paid: false,
        customer: 'Ravi',
        phone: null,
      );
      final b4 = await sale(
        'Oil',
        qty: 1,
        daysAgo: 3,
        inter: true,
        paid: false,
        partial: 40,
        customer: 'Sita',
        phone: '9000000001',
      );
      await sale(
        'Soap',
        qty: 2,
        daysAgo: 8,
        paid: false,
        customer: 'Mohan',
        phone: '9000000002',
      );
      await sale(
        'Rice',
        qty: 1,
        daysAgo: 34,
        paid: false,
        customer: 'Ravi',
        phone: null,
      );
      await sale(
        'Oil',
        qty: 3,
        daysAgo: 70,
        paid: false,
        customer: 'Old Debt',
        phone: null,
      );
      await sale(
        'Oil',
        qty: 4,
        daysAgo: 5,
        inter: true,
        gstin: '29ABCDE1234F1Z9',
        customer: 'Acme Pvt',
      );
      await sale(
        'Rice',
        qty: 6,
        daysAgo: 6,
        gstin: '27ABCDE1234F1Z7',
        customer: 'Local Wholesaler',
      );
      final cancelled = await sale('Soap', qty: 1, daysAgo: 2);
      await db.recordBillPayment(
        b4.id!,
        amount: 25,
        paymentMethod: 'upi',
        receivedAt: ago(1),
      );
      await db.createCreditNote(
        billId: b1.id!,
        quantities: {b1.items.single.uuid: 1},
        settlement: DatabaseBills.creditNoteSettleRefund,
        createdAt: ago(0, 15),
      );
      await db.cancelBill(cancelled.id!, reason: 'wrong customer');
      for (final e in [
        (0, 200.0, 'Tea & snacks', 'cash'),
        (0, 500.0, 'Rent', 'upi'),
        (2, 150.25, 'Transport', 'cash'),
        (33, 80.0, 'Tea & snacks', 'cash'),
      ]) {
        await db.saveExpense(
          Expense(
            date: ago(e.$1),
            amount: e.$2,
            category: e.$3,
            paymentMethod: e.$4,
          ),
        );
      }
      shopId = await ownerUploads('a', owner);
    });

    final web = apis['a']!;
    Future<Map<String, dynamic>> report(
      String path, [
      Map<String, String> q = const {},
    ]) {
      final query = q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
      return web.getJson('/v1/shops/$shopId/reports/$path$query');
    }

    double d(Object? v) => double.parse(v.toString());
    Matcher near(num v) => closeTo(v.toDouble(), 0.005);
    // The phone shows some sums unrounded; the server rounds to the paisa.
    void sameMoney(
      Map<Object?, double> got,
      Map<Object?, double> want,
      String why,
    ) {
      expect(got.keys.toSet(), want.keys.toSet(), reason: why);
      for (final key in want.keys) {
        expect(got[key], closeTo(want[key]!, 0.0051), reason: '$why $key');
      }
    }

    List<Map<String, dynamic>> rows(Object? v) =>
        (v as List).cast<Map<String, dynamic>>();

    await on('a', () async {
      final ranges = [
        (day(ago(60)), day(now)),
        (day(ago(10)), day(now)),
        (day(ago(3)), day(ago(1))),
      ];
      for (final (from, to) in ranges) {
        final k = await report('kpis', {'from': from, 'to': to});
        final label = 'kpis $from..$to';
        expect(
          d(k['revenue']),
          near(await db.kpiTotalRevenue(from: from, to: to)),
          reason: '$label revenue',
        );
        expect(
          d(k['collected']),
          near(await db.kpiCollected(from: from, to: to)),
          reason: '$label collected',
        );
        expect(
          d(k['average_order_value']),
          near(await db.kpiAverageOrderValue(from: from, to: to)),
          reason: '$label aov',
        );
        expect(
          d(k['discount_rate_percent']),
          near(await db.kpiDiscountRate(from: from, to: to)),
          reason: '$label discount',
        );
        expect(
          d(k['gross_profit']),
          near(await db.kpiGrossProfit(from: from, to: to)),
          reason: '$label profit',
        );
        expect(
          d(k['gross_margin_percent']),
          near(await db.kpiGrossMarginPercent(from: from, to: to)),
          reason: '$label margin',
        );
        expect(
          d(k['gst_collected']),
          near(await db.kpiGstCollected(from: from, to: to)),
          reason: '$label gst',
        );
        final unpaid = await db.kpiUnpaidBillsValue();
        expect(
          k['unpaid_count'],
          unpaid['count'],
          reason: '$label unpaid count',
        );
        expect(
          d(k['unpaid_total']),
          near(unpaid['total'] as double),
          reason: '$label unpaid total',
        );
        expect(
          d(k['inventory_value']),
          near(await db.kpiTotalInventoryValue()),
          reason: '$label inventory',
        );
        expect(
          k['out_of_stock_count'],
          await db.kpiOutOfStockCount(),
          reason: '$label out of stock',
        );
        expect(
          k['low_stock_count'],
          (await db.kpiLowStockProducts()).length,
          reason: '$label low stock',
        );
        final expenses = (await db.getExpenses(
          from: from,
          to: to,
        )).fold<double>(0, (s, e) => s + e.amount);
        expect(d(k['expenses']), near(expenses), reason: '$label expenses');
        final daily = await db.kpiDailyRevenueTrend(from: from, to: to);
        expect(
          rows(k['daily']).map((r) => r['day']).toList(),
          daily.map((r) => r['day']).toList(),
          reason: '$label days',
        );
        for (var i = 0; i < daily.length; i++) {
          expect(
            d(rows(k['daily'])[i]['revenue']),
            near(daily[i]['revenue'] as num),
            reason: '$label day ${daily[i]['day']}',
          );
        }
        final methods = await db.kpiRevenueByPaymentMethod(from: from, to: to);
        sameMoney(
          {
            for (final r in rows(k['by_payment_method']))
              r['method']: d(r['total']),
          },
          {
            for (final r in methods)
              r['method']: (r['total'] as num).toDouble(),
          },
          '$label methods',
        );
        final cats = await db.kpiRevenueByCategory(from: from, to: to);
        sameMoney(
          {
            for (final r in rows(k['by_category']))
              r['category']: d(r['revenue']),
          },
          {
            for (final r in cats)
              r['category']: (r['revenue'] as num).toDouble(),
          },
          '$label categories',
        );
        final top = await db.kpiTop10ProductsByRevenue(from: from, to: to);
        expect(
          rows(
            k['top_by_revenue'],
          ).map((r) => [r['name'], d(r['revenue']), d(r['units'])]).toList(),
          top
              .map(
                (r) => [
                  r['name'],
                  (r['revenue'] as num).toDouble(),
                  (r['units'] as num).toDouble(),
                ],
              )
              .toList(),
          reason: '$label top by revenue',
        );

        final pl = await db.profitAndLoss(from: from, to: to);
        final spl = await report('profit-loss', {'from': from, 'to': to});
        expect(d(spl['sales']), near(pl.sales), reason: '$label P&L sales');
        expect(
          d(spl['cost_of_goods']),
          near(pl.costOfGoods),
          reason: '$label P&L cost',
        );
        expect(
          d(spl['gross_profit']),
          near(pl.grossProfit),
          reason: '$label P&L gross',
        );
        expect(
          d(spl['gst_collected']),
          near(pl.gstCollected),
          reason: '$label P&L gst',
        );
        expect(
          d(spl['expenses']),
          near(pl.expenses),
          reason: '$label P&L expenses',
        );
        expect(
          d(spl['net_profit']),
          near(pl.netProfit),
          reason: '$label P&L net',
        );
        expect(
          {
            for (final r in rows(spl['expenses_by_category']))
              r['category']: d(r['amount']),
          },
          pl.expensesByCategory,
          reason: '$label P&L categories',
        );

        final tax = await db.taxSummary(from: from, to: to);
        final st = await report('tax-summary', {'from': from, 'to': to});
        expect(
          rows(st['rates']).length,
          tax.length,
          reason: '$label tax rate count',
        );
        for (var i = 0; i < tax.length; i++) {
          final r = rows(st['rates'])[i];
          expect(d(r['rate']), near(tax[i].rate), reason: '$label tax rate');
          expect(
            d(r['taxable']),
            near(tax[i].taxable),
            reason: '$label taxable @${tax[i].rate}',
          );
          expect(
            d(r['cgst']),
            near(tax[i].cgst),
            reason: '$label cgst @${tax[i].rate}',
          );
          expect(
            d(r['sgst']),
            near(tax[i].sgst),
            reason: '$label sgst @${tax[i].rate}',
          );
          expect(
            d(r['igst']),
            near(tax[i].igst),
            reason: '$label igst @${tax[i].rate}',
          );
        }

        final reg = await db.purchaseRegister(from: from, to: to);
        final sr = await report('purchase-register', {'from': from, 'to': to});
        expect(rows(sr['rows']).length, reg.length, reason: '$label purchases');
        for (var i = 0; i < reg.length; i++) {
          final r = rows(sr['rows'])[i];
          expect(
            r['product_name'],
            reg[i].productName,
            reason: '$label purchase $i',
          );
          expect(
            d(r['quantity']),
            near(reg[i].quantity),
            reason: '$label purchase qty $i',
          );
          expect(
            d(r['amount']),
            near(reg[i].amount),
            reason: '$label purchase amount $i',
          );
        }
      }

      for (final offset in [0, 1, 3]) {
        final dayText = day(ago(offset));
        final book = await db.dayBook(dayText);
        final s = await report('day-book', {'day': dayText});
        expect(
          rows(s['bills']).map((b) => b['bill_number']).toList(),
          book.bills.map((b) => b['bill_number']).toList(),
          reason: 'day book $dayText bills',
        );
        expect(
          d(s['sales']),
          near(book.sales),
          reason: 'day book $dayText sales',
        );
        expect(
          d(s['collected']),
          near(book.collected),
          reason: 'day book $dayText collected',
        );
        expect(
          d(s['cash_received']),
          near(book.cashReceived),
          reason: 'day book $dayText cash',
        );
        expect(
          d(s['total_expenses']),
          near(book.totalExpenses),
          reason: 'day book $dayText expenses',
        );
        expect(
          d(s['net_cash']),
          near(book.netCash),
          reason: 'day book $dayText net cash',
        );
      }

      final age = await db.receivablesAgeing();
      final sa = await report('receivables-ageing');
      final names = rows(
        sa['customers'],
      ).map((c) => c['customer_name']).toList();
      expect(
        names,
        age.map((c) => c.customerName).toList(),
        reason: 'ageing customers',
      );
      for (var i = 0; i < age.length; i++) {
        final buckets = (rows(sa['customers'])[i]['buckets'] as List)
            .map(d)
            .toList();
        for (var b = 0; b < 4; b++) {
          expect(
            buckets[b],
            near(age[i].buckets[b]),
            reason: 'ageing ${age[i].customerName} bucket $b',
          );
        }
      }

      for (final days in [10, 30]) {
        final exp = await db.expiringStock(days: days);
        final se = await report('expiring-stock', {'days': '$days'});
        expect(
          rows(se['batches'])
              .map((b) => [b['product_name'], b['batch_no'], d(b['quantity'])])
              .toList(),
          exp.map((b) => [b.productName, b.batchNo, b.quantity]).toList(),
          reason: 'expiring within $days days',
        );
      }

      final first = day(ago(60));
      final last = day(now);
      final shopProfile = (await db.getShopProfile())!;
      final phoneBills = await db.getBillsBetween(
        first,
        last,
        includeCancelled: true,
      );
      final phoneBook = Gstr1Export(shop: shopProfile, bills: phoneBills);
      final webBook = await report('gstr1', {'from': first, 'to': last});
      final phoneTotals = phoneBook.totals();
      final webTotals = webBook['totals'] as Map;
      expect(
        d(webTotals['taxable']),
        near(phoneTotals.taxable),
        reason: 'gstr1 taxable',
      );
      expect(
        d(webTotals['igst']),
        near(phoneTotals.igst),
        reason: 'gstr1 igst',
      );
      expect(
        d(webTotals['cgst']),
        near(phoneTotals.cgst),
        reason: 'gstr1 cgst',
      );
      expect(
        d(webTotals['sgst']),
        near(phoneTotals.sgst),
        reason: 'gstr1 sgst',
      );
      final webSheets = webBook['sheets'] as Map<String, dynamic>;
      final phoneSheets = phoneBook.sheets();
      expect(
        webSheets.keys.toList(),
        phoneSheets.keys.toList(),
        reason: 'gstr1 sheets',
      );
      for (final name in phoneSheets.keys) {
        final want = phoneSheets[name]!;
        final got = (webSheets[name] as List).cast<List<dynamic>>();
        expect(got.length, want.length, reason: 'gstr1 $name row count');
        for (var r = 0; r < want.length; r++) {
          expect(
            got[r].length,
            want[r].length,
            reason: 'gstr1 $name row $r width',
          );
          for (var c = 0; c < want[r].length; c++) {
            final a = got[r][c];
            final b = want[r][c];
            if (b is num) {
              expect(a, isA<num>(), reason: 'gstr1 $name[$r][$c]');
              expect(a as num, near(b), reason: 'gstr1 $name[$r][$c]');
            } else {
              expect(a, b, reason: 'gstr1 $name[$r][$c]');
            }
          }
        }
      }
      expect(
        (webSheets['b2b'] as List).length,
        greaterThan(1),
        reason: 'the data really has B2B rows',
      );
      expect((webSheets['hsn(b2b)'] as List).length, greaterThan(1));

      final val = await db.stockValuation();
      final sv = await report('stock-valuation');
      expect(
        rows(sv['items']).map((i) => i['name']).toList(),
        val.map((v) => v.name).toList(),
        reason: 'valuation order',
      );
      for (var i = 0; i < val.length; i++) {
        expect(
          d(rows(sv['items'])[i]['cost_value']),
          near(val[i].costValue),
          reason: 'valuation cost ${val[i].name}',
        );
        expect(
          d(rows(sv['items'])[i]['sale_value']),
          near(val[i].saleValue),
          reason: 'valuation sale ${val[i].name}',
        );
      }
    });
  }, skip: skip);

  test('a cancelled bill stays cancelled on every device', () async {
    final owner = await newAccount();
    final staff = await newAccount();
    late String shopId;
    late String billUuid;
    await on('a', () async {
      await addProduct('Rice');
      await sell('Rice', paid: false);
      billUuid = (await db.getAllBills()).single.uuid;
      shopId = await ownerUploads('a', owner);
      await invite('a', shopId, staff, 'staff');
    });
    await on('b', () => joins('b', staff));
    await on('a', () async {
      final bill = (await db.getAllBills()).single;
      await db.cancelBill(bill.id!, reason: 'Wrong item'); // not synced yet
    });
    await on('b', () async {
      final bill = (await db.getAllBills()).single;
      await db.recordBillPayment(bill.id!, amount: 10); // B collects meanwhile
      await sync('b');
    });
    await on('a', () => sync('a'));
    await on('b', () async {
      await sync('b');
      expect(await db.getAllBills(), isEmpty);
      expect((await productNamed('Rice')).quantity, 10);
    });
    await on('a', () async {
      await sync('a');
      expect(await db.getAllBills(), isEmpty);
      expect((await productNamed('Rice')).quantity, 10);
    });
    final stored = (await serverRows(
      'a',
      shopId,
      'bills',
    )).firstWhere((b) => b['uuid'] == billUuid);
    expect(stored['deleted_at'], isNotNull);
    expect(stored['lifecycle_status'], 'cancelled');
  }, skip: skip);

  test(
    'two admin phones cancelling the same bill restore stock once',
    () async {
      final owner = await newAccount();
      final admin = await newAccount();
      late String shopId;
      await on('a', () async {
        await addProduct('Rice');
        await sell('Rice', qty: 2);
        shopId = await ownerUploads('a', owner);
        await invite('a', shopId, admin, 'admin');
      });
      await on('c', () => joins('c', admin));
      for (final device in ['a', 'c']) {
        await on(device, () async {
          final bill = (await db.getAllBills()).single;
          await db.cancelBill(bill.id!, reason: 'Duplicate');
        });
      }
      for (final device in ['a', 'c', 'a']) {
        await on(device, () => sync(device));
      }
      for (final device in ['a', 'c']) {
        await on(device, () async {
          expect((await productNamed('Rice')).quantity, 10, reason: device);
        });
      }
      final voids = (await serverRows(
        'a',
        shopId,
        'stock_movements',
      )).where((m) => m['movement_type'] == StockMovementType.voidSale);
      expect(voids, hasLength(1));
    },
    skip: skip,
  );

  test('two phones billing offline get distinct bill numbers', () async {
    final owner = await newAccount();
    final staff = await newAccount();
    await on('a', () async {
      await addProduct('Rice');
      final shopId = await ownerUploads('a', owner);
      await invite('a', shopId, staff, 'staff');
    });
    await on('b', () => joins('b', staff));
    await on('a', () => sell('Rice'));
    await on('b', () => sell('Rice'));
    for (final device in ['a', 'b', 'a']) {
      await on(device, () async {
        final result = await sync(device);
        expect(result.conflicts, isEmpty, reason: device);
      });
    }
    await on('a', () async {
      final numbers = (await db.getAllBills()).map((b) => b.billNumber).toSet();
      final fy = InvoiceNumbering.financialYear(DateTime.now());
      expect(numbers, {'INV/$fy/0001', 'INV/$fy/B0001'});
      expect((await productNamed('Rice')).quantity, 8);
    });
  }, skip: skip);

  test('a second admin phone joining does not overwrite the shop', () async {
    final owner = await newAccount();
    final admin = await newAccount();
    late String shopId;
    await on('a', () async {
      await db.saveShopProfile(
        ShopProfile(
          name: 'Sharma Kirana',
          gstin: '27AAAAA0000A1Z5',
          gstScheme: GstScheme.regular,
        ),
      );
      await addProduct('Rice');
      shopId = await ownerUploads('a', owner);
      await invite('a', shopId, admin, 'admin');
    });
    final unitsBefore = (await serverRows('a', shopId, 'units')).length;

    await on('c', () async {
      await joins('c', admin);
      final profile = await db.getShopProfile();
      expect(profile!.name, 'Sharma Kirana');
      expect(profile.gstScheme, GstScheme.regular);
      await sell('Rice');
      expect((await sync('c')).conflicts, isEmpty);
    });

    final shop = (await serverRows('a', shopId, 'shops')).single;
    expect(shop['name'], 'Sharma Kirana');
    expect(shop['gstin'], '27AAAAA0000A1Z5');
    expect(await serverRows('a', shopId, 'units'), hasLength(unitsBefore));
    expect(await serverRows('a', shopId, 'invoice_series'), hasLength(1));
    final fy = InvoiceNumbering.financialYear(DateTime.now());
    expect(
      (await serverRows('a', shopId, 'bills')).single['bill_number'],
      'INV/$fy/B0001',
    );
  }, skip: skip);

  test('pulls page through large tables', () async {
    final owner = await newAccount();
    final staff = await newAccount();
    await on('a', () async {
      for (var i = 0; i < 20; i++) {
        await addProduct('Item $i');
      }
      final shopId = await ownerUploads('a', owner);
      await invite('a', shopId, staff, 'staff');
    });
    await on('b', () async {
      await signIn('b', staff);
      await sync('b', pageSize: 7);
      expect(await db.getAllProducts(), hasLength(20));
    });
  }, skip: skip);

  test('expenses sync to other phones, deletions too', () async {
    final owner = await newAccount();
    final staff = await newAccount();
    await on('a', () async {
      final shopId = await ownerUploads('a', owner);
      await invite('a', shopId, staff, 'staff');
    });
    await on('b', () => joins('b', staff));
    await on('a', () async {
      await db.saveExpense(
        Expense(date: DateTime(2026, 10, 23), amount: 1500, category: 'Rent'),
      );
      await sync('a');
    });
    await on('b', () async {
      await sync('b');
      final expenses = await db.getExpenses();
      expect(expenses.single.amount, 1500);
      expect(expenses.single.category, 'Rent');
    });
    await on('a', () async {
      await db.deleteExpense((await db.getExpenses()).single.id!);
      await sync('a');
    });
    await on('b', () async {
      await sync('b');
      expect(await db.getExpenses(), isEmpty);
    });
  }, skip: skip);

  test(
    'a staff phone that tries to edit the catalog gets a conflict, and its sale still syncs',
    () async {
      final owner = await newAccount();
      final staff = await newAccount();
      late String shopId;
      await on('a', () async {
        await addProduct('Rice');
        shopId = await ownerUploads('a', owner);
        await invite('a', shopId, staff, 'staff');
      });
      await on('b', () => joins('b', staff));
      await on('b', () async {
        await addProduct('Sugar'); // staff may not create catalog items
        await sell('Rice');
        // Pretend the phone thinks it is an admin (e.g. a stale local role).
        final result = await sync('b', forceAdmin: true);
        final sugar = await productNamed('Sugar');
        // The new product, and its opening stock movement (staff may only record
        // sales), are both refused, each with the reason.
        expect(result.conflicts.map((c) => c.table).toSet(), {
          'products',
          'stock_movements',
        });
        expect(result.conflicts.any((c) => c.key == sugar.uuid), isTrue);
        expect(
          result.conflicts.every(
            (c) => c.message.toLowerCase().contains('role'),
          ),
          isTrue,
        );
        expect(
          await db.cloudDirtyRows('bills'),
          isEmpty,
        ); // the sale got through
      });
      expect(await serverRows('a', shopId, 'bills'), hasLength(1));
      expect(
        (await serverRows('a', shopId, 'products')).map((r) => r['name']),
        ['Rice'],
      );
    },
    skip: skip,
  );

  test(
    'after a sync nothing is left waiting, and a second sync changes nothing',
    () async {
      final owner = await newAccount();
      final staff = await newAccount();
      await on('a', () async {
        await addProduct('Rice');
        final shopId = await ownerUploads('a', owner);
        await invite('a', shopId, staff, 'staff');
      });
      await on('b', () => joins('b', staff));
      await on('b', () async {
        await sell('Rice');
        expect(await db.pendingSyncCounts(), isNotEmpty);
        await sync('b');
        expect(await db.pendingSyncCounts(), isEmpty);
        final again = await sync('b');
        expect(again.conflicts, isEmpty);
        expect(await db.pendingSyncCounts(), isEmpty);
      });
    },
    skip: skip,
  );

  test(
    'someone outside the shop cannot read it, and the engine says so',
    () async {
      final owner = await newAccount();
      final stranger = await newAccount();
      late String shopId;
      await on('a', () async {
        shopId = await ownerUploads('a', owner);
      });
      await signIn('c', stranger);
      await expectLater(
        ApiSyncBackend(apis['c']!).pullPage(
          'products',
          shopId: shopId,
          afterTs: DateTime.utc(1970),
          afterKey: '',
          limit: 10,
        ),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
      expect(await ApiSyncBackend(apis['c']!).isShopAdmin(shopId), isFalse);
    },
    skip: skip,
  );

  test('the app does not trust a server it cannot verify', () async {
    // Same URL, but with the system trust store only (no development CA).
    final untrusting = ApiClient(
      baseUrl: Uri.parse(apiUrl!),
      httpClient: IOClient(
        HttpClient(context: SecurityContext(withTrustedRoots: false)),
      ),
      tokens: MemoryTokenStore(),
    );
    await expectLater(
      untrusting.login('a@b.com', 'pw'),
      throwsA(isA<HandshakeException>()),
    );
    expect(
      () => ApiClient(
        baseUrl: Uri.parse(apiUrl.replaceFirst('https://', 'http://')),
        httpClient: IOClient(HttpClient(context: trustedContext)),
        tokens: MemoryTokenStore(),
      ),
      throwsArgumentError,
    );
  }, skip: skip);
}
