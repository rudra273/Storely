# E01 slice 5 — settings revisions and shared posting adapters

19 November 2026. Status: implemented and verified; [evidence](../evidence/E01/slice-5.md). This slice completes the previously open implementation areas for aggregate settings and the stock/payable/journal interface. E01's final contract/fixture acceptance audit remains separate from human UX acceptance.

## Settings contract

InvoiceSettings adds readonly opaque revision `s1:<counter>`. InvoiceSettingsIn accepts optional expected_revision for legacy compatibility; a mismatch returns 409 settings_changed with no partial settings/audit write. New web clients require `features.settings_revision:1` and always send the token as a string; missing guard support cannot fall back to an unguarded write.

The counter covers existing shops/app_settings/bill_settings mutations, including legacy sync, deletes, tombstones and resurrection. Transport clocks alone do not invalidate edits. Statement triggers coordinate before row locks: modern declared tenant writers take global shared then tenant exclusive locks; context-free legacy SQL takes global exclusive fallback. Aggregate GET uses global/tenant shared locks for one projection/token. PATCH and settings sync acquire scope before entitlement locks. The declaration is checked against actual affected tenants. Counter state is member-readable under RLS and trigger-owned for writes. Reapplying the migration preserves counters/configuration.

Compatibility is for legacy clients using the updated server; arbitrary old server transactions with other pre-held locks require coordinated rollout. This is not a conversion of every domain settings reader to guarded snapshots or a replacement for legacy last-writer sync.

## Client behavior

Mobile captures canonical persisted config values before loading editors; save checks under SQLite transaction include active shop and omit runtime counters/transport metadata. Bill layout and default series formatting save in one transaction, preserving numbering counters. Profile/pricing sheets save before closing, so stale failures retain input. Existing derived product repricing remains separate.

Web freezes original settings/revision independently of refetch. Conflict keeps input and blocks resave until explicit latest review; rebase preserves unrelated remote fields and merges only locally changed visibility keys. Existing tabs/preview/theme remain. Raw image bytes are not shown in conflict reviews. Cross-client UX parity remains E02.

## Posting interface

PostingContext binds current RLS actor/shop/source and the actual live outer transaction. Typed immutable StockEffect and PayableAllocation are used by existing purchase receipt/reversal and supplier payment/reversal commands. They retain stock provenance/business dates, exact Decimal values, allocation totals, live payment status and original idempotency ledgers/hashes. Replay is resolved before adapters run. Native adoption continues linking previously uploaded stock instead of posting it twice.

JournalPostingPort defines a balanced immutable INR draft on the same connection. Requested journals without a port fail closed; journal failure or outer rollback rolls back associated stock/audit effects. E06 owns actual accounts, periods and source-idempotent journal storage. No journal implementation, historical repricing or automatic background financial posting is claimed.

## Acceptance

PostgreSQL same-token races, legacy writer/read coordination, independent tenant scopes, migration/retention/RLS checks, rejected-sync rollback, posting/journal rollback and ended transaction guards pass. Mobile stale editor/second-write failure tests and the full mobile suite pass. Real browser settings stale/review/rebase, emulator premium restore and final production Docker checks pass; exact revisions/results are in the evidence.
