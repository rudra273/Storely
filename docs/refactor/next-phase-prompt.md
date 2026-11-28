# Next Phase Development Prompt — Phase M1.0: Items, GST/Cess, Category Defaults & Billing UX

Copy and paste this file into a new AI session to implement **Phase M1.0** cleanly and quickly.

---

## Context & Repositories

You are continuing development of **Storely** across three local checkouts (all ahead of remotes — do **not** reset or pull-overwrite):

| Repo | Path | Branch | Current HEAD | Schema |
|---|---|---|---|---|
| API (FastAPI + Postgres 18) | `/Users/rudra/projects/storelyapi` | `dev` | `293bf0b` | Alembic `0029` |
| Web (React + TypeScript) | `/Users/rudra/projects/storelyweb` | `dev` | `441c506` | `openapi.json` synced |
| Mobile (Flutter / Android) | `/Users/rudra/projects/Storely` | `package-com-storely` | `b2c3c1b` | SQLite `v30` |

Read `/Users/rudra/projects/Storely/implementation-plan.md` for the short overall roadmap.

### Ground Rules
- **No live production data yet:** Make clean, direct schema/API/UI changes. Do **not** waste time writing heavy legacy-data migration shims or mixed-version backward-compatibility layers.
- **Keep existing UI theme, navigation shell, and Android local-only mode.**
- **Keep exact decimal money math** (`Decimal` on API, `ExactDecimal` on Android, `BigInt` paise on Web).
- **Never** run `make reset`, `docker compose down -v`, or commit credentials/temp files.
- **Leave production deploy and final UX approval to the user.**

---

## What to Build in Phase M1.0 (Across API, Web, and Android)

Implement these 7 cohesive upgrades together so the Item catalog, GST/Cess engine, and Bill creation flow are rock-solid before M1.1–M1.5:

### 1. Terminology: "Products" → "Items" (UI Labels Only)
- Update user-facing labels, tab/page titles, buttons, empty states, and search placeholders from **Product / Products** to **Item / Items** on both Android and Web.
- Keep existing DB table names (`products`), API paths (`/products`), and internal model names intact so nothing breaks unnecessarily.

### 2. Full-Screen Create / Edit Item (No Bottom Sheet)
- On **Android**, replace the cramped bottom-sheet item creation (`quick_add_sheet.dart` / modal sheets) with a dedicated **full-screen Create / Edit Item page** (`Scaffold` with clean sections: Basic Info, Pricing & Tax, Stock/Inventory).
- On **Web**, ensure Create / Edit Item uses a clean full-page or spacious dedicated view (not a cramped small popover).
- Keep the top section fast for quick entry (Name, Type, Category, Selling Price, GST, Code) with optional/collapsible advanced fields (Purchase Price, Opening Stock, Low-Stock Alert, HSN/SAC).

### 3. Item Type: `Product` vs `Service` (`I02`)
- Add `item_type` (`'product' | 'service'`, default `'product'`) to items across API (Alembic `0030`), SQLite (`v31`), sync contract, Web, and Android.
- **Product:** Tracks stock, unit, low-stock threshold, HSN code, barcode, purchase cost.
- **Service:** Non-stock (never deducts stock, never fails stock checks, hides stock fields on form, uses SAC code label instead of HSN).

### 4. Item Code / Barcode: `Generate` + `Scan`
- On the Create / Edit Item screen (Android + Web), put two clear inline actions on the Item Code / Barcode field:
  1. **Scan** — opens barcode scanner (existing camera/scanner flow on Android; keyboard/scanner input on Web).
  2. **Generate** — 1-tap generates a unique shop-scoped item code (e.g., collision-checked numeric/alphanumeric code suitable for barcode labels) without overwriting unless confirmed if already filled.

### 5. Category Default GST + Per-Item GST & Cess (`None` / `Exempt` / `0%..28%` + `Cess`)
- **Taxability & Cess fields on Items** (API + SQLite + Sync + Web + Android):
  - `tax_type`: `'taxable' | 'exempt' | 'none'` (default `'taxable'` when `gst_rate > 0`, or explicit user choice).
  - `gst_rate`: `0, 5, 12, 18, 28` (or custom numeric %).
  - `cess_rate`: optional numeric `%` (e.g., `12` for `+12% Cess`, default `0`).
  - Provide a clean selector in UI covering: **None**, **Tax Exempt**, **GST @ 0%**, **GST @ 5%**, **GST @ 12%**, **GST @ 18%**, **GST @ 28%**, plus an optional **+ Cess (%)** picker/input (common presets like `1%`, `3%`, `5%`, `12%`, `15%`, `22%` + custom).
- **Category Default GST:**
  - Add optional `default_tax_type`, `default_gst_rate`, `default_cess_rate` to Categories (API + SQLite + Web + Android).
  - When creating a new Item and choosing a Category, **auto-fill** the item's `tax_type`, `gst_rate`, and `cess_rate` from the category (user can still override freely on the item).
  - When updating a category's default GST, offer an optional toggle/prompt: *"Also update existing items in this category?"* (never mutate past invoices).
- **Billing & Invoice Math + PDF/Print:**
  - Include `cess_rate` and `cess_amount` in line & bill totals, API/Web/Android calculators, and invoice PDF/thermal output (when `cess_amount > 0`).
  - `none` and `exempt` compute `0` tax and store their taxability snapshot on bill lines so future GSTR-1 reports can distinguish Exempt vs Nil-rated vs Non-GST.

### 6. Bulk Edit GST Rates
- Add **"Set GST"** to the existing multi-select bulk action bar on **Android** (`product_bulk_actions.dart`) and **Web** Items list.
- Allow selecting multiple items (or filtering by category) and updating `tax_type`, `gst_rate`, and `cess_rate` in one batch API/local call.

### 7. Bill Creation: Optional Customer / Party Bar at Top + Fast Item Entry
- On **Create Bill** (both Android and Web):
  - Place a compact, always-visible **Customer / Party selector bar at the top** of the bill screen, defaulting to **Walk-in / Cash** (1-tap to pick/search/add a customer, never blocks billing).
  - Keep **fast Item scanning / search / add** immediately accessible right below so walk-in counter billing stays 1-tap fast while B2B billing lets you pick the customer first.
  - Ensure held carts, draft persistence, and checkout review/settlement stay intact.

---

## Important Codebase Invariants (Don't Miss These)
1. **Sync Data Contract:** Any new columns/tables in `public.*` must be reflected in `Storely/test/sync_data_contract_test.dart`, regenerated to `Storely/docs/sync_data_contract.json`, and copied to `storelyapi/tests/fixtures/sync_data_contract.json`.
2. **Authorization Matrix:** Any new API routes must be added to `storelyapi/tests/test_authorization_matrix.py`.
3. **Web API Types:** After API schema changes, run `make openapi` in `storelyapi` and `make api-types` in `storelyweb`.

---

## Verification & Finish Checklist
1. **API (`storelyapi`):** `make lint`, `make test`, `make migrate`, `make test-integration` (Docker PG).
2. **Web (`storelyweb`):** `make api-types-check`, `make typecheck`, `make lint`, `make test`, `make build`.
3. **Mobile (`Storely`):** `flutter analyze`, `flutter test` (including new tests for full-screen item form, service item billing, category default GST, Cess math, bulk GST, barcode generate, and top customer bar).
4. **Live check:** Rebuild Docker `api` + `web` (`docker compose up -d --build api web`) and sanity-check `https://localhost`.
5. **Commit cleanly** in all 3 repos and update `Storely/docs/refactor/feature-tracker.md` (and `next-phase-prompt.md` for M1.1).
