import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:storely/config/cloud_defaults.dart';
import 'package:storely/db/database_helper.dart';
import 'package:storely/services/api/api_client.dart';
import 'package:storely/services/api/http_client_factory.dart';
import 'package:storely/services/api/token_store.dart';
import 'package:storely/services/app_settings_service.dart';
import 'package:storely/services/cloud_service.dart';

const _shop = String.fromEnvironment('STORELY_PREF_TEST_SHOP');
const _ownerEmail = String.fromEnvironment('STORELY_PREF_TEST_OWNER');
const _ownerPassword = String.fromEnvironment(
  'STORELY_PREF_TEST_OWNER_PASSWORD',
);
const _staffEmail = String.fromEnvironment('STORELY_PREF_TEST_STAFF');
const _staffPassword = String.fromEnvironment(
  'STORELY_PREF_TEST_STAFF_PASSWORD',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real account switch and theme round trip on Android', (
    tester,
  ) async {
    final base = Uri.parse(CloudDefaults.apiUrl);
    expect(
      base.host,
      '10.0.2.2',
      reason: 'This fixture uses the local Docker API.',
    );
    expect(_ownerEmail, startsWith('appearance-owner-'));
    expect(_staffEmail, startsWith('appearance-staff-'));
    final api = ApiClient(
      baseUrl: base,
      httpClient: createApiHttpClient(),
      tokens: MemoryTokenStore(),
    );
    final db = DatabaseHelper.instance;
    final service = CloudService.instance;
    final preferences = AppSettingsService.instance;
    final originalName = DatabaseHelper.databaseFileName;
    await db.close();
    DatabaseHelper.databaseFileName = 'portable-theme-device-test.db';
    final path = await DatabaseHelper.databasePath();
    await deleteDatabase(path);
    var configured = false;
    try {
      await service.initialize();
      expect(
        service.state.value.isConfigured,
        isFalse,
        reason: 'Use the dedicated disposable test emulator.',
      );
      await db.adoptCloudShopId(_shop);
      await preferences.setThemePreference(AppThemePreference.dark);
      final endpoint = '/v1/shops/$_shop/preferences/theme';
      await api.login(_staffEmail, _staffPassword);
      expect(await api.putJson(endpoint, {'theme': 'light'}), {
        'theme': 'light',
      });
      await api.logout();
      await api.login(_ownerEmail, _ownerPassword);
      expect(await api.putJson(endpoint, {'theme': 'dark'}), {'theme': 'dark'});

      await service.useStorelyCloud();
      configured = true;
      await service.signIn(_ownerEmail, _ownerPassword, syncAfterAuth: false);
      Future<void> sync() async {
        await service.syncNow(reason: 'On-device appearance test');
        expect(service.state.value.error, isNull);
        expect(await db.currentShopId(), _shop);
        expect(await db.getSyncConflicts(), isEmpty);
      }

      await sync();
      expect(preferences.themePreference, AppThemePreference.dark);
      expect(await api.putJson(endpoint, {'theme': 'light'}), {
        'theme': 'light',
      });
      await sync();
      expect(preferences.themePreference, AppThemePreference.light);
      await preferences.setThemePreference(AppThemePreference.system);
      await sync();
      expect(await api.getJson(endpoint), {'theme': 'system'});

      final checkoutOwner = await db.getCloudSyncState('preference_owner');
      await service.signOut();
      expect(preferences.themePreference, AppThemePreference.dark);
      expect(await db.getCloudSyncState('preference_owner'), checkoutOwner);
      await service.signIn(_staffEmail, _staffPassword, syncAfterAuth: false);
      expect(preferences.themePreference, AppThemePreference.system);
      await sync();
      expect(preferences.themePreference, AppThemePreference.light);
      expect(await api.getJson(endpoint), {'theme': 'system'});
    } finally {
      if (configured) await service.clearConfig();
      api.dispose();
      await db.close();
      await deleteDatabase(path);
      DatabaseHelper.databaseFileName = originalName;
    }
  }, skip: _shop.isEmpty);
}
