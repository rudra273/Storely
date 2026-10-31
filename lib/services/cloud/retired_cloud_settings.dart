import 'package:shared_preferences/shared_preferences.dart';

/// Retire old backend credentials without touching business or API account data.
Future<void> retireLegacyCloudSettings(SharedPreferences prefs) async {
  await prefs.remove('storely_cloud_url');
  await prefs.remove('storely_cloud_anon_key');
  if (prefs.getString('storely_cloud_backend_mode') != 'storelyApi') {
    await prefs.remove('storely_cloud_backend_mode');
  }
  for (final key in prefs.getKeys()) {
    if (key.startsWith('sb-') && key.endsWith('-auth-token')) {
      await prefs.remove(key);
    }
  }
}
