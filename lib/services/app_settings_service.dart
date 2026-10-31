import 'portable_preference_keys.dart';
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

/// App language. System follows the phone (Hindi phones get Hindi).
enum AppLanguage {
  system('system', 'Phone language', null),
  english('en', 'English', Locale('en')),
  hindi('hi', 'हिन्दी (Hindi)', Locale('hi'));

  final String storageValue;
  final String label;
  final Locale? locale;

  const AppLanguage(this.storageValue, this.label, this.locale);

  static AppLanguage fromStorage(String? value) => AppLanguage.values
      .firstWhere((l) => l.storageValue == value, orElse: () => system);
}

class AppSettingsService extends ChangeNotifier {
  static const _languageKey = 'app_language';
  static const _themePreferenceKey = 'app_theme_preference';
  static const _appLockEnabledKey = 'app_lock_enabled';
  static const _billingSearchFirstKey = 'billing_search_first';
  static final AppSettingsService instance = AppSettingsService._();

  AppSettingsService._();

  AppThemePreference _themePreference = AppThemePreference.system;
  AppLanguage _language = AppLanguage.system;
  bool _languageChosen = false;

  AppLanguage get language => _language;
  Locale? get locale => _language.locale;

  /// True once a language was picked (the welcome screen asks until then).
  bool get languageChosen => _languageChosen;
  bool _appLockEnabled = false;
  bool _billingSearchFirst = false;

  AppThemePreference get themePreference => _themePreference;
  ThemeMode get themeMode => _themePreference.themeMode;
  bool get appLockEnabled => _appLockEnabled;

  /// Billing opens in Search (true) or Scan mode: whichever was used last.
  bool get billingSearchFirst => _billingSearchFirst;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themePreference = AppThemePreference.fromStorage(
      prefs.getString(_themePreferenceKey),
    );
    _appLockEnabled = prefs.getBool(_appLockEnabledKey) ?? false;
    final language = prefs.getString(_languageKey);
    _languageChosen = language != null;
    _language = AppLanguage.fromStorage(language);
    _billingSearchFirst = prefs.getBool(_billingSearchFirstKey) ?? false;
  }

  /// Remembered quietly (no rebuild of the app).
  Future<void> setBillingSearchFirst(bool value) async {
    if (_billingSearchFirst == value) return;
    _billingSearchFirst = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_billingSearchFirstKey, value);
    await PortablePreferenceChanges.record(_billingSearchFirstKey, value);
  }

  Future<void> setThemePreference(AppThemePreference value) async {
    if (_themePreference == value) return;
    _themePreference = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themePreferenceKey, value.storageValue);
    await PortablePreferenceChanges.record(
      _themePreferenceKey,
      value.storageValue,
    );
  }

  Future<void> setLanguage(AppLanguage value) async {
    _languageChosen = true;
    _language = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, value.storageValue);
    await PortablePreferenceChanges.record(_languageKey, value.storageValue);
  }

  Future<void> setAppLockEnabled(bool value) async {
    if (_appLockEnabled == value) return;
    _appLockEnabled = value;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_appLockEnabledKey, value);
  }

  Future<void> reload() async {
    await load();
    notifyListeners();
  }
}
