import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/services/app_settings_service.dart';
import 'package:storely/services/home_section_prefs.dart';
import 'package:storely/services/kpi_prefs.dart';
import 'package:storely/services/portable_preference_keys.dart';
import 'package:storely/services/portable_preferences_service.dart';
import 'package:storely/services/sync/cloud_sync_engine.dart';
import 'support/fake_sync_backend.dart';

const a = '11111111-1111-4111-8111-111111111111';
const b = '22222222-2222-4222-8222-222222222222';

class AuthFlipBackend extends FakeSyncBackend {
  bool valid = true;
  @override
  Future<List<Map<String, dynamic>>> pullPage(
    String table, {
    required String shopId,
    required DateTime afterTs,
    required String afterKey,
    required int limit,
  }) async {
    final page = await super.pullPage(
      table,
      shopId: shopId,
      afterTs: afterTs,
      afterKey: afterKey,
      limit: limit,
    );
    if (table == 'user_preferences') valid = false;
    return page;
  }
}

void main() {
  final db = DatabaseHelper.instance;
  String? auth;
  Future<void> install() async {
    PortablePreferencesService.install(authUser: () => auth);
    await PortablePreferencesService.ready();
  }

  Future<void> bind(String user, {bool restoring = true}) async {
    auth = user;
    await PortablePreferencesService.onAuthChanged(user);
    await PortablePreferencesService.prepare(user, restoring: restoring);
  }

  Future<List<Map<String, Object?>>> rows(String user) async =>
      (await db.database).query(
        'user_preferences',
        where: 'owner_user_id = ?',
        whereArgs: [user],
      );
  Future<void> remote(
    String user,
    String key,
    Object? value, {
    String? uuid,
    bool deleted = false,
    String updated = '2026-01-01T00:00:00Z',
  }) async {
    final shop = await db.currentShopId();
    final sql = await db.database;
    await sql.insert('user_preferences', {
      'uuid': uuid ?? '$shop:$user:$key',
      'shop_id': shop,
      'owner_user_id': user,
      'key': key,
      'value': value is String && value == 'bad-json'
          ? 'bad-json'
          : jsonEncode(value),
      'created_at': updated,
      'updated_at': updated,
      'deleted_at': deleted ? updated : null,
      'sync_dirty': 2,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    PortablePreferenceChanges.onChanged = null;
    auth = null;
    await db.close();
    DatabaseHelper.databaseFileName = 'portable-scope.db';
    await deleteDatabase(await DatabaseHelper.databasePath());
    SharedPreferences.setMockInitialValues({});
    await AppSettingsService.instance.reload();
    await HomeSectionPrefs.instance.reload();
    await KpiPrefs.instance.reload();
  });
  tearDown(() async {
    PortablePreferenceChanges.onChanged = null;
    await db.close();
    await deleteDatabase(await DatabaseHelper.databasePath());
    DatabaseHelper.databaseFileName = 'storely.db';
  });

  test(
    'proven explicit offline choices adopt once and remain local after signout',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_language', 'hi');
      await prefs.setBool('app_lock_enabled', true);
      await prefs.setString('printer_mac', 'keep');
      await install();
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      await bind(a, restoring: false);
      expect((await rows(a)).map((r) => r['key']).toSet(), {
        'app_language',
        'app_theme_preference',
      });
      auth = null;
      await PortablePreferencesService.onAuthChanged(null);
      expect(await db.getCloudSyncState('preference_owner'), a);
      expect(AppSettingsService.instance.language, AppLanguage.hindi);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      expect(prefs.getBool('app_lock_enabled'), true);
      expect(prefs.getString('printer_mac'), 'keep');
    },
  );
  test(
    'outgoing private values never seed another user or guest defaults',
    () async {
      await install();
      await bind(a);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      await AppSettingsService.instance.setLanguage(AppLanguage.hindi);
      await HomeSectionPrefs.instance.setAttentionHidden(true);
      await bind(b, restoring: false);
      expect(await rows(b), isEmpty);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      expect(AppSettingsService.instance.language, AppLanguage.system);
      expect(HomeSectionPrefs.instance.attentionHidden, isFalse);
      auth = null;
      await PortablePreferencesService.onAuthChanged(null);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      expect(AppSettingsService.instance.language, AppLanguage.system);
      expect(await db.getCloudSyncState('preference_owner'), b);
      expect((await rows(a)).map((r) => r['key']).toSet(), {
        'app_language',
        'app_theme_preference',
        'home_attention_hidden',
      });
    },
  );
  test(
    'ambiguous legacy cloud cache becomes neither guest nor another user data',
    () async {
      await db.bindCloudUserData(a);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_theme_preference', 'dark');
      await prefs.setString('app_language', 'hi');
      await install();
      await PortablePreferencesService.onAuthChanged(null);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      expect(AppSettingsService.instance.language, AppLanguage.system);
      await bind(b, restoring: false);
      expect(await rows(b), isEmpty);
    },
  );
  test(
    'unbound signed-in explicit picks are private pending choices, never guest seeds',
    () async {
      await install();
      auth = a;
      await PortablePreferencesService.onAuthChanged(a);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      auth = null;
      await PortablePreferencesService.onAuthChanged(null);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      auth = b;
      await PortablePreferencesService.onAuthChanged(b);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      auth = a;
      await PortablePreferencesService.onAuthChanged(a);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      expect(await rows(a), isEmpty);
      expect(await db.getCloudSyncState('preference_owner'), isNull);
    },
  );
  test(
    'missing deleted malformed and wrong-type scoped rows reset only allowed projections',
    () async {
      await install();
      await bind(a);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      await AppSettingsService.instance.setLanguage(AppLanguage.hindi);
      await HomeSectionPrefs.instance.setUnpaidCount(10);
      await remote(a, 'app_theme_preference', 'dark', deleted: true);
      await remote(a, 'app_language', 'bad-json');
      await remote(a, 'home_unpaid_count', true);
      await remote(a, 'analytics_enabled_kpis', [1]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('app_lock_enabled', true);
      await prefs.setString('printer_mac', 'keep');
      await PortablePreferencesService.apply();
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      expect(AppSettingsService.instance.language, AppLanguage.system);
      expect(HomeSectionPrefs.instance.unpaidCount, 3);
      expect(prefs.containsKey('analytics_enabled_kpis'), isFalse);
      expect(prefs.getBool('app_lock_enabled'), true);
      expect(prefs.getString('printer_mac'), 'keep');
    },
  );
  test(
    'queued user intent stays with outgoing scope and incoming profile wins after switch',
    () async {
      await install();
      await bind(a);
      final sql = await db.database;
      final entered = Completer<void>();
      final release = Completer<void>();
      final blocked = sql.transaction((txn) async {
        entered.complete();
        await release.future;
      });
      await entered.future;
      final write = AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      auth = b;
      final switching = PortablePreferencesService.onAuthChanged(b);
      release.complete();
      await blocked;
      await write;
      await switching;
      expect(jsonDecode((await rows(a)).single['value'] as String), 'dark');
      expect(await rows(b), isEmpty);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      await PortablePreferencesService.prepare(b, restoring: false);
      expect(await rows(b), isEmpty);
    },
  );
  test(
    'same-scope periodic prepare cannot reject or erase a real queued edit',
    () async {
      await install();
      await bind(a);
      final preparing = PortablePreferencesService.prepare(a, restoring: false);
      final edit = AppSettingsService.instance.setLanguage(AppLanguage.hindi);
      await preparing;
      await edit;
      expect(AppSettingsService.instance.language, AppLanguage.hindi);
      expect(jsonDecode((await rows(a)).single['value'] as String), 'hi');
    },
  );
  test(
    'stale scoped writes cannot retarget another checkout owner or tenant',
    () async {
      await install();
      await bind(a);
      final shop = await db.currentShopId();
      await db.bindCloudUserData(b);
      await expectLater(
        db.savePortablePreferenceForScope(
          'app_language',
          '"hi"',
          shopId: shop,
          userId: a,
        ),
        throwsStateError,
      );
      expect(await rows(b), isEmpty);
      await expectLater(
        db.savePortablePreferenceForScope(
          'app_language',
          '"hi"',
          shopId: 'other-shop',
          userId: b,
        ),
        throwsStateError,
      );
    },
  );
  test(
    'historical cloud preference UUID merges by checked natural identity and retains newer local choice',
    () async {
      await install();
      await bind(a);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      final shop = await db.currentShopId();
      final conflicts = await db.cloudImportRows('user_preferences', [
        {
          'uuid': 'legacy-native-uuid',
          'shop_id': shop,
          'owner_user_id': a,
          'key': 'app_theme_preference',
          'value': '"light"',
          'created_at': '2020-01-01T00:00:00Z',
          'updated_at': '2020-01-01T00:00:00Z',
          'deleted_at': null,
        },
      ]);
      expect(conflicts, isEmpty);
      final row = (await rows(a)).single;
      expect(row['uuid'], 'legacy-native-uuid');
      expect(row['value'], '"dark"');
      expect(row['sync_dirty'], 1);
      await PortablePreferencesService.apply();
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
    },
  );
  test(
    'older incoming user cursor rows pull after switching and legacy cursor is dropped once',
    () async {
      await install();
      await bind(a);
      final shop = await db.currentShopId();
      await db.ensurePortablePreferenceCursorScope(shop);
      await db.setCloudSyncState(
        'pull_cursor:user_preferences',
        '2099-01-01T00:00:00Z',
      );
      await db.setCloudSyncState(
        'pull_cursor:held_bills',
        '2099-01-01T00:00:00Z',
      );
      await bind(b);
      final backend = FakeSyncBackend()..memberShopId = shop;
      backend.tables['user_preferences'] = {
        'old-b': {
          'uuid': 'old-b',
          'shop_id': shop,
          'owner_user_id': b,
          'key': 'app_theme_preference',
          'value': '"dark"',
          'created_at': '2020-01-01T00:00:00Z',
          'updated_at': '2020-01-01T00:00:00Z',
          'server_updated_at': '2020-01-01T00:00:00Z',
          'deleted_at': null,
        },
      };
      final result = await CloudSyncEngine(
        backend: backend,
        database: db,
        knownIsAdmin: true,
        applyUserData: PortablePreferencesService.apply,
      ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
      expect(result.conflicts, isEmpty);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      expect(
        await db.getCloudSyncState('pull_cursor:held_bills'),
        '2099-01-01T00:00:00Z',
      );
      expect(
        await db.getCloudSyncState('pull_cursor:user_preferences'),
        '2020-01-01T00:00:00.000Z',
      );
      await bind(a);
      backend.tables['user_preferences'] = {
        'old-a': {
          'uuid': 'old-a',
          'shop_id': shop,
          'owner_user_id': a,
          'key': 'app_theme_preference',
          'value': '"light"',
          'created_at': '2019-01-01T00:00:00Z',
          'updated_at': '2019-01-01T00:00:00Z',
          'server_updated_at': '2019-01-01T00:00:00Z',
          'deleted_at': null,
        },
      };
      await CloudSyncEngine(
        backend: backend,
        database: db,
        knownIsAdmin: true,
        applyUserData: PortablePreferencesService.apply,
      ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.light,
      );
      final conflict = SyncConflict(
        table: 'user_preferences',
        key: 'old-b',
        message: 'test',
      );
      await CloudSyncEngine.useCloudCopy(db, conflict);
      expect(
        await db.getCloudSyncState('pull_cursor:user_preferences'),
        isNull,
      );
      await CloudSyncEngine.resetProgress(db);
      expect(
        await db.getCloudSyncState('pull_cursor:user_preferences'),
        isNull,
      );
    },
  );
  test(
    'stored authenticated restart and revoked-session event restore only current identity',
    () async {
      await install();
      await bind(a);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      await install();
      await PortablePreferencesService.onAuthChanged(a);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      auth = null;
      await PortablePreferencesService.onAuthChanged(null);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      expect(await db.getCloudSyncState('preference_owner'), a);
      auth = b;
      await PortablePreferencesService.onAuthChanged(b);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
    },
  );
  test(
    'scoped restoration keeps explicit guest profile separate and resets a new shop',
    () async {
      await install();
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      await bind(a);
      await remote(a, 'app_theme_preference', 'light');
      await PortablePreferencesService.apply();
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.light,
      );
      final oldShop = await db.currentShopId();
      await db.adoptCloudShopId('new-preference-shop');
      await bind(a, restoring: false);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
      expect(
        await db.portablePreferencesForScope(
          shopId: 'new-preference-shop',
          userId: a,
        ),
        isEmpty,
      );
      expect((await rows(a)).single['shop_id'], oldShop);
      auth = null;
      await PortablePreferencesService.onAuthChanged(null);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
    },
  );
  test(
    'legacy cursor without scope marker is invalidated before its first private pull',
    () async {
      await install();
      await bind(a);
      final shop = await db.currentShopId();
      await db.setCloudSyncState(
        'pull_cursor:user_preferences',
        '2099-01-01T00:00:00Z',
      );
      final backend = FakeSyncBackend()..memberShopId = shop;
      backend.tables['user_preferences'] = {
        'legacy-a': {
          'uuid': 'legacy-a',
          'shop_id': shop,
          'owner_user_id': a,
          'key': 'app_theme_preference',
          'value': '"dark"',
          'created_at': '2020-01-01T00:00:00Z',
          'updated_at': '2020-01-01T00:00:00Z',
          'server_updated_at': '2020-01-01T00:00:00Z',
          'deleted_at': null,
        },
      };
      expect(
        await db.getCloudSyncState('user_preferences_cursor_scope'),
        isNull,
      );
      await CloudSyncEngine(
        backend: backend,
        database: db,
        knownIsAdmin: true,
        applyUserData: PortablePreferencesService.apply,
      ).sync(firstSyncMode: FirstSyncMode.uploadExisting);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      expect(
        await db.getCloudSyncState('pull_cursor:user_preferences'),
        '2020-01-01T00:00:00.000Z',
      );
    },
  );
  test(
    'stale auth-error fallback cannot clear the successfully restored incoming user',
    () async {
      await install();
      await bind(a);
      await bind(b);
      await AppSettingsService.instance.setThemePreference(
        AppThemePreference.dark,
      );
      await PortablePreferencesService.clearVisibleProjection(expectedUser: a);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.dark,
      );
      await PortablePreferencesService.clearVisibleProjection(expectedUser: b);
      expect(
        AppSettingsService.instance.themePreference,
        AppThemePreference.system,
      );
    },
  );
  test(
    'auth changing during pull cannot import private rows or advance their cursor',
    () async {
      await install();
      await bind(a);
      final shop = await db.currentShopId();
      final backend = AuthFlipBackend()..memberShopId = shop;
      backend.tables['user_preferences'] = {
        'late-auth': {
          'uuid': 'late-auth',
          'shop_id': shop,
          'owner_user_id': a,
          'key': 'app_theme_preference',
          'value': '"dark"',
          'created_at': '2020-01-01T00:00:00Z',
          'updated_at': '2020-01-01T00:00:00Z',
          'server_updated_at': '2020-01-01T00:00:00Z',
          'deleted_at': null,
        },
      };
      await expectLater(
        CloudSyncEngine(
          backend: backend,
          database: db,
          knownIsAdmin: true,
          isUserDataScopeCurrent: () => backend.valid,
        ).sync(firstSyncMode: FirstSyncMode.uploadExisting),
        throwsStateError,
      );
      expect(await rows(a), isEmpty);
      expect(
        await db.getCloudSyncState('pull_cursor:user_preferences'),
        isNull,
      );
      final scope = await db.ensurePortablePreferenceCursorScope(shop);
      await expectLater(
        db.savePortablePreferenceCursor(
          scope,
          '2099-01-01T00:00:00Z',
          isTransportCurrent: () => false,
        ),
        throwsStateError,
      );
      expect(
        await db.getCloudSyncState('pull_cursor:user_preferences'),
        isNull,
      );
    },
  );
}
