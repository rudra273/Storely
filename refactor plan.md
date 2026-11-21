# Storely end-to-end refactor plan

**Prepared:** 17 November 2026. **Scope:** Flutter mobile, React web, FastAPI/PostgreSQL, SQLite/offline sync, data migration, business workflows and operational acceptance. **Deliverable status:** source-based comparison and implementation plan; no application code changed and no runtime acceptance claimed.

## 1. Outcome and non-negotiable requirements

Make Storely one coherent business product across mobile and web. Preserve the existing visual identity, theme, typography, colors and reusable UI components. Refactor the sequence of business actions, field semantics, defaults, validation, state transitions, calculations, permissions, persistence and recovery. Implement missing business capabilities through the same workflow on both clients.

“Same flow” means the same entry action, logical steps, required information, default values, validation order, confirmation, result, follow-up actions and error recovery. A wide layout versus a narrow layout is acceptable; silently skipping a step, choosing a different default, supporting an action on only one client, or producing different figures is not. Keep the existing application shell and theme; introduce shared logical steps within it.

Keep Flutter, React, FastAPI and the existing databases. Extract domain behavior incrementally rather than replacing all three applications. Keep Storely's useful existing work: sales returns, stock ledger, purchase composer, import replay protection, supplier accounting, tenant isolation, MFA, premium activation, local backup and sync.

Existing product constraints remain: free mobile works locally without an account; premium enables cloud sync and web. Web remains cloud-dependent under the existing architecture. This creates unavoidable availability differences, which must be explicit, not different business rules. Offline mobile operations use the same command and state model with a visible pending-sync state. Do not silently turn this request into a web offline/PWA rewrite or remove local-only operation. If identical offline availability on web is required too, that is an additional storage/auth/sync work package, not a completed property of this plan.

This document is the new refactor backlog; the existing `plan.md` remains the historical server-migration plan. Existing implementation documents are evidence, not proof that a feature is complete. This request authorizes this plan, not production changes or deployment.

## 2. Evidence, coverage and interpretation

### 2.1 Reference boundary

`/Users/rudra/projects/vyapar-rea` contains eleven Markdown evidence documents, not a runnable source application. Its `CLONE_SPEC.md` describes **Vyapar Android 32.2.0 / build 733**, analyzed statically. It explicitly says the UI was not opened, traffic was not captured and many formulas, feature gates and runtime transitions are unknown. The 273 activity/alias declarations and 1,084 XML variants are not 273 or 1,084 independently verified product features.

The comparison below covers the business families, form fields, settings, reports and integrations described by that corpus, plus Storely's implemented source contracts. Missing means **no implementation found in the inspected Storely application/schema/route surfaces**, not proof that no hidden code or deployed service exists. Presence means implementation exists, not that every branch was executed. Vyapar declarations and message-only evidence remain candidates; do not invent exact competitor behavior to fill gaps.

No test suite, live app, production database, physical printer or external integration was exercised in this planning audit. The acceptance plan below is future work. Exact regulatory formulas and provider behavior must be verified against the applicable current official specifications during implementation; this document does not establish compliance.

### 2.2 Source map

Paths below are relative to these roots: **M** `/Users/rudra/projects/Storely`; **W** `/Users/rudra/projects/storelyweb`; **A** `/Users/rudra/projects/storelyapi`; **V** `/Users/rudra/projects/vyapar-rea`.

| Evidence key | Inspected source anchors and what they establish |
|---|---|
| V0 | V `CLONE_SPEC.md`: evidence levels, pinned version and unresolved coverage. |
| V1 | V `BUSINESS_RULES.md`: documents, fields, guards, parties, items, finance, tax and loyalty. |
| V2 | V `APP_FLOWS.md`: onboarding, companies, recycle bin, field sales, reports and secondary modules. |
| V3 | V `SETTINGS.md`: behavioral toggles, invoice output controls, messaging and settings scope. |
| V4 | V `STORAGE_AND_SYNC.md`: file formats, import/export, backup, sync boundaries and schema inventory. |
| V5 | V `DOCUMENT_OUTPUT.md`: preview/share/print and device transport evidence. |
| V6 | V `SCREEN_REGISTRY.md`, `ENTRY_POINTS.md`, `XML_SURFACES.md`: declared surface/control inventory; not runtime reachability proof. |
| V7 | V `ERROR_CATALOG.md`: candidate validation, empty, waiting and failure states. |
| V8 | V `ADVERTISING_MODULE.md`: Smart Ads screens/routes, fields and integrations; largely static candidates. |
| S1 | M `lib/screens/scan_screen.dart`, `screens/scan/bill_checkout_sheet.dart`, `models/bill_totals.dart`, `db/database_bills.dart`; W `src/billing/NewBill.tsx`, `checkout/*`, `BillActions.tsx`; A `app/routers/bills.py`, `domains/billing/billing.py`, `billing_math.py`: sale, payment, return and cancellation. |
| S2 | M `lib/models/product.dart`, `models/pricing.dart`, `db/database_products.dart`, `screens/products/*`; W `src/products/*`; A `app/routers/catalog.py`, `domains/catalog/*`: product, pricing, import, bulk changes and stock. |
| S3 | M `lib/screens/products/new_purchase_screen.dart`, `models/purchase_document.dart`, `db/database_purchase_documents.dart`, `screens/purchase_history_screen.dart`; W `src/purchases/*`; A `app/routers/purchases.py`, `domains/purchases/purchase_contract.py`, `native_purchases.py`, `corrections.py`, `payment_terms.py`: purchase receipt lifecycle. |
| S4 | M `lib/screens/supplier_payments_screen.dart`, `db/database_purchase_documents.dart`; W `src/products/suppliers/*`; A `app/routers/supplier_payments.py`, `domains/purchases/supplier_payments.py`, `supplier_payment_math.py`: supplier balances, allocations and reversals. |
| S5 | M `lib/models/customer.dart`, `models/supplier.dart`, `screens/customer_profile_sheet.dart`, `screens/shared/record_payment_dialog.dart`; W `src/customers/CustomersPage.tsx`; A `app/routers/customers.py`, `domains/customers/customers.py`: customer accounts, collections, statements. |
| S6 | M `lib/db/database_reports.dart`, `screens/reports_screens.dart`, `screens/analytics_screen.dart`, `services/gstr1_export.dart`; W `src/reports/*`; A `app/routers/reports.py`, `domains/reports/reports.py`, `gstr1.py`: implemented reports and exports. |
| S7 | M `lib/models/bill_settings.dart`, `screens/store/bill_settings_screen.dart`, `utils/bill_pdf_generator.dart`, `services/thermal/*`; W `src/billing/invoice/*`, `ShareDialog.tsx`; A `app/domains/billing/invoice_pdf.py`, `templates/invoice.html`: document output. |
| S8 | M `lib/services/sync/*`, `db/database_sync.dart`, `services/backup_service.dart`, `services/portable_preferences_service.dart`; W `src/lib/drafts.ts`, `src/purchases/composer/draft.ts`; A `app/domains/sync/*`, `migrations/sql/0010_complete_sync.sql`, `0016_native_purchase_sync.sql`: persistence, draft and sync architecture. |
| S9 | M `lib/services/cloud_service.dart`, `screens/store/cloud_setup_sheet.dart`, `screens/shared/cloud_account_dialogs.dart`, `services/app_lock_service.dart`; W `src/App.tsx`, `permissions.ts`, `auth/*`, `shops/*`, `subscriptions/*`, `platform/*`; A `app/auth/*`, `domains/shops/*`: account, access and entitlement flows. |
| S10 | M `lib/models/expense.dart`, `db/database_expenses.dart`, `screens/expenses_screen.dart`; W `src/customers/ExpensesPage.tsx`; A `app/domains/customers/expenses.py`, `routers/customers.py`: expense CRUD. |
| S11 | M `lib/db/database_schema.dart`; A `migrations/sql/0003_storely_schema.sql`, `0014_purchase_documents.sql`, `0018_supplier_payments.sql`, `0019_purchase_corrections.sql`, `0020_purchase_payment_terms.sql`: entity and migration boundaries. |

Search boundary for absent modules: mobile `lib`, web `src` excluding generated API types/test files for absence searches, API `app` and SQL migrations. Searches for quotations/proforma/challans, orders, loyalty, unit conversions, manufacturing, opening balances/credit limits, wholesale pricing, recycle bin and closing books found no corresponding domain implementation. “Serial number” in invoice column settings means row numbering, not inventory serial/IMEI tracking. “Bank transfer” as a payment method is not a bank ledger. A storefront icon is not an online store.

### 2.3 Storely source snapshot

At plan completion: mobile HEAD `da24630`, web HEAD `6de0488`, API HEAD `8663a09`. Web/API working trees were clean. Mobile had a pre-existing untracked `node_modules/` directory; this task adds only this plan. These hashes identify the inspected checkout versions, not deployed build versions.

The comparison contains **145 feature rows**, **15 source-level divergence rows**, and an appendix mapping **273 native reference declarations**. Rows are scoped capabilities, not a count of missing features; partial/unknown items must not be counted as fully absent.

### 2.4 Status notation

- **E**: existing implementation for the stated slice; behavior still needs parity acceptance.
- **P**: partial implementation or a narrower equivalent.
- **N**: not found within the search boundary.
- **D**: confirmed source-level divergence between clients or client/server.
- **U**: unresolved; evidence does not establish the behavior.

Columns **M/W/A** refer to mobile/web/API. A module can be E while its advanced subfeatures are N. Phase identifiers refer to section 9. Rows marked N are feature implementation work, not merely code cleanup.

## 3. Confirmed differences to fix before expanding features

| ID | Observation and exact source anchor | Consequence and required change |
|---|---|---|
| D01 | M `lib/screens/scan_screen.dart:547` opens `_BillCheckoutSheet`; W `src/billing/NewBill.tsx` combines the cart, customer and payment form. | Business steps are presented differently. Adopt the same logical Item → Party/details → Settlement/review → Save/result sequence on both, retaining existing components. |
| D02 | M `lib/screens/scan/bill_checkout_sheet.dart:42` defaults `_paymentStatus` to paid; W `src/billing/NewBill.tsx` initializes `paid` to null. | An untouched checkout can imply payment on one client but require a decision on the other. Default to an explicit payment choice on both, with a future shared cash-default setting if desired. |
| D03 | M `lib/db/database_reports.dart:471` values positive stock at raw `purchase_price`; A `app/domains/reports/reports.py:643` includes nonzero quantities and calls `resolve_price`, including overhead/nonrecoverable purchase tax. | Same shop can produce different stock value and row counts. Define cost basis and negative-stock presentation once; add shared fixture before changing either implementation. |
| D04 | M `lib/screens/scan_screen.dart:171` implements multiple held bills; W `src/billing/NewBill.tsx` persists a single active draft with no equivalent held-cart list. | Cashier workflow differs. Add Hold, list, resume, discard and atomic consume semantics on both. |
| D05 | Mobile draft persistence in `scan_screen.dart:125` serializes cart items; web `BillDraft` includes customer, payment, discount and uncertain save attempt. | Different recovery coverage. Persist the complete logical draft, including current step and frozen operation identity, on both. |
| D06 | M `lib/screens/purchase_history_screen.dart` displays receipt details and a “not recorded” payment explanation. W `src/purchases/PurchaseDetailPage.tsx:41` exposes Pay supplier, Reverse purchase and Record payment terms. | Purchase correction/payment-term actions are not exposed equivalently on mobile. Add matching actions and guard outcomes using the existing API domain rules. |
| D07 | M `lib/screens/supplier_payments_screen.dart` queues date/amount/method and says sync to confirm. A `SupplierPaymentIn` also supports reference, notes and a specific `purchase_uuid`; W supplier payment UI uses the richer flow. | Align input fields, allocation review, receipt-specific payment and result states. Pending is not the same as server-confirmed payment. |
| D08 | M supplier accounting computes from locally available purchase snapshots and payment queue; web/API use server statement/ledger results. | Show data freshness and pending amounts separately. After convergence, confirmed balances must match exactly. |
| D09 | Mobile `Product`/`BillTotals` use doubles plus tolerances; server billing uses Decimal; purchases already use decimal text/integer arithmetic in parts. | Existing vectors reduce risk but do not eliminate all future precision drift. Introduce versioned decimal contracts and migrate incrementally, preserving historical snapshots. |
| D10 | A sale `Quantity` permits 3 decimal places; purchase contract permits 4. Product stock checks use a floating tolerance. | Precision policy is not universal. Define quantity scale by unit and transaction, with explicit conversion/rounding and identical UI validation. |
| D11 | A billing payment enum uses `bank`; purchases use `bank_transfer`. | Normalize the domain payment-method identity with backward-compatible wire aliases; keep historical rows readable. |
| D12 | W `src/lib/drafts.ts` silently ignores storage failures and expires drafts after seven days; purchase composer blocks confirmation when persistence fails and detects cross-tab changes. | Apply one durable recovery policy. Never suggest an uncertain financial operation is safely recoverable if its key/body was not persisted. |
| D13 | Mobile thermal service lists paired Bluetooth printers and emits ESC/POS; web prints/downloads documents through browser mechanisms. | Same Print intent/settings/result/error workflow, separate hardware adapters. Do not promise silent direct browser Bluetooth/USB access without a supported bridge. |
| D14 | Mobile has EN/HI localization resources; inspected web business UI contains inline English text. | Align supported business labels, validations and document-language choices without changing theme. |
| D15 | Mobile row sync plus atomic purchase snapshots coexist; web uses REST commands. | Extend atomic business-command sync to financial changes; raw row upserts must not become an alternate way to bypass new domain guards. |

These are code observations, not claims that a user-visible failure was reproduced. D03 is a direct formula mismatch; D09 is an architectural risk, not proof every existing invoice is wrong.

## 4. Feature-by-feature comparison and missing work

### 4.1 Account, company, permissions and shell — V2/V3/V6 versus S9/S11

| ID | Feature | M/W/A | Existing difference or required work | Phase |
|---|---|---|---|---|
| A01 | Email/password, verification, reset, sessions, MFA | E/E/E | Preserve existing security; use identical account recovery states and role-loss handling. | P1 |
| A02 | Phone OTP / Google sign-in | N/N/N | Reference has OTP/Google branches. Existing Storely decision is email/password; backlog candidate, not a prerequisite for accounting parity. | P9 |
| A03 | Local first use versus paid cloud activation | E/E/E | Mobile can start without account; web requires cloud access. Keep intentional availability difference and share activation progress vocabulary. | P1 |
| A04 | Shop selection / company management | P/E/E | Mobile local active-shop lifecycle and web account shop selector differ. Add common switch validation, dirty-draft handling and tenant cache clearing. | P1 |
| A05 | Multiple firms inside one business | N/N/N | Shops are tenant boundaries, not firms sharing inventory/parties. Add firm IDs, profile, bank details, numbering and report filters. | P6 |
| A06 | Warehouses/godowns inside one shop | N/N/N | Add location entities and per-location stock. Do not model transfers by creating unrelated shops. | P6 |
| A07 | Owner/admin/staff and invitations | E/E/E | Keep server/RLS enforcement. Match visibility and action guards on both clients. | P1 |
| A08 | Configurable permissions / category access | N/N/N | Current fixed role matrix is narrower than reference role editor/category access surfaces. Add capability policy with migration defaults. | P6 |
| A09 | App lock / sensitive-action authentication | P/P/P | Mobile app lock and account MFA are different controls. Add common reauthentication policy for high-impact actions without syncing device PINs. | P1/P6 |
| A10 | Audit/security history | P/P/E | Security/team history and domain audit exist; a unified searchable business activity history is not established across clients. | P2 |
| A11 | Onboarding tutorial and first invoice | P/P/P | Welcome and activation exist; category/profession/objective and first-sale tutorial parity absent. Add resumable essentials only; optional reference onboarding candidates remain tracked. | P1/P9 |
| A12 | Global search / settings search / notification routing | P/P/P | Domain lists and mobile notifications exist; shared global search destinations and safe deep-link resume need explicit contracts. | P1/P8 |
| A13 | Themes / seasonal launcher variants | E/E/— | Existing themes are preserved. Reference seasonal aliases/theme experiments are deliberately not copied. | Excluded visual work |

### 4.2 Document families and lifecycle — V1/V2 versus S1/S3/S4/S10

| ID | Feature | M/W/A | Existing difference or required work | Phase |
|---|---|---|---|---|
| T01 | Sales invoice, B2B/B2C | E/E/E | Preserve stock, tax snapshots, payment status and numbering; fix D01–D05. | P1/P2 |
| T02 | Purchase invoice/stock receipt | P/P/P | Composer, supplier, date/reference, lines, total tax/charges/discount and payment terms exist. Extend to fully typed tax invoices and line-level accounting. | P3 |
| T03 | Customer payment-in | E/E/E | Per-bill payments and customer collection allocation exist; unify selection/review and durable retries. | P2/P3 |
| T04 | Supplier payment-out | P/E/E | Existing allocation/reversal domain; mobile fields/actions lag. | P3 |
| T05 | Expense | E/E/E | Existing CRUD/payment/category. Extend itemized taxable expense and attachments as separate slices. | P3/P4 |
| T06 | Other income | N/N/N | Add separate non-sale income classification and accounting/report effects. | P4 |
| T07 | Sales return / credit note | E/E/E | Partial returns, original-line linkage, refund versus adjust exist. Preserve and test repeated partial returns, tax, stock and due limits. | P2 |
| T08 | Purchase return / debit note | N/N/N | Full receipt reversal exists on API/web; that is not a partial supplier return. Add original-line remaining quantities and supplier refund/credit settlement. | P3 |
| T09 | Full purchase/payment reversal | P/E/E | Reuse existing correction rules; complete mobile actions and confirmed/pending views. | P3 |
| T10 | Quotation/estimate | N/N/N | Draft/open/accepted/closed, share, expiry, convert to sale or sales order, source links. | P5 |
| T11 | Proforma invoice | N/N/N | Non-posting document, expiry, preview/share, controlled conversion to sale. | P5 |
| T12 | Sales order | N/N/N | Ordered/fulfilled/cancelled quantities, partial fulfillment and advance handling. | P5 |
| T13 | Purchase order | N/N/N | Ordered/received/cancelled quantities; receive into purchase document; prevent duplicate receipt. | P5 |
| T14 | Delivery challan | N/N/N | Dispatch, returned/undelivered goods, conversion to invoice, transport and quantity reconciliation. | P5 |
| T15 | Repeat/recurring invoices | N/N/N | Reference storage contains repeat templates; actual schedule semantics U. Define Storely schedules, retries, approvals and stop behavior. | P8 |
| T16 | Asset sale/purchase | N/N/N | Dedicated asset identity, acquisition/disposal entries and gain/loss policy. | P6 |
| T17 | Party-to-party balance transfer | N/N/N | Dual-party balanced entries, reason, authorization and reversal. | P4 |
| T18 | Save / Save and new / post-save preview | P/P/P | Existing completion/new-sale actions differ. One continuation policy across document types; failed save must not clear draft. | P1/P2 |
| T19 | Editing posted documents | P/P/P | Draft editing and selected corrections exist, not a universal posted-document editor. Choose revision/reversal policy by document type; never mutate historical totals silently. | P2/P5 |
| T20 | Cancellation / dependency guards | E/E/E | Preserve existing sales cancellation and purchase correction constraints; extend to linked documents, e-docs and closed periods. | P2/P5 |
| T21 | Recycle bin and restore | N/N/N | Tombstones/cancellation are not a user restore workflow. Add dependency-aware restore, identity collision checks, retention and audited purge. | P8 |
| T22 | POS mode | P/P/P | Scanner-first checkout exists; dedicated cashier permissions, shifts/drawer and mode setting are additional work. | P6 |

### 4.3 Transaction and line fields — V1/V3 versus S1/S3/S7

| ID | Field/rule | M/W/A | Gap or change | Phase |
|---|---|---|---|---|
| F01 | Cash/credit and full/partial/unpaid | D/D/E | Standardize explicit choice and whether party is required for credit; retain explicit unassigned-credit guard. | P1 |
| F02 | Date/time/backdating | P/P/P | Purchase date exists; sales create DTO does not offer arbitrary document date/time. Add common business-date rules and period locks. | P2/P4 |
| F03 | Prefix/number/series | P/P/E | Existing device-aware numbering; add firm/type/year scope and guarded manual override if enabled. Never renumber history. | P2/P5 |
| F04 | Billing name distinct from party master | P/P/P | Invoice name snapshots exist; explicit alternate billing-name policy/editor absent. | P3 |
| F05 | Billing and multiple shipping addresses | P/P/P | Billing address exists; separate shipping address book/snapshot absent. | P3 |
| F06 | Country/currency/exchange rate | N/N/N | INR-focused implementation. Add base/transaction currency and locked rates; no retroactive reinterpretation. | P6 |
| F07 | Payment terms/due date | P/P/P | Purchase terms exist; sale DTO lacks equivalent terms/due date. Implement common terms master and overdue definition. | P3 |
| F08 | Customer PO number/date | N/N/N | Purchase supplier invoice number is not a customer's PO reference. | P5 |
| F09 | E-way bill / IRN fields | N/N/N | Add typed manual references separately from actual generation/cancellation. | P7 |
| F10 | Document discount percentage | E/E/E | Keep current math and snapshots; align bounds/validation. | P2 |
| F11 | Fixed document discount / alternate discount controls | P/P/P | Purchase fixed amount exists; sales only one document percentage. Add amount↔percent editing and explicit allocation. The two reference control sets do not prove two stacked discounts. | P2/P3 |
| F12 | Line discount percent/amount | N/N/N | Current sale catalog DTO permits only product ID and quantity; add controlled line overrides. | P2 |
| F13 | Inclusive/exclusive rate per document/line | P/P/P | GST/pricing policy exists; general editable per-line tax mode and separate inward/outward defaults incomplete. | P2/P3 |
| F14 | Transaction-level tax and tax conflicts | P/P/P | Purchase accepts a total tax amount; no general tax-slot/conflict resolution engine. Define one tax basis and prohibit double taxation. | P2/P7 |
| F15 | Cess, additional cess, TCS/TDS, ITC and reverse charge | N/N/N | Add typed tax components, effective dates, bases, account mapping and return/report effects. | P7 |
| F16 | Taxable additional charges with SAC | P/P/P | Purchase scalar charges exist; named tax-bearing charge lines and allocation absent. | P3/P7 |
| F17 | Round-off modes/increments | P/P/P | Sale nearest-rupee boolean exists; configurable direction/increment and negative-total behavior absent. | P2 |
| F18 | Split tender | P/P/P | Multiple subsequent payments possible; initial checkout accepts one payment. Add payment list with sum/rounding guards and references. | P3 |
| F19 | Settlement discount/write-off | N/N/N | Distinguish cash received from amount cleared; post difference to an explicit account and preserve original invoice. | P4 |
| F20 | Advances/unallocated credits | P/P/P | Existing collections are invoice/balance-oriented; general party advance wallet/allocation/unlink model incomplete. | P3/P4 |
| F21 | Free quantity / packet count | N/N/N | Separate charged quantity, physical movement and optional count; do not fake with zero-priced duplicate products. | P2/P6 |
| F22 | Catalog rate override / last five prices | N/N/N | Current sale catalog input rejects custom price fields. Add permissioned override and party/history price precedence. | P2 |
| F23 | Line notes/service period | P/P/P | Custom line name exists; structured service duration and description snapshot need addition. | P3 |
| F24 | Item/party/transaction custom fields | N/N/N | Add typed definitions and immutable document snapshots; hide/disable must retain historical values. | P6 |
| F25 | Business notes, attachments and images | P/P/P | Customer/purchase notes, logo/signature exist; generalized transaction attachment lifecycle/internal notes absent. | P8 |
| F26 | Terms and conditions by document type | P/P/P | Invoice footer configuration exists; reusable versioned per-type terms and document override incomplete. | P5/P8 |
| F27 | Transport fields and delivery acknowledgement | N/N/N | Transporter, vehicle, delivery date/location and received/delivered-by need schema plus workflow. | P5/P7 |
| F28 | Loyalty earning/redemption | N/N/N | Dedicated ledger/rules needed; cannot be represented only by a discount field. | P9 |

### 4.4 Parties, inventory and pricing — V1/V3/V4 versus S2/S5/S11

| ID | Capability | M/W/A | Gap or change | Phase |
|---|---|---|---|---|
| I01 | Product catalog, category, unit and codes | E/E/E | Preserve CRUD, filters, bulk tools and code uniqueness; align entry and result flows. | P1 |
| I02 | Service/non-stock items | P/P/P | `trackStock=false` supports non-stock selling; explicit product/service type and service-specific fields absent. | P3 |
| I03 | HSN/SAC metadata | P/P/P | Existing HSN fields. Packaged lookup/authoritative verification lifecycle not established; track as integration gap. | P7 |
| I04 | Product photos / description | P/P/P | Product DTO is narrower than reference image/description master. Add image upload/storage and description snapshots. | P8 |
| I05 | MRP | P/P/P | Printed MRP exists separately from selling price; MRP-based tax calculation absent. | P2/P7 |
| I06 | Wholesale quantity tiers | N/N/N | Add threshold/rate, unit normalization and pricing precedence. | P6 |
| I07 | Party-specific item prices | N/N/N | Add sale/purchase histories and explicit negotiated rates with date/priority rules. | P6 |
| I08 | Primary/secondary units and conversions | N/N/N | Existing unit labels are not conversions. Store base quantities and conversion snapshots. | P6 |
| I09 | Opening stock / opening valuation date | P/P/P | Stock initialization/adjustment exists; full dated opening valuation workflow must be specified. | P4/P6 |
| I10 | Reorder/low stock and stock ledger | E/E/E | Existing thresholds, movements and ledger. Align insufficient-stock warnings and negative-stock policy. | P1/P2 |
| I11 | Batch and expiry | P/P/P | Receipt movement metadata/reporting exists; explicit sale lot allocation and remaining lot quantities not established. | P6 |
| I12 | Manufacturing date/size/model/batch attributes | N/N/N | Add configurable lot attributes and filters without conflating product and lot identity. | P6 |
| I13 | Serial/IMEI tracking | N/N/N | Add serial identity, acquisition, sale, return, transfer and uniqueness rules. | P6 |
| I14 | Multi-store stock transfers | N/N/N | Transfer out/in must share one identity and atomic posting, with transit state if enabled. | P6 |
| I15 | Manufacturing/BOM | N/N/N | Recipe versions, raw materials, quantity yield, labour/packaging/other costs, production and reversal. | P6 |
| I16 | Product import/export | E/E/E | Preserve preview, row errors, replay fingerprints and bulk operations; expand supported columns with contract tests. | P1/P8 |
| I17 | Import catalog without posting stock | P/P/P | Distinguish catalog-only upsert, opening stock, and purchase import as separate user intents. Never post stock because a price column is present. | P3/P8 |
| I18 | Barcode/QR scan and labels | E/E/E | Camera/mobile versus keyboard/web adapters; same duplicate/not-found/create/select outcome. Serial scan is new work. | P1/P6 |
| I19 | Customer/supplier master and balances | E/E/E | Preserve separate current identities; introduce common party abstraction without losing IDs or automatically merging matches. | P3 |
| I20 | Party opening balance/date/direction | N/N/N | Add dated receivable/payable opening entries and reconciled migration balances. | P4 |
| I21 | Party groups | N/N/N | Add membership, filters and group receivable/payable/sale/purchase reports. | P3 |
| I22 | Credit limits | N/N/N | Add policy, override permissions, exposure calculation and offline exception handling. | P3 |
| I23 | GSTIN verification / party details retrieval | P/P/P | Fields/status metadata exist; end-to-end authoritative lookup not established. Do not call regex validation “verified.” | P7 |
| I24 | Party spreadsheet/contact import | N/N/N | Add mapping/review/dedup, opening balance import and permission-aware contacts adapter. | P8 |
| I25 | Party self-registration/review link | N/N/N | Untrusted submissions → review → accepted party; scoped expiring link and duplicate review. | P9 |
| I26 | Party statements/collections/reminders | P/P/P | Statements and collection flows exist; mobile/manual reminders are narrower than scheduled, bulk, delivery-tracked reminders. | P3/P8 |
| I27 | CRM leads/tasks/field sales | N/N/N | Lead list/details, assignment, task type/status, location/photos, linked party and order lifecycle. | P9 |
| I28 | Customer profiling / partner/network / voice candidate | U/U/U | Reference mostly names surfaces. No established equivalent in Storely; discover actual product behavior before committing scope. | P9 discovery |

### 4.5 Accounting, reporting and tax — V1/V2/V4 versus S6/S10/S11

| ID | Capability | M/W/A | Gap or change | Phase |
|---|---|---|---|---|
| R01 | Day book | E/E/E | Existing transaction summaries; reconcile against canonical posting dates and refunds. | P2/P4 |
| R02 | Profit and loss | P/P/P | Existing sales/cost/expenses estimate, including uncosted-sales handling. Not a complete general-ledger P&L. | P4 |
| R03 | Receivables aging | E/E/E | Existing buckets; align due-date versus sale-date basis, as-of settlements and exports. | P3/P4 |
| R04 | Payables aging | P/P/P | Supplier balances/overdue exist; full aging buckets/report parity absent. | P3/P4 |
| R05 | Stock valuation | D/D/D | D03; then add historical costing and as-of valuation. Do not claim FIFO/weighted-average today. | P2/P6 |
| R06 | Purchase register | E/E/E | Movement-derived report and document list coexist. Separate purchase invoice totals from stock cost subtotal. | P3 |
| R07 | Expiry/low-stock reports | P/P/P | Existing views; lot consumption/expiry precision needed for true remaining-batch reports. | P6 |
| R08 | Tax summary and GSTR-1 export | P/P/P | Existing code and workbook output. Validate bucket coverage and reconciliation; not portal filing or e-invoice support. | P7 |
| R09 | GSTR-2, 3B, 4, 9, 9A | N/N/N | Reference declares these; applicability/current schemas require separate verification. | P7 |
| R10 | HSN/SAC summary and tax-rate detail | P/P/P | HSN metadata/basic tax summaries exist; complete independent drill-down exports incomplete. | P7 |
| R11 | TCS/TDS reports | N/N/N | Depends on typed tax posting and effective rules. | P7 |
| R12 | UAE VAT 201 / regional taxes | N/N/N | Regional extension, not implied by GST support. | P9 |
| R13 | Balance sheet / chart of accounts / journals | N/N/N | Add balanced journal infrastructure and opening balances; do not synthesize balance sheet from sales alone. | P4 |
| R14 | Cash ledger / adjustments / cash flow | N/N/N | Cash method totals are not cash-in-hand accounts. Add openings, receipts, payouts, deposits, withdrawals and reconciliation. | P4 |
| R15 | Bank accounts / statement / transfers | N/N/N | Bank payment label/UPI printing is not a bank subledger. Add account-scoped balances and transfer posting. | P4 |
| R16 | Cheques: open/closed/deposit/reopen | N/N/N | Add issued/received/pending/cleared/bounced/cancelled states and reversals. | P6 |
| R17 | Loans / EMI / fees / interest | N/N/N | Principal/interest separation, opening date, schedule, repayment and account dependency guards. | P6 |
| R18 | Fixed assets/depreciation/appreciation | N/N/N | Asset register, methods, adjustment/disposal and reports. Reference exact formulas U. | P6 |
| R19 | Party/item/category profit reports | P/P/P | Dashboard/category metrics and mobile invoice profit exist; dedicated shared reports/drill-downs incomplete. | P4/P6 |
| R20 | Party groups, items by party, parties by item | N/N/N | Add consistent filters, measures and source-document drill-down. | P6 |
| R21 | Item/document discount reports | N/N/N | Define gross/discount/net measures including returns, free quantities and write-offs. | P6 |
| R22 | Order, serial, manufacturing and transfer reports | N/N/N | Ship with owning modules, not disconnected later dashboards. | P5/P6 |
| R23 | Scheduled email reports | N/N/N | Reference weekly/monthly schedule. Add recipient validation, timezone, run history, retry and permission rechecks. | P8 |
| R24 | Custom reports / saved filters | P/P/P | Existing report filters; reusable configurable report definitions not established. | P8 |
| R25 | Financial year closing / period locks | N/N/N | Close with reconciled openings, backups and review. Prefer non-destructive locks; reference deletion behavior is not a safe default to copy. | P4/P8 |
| R26 | E-invoice generation/status/cancel | N/N/N | Credentials/setup, review, submit, uncertain response recovery, IRN/QR storage, cancellation and edit guards. | P7 |
| R27 | E-way bill generation/status/cancel | N/N/N | Transport/distance/dispatch inputs, validation and independent document status lifecycle. | P7 |

### 4.6 Output, settings, data and integrations — V3/V4/V5/V8 versus S7/S8/S9

| ID | Capability | M/W/A | Gap or change | Phase |
|---|---|---|---|---|
| O01 | Invoice PDF/preview/share/print | E/E/E | Multiple renderers exist. Same document data and settings must produce equivalent content, totals and pagination rules. | P2/P8 |
| O02 | PDF/image sharing choice | P/P/P | PDF flow exists; common invoice-as-image flow and naming/content rules need completion. | P8 |
| O03 | Original/duplicate/triplicate copies | U/U/U | No confirmed complete matching copy-mark flow in inspected settings. Inventory individual renderer controls before implementation. | P8 |
| O04 | Logo/signature, header/footer, columns | E/E/E | Existing options are valuable; preserve them. Diff every field across mobile model/API/web editor/renderers. | P1/P8 |
| O05 | Custom document titles/per-type print settings | P/P/P | Existing sale titles/settings; new document family configuration and overrides needed. | P5/P8 |
| O06 | Table headers/widths/min rows/header repeat/page numbers | P/P/P | Existing invoice layout controls do not establish all reference options. Field-by-field renderer inventory required. | P8 |
| O07 | Bluetooth thermal | E/N/— | Mobile transport exists; web print intent needs supported browser/bridge adapter and clear unavailable state. | P8 |
| O08 | Wi-Fi and USB thermal | N/N/— | Reference transports exist; Storely mobile thermal service is paired Bluetooth. Add adapters and device acceptance. | P8 |
| O09 | Feed/copies/cut/drawer/custom width/local-language raster | P/P/— | Mobile cut/raster/paper support exists; full configurable option parity not established. Expose only supported capabilities. | P8 |
| O10 | Shared settings registry | P/P/P | Existing settings are split across preferences, bill settings, pricing and app settings. Define scope/default/version/dependencies once. | P1 |
| O11 | Currency/date/quantity/amount display preferences | P/P/P | Some app preferences exist; full common options and invoice-language separation incomplete. | P1/P6 |
| O12 | Local backup/restore | E/N/P | Mobile zip/SQLite validation and pre-restore copy exist; personal-account export is not business backup. Add authorized cloud business export/restore workflow. | P8 |
| O13 | Automatic backup and reminder/retention | P/N/P | Manual mobile backup and server operations scripts exist; user-facing scheduled Drive/backup history not established. | P8 |
| O14 | Encrypted portable backups | U/N/P | Mobile format is a zip of SQLite. Add explicit encryption/key/recovery design if shipping encrypted portable files; never label zip encrypted. | P8 |
| O15 | Sync/conflicts/account-owned drafts | E/P/E | Existing row sync, private preferences and atomic purchase sync; web draft model differs. Preserve authorization and define supported command schemas. | P2 |
| O16 | Cross-device draft handoff | P/N/P | Mobile foreign-origin held carts are view-only backups. Add explicit ownership transfer/lease and single-consumer checkout if handoff is required. | P2 |
| O17 | Vyapar/MyBillBook/Tally interoperability | N/N/N | Reference includes candidate interchange surfaces. Require user-owned samples and formats; no promised binary `.vyb` compatibility from static docs alone. | P8/P9 |
| O18 | Automatic transaction messaging | N/N/N | Manual share/reminder is not delivered SMS/WhatsApp. Add templates, consent, outbox, provider status and dedup. | P8 |
| O19 | Service reminders | N/N/N | Add service interval/date, schedule, opt-out and completion/rearm. | P8 |
| O20 | Online storefront/catalogue/orders | N/N/N | Public catalog, prices, minimum order, delivery charges, stock availability, accept/reject/fulfill and reports. | P9 |
| O21 | Payment links / gateway / KYC | N/N/N | Payment method/UPI QR recording is not collection confirmation. Integrate setup, webhooks, reconciliation, refunds and disputed/unknown states. | P9 |
| O22 | Loyalty setup/party points/expiry | N/N/N | Add threshold, minimum spend, point value, cap, expiry, opening/adjustment, reversal and ledger views. | P9 |
| O23 | Smart Ads | N/N/N | Candidate creation/design request/media/preview/approval/payment/campaign/extension/dashboard flows. Separate optional module; provider rules U. | P9 |
| O24 | Facebook/WhatsApp marketing integrations | N/N/N | Reference route candidates; setup, consent, token lifecycle, failure/revoke states require discovery. | P9 |
| O25 | Referral/scratch cards/rewards/greetings | N/N/N | Growth modules, separately prioritized after business correctness; no fabricated payout logic. | P9 |
| O26 | Inbox/help/tutorials/NPS/what's new | P/P/P | Storely support/about/notifications exist; cross-client inbox/tutorial/feedback flows incomplete. | P9 |
| O27 | License/subscription/premium administration | E/E/E | Keep Storely's audited manual approval model; competitor pricing/entitlements are not requirements. Self-service billing is additional scope. | P1/P9 |

## 5. Shared workflow specifications

Every flow below is a specification for both clients. Responsive presentation may differ; the state sequence and meaning cannot. Entry shortcuts may prefill values but must enter the same workflow and must not silently skip validation or review.

### WF01 — Create a sale

1. Enter New invoice from Home, Sales or Party; restore/choose/discard an existing draft explicitly.
2. Add/search/scan items; choose quantity/unit, allowed rate/discount and lot/serial where enabled. Unknown code → choose existing or authorized create → return to draft.
3. Enter/select party and document details: type, business date, billing/shipping, GST/place of supply, terms and notes. Preserve draft while entering a child editor.
4. Select full/partial/unpaid; add tender lines/reference if paid; show amount received, due and cash change separately. Credit without a usable party requires the same explicit warning/policy everywhere.
5. Review immutable price/stock/tax/credit checks; stale values require refreshed review. Draft and preview never post stock, journal or payment effects.
6. Save using one persisted operation ID and payload fingerprint. Validate authorization, period, settings version, stock and document identity in the write transaction.
7. Result → document details, print/share, record another payment, return or New invoice. An uncertain save stays locked for lookup/retry; never offer a fresh duplicate operation as the default recovery.

### WF02 — Purchase and supplier settlement

1. Enter New purchase from Purchases, Supplier or Restock with equivalent prefill.
2. Choose supplier, supplier invoice number/date and purchase date; detect duplicate supplier/year/reference according to a published rule.
3. Add existing/staged new items or import and review rows. Enter quantity/unit/cost, lot/serial and tax components.
4. Review item cost, recoverable tax, nonrecoverable cost, charges, discounts and supplier total separately.
5. Explicitly choose paid/full/partial/unpaid or legacy “payment not recorded.” New typed invoices should not silently disappear from payables; retain unknown state only for historical/stock-only documents.
6. Save atomically → receipt, movements, payable and initial allocations → detail/result.
7. Pay supplier → choose account/method/date/reference/notes → review selected or oldest-first allocation → confirm → receipt/ledger. Mobile pending operations display separately from confirmed postings.
8. Correct using controlled reversal or partial return. Reverse dependent payments first where required; show blocking stock/linked-document reasons and links to resolve them. Complete the same actions on mobile.

### WF03 — Customer collection, returns and corrections

Select party/document → view outstanding and existing credits → enter amount/date/method/reference → preview allocation → confirm → receipt/statement. Show leftover advance or reject it according to one configured policy. A discount clearing part of a debt is a separate posting from cash.

Return: select original invoice → remaining returnable lines → quantity/lot/serial → refund or adjust balance → preview stock/tax/settlement → reason/confirmation → linked credit note/result. Cumulative returns cannot exceed the original quantity/value. Purchase returns mirror this with opposite stock/payable direction.

Cancel/reverse: open original → show dependencies and effects → reason/reauthentication if required → atomic reversal → retained original and reversal links. No destructive edit of posted history.

### WF04 — Quote/order/challan conversion

Create non-posting quote/proforma/order → save/share → open source → select conversion and quantities → review source/destination links → post target → source remaining quantity/status updates atomically. Full conversion repeated with the same operation ID returns the same target. Two concurrent conversions cannot over-fulfill. A challan's stock dispatch and later invoice must not reduce stock twice. Cancellation restores only the remaining quantities permitted by dependencies.

### WF05 — Inventory and production

Product master → opening/receive/adjust/transfer/produce action → choose location, base/alternate unit and lot/serial → preview physical/cost movement → reason → confirm → ledger. Transfers keep shop total unchanged; production consumes raw materials and creates output with a frozen recipe/cost snapshot. Expired stock and insufficient stock have explicit override/deny policies. Serial quantity and selected serial count must agree.

### WF06 — Reports, output, imports and settings

Reports: choose report → period/as-of/timezone/firm/location/party filters → result with freshness/cost-basis labels → drill-down source → export identical filters and totals. No silent dropped rows due to screen pagination.

Output: select document → preview saved snapshot → select format/copy/paper/device → print/share → clear cancelled/failed/submitted outcome. Print failure never rolls back a successfully posted invoice. Opening a system share sheet does not establish delivery.

Import: select intent/template → choose file → validate container/header/limits → map columns → review matches/errors/duplicates → confirm → operation result and row errors → source-linked documents. Retry cannot duplicate stock or balances.

Settings: choose setting → explain scope and future effect → edit → validate dependencies/permissions → save version → affected future workflows refresh. Historical invoices retain original financial snapshots. Turning off a feature hides future entry but does not erase historical data.

### WF07 — Backup, restore, closing and sync recovery

Backup: select scope → authorize → snapshot/manifest/checksum → encrypted package if configured → verify → save/share → record completion.

Restore: inspect metadata/version → dry-run validation and tenant identity → display replace/merge policy → pre-restore backup → isolated restore/reconciliation → atomic activation → explicit sync recovery. Never upload restored stale rows as new money operations automatically.

Closing: choose period → reconcile unresolved operations, stock, parties, banks and journals → backup → preview carry-forward → lock period and save audit. Historical transaction deletion is not the default. Reopen requires a privileged audited command.

Sync: pending → sending → accepted/rejected/conflict/unknown → retry or guided resolution. Users see affected document, cause and safe recovery; no blind “discard conflict” for financial records without explaining which business effects remain.

## 6. Business invariants and architecture

### 6.1 Commands, state and data boundaries

Create shared, versioned specifications and JSON fixtures consumed by Dart, TypeScript tests and Python. Share contracts, enums, formulas and scenario expectations; do not attempt to import Python code into Flutter or put authoritative accounting in React.

Recommended incremental boundaries:

- **Document commands:** create, revise permitted draft, post, allocate, return, reverse, convert and close. Each command has tenant, actor, operation ID, schema version, expected revision and payload fingerprint.
- **Calculations:** explicit decimal quantity/rate/amount inputs; tax/discount/rounding order; accounting and stock outputs; versioned snapshots.
- **Posting:** stock movements, journals, payment allocations and audit commit together. Use uniqueness constraints and row locks for contested stock, source remaining quantities and numbering.
- **Read models:** list/detail/report/export use common definitions and server pagination. Mobile derives equivalent local read models from accepted and local-only commands.
- **Adapters:** SQLite/PostgreSQL, REST/sync, print/share/files and remote providers. Platform adapters cannot change the business result.
- **UI controllers:** separate draft and workflow state from widgets/components; keep present state-management stack initially. Extract the large screen/database mixins by use case without a speculative framework rewrite.

Add normalized tables only as modules need them: party accounts/addresses/groups; payment allocations/advances; document links and revisions; journal entries/lines and accounts; locations/lots/serials/unit conversions; BOM/production; schedules/outbox/attachments. Keep compatibility views/adapters for existing `bills`, `purchase_documents`, customers/suppliers and stock movements. Do not build a universal transaction table that discards document-specific constraints.

### 6.2 Calculation contract

Specify independently for each document type:

1. Canonical decimal scale for quantities, rates, monetary intermediates and final amounts; serialization as decimal strings.
2. Unit conversion and free-quantity effects; line amount before tax; line discount; document-discount allocation; taxable charges; inclusive/exclusive tax; cess/withholding; rounding; total payable.
3. One rounding mode at named boundaries. Allocate residual paise deterministically; do not round each intermediate arbitrarily.
4. Cost basis: inventory acquisition cost, recoverable tax exclusion, nonrecoverable taxes/allocated costs, and historical cost recognition. Preserve existing cost snapshots until a reviewed migration establishes replacements.
5. Settlement: total cleared = cash/bank payment + allowed credit/write-off allocation; distinguish cash change, refund, advance and outstanding.
6. Returns use original snapshot rates/taxes/costs, not today's product prices. Last partial return absorbs any permitted residual so totals reconcile.
7. Missing/unknown cost is not zero-cost profit. Legacy unknown payment terms are not paid or unpaid by inference.
8. Date contracts: business date, immutable UTC event time, shop timezone, due date and financial period are separate fields.

For D03, a source-derived example is quantity 10, purchase price ₹100, GST 18%, overhead ₹5 and an unregistered shop: the mobile valuation expression yields ₹1,000 while the API resolved-cost expression yields ₹1,230. This is an algebraic example from the inspected functions, not a runtime reproduction. Add fixtures for recoverable versus nonrecoverable tax and positive/negative stock. Decide the canonical report basis explicitly, then change both clients and exports together. Existing invoice tax vectors remain regression fixtures, not the sole definition of every future calculation.

### 6.3 State and integrity invariants

- Drafts/quotes/proformas do not move stock or recognized balances. Orders reserve stock only if a separately defined reservation policy is enabled.
- Each posted operation affects stock, payments and accounting at most once, even after timeout, restart, replay or two tabs/devices.
- Posted journals balance; document links cannot cross tenant/firm boundaries improperly; both sides of a transfer remain traceable.
- Posted document financial snapshots are immutable. Corrections preserve original and reversal/replacement identity.
- Two clients returning/converting/paying the same remaining balance cannot over-allocate.
- Cancelled/reversed/deleted records cannot be revived by stale sync. Restore is a specific authorized command.
- Permission revocation, entitlement expiry and closed periods are checked on commit/replay as appropriate; UI hiding alone is never enforcement.
- Offline sales cannot guarantee global stock or credit limits across disconnected devices. Choose explicit pending exception review or preallocated quotas; never claim impossible online consistency while disconnected.
- Cloud financial command acceptance must reject incomplete aggregate state. Extend existing atomic purchase snapshots; migrate sales away from independent financial-row sync in a compatibility phase.

### 6.4 Settings and workflow contracts

Create a registry for each setting: stable key, type, default, allowed values, scope (shop/firm/user/device), permission, dependency, migration version, effect on future documents, and printing impact. Device PINs, printer pairing and credentials stay device-local. Business rules and portable preferences sync with their intended scope.

Create workflow fixtures containing ordered steps, initial values, visible/required fields, permitted actions by role/state, validation order/error codes, side effects and completion actions. Both clients must pass the same fixtures. Runtime-generated OpenAPI remains the wire contract; update the narrative API contract because it still contains historical/outdated statements.

### 6.5 Recovered reference calculations versus Storely

These details come from V `BUSINESS_RULES.md` sections “Recovered numeric paths” and “Line calculations and payment precision.” They are observed branches, not a complete tax algorithm.

| Rule | Reference evidence | Storely comparison and implementation requirement |
|---|---|---|
| Discount amount/rate editing | Amount maps to 100 × amount / subtotal; near-zero subtotal clears the rate. One of two control sets is active. | Sale uses a single percentage; purchase uses fixed document amount. Add equivalent editing with explicit zero handling. Do not infer stacking two discounts. |
| Transaction tax | Observed branch applies rate to subtotal less active discount, then adds charge totals. | Storely sales calculate line snapshots; purchase tax is supplied as a scalar. Define eligibility and conflict rules before adding a transaction-tax mode. |
| Taxable charges | Each observed charge adds its own percentage tax to its pre-tax amount. | Purchase scalar charges cannot represent this. Use charge-line components and separate recoverable cost/tax. |
| Round-off | Adjustment = N × mode(A/N) − A; nearest branch uses ties-to-even, with separate floor/ceiling. | Mobile grand-total rounding uses Dart `roundToDouble`; server money boundaries use HALF_UP. A 100.50 nearest-rupee fixture distinguishes behaviors. Preserve historical rules; choose and version future policy rather than silently adopting competitor rounding. |
| Exchange conversion | Observed display divides by rate; storage multiplies; null defaults to 1; near-zero returns zero with diagnostic. | No multicurrency domain. Define base/transaction direction explicitly and reject invalid zero rates; do not reproduce silent zero financial output. |
| Inclusive tax | Tax portion is inclusive amount × rate / (100 + rate). | Existing Storely GST calculation has equivalent basic algebra; verify discount, registration/place-of-supply and rounding vectors, not only a simple 118-at-18% case. |
| Exclusive line tax | Discounted exclusive subtotal × rate / 100. | General per-line inclusive/exclusive editing is incomplete. Add separate fixtures and snapshots. |
| MRP tax | Recovered branch uses MRP basis and unit factor; line discount does not reduce that basis. | Printed MRP alone does not implement this. Ship only with an explicit tax mode and independently verified applicable policy. |
| Line total | Recomputed subtotal − discount + tax + additional cess; overridden-total reverse calculation remains unknown. | Implement typed components; do not add editable total that silently changes tax/rate without a specified reverse calculation. |
| Serial mismatch | A recovered branch changes ordinary quantity to serial count minus free quantity, focuses it and refuses that save attempt. | No serial tracking. Proposed Storely behavior: show mismatch and require reviewed quantity correction on both clients, rather than silently changing posted quantities. |
| Cash/split settlement comparison | Reference rounds configured precision, with additional exchange-rate normalization; comparison rounding differs from transaction round-off. | Define settlement equality independently from invoice rounding; test split sum, currency scale, overpayment/change and negative/refund cases. |

These differences are requirements to decide and test, not an instruction to replace all Storely arithmetic with Vyapar's implementation.

## 7. Migration and rollout strategy

1. Snapshot current schema/contracts, repository revisions and dirty working trees; record supported app versions and baseline fixtures before implementation.
2. Inventory existing UUID/local-ID mappings, invoice series, cancelled bills, returns, purchase import fingerprints, supplier payments, native receipt snapshots and unsynced queues. Never regenerate identities.
3. Add nullable/versioned columns and new tables via Alembic and additive SQLite migrations. Read old and new forms during the transition; write new commands behind coordinated feature gates.
4. Backfill provenance and links with deterministic rules and reconciliation reports. Do not infer historical GST treatment, due dates, lot assignment or payment status where missing. Mark unknown and expose reviewed correction/import tools.
5. Shadow-calculate new totals/report projections against saved snapshots; classify differences. Historical issued documents retain original output until explicitly corrected.
6. Migrate customer/supplier references through a mapping table; same name/phone is not automatic identity equality. Keep foreign keys and old API compatibility until all supported clients migrate.
7. Add command sync negotiation. Old clients must not write unsupported new document shapes. Keep compatible read projections or require update for affected features without blocking unrelated local data access.
8. Pilot per shop, enabling a module only when API, web and mobile support it. Entitlement and capability checks must agree; avoid “web-only released” business modules.
9. Verify every pilot: document totals, party balances, stock by item/location/lot, payment allocations, journal balance, export totals and print content before/after.
10. Rollback means disabling new writes and using compatible readers while retaining new data. Never deploy an old binary against a schema it cannot safely interpret; never drop new data to make rollback convenient.
11. Rehearse interrupted SQLite migration, database restore, server deploy rollback, offline client reconnect and rejected queue recovery using copies of representative datasets.

## 8. Test and acceptance matrix

The plan is not accepted by counting screens or unit tests. Each feature must prove the user flow, persisted effects and cross-client convergence.

| Suite | Required scenarios | Evidence of completion |
|---|---|---|
| Workflow parity | Same seed data, role, settings and ordered actions on mobile and web; compare defaults, steps, validations, confirmation and follow-up actions. | Paired scenario recordings/logs linked to feature IDs; identical semantic outcomes. |
| Financial vectors | Fractional quantities, zero/unknown cost, inclusive/exclusive tax, line/document discounts, rounding ties, charges, returns and partial payments. | Exact expected decimal results in Python and Dart; web displays same server result. |
| Document lifecycle | Draft/edit/post/cancel/return/convert; double submit, repeated conversion, dependencies and period locks. | Expected immutable history and ledger/stock deltas. |
| Concurrency | Two clients sell last stock, return same line, allocate same due, choose same invoice number or convert same order. | One legal outcome; clear conflict and no duplicate posting. |
| Offline and retry | Network loss before/after commit, process kill, full storage, browser reload, two-tab draft conflict, reordered sync. | Original operation recovers exactly once; pending and rejected states retained. |
| Permissions | Owner/admin/staff/custom role; cross-shop IDs; role removal; expiry while form is open; direct API and sync bypass attempts. | Correct deny behavior and no hidden cost/contact leakage. |
| Reports | As-of dates, timezone boundaries, backdates, reversals, unknown cost, negatives, page limits and export filters. | Report equals source ledger/read model; mobile = API = export after sync. |
| Migration | Old databases, partial migration, retries, duplicate identifiers, historical unknowns and large datasets. | Reconciliation report and successful rollback/recovery drill. |
| Output | Long names, long invoices, EN/HI text, zero tax, credit notes, QR, logo/signature, all supported paper sizes. | Saved PDF/image artifacts reviewed; physical printer checks where claimed. |
| Integrations | Sandbox success/deny/timeout/duplicate webhook/status mismatch/revoked credential. | Reconciled provider state and durable outbox history. |
| Usability/accessibility | Back/cancel, keyboard navigation, focus on errors, screen reader labels, large text, small-screen keyboard. | No lost drafts or unreachable confirmation/actions. |
| Performance | Representative large catalogs, ledgers and imports, low-end Android; bounded paging and background exports. | Baseline and agreed latency/memory budgets recorded before release. |

Reuse existing tests instead of replacing them: A `tests/fixtures/billing_vectors.json`, `tests/fixtures/sync_data_contract.json`, billing/report/purchase/supplier/authorization/sync tests; W billing, purchase, report, draft and permission tests; M `test` and integration tests. Extend them with feature-specific scenarios.

Expected checks during implementation: mobile `flutter analyze` and relevant `flutter test`; web `npm run typecheck`, `npm run lint`, `npm test`, `npm run build`; API `make lint`, `make test` and applicable `make test-integration`, `make test-sql`, `make test-mobile`, `make test-device`, `make test-decimal-upgrade`, premium lifecycle and restore targets. Use local scratch/test data. None of these checks is claimed run for this documentation-only change.

## 9. Sequenced implementation work packages

Each package ships a complete vertical slice: schema + migration + domain commands + API/OpenAPI + local persistence/sync + web/mobile workflows + reports/output + tests + operational recovery. A server-only or web-only implementation is not “done.”

| Phase | Work and dependency | Deliverables and exit criteria |
|---|---|---|
| P0 — Baseline and contracts | Start here. Capture current behavior and all D findings; resolve formula/default policy before changes. | Feature ledger with owner/status/evidence; workflow specifications; field/settings inventories; shared fixtures; tested baseline on both clients; exact unsupported/unknown behaviors recorded. |
| P1 — Existing workflow parity | Depends P0. D01/D02/D04/D05/D12/D14; catalog, account, settings, scan and navigation intents. | Same sale steps/defaults, complete drafts/hold, consistent validation/recovery, tenant switching and settings registry; preserve theme. No new major module until current user tasks agree. |
| P2 — Financial consistency and atomic commands | Depends P1 contracts; can build foundations alongside P1. D03/D09/D10/D11/D15; T01/T03/T07/T18–20; F02/03/10–14/17/22; O15/16. | Canonical calculations, reconciled reports, operation recovery, versioned snapshots, safe sale/return/payment command sync and audit. Pass concurrency/retry tests. |
| P3 — Parties and purchasing completeness | Depends P2. D06–08; purchase tax/settlement, supplier reversal parity, purchase returns, party addresses/groups/limits, sale due dates and advances. | Complete procure-to-pay and order-to-cash settlement on both clients. No unintentional omission from dues. Clear legacy unknowns and matching statements. |
| P4 — Accounting foundations | Depends P2/P3. Accounts/journals, openings, cash/bank, transfers, write-offs, other income, balance sheet, full P&L and period locks. | Balanced postings and reconciled subledgers; fiscal opening import; period-close preview; accountant-reviewed policy fixtures. No balance sheet built from approximated dashboard figures. |
| P5 — Sales and procurement document chain | Depends P2/P3, financial posting uses P4 where applicable. Quotes, proforma, orders, challans, conversion, terms/transport. | Full/partial conversion and cancellation matrices; shared remaining-quantity logic; no duplicate fulfillment/stock movement. |
| P6 — Advanced inventory and business operations | Depends P3/P4/P5 as needed. Units, lots, serials, firms/stores/transfers, tiers, BOM, assets, loans, cheques, advanced reports and capability roles. | Implement in slices: units → locations/lots/serials → pricing → transfers → manufacturing → assets/loans/cheques. Each has ledger/report/reversal acceptance before next. |
| P7 — Tax and e-documents | Depends P2/P3/P4 plus P5 transport. GST components, current report schemas, ITC/reverse charge/cess/TCS/TDS, e-invoice/e-way integration. | Official schema/provider verification recorded; sandbox end-to-end approval; uncertain response/reconciliation and cancellation guards; matching reports and printable evidence. |
| P8 — Data operations, output and automation | Depends owning module contracts. Attachments, renderer parity, print transports, import/export, backups, recycle bin, closing, reminders and report schedules. | Restore drills, dependency-safe restore, full output matrix, durable jobs/retries and recipient permissions; capability-gated hardware support. |
| P9 — Extended product modules | Depends stable foundations. Loyalty, storefront, online collection/KYC, field sales, service growth tools, regional tax and optional reference candidates. | Separate acceptance per module on both clients. Discovery-only candidates become specified requirements before code. Record intentionally deferred growth features rather than claiming full reference parity. |
| P10 — Release and stabilization | Follows each module pilot; final pass after intended scope. | Migration evidence, paired web/mobile acceptance, performance and device output checks, support/recovery documentation and monitored staged rollout. |

Do not attach calendar promises to this backlog without staffing, supported-platform, provider and historical-data decisions. It contains multiple substantial new products in addition to refactoring. Deliver P0–P3 first to make the current Storely coherent; full reference breadth requires P4–P9 too and must remain visible as incomplete until delivered.

### 9.1 First implementation slice: concrete file targets

1. Add a documented workflow/fixture area under M `docs` and `test/fixtures`, mirrored/consumed by A/W tests. Capture D01–D15 before touching behavior.
2. Extract sale draft/checkout state from M `scan_screen.dart` and W `NewBill.tsx` into small controllers using the existing stacks. Keep components/theme. Standardize payment default, persisted draft content and completion actions.
3. Add web held-draft list/resume and mobile durable operation recovery. Keep private ownership and device consume guards; cross-device handoff requires explicit transfer design.
4. Add D03 shared stock-valuation fixture; change M `database_reports.dart` and A `reports.py` to the chosen rule and update W report labels/exports. Record historical result changes without rewriting invoices.
5. Expose existing purchase reversal/payment-terms actions in M receipt detail, then enrich M supplier payment fields/allocation review to match W/A. Add the necessary mobile transport methods and local confirmed/pending projections.
6. Add sale due-date/terms and purchase return as separate additive domain changes after parity gates pass; do not mix these new capabilities into a theme/layout change.

### 9.2 Definition of done for every feature row

- [ ] Reference evidence strength and Storely product rule recorded; UNKNOWN is not treated as fact.
- [ ] All fields/defaults/validation/error recovery and permissions specified.
- [ ] API/domain/local persistence implemented with additive migration and compatibility handling.
- [ ] Web and mobile expose the same logical sequence and follow-up actions.
- [ ] Draft, pending, confirmed, failed, conflicted and reversed states behave correctly where applicable.
- [ ] Stock, payment, journal, report and output consequences reconcile.
- [ ] Offline/retry/concurrency and role/tenant tests pass.
- [ ] Paired workflow acceptance and rollback/restore evidence attached.
- [ ] UI/theme preserved; no inaccessible new control or lost draft.

## 10. Explicit unknowns and scope decisions

1. The reference cannot establish every runtime feature or formula. Do not advertise “100% Vyapar parity” from this audit. This plan inventories known feature families and explicitly retains lower-confidence surface candidates.
2. Existing Storely code was read statically; deployed versions may differ. Capture repository revisions and actual build identities in P0 before coding.
3. Decide exact valuation method, sale payment default, stock/credit override policy and posted-document correction policy using the specified fixtures. Proposed defaults above are Storely design decisions, not recovered Vyapar truth.
4. Confirm whether mobile/web availability parity includes offline web; current architecture supports semantic workflow parity with different transport availability.
5. Tax region support, current filing schemas, gateway/KYC providers, message delivery channels, backup destination and printer support require concrete implementation choices and sandbox/device evidence.
6. Complete a field-level output/settings diff for O03/O06/O09 instead of treating uninspected controls as definitely missing.
7. No proprietary assets, exact theme, SDK behavior, seasonal aliases or speculative remote service behavior need to be copied. Implement independent Storely behavior using the evidence as a functional checklist.

## 11. Reference coverage register

The following appendices are a traceability inventory, not additional verified features. They prevent the less prominent reference surfaces from disappearing from the backlog. A declared screen may map to several rows above; runtime reachability, individual controls and rare failure branches still require the P0/Pn acceptance work. The detailed comparison in section 4 takes precedence over a surface's name.

### 11.1 All 273 declared native activity/alias entries

Each row points to its exact source section. Status is the mapped family status, not proof that every child dialog was reviewed. Generic wrappers remain discovery items.

| # | Reference surface | Backlog mapping | Disposition |
|---:|---|---|---|
| 1 | [AboutVyaparActivity](../vyapar-rea/SCREEN_REGISTRY.md#aboutvyaparactivity) | O26 | Support/inbox; partial |
| 2 | [activities.AddImageActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesaddimageactivity) | O01 / O02 / O04 | Output/media; existing narrower workflow |
| 3 | [activities.AppInboxActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesappinboxactivity) | O26 | Support/inbox; partial |
| 4 | [activities.ChangePrefixActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitieschangeprefixactivity) | F03 | Numbering; device series exists |
| 5 | [activities.closebook.FaqWebViewActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesclosebookfaqwebviewactivity) | R25 / O12 | Closing and backup; new workflow |
| 6 | [activities.closebook.StartClosingActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesclosebookstartclosingactivity) | R25 / O12 | Closing and backup; new workflow |
| 7 | [activities.DialogAddBusinessActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesdialogaddbusinessactivity) | A04 / A05 | Companies/profile; firms missing |
| 8 | [activities.MultiplePartyReminderActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesmultiplepartyreminderactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 9 | [activities.OpenBackupActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesopenbackupactivity) | O12–O14 | Backup/restore; mobile manual exists |
| 10 | [activities.report.GSTR9AReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesreportgstr9areportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 11 | [activities.report.GSTR9ReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesreportgstr9reportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 12 | [activities.report.ReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesreportreportactivity) | R01–R24 | Report family; consult individual report rows |
| 13 | [activities.RestartAppDialogActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesrestartappdialogactivity) | A12 / O26 | Generic wrapper/route; behavior unresolved |
| 14 | [activities.SaleOnBoardingAcitivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiessaleonboardingacitivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 15 | [activities.SerialNumberActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiesserialnumberactivity) | I18 / I13 | Scanning exists; serial inventory missing |
| 16 | [activities.SmsListActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiessmslistactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 17 | [activities.TxnListActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiestxnlistactivity) | T01–T22 / F01–F28 | Transaction family; consult individual rows |
| 18 | [activities.TxnPdfActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitiestxnpdfactivity) | O01 / O02 / O04 | Output/media; existing narrower workflow |
| 19 | [activities.WebViewActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitieswebviewactivity) | A12 / O26 | Generic wrapper/route; behavior unresolved |
| 20 | [activities.WhatsappPermissionActivity](../vyapar-rea/SCREEN_REGISTRY.md#activitieswhatsapppermissionactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 21 | [AddItemUnitMappingActivity](../vyapar-rea/SCREEN_REGISTRY.md#additemunitmappingactivity) | I08 | Unit conversion; missing |
| 22 | [AdditionalItemColumnsActivity](../vyapar-rea/SCREEN_REGISTRY.md#additionalitemcolumnsactivity) | I11–I13 / F24 | Advanced item attributes; partial/missing |
| 23 | [AddPartiesToGroupsActivity](../vyapar-rea/SCREEN_REGISTRY.md#addpartiestogroupsactivity) | I21 / R20 | Party grouping; missing |
| 24 | [appinbox.ui.webviews.TransactionWebViewActivity](../vyapar-rea/SCREEN_REGISTRY.md#appinboxuiwebviewstransactionwebviewactivity) | O26 | Support/inbox; partial |
| 25 | [AutoSyncBaseReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#autosyncbasereportactivity) | R01–R24 | Report family; consult individual report rows |
| 26 | [BankStatement](../vyapar-rea/SCREEN_REGISTRY.md#bankstatement) | R15 | Bank ledger; missing |
| 27 | [barcode.BarcodeItemSelectionActivity](../vyapar-rea/SCREEN_REGISTRY.md#barcodebarcodeitemselectionactivity) | I18 / I13 | Scanning exists; serial inventory missing |
| 28 | [barcode.ContinuousBarcodeScanningActivity](../vyapar-rea/SCREEN_REGISTRY.md#barcodecontinuousbarcodescanningactivity) | I18 / I13 | Scanning exists; serial inventory missing |
| 29 | [barcode.ContinuousScanningWithDeviceActivity](../vyapar-rea/SCREEN_REGISTRY.md#barcodecontinuousscanningwithdeviceactivity) | I18 / I13 | Scanning exists; serial inventory missing |
| 30 | [barcode.SingleBarcodeScanningActivity](../vyapar-rea/SCREEN_REGISTRY.md#barcodesinglebarcodescanningactivity) | I18 / I13 | Scanning exists; serial inventory missing |
| 31 | [BaseActivity](../vyapar-rea/SCREEN_REGISTRY.md#baseactivity) | A12 / O26 | Generic wrapper/route; behavior unresolved |
| 32 | [bulkUpdateItems.BulkUpdateTaxSlabActivity](../vyapar-rea/SCREEN_REGISTRY.md#bulkupdateitemsbulkupdatetaxslabactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 33 | [BusinessDashboardActivity](../vyapar-rea/SCREEN_REGISTRY.md#businessdashboardactivity) | R01–R24 | Report family; consult individual report rows |
| 34 | [businessprofile.BusinessProfileActivity](../vyapar-rea/SCREEN_REGISTRY.md#businessprofilebusinessprofileactivity) | A04 / A05 | Companies/profile; firms missing |
| 35 | [cashInHand.CashInHandAdjustmentActivity](../vyapar-rea/SCREEN_REGISTRY.md#cashinhandcashinhandadjustmentactivity) | R14 | Cash ledger; missing |
| 36 | [cashInHand.CashInHandDetailActivity](../vyapar-rea/SCREEN_REGISTRY.md#cashinhandcashinhanddetailactivity) | R14 | Cash ledger; missing |
| 37 | [catalogue.CatalogueActivity](../vyapar-rea/SCREEN_REGISTRY.md#cataloguecatalogueactivity) | O20 | Storefront; missing |
| 38 | [catalogue.orderList.OrderListActivity](../vyapar-rea/SCREEN_REGISTRY.md#catalogueorderlistorderlistactivity) | O20 | Storefront; missing |
| 39 | [catalogue.store.reports.presentation.StoreReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#cataloguestorereportspresentationstorereportactivity) | O20 | Storefront; missing |
| 40 | [chequedetail.activity.ChequeListActivity](../vyapar-rea/SCREEN_REGISTRY.md#chequedetailactivitychequelistactivity) | R16 | Cheques; missing |
| 41 | [chequedetail.activity.CloseChequeActivity](../vyapar-rea/SCREEN_REGISTRY.md#chequedetailactivityclosechequeactivity) | R16 | Cheques; missing |
| 42 | [closebook.CloseBookActivity](../vyapar-rea/SCREEN_REGISTRY.md#closebookclosebookactivity) | R25 / O12 | Closing and backup; new workflow |
| 43 | [companies.ManageCompaniesActivity](../vyapar-rea/SCREEN_REGISTRY.md#companiesmanagecompaniesactivity) | A04 / A05 | Companies/profile; firms missing |
| 44 | [customerprofiling.ui.activities.CustomerProfilingActivity](../vyapar-rea/SCREEN_REGISTRY.md#customerprofilinguiactivitiescustomerprofilingactivity) | I28 | Named integration candidate; behavior discovery |
| 45 | [CustomHeaderSettingActivity](../vyapar-rea/SCREEN_REGISTRY.md#customheadersettingactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 46 | [CustomizedReport](../vyapar-rea/SCREEN_REGISTRY.md#customizedreport) | R01–R24 | Report family; consult individual report rows |
| 47 | [CustomMessageSelectTxnActivity](../vyapar-rea/SCREEN_REGISTRY.md#custommessageselecttxnactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 48 | [DeleteAuthenticationActivity](../vyapar-rea/SCREEN_REGISTRY.md#deleteauthenticationactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 49 | [DeliveryChallan.DeliveryChallanActivity](../vyapar-rea/SCREEN_REGISTRY.md#deliverychallandeliverychallanactivity) | T14 / F27 | Challan/transport; missing |
| 50 | [DeliveryChallan.DeliveryChallanConversionActivity](../vyapar-rea/SCREEN_REGISTRY.md#deliverychallandeliverychallanconversionactivity) | T14 / F27 | Challan/transport; missing |
| 51 | [DeliveryDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#deliverydetailsactivity) | T14 / F27 | Challan/transport; missing |
| 52 | [devicemigration.DeviceSupportDropAccessBlockedActivity](../vyapar-rea/SCREEN_REGISTRY.md#devicemigrationdevicesupportdropaccessblockedactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 53 | [DiscountReport](../vyapar-rea/SCREEN_REGISTRY.md#discountreport) | R21 | Discount reports; missing |
| 54 | [dms.FieldSalesmanOrdersActivity](../vyapar-rea/SCREEN_REGISTRY.md#dmsfieldsalesmanordersactivity) | I27 | Field sales; missing |
| 55 | [dms.FieldSalesmanTaskActivity](../vyapar-rea/SCREEN_REGISTRY.md#dmsfieldsalesmantaskactivity) | I27 | Field sales; missing |
| 56 | [dms.LeadActivity](../vyapar-rea/SCREEN_REGISTRY.md#dmsleadactivity) | I27 | Field sales; missing |
| 57 | [dms.LeadsActivity](../vyapar-rea/SCREEN_REGISTRY.md#dmsleadsactivity) | I27 | Field sales; missing |
| 58 | [DriveAutoBackupSettingActivity](../vyapar-rea/SCREEN_REGISTRY.md#driveautobackupsettingactivity) | O12–O14 | Backup/restore; mobile manual exists |
| 59 | [EditTxnMessageActivity](../vyapar-rea/SCREEN_REGISTRY.md#edittxnmessageactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 60 | [einvoice.EInvoiceActivity](../vyapar-rea/SCREEN_REGISTRY.md#einvoiceeinvoiceactivity) | R26 / R27 | E-documents; missing |
| 61 | [EstimateDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#estimatedetailsactivity) | T10 | Quotation; missing |
| 62 | [ewaybill.EWayBillActivity](../vyapar-rea/SCREEN_REGISTRY.md#ewaybillewaybillactivity) | R26 / R27 | E-documents; missing |
| 63 | [expense.ExpenseActivity](../vyapar-rea/SCREEN_REGISTRY.md#expenseexpenseactivity) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 64 | [ExpenseOrOtherIncomeCategoryListActivity](../vyapar-rea/SCREEN_REGISTRY.md#expenseorotherincomecategorylistactivity) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 65 | [ExpenseorOtherIncomeCategoryReport](../vyapar-rea/SCREEN_REGISTRY.md#expenseorotherincomecategoryreport) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 66 | [ExpenseorOtherIncomeItemReport](../vyapar-rea/SCREEN_REGISTRY.md#expenseorotherincomeitemreport) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 67 | [ExportItemsActivity](../vyapar-rea/SCREEN_REGISTRY.md#exportitemsactivity) | I16 / I17 | Item import/export; existing narrower workflow |
| 68 | [financialYearOnBoard.presentation.FinancialYearOnBoardActivity](../vyapar-rea/SCREEN_REGISTRY.md#financialyearonboardpresentationfinancialyearonboardactivity) | R25 / O12 | Closing and backup; new workflow |
| 69 | [fixedAsset.view.AddOrEditFixedAssetActivity](../vyapar-rea/SCREEN_REGISTRY.md#fixedassetviewaddoreditfixedassetactivity) | R18 / T16 | Assets; missing |
| 70 | [fixedAsset.view.FixedAssetDetailActivity](../vyapar-rea/SCREEN_REGISTRY.md#fixedassetviewfixedassetdetailactivity) | R18 / T16 | Assets; missing |
| 71 | [fixedAsset.view.FixedAssetsListActivity](../vyapar-rea/SCREEN_REGISTRY.md#fixedassetviewfixedassetslistactivity) | R18 / T16 | Assets; missing |
| 72 | [GraphActivity](../vyapar-rea/SCREEN_REGISTRY.md#graphactivity) | R01–R24 | Report family; consult individual report rows |
| 73 | [greetings.uilayer.views.WhatsappCardsActivity](../vyapar-rea/SCREEN_REGISTRY.md#greetingsuilayerviewswhatsappcardsactivity) | O25 | Growth/rewards; missing |
| 74 | [GroupListActivity](../vyapar-rea/SCREEN_REGISTRY.md#grouplistactivity) | I21 / R20 | Party grouping; missing |
| 75 | [GroupToSend](../vyapar-rea/SCREEN_REGISTRY.md#grouptosend) | I21 / R20 | Party grouping; missing |
| 76 | [home.HomeActivity](../vyapar-rea/SCREEN_REGISTRY.md#homehomeactivity) | A12 / A11 | Shell/search/routing; partial |
| 77 | [HSNLookUpActivity](../vyapar-rea/SCREEN_REGISTRY.md#hsnlookupactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 78 | [ImportItemFileChooserActivity](../vyapar-rea/SCREEN_REGISTRY.md#importitemfilechooseractivity) | I16 / I17 | Item import/export; existing narrower workflow |
| 79 | [importItems.ImportItemsActivity](../vyapar-rea/SCREEN_REGISTRY.md#importitemsimportitemsactivity) | I16 / I17 | Item import/export; existing narrower workflow |
| 80 | [importItems.itemLibrary.view.ItemLibraryActivity](../vyapar-rea/SCREEN_REGISTRY.md#importitemsitemlibraryviewitemlibraryactivity) | I16 / I17 | Item import/export; existing narrower workflow |
| 81 | [importItems.msExcel.ImportMsExcelItemActivity](../vyapar-rea/SCREEN_REGISTRY.md#importitemsmsexcelimportmsexcelitemactivity) | I16 / I17 | Item import/export; existing narrower workflow |
| 82 | [importMBB.ImportMyBillBookActivity](../vyapar-rea/SCREEN_REGISTRY.md#importmbbimportmybillbookactivity) | O17 | Third-party import; missing, compatibility unknown |
| 83 | [importparty.ImportPartyActivity](../vyapar-rea/SCREEN_REGISTRY.md#importpartyimportpartyactivity) | I24 | Party import; missing |
| 84 | [ImportPartyFileChooserActivity](../vyapar-rea/SCREEN_REGISTRY.md#importpartyfilechooseractivity) | I24 | Party import; missing |
| 85 | [indiamart.ui.activities.IndiaMartActivity](../vyapar-rea/SCREEN_REGISTRY.md#indiamartuiactivitiesindiamartactivity) | I28 | Named integration candidate; behavior discovery |
| 86 | [InputReminderMessage](../vyapar-rea/SCREEN_REGISTRY.md#inputremindermessage) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 87 | [InvalidBuildActivity](../vyapar-rea/SCREEN_REGISTRY.md#invalidbuildactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 88 | [item.activities.TrendingAddItemsToCategoryActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingadditemstocategoryactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 89 | [item.activities.TrendingAddItemsToUnitActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingadditemstounitactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 90 | [item.activities.TrendingItemActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingitemactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 91 | [item.activities.TrendingItemAdjustmentActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingitemadjustmentactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 92 | [item.activities.TrendingItemBulkOperationActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingitembulkoperationactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 93 | [item.activities.TrendingItemCategoryDetail](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingitemcategorydetail) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 94 | [item.activities.TrendingItemDetailActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingitemdetailactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 95 | [item.activities.TrendingItemUnitConversion](../vyapar-rea/SCREEN_REGISTRY.md#itemactivitiestrendingitemunitconversion) | I08 | Unit conversion; missing |
| 96 | [ItemCategorySalePurchaseReport](../vyapar-rea/SCREEN_REGISTRY.md#itemcategorysalepurchasereport) | R01–R24 | Report family; consult individual report rows |
| 97 | [ItemCategoryStockSummaryReport](../vyapar-rea/SCREEN_REGISTRY.md#itemcategorystocksummaryreport) | R01–R24 | Report family; consult individual report rows |
| 98 | [itemCustomFields.ItemCustomFieldSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemcustomfieldsitemcustomfieldsettingsactivity) | I11–I13 / F24 | Advanced item attributes; partial/missing |
| 99 | [ItemDetailReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemdetailreportactivity) | R01–R24 | Report family; consult individual report rows |
| 100 | [ItemImportConfirmationActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemimportconfirmationactivity) | I16 / I17 | Item import/export; existing narrower workflow |
| 101 | [ItemReportByParty](../vyapar-rea/SCREEN_REGISTRY.md#itemreportbyparty) | I26 / R20 | Statements and cross reports; partial |
| 102 | [itemScreens.views.ItemActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemscreensviewsitemactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 103 | [ItemSelectionDialogActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemselectiondialogactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 104 | [ItemStockTrackingReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemstocktrackingreportactivity) | I11 / I13 / R22 | Tracking reports; partial/missing |
| 105 | [ItemWiseProfitAndLossReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#itemwiseprofitandlossreportactivity) | R02 / R19 | Profit reports; existing narrower coverage |
| 106 | [LearnVyapar](../vyapar-rea/SCREEN_REGISTRY.md#learnvyapar) | O26 | Support/inbox; partial |
| 107 | [lineItem.activity.LineItemActivity](../vyapar-rea/SCREEN_REGISTRY.md#lineitemactivitylineitemactivity) | I01–I18 / F12–F24 | Catalog/line entry; existing narrower scope |
| 108 | [loanaccounts.activities.AddLoanAccountActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiesaddloanaccountactivity) | R17 | Loans; missing |
| 109 | [loanaccounts.activities.LoanAccountsActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiesloanaccountsactivity) | R17 | Loans; missing |
| 110 | [loanaccounts.activities.LoanDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiesloandetailsactivity) | R17 | Loans; missing |
| 111 | [loanaccounts.activities.LoanExpenseActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiesloanexpenseactivity) | R17 | Loans; missing |
| 112 | [loanaccounts.activities.LoanStatementActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiesloanstatementactivity) | R17 | Loans; missing |
| 113 | [loanaccounts.activities.LoanTxnActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiesloantxnactivity) | R17 | Loans; missing |
| 114 | [loanaccounts.activities.PayEmiActivity](../vyapar-rea/SCREEN_REGISTRY.md#loanaccountsactivitiespayemiactivity) | R17 | Loans; missing |
| 115 | [loyalty.dashboard.LoyaltyDashboardActivity](../vyapar-rea/SCREEN_REGISTRY.md#loyaltydashboardloyaltydashboardactivity) | O22 / F28 | Loyalty; missing |
| 116 | [loyalty.parties.AllPartiesActivity](../vyapar-rea/SCREEN_REGISTRY.md#loyaltypartiesallpartiesactivity) | O22 / F28 | Loyalty; missing |
| 117 | [loyalty.setup.LoyaltySetupActivity](../vyapar-rea/SCREEN_REGISTRY.md#loyaltysetuployaltysetupactivity) | O22 / F28 | Loyalty; missing |
| 118 | [loyalty.txns.LoyaltyPartyTransactionsActivity](../vyapar-rea/SCREEN_REGISTRY.md#loyaltytxnsloyaltypartytransactionsactivity) | O22 / F28 | Loyalty; missing |
| 119 | [m2dFeatures.M2DFeaturesActivity](../vyapar-rea/SCREEN_REGISTRY.md#m2dfeaturesm2dfeaturesactivity) | A12 / O26 | Generic wrapper/route; behavior unresolved |
| 120 | [manufacturing.ui.activities.DefaultAssemblyActivity](../vyapar-rea/SCREEN_REGISTRY.md#manufacturinguiactivitiesdefaultassemblyactivity) | I15 / R22 | Manufacturing; missing |
| 121 | [manufacturing.ui.activities.ManufacturingActivity](../vyapar-rea/SCREEN_REGISTRY.md#manufacturinguiactivitiesmanufacturingactivity) | I15 / R22 | Manufacturing; missing |
| 122 | [manufacturing.ui.activities.ManufacturingReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#manufacturinguiactivitiesmanufacturingreportactivity) | I15 / R22 | Manufacturing; missing |
| 123 | [manufacturing.ui.activities.RawMaterialActivity](../vyapar-rea/SCREEN_REGISTRY.md#manufacturinguiactivitiesrawmaterialactivity) | I15 / R22 | Manufacturing; missing |
| 124 | [MessageToSendToParty](../vyapar-rea/SCREEN_REGISTRY.md#messagetosendtoparty) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 125 | [MPosActivity](../vyapar-rea/SCREEN_REGISTRY.md#mposactivity) | T01–T22 / F01–F28 | Transaction family; consult individual rows |
| 126 | [MultifirmSettingActivity](../vyapar-rea/SCREEN_REGISTRY.md#multifirmsettingactivity) | A04 / A05 | Companies/profile; firms missing |
| 127 | [NewCompany](../vyapar-rea/SCREEN_REGISTRY.md#newcompany) | A04 / A05 | Companies/profile; firms missing |
| 128 | [newDesign.onboardingTutorial.OnBoardingTutorialActivity](../vyapar-rea/SCREEN_REGISTRY.md#newdesignonboardingtutorialonboardingtutorialactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 129 | [newDesign.partyDetails.PartyDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#newdesignpartydetailspartydetailsactivity) | I19–I26 | Party lifecycle; basic master exists, review missing |
| 130 | [newftu.InvoiceCustomizationActivity](../vyapar-rea/SCREEN_REGISTRY.md#newftuinvoicecustomizationactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 131 | [newftu.OtpVerificationActivity](../vyapar-rea/SCREEN_REGISTRY.md#newftuotpverificationactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 132 | [newftu.preSignupA.PreSignupAActivity](../vyapar-rea/SCREEN_REGISTRY.md#newftupresignupapresignupaactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 133 | [newftu.preSignupB.PreSignupBActivity](../vyapar-rea/SCREEN_REGISTRY.md#newftupresignupbpresignupbactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 134 | [newftu.SignUpActivity](../vyapar-rea/SCREEN_REGISTRY.md#newftusignupactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 135 | [newftu.ui.FirstSaleInvoicePreviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#newftuuifirstsaleinvoicepreviewactivity) | R26 / R27 | E-documents; missing |
| 136 | [newftu.ui.FTUTooltipDialog](../vyapar-rea/SCREEN_REGISTRY.md#newftuuiftutooltipdialog) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 137 | [newreports.itemwiseDiscountReport.ItemWiseDiscountDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#newreportsitemwisediscountreportitemwisediscountdetailsactivity) | R21 | Discount reports; missing |
| 138 | [newreports.itemwiseDiscountReport.ItemWiseDiscountReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#newreportsitemwisediscountreportitemwisediscountreportactivity) | R21 | Discount reports; missing |
| 139 | [newreports.PartyReportByItemActivity](../vyapar-rea/SCREEN_REGISTRY.md#newreportspartyreportbyitemactivity) | I26 / R20 | Statements and cross reports; partial |
| 140 | [newreports.SerialReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#newreportsserialreportactivity) | I11 / I13 / R22 | Tracking reports; partial/missing |
| 141 | [NewTransactionActivity](../vyapar-rea/SCREEN_REGISTRY.md#newtransactionactivity) | T01–T22 / F01–F28 | Transaction family; consult individual rows |
| 142 | [NotificationTargetActivity](../vyapar-rea/SCREEN_REGISTRY.md#notificationtargetactivity) | A12 / A11 | Shell/search/routing; partial |
| 143 | [nps.NPSFeedbackActivity](../vyapar-rea/SCREEN_REGISTRY.md#npsnpsfeedbackactivity) | O26 | Support/inbox; partial |
| 144 | [orderdetail.OrderDetailActivity](../vyapar-rea/SCREEN_REGISTRY.md#orderdetailorderdetailactivity) | T12 / T13 / R22 | Order lifecycle; missing |
| 145 | [OrderItemReport](../vyapar-rea/SCREEN_REGISTRY.md#orderitemreport) | T12 / T13 / R22 | Order lifecycle; missing |
| 146 | [OrderTxnReport](../vyapar-rea/SCREEN_REGISTRY.md#ordertxnreport) | T12 / T13 / R22 | Order lifecycle; missing |
| 147 | [OtherIncomeReport](../vyapar-rea/SCREEN_REGISTRY.md#otherincomereport) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 148 | [p2ptransfer.P2pTransferActivity](../vyapar-rea/SCREEN_REGISTRY.md#p2ptransferp2ptransferactivity) | T17 | Party transfer; missing |
| 149 | [partnerstore.activity.PartnerStoreActivity](../vyapar-rea/SCREEN_REGISTRY.md#partnerstoreactivitypartnerstoreactivity) | I28 | Named integration candidate; behavior discovery |
| 150 | [PartyGroupDetailActivity](../vyapar-rea/SCREEN_REGISTRY.md#partygroupdetailactivity) | I21 / R20 | Party grouping; missing |
| 151 | [PartyGroupSalePurchaseReport](../vyapar-rea/SCREEN_REGISTRY.md#partygroupsalepurchasereport) | I21 / R20 | Party grouping; missing |
| 152 | [PartyImportConfirmationActivity](../vyapar-rea/SCREEN_REGISTRY.md#partyimportconfirmationactivity) | I24 | Party import; missing |
| 153 | [PartyReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#partyreportactivity) | I26 / R20 | Statements and cross reports; partial |
| 154 | [PartyToSend](../vyapar-rea/SCREEN_REGISTRY.md#partytosend) | A12 / O26 | Generic wrapper/route; behavior unresolved |
| 155 | [PasscodeCheck](../vyapar-rea/SCREEN_REGISTRY.md#passcodecheck) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 156 | [payment.bank.account.BankAccountActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentbankaccountbankaccountactivity) | R15 | Bank ledger; missing |
| 157 | [payment.bank.adjustment.BankAdjustmentActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentbankadjustmentbankadjustmentactivity) | R15 | Bank ledger; missing |
| 158 | [payment.bank.details.BankDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentbankdetailsbankdetailsactivity) | R15 | Bank ledger; missing |
| 159 | [payment.bank.list.BankListActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentbanklistbanklistactivity) | R15 | Bank ledger; missing |
| 160 | [paymentgateway.kyc.activity.ChargesWebviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivitychargeswebviewactivity) | O21 | Payment gateway/KYC; missing |
| 161 | [paymentgateway.kyc.activity.IFSCWebViewActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivityifscwebviewactivity) | O21 | Payment gateway/KYC; missing |
| 162 | [paymentgateway.kyc.activity.KycIntroScreen](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivitykycintroscreen) | O21 | Payment gateway/KYC; missing |
| 163 | [paymentgateway.kyc.activity.KycVerificationActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivitykycverificationactivity) | O21 | Payment gateway/KYC; missing |
| 164 | [paymentgateway.kyc.activity.LoginWebviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivityloginwebviewactivity) | O21 | Payment gateway/KYC; missing |
| 165 | [paymentgateway.kyc.activity.OnlinePaymentWebviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivityonlinepaymentwebviewactivity) | O21 | Payment gateway/KYC; missing |
| 166 | [paymentgateway.kyc.activity.TermsAndConditionWebviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentgatewaykycactivitytermsandconditionwebviewactivity) | O21 | Payment gateway/KYC; missing |
| 167 | [PaymentReminderActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentreminderactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 168 | [PaymentTermActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymenttermactivity) | F07 | Terms; purchase exists, sales incomplete |
| 169 | [PaymentWebsiteActivity](../vyapar-rea/SCREEN_REGISTRY.md#paymentwebsiteactivity) | O21 | Payment gateway/KYC; missing |
| 170 | [planandpricing.licenseupgrade.UpgradeLicenseActivity](../vyapar-rea/SCREEN_REGISTRY.md#planandpricinglicenseupgradeupgradelicenseactivity) | O27 | Subscription; independent Storely lifecycle exists |
| 171 | [planandpricing.pricing.PlanAndPricingActivity](../vyapar-rea/SCREEN_REGISTRY.md#planandpricingpricingplanandpricingactivity) | O27 | Subscription; independent Storely lifecycle exists |
| 172 | [printerstore.activity.PrinterStoreActivity](../vyapar-rea/SCREEN_REGISTRY.md#printerstoreactivityprinterstoreactivity) | O07–O09 | Print hardware; Bluetooth exists, transports incomplete |
| 173 | [PrintTxnItemTableSettingActivity](../vyapar-rea/SCREEN_REGISTRY.md#printtxnitemtablesettingactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 174 | [ReceivablePayableDashboardActivity](../vyapar-rea/SCREEN_REGISTRY.md#receivablepayabledashboardactivity) | R03 / R04 | Aging/outstanding; existing narrower coverage |
| 175 | [recycleBin.presentation.RecycleBinActivity](../vyapar-rea/SCREEN_REGISTRY.md#recyclebinpresentationrecyclebinactivity) | T21 | Recycle bin; missing |
| 176 | [referAndEarn.presentation.ReferAndEarnActivity](../vyapar-rea/SCREEN_REGISTRY.md#referandearnpresentationreferandearnactivity) | O25 | Growth/rewards; missing |
| 177 | [referral.ReferralRewardsActivity](../vyapar-rea/SCREEN_REGISTRY.md#referralreferralrewardsactivity) | O25 | Growth/rewards; missing |
| 178 | [referral.ReferralScratchCardsActivity](../vyapar-rea/SCREEN_REGISTRY.md#referralreferralscratchcardsactivity) | O25 | Growth/rewards; missing |
| 179 | [reports.aging.presentation.SalePurchaseAgingReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsagingpresentationsalepurchaseagingreportactivity) | R03 / R04 | Aging/outstanding; existing narrower coverage |
| 180 | [reports.balanceSheet.presentation.BalanceSheetActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsbalancesheetpresentationbalancesheetactivity) | R13 / R14 | Financial statements; missing |
| 181 | [reports.billWiseProfitAndLoss.presentation.BillWiseProfitLossReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsbillwiseprofitandlosspresentationbillwiseprofitlossreportactivity) | R02 / R19 | Profit reports; existing narrower coverage |
| 182 | [reports.billWiseProfitAndLoss.presentation.ProfitOnInvoiceActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsbillwiseprofitandlosspresentationprofitoninvoiceactivity) | R02 / R19 | Profit reports; existing narrower coverage |
| 183 | [reports.cashflow.ui.CashFlowReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportscashflowuicashflowreportactivity) | R13 / R14 | Financial statements; missing |
| 184 | [reports.dayBookReport.presentation.DayBookReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsdaybookreportpresentationdaybookreportactivity) | R01 | Day book; existing |
| 185 | [reports.gstr.presentation.GSTR1ReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsgstrpresentationgstr1reportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 186 | [reports.gstr.presentation.GSTR2ReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsgstrpresentationgstr2reportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 187 | [reports.gstr.presentation.GSTR3BReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsgstrpresentationgstr3breportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 188 | [reports.gstr.presentation.GSTR4ReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsgstrpresentationgstr4reportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 189 | [reports.gstr.presentation.GSTRTxnReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsgstrpresentationgstrtxnreportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 190 | [reports.hsnorsac.HsnOrSacReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportshsnorsachsnorsacreportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 191 | [reports.outstandingTxnDetails.presentation.OutstandingTxnDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsoutstandingtxndetailspresentationoutstandingtxndetailsactivity) | R03 / R04 | Aging/outstanding; existing narrower coverage |
| 192 | [reports.partyStatement.presentation.PartyStatementReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportspartystatementpresentationpartystatementreportactivity) | I26 / R20 | Statements and cross reports; partial |
| 193 | [reports.partyWiseProfitLoss.presentation.PartyWiseProfitLossActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportspartywiseprofitlosspresentationpartywiseprofitlossactivity) | R02 / R19 | Profit reports; existing narrower coverage |
| 194 | [reports.profitAndLoss.presentation.ProfitAndLossReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsprofitandlosspresentationprofitandlossreportactivity) | R02 / R19 | Profit reports; existing narrower coverage |
| 195 | [reports.salePurchaseByParty.presentation.PartyWiseSalePurchaseReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportssalepurchasebypartypresentationpartywisesalepurchasereportactivity) | R01–R24 | Report family; consult individual report rows |
| 196 | [reports.salePurchaseExpense.presentation.SalePurchaseExpenseReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportssalepurchaseexpensepresentationsalepurchaseexpensereportactivity) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 197 | [reports.scheduleReports.ReportScheduleActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsschedulereportsreportscheduleactivity) | R23 | Scheduled reports; missing |
| 198 | [reports.stockAndLowStockSummary.presentation.ItemSummaryReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsstockandlowstocksummarypresentationitemsummaryreportactivity) | R01–R24 | Report family; consult individual report rows |
| 199 | [reports.stockDetails.presentation.StockDetailReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsstockdetailspresentationstockdetailreportactivity) | R01–R24 | Report family; consult individual report rows |
| 200 | [reports.stockTransfer.presentation.StockTransferReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsstocktransferpresentationstocktransferreportactivity) | I14 / A06 | Stores/transfers; missing |
| 201 | [reports.stockTransfer.presentation.StockTransferTxnDetailReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsstocktransferpresentationstocktransfertxndetailreportactivity) | I14 / A06 | Stores/transfers; missing |
| 202 | [reports.summaryByHsnReport.SummaryByHsnReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportssummarybyhsnreportsummarybyhsnreportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 203 | [reports.tds.ui.TdsReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportstdsuitdsreportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 204 | [reports.vat.presentation.Vat201ReturnActivity](../vyapar-rea/SCREEN_REGISTRY.md#reportsvatpresentationvat201returnactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 205 | [Searchresults](../vyapar-rea/SCREEN_REGISTRY.md#searchresults) | A12 / A11 | Shell/search/routing; partial |
| 206 | [SelectTransactionActivity](../vyapar-rea/SCREEN_REGISTRY.md#selecttransactionactivity) | T01–T22 / F01–F28 | Transaction family; consult individual rows |
| 207 | [serviceReminders.RemindersActivity](../vyapar-rea/SCREEN_REGISTRY.md#serviceremindersremindersactivity) | I26 / O18 / O19 | Messaging/reminders; manual slice exists |
| 208 | [settings.activities.GeneralSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesgeneralsettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 209 | [settings.activities.InvoicePrintSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesinvoiceprintsettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 210 | [settings.activities.ItemSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesitemsettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 211 | [settings.activities.MultiCurrencySettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesmulticurrencysettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 212 | [settings.activities.OriginalDuplicateSettingActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesoriginalduplicatesettingactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 213 | [settings.activities.PartySettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiespartysettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 214 | [settings.activities.PaymentReminderSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiespaymentremindersettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 215 | [settings.activities.ResizeItemTableActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesresizeitemtableactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 216 | [settings.activities.SettingsListActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiessettingslistactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 217 | [settings.activities.SettingsSearchActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiessettingssearchactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 218 | [settings.activities.TaxesAndGstSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiestaxesandgstsettingsactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 219 | [settings.activities.TermsAndConditionsSettingHostActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiestermsandconditionssettinghostactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 220 | [settings.activities.ThermalPrinterAdditionalItemDetailsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiesthermalprinteradditionalitemdetailsactivity) | O07–O09 | Print hardware; Bluetooth exists, transports incomplete |
| 221 | [settings.activities.TransactionSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiestransactionsettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 222 | [settings.activities.TransactionSmsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsactivitiestransactionsmsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 223 | [settings.ui.AcSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsuiacsettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 224 | [SettingsUDFScreens.UDFFirmTxnSettingsActivity](../vyapar-rea/SCREEN_REGISTRY.md#settingsudfscreensudffirmtxnsettingsactivity) | O04–O11 / F24 | Settings; field-level verification required |
| 225 | [SettingsUDFScreens.UDFPartySettings](../vyapar-rea/SCREEN_REGISTRY.md#settingsudfscreensudfpartysettings) | O04–O11 / F24 | Settings; field-level verification required |
| 226 | [ShareUtilsActivity](../vyapar-rea/SCREEN_REGISTRY.md#shareutilsactivity) | O01 / O02 / O04 | Output/media; existing narrower workflow |
| 227 | [splash.SplashActivity](../vyapar-rea/SCREEN_REGISTRY.md#splashsplashactivity) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 228 | [SplashActivityAlias](../vyapar-rea/SCREEN_REGISTRY.md#splashactivityalias) | A13 | Visual/launcher variant; excluded from refactor |
| 229 | [SplashActivityAliasChristmas](../vyapar-rea/SCREEN_REGISTRY.md#splashactivityaliaschristmas) | A13 | Visual/launcher variant; excluded from refactor |
| 230 | [SplashActivityAliasDiwali](../vyapar-rea/SCREEN_REGISTRY.md#splashactivityaliasdiwali) | A13 | Visual/launcher variant; excluded from refactor |
| 231 | [SplashActivityAliasIndependenceDay](../vyapar-rea/SCREEN_REGISTRY.md#splashactivityaliasindependenceday) | A13 | Visual/launcher variant; excluded from refactor |
| 232 | [SplashActivityAliasPongal](../vyapar-rea/SCREEN_REGISTRY.md#splashactivityaliaspongal) | A13 | Visual/launcher variant; excluded from refactor |
| 233 | [SplashActivityDefaultAlias](../vyapar-rea/SCREEN_REGISTRY.md#splashactivitydefaultalias) | A13 | Visual/launcher variant; excluded from refactor |
| 234 | [store.presentation.ui.AddOrEditStoreActivity](../vyapar-rea/SCREEN_REGISTRY.md#storepresentationuiaddoreditstoreactivity) | I14 / A06 | Stores/transfers; missing |
| 235 | [store.presentation.ui.ManageStoreActivity](../vyapar-rea/SCREEN_REGISTRY.md#storepresentationuimanagestoreactivity) | I14 / A06 | Stores/transfers; missing |
| 236 | [store.presentation.ui.StockTransferActivity](../vyapar-rea/SCREEN_REGISTRY.md#storepresentationuistocktransferactivity) | I14 / A06 | Stores/transfers; missing |
| 237 | [syncAndShare.activities.EditExpenseItemUserLogsActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncandshareactivitieseditexpenseitemuserlogsactivity) | T05 / T06 / R02 | Expenses exist; other-income/itemized extensions missing |
| 238 | [syncAndShare.activities.RelaunchAppAlertActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncandshareactivitiesrelaunchappalertactivity) | O15 / A04 | Sync; existing with aggregate parity work |
| 239 | [syncAndShare.activities.RolePermissionEditorActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncandshareactivitiesrolepermissioneditoractivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 240 | [syncAndShare.activities.SyncAndShareActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncandshareactivitiessyncandshareactivity) | O15 / A04 | Sync; existing with aggregate parity work |
| 241 | [syncAndShare.activities.SyncAndShareUserLogsActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncandshareactivitiessyncandshareuserlogsactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 242 | [syncAndShare.activities.UserProfileFormActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncandshareactivitiesuserprofileformactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 243 | [syncFlow.view.activity.SyncLoginActivity](../vyapar-rea/SCREEN_REGISTRY.md#syncflowviewactivitysyncloginactivity) | O15 / A04 | Sync; existing with aggregate parity work |
| 244 | [TaxActivity](../vyapar-rea/SCREEN_REGISTRY.md#taxactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 245 | [TaxRateReportActivity](../vyapar-rea/SCREEN_REGISTRY.md#taxratereportactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 246 | [TaxReport](../vyapar-rea/SCREEN_REGISTRY.md#taxreport) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 247 | [tcs.ManageTcsActivity](../vyapar-rea/SCREEN_REGISTRY.md#tcsmanagetcsactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 248 | [tcs.reports.TcsReport](../vyapar-rea/SCREEN_REGISTRY.md#tcsreportstcsreport) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 249 | [tcs.TcsActivity](../vyapar-rea/SCREEN_REGISTRY.md#tcstcsactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 250 | [tds.AddOrEditTdsActivity](../vyapar-rea/SCREEN_REGISTRY.md#tdsaddoredittdsactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 251 | [tds.ManageTdsActivity](../vyapar-rea/SCREEN_REGISTRY.md#tdsmanagetdsactivity) | R08–R12 / F15 | Tax surfaces; basic GST exists, advanced scope missing |
| 252 | [themechooseractivity.TransactionThemeChooserActivity](../vyapar-rea/SCREEN_REGISTRY.md#themechooseractivitytransactionthemechooseractivity) | A13 | Visual/launcher variant; excluded from refactor |
| 253 | [thermalprint.ui.addwifiprinter.AddWifiThermalPrinterActivity](../vyapar-rea/SCREEN_REGISTRY.md#thermalprintuiaddwifiprinteraddwifithermalprinteractivity) | O07–O09 | Print hardware; Bluetooth exists, transports incomplete |
| 254 | [thermalprint.ui.BuyThermalPrintersWebViewActivity](../vyapar-rea/SCREEN_REGISTRY.md#thermalprintuibuythermalprinterswebviewactivity) | O07–O09 | Print hardware; Bluetooth exists, transports incomplete |
| 255 | [thermalprint.ui.ThermalPrinterActivity](../vyapar-rea/SCREEN_REGISTRY.md#thermalprintuithermalprinteractivity) | O07–O09 | Print hardware; Bluetooth exists, transports incomplete |
| 256 | [transaction.ui.AdditionalChargeForTxnActivity](../vyapar-rea/SCREEN_REGISTRY.md#transactionuiadditionalchargefortxnactivity) | F16 | Charges; purchase scalar only |
| 257 | [ui.party.party.ui.party.PartyActivity](../vyapar-rea/SCREEN_REGISTRY.md#uipartypartyuipartypartyactivity) | I19–I26 | Party lifecycle; basic master exists, review missing |
| 258 | [ui.party.party.ui.review.PartiesForReviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#uipartypartyuireviewpartiesforreviewactivity) | I19–I26 | Party lifecycle; basic master exists, review missing |
| 259 | [UserBusinessCategoryFTU](../vyapar-rea/SCREEN_REGISTRY.md#userbusinesscategoryftu) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 260 | [UserObjectiveFTU](../vyapar-rea/SCREEN_REGISTRY.md#userobjectiveftu) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 261 | [UserProfessionFTU](../vyapar-rea/SCREEN_REGISTRY.md#userprofessionftu) | A01–A03 / A11 | Onboarding/startup; partial, gates need discovery |
| 262 | [userRolePermission.activity.NoPermissionBottomSheetActivity](../vyapar-rea/SCREEN_REGISTRY.md#userrolepermissionactivitynopermissionbottomsheetactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 263 | [userRolePermission.admin.AddPrimaryAdminActivity](../vyapar-rea/SCREEN_REGISTRY.md#userrolepermissionadminaddprimaryadminactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 264 | [userRolePermission.login.LoginDialog](../vyapar-rea/SCREEN_REGISTRY.md#userrolepermissionloginlogindialog) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 265 | [userRolePermission.logs.SecurityLogNewActivity](../vyapar-rea/SCREEN_REGISTRY.md#userrolepermissionlogssecuritylognewactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 266 | [userRolePermission.UserManagementActivity](../vyapar-rea/SCREEN_REGISTRY.md#userrolepermissionusermanagementactivity) | A07–A10 | Access/security; fixed roles exist, configurable scope missing |
| 267 | [vaani.VaaniConversationActivity](../vyapar-rea/SCREEN_REGISTRY.md#vaanivaaniconversationactivity) | I28 | Named integration candidate; behavior discovery |
| 268 | [VerifyFileNegativeResultActivity](../vyapar-rea/SCREEN_REGISTRY.md#verifyfilenegativeresultactivity) | O12–O14 | Backup/restore; mobile manual exists |
| 269 | [ViewOrEditTransactionDetailActivity](../vyapar-rea/SCREEN_REGISTRY.md#vieworedittransactiondetailactivity) | T01–T22 / F01–F28 | Transaction family; consult individual rows |
| 270 | [vyaparNetwork.activity.VyaparNetworkActivity](../vyapar-rea/SCREEN_REGISTRY.md#vyaparnetworkactivityvyaparnetworkactivity) | I28 | Named integration candidate; behavior discovery |
| 271 | [vyaparNetwork.activity.VyaparNetworkInvoicePreviewActivity](../vyapar-rea/SCREEN_REGISTRY.md#vyaparnetworkactivityvyaparnetworkinvoicepreviewactivity) | I28 | Named integration candidate; behavior discovery |
| 272 | [whatsnew.WhatsNewActivity](../vyapar-rea/SCREEN_REGISTRY.md#whatsnewwhatsnewactivity) | O26 | Support/inbox; partial |
| 273 | [youtube.YouTubePlayerActivity](../vyapar-rea/SCREEN_REGISTRY.md#youtubeyoutubeplayeractivity) | O26 | Support/inbox; partial |

### 11.2 Corpus provenance and remaining granular coverage

The checksums below identify the reference documents used for this plan. A file hash records the input version; it does not certify every statement or XML node was behaviorally verified.

| Reference file | Lines | SHA-256 |
|---|---:|---|
| [ADVERTISING_MODULE.md](../vyapar-rea/ADVERTISING_MODULE.md) | 125 | `de0053845fbf84e3f9156473a364f1fbd6db6b11ec13ca8fd9e25ad631306a8f` |
| [APP_FLOWS.md](../vyapar-rea/APP_FLOWS.md) | 56 | `133f5cd605056cf93c573c73423eb4208c68021847d62b35ce293651f56d988c` |
| [BUSINESS_RULES.md](../vyapar-rea/BUSINESS_RULES.md) | 173 | `4dba34d61d1419760da2cd0729772c9471760e3bcc85d83b140aef3fb2d86fb6` |
| [CLONE_SPEC.md](../vyapar-rea/CLONE_SPEC.md) | 53 | `0311bd9ffecf98b861ce2c4b9a16e2fb232fc2186e29517878773a81f3268ca2` |
| [DOCUMENT_OUTPUT.md](../vyapar-rea/DOCUMENT_OUTPUT.md) | 15 | `3c340b3ee25b5373493c97d152931e0736f5ea385263b0b69e7e3b4dc26a4eb9` |
| [ENTRY_POINTS.md](../vyapar-rea/ENTRY_POINTS.md) | 583 | `a4595a8f4b09a98488785f6d5da038c9951dfd86c5445270e220ed6eee016778` |
| [ERROR_CATALOG.md](../vyapar-rea/ERROR_CATALOG.md) | 675 | `b07c8b4417b08a195fa1f5e24f8a951fdc67b65656c13418bda066b2bd3ac524` |
| [SCREEN_REGISTRY.md](../vyapar-rea/SCREEN_REGISTRY.md) | 2254 | `8b8a0bd0c9f94c96f60b2485c96611be30ec7d5a43fdaacb88c36f644c919523` |
| [SETTINGS.md](../vyapar-rea/SETTINGS.md) | 205 | `a9a12f6ddcd892a65da72fa0daa67ecb198251c3bec143d4fd720548cd3c773b` |
| [STORAGE_AND_SYNC.md](../vyapar-rea/STORAGE_AND_SYNC.md) | 756 | `ac10c0b78da7be7dc28fc8d6c91c6f3fe6e281a456f8d1ad5d50dcd9b8fdd654` |
| [XML_SURFACES.md](../vyapar-rea/XML_SURFACES.md) | 19516 | `5b55cad090e5757a3dd6b51dfc22fdbf870f50ec8bcf02456169522b974d354b` |

The XML inventory includes structural/vendor resources, alternative layouts and child dialogs, so reproducing it as thousands of “missing features” would be misleading. Implementation must expand the owning feature row into a field checklist using the cited XML section: control name, semantic purpose, type/scale, requiredness, default, conditional visibility, permissions, persisted column, print/report effect, validation code and paired acceptance scenario. Unbound labels stay unresolved.

Similarly, `ERROR_CATALOG.md` contains message candidates, not a proven error-state machine. For each implemented module, classify its relevant messages into invalid input, missing/deleted dependency, duplicate identity, no permission, offline, timeout/unknown result, conflict, corrupt file, permission-denied hardware, empty/loading and retry/cancel. Record whether the attempt changed data and whether retry reuses the operation ID. No release may leave a financial failure mapped only to an opaque exception string.

`ENTRY_POINTS.md` additionally covers fragments, receivers, services and external intents; these require ownership by their business flow. App-owned deep links must validate tenant/role, restore the intended destination after login and refuse stale/malformed identifiers. Backup intents must inspect content rather than trusting an extension. Printer/scan permission results, notification taps and activity restoration must re-enter the same workflow state without replaying a commit.

### 11.3 Extended-module acceptance details

- **Loyalty (O22):** setup → preview examples → enable → party points/ledger → sale earn/redeem → expiry/adjustment → return/reversal. Cover minimum spend, spend-to-point conversion, redemption value, maximum percentage, opening date, unique-party identification, disable behavior and historical settings snapshots. No exact rounding or expiry schedule is established by the reference.
- **Storefront (O20):** configure profile/catalog/store prices → publish → customer cart/minimum order/delivery charge → submit → merchant accept/reject → fulfill/mark delivered → return/cancel → store reports. Inventory availability is authoritative at acceptance; public reads must not expose costs or private parties.
- **Payments (O21):** bank/KYC setup → pending/verified/rejected → link/checkout → provider processing → verified settlement → allocation → reconciliation/refund. A redirect or user-entered reference never confirms receipt of funds.
- **Field sales (I27):** create/assign lead → task with type/description/phone/address/location/attachments → complete/reschedule → party/order link → owner review. Enforce task dependencies on lead deletion and assignment permissions on both clients. Reference task type/status lists remain unknown.
- **Smart Ads (O23/O24):** business/category → goal/design request/media → area and age audience → budget/duration → integration → preview/approval/payment → publish/status/leads → extension. Validate region duplicates, budget/duration, revision limits and payment recovery only after provider contracts are established; the reference does not supply them.
- **Regional tax (R12):** separate country/tax registration profiles, identifier validation, currency and statutory output contracts. Preserve GST data; never reinterpret it when changing locale.
- **Growth/support (O25/O26):** referral eligibility/reward history and support/inbox/feedback states need independent requirements; no financial rewards without a defined earned/redeemed/reversed ledger. These are tracked gaps, not reasons to delay fixing current billing.

### 11.4 Audit completion checklist

- [x] Inspected the reference document inventory and evidence limitations.
- [x] Inventoried mobile/web/API routes, models, schema and domain source boundaries.
- [x] Compared core transaction, catalog, party, purchase, report, output, access and sync implementations.
- [x] Recorded confirmed source-level divergences and existing functionality to preserve.
- [x] Cataloged missing and partial feature families, with all native registry declarations mapped to the backlog.
- [x] Defined shared flows, architecture, migrations, phased implementation and acceptance gates.
- [ ] Execute every mobile/web workflow and verify runtime feature reachability.
- [ ] Complete every individual XML/control/validation branch mapping and resolve reference UNKNOWNs where necessary.
- [ ] Verify external provider behavior, actual stored production data and physical hardware.

The unchecked items are explicit implementation/discovery gates. This is a comprehensive source-based refactor plan, not a claim that every runtime branch in either product has already been tested.
