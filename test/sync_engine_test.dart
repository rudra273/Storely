import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/bill.dart';
import 'package:storely/models/product.dart';
import 'package:storely/models/product_purchase.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';

import 'support/fake_sync_backend.dart';

/// Multi-device sync scenarios. Each "device" is its own SQLite file; the
/// server is [FakeSyncBackend], which applies the same rules as the SQL
/// migration.
void main() {
  final db = DatabaseHelper.instance;
  late FakeSyncBackend server;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> deleteDevices() async {
    await db.close();
    final dir = await getDatabasesPath();
    for (final name in ['a.db', 'b.db', 'storely.db']) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) await deleteDatabase(file.path);
    }
  }

  setUp(() async {
    server = FakeSyncBackend();
    await deleteDevices();
  });

  tearDown(() async {
    await deleteDevices();
    DatabaseHelper.databaseFileName = 'storely.db';
  });

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

  Future<CloudSyncResult> sync({
    bool admin = true,
    FirstSyncMode? mode,
    int pageSize = CloudSyncEngine.defaultPageSize,
  }) => CloudSyncEngine(
    backend: server,
    database: db,
    knownIsAdmin: admin,
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

  /// Device A owns the shop and uploads its data; device B joins as staff.
  Future<void> setUpShop({void Function()? beforeJoin}) async {
    await on('a', () async {
      server.memberShopId = await db.currentShopId();
      await addProduct('Rice');
      expect((await sync()).needsFirstSyncChoice, isTrue);
      await sync(mode: FirstSyncMode.uploadExisting);
    });
    beforeJoin?.call();
    await on('b', () => sync(admin: false));
  }

  test('a joining device receives the shop catalog and stock', () async {
    await on('a', () async {
      server.memberShopId = await db.currentShopId();
      await addProduct('Rice');
      await sell('Rice', qty: 3);
      await sync(mode: FirstSyncMode.uploadExisting);
    });
    await on('b', () async {
      await sync(admin: false);
      expect(await db.currentShopId(), server.memberShopId);
      expect((await productNamed('Rice')).quantity, 7);
      expect(await db.getAllBills(), hasLength(1));
    });
  });

  test(
    'a bill uploaded late by an offline phone still reaches others',
    () async {
      await setUpShop();
      await on('b', () => sell('Rice')); // B offline
      await on('a', () => sync()); // A syncs: nothing yet
      await on('b', () => sync(admin: false)); // B comes online
      await on('a', () async {
        await sync();
        expect(await db.getAllBills(), hasLength(1));
        expect((await productNamed('Rice')).quantity, 9);
      });
    },
  );

  test(
    "a sale on one phone does not revert another phone's product edit",
    () async {
      await setUpShop();
      await on('a', () async {
        final rice = await productNamed('Rice');
        await db.updateProduct(rice.copyWith(name: 'Basmati Rice'));
        await sync();
      });
      await on('b', () async {
        await sell('Rice'); // sold under the old name, before pulling
        await sync(admin: false);
        expect((await db.getAllProducts()).single.name, 'Basmati Rice');
      });
      final serverProduct = server.rows('products').single;
      expect(serverProduct['name'], 'Basmati Rice');
      await on('a', () async {
        await sync();
        final product = (await db.getAllProducts()).single;
        expect(product.name, 'Basmati Rice');
        expect(product.quantity, 9);
      });
    },
  );

  test('a cancelled bill stays cancelled on every device', () async {
    late String billUuid;
    await on('a', () async {
      server.memberShopId = await db.currentShopId();
      await addProduct('Rice');
      await sell('Rice', paid: false);
      billUuid = (await db.getAllBills()).single.uuid;
      await sync(mode: FirstSyncMode.uploadExisting);
    });
    await on('b', () => sync(admin: false));

    await on('a', () async {
      final bill = (await db.getAllBills()).single;
      await db.cancelBill(bill.id!, reason: 'Wrong item'); // not synced yet
    });
    await on('b', () async {
      final bill = (await db.getAllBills()).single;
      await db.recordBillPayment(bill.id!, amount: 10); // B collects
      await sync(admin: false);
    });
    await on('a', () => sync());
    await on('b', () async {
      await sync(admin: false);
      expect(await db.getAllBills(), isEmpty);
      expect((await productNamed('Rice')).quantity, 10);
    });
    await on('a', () async {
      await sync();
      expect(await db.getAllBills(), isEmpty);
      expect((await productNamed('Rice')).quantity, 10);
    });
    expect(server.row('bills', billUuid)!['deleted_at'], isNotNull);
  });

  test('two phones cancelling the same bill restore stock once', () async {
    await on('a', () async {
      server.memberShopId = await db.currentShopId();
      await addProduct('Rice');
      await sell('Rice', qty: 2);
      await sync(mode: FirstSyncMode.uploadExisting);
    });
    await on('b', () => sync()); // second admin device
    for (final device in ['a', 'b']) {
      await on(device, () async {
        final bill = (await db.getAllBills()).single;
        await db.cancelBill(bill.id!, reason: 'Duplicate');
      });
    }
    for (final device in ['a', 'b', 'a']) {
      await on(device, () => sync());
    }
    for (final device in ['a', 'b']) {
      await on(device, () async {
        expect((await productNamed('Rice')).quantity, 10, reason: device);
      });
    }
    final voids = server
        .rows('stock_movements')
        .where((m) => m['movement_type'] == StockMovementType.voidSale);
    expect(voids, hasLength(1));
  });

  test('pulls page through large tables', () async {
    await on('a', () async {
      server.memberShopId = await db.currentShopId();
      for (var i = 0; i < 20; i++) {
        await addProduct('Item $i');
      }
      await sync(mode: FirstSyncMode.uploadExisting);
    });
    await on('b', () async {
      await sync(admin: false, pageSize: 7);
      expect(await db.getAllProducts(), hasLength(20));
    });
  });

  test(
    'one rejected row does not block the others and retries later',
    () async {
      late String badUuid;
      await on('a', () async {
        server.memberShopId = await db.currentShopId();
        await sync(mode: FirstSyncMode.uploadExisting);
        for (final name in ['Tea', 'Sugar', 'Salt']) {
          await addProduct(name);
        }
        badUuid = (await productNamed('Sugar')).uuid;
        server.rejectKeys.add(badUuid);

        final result = await sync();
        expect(result.conflicts.map((c) => c.key), [badUuid]);
        expect(server.rows('products'), hasLength(2));
        expect(await db.cloudDirtyRows('products'), hasLength(1));

        server.rejectKeys.clear();
        final retry = await sync();
        expect(retry.conflicts, isEmpty);
        expect(server.rows('products'), hasLength(3));
      });
    },
  );

  test(
    'a failed role check stops the sync instead of skipping uploads',
    () async {
      await on('a', () async {
        server.memberShopId = await db.currentShopId();
        server.adminCheckError = Exception('network down');
        await expectLater(
          CloudSyncEngine(backend: server, database: db).sync(),
          throwsException,
        );
        expect(
          await db.getCloudSyncState(CloudSyncEngine.lastSyncStateKey),
          isNull,
        );
      });
    },
  );

  test('only changed rows are uploaded on later syncs', () async {
    await setUpShop();
    await on('a', () async {
      await sync();
      final before = server.uploads;
      await sync();
      expect(server.uploads, before);
      await sell('Rice');
      await sync();
      // bill + bill item + stock movement + payment + the shared bill-number
      // counter (made per-device in the next stage); the product is not
      // re-uploaded by a sale.
      expect(server.uploads - before, 5);
    });
  });
}
