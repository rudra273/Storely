# Next Phase Development Prompt — Phase M1.1: Typed Purchases & Expenses (`E04.2`)

Copy and paste this file into a new AI session to implement **Phase M1.1**.

---

## Context & Repositories

You are continuing development of **Storely** across three local checkouts (all ahead of remotes — do **not** reset or pull-overwrite):

| Repo | Path | Branch | Current HEAD | Schema |
|---|---|---|---|---|
| API (FastAPI + Postgres 18) | `/Users/rudra/projects/storelyapi` | `dev` | `44d75de` | Alembic `0030` |
| Web (React + TypeScript) | `/Users/rudra/projects/storelyweb` | `dev` | `20f5f53` | `openapi.json` synced |
| Mobile (Flutter / Android) | `/Users/rudra/projects/Storely` | `package-com-storely` | `530e507` (+ docs) | SQLite `v31` |

Read `/Users/rudra/projects/Storely/implementation-plan.md` for the roadmap and
`docs/refactor/feature-tracker.md` for row status.

### Ground Rules
- **No live production data yet:** clean, direct schema/API/UI changes; no legacy shims.
- **Keep existing UI theme, navigation shell, and Android local-only mode.**
- **Exact decimal money math** (`Decimal` API, `ExactDecimal` Android, `BigInt` paise Web).
- **Never** run `make reset`, `docker compose down -v`, or commit credentials/temp files.
- **Leave production deploy and final UX approval to the user.**

### What M1.0 delivered (build on it, don't duplicate)
- UI says **Items**; DB/API/models still say `products`.
- Full-screen item form (Android `lib/screens/products/item_form_screen.dart`, web `src/products/components/ProductForm.tsx`).
- `products.item_type` (`product`|`service`), `products.tax_type` (`taxable`|`exempt`|`none`), `products.cess_percent`; categories carry default `gst_percent`, `tax_type`, `cess_percent` (+ `apply_tax_to_items` on PATCH).
- Bill lines snapshot `item_type_snapshot`, `tax_type_snapshot`, `cess_percent_snapshot`, `cess_amount_snapshot` (**per unit**, like `gst_snapshot`); `bills.cess_amount` total. Line `tax_amount` is GST-only: `taxable + tax + cess == total`.
- Supported GST rates (API validation): `0, 0.25, 3, 5, 12, 18, 28, 40`. Cess 0..100.
- Endpoints: `POST /products/bulk-tax`, `POST /products/generate-code` (EAN-13 in-store `2…`).
- Top item field = `barcode`; `product_code` is the secondary "Short code".

### Open M1.0 items to keep in mind
- Android emulator and localhost browser walkthrough of M1.0 not yet run; owner UX review pending.
- API invoice PDF HSN summary does not include cess (Android/web do).
- Android purchase line editor is full screen but has no item-type / tax selector — **M1.1 fixes this**.
- A few web secondary texts still say "product" (import help, label dialog, "Product details").

---

## What to Build in Phase M1.1

1. **Line-level purchase GST/HSN/ITC (`T02`):** purchase lines carry tax_type, gst_percent, cess_percent, HSN/SAC, taxable value, CGST/SGST/IGST, cess, and an ITC-eligible flag; reuse the M1.0 tax math and selector widgets. Default from the item (then category).
2. **Taxable additional charges with SAC (`F16`):** freight/packing/other charges on sales bills and purchases with their own GST rate and SAC, included in totals, PDF and thermal output.
3. **Itemized expenses (`T05`):** expense lines with category, amount, GST/ITC, payment method; expense list/report.
4. **Purchase Register (`R06`):** filterable register with taxable/GST/cess/ITC columns and CSV export.

Apply across API (Alembic `0031`), SQLite (`v32`), sync contract, Web and Android.

## Codebase Invariants
1. **Sync data contract:** update `Storely/test/sync_data_contract_test.dart`, regenerate `Storely/docs/sync_data_contract.json`, copy to `storelyapi/tests/fixtures/sync_data_contract.json` (the test writes it only with `STORELY_WRITE_API_FIXTURE=1`).
2. **Authorization matrix:** add new API routes to `storelyapi/tests/test_authorization_matrix.py`.
3. **Web API types:** `make openapi` in storelyapi, then `make api-types` in storelyweb.

## Verification & Finish Checklist
1. **API:** `make lint`, `make test`, `make migrate`, `make test-integration`.
2. **Web:** `make api-types-check`, `make typecheck`, `make lint`, `make test`, `make build`.
3. **Mobile:** `flutter analyze`, `flutter test`.
4. **Live check:** `docker compose up -d --build api web` in storelyapi; app at `https://app.storely.localhost`, API health at `/health` and `/health/ready`.
5. **Commit cleanly** in all 3 repos; update `docs/refactor/feature-tracker.md` and this prompt for M1.2.
