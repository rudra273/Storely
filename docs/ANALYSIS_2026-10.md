# Storely: Release 2.0 Analysis (Oct 2026)

> Scope: a read-only audit of `main` @ `c57c40d` (v1.0.4+5), compared against Indian billing apps and GST rules.
> Method:
> - 4 parallel code audits (Opus): sync, billing/money, products/DB/reports, UI/UX/robustness.
> - 2 web research passes (Sonnet): competitors, GST/invoice rules and Flutter tooling.
> - A hands-on run on an Android 15 emulator (Pixel 6 profile).
>
> I verified every **Critical** item below by reading the code myself. `file:line` references are on `main`.
> No code was changed. Per CLAUDE.md, nothing gets built until you confirm.

**Baseline health:**
- `flutter test`: 53/53 pass.
- `flutter analyze`: 1 info-level issue (`app_screen_header.dart:78`).
- The bugs below are logic and data-integrity issues that neither lints nor the current tests catch.
- No tests cover GST math, migrations or sync.

---

## 0. TL;DR

1. **There is a live crash for upgraded users.** Devices whose DB was created on v15 (app 1.0.0/1.0.1) cannot save bills or purchases. The fix already exists on `origin/dev` (`8ec2061`) but is **not merged or released**. Ship it first.
2. **Cloud sync is not safe for multi-device shops.** The watermark design misses rows, and bill numbers collide across devices and merge two different sales. Every sale re-stamps products, which reverts other devices' price edits. Onboarding a second device overwrites the shop profile. Pulls aren't paginated (1000-row cap).
3. **The GST math is wrong on invoices.** Rounding is per unit, then multiplied by quantity, so CGST+SGST ≠ GST and taxable + tax ≠ total. The default bill number is 17 chars, over GST's 16-char limit. Unregistered shops print "TAX INVOICE".
4. **Billing UX is ~13 taps for a 3-item bill.** There is a duplicate-bill path (back on the success dialog), the scanner re-adds an item held in frame every ~1 s, and the qty field loses focus on every keystroke.
5. **Competitors' #1 user complaint is data loss, sync and wrong totals.** If we fix those and make billing fast, reliability becomes our selling point.

---

## 1. Critical & high bugs (prioritised)

Legend: 🔴 Critical (data loss, crash, or wrong money) · 🟠 High · 🟡 Medium. ✅ = I personally confirmed it in the code.

### 1A. Database / upgrade

| # | Sev | Bug | Where | Failure scenario |
|---|---|---|---|---|
| D1 | 🔴✅ | `stock_movements` is missing 6 columns on DBs created at v15 | `database_schema.dart:582-609`; `_ensureV16Columns` at `:685` never adds them | A user from 1.0.0/1.0.1 upgrades, and every bill or purchase throws "no column named source_document_type". **Fix is on `origin/dev` 8ec2061, unmerged.** It also needs a `supabase/migrations/` file (CLAUDE.md rule) and a v15→v21 migration test. |
| D2 | 🔴 | The barcode/code unique indexes are never rebuilt on upgraded DBs | same, `IF NOT EXISTS` keeps the old non-unique index | Duplicate barcodes are allowed on old installs. This is also covered by 8ec2061, but its `_clearDuplicateProductValues` silently NULLs duplicates; the user should be told. |

### 1B. Cloud sync & security

| # | Sev | Bug | Where | Failure scenario |
|---|---|---|---|---|
| S1 | 🔴✅ | The pull watermark uses the **device clock** plus a client-written `updated_at` (a text column with no server trigger) | `cloud_service.dart:742, 822-841, 1013`; schema `updated_at text` | Device B bills offline at 09:00 and pushes at 11:00. Device A synced at 10:00, so it **never** sees B's bill. The same happens with a partial push (bill without items), and on clock skew. |
| S2 | 🔴✅ | Bill numbers collide across devices, and the merge-by-`bill_number` corrupts or drops bills | `database_bills.dart:577-641`, `database_sync.dart:356-488`, `database_schema.dart:486, 671` | Two phones both issue `INV-20261023-0001`. On pull, one bill overwrites the other and re-points its items and payments, or the remote bill is silently dropped. |
| S3 | 🔴✅ | Every sale re-stamps `products.updated_at`, and pulling any stock movement re-stamps **all** products | `database_products.dart:1038-1068`, `database_sync.dart:132, 300` | The admin changes a price at 09:58 and staff sells at 10:00, so staff's stale price "wins" and staff bills at the old price and GST forever. Two-admin edits get reverted. |
| S4 | 🔴 | Joining an existing shop overwrites the real shop profile with "My Shop" defaults | `database_helper.dart:182-231`, `cloud_service.dart:755, 894` | A second device or invited admin joins, and the shop name, GSTIN and address in the cloud are wiped. Preset units also lose mapping (`unit_id = null`). |
| S5 | 🔴✅ | Pulls aren't paginated (Supabase caps responses at 1000 rows by default) | `cloud_service.dart:1002-1020` | A new device joins a shop with >1000 bill items and gets only the first 1000. The watermark then advances, so the rest are never fetched and stock is wrong. |
| S6 | 🟠 | RLS lets an **admin take over the shop** (promote self to owner, delete owner, delete shop) | `storely_cloud_schema.sql:637, 662-666` | The code comment claims RLS blocks it, but it doesn't; only the UI does. |
| S7 | 🟠 | Staff can rewrite or **hard-delete** bills, payments and stock via the REST API | schema `:742-791` (`for all`) | Admin-only cancel is client-side only. |
| S8 | 🟠 | Opening Customers re-stamps **every** customer (`UPDATE` without `WHERE`) | `database_schema.dart:895-900` | Overwrites other devices' customer edits and causes sync churn. |
| S9 | 🟠 | Cancelled bills come back to life via whole-row last-write-wins; a double cancel restores stock twice | `database_bills.dart:269-343, 644-687` | A cancels while B (offline) records a payment, so the bill reappears with deleted items. |
| S10 | 🟠 | Sync can wedge permanently: one bad row fails the whole table batch, and the FK to parents is missing in the cloud | `cloud_service.dart:785-819` | One duplicate barcode leads to every sync failing forever, with no conflict UI. |
| S11 | 🟠 | A role-check error is treated as "not admin", so admin pushes are skipped **but the watermark still advances** | `cloud_service.dart:921-931, 838` | Catalog edits are never uploaded. |
| S12 | 🟡 | `storely_cloud_schema.sql` is not re-runnable (some `create policy` lack `drop policy if exists`) | schema `:693-766` | Violates the CLAUDE.md idempotency rule. |

**Sync verdict:** S1, S2 and S3 are design-level. Spot patches won't hold; this needs a small **sync v2**:
- a server-assigned change cursor (`server_seq` via trigger);
- no timestamp bumps for derived columns (`quantity_cache`, customer aggregates);
- per-device bill-number prefixes, or server allocation;
- sticky tombstones;
- paginated pulls;
- per-row quarantine with a conflict UI;
- tightened RLS.

All of this ships as additive files in `supabase/migrations/`.

### 1C. Billing & money

| # | Sev | Bug | Where | Failure scenario |
|---|---|---|---|---|
| B1 | 🔴✅ | GST is rounded per **unit**, then multiplied by qty | `scan_screen.dart:394-399` → `:317-323` | ₹100 incl. 18% × 100 qty: CGST+SGST = ₹1526.00 (true ₹1525.42); taxable + tax = 10001 vs a total of 10000. The PDF shows inconsistent totals and GSTR figures are overstated. |
| B2 | 🔴✅ | Bill creation can get **permanently stuck** | `database_bills.dart:611-614` (seq resets to 1) + unique index `database_schema.dart:486` + daily reset default `:671` | The owner changes the template to `INV-{SEQ}` (leaving daily reset), and the next day's `INV-0001` collides. The transaction rolls back including the seq bump, so **no bill can ever be saved**. Also `{YY}` + FY reset. |
| B3 | 🟠✅ | Duplicate bill + double stock deduction | `scan_screen.dart:464-523` | Android back on the "Bill Created" dialog leaves the cart full (never cleared), and tapping Bill again saves a second bill. |
| B4 | 🟠 | "Mark Unpaid" soft-deletes **all** payment history in 1 tap, with no confirm and no admin gate | `bill_card.dart:33-38`, `database_bills.dart:372-378` | Staff erases weeks of partial payments. This is a fraud/mistake risk. |
| B5 | 🟠✅ | The scanner re-adds the same item every ~1 s while it stays in frame | `scan_screen.dart:262-270` (`_lastScanned = null`) | Customers get overcharged. |
| B6 | 🟠 | The default bill number is 17 chars (GST max is 16) | `database_schema.dart:671` | GSTR-1 / e-invoice uploads would reject it. |
| B7 | 🟠 | The purchase import **wipes** HSN, GST%, barcode and category on existing products | `new_purchase_screen.dart:111-127`, `database_products.dart:182, 848-866` | After a restock via CSV, later bills carry the wrong GST and no HSN. |
| B8 | 🟡 | Decimal stock is compared without epsilon | `database_bills.dart:725`, `scan_screen.dart:221` | Buy 0.3 kg and sell 0.1 ×2, and the last 0.1 kg is refused. |
| B9 | 🟡 | Mixed UTC/local timestamps (`_nowIso` is UTC; insertBill/recordPayment use local) | `database_helper.dart:101`, `database_bills.dart:67, 387, 431` | Payments made 00:00–05:29 IST land on the previous day in "Today collected" and in KPIs. |
| B10 | 🟡 | Record Payment / Cancel / Status have no try/catch | `bills_screen.dart:231`, `database_bills.dart:419` | Overpayment or "1,000" input fails silently. |
| B11 | 🟡 | Qty field loses focus on every keystroke (key includes qty) | `scan_screen.dart:981` | Typing "25" is impossible. |
| B12 | 🟡 | Profit KPIs ignore bill discount; commission KPI always 0 | `scan_screen.dart:361-405`, `database_kpi.dart`, `database_products.dart:525` | A 10% discount on 10% margin still shows full profit. |
| B13 | 🟡 | "Revenue" means 3 things: Home counts all bills, KPI counts only `is_paid=1`, profit counts all | `database_kpi.dart:21`, `database_bills.dart:522` | Credit sales vanish from revenue. **GST collected is understated**: liability arises on the invoice, not on payment. |
| B14 | 🟡 | The PDF ignores `showPaymentDetails`; line amounts and subtotal disagree when discount + GST are both present | `bill_settings.dart:79`, `bill_pdf_generator.dart:449` | Udhaar invoices don't show Balance Due. |
| B15 | 🟡 | Non-GST shops print "TAX INVOICE" (should be "Bill of Supply" or a plain bill) | `bill_settings.dart:2` | Compliance issue. |
| B16 | 🟡 | CSV `shouldParseNumbers` turns barcode `001234` into `1234`; `"Rs.250"` parses as `0.25` | `csv_importer.dart:159, 538` | Scanned barcodes no longer match. |
| B17 | 🟡 | Re-importing the same purchase file doubles stock (duplicate check only in unused code paths) | `new_purchase_screen.dart:94-137` | |

### 1D. App robustness & security

| # | Sev | Bug | Where |
|---|---|---|---|
| R1 | 🟠✅ | **App lock bypass.** The lock replaces only the home route; pushed screens (Customers, KPI/profit, Scan, settings) stay usable after resume. Locking also unmounts `AppShell`, which breaks "Add product" after unlock. | `app_lock_gate.dart:88`, `main.dart:116` |
| R2 | 🟠 | Data is visible in the Android Recents preview (no `FLAG_SECURE`), and turning App Lock off needs no re-auth. | `MainActivity.kt`, `app_lock_gate.dart:47` |
| R3 | 🟠 | Home loads **all** bills, items, products and customers on every tab switch; the Bills list is a non-lazy `Column`. This causes jank or OOM on low-end phones (our users). | `home_screen.dart:104`, `bills_screen.dart:535` |
| R4 | 🟡 | No startup error path: a migration exception leads to a stuck splash or blank screen. | `main.dart:20-33, 71` |
| R5 | 🟡 | Camera denied or missing shows a blank black frame with no "use search instead" (seen on the emulator). | `scan_screen.dart` (no `errorBuilder`) |
| R6 | 🟡 | Dark-mode leaks: the profit sheet and empty states use static light colours, so text is unreadable. | `bill_profit_sheet.dart:68` |
| R7 | 🟡 | A double-tap on Save then `pop` can pop the AppShell, leaving a black screen. | `home_screen.dart:1152` |
| R8 | 🟢 | `lib/db/inject_hook.dart` is a dev script inside `lib/`; move it out. Version is hard-coded in 2 screens. | |

---

## 2. Competitor comparison (India, 2026)

| | **Vyapar** | **myBillBook** | **Swipe** | **Khatabook / OkCredit** | **Zoho Invoice** | **Storely today** |
|---|---|---|---|---|---|---|
| Price | Android free; ₹3.4–4k/yr desktop/sync | ₹3.5–4k/yr; Enterprise for e-inv/multi-user | Free unlimited invoices; ~₹250/mo | Free core, premium extras | Free 2 users/500 inv | Free |
| Offline | ✅ strong | Desktop only | ? | ✅ | ❌ | ✅ (local-first) |
| GST tax invoice / Bill of supply | ✅ | ✅ | ✅ | Light | ✅ | Partial (wrong math, no BoS) |
| Thermal 58/80mm | ✅ | ✅ | ✅ | ? | ? | ❌ |
| UPI QR on invoice | ✅ | ✅ | ✅ | ✅ | – | ❌ |
| WhatsApp share of PDF | ✅ | ✅ | ✅ | ✅ | ✅ | Text only |
| Udhaar ledger + reminders | ✅ | ✅ | ✅ | ✅✅ (core) | – | Per-bill only, no reminders |
| Staff roles / multi-device | per-device licence | Enterprise | ✅ | premium | ✅ | ✅ (but sync unsafe) |
| GSTR-1 export | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| Languages | 9+ | ~5 | ? | 11 | ✅ | English only |
| Batch/expiry, godowns | ✅ | Platinum | ✅ | ❌ | – | ❌ |

**What users complain about most in competitors.** Sources: Capterra, Software Advice, App Store, Trustpilot.
1. Poor support after purchase (Vyapar, myBillBook, Marg).
2. **Data loss, stuck sync, failed backup restore.** A Vyapar user lost 5 years of data; myBillBook gets stuck on "syncing"; Khatabook has had backup problems.
3. Paywalls and lock-in: data withheld after non-renewal; per-device licences; key features on top tiers.
4. **Wrong calculations or GST bugs** ("calculation errors cost me thousands", negative stock).
5. WhatsApp sends blank PDFs; SMS shows the vendor brand, not the shop.
6. Slowness and hangs after updates.

**Our opportunity is to be the billing app that never loses data and never gets the math wrong, while staying faster and simpler than Vyapar.** That means fixing §1 first, then building trust features:
- a visible sync status;
- 1-tap backup and restore;
- an audit trail;
- free export always.

**Table stakes we're missing:**
- GST-correct invoice + Bill of Supply;
- thermal printing;
- UPI QR;
- WhatsApp PDF share;
- customer ledger + reminders;
- GSTR-1 export;
- credit notes / returns;
- Hindi + regional languages;
- day book / P&L.

---

## 3. GST & invoice rules we must follow

Notes on certainty:
- [V] = verified in a source; [K] = from background knowledge.
- Items marked [K] need an accountant check before they become hard rules.

- **Document type by seller status:**
  - Regular → **Tax Invoice** (Rule 46).
  - Composition → **Bill of Supply** with the legend "composition taxable person, not eligible to collect tax" [K].
  - Unregistered → plain bill with **no GST shown**.
  - Needs a "GST status" setting that drives the title, the tax columns and the legend.
- **Mandatory fields on a Tax Invoice:** seller name, address and GSTIN; serial no. (**≤16 chars, `A-Z 0-9 - /`, unique per FY**); date; buyer GSTIN (B2B); HSN; qty + UQC; taxable value; rate + CGST/SGST/IGST; place of supply (state name + code); reverse-charge flag; signature.
- **B2C ≥ ₹50,000:** buyer name, address and state are mandatory [V].
- **HSN digits:** 4 digits if turnover ≤ ₹5 Cr (B2B only); 6 digits above that [V, Notif. 78/2020].
- **⚠️ GST rate reform, 22 Sep 2025:** the 12% and 28% slabs were removed; slabs are now 5/18/40 [V]. Rates must be a user-editable list, and old bills keep their snapshot rate (we already snapshot ✅).
- **Rounding:**
  - compute per line at full precision;
  - round each line to 2 dp;
  - derive SGST = GST − CGST;
  - round the grand total to the nearest rupee and show a **Round-off** line.
- **Numbering:** reset per **financial year (Apr–Mar)** and per series (INV / CN / BOS). Never reuse a cancelled number; keep it as "Cancelled".
- **Credit notes (returns):**
  - must reference the original invoice;
  - use their own series;
  - go in GSTR-1 table 9B.
- **E-invoice (IRN):** mandatory only above ₹5 Cr AATO [V]. Out of scope for us; show a warning if the user enters turnover > ₹5 Cr.
- **GSTR-1 export needs** B2B, B2CL, B2CS, CDNR, **HSN summary split B2B/B2C (since Apr–May 2025)** and **Table 13 docs issued (now mandatory)** [V].

---

## 4. Feature & enhancement plan

### 4.1 Billing & invoice ("easy billing")

- **Search-first billing screen**:
  - autofocused search plus a **Recent/Frequent items grid**, with the scanner as a toggle;
  - clear the query after each add;
  - 48dp qty **stepper**, where tapping the number opens a numpad.
- **Defaults:** Paid-full · Cash. Collapse B2B fields behind "Add GST details".
- **Success screen:** **Share PDF · WhatsApp · Print · New bill** (today only "Done").
- **Hold/park bill** (drafts), discard confirm on back, undo for Clear, draft survives app kill.
- **Invoice engine v2:**
  - templates: A4, A5, **Thermal 58mm / 80mm**;
  - a template picker with a live preview;
  - shop logo, signature/stamp image, T&C, bank details;
  - **UPI QR for the balance due** (`upi://pay?pa=…&pn=…&am=…&cu=INR&tn=…&tr=<billno>`);
  - **amount in words** (lakh/crore);
  - HSN/rate tax summary, round-off line, place of supply with state name;
  - Paid / Balance Due block;
  - correct title per GST status.
- **Thermal printing:**
  - `print_bluetooth_thermal` (maintained, Android 12+ permissions fixed, Sep 2026) + `esc_pos_utils_plus` [V];
  - a **raster/image mode** for Hindi/Indic text (printer code pages are Latin-only);
  - saved printer and a test-print button.
- **Fonts:** bundle Noto Sans (₹) + Noto Sans Devanagari as PDF `fontFallback` (today: Latin only).
- **Money formatting:** a single `fmtMoney` using `NumberFormat.currency(locale: 'en_IN')`, giving ₹12,34,567.00 (today "Rs. 1234567.00").
- **Credit note / sales return** flow, replacing cancel + duplicate.
- **Customer-level udhaar:**
  - record one payment allocated across bills (oldest first);
  - a WhatsApp reminder with the shop's name, the amount due and the UPI link;
  - a customer statement PDF.

### 4.2 Product management ("easy products")

- **Quick Add** (name · price · qty · optional barcode) as the default. Keep the full purchase/supplier flow as "Add purchase". Today a purchase step is forced even for one product.
- Make the whole product card long-pressable. Use swipe actions, or move delete into an overflow menu with an **undo snackbar**. Make tap targets 48dp.
- **Stock adjustments with reasons:** damage, theft, return, count correction.
- **Per-product reorder level.** A "don't track stock" option for services and loose items; stock 0 currently blocks billing.
- **MRP** separate from selling price. **Batch/expiry** as an optional module for medical and grocery shops.
- **Weighted-average cost** instead of "last purchase price overwrites". This fixes inventory valuation and profit.
- **Import v2:**
  - column aliases ("Product Name"), plus HSN and GST% columns;
  - a preview with per-row errors;
  - merge without wiping fields;
  - duplicate-file detection;
  - **export products to CSV/Excel**.
- **Labels:** quantity per product, thermal label sizes, a Noto font, and a short code instead of the 36-char UUID in the barcode.

### 4.3 Reports dashboard ("easy reports")

- **One-scroll home dashboard:**
  - hero: **Today's sales vs yesterday** + **Today's profit** + a "New Bill" CTA;
  - KPI tiles: Collected (Cash/UPI/Card split), **Customers owe you** (tap through to the list), **Running low**, Top items.
- **A period chip row for the whole screen:** **Today** / Yesterday / 7d / Month / Custom. Today the KPI screen has no "Today" and defaults to All Time.
- **One revenue definition:** "Booked" (invoiced) and "Collected" (payments), labelled identically everywhere.
- **New reports:**
  - **Day book** (bills, payments and expenses, with closing cash);
  - **P&L**;
  - **Receivables ageing** (0-7 / 8-30 / 30+);
  - **Stock valuation**;
  - Purchase register;
  - **GSTR-1 workbook export** (b2b, b2cl, b2cs, cdnr, hsn-b2b, hsn-b2c, docs) + monthly tax summary.
- **Performance:**
  - SQL aggregates on indexed `(shop_id, created_at)`; no loading every bill into Dart;
  - paged, lazy lists;
  - skeleton loaders.

### 4.4 Professional UI upgrade (within `lib/theme/`)

From the emulator run (screenshots in `docs/screenshots/`) and the code audit:
- **Shared state widgets:**
  - add `AppEmptyState`, `AppSkeleton` and `AppErrorState` to `lib/theme/widgets`;
  - today there are 6+ ad-hoc empty states, spinners everywhere, and raw `Error: $e` text.
- **One header system.** Today there are three: `AppScreenHeaderDelegate`, the theme `AppBar` (#161616, effectively black, not navy), and `navyAppBar()`. Use one search pattern too.
- **Remove hard-coded sizes and colours** in `kpi_widgets`, `product_editor_widgets`, `bill_settings_screen` and `scan_screen`. Use `…Of(context)` colours so dark mode works.
- **Welcome screen:** the keyboard covers the Continue button (seen on the emulator; `02_start_fresh.png`). Add a **language picker** and an optional **sample data** shop for first-run.
- **Store tab:** group into Shop / Billing / Catalog / Security / Account. Remove entries duplicated on Home (Customers, Analytics, low-stock).
- **Home:**
  - make unpaid rows tappable (open bill / record payment / remind);
  - merge Notifications into the Unpaid section (there are 3 duplicate unpaid lists today);
  - search results should open the specific item.
- **Localisation:** Hindi first, using `flutter_localizations` + ARB files (none today). Later Marathi, Tamil, Telugu, Bengali, Odia.
- **Bottom nav unchanged** (per CLAUDE.md).

### 4.5 Trust features (our differentiator)

- **Visible sync status** per bill and app-wide: Synced / Pending / Conflict, with a conflict-resolution screen.
- **1-tap backup to Google Drive or a file, and restore on a new phone.** This addresses competitors' #1 complaint.
- **Audit trail** for edited, cancelled and payment-reversed bills.
- **Export everything, always** (no lock-in).
- **In-app "Report a problem"** that attaches logs.

### 4.6 Current tap counts → target

| Task | Today | Target |
|---|---|---|
| Add a product | 4–5 taps + forced purchase step | 2 taps (Quick Add) |
| Bill 3 items + share on WhatsApp | ~13 taps + 3 searches | ~6 taps |
| See today's profit | **Not possible** (no Today period) | 0 taps (Home hero) |
| Record a customer's payment | 5 taps **per bill**, from the Bills tab only | 3 taps from the Home unpaid row or the customer page |

---

## 5. Proposed roadmap

### Phase 0: Hotfix 1.0.5 (this week, small, low risk)
1. Merge `origin/dev` 8ec2061 (D1/D2). Add a migration test (v15 fixture → current) and a `supabase/migrations/` note. Surface any NULLed duplicate barcodes to the user.
2. B3: clear the cart after save, plus `PopScope` on the success dialog.
3. B5: fix the scanner re-add. B11: fix the qty-field focus.
4. B2: skip forward on a bill-number collision, and validate the template against the reset period.
5. B4: Mark Unpaid → confirm + admin-only.
6. B10: try/catch + snackbars on payment, cancel and status writes.
7. B8: epsilon on stock comparison.

### Phase 1: Money & GST correctness (2.0 core)
- B1 per-line GST math + round-off.
- B6 + an FY numbering token (`{FY}`, ≤16 chars).
- B13 unified revenue; B12 discount-aware profit.
- B15 Bill of Supply.
- B9 timestamp normalisation (one-shot local migration).
- B7 / B16 / B17 import fixes.
- Add **unit tests for GST math and numbering**.

### Phase 2: Sync v2 + security (2.0 core, needs migrations)
- S1 server change cursor.
- S3 / S8 no re-stamps.
- S2 per-device numbering + never merge by bill number.
- S4 safe onboarding.
- S5 pagination.
- S9 sticky tombstones + deterministic void UUIDs.
- S10 / S11 chunked push + quarantine + conflict UI.
- S6 / S7 RLS hardening.
- S12 idempotent schema.
- R1 / R2 app lock overlay + `FLAG_SECURE`.

### Phase 3: Billing & invoice UX
Includes the A4/A5/thermal PDF invoice engine (§4.1):
- search-first billing;
- success-screen share;
- park bill;
- invoice templates;
- UPI QR;
- thermal printing;
- Indic fonts;
- `en_IN` money format;
- WhatsApp PDF;
- credit notes;
- customer ledger + reminders.

### Phase 4: Products & reports
Products and reports as listed in §4.2 and §4.3:
- Quick Add;
- adjustments with reasons;
- reorder level;
- weighted-average cost;
- import v2 + export;
- dashboard rework with Today;
- day book;
- P&L;
- receivables ageing;
- stock valuation;
- GSTR-1 export;
- SQL aggregates + lazy lists (R3).

### Phase 5: Polish & trust
- Shared state widgets, one header system, dark-mode fixes.
- Hindi localisation.
- Onboarding sample data + language picker.
- Backup/restore.
- Audit trail.
- Sync status UI.
- Startup error screen (R4).

Each phase follows the CLAUDE.md rules: verify with you first; keep `flutter analyze` clean; mounted checks; additive migrations in `supabase/migrations/` + `_ensure…Columns` locally; no change to the bottom nav.

---

## 6. Open questions for you

1. **Hotfix first?** Should we release 1.0.5 with Phase 0 now (protects current users), then do 2.0?
2. **Sync usage:** how many live shops use cloud sync with **2+ devices**? This decides whether Sync v2 goes before or after the UX work.
3. **Target segment:** kirana/retail counter (thermal + speed) vs small wholesalers (A4, B2B, e-way bill)? This shapes the invoice defaults.
4. **Monetisation:** stay free, or a paid tier for sync, multi-member and GST reports? Competitors charge ₹250–350/month.
5. **Languages:** which ones after Hindi?
6. **Printers:** do your customers already own Bluetooth thermal printers (58mm or 80mm)?

---

## Appendix: environment notes

- Android emulator set up: AVD `storely_pixel` (Pixel 6, Android 15 / API 35, arm64). To launch:
  `~/Library/Android/sdk/emulator/emulator -avd storely_pixel` then `flutter run`.
  Needs `JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`.
- The emulator has no camera, so the scanner flow must be tested on a real device. Use search mode on the emulator.
- Working-tree side effects from the tooling (not code changes):
  - `pubspec.lock` (meta / test_api bumps from `pub get`);
  - `android/gradle.properties` (Flutter migrator lines added by `flutter run`).
  - Review, then keep or `git checkout` them.
