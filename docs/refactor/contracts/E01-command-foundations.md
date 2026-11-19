# E01 command foundations — draft for implementation

Status: the universal design remains proposed; current implemented boundaries are in [slice 4](E01-slice-4.md) and preceding slices. [Slice 1](E01-slice-1.md) freezes the implemented recovery and decimal boundaries. This document is not a frozen universal wire schema. E00 live baseline must finish before new business commands replace existing sync. Existing routes remain compatible until an additive migration and client negotiation are tested.

## Initial implementation anchors (before the verified slices)

- API purchase receipt requests bind `request_key` to a normalized payload fingerprint; native receipt adoption verifies existing stock movements rather than receiving stock twice (`app/domains/purchases/native_purchases.py`). This is an adoption protocol, not proof that upload of every stock row is atomic.
- Mobile purchase drafts store UUID/shop/revision, while sale drafts currently persist only cart items. Supplier payments have an explicit pending queue.
- Web billing persists an uncertain attempt with exact body/key. Generic draft storage can silently fail; purchase draft persistence is stricter.

## Shared invariants for the next slice

1. An operation identity is stable across timeout, restart and retry. Persist exact business payload before sending. Payload edits require a new operation only after the previous result is definitively known.
2. Bind identity to tenant, operation kind, source document and normalized payload; never accept a replay under another shop or authorization context.
3. Actor identity comes from verified authentication/server context, not an editable request field. Origin device and local account ownership are separately validated.
4. Distinguish local draft, ready, sending, unknown, accepted, rejected and conflict. A network error after send is unknown until lookup/replay establishes the result.
5. Stock movements, allocations, document snapshots and audit effects commit in the same transaction. Future journal adapter must share that boundary.
6. Pending local projection remains distinguishable from server-confirmed balances. Cross-device globally constrained stock/credit cannot be guaranteed while offline.
7. Expected revision protects edits/conversions/allocations. New operation creation does not overwrite an existing immutable financial snapshot.
8. JSON money/quantity/rate contracts use decimal strings with named scale/rounding policy. Keep legacy readers; never silently reprice issued invoices.
9. Replays authorize the current caller and return a safe current representation of the original result; no new effects. Conflicting payload returns a stable conflict code.
10. A durable outbox records attempt/result/retry timing and safe diagnostics without credentials. Scheduling and provider reconciliation build on this infrastructure later.

## Required contract decisions before code

- Exact command envelope and compatibility/version negotiation, including existing billing keys versus purchase request keys.
- Canonical payload normalization (decimal trailing zeros, dates/timezones, ordering, optional fields) with independent fixtures.
- Lookup authorization, retention and supported unknown-result recovery after logout/account change.
- Atomic acceptance versus adoption of already-synced native movements; reject partial groups and stale tombstones.
- Minimal SQLite/PostgreSQL additive tables/indexes, transaction boundaries and migration recovery.
- Precise mapping of transport errors versus domain rejection versus conflict, with matching web/mobile user recovery.

No new universal endpoint or monetary algorithm is declared implemented by this document. The E01 implementation will freeze these decisions with tests across all three repos.
