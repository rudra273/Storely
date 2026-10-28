import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:storely/services/cloud/retired_cloud_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('legacy credentials retire without enabling API or deleting unrelated settings', () async {
    SharedPreferences.setMockInitialValues({
      'storely_cloud_url': 'https://old.example.com',
      'storely_cloud_anon_key': 'old-key',
      'storely_cloud_backend_mode': 'ownSupabase',
      'sb-old-auth-token': 'old-session',
      'storely_api_last_user': 'saved-user',
      'language': 'hi',
    });
    final prefs = await SharedPreferences.getInstance();
    await retireLegacyCloudSettings(prefs);
    await retireLegacyCloudSettings(prefs);
    expect(prefs.getKeys(), {'storely_api_last_user', 'language'});
  });
  test('explicit API selection survives retirement', () async {
    SharedPreferences.setMockInitialValues({'storely_cloud_backend_mode': 'storelyApi'});
    final prefs = await SharedPreferences.getInstance();
    await retireLegacyCloudSettings(prefs);
    expect(prefs.getString('storely_cloud_backend_mode'), 'storelyApi');
  });
}
