# E01 execution evidence

Latest: [slice 2 posting, payment attempts and browser ownership](slice-2.md). The slice 1 results below remain historical evidence; E01 is still implementing.

18 November 2026. Coordinator + API/mobile/web agents. Scope contract: `../../contracts/E01-slice-1.md`. This is an incremental E01 slice, not completion of all command/outbox/posting foundations.

## Verified repo work

- API `305eb01`: additive ledger-family recovery selection and truthful versioned metadata. Existing operation hashes/fields and omitted-selector lookup priority preserved. 317 unit tests, 16 targeted integration tests, lint/type/security checks passed. Same-key records across three ledgers and current role/tenant/premium checks exercised.
- Mobile `552eed9`: exact BigInt decimal boundaries integrated into existing purchase and supplier-payment paths; no schema/wire/historical snapshot change. Analyzer clean; 41 focused tests and billing-vector test passed. Large persisted payment, reopen/rejection and malformed input covered.
- Web: durable pre-send invoice attempt storage and recovery passed real localhost smoke: blocked storage produced no invoice POST; committed/lost-response recovery retried the identical body/key after reload; stock decreased once. Web commit `e50b8ce`; 363 tests across 40 files, typecheck/lint/build, generated types, script syntax and diff checks passed.

## Integration/environment work

- API `make openapi` exported current schema for web generation; duplicate health operation-ID warning remains.
- Isolated `make test-platform`: passed, exit 0. Built API image `e8008e4169ac5140a50627a5be220f18d2eda1e38beab8b1ccd57496213db385`; web platform image `e40a0ad41396e60ef87f77c94f493b7a58eff56bd904feef824a7a9bff25667b`. Bootstrap, repeated migrations, TLS database, proxy/deep links, missing assets, and full static security headers/CSP assertions passed. Root committed enhanced test as API `618d467`. Web image records an intermediate stable source snapshot; final web source regression is recorded separately.
- First production build attempt read a changing web working tree and failed build; stable-snapshot rerun above passed. Do not count the first attempt as passing.
- Run-owned local synthetic premium fixture created for browser test (UUID b9ac352d-0f3d-4b10-ad80-39bfd2de362a); credential files live only under /tmp. Existing user shops unaffected. Exact-ID cleanup completed after browser pass: synthetic shop/account/mail removed and /tmp credential files deleted.
- `make test-device-premium DEVICE=emulator-5554`: passed end-to-end, exit 0, actual API 35 emulator. Activation/upload/all-table restore/two-device-web roundtrip passed (1 test); screenshot collection succeeded (264,087 bytes). Generated screenshot copied to `/tmp/storely-e01-artifacts/premium-activated.png`; tracked historical screenshot restored to avoid unrelated binary churn. Browser live run serialized after its API-restart window.

## Remaining gates

Premium emulator wrapper, real localhost recovery scenario, generated web schema and exact synthetic-fixture cleanup all verified. Final repo revisions for the slice: mobile `552eed9`, API `618d467` (includes recovery `305eb01`), web `e50b8ce`. Generic durable server jobs, complete local command outbox/state, expected-revision negotiation and posting interface remain future E01 slices. E00 broad legacy browser modernization and full scenario manifest expansion remain visible; this additive slice does not replace financial sync or depend on an assumed green old browser suite.

## Slice acceptance and remaining work

The recovery/decimal slice has API integration, mobile persistence/vector tests, real premium emulator regression, real localhost invoice lost-response recovery, and isolated Docker production checks. E01 as a whole remains **implementing**: generic durable server job/outbox, local command-state integration, revision negotiation, and posting interface are not implemented by these changes. E00 static security acceptance now has a passing isolated production test; the old broad browser harness remains a separately tracked gap.

## Practical limits retained

Browser storage uses compare/write/readback conflict detection, not atomic cross-tab compare-and-swap; truly simultaneous multi-tab ownership still needs a later ownership/lease design. Explicit signout retains the existing privacy policy of clearing browser drafts. The typed API selector names ledger families; legacy shared-ledger result type remains unknown rather than inferred. These limits are documented in lane reports and do not justify claiming complete command/outbox or cross-device recovery.
