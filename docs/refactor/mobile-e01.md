# Mobile E01 slice 1 — exact decimal boundaries

Date: 18 November 2026. Contract: `docs/refactor/contracts/E01-slice-1.md`, version 1. Scope: E01.3 exact decimal/string adapter and existing purchase/supplier boundaries. This slice does not complete E01's durable command/outbox and posting requirements.

## Change and compatibility

Added `lib/utils/decimal_text.dart`: exact parsing/normalization/formatting with explicit scale and arbitrary-size BigInt. It accepts trimmed ASCII plain decimal text with optional minus, rejects exponent/plus/grouping/nonfinite/malformed values, allows insignificant trailing zeros beyond the scale, and rejects inexact input rather than rounding. Negative zero canonicalizes to zero. Fixed formatting retains the requested scale.

The adapter is used by purchase normalization, exact purchase line calculations and supplier accounting/payment queue cents parsing. Legacy purchase normalization retains its original unsigned, untrimmed, maximum-four-place grammar; supplier payment entry retains its unsigned 12-whole-digit and two-fractional-place validation. Existing `purchaseDecimal(num)` remains the compatibility boundary for double-valued models. No existing wire shape, operation key, fingerprint, database schema or historical snapshot changes. Purchase line rounding remains the existing explicit HALF_UP calculation.

The new helper handles signed decimal boundaries for future commands; caller business rules continue to reject negative purchases/payments. This does not claim all mobile billing uses exact decimal arithmetic.

## Verified behavior

- Edge vectors include `9007199254740993.01` without binary conversion, `-0.00`, outer whitespace, leading zeros, exact `1.2300` at scale 2, rejected `.5`, rejected `1.005` at scale 2, and signed sub-unit formatting.
- Large supplier payment `900719925474.01` persists with the same exact payload over SQLite close/reopen. Outstanding `900719925474.02` less that pending payment is exactly `0.01`.
- Rejected supplier sync restores the exact full outstanding amount and records a conflict. Existing lost-acknowledgement tests continue proving one payment identity after replay.
- Invalid negative, rounded, exponent, whitespace and zero payment inputs do not create queue records. Legacy purchase normalization validation is preserved.

## Checks

- `flutter analyze`: passed, no issues.
- `flutter test test/decimal_text_test.dart test/purchase_documents_test.dart test/purchase_composer_draft_test.dart test/purchase_api_sync_backend_test.dart test/purchase_import_review_test.dart`: 41 passed, exit 0.
- `flutter test test/billing_vectors_test.dart`: 1 passed, exit 0.
- `git diff --check`: passed.

Raw local logs: `/tmp/storely-mobile-e01-analyze.log`, `/tmp/storely-mobile-e01-tests.log`, `/tmp/storely-mobile-e01-vectors.log`. No emulator, Docker service or production data was used by this lane. Parent coordinator owns combined localhost/emulator acceptance and phase completion.

## Remaining E01 work

Generic command envelope/revision negotiation, local durable command state and aggregate sales sync, provider-job infrastructure and posting adapters remain separate work. No new UI or flow behavior was introduced here.

# E01 slice 2 — durable supplier-payment send state

## Observed gap and bounded implementation

The supplier-payment queue already preserved request keys and exact bodies, but a transport failure left the payment indistinguishable from a never-sent request. A process stop after send also had no durable marker. SQLite v26 adds local `command_state`, `attempt_count` and `last_attempt_at` metadata while preserving the legacy `sync_state`, exact payload, request key and API wire shape.

- New queued payment: `ready`; a conditional SQLite claim persists `sending` and increments attempt metadata before network dispatch. A competing sender cannot claim the same request while sending.
- Accepted response: `accepted` plus legacy `synced` and returned payment UUID.
- First-attempt proven rejection: `rejected` plus legacy `error`; first-attempt identity conflict: `conflict` with legacy `pending`, retaining its local reservation and requiring review rather than automatic retry.
- Transport/acknowledgement uncertainty: `unknown` with legacy `pending`, retaining body/key and reservation. A denied replay after an unknown response remains unknown; permission denial cannot establish that the earlier attempt did not commit.
- After database reopen (including restoring a backup), an interrupted `sending` becomes `unknown`. Recovery occurs only once per database open, outside in-process send iteration.
- Callbacks and claims constrain the captured original shop, rather than reading the possibly changed active shop when acknowledgement arrives.

The additive v26 migration maps legacy pending rows to **unknown** because old pending may already represent a lost acknowledgement; acknowledged/error/local rows map to accepted/rejected/local. Existing legacy error history cannot reconstruct uncertainty that older versions already discarded. No row is rekeyed or resubmitted with a new identity by migration.

`SyncRowRejected.isConflict` is optional and defaults false, preserving existing row-sync call sites. Only the supplier-payment API adapter adds HTTP409 conflict metadata. This is not a new wire field.

## Provisional accounting limitation

Unknown/conflict requests continue reserving their amounts so a user cannot issue unsafe new payments after a lost acknowledgement or revoked access. If the receipt feed already includes the server payment but no response UUID was acknowledged, the existing snapshot contract cannot identify which queued request it matches. The provisional local balance may therefore understate the available payable amount until an authorized replay resolves identity. The adapter does not guess by amount or release the reservation. Confirmed accounting and recovery via typed lookup across all denial states remain future work; no new UI/confirmed-balance claim is made here.

## Verification

- Analyzer: no issues.
- Focused purchase-document, purchase API adapter, v16 upgrade and backup suites: **36 passed**.
- Final conservative v25 pending→unknown migration regression: **1 passed** after the broader run.
- Tests cover duplicate claims, sending→restart→unknown, immutable exact payload, lost acknowledgement followed by denied retry, no unsafe new payment, recovery to one server payment, terminal rejection/conflict behavior and wrong-shop acknowledgement refusal.
- Actual SQLite backup/restore preserves pending identity/attempt metadata and recovers interrupted sending to unknown.
- Contract field inventory classified the new fields as local-only; parent coordinator regenerates/reviews both fixture copies before combined contract acceptance.

Logs: `/tmp/storely-mobile-e01-state-tests.log`, `/tmp/storely-mobile-e01-state-analyze.log`, `/tmp/storely-mobile-e01-v26-migration.log`. No emulator or shared Docker service was used by this lane. Parent owns the premium emulator regression and overall E01 status.
