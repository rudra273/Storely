# E03.3A Billing Calculation & Line/Document Controls Evidence

- **Feature/subfeature ID**: `F10`, `F11`, `F12`, `F13`, `F17` / Divergence `D09`
- **Owner phase/slice**: E03.3A
- **Contract**: [E03-billing-controls.md](../../contracts/E03-billing-controls.md)
- **Oracle fixtures**: `financial_contract_v1.json` (12 cases) + `financial_contract_v2.json` (14 manually authored cases covering tax-exclusive, mixed inclusive/exclusive lines, line `%`/`₹` discounts, fixed document discount proration, round-off modes `none`/`nearest`/`up`/`down` across `0.50`/`1.00`/`5.00`/`10.00`, and binary-float exactness)
- **API / mobile / web revisions**:
  - `storelyapi` (`dev`): `b04db72` (migration `0026_billing_controls`, `billing_math.py`, `billing.py`, `bills.py`, `invoice_pdf.py`, `private_sync.py`, `shops.py` capability `billing_controls: 1`)
  - `storelyweb` (`dev`): `7f5c47c` (regenerated `openapi.json` & `schema.d.ts`, `BigInt` paise `money.ts` & `hsnSummary`, `NewBill.tsx`, `InvoiceSettingsPage.tsx`, `InvoiceDocument.tsx`, `e2e/billing-controls.cjs`)
  - `Storely` (`package-com-storely`): this commit (pure Dart `ExactDecimal`, SQLite `v28 -> v29`, `BillTotals`, `Bill`/`BillItem`/`BillSettings`, `native_sale_posting.dart`, `ScanScreen`/`BillCheckoutSheet`/`BillSettingsScreen`, `integration_test/billing_controls_test.dart`)

## Gate Results

| Gate | Status | Evidence |
|---|---|---|
| Repo / domain checks (API) | **pass** | `make lint` (ruff/mypy strict/bandit: 0 errors); `make test` (438/438 passed, including all 12 v1 + 14 v2 oracle cases at 0.00 tolerance); `make vectors-check` (all 91 shared vectors match 100%). |
| Repo / domain checks (Web) | **pass** | `make typecheck` (0 errors); `make api-types-check` (up to date); `make test` (696/696 passed); `make build` (clean). |
| Repo / domain checks (Mobile) | **pass** | `flutter analyze` (0 issues); `flutter test` default + opt-in (`STORELY_NATIVE_SALE_POSTING=true`, 100/100 passed including `financial_contract_test.dart`, `billing_controls_test.dart`, `billing_vectors_test.dart`, `sync_data_contract_test.dart`, v28->v29 upgrade). |
| Docker integration | **pass** | `make migrate` applied `0026_billing_controls` cleanly; `make test-integration` passed **451/451** (including `test_billing_controls.py`, `test_authorization_matrix.py`, `test_command_capabilities.py`, `test_checkout_review.py`, `test_native_sale_*`). |
| Localhost browser | **pass** | Playwright (`e2e/billing-controls.cjs`) against `https://app.storely.localhost` with disposable GST-registered shop created `INV/2627/0001`: 2 × ₹100 (18% GST), 10% line discount, ₹10 fixed doc discount, exclusive tax, up ₹5 round-off -> verified `subtotal=200.00`, `discount=30.00`, `taxable=170.00`, `cgst=15.30`, `sgst=15.30`, `round_off=4.40`, `total=205.00`. |
| Android emulator | **pass** | `flutter test -d emulator-5554 integration_test/billing_controls_test.dart` (`01:14 +1: All tests passed!`) executed the exact same paired ₹100 × 2 / 18% GST / 10% line discount / ₹10 fixed doc discount / exclusive tax / up ₹5 round-off scenario and verified identical SQLite totals (`205.00`). |
| Cross-client reconciliation | **pass** | Exact 0.00-tolerance parity across API `Decimal`, Mobile `ExactDecimal`, and Web server-authoritative preview + `BigInt` paise display/HSN totals. |

## Migration / Retry / Offline / Permission Coverage
- PostgreSQL `0026_billing_controls` and SQLite `v28 -> v29` are purely additive with `round_off_mode` backfill from `round_off_total`; historical invoices are untouched.
- Checkout review fingerprint (`review_context`) binds all new document and line controls; legacy clients omitting new fields preserve v1 defaults identically.
- Human UX review belongs to E18.
