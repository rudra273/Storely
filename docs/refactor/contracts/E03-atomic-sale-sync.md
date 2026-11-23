# Atomic sale sync

Android commits a reviewed sale, its initial payment, stock effects, and the cart tombstone in one SQLite transaction. The existing cloud loop pushes tables separately and can expose a header or stock effect before the rest arrives. Web posts the entire sale in one API transaction. A separate purchase document adoption flow verifies previously uploaded stock movements and does not provide atomic sale delivery.

## Local posting snapshot

A new reviewed checkout captures a versioned snapshot of the accepted invoice, lines, initial payment and sale movements in its existing `checkout_acceptances` record. The attempt, shop and owner are the outer record identity. The snapshot records the origin device and durable row UUIDs. A local replay returns the original invoice and does not replace the snapshot. A failure during acceptance rolls back the snapshot and all posting effects. Earlier acceptances keep a null snapshot because current mutable rows cannot establish the original state. The snapshot is device-only and stays out of the row-sync and portable restore contracts.

## Server preflight

`POST /v1/shops/{shop_id}/bills/native/preflight` checks a recorded invoice UUID and number, a structured cart and the recorded line and invoice amounts. It requires a current paid shop membership and applies the same custom-line permissions as ordinary billing. The current catalog rules check available stock and price the cart. The response reports `matched_recorded_amounts` only when its compared line and invoice amounts agree. A shortage, a reused cloud invoice identity or differing amounts need reconciliation. Preserve the original Android invoice for that review. The check does not reserve inventory, verify a payment receipt, consume an operation key or post business rows. An eventual posting command must repeat the checks inside the acceptance transaction.

## Server posting

`POST /v1/shops/{shop_id}/bills/native` is a separate command for a recorded checkout. It requires a paid membership, a device registered to the caller, and a stable `Idempotency-Key`. The server locks current stock, verifies the recorded line and invoice amounts, and applies the existing settlement and custom-line permissions. If accepted, it writes the invoice number and identity, shop-local invoice time, original line/payment/movement IDs, and server-validated business effects in one transaction. Identity collisions, shortages and amount mismatches roll back the entire transaction, including the retry key.

An exact retry returns the existing invoice. A changed payload using the same key receives a conflict. The existing operations endpoint can look up a committed key. The current command accepts sales whose recorded amounts match the current server rules. It does not overwrite a legacy upload or force a shortage through. Server-generated pricing metadata comes from the validated cloud calculation, so client rollout still needs to cover historical snapshot differences and block ambiguous dual delivery.

## Cloud delivery gates

1. Map the captured Android sale to the server command without rewriting the locally issued invoice. Decide how an offline sale that now exceeds server stock is reconciled. Android permits negative stock after a warning. The server command leaves a shortage unresolved for review.
2. Negotiate capability before sending. A lost response leaves the device outcome uncertain until authenticated recovery or exact replay confirms it.
3. Select the transport before publishing an operation. The command and the legacy row paths must agree on ownership of its invoice, payment and stock effects. Do not send both paths on an ambiguous result. Handle earlier row uploads and edits with explicit identity checks before adopting an invoice. A local-only checkout or a snapshot under a former shop or account requires a separate, explicit adoption decision during first sync.
4. Apply the same contract to subsequent payments and credit notes with their own identities and revision checks. Confirm that interrupted and competing writes produce exactly one matching ledger result in browser, Android, and exports.

Local capture, server preflight and server posting are implemented. Android continues to use legacy row uploads while command transport selection is pending.
