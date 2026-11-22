# Atomic sale sync

Android commits a reviewed sale, its initial payment, stock effects, and the cart tombstone in one SQLite transaction. The existing cloud loop pushes tables separately and can expose a header or stock effect before the rest arrives. Web posts the entire sale in one API transaction. A separate purchase document adoption flow verifies previously uploaded stock movements and does not provide atomic sale delivery.

## Local posting snapshot

A new reviewed checkout captures a versioned snapshot of the accepted invoice, lines, initial payment and sale movements in its existing `checkout_acceptances` record. The attempt, shop and owner are the outer record identity. The snapshot records the origin device and durable row UUIDs. A local replay returns the original invoice and does not replace the snapshot. A failure during acceptance rolls back the snapshot and all posting effects. Earlier acceptances keep a null snapshot because current mutable rows cannot establish the original state. The snapshot is device-only and stays out of the row-sync and portable restore contracts.

## Cloud delivery gates

1. Define a supported sale command that validates membership, entitlement, product/customer identities and internal totals on the server. Decide how a valid offline sale that now exceeds server stock is reconciled. Today Android permits negative stock after a warning and the web sale route refuses a shortage. Preserve issued invoice identity and snapshots while handling the difference explicitly.
2. Negotiate capability before sending. Bind the attempt identity and content to durable server acceptance. Return the existing accepted result after an exact replay and report conflicting content without writing more effects. A lost response leaves the device outcome uncertain until recovery or replay confirms it.
3. Select the transport before publishing an operation. The command and the legacy row paths must agree on ownership of its invoice, payment and stock effects. Do not send both paths on an ambiguous result. Handle earlier row uploads and edits with explicit identity checks before adopting an invoice. A local-only checkout or a snapshot under a former shop or account requires a separate, explicit adoption decision during first sync.
4. Apply the same contract to subsequent payments and credit notes with their own identities and revision checks. Confirm that interrupted and competing writes produce exactly one matching ledger result in browser, Android, and exports.

The current increment implements local capture. The legacy upload route remains active, so a captured snapshot alone says nothing about cloud acceptance.
