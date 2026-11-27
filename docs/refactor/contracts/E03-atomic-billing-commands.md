# Atomic billing follow-up commands (E03.2)

Later invoice payments, cancellations, and credit notes recorded offline on Android (`STORELY_NATIVE_SALE_POSTING=true`) must deliver as atomic, idempotent cloud commands rather than independent row-sync pushes. This prevents concurrent overpayment, over-return, partial credit-note exposure, and unguarded cancellation.

## Capabilities

`GET /v1/shops/{shop_id}/capabilities` advertises `native_billing_commands: 1` alongside `native_sale_posting: 1`, `native_sale_snapshot_proof: 1`, and `native_sale_reconciliation: 1`. Selection on Android requires `STORELY_NATIVE_SALE_POSTING=true`, `native_billing_commands: 1`, and `native_sale_device_registered: true` for the active `(shop_id, owner, device_id)`.

## API endpoints

All three commands require paid shop membership, caller-owned device registration (`403 native_sale_device`), and a valid `Idempotency-Key` header (`KEY`). Any validation, permission, or conflict failure rolls back the entire transaction, including the idempotency key. Exact replay returns `200 OK` with `Idempotent-Replay: true` and the committed `BillDetail`.

1. **`POST /v1/shops/{shop_id}/bills/{bill_id}/payments/native`** (`201 Created`, `BillDetail`, `shops.ANY_MEMBER`):
   - Body: `payment_uuid`, `device_id`, `received_at` (tz-naive shop-local, `<= now + 5m`), `amount`, `method` (`SalesMethod`), `reference` (optional), `notes` (optional).
   - Locks the invoice `FOR UPDATE`, rejects cancelled/credit-note/overpayment (`409`), inserts `bill_payments` with `new_only=True` (`409 native_sale_identity_exists`), refreshes payment summary, and writes `audit_log`.
2. **`POST /v1/shops/{shop_id}/bills/{bill_id}/cancel/native`** (`200 OK`, `BillDetail`, `shops.ADMINS`):
   - Body: `device_id`, `cancelled_at` (tz-naive shop-local, `<= now + 5m`), `reason` (optional).
   - Locks the invoice/credit note `FOR UPDATE`, rejects already-cancelled (`409 cancelled`) or open credit notes (`409 has_credit_notes`), writes deterministic `void-{bill_uuid}-{item_uuid}` stock movements, soft-deletes items/payments/bill, undoes credit-note adjustment if applicable, refreshes customer, and writes `audit_log`.
3. **`POST /v1/shops/{shop_id}/bills/{bill_id}/credit-note/native`** (`201 Created`, `BillDetail`, `shops.ADMINS`):
   - Body: `credit_note_uuid`, `credit_note_number`, `device_id`, `created_at` (tz-naive shop-local, `<= now + 5m`), `settlement` (`"refund" | "adjust"`), `refund_method` (`SalesMethod`), `reason` (optional), `lines` (`[{line_uuid, original_item_uuid, movement_uuid?, quantity}]`), `note_payment_uuid` (optional), `invoice_adjustment_payment_uuid` (optional).
   - Locks original invoice `FOR UPDATE`, validates distinct UUIDs, remaining returnable quantities (`409 too_many`), and adjustment bound (`409 adjust_too_much`), writes credit note header, lines (carrying original snapshots), return stock movements, and settlement payment(s) with `new_only=True`, refreshes summaries/customer, and writes `audit_log`.

## Android durable reservation & delivery

- Device-only SQLite table `native_billing_commands` stores `command_id` (stable `Idempotency-Key`), `shop_id`, `owner`, `device_id`, `command_type` (`payment | cancel | credit_note`), `bill_uuid`, `target_uuid`, `request_json`, `reserved_uuids_json`, `state` (`pending | posted`), `last_error`, and `created_at`.
- `recordBillPayment`, `cancelBill`, and `createCreditNote` enqueue the command in the same SQLite transaction as their local effects when enabled for the active scope.
- Reserved rows stay out of legacy row push and cloud pull (holding back pull cursors) until the command is acknowledged.
- `CloudSyncEngine` delivers `native_billing_commands` in creation order immediately after `_syncNativeSales`, verifies returned identities, clears `sync_dirty = 0` on reserved rows in one transaction, and marks `state = 'posted'`.
- `Use cloud copy` is refused for `native_billing_commands` conflicts; local records and operation keys are preserved.
