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
  static Future<void> record(String key, Object value) async {
    if (!portablePreferenceKeys.contains(key)) {
      throw ArgumentError('Not a portable preference');
    }
    await onChanged?.call(key, value);
  }
}
