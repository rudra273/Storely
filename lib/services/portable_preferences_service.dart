import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import 'app_settings_service.dart';
import 'home_section_prefs.dart';
import 'kpi_prefs.dart';
import 'portable_preference_keys.dart';

class PortablePreferencesService {
  static void install() {
    PortablePreferenceChanges.onChanged = (key, value) =>
        DatabaseHelper.instance.savePortablePreference(key, jsonEncode(value));
  }

  /// On a clean restore, remote choices win over this phone's startup defaults.
  /// On upgrade, existing explicit local choices are captured before first push.
  static Future<void> prepare(String userId, {required bool restoring}) async {
    final db = DatabaseHelper.instance;
    await db.bindCloudUserData(userId, bindPreferences: !restoring);
    if (!restoring) {
      final prefs = await SharedPreferences.getInstance();
      for (final key in portablePreferenceKeys) {
        final value = prefs.get(key);
        if (value != null) {
          await db.savePortablePreference(
            key,
            jsonEncode(value),
            onlyIfMissing: true,
          );
        }
      }
    }
  }

  static Future<void> apply() async {
    final helper = DatabaseHelper.instance;
    final owner = await helper.getCloudSyncState('preference_owner');
    if (owner == null) return;
    final db = await helper.database;
    final rows = await db.query(
      'user_preferences',
      where: 'shop_id = ? AND owner_user_id = ? AND deleted_at IS NULL',
      whereArgs: [await helper.currentShopId(), owner],
    );
    final prefs = await SharedPreferences.getInstance();
    for (final row in rows) {
      final key = row['key'] as String;
      if (!portablePreferenceKeys.contains(key)) continue;
      final value = jsonDecode(row['value'] as String);
      if (value is String) {
        await prefs.setString(key, value);
      } else if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, value.cast<String>());
      }
    }
    await AppSettingsService.instance.reload();
    await HomeSectionPrefs.instance.reload();
    await KpiPrefs.instance.reload();
  }
}
