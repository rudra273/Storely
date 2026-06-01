
**P0 Blockers**
- Destructive DB upgrade: old app data is dropped for `oldVersion < 15` in [database_schema.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_schema.dart:21).  
  Real fix: write real migrations, backup before upgrade, and never auto-drop production tables.

- Cloud shop identity is hard-coded as `local-shop` in [database_helper.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_helper.dart:22) and [cloud_service.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/services/cloud_service.dart:98).  
  Real fix: generate a real shop UUID per business, migrate local data, and use that UUID everywhere.

- Cloud membership can auto-join existing shop as staff in [cloud_service.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/services/cloud_service.dart:452). With `local-shop`, this is dangerous.  
  Real fix: invitation/approval flow, server-side RLS, no automatic staff membership.

- Cloud sync is last-write-wins row sync, not domain-safe sync in [database_sync.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_sync.dart:194).  
  Real fix: server timestamps/versioning, dependency-aware batches, conflict rules per table, and reconciliation after sync.

- First cloud sync can discard local rows when joining an existing cloud shop because it pulls first, then only pushes local rows newer than sync start in [cloud_service.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/services/cloud_service.dart:364).  
  Real fix: explicit user choice: replace local, merge local, or backup and pull cloud.

- Invoice numbering uses `COUNT(*) + 1` instead of `invoice_series.next_sequence` in [database_bills.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_bills.dart:387).  
  Real fix: transactional sequence allocation from `invoice_series`, immutable numbers, device/server allocation rules.

- GST/tax math is not production-grade. Discount is not allocated into line taxable/GST totals in [scan_screen.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/screens/scan_screen.dart:271), and IGST is never used even though place of supply exists in [database_products.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_products.dart:501).  
  Real fix: line-level tax engine: taxable value after discount, CGST/SGST vs IGST, rounding rules, immutable snapshots.

**P1 High**
- Foreign keys are declared but likely not enforced because `openDatabase` has no `onConfigure` with `PRAGMA foreign_keys = ON` in [database_schema.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_schema.dart:7).  
  Real fix: enable FK enforcement and fix any failing delete/import paths.

- Product barcode/code uniqueness is only app-layer; DB indexes are non-unique in [database_schema.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_schema.dart:235).  
  Real fix: partial unique indexes for active products after duplicate cleanup.

- Inventory source of truth is split between `quantity_cache` and `stock_movements` in [database_schema.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_schema.dart:215).  
  Real fix: movement ledger as truth, rebuild cache from ledger, reconciliation after import/sync/void.

- Replace import is still an audit workaround: it soft-deletes old purchase movements in [database_products.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_products.dart:549).  
  Real fix: stocktake/replacement movement type and import batch table. Do not erase purchase history.

- Stock movement `source_type/source_id` is overloaded for suppliers in [database_sync.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_sync.dart:310).  
  Real fix: separate `supplier_uuid`, `source_document_uuid`, and `import_batch_uuid`.

- Import parser silently skips bad rows in [csv_importer.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/utils/csv_importer.dart:89) and strips negative signs in [csv_importer.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/utils/csv_importer.dart:536).  
  Real fix: validate all rows, show row-level errors, reject negative/invalid quantities/prices explicitly.

- Duplicate import row handling sums quantity but keeps only one row’s price/supplier in [database_products.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_products.dart:700).  
  Real fix: preserve each import row as a purchase line/movement.

- Marking a partially paid bill as paid inserts a full total payment, causing overpayment in [database_bills.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_bills.dart:259).  
  Real fix: insert only remaining balance or replace payment state intentionally.

- Unknown QR JSON becomes a bill item with arbitrary name/price in [scan_screen.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/screens/scan_screen.dart:112).  
  Real fix: signed QR or DB lookup by UUID/code only; explicit permission-gated non-stock manual item flow.

- Staff permissions are mostly UI-level. Product/store mutations are still callable without service-layer role checks, for example product delete in [products_screen.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/screens/products_screen.dart:2489).  
  Real fix: central permission guard in database/service layer plus server RLS.

**P2 Important**
- KPI “revenue by payment method” includes unpaid bills in [database_kpi.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_kpi.dart:41).  
  Real fix: separate sales booked, cash collected, revenue, receivables.

- Today sales also sums unpaid bills in [database_bills.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_bills.dart:345).  
  Real fix: show “sales” vs “collected” separately.

- Non-GST registered pricing still stores `gstAmount` as purchase GST in [pricing.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/models/pricing.dart:206), and KPI calls it collected GST in [database_kpi.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/db/database_kpi.dart:250).  
  Real fix: split input tax/cost from output GST collected.

- App onboarding is controlled by `SharedPreferences` only in [main.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/main.dart:181).  
  Real fix: gate by real shop/profile/data readiness.

- PDF generation uses default PDF fonts in [bill_pdf_generator.dart](/Users/rudrapratapmohanty/Desktop/projects/Storely/lib/utils/bill_pdf_generator.dart:15). Rupee/local text can render badly.  
  Real fix: bundle Noto Sans or another Unicode font and use it in all PDFs.

My senior-dev call: do not ship production with cloud sync enabled until P0 is fixed. If this is local-only beta, you can defer some cloud items, but invoice numbering, migration safety, tax calculation, and inventory ledger consistency still need real fixes before serious users touch it.