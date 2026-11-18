# E01 slice 1 — recovery and decimal boundaries

Status: implementation contract, version 1. User authorized next-phase implementation on 18 November 2026. This slice is part of E01; generic durable server jobs/posting infrastructure and aggregate migration remain separate prerequisites before later features consume them.

## Compatibility boundaries

No existing idempotency fingerprint is recomputed. Shared billing idempotency and purchase/supplier ledgers retain their existing hashes, keys and replay behavior. No historical invoice is repriced. No new universal transaction endpoint, ledger migration or sync replacement is introduced in this slice.

## API recovery lookup

Extend the current operation-status endpoint additively:

- Optional `operation_kind`: `idempotent_write`, `purchase_receipt`, `supplier_payment`. This identifies a storage family, not a claim that the underlying command kind was recorded.
- Omitted selector retains legacy search ordering and fields.
- Add `contract_version: 1`, matched `operation_kind` and nullable `result_kind`; unknown/shared historical result types stay null. Do not infer result type by matching UUID against business tables.
- Unknown enum is invalid input. Supplied selector searches only its family. An identical key in another family must never return that other result.
- Preserve membership, premium and role boundaries; querying a key cannot reveal tenant-private results or bypass command permissions. No credentials/actor supplied by the client are trusted.
- Tests exercise cross-family collisions, missing keys, backward-compatible callers and permission denial.

## Web durable invoice attempts

Persist exact request body and retry key synchronously before network send; verify storage/readback and detect a changed owner snapshot. Storage failure/conflicting tabs block send and show actionable recovery. After uncertain transport outcome, preserve frozen attempt across reload and retry. Do not expire uncertain attempts under the ordinary seven-day draft rule. Clearing a definitively rejected attempt must itself persist before unlocking edit state. Do not automatically treat timeout/key conflicts as definite failure.

Keep the existing explicit signout privacy policy; document that it clears browser drafts. This slice does not claim durable cross-device operation recovery after explicit signout. API typed lookup may aid recovery but is not an excuse to generate a fresh identity after timeout.

## Mobile exact decimal adapter

An internal reusable plain-decimal adapter accepts trimmed ASCII decimal text with optional minus and an optional fractional part. It rejects exponent notation, NaN/Infinity, plus prefix, separators, `.5`, and excess nonzero precision for an explicit scale. Trailing zeros beyond the scale are allowed if exact (`1.2300` at scale 2 → integer 123). Normalize negative zero. Use arbitrary-size integers; never round implicitly.

Integrate only where existing purchase normalization and supplier-payment cents can retain their wire/fingerprint output. Keep legacy num/double conversion boundaries readable; do not imply all mobile billing is decimal after this change. Caller validation still prohibits negative amounts where required.

Independent examples: `-0.00` → zero; `1.005` at scale 2 rejected; `1.2300` at scale 2 → 123; `900719925474.01` at scale 2 → 90071992547401. Existing explicit purchase line ROUND_HALF_UP remains a separate calculation rule, not parser rounding.

## Acceptance

API: meaningful lookup integration tests plus unit/lint; web: NewBill storage-failure/no-network-send, frozen retry/reload, conflict tests plus type/lint/build; mobile: exact parser and persisted payment-queue/reopen tests plus existing purchase vectors/analyzer. Root runs real localhost/emulator checks and records gaps. A completed slice does not close E01's unimplemented outbox/job/posting requirements.
