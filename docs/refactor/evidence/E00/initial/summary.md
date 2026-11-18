# E00 initial execution evidence

Started 18 November 2026 (Asia/Kolkata). User authorized parallel implementation and commits after completed features. Coordinator plus API, mobile and web workers use one writer per repo/path. Existing mobile branch `package-com-storely`; API/web `dev`. All working trees were clean at dispatch. Plans were already committed in mobile `eb219e6`; API `8663a09`; web `6de0488`.

## Environment observations

- Docker API, PostgreSQL 18, mailpit, TLS proxy and web were healthy; containers were created about two weeks earlier. Running image identity must not be assumed equal to source.
- Flutter, ADB and an existing `storely_pixel` Android API 35 AVD available. Coordinator booted the AVD without wiping data, `-no-snapshot-save`; `emulator-5554` boot property is 1.
- Default sandbox could not access Docker socket or start ADB; approved escalated access succeeded. This is not a missing tool or application defect.
- `make verify`: **failed (exit 2)**. API trusted TLS, rejection of invalid certificates/old TLS, redirects, API security headers, same-origin API routing, and database transport/role checks passed. Web security-header/CSP checks failed. Investigating whether dev Vite or stale runtime configuration explains this. Do not describe the overall TLS gate as passed.

## Current execution state

E00 is in progress. Repo checks and repairs are recorded in the individual worker reports. No phase is agent-verified yet. Localhost browser acceptance is pending. Initial emulator run completed: 3 security/Keystore cases passed; first case failed because the legacy harness expects free-shop sync success. Mobile worker is correcting that obsolete expectation; this does not prove paid sync. No business-data fixture reset or production action was performed.

## Next gates

1. Finish repo baselines and commit narrowly verified repairs.
2. Confirm current-source localhost browser runtime and reconcile web header checks.
3. Run serialized device CloudService and cross-client baseline against the current stack.
4. Freeze E01 command/workflow/decimal contracts using existing atomic purchase patterns.

## First device run

`make test-device DEVICE=emulator-5554`: exit 2. Debug APK built and installed. First scenario expected no sync error after free registration but received the intended subscription-free pause. Refresh token/Keystore persistence, untrusted CA refusal and HTTP refusal passed. Raw local log: `/tmp/storely-e00-device.log` (not committed). Follow-up rerun required after the scoped harness repair.

## Repo baseline results so far

- Mobile commit `6103632`: analyzer clean; 309 unit/widget tests passed; 17 opt-in live tests skipped.
- Web: typecheck/lint/build and 352 tests reported passed by lane; actual browser smoke pending.
- API: request-ID and product-edit baseline repairs in progress; 317 unit tests and lint/type checks reported passed; scratch integration pending.

Web TLS failures are explained by the active development Vite service bypassing static Caddy headers. This is a development-stack observation; built-image verification remains required before claiming the full header gate passes.

## Verified commits and coordinator follow-up

- Web `956a32b`: current-source localhost onboarding smoke passed; account/mail cleanup succeeded.
- Mobile `c4f3e8c`: corrected free registration test; actual emulator rerun **4 passed**, exit 0.
- API `e58b074`: unhandled error headers fix; `7279758`: product PATCH repair and baseline type/lint fixes. Unit gate 317 passed; targeted audit/product integration 36 passed; final lint/type/security command exit 0.
- Broad integration run is being captured separately; E00 remains implementing. Built-static headers and paid cross-client restore/roundtrip still outstanding.
- Parallel workers reached their usage limit; coordinator reviewed pending patches, corrected new decimal/paper-size test assumptions, reran focused checks and made the commits.

The command-foundation contract remains a draft. No E01 business-command implementation or full refactor completion is claimed.

## Full integration diagnosis

First complete API baseline: 322 passed, 6 failed (328 selected). Five failures shared a purchase-register SQL query referencing nonexistent `purchase_documents.deleted_at`; the receipt schema uses reversal state and the query already excludes reversed documents. Removed the invalid join predicate, preserving movement tombstones and reversed-document filtering. The sixth failure proved business audit events bypassed paid access; restored the standard admin+premium guard while leaving the separate security-event recovery route available. Full rerun and lint results recorded next.

## API integration repaired and verified

`make test-integration` full rerun: **328 passed**, 317 deselected, exit 0 (existing duplicate health OpenAPI operation-ID warning). `make lint`: passed, exit 0. Committed report/access repairs as API `87d35f4`. Unit baseline 317 passed remains separately recorded. Premium device activation/restore roundtrip is now running; no pass claimed until completion.

## Premium device outcome

Actual premium scenario passed (1 test): activation, upload, all-table clean restore and two-device/web roundtrip. Original wrapper exited 2 after the test because screenshot collection used obsolete Android package `com.rudra.storely`. Current application ID is `com.storely`; corrected script path, `bash -n` passed, and the exact corrected ADB pull succeeded (264,523-byte PNG at `/tmp/storely-e00-artifacts/premium-activated.png`). The original wrapper is not reported as a zero-exit run. Temporary reviewer removed successfully.

Current E00 outstanding work: built-static Docker/header acceptance, broad browser harness modernization, schema consistency and remaining reproducible scenario fixtures. Paid device roundtrip is now evidenced; no human UX acceptance or full E01 completion claimed.
