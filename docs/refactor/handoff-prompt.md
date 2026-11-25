# Storely continuation prompt

Resume the Storely end-to-end refactor from the existing local commits. Implement and verify the remaining work in the documented phase order. Preserve the existing web and Android UI, theme, navigation and checkout sequence. Align business rules, permissions, data, error recovery and results across clients. Preserve Android local-only operation. Hindi localization is deferred. I will personally run the final E18 flow and UX review.

## Workspace and checkpoint

| Repository | Path | Branch | Verified starting revision |
|---|---|---|---|
| Android and project docs | `/Users/rudra/projects/Storely` | `package-com-storely` | `ad75ae9` documents Android implementation `99403a5`. The handoff documentation commit is later. |
| API | `/Users/rudra/projects/storelyapi` | `dev` | `1c2c9ac` |
| Web | `/Users/rudra/projects/storelyweb` | `dev` | `9c8d3b7`, with generated API types in `4bcd74a` |
| Vyapar functional reference | `/Users/rudra/projects/vyapar-rea` | | Read-only fallback for observed flows and business rules. Start at `CLONE_SPEC.md`. |

Read applicable repo instructions and inspect `git status` and history in all three repos. The checkpoint commits were local and ahead of the remote branches when recorded. Use the existing checkouts or ensure any new environment has those commits. Preserve any newer user changes. An older remote checkout will miss completed work.

Start with `/Users/rudra/projects/Storely/refractor.md`, `implementation-plan.md`, `docs/refactor/feature-tracker.md`, and `refactor plan.md` in that repository. Use the tracker for scope and the evidence files for verified outcomes. E01 foundations are complete. E00 and E02 have verified milestones and open exit checks. E03 includes verified stock valuation, quantity and bank-transfer work, Android sale capture, API preflight and atomic posting, opt-in Android exact replay, and historical line snapshot verification. Keep these implementations and their compatibility guarantees.

## Start here

1. Implement **E03.2 reconciliation of reserved Android sales**, using `docs/refactor/contracts/E03-atomic-sale-sync.md`. Trace existing sync status, local reservation data, API operation lookup and invoice detail before changing behavior. Cover stock shortages, historical snapshot mismatches, edits to a reserved invoice and a server commit with a lost response. Define what each actor can safely inspect, retry or resolve. Use the existing sync/status surfaces where possible.
2. Preserve the original issued invoice, frozen body, operation key and reservation across retries, restart and account/shop changes. A timeout or incomplete acknowledgement must never release financial rows into legacy sync. Verify exact invoice, item, payment and movement identities and a single ledger result. Any correction affecting an issued invoice needs explicit, auditable business semantics. Keep `STORELY_NATIVE_SALE_POSTING` off by default pending reconciliation and mixed-version upgrade/restore verification.
3. Close the outstanding E02 paired checkout sequence and phase-exit checks. This can run in parallel if code ownership and live test infrastructure are independent. Then continue E03 payment, cancellation and credit-note commands and other open E03 items. Follow the remaining E04–E17 dependencies in the implementation plan.

Useful starting files are Android `lib/db/database_native_sales.dart`, `lib/models/native_sale_posting.dart`, `lib/services/sync/cloud_sync_engine.dart`, and `integration_test/native_sale_sync_test.dart`. On the API side start with `app/routers/bills.py`, `app/domains/billing/billing.py`, and the native sale tests. Web consumes the generated schema and should only change where the slice needs it.

## Working and verification

Use up to three subagents plus the coordinator when useful. Freeze a small contract first. Assign one writer per file or repo lane, and have the coordinator own Docker, emulator and shared fixtures. Run API `make openapi` before web `make api-types` when the schema changes. Commit each verified feature and update the tracker and evidence. Preserve disposable fixture cleanup and keep credentials outside version control.

Run focused tests, then relevant Docker API integration, localhost browser and Android emulator scenarios for the affected paths. Exercise reuse of the same key after a lost response, stale catalog, role changes and mixed versions, as relevant. Use the runbook in `implementation-plan.md` and explicit emulator IDs and disposable shops. Record exact revisions, pass/fail/skip results and follow-up work. The last snapshot checkpoint passed 605 Flutter tests, 119 focused opt-in tests, 435 API integration tests, 420 API unit tests, 688 web tests, localhost TLS and the Android emulator. Those results apply to the checkpoint; rerun affected scenarios on new changes.

At E17, prepare the verified local web and emulator builds, shared review data, and a walkthrough checklist. Leave E18 human approval to me. Production deployment requires my separate authorization.
