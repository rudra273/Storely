# Storely Screen Modularization Plan

## Goal

Make the app easier to scale for production by splitting oversized screen files into focused screens, widgets, dialogs, and helpers without changing the current UI colors, layout style, text hierarchy, navigation behavior, or business functionality.

Current health check:
- `flutter analyze` passes with no issues.
- Largest files:
  - `lib/screens/products_screen.dart`: ~5030 lines
  - `lib/screens/store_screen.dart`: ~2552 lines
  - `lib/screens/scan_screen.dart`: ~1523 lines
  - `lib/screens/bills_screen.dart`: ~1125 lines
- Existing tests are present under `test/`.

Existing product backlog note:
- Make QR code/barcode generation optional when creating printable code sheets.

Implementation status:
- Completed modular extraction for Products, Store, Scan, and Bills screens.
- Used Dart `part` files so existing private classes/helpers could move without changing behavior.
- Verified with `flutter analyze`, `flutter test`, and `flutter build apk --release`.

## Rules For The Refactor

1. Keep all user-facing UI visually identical unless a bug fix absolutely requires a tiny structural change.
2. Move code first; do not redesign.
3. Preserve current navigation and refresh behavior from `main.dart`.
4. Keep database APIs unchanged unless a real bug is found.
5. Keep theme usage through existing `AppColors`, `AppText`, `AppSpacing`, `AppRadius`, `AppCard`, and related theme widgets.
6. After each phase run:
   - `dart format lib test`
   - `flutter analyze`
   - `flutter test`
7. Commit-ready rule: every phase should leave the app compiling and runnable.

## Proposed Folder Structure

```text
lib/
  screens/
    products/
      products_screen.dart
      add_edit_product_sheet.dart
      new_purchase_screen.dart
      import_products_sheet.dart
      product_filters_sheet.dart
      stock_history_sheet.dart
      product_bulk_actions.dart
      product_cards.dart
      product_editor_widgets.dart
      product_import_widgets.dart
      product_models.dart
      product_formatters.dart
    store/
      store_screen.dart
      shop_profile_sheet.dart
      supplier_profile_sheet.dart
      supplier_manager_sheet.dart
      customer_table_sheet.dart
      customer_profile_sheet.dart
      pricing_settings_sheets.dart
      cloud_setup_sheet.dart
      store_dialogs.dart
      store_panels.dart
    billing/
      bills_screen.dart
      bill_actions.dart
      bill_cards.dart
      bill_dialogs.dart
    scan/
      scan_screen.dart
      billing_cart_widgets.dart
      billing_customer_sheet.dart
      product_picker_widgets.dart
```

Compatibility option:
- Keep temporary forwarding files like `lib/screens/products_screen.dart` that export `products/products_screen.dart` if changing imports all at once becomes risky.

## Phase 1: Products Screen Split

Target: reduce `products_screen.dart` from ~5030 lines to a focused route/controller file of roughly 500-900 lines.

Move first:
1. Private models and format helpers:
   - `_ProductSortMode`
   - `_PurchaseDraft`
   - `_formatShortDate`
   - `_formatFullDate`
   - `_formatQuantityInput`
   - `_optionalControllerText`
   - `_normaliseOptionName`
2. Pure UI widgets:
   - product card/source/info chips
   - bulk selection bar/action chips
   - filter/sort buttons and active filter chips
   - import preview table/rows
   - product editor UI parts such as header, sections, mode pills, price controls, pricing table, dropdowns
3. Sheets:
   - filters sheet
   - import preview sheet
   - stock history sheet
   - add/edit product sheet
4. Full page:
   - move `_NewPurchaseScreen` into `new_purchase_screen.dart`.

Important behavior to preserve:
- Search, sort, category/supplier/date filters.
- Bulk select, select all visible, bulk category/supplier update, bulk delete.
- QR sheet navigation.
- CSV import, duplicate purchase warning, replace/add/update stock behavior.
- New purchase flow: purchase date/supplier first, then separate staging page.
- Add/edit product validation, duplicate-name handling, restock matching, direct price vs formula price, category/global pricing inheritance.
- Stock movement history.

Possible improvement that matches the request:
- The current add/edit product editor is a bottom sheet. It can be moved into a separate file immediately.
- After that works, decide whether to convert it from bottom sheet to a dedicated `AddEditProductScreen`. This is more visible behavior, so do it only after the no-UI-change extraction is stable.

## Phase 2: Store Screen Split

Target: reduce `store_screen.dart` from ~2552 lines to a focused route/controller file of roughly 400-700 lines.

Move first:
1. Store display widgets:
   - section labels
   - shop panel
   - action rows
   - store panels/icon widgets
2. Cloud sync:
   - `_CloudSyncPanel`
   - `_CloudSetupSheet`
   - configured summary/status message widgets
3. Store configuration sheets:
   - shop profile sheet
   - supplier profile sheet
   - supplier manager sheet
   - global pricing sheet
   - category pricing sheet
4. Customer management:
   - customer table sheet
   - customer profile sheet
5. Reusable dialogs:
   - name dialog
   - number dialog
   - delete confirmation helper
   - money field

Important behavior to preserve:
- Store profile editing with GST setting.
- Category add/edit/delete.
- Supplier add/edit/delete, including supplier profiles.
- Pricing defaults and category pricing overrides.
- Unit management inside pricing defaults.
- Low-stock threshold.
- Customer table and customer profile editing.
- Cloud setup, sync, sign-in/sign-up/sign-out/disable.
- Privacy/About/Analytics navigation.

## Phase 3: Scan And Billing Cleanup

These are smaller than product/store, but still large enough to benefit from separation.

Scan screen split:
- Keep scan route state and billing operations in `scan_screen.dart`.
- Move cart rows, totals/footer, manual product picker, customer/payment sheet, and mode-specific widgets into `lib/screens/scan/`.

Bills screen split:
- Keep bill loading/search/refresh state in `bills_screen.dart`.
- Move bill card/list widgets, payment dialog, WhatsApp/PDF action helpers, and formatting helpers into `lib/screens/billing/`.

Important behavior to preserve:
- Scanner cooldown behavior.
- Manual billing flow.
- Customer/GST details on bill creation.
- Stock deduction and bill persistence.
- Bill search, delete, payment recording, WhatsApp share, PDF share.

## Phase 4: Verification Checklist

Automated:
1. `dart format lib test`
2. `flutter analyze`
3. `flutter test`

Manual smoke test:
1. Fresh app launch and bottom navigation.
2. Products:
   - add product
   - edit product
   - restock existing product
   - import CSV
   - filter/search/sort
   - bulk select and update
   - stock history
   - QR sheet open
3. Billing:
   - scan/manual add item
   - create bill
   - record payment
   - share bill/PDF
4. Store:
   - edit shop profile
   - category/supplier/customer CRUD
   - pricing defaults/category pricing
   - low-stock threshold
   - cloud setup panel opens
5. Production check:
   - `flutter build apk --release`

## Suggested Order Of Work

1. Product widgets/helpers extraction only. No behavior changes.
2. Product sheets extraction. No behavior changes.
3. New purchase page extraction. No behavior changes.
4. Store widgets/helpers extraction.
5. Store sheets extraction.
6. Scan and bills cleanup.
7. Optional: convert add/edit product from bottom sheet to full page if desired after the safe extraction is complete.

## Risk Notes

- The product add/edit sheet has many local variables and closures. Move it carefully as a callable function/widget with explicit inputs and callbacks instead of changing its logic during extraction.
- Private Dart names cannot be imported across files. During splitting, classes/functions that move must lose the leading `_` only when they are used by another file.
- Avoid circular imports by putting shared product models/formatters in small helper files.
- Run analyzer after each small move; it will catch missing imports, private-name access, and callback type mismatches quickly.
