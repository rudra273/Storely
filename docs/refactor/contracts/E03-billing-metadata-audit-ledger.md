# E03.3B Document Date/Series, Posted-Bill Metadata Edit, Audit & Stock Ledger Contract

**Slice:** E03.3B  
**Feature IDs:** `F02`, `F03`, `T19`, `A10`, `I10`  
**Status:** Frozen for parallel implementation across `storelyapi`, `Storely` (mobile), and `storelyweb`.

## 1. Schema Changes

### 1.1 API PostgreSQL Migration (`0027_e03_3b_billing_metadata`, `revision = "0027"`, `down_revision = "0026"`)
- `public.bills`:
  - `notes text` (nullable, max 500 chars validated at API layer).

### 1.2 Mobile SQLite Migration (`version: 29 -> 30`)
- `bills`:
  - `notes TEXT` (additive `ALTER TABLE bills ADD COLUMN notes TEXT` in `_ensureV30Columns` + `_createCleanSchema`).
- Update `Storely/docs/sync_data_contract.json` (and coordinator mirrors to `storelyapi/tests/fixtures/sync_data_contract.json`).

## 2. Feature Specifications

### 2.1 `F02` — Date/Time & Backdating
- **API**:
  - `BillIn` (`POST /v1/shops/{shop_id}/bills`) and `CartIn` (`POST /v1/shops/{shop_id}/bills/preview`): accept optional `bill_date: str | None = None` (ISO-8601 date `YYYY-MM-DD` or naive shop-local datetime `YYYY-MM-DDTHH:MM:SS`).
  - Reject timezone-aware datetimes, dates before `2000-01-01`, or datetimes > 5 minutes in the future (`422 invalid_bill_date`).
  - **Role guard**: If `bill_date[:10] < shop_today`, require `shops.ADMINS` (`owner`/`admin`); staff attempting to backdate receives `403 backdate_forbidden`.
  - When `bill_date` is date-only (`YYYY-MM-DD`), preserve current shop-local time-of-day if today, or `12:00:00.000` for past dates.
  - Use the resolved `placed_at` for `bills.created_at`, `bill_items.created_at`, `bill_payments.received_at`/`created_at`, `stock_movements.created_at`, and invoice series reset/FY calculation.
  - When backdated, record `backdated_to=<date>` in `audit_log` `created` details.
- **Mobile**:
  - Add optional `billDate` picker (`ValueKey('checkout-bill-date')`) in `BillCheckoutSheet` (visible/enabled for admins; defaults to today/now), persisted in `_BillDraft` and `checkout_draft_state`, passed as `createdAt` into `Bill(...)` on save.
- **Web**:
  - Add optional `Invoice date` input (`type="date"`, max = today) in `NewBill.tsx` (enabled when user has `billing.cancel`/admin role), persisted in `BillDraft`, sent as `bill_date` when set to a non-today date (or explicit).
  - Display date and time on `BillDetailPage.tsx` header (`when(b.created_at)`).

### 2.2 `F03` — Prefix / Number / Series
- **API**:
  - Extend `InvoiceSettings` and `InvoiceSettingsIn` (`GET/PATCH /v1/shops/{shop_id}/invoice-settings`):
    - `series_name: str` (default `'Default'`)
    - `format_template: str` (default `'INV/{FY}/{SEQ}'`, validated by `billing_math.validate_template` — max 16 chars, allowed tokens `{FY}`, `{YYYY}`, `{YY}`, `{MM}`, `{DD}`, `{SEQ}`, `{DEVICE}`)
    - `sequence_padding: int` (`1..8`, default `4`)
    - `reset_period: Literal['never', 'financial_year', 'monthly', 'daily']` (default `'financial_year'`)
    - `next_sequence: int` (`>= 1`, default `1`; on `PATCH`, updates the active counter in `invoice_counters` for the current period if `>= current_next`, rejecting downward regression if bills already exist in that period with `422 invalid_next_sequence`)
    - `next_bill_number_preview: str` (read-only computed preview on `GET`/`PATCH` response using `billing_math.format_number`)
  - Upsert default `public.invoice_series` row (`is_default = 1, is_active = 1`) on `PATCH` and bump `settings_revision`.
- **Web**:
  - Add `Invoice numbering` controls in `InvoiceSettingsPage.tsx` (template/prefix, padding, reset period, next sequence number, live preview) wired to `PATCH /v1/shops/{shop_id}/invoice-settings`.
- **Mobile**:
  - Add editable `Next invoice number` (`next_sequence`) input to `BillSettingsScreen` alongside existing template, padding, reset period, and preview; persist to `invoice_series.next_sequence`.

### 2.3 `T19` — Editing Posted Documents (Non-Financial Metadata)
- **API**:
  - Add `PATCH /v1/shops/{shop_id}/bills/{bill_id}` (`shops.ADMINS`, `require_premium=True`; MUST be registered in `tests/test_authorization_matrix.py`!).
  - Editable fields (`BillMetadataPatchIn`, `extra="forbid"`):
    - `customer_name: str | None`
    - `customer_phone: str | None`
    - `customer_gstin: str | None`
    - `customer_gst_legal_name: str | None`
    - `customer_gst_trade_name: str | None`
    - `customer_address: str | None`
    - `notes: str | None` (max 500 chars)
  - Rejects cancelled bills (`deleted_at IS NOT NULL`) with `409 bill_cancelled`.
  - Financial lines, totals, tax amounts, and `bill_number` remain strictly immutable.
  - Writes structured field-diff `edited` event to `public.audit_log` via `audit.record` + `audit.summarize_changes` and returns updated `BillDetail`.
  - Also accept optional `notes: str | None = None` on `BillIn` (`POST /v1/shops/{shop_id}/bills`) and expose `notes` on `BillSummary`.
- **Mobile**:
  - Persist `notes` on `Bill` (`bills.notes`, SQLite `v30`), add optional `Notes` field in `BillCheckoutSheet` (`checkout-notes`) and `_EditBuyerDetailsSheet` (`edit-bill-notes`), and include `notes` diff in `_logBillAudit`.
- **Web**:
  - Add optional `Notes` field in `NewBill.tsx` (persisted in `BillDraft`, sent on `POST /bills`) and display `notes` on `BillDetailPage.tsx` & `InvoiceDocument.tsx`.
  - Add `Edit details` button/dialog on `BillDetailPage.tsx` (admin-only, live non-cancelled bills) calling `PATCH /v1/shops/{shop_id}/bills/{bill_id}` to update customer metadata & notes and refresh the bill + history timeline.

### 2.4 `A10` — Audit & Security History
- **API**:
  - Extend `GET /v1/shops/{shop_id}/audit-events` with optional query parameters: `from_date` (alias `from`), `to_date` (alias `to`), and `action` (exact match).
  - Extend `GET /v1/shops/{shop_id}/security-events` with optional `limit` (`1..200`, default `100`) and `offset` (`>= 0`, default `0`), keeping response shape `list[ShopEventOut]` backward-compatible.
- **Web**:
  - Update `src/navigation.ts` label for `/activity` from `"Team activity"` to `"Activity & audit"` with accurate description.
  - Add `From` / `To` date filters on `ShopActivity.tsx` Business changes tab.
  - Add link to `/activity` from `InvoiceSettingsPage.tsx`.
- **Mobile**:
  - Add `getShopAuditLog({entityType, query, from, to, limit, offset})` in `lib/db/database_audit.dart`, and log local `product` edits and `stock` adjustments to `audit_log` so offline/local-only users have real shop-wide audit history.
  - Add `lib/screens/store/audit_log_screen.dart` (`Activity & audit` screen with entity-type filter chips, search, and chronological entries) reachable from `StoreScreen` (`Data & security` section, admin-only).

### 2.5 `I10` — Reorder / Low Stock & Stock Ledger
- **API**:
  - Add `GET /v1/shops/{shop_id}/stock-movements` (`shops.ANY_MEMBER`, `require_premium=True`; MUST be registered in `tests/test_authorization_matrix.py`!): shop-wide stock ledger across all products with optional `from`, `to`, `type` (`purchase|sale|adjustment|return|void|stocktake`), `q` (product name/code search), `limit` (`1..100`, default `25`), and `cursor`, returning `{items, next_cursor}` where each item includes `uuid`, `product_uuid`, `product_name`, `movement_type`, `quantity_delta`, `balance_after`, `reason`, `unit_cost` (admins only), `source_document_type`, `source_document_uuid`, `created_at`.
- **Web**:
  - Add a `Stock ledger` button/modal on `ProductsPage.tsx` backed by `GET /v1/shops/{shop_id}/stock-movements` with date/type/search filters and pagination.
- **Mobile**:
  - Enhance `_StockMovementHistorySheet` (`lib/screens/products/stock_history_sheet.dart`) with **running balance** (`balanceAfter`, computed cleanly from current stock backward or chronologically) and **movement type filter chips** (`All`, `Sale`, `Purchase`, `Adjustment`, `Return`, `Void`).

## 3. Capabilities & Acceptance

- Advertise `"billing_metadata": 1` in `GET /v1/shops/{shop_id}/capabilities`.
- `S-E03.3B-1`: API integration tests cover backdating (admin succeeds, staff 403, future rejected 422), series template/next_sequence update & preview, `PATCH /bills/{id}` metadata edit + audit diff + cancelled 409 + staff 403, `/audit-events` date filter, `/stock-movements` shop-wide ledger, and `test_authorization_matrix.py`.
- `S-E03.3B-2`: Localhost browser E2E edits invoice numbering in settings, creates a backdated bill with notes, edits its customer/notes on detail page, verifies audit history & shop-wide stock ledger.
- `S-E03.3B-3`: Android emulator/widget tests verify backdated bill with notes, posted-bill metadata edit + audit history, shop-wide `Activity & audit` screen, and stock ledger running balance + type filter.
