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
import 'package:storely/models/expense.dart';
import 'package:storely/models/invoice_numbering.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/models/shop_profile.dart';
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
