# Storely Release 1.0.3 Plan

Prepared: 2026-05-31
Current app version: 1.0.2+3
Target release: 1.0.3

## Goal

Release 1.0.3 should upgrade Storely billing for shop owners who need more GST-ready invoices, custom bill numbering, and partial payments. This release should be schema-backed, sync-safe, and future-ready for e-invoicing, without screen-only workarounds or scraping government portals.

## Requested Features

1. Show HSN/SAC code on bills when required.
2. Capture and show customer GSTIN for B2B bills when required.
3. Capture customer business details manually from GSTIN information for now.
4. Add owner-configurable bill number formats and allow selecting a format while creating a bill.
5. Support partial payment instead of only paid/unpaid.

## Current Storely State

- Local database version is 15 in `lib/db/database_schema.dart`.
- App version is `1.0.2+3` in `pubspec.yaml`.
- `products` currently store `gst_percent`, but not HSN/SAC.
- `bill_items` snapshot prices and GST amount, but not GST rate, taxable value, HSN/SAC, or tax split.
- `customers` currently store name, phone, email, address, notes, totals, and bill count, but not GSTIN.
- `bills` currently store `bill_number`, customer name/phone snapshots, `is_paid`, and one `payment_method`.
- Cloud sync includes `customers`, `products`, `bills`, and `bill_items`, so every new table/column must be added to both local SQLite and Supabase schema.

## Compliance Notes From Research

- The GST portal allows taxpayer search by GSTIN/UIN without login and shows public details such as legal name, trade name, registration status, principal place of business, and cancellation date. The public pre-login flow requires captcha, so it is not suitable for automatic API integration.
- GST invoice fields include supplier GSTIN, consecutive serial number unique for the financial year, date, registered recipient GSTIN/UIN, recipient details for unregistered recipients in some cases, HSN code, description, quantity/unit, value, tax rate, tax amounts, and invoice value.
- GSTN HSN reporting has turnover-based digit requirements. Storely should not hard-code one universal HSN length. It should store the shop's turnover/compliance setting and validate based on that setting.
- E-invoicing is a separate compliance layer. For affected taxpayers, B2B invoices require IRN/QR handling through an Invoice Registration Portal flow. That is not part of 1.0.3 unless explicitly added, but 1.0.3 data fields should not block a later e-invoice module.

Sources:

- GST portal taxpayer search manual: https://tutorial.gst.gov.in/userguide/taxpayersdashboard/Search_Taxpayer_manual.htm
- E-invoice printing and mandatory invoice fields: https://einvoice6.gst.gov.in/content/e-invoice-printing-process-mandatory-fields-modes-of-irn-generation/
- GSTN HSN advisory PDF: https://tutorial.gst.gov.in/downloads/news/hsn_advisory_table_12_2.pdf
- GSTN GSP ecosystem: https://www.gstn.org.in/gsp-ecosystem

## Product Decisions

### 1. GSTIN Business Details

Automatic customer detail fetch is possible later, but Storely 1.0.3 will not include GSTIN lookup/API code. Owners will enter GSTIN and business details manually.

For 1.0.3:

- Include local GSTIN validation for free: format, state code, PAN segment, entity code, and checksum.
- Do not add GSTIN lookup provider code in this release.
- Do not scrape `gst.gov.in` taxpayer search because the public flow uses captcha and is not stable for production.
- Allow manual entry of customer GSTIN, legal name, trade name, address, registration status, and verification date.

Recommended release stance:

- 1.0.3 ships manual GSTIN capture plus local validation.
- A future 1.0.4 or 1.1.0 can enable paid/provider lookup after choosing vendor, pricing, rate limits, consent wording, and privacy policy updates.

### 2. B2B Billing

Add an explicit bill type:

- `b2c`: default for walk-in or unregistered customers.
- `b2b`: requires customer GSTIN and business name.

The create bill sheet should expose a simple toggle: `Customer type: B2C / B2B`. When B2B is selected, show GSTIN and business fields. Existing customer selection should prefill GSTIN if available.

### 3. HSN/SAC

Add HSN/SAC at product/category level and snapshot it into bill items at billing time.

Do not depend on live product data for old invoices. Invoices must remain historically correct even if product HSN, GST rate, or price changes later.

### 4. Bill Number Patterns

Owners should be able to create multiple invoice series and choose one while generating a bill.

Important constraint: Storely has offline/local billing plus cloud sync. A single shared bill sequence across multiple devices cannot be guaranteed while fully offline unless each device has a reserved range or device-specific prefix. For a standard implementation, support two modes:

- `local_device`: works offline, requires a device/terminal token in the format to avoid duplicates.
- `cloud_shared`: single shop-wide sequence, requires online allocation at final billing time.

Default for 1.0.3 should remain an offline-safe local-device series unless the shop explicitly chooses cloud-shared numbering.

### 5. Partial Payments

Replace the business meaning of `is_paid` with a derived payment status:

- `unpaid`: paid amount is 0.
- `partial`: paid amount is greater than 0 and less than bill total.
- `paid`: paid amount equals bill total.
- `overpaid`: paid amount exceeds bill total, blocked by default unless later store-credit support is added.

Keep `is_paid` temporarily for backward compatibility and sync migration, but new UI and reports should use payment records and derived status.

## Data Model Plan

### Products

Add:

- `hsn_code text`
- `hsn_type text` with values `goods`, `services`, or `unknown`
- `hsn_description text`

### Categories

Add optional defaults:

- `hsn_code text`
- `hsn_type text`
- `hsn_description text`

### Customers

Add:

- `gstin text`
- `gst_legal_name text`
- `gst_trade_name text`
- `gst_registration_status text`
- `gst_taxpayer_type text`
- `gst_verified_at text`
- `gst_source text` with values `manual`, `api`, or `import`
- `place_of_supply_state_code text`

### Bills

Add invoice/customer tax snapshots:

- `bill_type text not null default 'b2c'`
- `customer_gstin text`
- `customer_gst_legal_name text`
- `customer_gst_trade_name text`
- `customer_address_snapshot text`
- `place_of_supply_state_code text`
- `taxable_amount double precision not null default 0`
- `cgst_amount double precision not null default 0`
- `sgst_amount double precision not null default 0`
- `igst_amount double precision not null default 0`
- `paid_amount double precision not null default 0`
- `balance_due double precision not null default 0`
- `payment_status text not null default 'unpaid'`
- `invoice_series_uuid text`

### Bill Items

Add immutable tax snapshots:

- `hsn_code_snapshot text`
- `hsn_type_snapshot text`
- `gst_percent_snapshot double precision`
- `taxable_value_snapshot double precision not null default 0`
- `cgst_amount_snapshot double precision not null default 0`
- `sgst_amount_snapshot double precision not null default 0`
- `igst_amount_snapshot double precision not null default 0`

### Invoice Series

Create `invoice_series`:

- `uuid text primary key`
- `shop_id text not null`
- `name text not null`
- `format_template text not null`
- `sequence_padding integer not null default 4`
- `reset_period text not null default 'financial_year'`
- `allocation_mode text not null default 'local_device'`
- `next_sequence integer not null default 1`
- `is_default integer not null default 0`
- `is_active integer not null default 1`
- `device_token_required integer not null default 1`
- `last_sequence_key text`
- `device_id text`
- `created_at text not null`
- `updated_at text not null`
- `deleted_at text`

Template tokens:

- `{YYYY}` calendar year
- `{YY}` short calendar year
- `{FY}` Indian financial year, for example `2026-27`
- `{MM}` month
- `{DD}` day
- `{SEQ}` padded sequence
- `{DEVICE}` terminal/device token
- `{SHOP}` optional shop short code

Example formats:

- `INV/{FY}/{SEQ}`
- `GST/{FY}/{SEQ}`
- `{SHOP}/{DEVICE}/{YYYY}{MM}/{SEQ}`

Validation:

- Final bill number must be unique per shop.
- GST invoice serial number must not exceed 16 characters if the shop uses GST tax invoice mode.
- For `local_device`, require `{DEVICE}` or a device-specific series.
- For `cloud_shared`, require online central allocation.

### Payments

Create `bill_payments`:

- `uuid text primary key`
- `shop_id text not null`
- `bill_uuid text not null`
- `amount double precision not null`
- `payment_method text not null`
- `payment_reference text`
- `notes text`
- `received_at text not null`
- `device_id text`
- `created_at text not null`
- `updated_at text not null`
- `deleted_at text`

Rules:

- New bills can be created as unpaid, partially paid, or fully paid.
- Payment amount cannot be negative.
- Payment amount cannot exceed balance unless future store-credit support is implemented.
- Deleting/voiding a bill should soft-delete or reverse payment rows consistently.
- Reports must use active payment rows, not the old boolean.

## Migration Plan

1. Bump local database version from 15 to 16.
2. Add non-destructive `ALTER TABLE` migrations for all new columns.
3. Create `invoice_series` and `bill_payments` tables locally.
4. Seed a default local-device invoice series matching the current `SHOP-LOCAL-local-YYYYMMDD-0001` behavior.
5. Backfill existing bills:
   - `bill_type = 'b2c'`
   - `payment_status = 'paid'` when `is_paid = 1`, otherwise `unpaid`
   - `paid_amount = total_amount` when `is_paid = 1`, otherwise 0
   - `balance_due = total_amount - paid_amount`
6. Create a migration payment row for each existing paid bill, using the old `payment_method`.
7. Update `supabase/storely_cloud_schema.sql` with the same columns/tables and indexes.
8. Add `invoice_series` and `bill_payments` to `storelyCloudTables`.
9. Extend cloud map conversion only where local IDs need UUID mapping.

## UI Plan

### Product And Category Screens

- Add optional HSN/SAC field.
- Add GST rate and HSN together in tax section.
- Show validation warning based on shop HSN setting.
- Allow category-level default HSN and product override.

### Customer Screen

- Add GSTIN field.
- Add business legal name/trade name fields.
- Add state/place of supply.
- Show validation status: `Not verified`, `Format valid`, `Verified manually`, or `Verified by provider`.

### Create Bill Sheet

- Add bill type selector: B2C / B2B.
- Add customer GSTIN fields when B2B is selected.
- Add invoice series dropdown.
- Add bill number preview before final generation.
- Replace Paid/Unpaid toggle with:
  - `Unpaid`
  - `Paid full`
  - `Partial`
- For Partial, show amount received and payment method.

### Bills Screen

- Show status chips: Paid, Partial, Unpaid.
- Show paid amount and balance due.
- Add `Record payment` action for unpaid/partial bills.
- Keep `Mark paid` as a shortcut that creates a payment row for the remaining balance.

### PDF / Share Output

- Add customer GSTIN and legal name for B2B bills.
- Add HSN/SAC column when shop is GST registered or when any item has HSN.
- Add taxable value, GST rate, CGST/SGST/IGST amounts where available.
- Add paid amount and balance due.
- Keep old bills readable even if they lack HSN snapshots.

## Services Plan

### GSTIN Validation Service

Create a local validator:

- `isValidFormat(gstin)`
- `stateCode(gstin)`
- `panPart(gstin)`
- `checksumValid(gstin)`
- `normalise(gstin)`

### GSTIN Lookup Service

Deferred. Do not add provider/no-op lookup code in 1.0.3. Keep the manual GSTIN and business detail fields clean so a future provider can fill the same fields without another data migration.

## Reporting Plan

Update dashboard and KPIs:

- Sales total should continue using bill total.
- Collection total should use bill payments.
- Outstanding amount should use bill balance due.
- Customer profile should show total purchase, paid amount, and due amount.
- Unpaid list should include partial bills.

## Test Plan

Unit tests:

- GSTIN format/checksum validation.
- HSN validation rules by shop setting.
- Invoice series rendering and sequence reset.
- Payment status derivation from payment rows.
- Backfill migration from old `is_paid` bills.

Database tests:

- Local version 15 to 16 migration preserves existing bills.
- Unique bill number constraint is enforced.
- `bill_payments` sync/import/export works.
- Soft-deleted payments do not count toward paid amount.

Widget tests:

- Create B2B bill with GSTIN.
- Create partial payment bill.
- Record later payment and status changes from partial to paid.
- Select alternate invoice series.

Manual QA:

- Generate B2C bill PDF.
- Generate B2B GST bill PDF with HSN and customer GSTIN.
- Create bills offline using local-device series.
- Sync two devices and verify no duplicate local-device bill numbers.
- Cloud-shared series blocks or waits when offline.

## Release Phases

### Phase 1: Foundation

- Schema migration.
- Models and sync changes.
- GSTIN validation service.
- Invoice series model/service.
- Payment ledger model/service.

### Phase 2: Billing Flow

- Create bill sheet changes.
- Bill insertion snapshots for GSTIN/HSN/tax/payment.
- Default series seed and bill number preview.

### Phase 3: Bills, Customers, PDF

- Bills screen status/actions.
- Customer GSTIN and due tracking.
- PDF and share text updates.

### Phase 4: QA And Release

- Automated tests.
- Manual PDF review.
- Migration testing from 1.0.2 database.
- Supabase schema verification.
- Bump `pubspec.yaml` to `1.0.3+4`.

## Open Questions

1. Should 1.0.3 support only Indian GST, or should tax fields be named generically enough for future regions?
2. Do owners need e-invoice/IRN in this release, or only GST-ready printable bills?
3. Should cloud-shared bill numbering be allowed to block bill creation when offline?
4. Which GSTIN API provider should be evaluated later for auto-fetch: GSP/ASP provider, existing Supabase edge function integration, or another paid verification API?
5. Do shops need separate series for tax invoice, estimate/quotation, credit note, and return bill?
6. Should staff be allowed to change invoice series and customer GSTIN, or should those actions be owner/admin only?

## Recommended Scope For 1.0.3

Ship:

- Manual customer GSTIN capture with local validation.
- B2B/B2C bill type.
- Product/category HSN/SAC and bill item snapshots.
- Configurable invoice series with offline-safe local-device default.
- Partial payments through a real payment ledger.
- Updated bill PDF/share output.
- Local and Supabase migrations.

Defer:

- Automatic GSTIN detail fetch and any provider integration until provider/pricing is selected.
- E-invoice IRN/QR generation.
- GSTR filing/export automation.
- Store-credit/overpayment workflows.

## Acceptance Criteria

- A shop owner can create a B2B bill with customer GSTIN and HSN visible on PDF.
- A shop owner can configure at least two bill number formats and choose one during billing.
- Bill numbers remain unique per shop under the selected allocation mode.
- A bill can be created with partial payment and later settled.
- Old bills from 1.0.2 remain visible and migrate without data loss.
- Cloud sync handles the new tables/columns.
- No GST portal scraping is used.
