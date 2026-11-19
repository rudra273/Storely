# E01 slice 5 — aggregate settings and posting interface

19 November 2026. [Contract](../../contracts/E01-slice-5.md). Three repository agents implemented settings paths; coordinator extracted shared posting, finished verification and committed after agent limits. The source comparison/reference audit remains unchanged; no theme redesign or production deployment.

## Revisions and behavior

- API `9b0a485`: migration 0024, trigger-owned aggregate revision metadata, coherent invoice-settings GET, optional guarded PATCH/409 settings_changed, capability settings_revision 1 and coordinated sync writes. Statement locks precede tenant row/entitlement locks, legacy SQL has a global fallback, meaningful row changes bump counters, and current public sync columns stay compatible.
- API `b67be7c`: production-used typed stock/payable effects and a transaction-bound future journal port. Existing purchase/reversal/payment paths retain source UUIDs, business dates, amounts, stock costing, hashes and replay behavior. Invalid floats/non-finite/unbalanced values fail closed. A requested missing/failing journal adapter cannot silently succeed; E06 still owns the actual ledger.
- Mobile `f7465d2`: frozen persisted settings baseline, local stale/tenant/permission guards, save-before-close profile/pricing sheets and atomic invoice layout+default-series save. Runtime invoice counters are preserved and ignored for conflict purposes; no new SQLite/cloud fields.
- Web `634dfd2`: frozen settings snapshot/token, guard capability check, sparse fields/show diffs, preserved input on conflict, explicit latest review and dirty-only rebase. Existing tabs, preview/theme and unrelated remote edits are retained. Generated API types and real browser harness included.

## Verification

API full PostgreSQL integration: **364 passed**. Final unit suite: **331 passed**. After the final explicit payment-total float guard, the focused posting/purchase/payment/reversal/settings suite passed **35 tests**. Final lint/format/mypy/security passed (178 formatted files; 157 typed source files). Existing duplicate health OpenAPI operation-ID warning remains.

Settings races hold real coordinator locks, proving one same-token writer wins; current legacy profile/app/layout sync invalidates stale REST views; clock-only changes preserve tokens; scoped tenants remain independent; context-free legacy writes and coherent GET complete without the tested deadlocks. Counter RLS/tamper/tenant checks, repeated migration and rejected-row savepoint rollback are exercised. An initial added test assumed two active layouts; the existing unique active-shop index correctly refused it. The final test preserves that invariant and verifies rejected sync changes no snapshot/token. No database uniqueness rule was weakened.

Posting tests cover immutable/protected provenance, exact money, current actor/source, live transaction binding, missing journal adapter, successful/failing journal port rollback, original payment identity on replay, allocations and live reversal balances. Existing financial snapshots/calculations are not regenerated or repriced.

Mobile: agent 46 focused settings/pricing/billing/invoice tests and analyzer pass. Coordinator full `flutter test`: **339 passed, 17 opt-in live tests skipped**, exit 0. Actual API 35 emulator premium activation/all-table clean restore/two-device-web roundtrip passed exit 0 (1 scenario). Screenshot pull 266,863 bytes; artifact `/tmp/storely-e01-slice5-artifacts/premium-activated.png`. The broad emulator regression supplements the explicit local stale/atomicity tests; it does not claim every new editor conflict was manually exercised on-device.

Web: **410 tests / 43 files**, typecheck, lint and production build pass. Real current-source localhost `e2e/settings-revision.cjs` passed: concurrent remote footer/phone/show changes cause stale refusal; local text is kept; explicit review rebases only local footer/show keys; unrelated phone/show changes survive. The final PATCH is asserted exactly, including reviewed opaque revision. Existing bundle-size warning remains (about 785 KB).

Final production Docker `make test-platform` passed exit 0 on committed source: migrations through 0024, repeat deployment, restricted verified-TLS runtime, proxy/deep links/API errors/cache/security headers and missing assets. API image `8af98cc24a4333ff6e70eaaf7cd536a8bc1d84bbb6508b314715ee2dd4bdaa34`; web image `e1736f3e2941b0b6fdc8223459ec503d81038a64687695bfa21265ed3a799d50`. No push or deployment.

## Fixture and rollout integrity

Browser used a fresh synthetic premium shop. Exact-ID owner API cleanup removed its shop/account/mail; private credential files were deleted. Historical tracked screenshot restored after copying the review artifact. Final idempotent 0024 SQL was reapplied locally after provisional development trigger changes; counters were preserved. No user-owned shop was removed.

Modern sync/API writers use the new scope helpers. Context-free SQL serializes settings globally; arbitrary old server transactions with previously held locks still require coordinated rollout. Legacy callers omitting a revision retain legacy semantics; new web settings fail closed without support. Other domain settings readers were not globally converted to coherent editor snapshot reads. Local derived product repricing is still a separate preexisting operation. Real accounting/journal storage remains E06 and complete flow parity remains E02.

## E01 closing gate

The previously listed settings and posting implementation areas are now delivered. Before marking all E01 complete, consolidate and audit shared command/default/precision/capability decisions and independent expected-value fixture coverage against the phase checklist. The old universal-command design remains a proposal, not an implemented replacement endpoint. This is a coordinator acceptance audit, not a request for early human approval. Human flow/UX acceptance remains E18.
