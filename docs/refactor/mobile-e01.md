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
