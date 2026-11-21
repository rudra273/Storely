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

## Slice 3 — exact-attempt recovery proof (19 November 2026)

Unknown supplier-payment attempts can use the optional authenticated exact-body recovery endpoint before replay. A committed proof records the verified UUID without another payment POST; not-found retries the original request. This removes the temporary double reservation once the matching payment is known. The key-only lookup is not accepted as body equivalence.

The adapter validates contract/version/nullability and rejects malformed responses. Permission/network/conflicting intent retain unknown state and the reservation. Older servers lacking the endpoint allow exact unselected legacy replay; a restored selected-purchase attempt fails closed when target binding cannot be verified. Saved queue/body key mismatch prevents dispatch. Backends without this optional capability remain compatible.

Final coordinator check: analyzer clean; 42 tests passed across purchase API parsing, durable purchase/payment recovery, backup and database upgrades. Real-device broad premium regression is recorded centrally; these focused tests exercise the new proof states explicitly. No SQLite schema or money algorithm changed in this slice.

# E01 slice 4 — guarded local catalog edits

Date: 19 November 2026. The existing mobile purchase draft path already performs revision-checked save/discard/post. Catalog editing did not: `updateProduct` reloaded current stock but unconditionally wrote the editor's older master/quantity snapshot, potentially creating a stale stock-count adjustment.

Added an optional `expectedUpdatedAt` local precondition and wired the catalog editor and bulk-edit entry points to their original loaded timestamp. Guarded writes check the original UUID, active tenant and equal timestamp instant before preparing any rows or stock movements. Rejection uses the existing error handling, so fields/selection remain available for review; no layout or theme change. Existing programmatic callers remain compatible, and no sync wire/schema token is added by this local guard.

Focused inventory + purchase-draft regression: **30 passed**. Cases verify stale edit cannot overwrite the newer name/stock or add a movement; current timestamp in another timezone is accepted; foreign-tenant source is refused; existing purchase-draft conflicts remain safe. Analyzer: clean, no issues. This guard does not claim optimistic concurrency across disconnected devices; server row-sync compatibility remains unchanged.

## Fresh service capability negotiation

Added `ServerCapabilities.load` against the frozen membership-only `/v1/shops/{shop}/capabilities` contract. Supplier-payment proof recovery fetches it afresh for each proof attempt; it does not cache role/access or authorize business commands. It validates response version, requested tenant identity, known role shape and nonnegative integer feature versions. Current command endpoints still enforce current membership, role and premium status.

A missing old capability route/method (`http_404`/`http_405`) preserves the existing exact-body proof probe. Explicit proof feature version zero/absent returns unsupported and therefore uses the existing safe fallback policy (including fail-closed selected-target guards). Future/invalid proof versions, malformed metadata, tenant mismatch and access/network errors fail closed and retain unknown payment work through the existing queue state handling. A changed account during the metadata request is refused.

Verification: **60 focused tests passed** across purchase API transport, durable purchase/payment queue and API sync backend; analyzer clean. New tests cover fresh support→unsupported transitions, feature metadata not granting staff permission, malformed/future/cross-tenant responses, denied auth/refresh, network failures and no business dispatch after failed negotiation. Old capability-route fallback remains covered by existing recovery-proof transport tests. No schema, theme, offline/free behavior or sync wire changes.

# E01 slice 5 — guarded settings and atomic invoice-editor saves

Date: 19 November 2026. Found two local gaps: the invoice editor saved `bill_settings` and invoice-series configuration in separate transactions, and profile/pricing editors did not compare a frozen persisted baseline. Profile/pricing sheets also closed before persistence, making a failed save lose the visible form.

## Implementation

- `SettingsEditBaseline` captures canonical persisted configuration rows from the actual current shop. It is in memory only, never row-synced or uploaded as configuration data. Keys/row representations are sorted deterministically. Runtime invoice counters, device/transport flags and bookkeeping timestamps are excluded so ordinary billing/sync does not create false conflicts.
- Guarded writes compare that baseline and tenant identity inside the SQLite transaction before any settings mutation. Existing programmatic callers retain optional-baseline compatibility; this is not a replacement for server sync revision enforcement.
- The actual invoice editor captures its baseline before loading fields and commits bill appearance plus default invoice-series configuration in one transaction. A later-write failure rolls back the first write and all associated local dirty flags.
- Shop/profile and global-pricing sheets persist under their frozen baseline before closing. A conflict leaves existing fields visible. Async Store-screen refresh can replace surrounding view data without replacing the sheet's frozen baseline.
- The standalone pricing editor receives its next baseline from the same transaction that saved its settings, avoiding a post-save recapture race. Its text controllers remain intact on failure.
- No schema, wire, theme or navigation changes. Settings mutation rights still use the existing authoritative local mutation guard, including free/offline operation. Product selling-price recomputation remains the existing separate derived refresh; the new atomic claim is for the settings rows, not a new all-product repricing transaction.

## Verification

`flutter test test/settings_concurrency_test.dart test/pricing_test.dart test/billing_database_test.dart test/invoice_v2_test.dart`: **46 passed**. `flutter analyze`: clean, no issues. `git diff --check`: passed.

Cases include a sync-style concurrent settings update, stale profile/pricing rejection, same-transaction follow-up pricing baseline, invoice counter/transport-only updates, revoked edit rights, changed shop identity, and an injected failure on the second invoice-series write proving full rollback. A real BillSettingsScreen widget test edits its title, changes persisted settings concurrently, attempts Save and verifies the route stays open, typed title is retained and persisted title is unchanged.

The widget harness initially targeted the preview scroller and attempted settling an active loading spinner; bounded async pumping and selecting the actual vertical settings list fixed the harness. The final run above is the passing evidence. Logs: `/tmp/storely-mobile-e01-settings-tests.log`, `/tmp/storely-mobile-e01-settings-analyze.log`. No emulator or live Docker access was used by this lane; coordinator owns integrated acceptance.
