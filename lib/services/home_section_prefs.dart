import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sort options for the home Unpaid Bills section.
enum UnpaidBillsSort {
  newest('newest', 'Newest first'),
  oldest('oldest', 'Oldest first'),
  highest('highest', 'Highest amount');

  final String storageValue;
  final String label;
  const UnpaidBillsSort(this.storageValue, this.label);

  static UnpaidBillsSort fromStorage(String? value) =>
      UnpaidBillsSort.values.firstWhere(
        (s) => s.storageValue == value,
        orElse: () => UnpaidBillsSort.newest,
      );
}

/// Per-section display preferences for the home screen.
/// Counts, sort, and visibility persist in SharedPreferences.
/// (The low-stock threshold itself lives in the DB.)
class HomeSectionPrefs extends ChangeNotifier {
  static final HomeSectionPrefs instance = HomeSectionPrefs._();
  HomeSectionPrefs._();

  static const _unpaidCountKey = 'home_unpaid_count';
  static const _unpaidSortKey = 'home_unpaid_sort';
  static const _unpaidHiddenKey = 'home_unpaid_hidden';
  static const _attentionCountKey = 'home_attention_count';
  static const _attentionHiddenKey = 'home_attention_hidden';

  int _unpaidCount = 3;
  UnpaidBillsSort _unpaidSort = UnpaidBillsSort.newest;
  bool _unpaidHidden = false;
  int _attentionCount = 3;
  bool _attentionHidden = false;

  int get unpaidCount => _unpaidCount;
  UnpaidBillsSort get unpaidSort => _unpaidSort;
  bool get unpaidHidden => _unpaidHidden;
  int get attentionCount => _attentionCount;
  bool get attentionHidden => _attentionHidden;

  /// Sentinel used in pickers to mean "show all".
  static const showAll = 1000000;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _unpaidCount = prefs.getInt(_unpaidCountKey) ?? 3;
    _unpaidSort = UnpaidBillsSort.fromStorage(prefs.getString(_unpaidSortKey));
    _unpaidHidden = prefs.getBool(_unpaidHiddenKey) ?? false;
    _attentionCount = prefs.getInt(_attentionCountKey) ?? 3;
    _attentionHidden = prefs.getBool(_attentionHiddenKey) ?? false;
  }

  Future<void> setUnpaidCount(int value) async {
    if (_unpaidCount == value) return;
    _unpaidCount = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_unpaidCountKey, value);
  }

  Future<void> setUnpaidSort(UnpaidBillsSort value) async {
    if (_unpaidSort == value) return;
    _unpaidSort = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_unpaidSortKey, value.storageValue);
  }

  Future<void> setUnpaidHidden(bool value) async {
    if (_unpaidHidden == value) return;
    _unpaidHidden = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_unpaidHiddenKey, value);
  }

  Future<void> setAttentionCount(int value) async {
    if (_attentionCount == value) return;
    _attentionCount = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_attentionCountKey, value);
  }

  Future<void> setAttentionHidden(bool value) async {
    if (_attentionHidden == value) return;
    _attentionHidden = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_attentionHiddenKey, value);
  }
}
