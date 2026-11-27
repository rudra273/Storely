# E04.1 Contract — Purchase & Supplier Parity (`D06–D08`, `T02`, `T04`, `T08`, `T09`)

Status: Frozen for Base (v1) implementation (2026-11-27)

## Scope
Closes confirmed mobile/web divergences `D06`, `D07`, and `D08`, adds partial Purchase Returns / Debit Notes (`T08`), aligns full purchase & supplier payment reversal (`T09`), and ensures supplier dues, stock quantities, and weighted average stock cost converge identically across API, Web, and Android.

## 1. API Contract (`storelyapi`, Migration `0029_e04_1_purchase_returns`)

### 1.1 Bug Fixes
- `app/domains/purchases/native_purchases.py`: Ignore reversed receipts (`reversed_at is null`) when checking duplicate `(supplier_uuid, invoice_number)` in the same Indian FY.
- `app/routers/purchases.py`: Add `"reversed"` to `PaymentFilter` (`Literal["not_recorded", "unpaid", "partial", "paid", "open", "reversed"]`).

### 1.2 Database Schema (`0029_e04_1_purchase_returns.sql`)
- `public.purchase_returns`:
  - `uuid text primary key`
  - `shop_id text not null references public.shops(uuid) on delete cascade`
  - `purchase_uuid text not null` — FK `(shop_id, purchase_uuid) references public.purchase_documents(shop_id, uuid) on delete cascade`
  - `supplier_uuid text`
  - `supplier_name text`
  - `return_number text not null` — formatted `DN/{FY}/{seq:04d}` (e.g. `DN/2627/0001`), unique per `(shop_id, return_number)`
  - `request_key text not null`, `request_hash text not null`, unique `(shop_id, request_key)`
  - `return_date date not null` (reject future IST date `422 future_return`)
  - `reason text not null check (length(btrim(reason)) between 3 and 300)`
  - `subtotal numeric(16,2) not null check (subtotal >= 0)`
  - `tax_amount numeric(16,2) not null default 0 check (tax_amount >= 0)`
  - `total numeric(16,2) not null check (total >= 0)`
  - `payable_credit numeric(16,2) not null default 0 check (payable_credit >= 0)`
  - `refund_amount numeric(16,2) not null default 0 check (refund_amount >= 0)`
  - `refund_method text` (`cash | upi | card | bank_transfer | online`, required when `refund_amount > 0`)
  - `created_by uuid`
  - `created_at timestamptz not null default now()`
  - `unique (shop_id, uuid)`
- `public.purchase_return_items`:
  - `uuid text primary key`
  - `shop_id text not null`
  - `return_uuid text not null` — FK `(shop_id, return_uuid) references public.purchase_returns(shop_id, uuid) on delete cascade`
  - `purchase_item_uuid text not null` — FK `(shop_id, purchase_item_uuid) references public.purchase_document_items(shop_id, uuid)`
  - `product_uuid text not null`
  - `product_name text not null`
  - `unit_name text`
  - `quantity numeric(16,4) not null check (quantity > 0)`
  - `unit_cost numeric(16,4) not null check (unit_cost >= 0)`
  - `amount numeric(16,2) not null check (amount >= 0)`
  - `movement_uuid text not null` — unique FK `(shop_id, movement_uuid) references public.stock_movements(shop_id, uuid)`
- RLS policies enabled on both tables matching `purchase_documents` (`public.is_shop_member(shop_id)` for SELECT, admin write).
- `stock_movements` trigger guard permits `source_document_type = 'purchase_return'` when `app.posting_purchase_receipt` (or `app.posting_purchase_return`) matches the return UUID.
- Both tables registered in `server_managed_public_tables` in `Storely/test/sync_data_contract_test.dart` and mirrored to `storelyapi/tests/fixtures/sync_data_contract.json`.

### 1.3 Purchase Return Business Rules
- Acquires `lock_purchase_posting(shop_id)`.
- Idempotent by `(shop_id, request_key)` + canonical `request_hash`; mismatched payload returns `409 request_conflict`.
- Rejects reversed purchase (`409 purchase_reversed`).
- Rejects future `return_date` (`422 future_return`).
- For each line (`purchase_item_uuid`, `quantity`):
  - Validates line belongs to `purchase_uuid` (`422 bad_return_item`).
  - Validates `quantity <= original_item.quantity - already_returned_quantity` (`422 return_exceeds_purchased`).
  - Locks products `FOR UPDATE` in sorted UUID order and verifies `on_hand >= quantity` (`409 stock_used`).
  - Computes line `amount = round_half_up(quantity * original_item.unit_cost, 0.01)`.
  - Posts negative `stock_movements` (`movement_type='adjustment'`, `reason='purchase_return'`, `source_document_type='purchase_return'`, `source_document_uuid=return_uuid`, `quantity_delta=-quantity`, `unit_cost=original_item.unit_cost`).
  - Updates `products.purchase_price` via `cost_after_removal(on_hand, current_cost, quantity, original_item.unit_cost)` and refreshes `products.quantity_cache`.
- Totals & Settlement:
  - `subtotal = sum(line.amount)`, `total = subtotal + tax_amount`.
  - If parent purchase has `payment_status == 'not_recorded'`: `payable_credit = 0`, `refund_amount = 0`, `refund_method = None`, parent stays `not_recorded`.
  - Otherwise: `current_balance_due = max(0, purchase.total - live_paid - prior_payable_credit)`.
    - `payable_credit = min(total, current_balance_due)`.
    - `refund_amount = total - payable_credit`.
    - If `refund_amount > 0`: `refund_method` is required (normalized via `PurchaseMethod`, else `422 refund_method_required`).
- Bumps `purchase_documents.change_sequence = DEFAULT` and calls `refresh_payables` so `payment_status` becomes `'paid'` when `balance_due == 0` and mobile `/purchase-receipts/changes` pulls the updated snapshot.
- Reversal guard: `corrections.reverse_purchase()` rejects with `409 returns_recorded` if the purchase has any `purchase_returns`.

### 1.4 Endpoints & Payloads (Admin-only, registered in `test_authorization_matrix.py`)
- `POST /v1/shops/{shop_id}/purchase-receipts/{receipt_id}/returns` (201)
  - Body `PurchaseReturnIn`:
    ```json
    {
      "request_key": "string",
      "return_date": "YYYY-MM-DD",
      "reason": "string (3..300)",
      "tax_amount": "0.00",
      "refund_method": "cash|upi|card|bank_transfer|online|null",
      "items": [{ "purchase_item_uuid": "uuid", "quantity": "1.0000" }]
    }
    ```
  - Response `PurchaseReturnOut`: `uuid`, `purchase_uuid`, `supplier_uuid`, `supplier_name`, `return_number`, `return_date`, `reason`, `subtotal`, `tax_amount`, `total`, `payable_credit`, `refund_amount`, `refund_method`, `created_at`, `items[]` (`uuid`, `purchase_item_uuid`, `product_uuid`, `product_name`, `unit_name`, `quantity`, `unit_cost`, `amount`, `movement_uuid`).
- `GET /v1/shops/{shop_id}/purchase-receipts/{receipt_id}/returns` -> `list[PurchaseReturnOut]`.
- `ReceiptOut` adds: `returned_total: Decimal` (default `"0.00"`), `returns: list[PurchaseReturnOut]` (default `[]`).
- `ReceiptItemOut` adds: `returned_quantity: Decimal` (default `"0"`), `returnable_quantity: Decimal` (default `quantity`).
- `SupplierStatementOut` `LedgerEntryOut.kind` adds `"purchase_return"` (`amount` = `payable_credit`, `total` / `refund_amount` in description/note, `reference_uuid` = `purchase_uuid`).
- `ContractFeatures` (`app/routers/shops.py`): adds `purchase_returns: int = 1`.

## 2. Mobile Parity (`Storely` Flutter Android)
- **D06 (`PurchaseHistoryScreen` / `_PurchaseDetails`)**:
  - Model `reversedAt`, `reversalReason`, `returnedTotal`, `returns[]`, and per-item `returnedQuantity` / `returnableQuantity` in `PurchaseDocument`.
  - Expose `Pay supplier` (deep-links to `SupplierPaymentsScreen(initialPurchaseUuid: receipt.uuid)`), `Record payment terms`, `Return items (Debit note)`, and `Reverse purchase` actions with matching server guards.
  - Display reversed banner, returns/debit notes list, and returned quantities cleanly; preserve local-only mode gracefully.
- **D07 (`SupplierPaymentsScreen` & `supplier_payment_queue`)**:
  - Support optional `purchase_uuid` selector (`Oldest unpaid bills (FIFO)` or specific unpaid/partial receipt), `reference`, and `notes` inputs.
  - Distinguish **Confirmed** vs **Pending on this device** vs **Failed/Conflict** states clearly.
  - Expose `Reverse` action on confirmed supplier payments (`T09`).
- **D08 (`SupplierPaymentsScreen` & `database_purchase_documents.dart`)**:
  - Exclude reversed purchases from local balance aggregation.
  - Show **Confirmed balance**, **Pending on this device**, **Projected balance after sync**, and sync freshness separately.
  - Refresh synced purchase snapshots after online mutations so confirmed balance converges to `0.00` diff against Web/API.

## 3. Web Parity (`storelyweb`)
- Regenerate OpenAPI types (`make api-types`).
- `PurchaseDetailPage`: add `Return items` dialog (`PurchaseReturnDialog`), display `Returns / Debit notes` list, `Returned` total/line badges, and handle `returns_recorded` reversal guard.
- `SupplierDetailPage`: render `purchase_return` entries in the statement ledger.
- `SupplierPayment`: add optional `notes` field for full `D07` parity.
- `ledgerLabels.ts`: map `purchase_return` stock movement source to `/purchases/{purchase_uuid}`.
