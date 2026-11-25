import 'package:shared_preferences/shared_preferences.dart';

/// The allowlist deliberately excludes credentials, app lock, printer pairing,
/// device identity and sync/backup runtime state.
const portablePreferenceKeys = {
  'app_language',
  'app_theme_preference',
  'billing_search_first',
  'home_unpaid_count',
  'home_unpaid_sort',
  'home_unpaid_hidden',
  'home_attention_count',
  'home_attention_hidden',
  'analytics_enabled_kpis',
};

class PortablePreferenceChanges {
  static Future<void> Function(String key, Object value)? onChanged;
  static Future<void> record(String key, Object value) {
    if (!portablePreferenceKeys.contains(key)) {
      throw ArgumentError('Not a portable preference');
    }
    final snapshot = value is List<String>
        ? List<String>.unmodifiable(value)
        : value;
    final handler = onChanged;
    return handler == null ? writeLocal(key, snapshot) : handler(key, snapshot);
  }

  static Future<void> writeLocal(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) {
      await prefs.setString(key, value);
    } else if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is int) {
      await prefs.setInt(key, value);
    } else if (value is List<String>) {
      await prefs.setStringList(key, value);
    } else {
      throw ArgumentError('Invalid portable preference value');
    }
  }
}
