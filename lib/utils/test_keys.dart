import 'package:flutter/material.dart';

/// Helpers that expose widgets to external UI test tools
/// (Appium, UIAutomator, Maestro, …) and to Flutter integration tests.
///
/// These tools read the platform accessibility tree, where Flutter maps:
///   * [SemanticsProperties.identifier] -> Android
///     `AccessibilityNodeInfo.setViewIdResourceName`, surfaced as `resource-id`
///   * [SemanticsProperties.identifier] -> iOS `accessibilityIdentifier`
///   * [SemanticsProperties.identifier] -> Web `flt-semantics-identifier`
///   * [SemanticsProperties.label]      -> Android `content-desc`
///
/// Per the official docs, `identifier` "provides an identifier for the
/// semantics node in native accessibility hierarchy. This value is not exposed
/// to the users of the app."
///
/// NOTE: Flutter only populates the accessibility tree when an accessibility
/// service (or a test tool acting as one) is attached, so this adds no runtime
/// cost or behaviour change for normal users — it is Play Store safe. It adds
/// no permissions, no native code and no new dependency.
///
/// In Flutter tests these can be found with
/// `find.bySemanticsIdentifier('<id>')`.
class TestKeys {
  TestKeys._();

  /// Wrap any widget so a test tool can find it by [id] (resource-id).
  ///
  /// [label] is optional human-readable text (content-desc); pass it for
  /// icon-only buttons that have no visible text. For widgets that already
  /// show text, omit [label] so the visible text is used as-is.
  ///
  /// Pass [button] for tappable controls and [textField] for inputs so the
  /// node is correctly typed in the accessibility tree.
  static Widget tag(
    String id,
    Widget child, {
    String? label,
    bool button = false,
    bool textField = false,
  }) {
    return Semantics(
      identifier: id,
      label: label,
      button: button,
      textField: textField,
      container: true,
      child: child,
    );
  }

  // ---- Stable identifiers used across the app ----------------------------
  // Centralised so tests and UI stay in sync. Keep names stable.

  // Bottom navigation
  static const navHome = 'nav_home';
  static const navProducts = 'nav_products';
  static const navScan = 'nav_scan';
  static const navBills = 'nav_bills';
  static const navStore = 'nav_store';

  // Primary actions / FABs
  static const addProductBtn = 'btn_add_product';
  static const createBillBtn = 'btn_create_bill';

  // Generic dialog / form buttons
  static const saveBtn = 'btn_save';
  static const cancelBtn = 'btn_cancel';
  static const deleteBtn = 'btn_delete';
  static const confirmBtn = 'btn_confirm';

  // Search fields
  static const productSearchField = 'field_product_search';
  static const billSearchField = 'field_bill_search';

  // Product add/edit form fields
  static const productNameField = 'field_product_name';
  static const productPriceField = 'field_product_price';
  static const productCostField = 'field_product_cost';
  static const productQtyField = 'field_product_qty';
  static const productBarcodeField = 'field_product_barcode';
  static const productCategoryField = 'field_product_category';

  // Filters / sort
  static const productFilterBtn = 'btn_product_filter';
  static const productSortBtn = 'btn_product_sort';

  // Home screen
  static const homeScanBillBtn = 'btn_home_scan_bill';
  static const homeNewBillBtn = 'btn_home_new_bill';
  static const homeAddProductBtn = 'btn_home_add_product';
  static const homeNotificationsBtn = 'btn_home_notifications';

  // Scan screen
  static const scanBillBtn = 'btn_scan_bill';

  // Welcome / onboarding
  static const welcomeShopNameField = 'field_welcome_shop_name';
  static const welcomeContinueBtn = 'btn_welcome_continue';

  /// Build a per-item identifier, e.g. `productRow(42) -> 'product_row_42'`.
  static String productRow(Object id) => 'product_row_$id';
  static String billRow(Object id) => 'bill_row_$id';
  static String customerRow(Object id) => 'customer_row_$id';
  static String supplierRow(Object id) => 'supplier_row_$id';
}
