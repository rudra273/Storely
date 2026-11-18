# E01 slice 2 — serialized posting and durable attempt ownership

Status: implemented and verified as a bounded E01 slice; see [evidence](../evidence/E01/slice-2.md). This slice extends the implemented recovery contract without introducing a universal command endpoint or changing issued financial snapshots.

## API posting boundary

The domain already serializes purchases/payments with a shop advisory transaction lock, but routes classified a replay before acquiring that lock. Concurrent identical requests could both report a new posting to audit even while domain idempotency correctly prevented duplicate financial effects. Acquire the same lock before replay classification and retain it through document/payment, allocation and audit writes in the request transaction. Concurrent identical requests must produce one financial result and one creation audit event; injected audit failure must roll back the financial aggregate.

No ledger fingerprint is recomputed. Durable jobs and the future journal interface remain separate E01 work. Auth email delivery currently uses BackgroundTasks; moving codes and account-security notices into persistent storage requires an explicit sensitive-payload lifecycle design rather than an unused general queue.

## Mobile supplier-payment attempt state

Keep the existing exact payload/request key and legacy sync_state contract. Add local-only durable attempt metadata through an additive SQLite migration: explicit ready/sending/unknown/accepted/rejected/conflict states, attempt count and last-attempt timestamp. Persist sending before network; transport uncertainty preserves the same request for replay. A restarted process must recover an abandoned sending attempt without generating a new identity. Definitive rejection and uncertainty must remain distinct. Concurrent senders must not both claim an active attempt; acknowledgement must remain bound to the captured shop.

Unknown attempts remain reflected in pending supplier balance, preventing a second local payment from spending the same balance. Legacy pending rows migrate to unknown because their previous send history cannot be proven. Existing backups/compatibility readers and the checked field classification must handle new metadata and old rows. A denied replay after uncertainty cannot release the reservation; a conflict also retains the reservation. If a remotely committed payment appears in the receipt feed before its UUID is recovered, the conservative local reservation can temporarily understate available balance. Exact confirmed balance requires authorized replay/reconciliation, not matching by amount. This is one production adapter, not completion of every sales-command outbox.

## Web invoice draft ownership

Serialize draft save/clear using a browser Web Lock scoped to user and shop. Read and compare the expected storage snapshot inside the exclusive lock, then write and verify before invoice submission. Keep the critical section limited to storage operations; never hold it over a network request. Browser lock release on callback completion/tab teardown replaces a manually timed lease. Frozen retries retain the existing exact body/key, so duplicate transmission of that same attempt remains idempotent at the server.

When exclusive locking is unavailable, fail closed with an actionable persistence error and no invoice POST. Reload recovery, malformed record rejection, stale-tab conflict, safe rejection and explicit signout privacy behavior remain covered. This does not introduce cross-device draft ownership.

## Validation gates

API: actual concurrent requests and transaction rollback against scratch PostgreSQL plus lint/unit checks. Mobile: migration/reopen, abandoned send, lost acknowledgement/exact replay, terminal rejection and shop/concurrent-sender protection plus analyzer. Web: queued contenders, unsupported locks, storage failure/no POST and reload recovery, then real browser checks. Coordinator records exact revisions, fixture compatibility and integration outcomes before marking the slice verified.
