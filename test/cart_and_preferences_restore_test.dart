import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/models/product.dart';
import 'package:storely/services/app_settings_service.dart';
import 'package:storely/services/portable_preference_keys.dart';
import 'package:storely/services/portable_preferences_service.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';

import 'support/fake_sync_backend.dart';

const userId = '11111111-1111-4111-8111-111111111111';

class LostCartResponse extends FakeSyncBackend {
  bool dropped = false;
  @override
  Future<void> upsert(String table, List<Map<String, dynamic>> rows) async {
    await super.upsert(table, rows);
    if (table == 'held_bills' && !dropped) {
      dropped = true;
      throw StateError(
        'The server accepted the cart but the connection dropped.',
      );
    }
  }
}

void main() {
  final db = DatabaseHelper.instance;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  Future<void> use(String name) async {
    await db.close();
    DatabaseHelper.databaseFileName = 'restore-$name.db';
  }

  setUp(() async {
    PortablePreferenceChanges.onChanged = null;
    SharedPreferences.setMockInitialValues({});
    for (final name in ['a', 'b', 'old']) {
      await use(name);
      await deleteDatabase(await DatabaseHelper.databasePath());
    }
    await use('a');
  });
  tearDown(() async {
    PortablePreferenceChanges.onChanged = null;
    for (final name in ['a', 'b', 'old']) {
      await use(name);
      await deleteDatabase(await DatabaseHelper.databasePath());
    }
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  test(
    'carts restore read-only with remapped IDs, stable drafts and final tombstones',
    () async {
      final server = FakeSyncBackend();
      final id = await db.insertProduct(
        Product(name: 'Tea', purchasePrice: 12.34, mrp: 20, quantity: 10),
      );
      final product = (await db.getProductById(id))!;
      final item = await db.buildBillItemForProduct(product);
      await db.bindCloudUserData(userId);
      final heldId = await db.holdBill('Counter', [item]);
      await db.saveCartDraft([item]);
      final before = await db.cloudExportRows('held_bills');
      final draftUuid = before.singleWhere((r) => r['kind'] == 'draft')['uuid'];
      item.quantity = 2;
      await db.saveCartDraft([item]);
      expect(
        (await db.cloudExportRows(
          'held_bills',
        )).singleWhere((r) => r['kind'] == 'draft')['uuid'],
        draftUuid,
      );
      server.memberShopId = await db.currentShopId();
      Future<CloudSyncResult> sync() => CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
      ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
      expect((await sync()).conflicts, isEmpty);
      final exported = await db.cloudExportRows('held_bills');
      final nested =
          (jsonDecode(exported.first['items_json'] as String) as List).first
              as Map;
      expect(nested.containsKey('product_id'), isFalse);
      expect(nested['product_uuid'], product.uuid);
      await use('b');
      final clean = await db.database;
      await clean.rawInsert(
        "INSERT INTO sqlite_sequence(name,seq) VALUES('products',100)",
      );
      await db.bindCloudUserData(userId);
      expect((await sync()).conflicts, isEmpty);
      final restoredProduct = (await db.getAllProducts()).single;
      expect(restoredProduct.id, greaterThan(100));
      final restored = await db.getHeldBills();
      expect(restored, hasLength(2));
      expect(restored.every((c) => c.readOnly), isTrue);
      expect(
        restored.every((c) => c.items.first.productId == restoredProduct.id),
        isTrue,
      );
      expect(await db.loadCartDraft(), isEmpty);
      await expectLater(db.takeHeldBill(restored.first.id), throwsStateError);
      await use('a');
      await db.takeHeldBill(heldId);
      await expectLater(db.takeHeldBill(heldId), throwsStateError);
      await db.saveCartDraft([]);
      await sync();
      await use('b');
      await sync();
      expect(await db.getHeldBills(), isEmpty);
    },
  );

  test(
    'portable choices restore without printer, security or token settings',
    () async {
      PortablePreferencesService.install();
      await AppSettingsService.instance.load();
      await AppSettingsService.instance.setLanguage(AppLanguage.hindi);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_lock_enabled', true);
      await prefs.setString('printer_mac', 'old-printer');
      await PortablePreferencesService.prepare(userId, restoring: false);
      final snapshot = await db.cloudExportRows('user_preferences');
      expect(snapshot.map((r) => r['key']).toSet(), {
        'app_language',
        'app_theme_preference',
      });
      await use('b');
      final shop = snapshot.first['shop_id'] as String;
      await db.adoptCloudShopId(shop);
      await prefs.remove('app_language');
      await prefs.remove('app_theme_preference');
      await prefs.setBool('app_lock_enabled', false);
      await prefs.setString('printer_mac', 'new-printer');
      await PortablePreferencesService.prepare(userId, restoring: true);
      expect(await db.cloudDirtyRows('user_preferences'), isEmpty);
      expect(await db.cloudImportRows('user_preferences', snapshot), isEmpty);
      await PortablePreferencesService.apply();
      expect(AppSettingsService.instance.language, AppLanguage.hindi);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      expect(prefs.getBool('app_lock_enabled'), false);
      expect(prefs.getString('printer_mac'), 'new-printer');
      expect(await db.cloudDirtyRows('user_preferences'), isEmpty);
    },
  );

  test(
    'a lost cart upload response retries without duplicates or clearing the queue',
    () async {
      final server = LostCartResponse();
      final productId = await db.insertProduct(
        Product(name: 'Queued', mrp: 10, purchasePrice: 5, quantity: 5),
      );
      await db.bindCloudUserData(userId);
      final item = await db.buildBillItemForProduct(
        (await db.getProductById(productId))!,
      );
      await db.holdBill('Queued cart', [item]);
      server.memberShopId = await db.currentShopId();
      Future<CloudSyncResult> sync() => CloudSyncEngine(
        backend: server,
        database: db,
        knownIsAdmin: true,
      ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
      await expectLater(sync(), throwsStateError);
      expect(await db.cloudDirtyRows('held_bills'), hasLength(1));
      expect(server.rows('held_bills'), hasLength(1));
      expect((await sync()).conflicts, isEmpty);
      expect(await db.cloudDirtyRows('held_bills'), isEmpty);
      expect(server.rows('held_bills'), hasLength(1));
    },
  );

  test(
    'switching the bound account cannot expose or consume cached private carts',
    () async {
      final product = await db.insertProduct(
        Product(name: 'Private', mrp: 10, purchasePrice: 5, quantity: 2),
      );
      await db.bindCloudUserData(userId);
      final item = await db.buildBillItemForProduct(
        (await db.getProductById(product))!,
      );
      final held = await db.holdBill('Private cart', [item]);
      await db.saveCartDraft([item]);
      await db.bindCloudUserData('22222222-2222-4222-8222-222222222222');
      expect(await db.getHeldBills(), isEmpty);
      expect(await db.loadCartDraft(), isEmpty);
      await expectLater(db.takeHeldBill(held), throwsStateError);
      await db.deleteHeldBill(held);
      await db.bindCloudUserData(userId);
      expect(await db.getHeldBills(), hasLength(1));
      expect(await db.loadCartDraft(), hasLength(1));
    },
  );

  test('v21 held carts migrate additively and only once', () async {
    await use('old');
    final path = await DatabaseHelper.databasePath();
    final legacy = await openDatabase(
      path,
      version: 21,
      onCreate: (raw, _) async {
        await raw.execute(
          'CREATE TABLE held_bills(id INTEGER PRIMARY KEY AUTOINCREMENT,shop_id TEXT NOT NULL,kind TEXT NOT NULL,label TEXT NOT NULL,items_json TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL)',
        );
        await raw.insert('held_bills', {
          'shop_id': 'legacy-shop',
          'kind': 'held',
          'label': 'Saved cart',
          'items_json': '[]',
          'created_at': '2026-10-01T10:00:00',
          'updated_at': '2026-10-01T10:00:00',
        });
      },
    );
    await legacy.close();
    final current = await db.database;
    final first = (await current.query('held_bills')).single;
    expect(first['label'], 'Saved cart');
    expect(first['uuid'], isNotEmpty);
    expect(first['origin_device_id'], isNotEmpty);
    await db.close();
    final second = (await (await db.database).query('held_bills')).single;
    expect(second['uuid'], first['uuid']);
    expect(second['origin_device_id'], first['origin_device_id']);
    expect(second['items_json'], '[]');
  });
}
