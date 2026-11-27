# Atomic sale sync

Android commits a reviewed sale, its initial payment, stock effects, and the cart tombstone in one SQLite transaction. Legacy cloud sync pushes tables separately and can expose a header or stock effect before the rest arrives. Web posts the entire sale in one API transaction. The purchase document adoption flow verifies previously uploaded stock movements.

## Local posting snapshot

A new reviewed checkout captures a versioned snapshot of the accepted invoice, lines, initial payment and sale movements in its existing `checkout_acceptances` record. The attempt, shop and owner are the outer record identity. The snapshot records the origin device and durable row UUIDs. A local replay returns the original invoice and does not replace the snapshot. A failure during acceptance rolls back the snapshot and all posting effects. Earlier acceptances keep a null snapshot because current mutable rows cannot establish the original state. The snapshot is device-only and stays out of the row-sync and portable restore contracts.

## Server preflight

`POST /v1/shops/{shop_id}/bills/native/preflight` checks a recorded invoice UUID and number, a structured cart and the recorded line and invoice amounts. It requires a current paid shop membership and applies the same custom-line permissions as ordinary billing. The current catalog rules check available stock and price the cart. The response reports `matched_recorded_amounts` only when its compared line and invoice amounts agree. A shortage, a reused cloud invoice identity or differing amounts need reconciliation. Preserve the original Android invoice for that review. The check does not reserve inventory, verify a payment receipt, consume an operation key or post business rows. An eventual posting command must repeat the checks inside the acceptance transaction.

## Server posting

`POST /v1/shops/{shop_id}/bills/native` is a separate command for a recorded checkout. It requires a paid membership, a device registered to the caller, and a stable `Idempotency-Key`. The server locks current stock, verifies the recorded line and invoice amounts, and applies the existing settlement and custom-line permissions. If accepted, it writes the invoice number and identity, shop-local invoice time, original line/payment/movement IDs, and server-validated business effects in one transaction. Identity collisions, shortages and amount mismatches roll back the entire transaction, including the retry key.

An exact retry returns the existing invoice. A changed payload using the same key receives a conflict. The existing operations endpoint can look up a committed key. The current command accepts sales whose recorded amounts match the current server rules. It does not overwrite a legacy upload or force a shortage through. Server-generated pricing metadata comes from the validated cloud calculation, so client rollout still needs to cover historical snapshot differences and block ambiguous dual delivery.

## Android delivery

An opt-in Android build uses `--dart-define=STORELY_NATIVE_SALE_POSTING=true`. A successful sync enables selection for the current shop, owner or admin account, and device when capabilities advertise `native_sale_posting: 1`, `native_sale_snapshot_proof: 1`, and confirm the device belongs to the signed-in account. The flag defaults to off. A checkout selects and saves its request in the SQLite acceptance transaction. Staff and sales outside the supported catalog and settlement cases use row sync for new checkouts. Previously reserved requests retain their original key, payload, and route, including requests saved before snapshot proof was available.

Reserved sales keep the invoice, items, payments, sale movements, related billing changes, and consumed cart tombstone out of legacy uploads until the original command is confirmed. Sync sends the saved body and checkout attempt key. Account-scoped transport checks the current actor before sending and after an authentication retry. If the response is lost, the app replays the same command on the next sync. Acknowledgement verifies the returned invoice number and the original invoice, line, and payment IDs. SQLite then marks the original rows uploaded and releases the tombstone and any eligible dependent rows. Pull cursors stay at their prior position when a reserved row is skipped, so the cloud data can be read after acknowledgement.

Rejection keeps the request and original invoice reserved. A local edit to a reserved sale requires reconciliation and keeps its effects out of both delivery paths. The existing sync status shows the problem and preserves the reservation across restart and capability changes.

## Historical line proof

New native commands carry the accepted purchase price, cost, profit, HSN code and type, and unit for every line. The API compares the text exactly and each financial snapshot to nine decimal places with half-up rounding. It verifies the same values it will store, under the posting transaction. A mismatch keeps the original invoice reserved and rolls back the cloud command. Snapshot verification is restricted to owner and admin accounts because comparing private costs can disclose them.

The API confirms proof version 1 after checking the stored line snapshots. Exact replay checks the issued lines without re-reading current catalog values. Android requires that confirmation and checks the returned HSN and unit before releasing the reservation. Earlier proofless requests use their original acknowledgement contract.

## Reconciliation

Reserved native sales can stall when cloud stock drops below the recorded sale quantity (`insufficient_stock`), when cloud pricing, tax, or historical cost/HSN/unit snapshots change after offline checkout (`native_sale_terms_changed`, `native_sale_snapshot_changed`), when the local invoice is edited while still reserved (`reconcile`), or when the server committed the original command but the response was lost.

- **Capabilities**: `GET /v1/shops/{shop_id}/capabilities` advertises `native_sale_reconciliation: 1`.
- **Read-only inspection**: `POST /v1/shops/{shop_id}/bills/native/reconcile/inspect` inspects a reserved `attempt_id` and frozen `NativeSalePostIn` without mutating rows, reserving stock, or consuming the operation key. It checks `operation_status` (`idempotent_write`), invoice/line/payment/movement identity collisions, tracked stock shortages, pricing/tax differences, and (for owner/admin only) historical snapshot differences. Staff cannot inspect strict snapshot requests (`403 native_sale_snapshot_permission`).
- **Explicit reconciliation**: `POST /v1/shops/{shop_id}/bills/native/reconcile` requires owner/admin membership, the registered device owned by the caller, the original `Idempotency-Key` (`attempt_id`), explicit approval flags (`allow_stock_shortage`, `accept_recorded_snapshot`), and a non-empty auditable `reason`. If the original `attempt_id` already committed for the same invoice, the endpoint replays the committed invoice without creating duplicates. Otherwise it validates self-consistent recorded math, locks stock, writes the exact original invoice, line, payment, and movement IDs in one transaction, records an `audit_log` entry (`native_sale_reconciled`), and verifies stored snapshots before returning `native_sale_snapshot_verified: 1`.
- **Local edits and lost responses on Android**: The original issued invoice, frozen request body, `attempt_id`, and reservation are preserved across retries, restarts, and account/shop switches. Android surfaces reconciliation from the existing Sync Status conflict menu (`Review & reconcile`) without exposing `Use cloud copy`. Confirming an already-committed server invoice or explicitly posting the original frozen invoice clears `sync_dirty` only for rows that still match `posting_snapshot`, leaving post-issue local edits (such as customer updates, later payments, or cancellations) dirty to sync cleanly on top of the committed cloud invoice.

## Rollout gates

1. Explicit reconciliation for offline stock shortages, snapshot discrepancies, edited pending invoices, and lost-response commits is governed by the contract above.
2. Verify safe upgrade, restore, downgrade, and mixed-version operation before enabling selection in release builds. Each device needs to preserve its operation reservation, and adopting previously synced or restored invoices needs an explicit decision.
3. Apply atomic commands and recovery to later payments, cancellations, and credit notes. Compare interrupted and competing writes across Android, web and exports before the final human UX review.
