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

An opt-in Android build uses `--dart-define=STORELY_NATIVE_SALE_POSTING=true`. A successful sync enables selection for the current shop, account, and device when capabilities advertise `native_sale_posting: 1` and confirm the device belongs to the signed-in account. The flag defaults to off. A checkout selects and saves its request in the SQLite acceptance transaction. Earlier sales and sales outside the supported catalog and settlement cases keep their original row-sync delivery.

Reserved sales keep the invoice, items, payments, sale movements, related billing changes, and consumed cart tombstone out of legacy uploads until the original command is confirmed. Sync sends the saved body and checkout attempt key. Account-scoped transport checks the current actor before sending and after an authentication retry. If the response is lost, the app replays the same command on the next sync. Acknowledgement verifies the returned invoice number and the original invoice, line, and payment IDs. SQLite then marks the original rows uploaded and releases the tombstone and any eligible dependent rows. Pull cursors stay at their prior position when a reserved row is skipped, so the cloud data can be read after acknowledgement.

Rejection keeps the request and original invoice reserved. A local edit to a reserved sale requires reconciliation and keeps its effects out of both delivery paths. The existing sync status shows the problem and preserves the reservation across restart and capability changes.

## Rollout gates

1. Resolve offline stock shortages, catalog and pricing snapshot differences, and edited pending invoices. The opt-in command validates recorded amounts against current stock and pricing. The rollout needs an explicit resolution flow, including exact verification of cost, HSN and unit snapshots.
2. Verify safe upgrade, restore, downgrade, and mixed-version operation before enabling selection in release builds. Each device needs to preserve its operation reservation, and adopting previously synced or restored invoices needs an explicit decision.
3. Apply atomic commands and recovery to later payments, cancellations, and credit notes. Compare interrupted and competing writes across Android, web and exports before the final human UX review.
