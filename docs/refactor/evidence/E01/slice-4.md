# E01 slice 4 — capabilities, guarded edits and durable jobs

19 November 2026. [Frozen scope](../../contracts/E01-slice-4.md). API/mobile/web agents worked independently; the coordinator implemented durable jobs and completed final integration/commits after client-agent limits. Theme identity is preserved. E01 remains implementing.

## Implemented revisions

- API `f375038`: current-membership capability metadata and atomic product expected_updated_at comparison under the actual row lock. Held-row concurrency proves one success/one changed_elsewhere conflict and one audit. Negative control reproduces two stale successes without the lock. Capability metadata remains available to unpaid members without granting business access.
- API `bd1aa1f`: job route authorization matrix policies/cases. API `7838fed`: migration 0023, actor-owned durable enqueue, real inventory CSV handler, lifespan dispatcher, RLS, current authorization, database-clock leases/retries/fencing, cancellation, bounded artifacts/retention and opt-in worker configuration. No credentials or provider payloads persisted; no financial algorithm changed.
- Mobile `8d1dd73`: local catalog/bulk edits check captured revision, UUID and active shop in the SQLite transaction before writes/stock changes. Mobile `cef50e0`: fresh per-call capability negotiation for supplier proof, strict identity/version parsing and explicit legacy fallback. Feature metadata is not an authorization cache.
- Web `b6fc182`: frozen full/inline product edit baselines, current capability check, preserved input on conflict and explicit latest review/dirty-only rebase. Background refetch cannot silently change the editing token. Generated types include capabilities and the job API/CSV artifact metadata.

## Validation

API: 54 agent capability/catalog integration tests and 317 initial unit tests passed; coordinator's expanded suite passed **319 unit tests** and **352 full PostgreSQL integration tests**. After final DB-clock/download-metadata refinements, **21 focused job/capability/authorization tests** passed. Final Ruff/format/mypy/security checks passed (170 formatted files; 151 typed source files). Existing duplicate health OpenAPI operation-ID warning remains.

Jobs cover transaction enqueue rollback, duplicate producers/workers, immutable actor-private artifacts, interrupted worker/fresh-pool lease recovery, retry timing and safe diagnostics, revoked session/disabled account/role/premium, in-flight cancellation/session revocation/new-fence races, expiry/attempt budgets, disabled producer, quotas, output cap and retention. Lifespan unit tests prevent unintended default-DB dispatch and verify pool disposal. Dispatcher validates restricted runtime role and verified DB TLS before work.

Mobile: **30 catalog/draft focused tests** and **60 capability/proof/sync focused tests** passed, analyzer clean (sets may overlap; no invented unique total). Actual API 35 emulator `make test-device-premium DEVICE=emulator-5554` passed exit 0: activation, all-table clean restore and two-device/web roundtrip (1 scenario). Screenshot pull 268,559 bytes; review artifact `/tmp/storely-e01-slice4-artifacts/premium-activated.png`. Emulator broad regression does not replace focused stale-edit/contract tests.

Web: coordinator reran **391 tests / 42 files**, typecheck, lint and production build, all pass. Final generated-type regeneration/typecheck passed after CSV schema correction. Actual localhost `e2e/product-revision.cjs` passed inline/full stale rejection, retained values, explicit dirty-only rebase and preservation of remote fields. Existing large-bundle warning remains (about 781 KB).

Live backend: isolated premium fixture queued stock_valuation_csv_v1 through the local TLS API. The running dispatcher produced byte-identical CSV to the existing synchronous report, with one attempt and stable job identity on duplicate enqueue. Artifact/identity stayed stable across an actual API process restart. Fresh dispatch after the runtime-role/TLS gate also passed. The initial disabled-worker 503 was configuration setup, correctly accepted no job; enabling local Compose resolved it. An initial assumed CSV header assertion was corrected to byte equality/BOM; it was not a production report defect.

Final production Docker `make test-platform` passed exit 0 on committed implementation, with worker opt-in enabled in the isolated runtime. Bootstrap/migrations through 0023/repeat deployment, verified DB TLS, runtime-role restrictions, proxy/deep links/API errors/cache/security headers/missing assets passed. API image `70ff426af6fd49f06afbfbfc1108dc748f54352425eb0571548098e7eb21bd9c`; web image `523767269bf0068c031e10264a8e0d22c742c9655fc9bda4c39be87bfbe26679`. No deployment or push.

## Cleanup and practical boundaries

Browser/job acceptance used only a fresh synthetic premium shop/product. Normal owner API cleanup removed exact run-owned shop/jobs/account/mail; credential files were deleted. Tracked historical screenshot restored after copying the new artifact. Other shops were untouched.

The worker defaults off outside local Compose; production must opt in, and disabled producers return 503. Reports read data at execution time, not an enqueue-time snapshot. Five attempts/active-job quota, rate limiting, 10,000 product cap, 30-second DB statements, 5 MiB artifact cap and expiry bound processing; output size is checked after encoding and is not a strict peak-memory guarantee. Queue/outbox enqueue is transaction-compatible, but existing financial commands were not silently converted to background work. External delivery still needs provider-specific dedup/receipts; scheduling remains E14.

## Next E01 work

Shared stock/payment/journal posting adapters and aggregate settings revision semantics remain open. A settings snapshot spans multiple rows and legacy sync writers, so a REST-only advisory lock is insufficient. Legacy writers omitting product revision remain compatible; broad row-sync/financial aggregate replacement is not completed. Full mobile/web conflict UX parity and general recoverable draft flows remain E02; final human flow/UX acceptance remains E18. No claim that all E01 or flow parity is finished.
