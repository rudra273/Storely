# E03.3A Billing Calculation & Line/Document Controls Contract

**Slice:** E03.3A  
**Feature IDs:** `F10`, `F11`, `F12`, `F13`, `F17`  
**Divergence IDs:** `D09`  
**Status:** Frozen for parallel implementation across `storelyapi`, `Storely` (mobile), and `storelyweb`.

## 1. Goals & Backward Compatibility

1. **Exact decimal parity (`D09`)**: API (`decimal.Decimal`), Mobile (pure Dart exact `BigInt` rational/decimal arithmetic — no IEEE-754 `double` drift in billing math), and Web (`BigInt` minor-unit helpers for display/balance/HSN totals; server-authoritative preview & post) produce identical paise results on both `financial_contract_v1.json` (12 cases) and `financial_contract_v2.json` (14 cases).
2. **Zero breaking changes for legacy clients/data**:
   - When new fields (`discount_mode`, `discount_value`, `line_discount_mode`, `line_discount_value`, `tax_mode`, `round_off_mode`, `round_off_increment`) are omitted, defaults match E01/v1 behavior identically (`discount_mode='percent'`, `line_discount_mode='percent'`, `line_discount_value=0`, `tax_mode='inclusive'`, `round_off_mode` from `bill_settings.round_off_total`, `round_off_increment=1.00`).
   - All existing `billing_vectors.json` and `financial_contract_v1.json` fixtures remain 100% green.
   - Historical invoices are never repriced or mutated.

## 2. Schema Changes

### 2.1 API PostgreSQL Migration (`0026_billing_controls`)
- `public.bill_settings`:
  - `default_tax_mode text not null default 'inclusive'` (`'inclusive'` | `'exclusive'`)
  - `round_off_mode text not null default 'nearest'` (`'none'` | `'nearest'` | `'up'` | `'down'`)
  - `round_off_increment numeric not null default 1.00` (allowed: `0.50`, `1.00`, `5.00`, `10.00`)
  - Backfill existing rows: `round_off_mode = case when round_off_total = 0 then 'none' else 'nearest' end`.
- `public.bills`:
  - `discount_mode text not null default 'percent'` (`'percent'` | `'amount'`)
  - `discount_value numeric not null default 0` (user-entered percent or fixed rupee amount)
  - `tax_mode text not null default 'inclusive'` (`'inclusive'` | `'exclusive'`)
  - `round_off_mode text not null default 'nearest'` (`'none'` | `'nearest'` | `'up'` | `'down'`)
  - `round_off_increment numeric not null default 1.00`
- `public.bill_items`:
  - `discount_mode text not null default 'percent'` (`'percent'` | `'amount'`)
  - `discount_value numeric not null default 0`
  - `discount_amount numeric not null default 0` (computed line-level discount in rupees, before document discount)
  - `tax_mode text` (nullable: `NULL` inherits `bills.tax_mode`; `'inclusive'` | `'exclusive'` overrides per line)

### 2.2 Mobile SQLite Migration (`version: 29`)
Add the exact same columns to `bill_settings`, `bills`, and `bill_items` (additive `ALTER TABLE` in `_ensureV29Columns` + `_createCleanSchema`). Update `Storely/test/sync_data_contract_test.dart` if needed and verify `sync_data_contract.json` stays in sync.

### 2.3 Held Carts (`private_sync.py`)
Allowlist optional fields in `CART_ITEM_FIELDS` (and `numeric_fields`):
- `discount_mode` (`'percent'` | `'amount'`)
- `discount_value` (numeric)
- `discount_amount` (numeric)
- `tax_mode` (`'inclusive'` | `'exclusive'` | null)

## 3. Canonical Math Specification (`D09`, `F10`, `F11`, `F12`, `F13`, `F17`)

All intermediate rates/ratios are computed in exact `Decimal` (API) or exact `BigInt` rational (Mobile). Money rounding (`round_money`) rounds to 2 decimal places (`0.01`) with `ROUND_HALF_UP` (half away from zero for both positive and negative values).

### 3.1 Per-Line Pre-Document-Discount Stage (`F12`)
For each line $i$ with `selling_price >= 0`, `quantity` ($> 0$ for sales; signed for return snapshots):
1. `subtotal_i = round_money(selling_price_i * quantity_i)`
2. If `line_discount_mode == 'percent'`:
   - Clamp `line_discount_value` to `[0, 100]`.
   - `line_factor = 1 - line_discount_value / 100`
   - `after_line_unit_i = selling_price_i * line_factor`
   - `after_line_base_i = round_money(after_line_unit_i * quantity_i)`
   - `line_discount_amount_i = round_money(subtotal_i - after_line_base_i)`
3. If `line_discount_mode == 'amount'`:
   - Validate `0 <= line_discount_value <= abs(subtotal_i)`.
   - Sign follows `quantity_i` (positive for sales).
   - `line_discount_amount_i = round_money(line_discount_value)` (signed for returns)
   - `after_line_base_i = round_money(subtotal_i - line_discount_amount_i)`
   - `after_line_unit_i = after_line_base_i / quantity_i` (or `0` if `quantity_i == 0`)

### 3.2 Document Discount Stage (`F10`, `F11`)
Let $B = \sum_i \text{after\_line\_base}_i$.
1. If `discount_mode == 'percent'` (default):
   - Clamp `discount_value` (or `discount_percent`) to `[0, 100]`.
   - `doc_factor = 1 - discount_value / 100`
   - For each line $i$: `discounted_unit_i = after_line_unit_i * doc_factor`
   - `after_doc_base_i = round_money(discounted_unit_i * quantity_i)`
   - Note: when `line_discount_value == 0` and `tax_mode == 'inclusive'`, this is **identical** to v1 `discounted_gross = selling_price * (1 - discount_percent / 100)`.
2. If `discount_mode == 'amount'` (fixed document discount $D \ge 0$):
   - Validate `0 <= D <= abs(B)` (reject with 422 / validation error if `D > abs(B)`).
   - Prorate $D$ across lines with `after_line_base_i != 0` in exact paise:
     - For each eligible line before the last eligible line: `d_i = round_money(D * after_line_base_i / B)`
     - For the last eligible line: `d_last = round_money(D - sum(d_prev))`
   - For each line $i$:
     - `after_doc_base_i = round_money(after_line_base_i - d_i)`
     - `discounted_unit_i = after_doc_base_i / quantity_i` (or `0` if `quantity_i == 0`)

### 3.3 Tax Extraction / Addition Stage (`F13`)
Effective line tax mode: `eff_mode_i = line.tax_mode ?? bill.tax_mode ?? 'inclusive'`.
Let `charged_i = gst_registered and gst_percent_i > 0`.
1. **`eff_mode_i == 'inclusive'`** (default):
   - `taxable_unit_i = discounted_unit_i / (1 + gst_percent_i / 100)` if `charged_i` else `discounted_unit_i`
   - `gst_unit_i = discounted_unit_i - taxable_unit_i` if `charged_i` else `0`
   - `line_amount_i = after_doc_base_i` (equals `round_money((taxable_unit_i + gst_unit_i) * quantity_i)`)
   - `total_taxable_value_i = round_money(taxable_unit_i * quantity_i)`
   - `total_gst_i = round_money(line_amount_i - total_taxable_value_i)`
2. **`eff_mode_i == 'exclusive'`**:
   - `taxable_unit_i = discounted_unit_i`
   - `gst_unit_i = discounted_unit_i * (gst_percent_i / 100)` if `charged_i` else `0`
   - `total_taxable_value_i = after_doc_base_i`
   - `total_gst_i = round_money(gst_unit_i * quantity_i)`
   - `line_amount_i = round_money(total_taxable_value_i + total_gst_i)`
3. **Intra/Inter Split** (per unit snapshots):
   - Intra-state: `cgst_unit = gst_unit_i / 2`, `sgst_unit = gst_unit_i / 2`, `igst_unit = 0`.
   - Inter-state: `cgst_unit = 0`, `sgst_unit = 0`, `igst_unit = gst_unit_i`.

### 3.4 Invoice Totals & Round-Off Stage (`F17`)
- `subtotal = sum(subtotal_i)`
- `line_discount_total = sum(line_discount_amount_i)`
- `total_after_doc_base = sum(after_doc_base_i)`
- `discount_amount = round_money(subtotal - total_after_doc_base)` (equals `line_discount_total + doc_discount_amount`)
- `taxable_amount = sum(total_taxable_value_i)`
- `net_amount = sum(line_amount_i)` (always equals `taxable_amount + cgst_amount + sgst_amount + igst_amount`)
- Intra-state GST split once at invoice level: `cgst_amount = round_money(intra_gst / 2)`, `sgst_amount = round_money(intra_gst - cgst_amount)`.
- Round-off with `round_off_mode` (`'none' | 'nearest' | 'up' | 'down'`) and `round_off_increment` (`0.50 | 1.00 | 5.00 | 10.00`):
  - `'none'`: `target = net_amount`
  - `'nearest'`: `q = round_half_away(net_amount / inc)`, `target = q * inc`
  - `'up'`: round magnitude away from zero to multiple of `inc` (exact multiples unchanged), preserving sign of `net_amount`.
  - `'down'`: round magnitude toward zero to multiple of `inc` (exact multiples unchanged), preserving sign of `net_amount`.
  - `round_off_amount = round_money(target - net_amount)`
  - `grand_total = round_money(net_amount + round_off_amount)`

## 4. API DTOs & Capability Advertisement

- Add capability `"billing_controls": 1` to `GET /v1/shops/{shop_id}/capabilities`.
- `InvoiceSettings` / `InvoiceSettingsIn`:
  - `default_tax_mode: Literal['inclusive', 'exclusive']` (default `'inclusive'`)
  - `round_off_mode: Literal['none', 'nearest', 'up', 'down']` (default `'nearest'`)
  - `round_off_increment: Decimal` (`0.50 | 1.00 | 5.00 | 10.00`, default `Decimal("1.00")`)
  - Keep `round_off_total: bool` synchronized with `round_off_mode != 'none'`.
- `CartItem`:
  - Optional `discount_mode: Literal['percent', 'amount'] = 'percent'`
  - Optional `discount_value: Decimal = Decimal(0)` (also accept `discount_percent`? Keep canonical `discount_mode` + `discount_value` so it's unambiguous; validate `<= 100` for percent, `>= 0` for amount).
  - Optional `tax_mode: Literal['inclusive', 'exclusive'] | None = None`
- `CartIn` (and `BillIn`):
  - Keep `discount_percent: Decimal = Decimal(0)` for backward compatibility.
  - Optional `discount_mode: Literal['percent', 'amount'] | None = None` (when omitted: `'percent'`).
  - Optional `discount_value: Decimal | None = None` (when omitted and `discount_mode == 'percent'`, falls back to `discount_percent`; when `discount_mode == 'amount'`, required `>= 0`).
  - Optional `tax_mode: Literal['inclusive', 'exclusive'] | None = None` (when omitted: `'inclusive'` for backward compatibility).
  - Optional `round_off_mode: Literal['none', 'nearest', 'up', 'down'] | None = None` (when omitted: shop `bill_settings.round_off_mode`).
  - Optional `round_off_increment: Decimal | None = None` (when omitted: shop `bill_settings.round_off_increment`).
- `Preview` / `BillSummary` / `PreviewLine` / `BillLine`:
  - Expose `discount_mode`, `discount_value`, `discount_amount`, `tax_mode`, `round_off_mode`, `round_off_increment` on bill summary/preview, and `discount_mode`, `discount_value`, `discount_amount`, `tax_mode` on lines.
- `NativeSalePreflightIn` / `NativeSalePostIn`:
  - Accept the new cart/line/bill fields, update `round_off_amount` bound to `[-10, 10]` (validated against `round_off_increment`), and update `_validate_recorded_sale_math` to validate the universal identities (`taxable + tax == net`, `net + round_off == total`, and `subtotal - discount == net - exclusive_gst`).
- `billing.review_context`:
  - Include `discount_mode`, `discount_value`, `tax_mode`, `round_off_mode`, `round_off_increment`, and line discount/tax_mode fields in the review fingerprint so reviewed-save guards detect any change.

## 5. UI Parity (Web & Mobile — Preserve Existing Theme & Checkout Flow)

- **Shop Invoice Settings** (Web `InvoiceSettingsPage`, Mobile `BillSettingsScreen`):
  - Default rate tax mode: `GST inclusive` / `GST exclusive` (applies to new bills).
  - Round-off mode: `None` / `Nearest` / `Round up` / `Round down` + increment (`₹0.50`, `₹1`, `₹5`, `₹10`) when mode != `None`.
- **Checkout / New Bill** (Web `NewBill.tsx`, Mobile `ScanScreen` + `BillCheckoutSheet`):
  - Per-line discount control (`%` or `₹` amount) and optional per-line tax mode (`Incl.` / `Excl.`) without cluttering the default cart row (inline compact edit or tap-to-edit line controls).
  - Document discount mode toggle (`%` vs `₹`) alongside the existing discount input.
  - Document tax mode selector (`Tax inclusive` / `Tax exclusive`, initialized from shop default `default_tax_mode`).
  - Document round-off override selector (`None` / `Nearest` / `Up` / `Down` + increment, initialized from shop default `round_off_mode` / `round_off_increment`).
  - Persist all new controls in checkout drafts (Web `BillDraft`, Mobile `checkout_draft_state` / `_BillDraft` / `HeldBill`).
  - Mobile `totalsFor` MUST pass real `gstRegistered` and `interState` when computing checkout preview (fixing the hardcoded `gstRegistered: false` shortcut that only worked for inclusive pricing).

## 6. Acceptance Scenarios

- `S-E03.3A-1`: Both API (`test_financial_contract.py`) and Mobile (`financial_contract_test.dart`) pass all 12 v1 + 14 v2 oracle cases with 0.00 tolerance.
- `S-E03.3A-2`: Docker integration test verifies create/preview/native-post/credit-note with exclusive tax mode, line `%` & `₹` discounts, fixed document discount, and `up`/`down`/`nearest` + `₹5`/`₹0.50` round-off, plus validation rejection when fixed discount exceeds subtotal.
- `S-E03.3A-3`: Localhost browser Playwright test creates an exclusive-tax bill with line discount + fixed document discount + `up` ₹5 round-off, verifies preview matches saved bill totals.
- `S-E03.3A-4`: Android emulator test creates the equivalent bill offline (or synced), verifies exact totals match the oracle and survive draft reload.
