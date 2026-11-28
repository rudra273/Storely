# Storely Implementation Plan (Simplified)

**Last updated:** 28 November 2026
**Repositories (use local checkouts):**
- Mobile (Flutter/Android): `/Users/rudra/projects/Storely` (`package-com-storely`)
- API (FastAPI/Postgres): `/Users/rudra/projects/storelyapi` (`dev`)
- Web (React/TS): `/Users/rudra/projects/storelyweb` (`dev`)
- Functional reference (read-only): `/Users/rudra/projects/vyapar-rea/CLONE_SPEC.md`

---

## Ground Rules (Fast Development Mode)

1. **No live production data yet.** Evolve API/SQLite schemas cleanly — **do not** build heavy legacy-data migrations, mixed-version compatibility shims, or multi-step deprecation scaffolding until after launch.
2. **Preserve UI identity & offline Android.** Keep the existing theme/colors/navigation shell and Android local-only operation. Hindi web localization (`D14`) remains deferred.
3. **Cross-platform parity.** Keep business rules, math (`Decimal` / `ExactDecimal` / `BigInt` paise), and user-facing workflows aligned across API, Web, and Android.
4. **Right-sized verification.** For each phase: run repo lint + unit/integration tests, verify on Docker/localhost (and Android build/tests), update `docs/refactor/feature-tracker.md`, and commit cleanly. Skip multi-document ceremony.
5. **Human gates.** Leave final UX approval and production deployment to the owner. Never run `make reset` or `docker compose down -v`.

---

## Locked Product & UX Decisions

- **Items & Purchases stay separate** in data and navigation (with quick shortcuts to add/restock).
- **Terminology:** Use **"Items"** (not "Products") in UI labels; use **"Parties"** (unified Customer + Supplier model, with Customer/Supplier tabs/filters) starting in M1.2.
- **Create / Edit Item:** Always **full screen** on mobile and web (never a cramped bottom sheet).
- **Item Type:** Support **Product** (stock-tracked, HSN) and **Service** (non-stock, SAC).
- **Item Code / Barcode:** Always offer 2 explicit actions: **Generate** (unique code) or **Scan**.
- **GST & Cess:**
  - **Category default GST:** Categories can store a default tax setting that auto-fills when creating a new item (overridable per item).
  - **Per-item GST options:** `None`, `Tax Exempt`, `GST 0%`, `5%`, `12%`, `18%`, `28%` + optional **Cess** (e.g., `+12%` or custom %).
  - **Bulk Edit GST:** Allow bulk-updating GST/Cess rates across selected items (or applying a category's default GST).
- **Bill creation flow:** Show a compact, optional **Customer / Party selector bar at the top** (defaults to *Walk-in / Cash*), with immediate fast **Items** scanning/entry right below.

---

## Current Baseline — Base (v1) ✅ Done

Verified commits: `storelyapi` `293bf0b` (Alembic `0029`) · `storelyweb` `441c506` · `Storely` `b2c3c1b` (SQLite `v30`).

- **Core Billing (`E00–E03`):** Exact decimal math, line/doc discounts (`%`/`₹`), inclusive/exclusive GST, round-off modes, backdating, invoice series, metadata edit + audit log, stock ledger, credit notes/returns, cancellations, held carts/durable drafts, cross-device draft handoff, opt-in atomic Android posting.
- **Purchases & Suppliers (`E04.1`):** Purchase receipts, supplier payments (confirmed vs pending), purchase returns / debit notes (`DN/{FY}/{seq}`), reversals.
- **Print / PDF / Share (`E12.1–E12.2`):** A4/A5/80mm/58mm PDF, WhatsApp/PNG image share, Bluetooth ESC/POS + raster thermal printing, all 39 invoice visibility flags.
- **Pilot Build (`E17 lite`):** PG 18.6 verified, Android local backup/restore (`O12`), clean release APK built (`STORELY_NATIVE_SALE_POSTING` default `false`).

---

## Milestone 1 (M1) — Core Daily Business & Accounting

| Phase | Scope | Key Deliverables |
|---|---|---|
| **M1.0 (Next)** | **Items, GST/Cess, Category Defaults & Billing UX** | Rename UI "Products" → "Items"; full-screen Create/Edit Item (replace bottom sheet); Item type (`Product` vs `Service`, `I02`); Item code `Generate` + `Scan`; Category default GST/Cess auto-apply; per-item GST (`None` / `Exempt` / `0%..28%` + `Cess`); Bulk Edit GST rates; optional top Customer/Party bar on Create Bill (defaults to Walk-in). |
| **M1.1** | **Typed Purchases & Expenses (`E04.2`)** | Line-level purchase GST/HSN/ITC (`T02`), taxable additional charges with SAC (`F16`), itemized expenses (`T05`), upgraded Purchase Register (`R06`). |
| **M1.2** | **Unified Parties & Receivables (`E05`)** | Unified Party master (`I19`, `I21`) keeping customer/supplier IDs, billing & multiple shipping addresses (`F04`, `F05`), credit limits (`I22`), payment terms/due dates (`F07`), receivables/payables aging (`R03`, `R04`), split tender (`F18`), advances/unallocated credits (`F20`), customer payment-in parity (`T03`), line notes/service period (`F23`). |
| **M1.3** | **Accounting, Cash & Bank (`E06`)** | Cashbook & bank accounts/transfers (`R14`, `R15`), other income (`T06`), party opening balances (`I20`), party-to-party transfers (`T17`), settlement write-offs (`F19`), Day Book (`R01`), Profit & Loss (`R02`), Balance Sheet & Journals (`R13`). |
| **M1.4** | **Quotes, Orders & Delivery Challans (`E07`)** | Quotations (`T10`), Proforma (`T11`), Sales Orders (`T12`), Purchase Orders (`T13`), **Delivery Challans (`T14`)**, PO/transport fields (`F08`, `F27`), per-doc terms (`F26`), 1-click convert to invoice. |
| **M1.5** | **Core GST Reports & Data Safety (`E11 core` + `E13`)** | GSTR-1/2/3B/4/9 exports (`R08`, `R09`), HSN/SAC & tax-rate summary (`R10`), TCS/TDS/RCM (`F14`, `F15`, `R11`), MRP/HSN catalog (`I03`, `I05`); catalog/party imports & photos (`I04`, `I16`, `I17`, `I24`), attachments (`F25`), recycle bin (`T21`), auto/encrypted backups (`O12–O14`), FY closing/period locks (`R25`). |

---

## Milestone 2 (M2) — Scale, Traceable Stock, Automation & Growth

| Phase | Scope | Key Deliverables |
|---|---|---|
| **M2.1** | **Multi-Firm, Warehouses & Traceable Stock (`E08`)** | Multiple firms (`A05`), warehouses/godowns (`A06`), primary/secondary units (`I08`, `D10`), batch/expiry/serial/IMEI (`I11–I13`), inter-store transfers (`I14`), stock valuation & expiry reports (`R05`, `R07`). |
| **M2.2** | **Advanced Pricing, BOM & Deep Reports (`E09`)** | Wholesale tiers (`I06`), party-specific pricing (`I07`), last-5-prices (`F22`), custom fields (`F24`), manufacturing/BOM (`I15`), party/item/category profit & discount reports (`R19–R22`). |
| **M2.3** | **Permissions, Finance Ops & POS (`E10`)** | Granular role/category permissions (`A08`), app lock (`A09`), cheques (`R16`), loans (`R17`), fixed assets (`R18`, `T16`), POS shift/drawer mode (`T22`). |
| **M2.4** | **Provider GST, Printing & Automation (`E11/E12.3/E14`)** | Provider-gated GSTIN lookup (`I23`), e-Invoice (`R26`), e-Way Bill (`R27`); Wi-Fi/USB thermal (`O08–O09`), multi-copy (`O03`, `O05–O06`); recurring invoices (`T15`), auto reminders/messaging (`I26`, `O18–O19`), scheduled email reports (`R23–R24`). |
| **M2.5** | **Storefront, Growth & Regional (`E15–E16`)** | Online catalog/orders (`O20`), payment links (`O21`), loyalty (`F28`, `O22`), CRM (`I27`), phone OTP / Google sign-in (`A02`), multi-currency/regional (`F06`, `R12`), Tally/Vyapar interop (`O17`), deferred Hindi web (`D14`). |

---

## Release & Human Acceptance (`E17–E18`)
- **E17:** Regression checks + clean release APK/web build before each milestone launch.
- **E18:** Owner hands-on UX walkthrough, decision on `STORELY_NATIVE_SALE_POSTING=true`, and production deployment.

---

## Next Phase Handoff
Hand **[docs/refactor/next-phase-prompt.md](docs/refactor/next-phase-prompt.md)** directly to the next AI session to implement **Phase M1.0**.
