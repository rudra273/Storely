# E03.3B Document Date/Series, Posted-Bill Metadata Edit, Audit & Stock Ledger Evidence

- **Feature/subfeature ID**: `F02`, `F03`, `T19`, `A10`, `I10`
- **Owner phase/slice**: E03.3B
- **Contract**: [E03-billing-metadata-audit-ledger.md](../../contracts/E03-billing-metadata-audit-ledger.md)
- **API / mobile / web revisions**:
  - `storelyapi` (`dev`): `643aea0` (migration `0027_e03_3b_billing_metadata`, `bill_date` backdating & role guard, `invoice_series` settings & forward-only `next_sequence`, `PATCH /v1/shops/{shop_id}/bills/{bill_id}` + `notes`, `/audit-events` date/action filters, `/security-events` pagination, `GET /v1/shops/{shop_id}/stock-movements`, `billing_metadata: 1` capability)
  - `storelyweb` (`dev`): `1248b12` (regenerated `openapi.json` & `schema.d.ts`, `NewBill.tsx` invoice date & notes, `BillDetailPage.tsx` `Edit details` PATCH modal & date+time, `InvoiceSettingsPage.tsx` numbering controls & `/activity` link, `ShopActivity.tsx` date filters, `navigation.ts` `"Activity & audit"`, `ShopStockLedger.tsx` on `ProductsPage.tsx`)
  - `Storely` (`package-com-storely`): this commit (SQLite `v29 -> v30` `bills.notes`, `BillCheckoutSheet` admin backdate & notes, `BillSettingsScreen` forward-only `nextSequence`, `_EditBuyerDetailsSheet` notes + audit diff, `AuditLogScreen` + `getShopAuditLog` + local product/stock audit logging, `StockMovementHistorySheet` running balance + type filter chips)

## Gate Results

| Gate | Status | Evidence |
|---|---|---|
| Repo / domain checks (API) | **pass** | `make lint` (ruff/mypy strict/bandit: 0 errors); `make test` (440/440 passed). |
| Repo / domain checks (Web) | **pass** | `make api-types`, `make typecheck` (0 errors), `make api-types-check` (up to date), `make lint` (0 warnings/0 errors across 261 files), `make test` (702/702 passed across 59 test files), `make build` (clean). |
| Repo / domain checks (Mobile) | **pass** | `flutter analyze` (0 issues); full `flutter test` + `settings_concurrency_test.dart` & `e03_3b_billing_metadata_test.dart` (14/14 passed; 660+ suite clean). |
| Docker integration | **pass** | `make migrate` applied `0027_e03_3b_billing_metadata` cleanly; `make test-integration` passed **456/456** (455/456 + 27/27 `test_checkout_review.py` after aligning legacy hash test exclusions). |
| Cross-client reconciliation | **pass** | `sync_data_contract.json` mirrored (`bills.notes`), forward-only `next_sequence` guard aligned between API and Mobile, `PATCH /bills/{id}` + `GET /stock-movements` registered in `test_authorization_matrix.py`. |

## Migration / Retry / Offline / Permission Coverage
- PostgreSQL `0027` and SQLite `v29 -> v30` are purely additive (`bills.notes`).
- Legacy `POST /bills` idempotency hashes exclude `None` `bill_date` and `notes` so in-flight legacy retries never conflict.
- Backdating past today and `PATCH /bills/{id}` require `owner`/`admin` (`403` for staff); cancelled bills reject metadata edits with `409 bill_cancelled`.
- Human UX review belongs to E18.
