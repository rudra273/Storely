import 'package:flutter/foundation.dart';

import '../db/database_helper.dart';

/// What is waiting to upload and what failed, refreshed after each sync and
/// after local changes.
class SyncStatus extends ChangeNotifier {
  static final SyncStatus instance = SyncStatus._();

  SyncStatus._();

  Map<String, int> pending = const {};
  List<SyncConflict> conflicts = const [];

  int get pendingTotal => pending.values.fold(0, (s, n) => s + n);

  Future<void> refresh() async {
    try {
      final db = DatabaseHelper.instance;
      pending = await db.pendingSyncCounts();
      conflicts = await db.getSyncConflicts();
      notifyListeners();
    } catch (error) {
      debugPrint('Sync status refresh failed: $error');
    }
  }

  /// Plain-language name for a synced table.
  static String label(String table) => switch (table) {
    'shops' => 'Shop profile',
    'app_settings' || 'bill_settings' => 'Settings',
    'categories' => 'Categories',
    'units' => 'Units',
    'suppliers' => 'Suppliers',
    'customers' => 'Customers',
    'products' => 'Products',
    'invoice_series' => 'Bill numbering',
    'bills' => 'Bills',
    'bill_items' => 'Bill items',
    'bill_payments' => 'Payments',
    'stock_movements' => 'Stock changes',
    'purchase_documents' => 'Purchase documents',
    'expenses' => 'Expenses',
    'audit_log' => 'History',
    'held_bills' => 'Held carts and drafts',
    'user_preferences' => 'Display preferences',
    _ => table,
  };
}
