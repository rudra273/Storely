# Storely product and purchase implementation plan

Status: expanded end-to-end upgrade plan, version 2; no application changes made.
Research and code review: 29 October 2026.

## Outcome

Make everyday entry fast while keeping products, stock receipts, purchase costs, and supplier dues traceable. Web and Android should share business rules and terminology, with layouts suited to each device. Scope assumes small retail shops first; advanced procurement stays optional.

## Evidence and competitor comparison

| Product | Verified pattern | Lesson for Storely |
| --- | --- | --- |
| Vyapar | Separate item setup, opening stock, purchases, and stock adjustments; purchase bills, payment-out, supplier statements and purchase returns | Distinguish why stock changed and connect purchases to suppliers and payments |
| myBillBook | Purchase entry allows selecting/creating a supplier, adding items and attaching documents | Create missing suppliers/products inside the task, without losing the purchase |
| Khatabook | Official site advertises ledger, invoice, inventory and desktop/mobile sync | Maintain continuity across devices; exact purchase-screen parity was not verified |
| Zoho Inventory | Purchase receives track deliveries and can be converted to bills | Design for separate receipt and bill dates, partial deliveries and later billing, without requiring that complexity for ordinary purchases |
| Storely Android | Date and optional supplier first; add/import staged products; confirm batch; inline supplier creation | Preserve staging, optional supplier and atomic local commit; improve existing-product selection and recoverable drafts |
| Storely web | Product creation/opening stock, import preview and duplicate warning, stock adjustments, purchase report | Add the missing purchase workflow and supplier management; preserve existing useful preview and report features |

Sources:
- https://vyaparapp.in/guides/how-to-manage-stock-inventory-in-vyapar
- https://vyaparapp.in/blog/vyapar-app-features/
- https://knowledge.mybillbook.in/articles/8884620-how-to-create-a-purchase-voucher-in-mybillbook
- https://khatabook.com/
- https://www.zoho.com/us/inventory/help/purchase-orders/purchase-receive.html
- https://www.zoho.com/us/inventory/kb/bill/bill-creation.html

These are documented capabilities, not a hands-on usability benchmark. The UX below is a Storely recommendation, not a claim that competitors use every detail.

## 1. Shared entry points

Products has two visible actions: **Add product** and **Add purchase**. Low-stock rows and product details also offer **Restock**, opening Add purchase with the item selected. Keep Adjust stock for damage, loss, counts and other corrections.

Add product creates a catalog item, even with zero stock. A collapsed Opening stock section handles stock already owned when starting Storely: quantity, as-of date, and unit cost. Opening stock must not create supplier dues or appear as a new purchase. Warn that unknown opening cost makes valuation incomplete; do not silently equate unknown cost with zero.

Purchases gets its own list and details view, with supplier/date/status filters and a link from Reports. Suppliers gets a directory, editable profiles and purchase history. Payment balances appear only once the supplier-payment workflow ships.

## 2. Quick product setup

Show name, selling price and unit first. Require name; default unit to pieces. Permit products without a selling price to be saved as setup-incomplete, but require a valid price at billing. Offer explicit direct-price or automatic-price behavior consistently across clients; do not overwrite an existing formula when restocking.

Group optional fields into Codes and category, Tax, Stock and reorder level, and Batch/expiry or serial tracking when supported. Use barcode scanning and keyboard-friendly SKU search. Category/unit creation stays inline. Preserve entered values when validation fails.

Distinguish product identity from purchase lots: the same product can come from multiple suppliers, at different costs and dates. Supplier is a purchase attribute; a product may optionally retain a preferred supplier.

## 3. Add purchase UX

Open one composer with an editable header: purchase date defaults to shop-local today; supplier is optional with search and Add supplier. Supplier creation initially asks only for name; phone, GSTIN, address and notes are expandable. Select the new supplier immediately and retain the purchase draft.

Below the header: Search or scan product, Add new product, and Import file. Selecting an existing product shows current stock, last purchase cost as a suggestion, quantity and unit cost. No full product editor is needed for ordinary restocking. New products can be created inside the composer and staged with their first purchase quantity.

Show subtotal and a sticky Save purchase action. Expand Bill details for supplier invoice number/date, attachment and notes. Expand Charges and taxes for discounts, inclusive/exclusive tax and freight. Payment entry is optional; never silently assume paid or unpaid. Use a distinct Not recorded state until the user records terms/payment. Credit or partial-payment entries require a supplier.

Web: editable item table, predictable Tab/Enter navigation, visible totals and line errors. Android: compact editable item cards, scanning, numeric keyboards and a bottom total/save bar. Both retain draft edits across navigation and restart. Show whether drafts are saved locally, queued or synced. Initially, a draft may belong to one device; do not imply cross-device draft synchronization until implemented.

Confirmation saves all lines together. Show the saved purchase with View purchase and Add another actions. Never save partial stock silently. Error handling preserves the entire draft.

## 4. Import behavior

Make purpose explicit: **Import product catalog**, **Import opening stock**, or **Import purchase items**. Within Add purchase, purpose is already known and supplier/date come from its header.

Preview every row: source row number, matched product or proposed new item, quantity, unit cost, totals and validation errors. Allow corrections before confirming. Resolve identity by stable ID, code or barcode; name-only matches are suggestions when ambiguous. Do not silently merge different products with identical names.

Only combine repeated rows when product, unit, cost, batch, expiry and tax treatment match. Preserve distinct lots. Existing Android name-based aggregation needs review here. Explain changes to product pricing separately from purchase costs; do not silently change selling prices during a restock import.

Use a stable request ID to prevent duplicate saves on retries. Separately detect repeated supplier invoices and likely duplicate imports. A warning can allow intentional repeated imports; a retry of the same confirmed request must never add stock again. Current web duplicate detection uses file bytes and current UTC date, so it needs a durable, shop-scoped approach across dates and clients.

## 5. Data and API foundation

Introduce durable purchase headers and lines rather than treating a set of stock movements as the complete bill. Proposed records: purchases, purchase_items, purchase_payments/payment allocations and purchase_returns/return_items. Reuse supplier profiles and stock movements.

Purchase header: UUID, shop, optional supplier UUID and historical supplier snapshot, effective purchase/receipt date, optional supplier bill date and number, document state, payment-recording state, totals, currency, notes, attachment references, revision, author/device, created/updated timestamps and idempotency key. Document state and payment state are separate.

Lines: product UUID and name/unit snapshots, received quantity, conversion factor when applicable, unit cost, discounts, tax snapshots, lot/expiry or serial references and resulting stock-movement references. Payments capture actual amount, date and method; allocations determine outstanding balances.

Use decimal arithmetic and one documented rounding policy. Keep business dates separate from audit timestamps. Define purchase cost versus sale price, recoverable tax treatment, discounts and freight allocation before implementing totals. Verify the accounting policy with an appropriate domain reviewer before claiming accounting/tax completeness.

API should support draft/create, preview import, confirm, list/detail, correction/void, payment and return operations. Confirm validates shop ownership and permissions, then atomically writes purchase, lines, stock movements and applicable payments. Use unique constraints, optimistic revision checks and idempotency across the entire operation.

Android offline confirmation must use the same IDs and rules. Extend sync to preserve whole purchase transactions and dependencies, acknowledge retries safely and surface conflicts. A retry must not post an additional stock movement. Existing per-table sync needs an explicit compatibility design before implementation.

## 6. History, costs and corrections

Persist the supplier and cost snapshot on each purchase; changing today's product/supplier details must not rewrite old bills. Preserve original purchase date and audit timestamps. Purchase history shows quantities, costs and source bill; supplier history shows purchases and, when enabled, payments and balances.

Keep the existing cost model only after verifying parity across Android and API. Specify weighted-average behavior for zero/negative inventory, backdated purchases, returns, voids and already-sold stock. Decide whether historical cost of goods sold is recomputed or adjusted and expose that policy; do not casually overwrite historical margins.

Posted records require controlled corrections or reversal/replacement with an audit trail. Supplier returns are linked to original lines and costs, with explicit refund/credit treatment. Block or explain corrections that conflict with sold stock, returned quantities or allocated payments. Opening-stock corrections remain distinguishable from purchases.

Migrate historical stock movements conservatively. Preserve IDs and counts. Only group legacy entries when an existing reliable batch/document key supports it; do not guess that same-day entries belong to one supplier bill. Label uncertain history as legacy stock entries, with payment status unknown. Migration must not post stock again.

## 7. Delivery sequence and exit criteria

1. **Agree rules and prototype:** approve the above terminology and cost policy; prototype add product, restock, purchase and import on phone and desktop. Test with representative shop owners. Exit: users can identify the right action and complete each core scenario without guidance.
2. **Shared foundation:** schema/API, transaction IDs, decimals, dates, permissions, historical snapshots, migration and sync compatibility. Exit: atomic commit, retry safety and migration reconciliation pass before UI rollout.
3. **Core web and Android parity:** quick product entry, optional supplier/create inline, editable date, existing-item restock, multi-item drafts, import preview, purchase list/detail and reports. Ship tax/lot fields needed by supported shops before calling the purchase flow complete. Exit: both clients create equivalent stock/history results, including offline Android retry.
4. **Supplier accounting and corrections:** payments, partial payments, dues/due dates, statement, return/refund/credit and audited correction/void. Exit: purchase totals, stock and supplier balances reconcile. Until then clearly describe the product as purchase/stock recording, not full supplier accounting.
5. **Advanced workflows by demand:** purchase orders, partial receipts, separate receipt/bill workflow, alternate packaging units, serials/variants, multi-location stock and bill OCR. Reserve model extension points now; enable each feature only when fully supported by sale, return, reporting and sync paths.

Roll out API and compatible sync support first, then clients behind a feature flag. Preserve old-client behavior during migration and prevent unsupported edits from silently discarding new fields. Reconcile stock, purchase totals and payment balances before widening rollout. Rollback must preserve already-created purchase records.

## 8. Acceptance scenarios

- Create a product without stock; record opening stock separately; neither creates purchase dues.
- Buy existing stock from a new supplier, add another new product, and save one purchase.
- Save an anonymous purchase; require supplier when recording credit or partial payment.
- Receive the same product from two suppliers at different costs; historical records retain both.
- Import ambiguous names and multiple lots; preview resolves matches without silent merging.
- Double-click Save, retry after timeout, restart Android offline and sync: stock posts exactly once.
- Fail one purchase line: no partial stock/payment write; draft remains recoverable.
- Backdate around timezone boundaries; reports use the intended business date.
- Apply taxes, discounts, freight, fractional units and rounding consistently on both clients.
- Preserve automatic selling-price settings while updating purchase cost.
- Correct/void/return a purchase with subsequent sales or payments under the agreed accounting policy.
- Prevent unauthorized cost access and cross-shop supplier/product references.
- Migrate legacy records and operate old/new clients without duplicating stock or losing history.

Measure completion time, correction rate, abandonment, import match errors and duplicate incidents. Proposed usability targets to validate: existing-item restock within 20 seconds and a basic new product within 30 seconds for a trained user; no mandatory advanced fields for simple purchases.

## Code anchors

- Android: lib/screens/products_screen.dart; lib/screens/products/new_purchase_screen.dart; lib/models/product_purchase.dart; lib/models/supplier.dart; lib/db/database_schema.dart.
- Web: src/products/ProductForm.tsx; ImportDialog.tsx; AdjustStock.tsx; queries.ts; ProductDetailPanel.tsx; src/reports/Registers.tsx.
- API: app/routers/catalog.py; app/products.py; app/product_import.py; app/reports.py; app/sync.py and schema migrations.

These are initial change areas, not a complete implementation diff. No engineering estimate is committed until sync and costing policies are resolved.

## 9. End-to-end scope and completeness contract

This plan covers the product lifecycle across Android and web: setup → opening inventory → procurement → receipt → supplier bill → payment → sale consumption → customer/supplier returns → counts and corrections → reporting → archive. It also covers the platform dependencies needed to keep that lifecycle consistent. It is not a promise of every feature in every ERP, nor a redesign of unrelated payroll, lending or ecommerce systems.

Sections 9–14 expand the earlier delivery sequence. Core completion requires stages A–E below, including supplier accounting and returns. Stage C alone is an intermediate release and must not be called the completed upgrade. Advanced capabilities have explicit scope and dependencies rather than being forgotten.

### Coverage register

All rows require web and Android acceptance, unless an explicit platform distinction is recorded. Existing capability must be verified rather than assumed absent; the initial review established only the specific gaps in the comparison table.

| ID | Capability and completion requirement | Delivery |
| --- | --- | --- |
| CAT-01 | Quick add, full edit, searchable catalog, categories, units, barcode/SKU, optional images, stock-tracked and non-stock/service items | Core |
| CAT-02 | Active/archive/restore, safe deletion only when unreferenced, duplicate detection and reviewed merge with history preservation | Core |
| CAT-03 | Bulk edit with preview, import/export templates, row corrections and outcome summaries; preserve prices unless explicitly changed | Core |
| CAT-04 | Direct/automatic selling-price parity, overhead/margin rules, MRP warnings and confirmation of cost-driven price changes | Core |
| INV-01 | Opening quantity/value/date; missing-cost treatment; opening supplier balances separately recorded | Core |
| INV-02 | Stock ledger, physical counts and variance posting, reasoned adjustments, negative-stock policy | Core |
| INV-03 | Batch identity, expiry and optional manufacturing date; allocation through sale and return; expired-stock policy and alerts | Core for batch-enabled shops |
| INV-04 | Low-stock thresholds, reorder queue and supplier hints; notifications with preferences and deduplication | Core |
| PUR-01 | Optional supplier, editable business dates, new/existing items, atomic confirmation, draft recovery, bill reference and attachment | Core |
| PUR-02 | Line/bill discounts, free quantities, freight/other charges, inclusive/exclusive tax, round-off and reconciled totals | Core |
| PUR-03 | Purchase detail, supplier/date/item search, duplicate bill warnings, copy-as-draft, export/print and attachment access | Core |
| PAY-01 | Paid/unpaid/partial/not-recorded states, payment methods, due dates, allocation across bills and supplier statement | Core |
| PAY-02 | Supplier advances, overpayments/unallocated credit, refunds, opening balances, reversal and allocation history | Core |
| RET-01 | Partial/full supplier return, original quantity/cost/tax references, refund or credit, remaining-returnable limits | Core |
| RET-02 | Existing customer returns preserve original lot/unit/cost where known; damaged returns go to non-sellable stock | Core integration |
| REP-01 | Purchase register, supplier statement, outstanding aging, stock movements/valuation, low stock, expiry and return reports | Core |
| REP-02 | Reconcile purchase totals, discounts/taxes, inventory value and supplier balances; expose unknown cost/payment rather than false precision | Core |
| OPS-01 | Permissions, audit, concurrency, retry safety, offline queue, sync conflicts, backups and migration reconciliation | Core |
| ADV-01 | Buy cartons/sell pieces, weight/fractional quantities, conversion snapshots, free-unit costing and packaging barcodes | Advanced; promote before launch for shops requiring it |
| ADV-02 | Variant families with distinct SKU/stock, serial/IMEI tracking and optional warranty references | Advanced |
| ADV-03 | Purchase orders, approval, partial receipt, short/excess/damaged delivery and separate supplier billing | Advanced |
| ADV-04 | Warehouses/locations, transfers, in-transit stock and location-specific counts/reordering | Advanced |
| ADV-05 | Bundles/kits with defined component stock behavior; manufacturing/BOM is separate scope | Advanced |
| ADV-06 | OCR/photo bill extraction with editable confidence review and duplicate detection before posting | Advanced |

Advanced does not mean silently unsupported: onboarding and UI must disclose capability availability. Do not onboard a shop to batch/serial/unit-conversion workflows until its entire sale, return and reporting path works.

## 10. Additional UX and business rules

- **Navigation:** Products, Purchases and Suppliers are first-class destinations, with Reports linking back to source documents. Product detail includes stock history, purchase cost history where permitted, recent suppliers and Restock. Empty states explain the next action.
- **Supplier lifecycle:** name is sufficient for quick setup; optional contact/tax/address fields. Archive suppliers while preserving bills. Warn on likely duplicates; merging must retain links and audit history. One product can have many suppliers.
- **Payment clarity:** Not recorded is excluded from confirmed payable totals and shown in a separate unresolved amount/count. Once payment terms are recorded, outstanding is calculated from bills, returns/credits and allocations. Supplier advances do not increase stock. One payment can settle several bills and one bill can have several payments.
- **Receipt status:** core Save purchase means goods received. Future-dated receipt entries cannot affect today's stock; offer a planned/draft document instead. Supplier invoice date may differ from receipt date. Later purchase-order modules change stock only upon receipt, and creating the bill must not receive the same goods twice.
- **Quantities:** free goods increase received quantity and allocate total cost over all received units under the chosen policy. Fractional precision is unit-dependent. Never aggregate different rates or lots merely because the product name matches.
- **Tracking:** lot/serial requirements become mandatory only for tracked items. Batch-expiry entry alone is insufficient: sale allocation, customer returns, supplier returns and adjustments must reference the appropriate lot. Historical untracked quantities need an explicit migration state.
- **Drafts:** offer Save draft, resume and discard; show unsaved/local/queued/synced states. Draft deletion has no ledger effect. Copying a purchase creates fresh IDs and clears supplier bill/payment identifiers by default.
- **Corrections:** define permitted edits for draft and posted documents. Changing descriptive notes can be audited in place; quantity/cost/payment changes must reconcile dependent entries. Period locks and authorized reopen rules apply if accounting periods are introduced.
- **Accessibility:** touch targets, screen-reader labels, keyboard focus, error summaries, no color-only status, readable currency/quantity formats and localization-ready strings. Existing translated mobile text must not regress.
- **Attachments:** camera/file upload, preview, explicit pending/failed status, size/type limits and access scoped to the shop. Purchase saving and attachment retry must not duplicate the purchase. Support deliberate deletion with retention policy.
- **Printing/export:** purchase copy clearly identified as an internal purchase record; supplier bill reference retained. Support readable PDF/CSV and existing Android printer paths where applicable; barcode labels remain consistent with product identity.

## 11. Platform parity contract

| Area | Android | Web | Shared requirement |
| --- | --- | --- | --- |
| Purchase composer | Touch cards, camera scan, numeric entry | Editable table, keyboard/scanner input, responsive layout | Same fields, validation, totals and posting rules |
| Product/supplier creation | Inline sheet | Inline dialog/panel | Returning to purchase preserves every draft field |
| Offline work | Durable local drafts and queued supported transactions | Durable local draft recovery; confirmed posting requires connectivity initially | Clearly disclose limits; no false Saved/Synced status |
| Import | File picker with row review | File upload with row review | Same parsing/matching semantics and stable duplicate protection |
| Reports/payments/returns | Usable on phone | Usable on desktop and narrow browser | Equivalent business capabilities and source records |
| Conflicts | Visible retry/conflict resolution | Visible revision conflict resolution | Never silently replace a newer confirmed record |

Full offline web posting is an explicit later capability, not an implied promise of this upgrade. Both clients must permit reading the actual server status after an uncertain save. Offline permission revocation must be checked at sync and rejected records surfaced for resolution.

## 12. Technical work packages and dependency order

**A — Rules and contracts:** record decisions for base units/precision, money rounding, cost and backdating, tax snapshots, anonymous purchases, payment-unknown semantics, document states and negative inventory. Inventory the existing screens/endpoints against each coverage ID and mark retain/change/new. Build shared golden examples consumable by Dart and Python/TypeScript tests. Current Android product models use doubles while the API uses decimals; money parity requires explicit scaled-decimal or canonical-string calculations rather than UI formatting alone.

**B — Persistence and API:** migrations for document/line/payment/return records, supplier and product snapshots, movement references, attachment metadata, stable idempotency and revisions. Extend authorization with separate capabilities for purchase viewing/creation, cost visibility, confirmation, payment recording, returns, corrections and supplier management. Enforce on server and sync paths. Add reconciliation queries and migration dry runs before enabling writes.

**C — Both clients:** implement the shared catalog and purchase workflows, supplier directory, import review, drafts, purchase history and report links. Upgrade Android's date-first modal to an editable composer header and direct existing-item selection. Replace name-only restock decisions with explicit identity selection. Add web purchase routes and supplier query/mutation support. Regenerate API types. Deliver required batch/tax behaviors end to end for supported shops.

**D — Close the financial and stock lifecycle:** payments/allocations, opening supplier balances, advances/credits, supplier returns and refunds, corrections/reversals, customer-return integration, counts, aging and reconciliation reports. Add searchable audit events showing actor, device and original/replacement documents.

**E — Release validation:** run Android/API/web integration scenarios, old-client compatibility, offline sync/retry tests, permission tests, migration comparisons, realistic catalog/import performance and shop-owner usability sessions. Pilot with feature flags, inspect duplicate/conflict/reconciliation metrics, then widen rollout. Core complete means A–E, not just a new web form.

**F — Advanced modules:** implement coverage ADV-01 through ADV-06 by shop segment. Each module must include persistence, API, Android, web, import/export, sale/return integration, reports, migration and acceptance evidence. Keep a visible deferred register with rationale and promotion criteria.

## 13. Required end-to-end test journeys

1. Start a shop: import catalog, enter opening stock and supplier opening balances; reconcile without fabricating purchases.
2. Receive five items from a new supplier, including a new item and an existing one; record a partial payment, sync, then pay the remainder on the other device.
3. Receive the same item at different prices/lots, sell some, return a customer item, then return remaining units to the supplier; verify stock, costs and credits.
4. Receive promotional free quantities and freight, apply discount/tax, and compare every displayed/exported total across platforms.
5. Use an anonymous cash purchase and a purchase with payment Not recorded; neither creates invented supplier dues.
6. Record a supplier advance, allocate across two bills, then reverse a mistaken payment without altering stock.
7. Retry after a timeout or app termination; sync two devices editing the same draft/record; observe one posting or an explicit conflict.
8. Import a renamed/reformatted duplicate bill on another day and review the warning; intentionally receive identical genuine purchases with distinct transaction IDs.
9. Count stock while sales continue; detect movement since count start and reconcile the variance rather than overwriting current quantity.
10. Archive a product/supplier, inspect older documents and attempt a new transaction; references remain valid and availability is explained.
11. Use staff with restricted cost/payment permissions, including offline revocation; APIs, sync, exports and reports enforce the same restriction.
12. Upgrade a shop containing legacy purchases, unknown costs and unsynced Android transactions; compare pre/post stock and preserve unresolved history.

Add branch-specific scenarios for ADV modules before enabling them, including unit conversion across receipts/sales/returns, serial uniqueness and transfer receipt duplication.

## 14. Definition of done and remaining design decisions

Each coverage ID needs an implementation owner, API/schema changes, Android task, web task, migration impact, report impact, tests and acceptance evidence. A feature is Done only when all applicable cells pass; otherwise mark Partial, Deferred or Blocked with a reason. No currently unverified capability is labeled missing solely because it was not in the initial code search.

Before implementation, resolve through a short design review: supported first-release shop segments; exact historical costing/backdating policy; tax/charge treatment; negative-stock behavior; tracked-lot migration; old-client minimum-version policy; attachment retention; and permissions for financial corrections. Recommended default is single-location retail, moving-average cost aligned across clients, server confirmation for web and offline queue support for Android. These defaults still need validation against existing data and product behavior.

Release evidence: zero duplicate stock postings in retry tests; zero unexplained migration stock differences; matching totals for shared golden cases; reconciled supplier balances; successful recovery after interrupted save; equivalent core journeys on both platforms; and usability results against the time/error targets above. Measure performance with representative large catalogs and imports and set budgets before sign-off.

Additional primary competitor references supporting the expanded coverage:
- https://mybillbook.in/s/features/inventory/ — items, units, batches, serials, barcodes and stock reporting.
- https://knowledge.mybillbook.in/articles/8743420-how-to-record-daily-purchases-seamlessly-on-mybillbook — incoming stock, supplier bills and payment dues.
- https://www.zoho.com/us/inventory/help/settings/preferences.html — unit conversion and tracking preferences.
- https://www.zoho.com/us/inventory/help/items/composite-items.html — kits/composites and advanced tracking.
- https://vyaparapp.in/free/erp-software/inventory — godowns, expiry, purchase orders, alerts and transfers.

## Implementation checkpoint — 29 October 2026

Stage 1 implemented in storelyweb commit `babb61a`: supplier directory/search,
create/edit profiles, preferred supplier selection on products, inline creation
preserving product drafts, and error/permission handling. Validated with all 120
web tests (18 files), TypeScript, lint and production build. Existing unrelated
working changes were excluded from the commit. No API, stock, Android or database
migration behavior changed in this stage.

Next stage remains work package A/B: shared purchase contracts and persistence,
including effective dates, exact decimal costing, atomic posting, idempotency,
legacy compatibility and offline sync. The full upgrade remains in progress.

## Stage 2 checkpoint — 29 October 2026

API commit `79147fb` adds atomic/idempotent purchase receipt confirmation, list/detail,
immutable line and supplier snapshots, decimal costs, batch/expiry, financial-year
invoice duplicate protection and legacy movement sync compatibility. Migration 0014
adds document tables without backfilling or reposting existing stock. Legacy sync
cannot alter/forge posted receipt stock. Payment status remains explicitly unknown.

Validation: 262 unit tests; 75 receipt/product/sync/report integration tests; Ruff,
strict mypy for new modules and Bandit pass. Migration reapplication verified on
populated scratch data. Local development schema was migrated/aligned during testing;
remote environments were not deployed. See storelyapi/docs/PURCHASE_RECEIPTS.md for
endpoint examples, scope, costing/backdating limitations and migration dependencies.

Next: web purchase composer backed by these endpoints, recoverable shop-scoped drafts,
existing-product selection, inline supplier creation and purchase history. Android
native document sync/composer upgrade, payments, tax/charge totals, attachments,
returns and wider concurrency/costing work remain open. Stage 2 is a foundation and
does not satisfy the full end-to-end definition of done.

## Stage 3 checkpoint — 29 October 2026

Web commits `c3f9703` (native dialog lifecycle fix) and `0eed9d0` (purchase composer)
add Add purchase, product-detail Restock, date/optional supplier and inline creation,
existing-product selection, fractional quantities/costs, distinct lot rows,
batch/expiry, invoice reference/notes, immutable receipt display and purchase history.

Account/shop-scoped local drafts recover after close/reload. The exact request is
persisted before posting and stays frozen after uncertain responses, including access
loss on a later retry. Cross-tab changes, blocked storage, offline confirmation and
double submissions have explicit handling. Decimal totals/display are exact.

Validation: all 139 web tests, TypeScript, lint and production build pass. Real Chromium
fixture tests pass at desktop/narrow widths and verify native nested supplier dialogs,
item editing, reload recovery and identical retry payloads. Screenshots inspected.
No remote deployment or migration in this stage. Browser checks use explicit API
fixtures; stage-2 PostgreSQL tests remain the transaction validation evidence.

Remaining web-composer work includes atomic new-product staging inside purchases,
purchase import staging, payments, taxes/charges, attachments and returns. Android
native document sync and composer parity remain open. These capabilities must be
completed before declaring the whole core upgrade finished. See
storelyweb/docs/purchase-composer.md for implemented behavior and scope.

## Stage 4 checkpoint — 29 October 2026

API `24ca2d0` and web `8ef790f` add atomic new-product staging and reviewed CSV/XLSX
purchase imports. New products, unit/category lookups and stock commit together;
preview/staging creates no catalog or stock records. Multiple lots share a staged
identity without collapsing quantities/costs. New-product metadata recovers with the
local draft and remains editable before confirmation.

Import review retains original row numbers, requires explicit name/identifier choices,
blocks incompatible base units and invalid rows unless corrected/excluded, and preserves
existing selling prices/settings. Fingerprints survive renamed files, normalized numeric
spellings and dates; each duplicate file needs its own approval. Confirmation rechecks
fingerprints under the receipt lock. Saved stock retains source-file key and row number.
Stage-2/3 request hashes and stage-3 drafts/retries remain backward compatible.

Validation: 264 API unit tests and 80 purchase/product/sync/report integration tests;
143 web tests; Ruff, strict mypy, Bandit, TypeScript, lint and production build pass.
Real Chromium staging fixture checks pass for native dialogs, review/exclusion, narrow
layout, reload recovery and identical retries; screenshots reviewed. Migration 0015
was applied to the local development database (verified version/table). No remote
deployment. Unrelated repository changes were excluded from commits.

Next: Android native purchase-document persistence/sync and composer parity, preserving
atomic offline commits and safe upgrade/legacy behavior. Payments, invoice tax/charges,
attachments, returns/reconciliation and advanced capabilities remain open before full
end-to-end completion.
