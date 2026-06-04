import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePreference {
  system('system', 'System', ThemeMode.system),
  light('light', 'Light', ThemeMode.light),
  dark('dark', 'Dark', ThemeMode.dark);

  final String storageValue;
  final String label;
  final ThemeMode themeMode;

  const AppThemePreference(this.storageValue, this.label, this.themeMode);

  static AppThemePreference fromStorage(String? value) {
    return AppThemePreference.values.firstWhere(
      (preference) => preference.storageValue == value,
      orElse: () => AppThemePreference.system,
    );
  }
}

class AppSettingsService extends ChangeNotifier {
  static const _themePreferenceKey = 'app_theme_preference';
  static const _appLockEnabledKey = 'app_lock_enabled';
  static final AppSettingsService instance = AppSettingsService._();

  AppSettingsService._();

  AppThemePreference _themePreference = AppThemePreference.system;
  bool _appLockEnabled = false;

  AppThemePreference get themePreference => _themePreference;
  ThemeMode get themeMode => _themePreference.themeMode;
  bool get appLockEnabled => _appLockEnabled;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themePreference = AppThemePreference.fromStorage(
      prefs.getString(_themePreferenceKey),
    );
    _appLockEnabled = prefs.getBool(_appLockEnabledKey) ?? false;
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    if (_themePreference == value) return;
    _themePreference = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePreferenceKey, value.storageValue);
  }

  Future<void> setAppLockEnabled(bool value) async {
    if (_appLockEnabled == value) return;
    _appLockEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appLockEnabledKey, value);
  }
}
