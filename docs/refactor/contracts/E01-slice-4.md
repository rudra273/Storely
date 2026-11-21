# E01 slice 4 — capabilities, product revisions and durable jobs

19 November 2026. Status: verified implementation; [execution evidence](../evidence/E01/slice-4.md). The slice adds reusable foundations through existing product and inventory-report paths. It does not declare universal command or accounting migration complete.

## Shared capability contract

Authenticated current members may GET `/v1/shops/{shop}/capabilities`, including unpaid shops. Contract version 1 returns exact shop identity, current role and implemented feature versions: operation_lookup 1, supplier_payment_proof 1, supplier_payment_binding 2, product_expected_updated_at 1. Metadata grants no command permission. Actual mutations/recovery retain current tenant, premium and role checks. Missing old-server route is distinct from tenant-concealing not_found; malformed/unsupported contracts cannot silently authorize writes. Mobile negotiates fresh proof support; web negotiates guarded product editing.

## Product revision boundary

API product PATCH takes its existing optional expected_updated_at token and holds the actual product row lock from comparison through write/audit transaction. Two guarded edits based on one version cannot both succeed. Legacy writers omitting the token retain compatibility; this is not a replacement for legacy row-sync reconciliation.

Mobile catalog/bulk entry points pass the captured product revision into a SQLite transaction that checks current version, UUID and active shop before any master/stock change. Web full/inline editors freeze original fields and token together. A refetch cannot silently advance the baseline; conflict preserves entered values, and explicit latest review reapplies only locally changed fields. Full mobile/web conflict UX parity and settings aggregate revisions remain later work.

## Durable job/outbox primitive

Migration 0023 adds actor-owned session-bound work, transaction-compatible enqueue, stable request-key/work identity, persisted attempts/due times/leases, completion fencing, cancellation, bounded retry and expiry. A narrow dispatcher exposes due identifiers only; handlers run under actor RLS with current authorization. No credentials/provider payloads are stored. Runtime opts in; disabled producers return 503. Local Compose enables the worker; production must enable it explicitly. Custom app settings own the worker pool.

The concrete handler is stock_valuation_csv_v1, reusing the existing report/pricing/export calculation. Data is read at execution, not enqueue. Replaying a job preserves the original result bytes. DB-clock leases and final fencing prevent a cancelled/stale worker publishing an artifact; final session/account and role/entitlement checks prevent publication after observed authorization loss. Existing synchronous reports remain compatible. Queue enqueue can share an enclosing business transaction; rollback leaves no pending work. Financial commands have not been silently converted to this producer.

Limits: five active jobs per actor/shop, enqueue rate limit, five attempts, capped backoff, 10,000 report rows, 30-second DB statements, 5 MiB artifacts, 24-hour artifact expiry and bounded seven-day metadata cleanup. Byte checks follow encoding and are not a strict peak-memory budget. Future external providers require their own idempotency/receipts; calendar scheduling remains E14.

## Acceptance

Actual row-lock concurrency/negative control, current membership metadata, mobile stale-edit/proof compatibility, browser preserved-input/latest-review/rebase, PostgreSQL job rollback/lease/retry/fencing/cancel/revocation/retention, worker lifecycle tests, real dispatcher and API restart artifact recovery, emulator regression and production Docker checks are recorded in the evidence. General stock/payment/journal posting adapters and multirow settings revision semantics remain open E01 work.
