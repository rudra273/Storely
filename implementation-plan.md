# Storely refactor — implementation and verification plan

**Date:** 18 November 2026. **Status:** planned; implementation and test runs have not started under this plan.

**Scope:** `/Users/rudra/projects/Storely` (mobile), `/Users/rudra/projects/storelyweb` (web), `/Users/rudra/projects/storelyapi` (API). Preserve the current UI/theme and existing local-only mobile operation. Deliver matching business workflows across mobile and web, including validation, calculations, permissions, results and recovery. Final flow/UX acceptance belongs to the user.

## 1. How to use this plan

Read [refractor.md](refractor.md) first. The preserved [comparison](<refactor plan.md>) explains what exists, what differs and what is missing. [Feature tracker](docs/refactor/feature-tracker.md) assigns all 145 comparison rows to execution phases. The [Vyapar reference](../vyapar-rea/CLONE_SPEC.md) remains the fallback for functional questions; do not implement guesses from a screen name or UNKNOWN entry.

This document governs the implementation order. Its **E00–E18** identifiers are deliberately distinct from the comparison's broader **P0–P10** groups. Each E phase ends with tested, integrated work across the affected repositories. Do not implement all backend changes first and postpone mobile/web integration until the end.

This turn creates work plans only. After implementation is authorized, the coordinator carries approved work through implementation, automated verification, repairs and evidence collection without repeatedly requesting permission for ordinary engineering steps. Do not interpret this plan as authorization to merge into production, spend on external providers or mark human UX acceptance passed. Existing repository verification requirements are satisfied by investigating each slice before changing it and using the already-authorized scope; genuinely unresolved product decisions remain explicit.

### Completion states

`planned → contract-ready → implementing → repo-tested → integrated → agent-verified → ready-for-human → accepted`

Use `blocked` with a concrete prerequisite and next action; `failed` with a reproducible case; and `deferred` only with an explicit user scope decision. A skipped test, unavailable emulator/provider or stub-only integration is not a pass. The initial feature tracker uses `planned` for execution work even when the comparison says the basic feature already exists.

A phase can proceed to its dependent phase after **agent-verified**; the user is not required to review every intermediate phase. The final E18 gate changes delivered scope to **accepted**. Fixes discovered in E18 return to the owning phase and then back through the relevant tests and human retest.

## 2. Parallel agent structure

Use **four active slots maximum**: coordinator plus three repo agents. This is the default topology for each implementation slice.

| Worker | Write ownership | Responsibility | Required handoff |
|---|---|---|---|
| Coordinator/integrator | Plan, tracker, cross-repo contracts/fixtures and integration evidence; shared environment control | Investigate scope, freeze contracts, allocate tasks, resolve dependencies, integrate, run real cross-client acceptance and review diffs | Phase report with exact revisions, tests, remaining risks and next ready tasks |
| API agent | `storelyapi/app`, migrations, API tests and API docs allocated for the slice | Domain rules, transactions, permissions, migrations, endpoints, sync acceptance, report projections | Endpoint/schema diff, migration/recovery notes, tests and known limitations |
| Mobile agent | `Storely/lib`, `test`, `integration_test` allocated for the slice | Local domain/persistence, offline command queue, workflow controllers, matching screens, device scenarios | Local migration notes, offline/retry behavior, test results and emulator scenario IDs |
| Web agent | `storelyweb/src`, `e2e`, web tests allocated for the slice | Same workflow/state sequence, generated client consumption, durable drafts, browser scenarios | Flow/field parity results, browser scenarios and build/test results |

No fourth subagent runs concurrently with all three repo agents. For independent review, finish/idle a lane, then reuse that slot as a reviewer. The coordinator remains responsible for integration even if an agent reports success.

### Safe parallelism rules

1. Freeze a small contract first: commands/DTOs, enum values, defaults, validation order, error codes, permissions, state machine, monetary fixtures, storage/sync versions and acceptance scenarios. Store it in `docs/refactor/contracts/<slice>.md` when implementation starts.
2. All three repo agents can then implement against that contract. Client mocks unblock development; they do **not** satisfy real API acceptance. Contract changes go back through the coordinator and all consumers before continuing.
3. Give each agent an explicit file/path allocation. One writer per shared file: API migration head, OpenAPI output, generated TypeScript schema, mobile schema/helper, shared fixtures, navigation registry and feature tracker. No agent reverts another agent's edits or runs broad formatting across unowned files.
4. The API agent owns schema semantics; the coordinator schedules `make openapi`, then the web agent runs `make api-types`. These commands write across repo boundaries; they are a serialized handoff, not independent background jobs.
5. Reuse suitable current checkouts. Follow the API repo's `dev` integration policy and avoid direct `main` commits. If isolation is necessary, create worktrees through the worktree tool and allocate them explicitly. Do not independently switch branches in a shared checkout. Use `codex/` names when new task branches are appropriate.
6. A worktree does not isolate Docker ports, containers, image tags, emulator data or fixed scratch databases. The coordinator owns those resources.
7. Repo-local pure tests may run in parallel when they do not write shared artifacts. Run live Docker/browser/emulator suites serially until the harness supports separate ports, project names, databases, volumes, images, run directories and emulator IDs.
8. Do not run `make reset`, `docker compose down -v`, blanket database cleanup or emulator wipe as routine test setup. Use identified disposable fixtures and preserve existing user/local data.
9. When one lane finishes, use it for review/test authoring within assigned paths; do not start a dependent feature that changes the unfinished contract.
10. Integration handoff records all three commit SHAs plus any dirty patch identifiers. A passing test against stale containers or an older APK is not evidence for current changes.

### Dispatch template for every subagent

```text
Slice: Exx.y / feature IDs / divergence IDs
Repo and exact writable files:
Contract and reference sections:
Depends on:
Implement:
Do not change:
Shared file/environment owner:
Required local tests:
Required integration scenario IDs (coordinator runs shared environment):
Return: changed files, contract deviations, test commands/results, remaining gaps,
        migration/recovery effects, and evidence locations.
```

## 3. Mandatory lifecycle inside every implementation slice

| Step | Work | Owner | Gate |
|---|---|---|---|
| A. Inspect | Trace existing code, reference evidence and affected data; reproduce the reported difference where possible | Coordinator + relevant repo agent | Existing behavior and intended result documented; no duplicate implementation |
| B. Specify | Freeze workflow/field/state/API/math/migration contracts and scenario IDs | Coordinator with agents | Contract-ready; decisions and unknowns explicit |
| C. Implement in parallel | API/domain + mobile/offline + web/workflow, each with focused tests | Three repo agents | Repo-tested with no unresolved contract deviations |
| D. Integrate | Apply migrations, regenerate clients, connect real services and seed fixtures | Coordinator | All repos run together at recorded revisions |
| E. Verify locally | Docker tests, real localhost browser flow, real Flutter app on emulator, cross-client read/write/sync | Coordinator, agents repair owned failures | Matching business outcomes, durable retry and permission checks |
| F. Review/reconcile | Review changes, compare reports/stock/payments, inspect artifacts, check migration/recovery | Coordinator + available reviewer | No known data-loss/security/money/parity defect; evidence stored |
| G. Record | Update feature tracker, phase report and next dependencies | Coordinator | Agent-verified; no unreported skips |

A phase report must include **passed / failed / not run / not applicable** per gate. “Tests added” is not “tests passed.” Existing broad suites do not substitute for the feature's new scenario.

## 4. Execution phases and dependencies

Every phase below inherits steps A–G. Existing capability rows mean preserve/refactor/verify, not rebuild. Each phase may be delivered as the smaller slices listed; close one slice's integration gate before expanding its contract.

### E00 — Baseline, environment and reproducible fixtures

**Dependency:** none. **Comparison groups:** P0.

- Coordinator: inventory current branches, dirty changes, tool versions, Docker stack, test databases and available unlocked Android emulator; record real build identities. Run existing baseline checks and document pre-existing failures separately.
- API agent: inventory migrations/auth/RLS/financial endpoints and existing integration fixtures; verify how test databases are created and cleaned.
- Mobile agent: inventory SQLite versions, draft/queue storage, local-only and premium paths; identify emulator test entry points and safe fixture cleanup.
- Web agent: inventory routes/generated schema/browser scripts, native localhost and Docker-served origins, draft storage and browser seed needs.
- Create deterministic shared shop fixtures: free local shop; premium owner/admin/staff; second tenant; expired access; ordinary and fractional products; unknown cost; low/negative stock; invoices, partial returns and supplier dues. Use uniquely named synthetic data only.
- Output: environment manifest, baseline report, scenario manifest and evidence directory convention. Services and emulator actually run; unavailable prerequisites are recorded, not waived.

**Exit:** reproduce at least one web→API→mobile and one mobile→sync→web transaction with the existing implementation, verify local-only startup, and record baseline D01–D15 observations.

### E01 — Shared contracts and financial foundations

**Execution update (19 November 2026):** foundation scope accepted; slices 1–5 and the [closing audit](docs/refactor/evidence/E01/closing-audit.md) are verified. The [accepted compatibility contract](docs/refactor/contracts/E01-command-foundations.md) maps existing routes and negotiated versions; no universal replacement endpoint is claimed. Independent money fixtures, recovery safety and existing-data compatibility passed final API/mobile/web, localhost, emulator and Docker checks. E02 is ready to implement.

**Dependency:** E00. **Comparison groups:** P0/P2 foundation; P4 interface only.

- API: versioned command envelope, idempotency/result lookup, expected revision, structured errors, transaction boundaries, durable job/outbox/retry infrastructure and posting interface for stock/payments/future journals. Build this generic infrastructure before external reconciliation or restore jobs; calendar scheduling arrives in E14.
- Mobile: decimal/string conversion boundaries, local command/outbox adapter, revision metadata and compatibility readers; do not mass-rewrite historical money values.
- Web: generated DTO adoption, command/retry controller, durable operation identity and consistent error mapping.
- Coordinator: canonical workflow/default/precision/settings/capability specifications; independently reviewed expected-value fixtures. Existing vectors generated from mobile are regression evidence, not an independent mathematical oracle.
- Define journal posting interface now so later purchase returns/advances do not invent a second accounting model. Full accounting schema/UI comes in E06.
- Sub-slices: E01.1 contracts/settings; E01.2 command/recovery and durable outbox/job primitives; E01.3 decimal and posting adapters.

**Exit:** replay/timeout/conflicting-payload tests pass; all clients consume the same contract version; existing data remains readable; representative transaction commits atomically.

### E02 — Current flow parity and recoverable drafts

**Dependency:** E01. **Comparison groups:** P1.

**Execution update (20 November 2026).** [E02.1 settlement and checkout validation](docs/refactor/contracts/E02-slice-1.md) implemented and verified across API/mobile/web. Explicit choice, exact partial amounts/consent, atomic reviewed-save guard and retained safe retry passed API/web/mobile, paired localhost/offline emulator, premium restore and production Docker checks. [Settlement evidence](docs/refactor/evidence/E02/slice-1.md). E02.2 [recoverable checkout and held invoices](docs/refactor/contracts/E02-slice-2.md) is implemented and verified on localhost and Android. [Draft evidence](docs/refactor/evidence/E02/slice-2.md). [E02.3 Part 1 catalog entry from checkout](docs/refactor/contracts/E02-slice-3-catalog.md) is implemented and verified across API/web/mobile, localhost, Android emulator and production Docker. [Catalog evidence](docs/refactor/evidence/E02/slice-3-catalog.md). [E02.3 payment and completion](docs/refactor/contracts/E02-slice-3-payment-completion.md), web workspace selection and catalog return recovery passed [verification](docs/refactor/evidence/E02/slice-3-payment-completion.md).

**Execution update (21 November 2026).** [GST scheme and pricing defaults](docs/refactor/contracts/E02-slice-3-pricing-settings.md) now resolve consistently across web and mobile. [Pricing verification](docs/refactor/evidence/E02/slice-3-pricing-settings.md).

**Execution update (21 November 2026).** The shop-wide [low-stock threshold](docs/refactor/contracts/E02-slice-3-low-stock-threshold.md) now uses the same decimal settings contract across API, web and Android. Catalog and dashboard consume the same effective setting, with product reorder levels taking precedence. Android Store and Home and web Shop details passed runtime checks, including live Android and REST sync in both directions. [Low-stock evidence](docs/refactor/evidence/E02/slice-3-low-stock-threshold.md).

**Execution update (21 November 2026).** [Portable preferences](docs/refactor/contracts/E02-slice-3-portable-preferences.md) now follow the active Android account and shop, including defaults for absent settings. The web Appearance picker syncs with Android for the active paid workspace. [Preference verification](docs/refactor/evidence/E02/slice-3-portable-preferences.md).

**Execution update (21 November 2026).** [First-invoice onboarding](docs/refactor/contracts/E02-first-invoice-onboarding.md) now guides owners from Home to their first product and saved invoice. The [paired tests](docs/refactor/evidence/E02/first-invoice-onboarding.md) verified recovery and a single stock movement on localhost and offline Android.

**Execution update (22 November 2026).** [Workspace search](docs/refactor/evidence/E02/workspace-search.md), [settings search](docs/refactor/evidence/E02/settings-search.md), and [in-app notification routing](docs/refactor/evidence/E02/notification-routing.md) passed on localhost, Docker and Android. The next increment is the E02 phase-exit checks. Web Hindi localization and portable web language selection are deferred by the owner.

- API: expose/validate shared settings and capability responses where necessary; preserve existing account/security and entitlement behavior.
- Mobile: unified sale steps and explicit payment choice, complete checkout draft persistence, hold/resume/discard, safe child-editor return, validation/focus/error states.
- Web: same steps/defaults and held-cart workflow, reliable storage failure handling and cross-tab conflict recovery; align scan/not-found/create behavior.
- All: account/shop switching, activation progress, product entry, notifications/deep links, localization and business terminology. Preserve theme and existing shell; layout adaptation cannot omit a logical step.
- Sub-slices: E02.1 sale steps/default; E02.2 drafts/held carts; E02.3 catalog/account/settings/locale parity.

**Exit:** paired browser/emulator recordings show equivalent steps; kill/relaunch/reload restores complete drafts; switch tenant/role safely; expiry and failed save do not discard work.

The [real Android process-death acceptance](docs/refactor/evidence/E02/slice-2.md) passed two force-stops and three processes. The remaining phase-exit work includes the paired logical checkout sequence review. Human UX review remains pending.

### E03 — Billing, calculation and atomic sync correctness

**Dependency:** E01/E02. **Comparison groups:** P2.

The D03 [stock valuation contract](docs/refactor/contracts/E03-stock-valuation.md) and [paired verification](docs/refactor/evidence/E03/stock-valuation.md) are complete. The remaining E03 billing calculations and atomic sync work are tracked below.

- API: canonical sale/return/payment calculations, numbering/stock locks, versioned snapshots, aggregate command sync and safe legacy-row compatibility.
- Mobile: equivalent offline calculation and queue; migrate eligible financial writes from independent rows to atomic aggregate commands without duplicating historical effects.
- Web: pricing/review/version conflict recovery and immutable completion; display server-authoritative totals.
- All: resolve D03 valuation formula, quantity precision, payment enum aliases, discounts/rounding, catalog rate override guards and correction history. Cross-device draft handoff requires a single-consumer ownership design; current view-only backup must remain clearly labeled until implemented.
- Sub-slices: E03.1 report/math parity; E03.2 atomic sales/payment/return sync; E03.3 advanced line controls and handoff.

**Exit:** exact money fixture equality; concurrent last-stock/return/payment races remain valid; dropped response replays once; mobile/web/export reports converge. No arbitrary resnapshot of issued invoices.

### E04 — Purchase and supplier flow completion

**Dependency:** E03 and E01 posting interface. **Comparison groups:** P3 purchasing.

- API: preserve existing receipt/reversal rules; extend typed purchase tax/charge components, itemized taxable expenses, partial purchase returns, allocation preview and payment terms through the posting interface.
- Mobile: add receipt reversal/payment-term actions, richer supplier payment fields and selected-invoice allocation; local pending/confirmed/failed projection.
- Web: match the same review/correction states and typed receipt inputs; distinguish unknown legacy terms from paid/unpaid invoices.
- Sub-slices: E04.1 existing D06–D08 parity; E04.2 typed purchase and settlement; E04.3 partial purchase return and refund/credit.

**Exit:** receive → pay → partial return → reverse permitted effects → sync yields identical supplier balances and stock; duplicates/paid or consumed-stock reversals have matching guards. Legacy “not recorded” remains explicit.

### E05 — Parties, receivables and settlement rules

**Dependency:** E03/E04. **Comparison groups:** P3 party features.

- API: party abstraction with preserved customer/supplier IDs, addresses/groups, credit exposure, due dates/terms, advances and allocation/reversal contracts.
- Mobile/web: matching party editor/detail, statements, shipping address selection, payment preview, split tender and overdue/limit feedback; explicit service/non-stock type, service-period and line-description snapshots.
- Define offline credit policy honestly: local availability cannot guarantee global exposure across disconnected devices. Keep pending exceptions visible.
- Sub-slices: E05.1 party/address/group; E05.2 sales terms/aging/limits; E05.3 advances and receipt allocation.

**Exit:** as-of party statements and aging reconcile; groups/address changes do not rewrite invoice snapshots; concurrent allocations cannot overpay; account identity is not merged by matching names/phones.

### E06 — Accounting, cash/bank and period foundations

**Dependency:** E04/E05. **Comparison groups:** P4.

- API: accounts/journals/opening entries, cash and bank ledgers/transfers, other income, write-offs, balanced posting, period locks and ledger-backed reports.
- Mobile: local accounting adapter and report projections for free/offline use, compatible sync for premium.
- Web: same opening-balance, account, transfer, adjustment, journal and report workflows.
- Backfill only evidenced balances; retain unknowns and reconciled adjustment provenance. Never fabricate historical journals to force totals to balance.
- Sub-slices: E06.1 ledger/openings; E06.2 cash/bank/other-income/write-offs; E06.3 statements/period locks.

**Exit:** every new posting balances; party/stock/payment subledgers reconcile; balance sheet/P&L/cash flow are traceable to entries; opening migration and reopen authorization tested.

### E07 — Quote, order and delivery document chain

**Dependency:** E03/E05/E06. **Comparison groups:** P5.

- API: quote/proforma/order/challan states, links, remaining quantities, conversion/cancellation guards, reservation policy, terms and transport fields.
- Mobile/web: same create/share/review/convert/partial-fulfill/cancel flows with source and target drill-downs.
- Sub-slices: E07.1 quotation/proforma; E07.2 sales/purchase orders; E07.3 challan/undelivered return and invoice conversion.

**Exit:** concurrent/replayed conversion cannot over-fulfill or post stock twice; partial state and reversal remain identical; non-posting documents do not alter recognized balances.

### E08 — Firms, locations, units and traceable stock

**Dependency:** E06/E07 where document linkage applies. **Comparison groups:** P6 inventory foundation.

- API: firms inside tenants, warehouses, base/alternate units, lot/expiry/serial identity, stock allocations and transfers.
- Mobile/web: same master, receive, pick, transfer, serial selection and ledger workflows; supported scanner adapters enter the same state machine.
- Sub-slices in order: E08.1 firms/locations/units; E08.2 lots/expiry/serials; E08.3 transfers and reports.

**Exit:** conversion snapshots survive unit edits; transfer conserves total quantity; serials remain traceable across sale/return; batch remaining quantities reconcile after consumption and returns.

### E09 — Advanced pricing, manufacturing and inventory reports

**Dependency:** E08. **Comparison groups:** P6 advanced stock.

- API: wholesale/party-price precedence, BOM versions, production consumption/output/cost allocation and reversals; typed custom fields.
- Mobile/web: matching price rule setup and production preview/post/reverse, custom attribute editors and drill-down reports.
- Sub-slices: E09.1 negotiated/tier pricing; E09.2 BOM/production; E09.3 item/party/category/discount/manufacturing reports.

**Exit:** price precedence has deterministic fixtures; manufacturing input/output/cost reconcile; consumed material cannot be reversed illegally; historical recipes and attributes are retained.

### E10 — Cheques, loans, assets and fine-grained access

**Dependency:** E06/E08/E09 as applicable. **Comparison groups:** P6 finance/security extensions.

- API: cheque state transitions, loan principal/interest/fees, asset acquisition/depreciation/disposal, configurable capability/category access and audited reauthentication actions; defined cashier/POS shift and drawer rules where included in T22.
- Mobile/web: matching setup, post, settle/reopen/reverse and reports; permission editor cannot grant more than the actor may assign.
- Sub-slices: E10.1 capabilities; E10.2 cheques; E10.3 loans; E10.4 assets; E10.5 POS operations. Each is a separately verified slice; do not parallelize competing journal/schema edits.

**Exit:** cash/loan/asset accounts reconcile; prohibited transitions produce identical feedback; direct REST/sync cannot bypass role restrictions.

### E11 — Tax reports and electronic documents

**Dependency:** E01 durable job/outbox infrastructure, E06/E07/E08 and typed tax components from E04. **Comparison groups:** P7.

- API: verified current GST/cess/TCS/TDS/ITC/reverse-charge rules where applicable, report schemas, provider adapters, credentials and durable e-document status/reconciliation.
- Mobile/web: same tax setup, registration lookup states, review/generate/status/cancel workflows and export filters.
- Sub-slices: E11.1 tax components and official-schema fixtures; E11.2 report coverage; E11.3 e-invoice; E11.4 e-way bill.
- Research applicable official specifications during implementation. Provider credentials and sandbox access are concrete prerequisites; mocks are not external acceptance. If unavailable, finish unaffected tax/report work and keep provider slices blocked, not passed.

**Exit:** sandbox submit/status/replay/cancel reconciles; generated e-doc guards match; output and tax exports equal posted components. Physical/provider/regulatory acceptance is not inferred from emulator success.

### E12 — Invoice output, sharing and printing

**Dependency:** E03/E07 for core output; only e-document fields require the relevant E11 slice. Core PDFs and print adapters must not wait for unavailable tax-provider access. **Comparison groups:** P8 output.

- API: canonical renderable document snapshot and output settings; server renderer parity.
- Mobile: PDF/image/share and Bluetooth/Wi-Fi/USB adapters where supported; clear permission/connection/retry states.
- Web: same preview/output/copy/paper/settings intent; browser-supported printing or an explicit bridge capability. No promise of unsupported silent hardware access.
- Sub-slices: E12.1 field/settings/renderer diff; E12.2 PDF/image/copy parity; E12.3 hardware adapters.

**Exit:** compare A4/A5/58/80 mm artifacts, long invoices, returns, EN/HI, logo/signature and totals. Emulator can verify workflow/artifacts; hardware transport requires real-device/printer evidence or an explicit outstanding prerequisite.

### E13 — Imports, attachments, backup, restore and closing

**Dependency:** E01 durable job infrastructure, E06/E08 and relevant snapshot/file contracts from E12.1–E12.2 plus owning domain contracts. E12.3 physical-printer acceptance does not block imports, backups or closing. **Comparison groups:** P8 data operations.

- API: authorized business exports/restore jobs, catalog images/attachments, import validation/dedup, automatic-backup scheduling/retention, explicit portable-backup encryption/key recovery, recycle-bin dependency checks and close/reopen commands.
- Mobile: local backup/schema upgrades, dry-run restore, pre-restore recovery, corrupt/newer-version handling and safe re-sync.
- Web: equivalent import/review/result and authorized cloud backup/restore controls; personal account export is not substituted for business backup.
- Sub-slices: E13.1 catalog/party imports and attachments; E13.2 backup/restore; E13.3 recycle bin and fiscal closing.

**Exit:** restore and interrupted-migration drills preserve identity/totals; retry does not duplicate imports/stock; closing retains traceable carry-forward; `.vyb` compatibility remains unclaimed without verified format/sample support.

### E14 — Scheduled work, reminders and recurring documents

**Dependency:** E05/E07/E11/E13 as applicable. **Comparison groups:** P8 automation.

- API: durable scheduling/outbox, timezone, retry/dedup, permissions at execution, run history and provider delivery receipts.
- Mobile/web: same create/edit/disable schedule, preview, recipient, message and failure-history flows; saved/custom report definitions and matching export filters.
- Sub-slices: E14.1 report schedules; E14.2 payment/service reminders; E14.3 recurring invoices and transaction messaging.

**Exit:** simulated clock/restart/DST/expiry cases and provider sandbox failures do not duplicate sends/invoices; cancelled jobs stay cancelled; opening a share sheet is never reported as delivered.

### E15 — Loyalty, storefront, collections and field sales

**Dependency:** E05–E14 foundations required by the particular module. **Comparison groups:** P9 business extensions.

- API: module-specific entities/postings, public boundary protection, integrations and reconciliation.
- Mobile/web: same merchant setup and operational workflows; public customer/storefront interfaces are separate actors, not a replacement merchant flow.
- Sub-slices: E15.1 loyalty earn/redeem/expire/reverse; E15.2 public catalog/order acceptance/fulfillment; E15.3 collection/KYC/webhook/refund; E15.4 leads/tasks/assignment/location/attachments.

**Exit:** rewards and money ledgers reconcile; public endpoints cannot expose tenant-private data; online order/checkout retry does not oversell/double-collect; field permissions and task dependencies tested.

### E16 — Remaining reference candidates and explicit scope closure

**Dependency:** relevant foundations, particularly E15. **Comparison groups:** P9 discovery/growth/regional.

- Review phone/Google auth, partner/network/customer-profiling/voice surfaces, regional tax/multicurrency, interoperability, Smart Ads/campaign integrations, referrals/rewards/support/inbox and self-service subscription candidates.
- For each: establish behavior from the reference and current provider contracts, write a bounded contract, then use the three-repo slice lifecycle. Missing evidence is a discovery task, not permission to invent behavior.
- Multicurrency/region work needs conversion/posting/report fixtures and an explicit migration policy before UI inputs. Cosmetic seasonal aliases/themes remain excluded by the user's UI/theme requirement.
- Do not automatically drop these items because they are large. Mark implemented and verified, blocked on evidence/provider, or explicitly user-deferred with rationale. Discovery-only items can complete as discovery, but that does not mark the underlying feature implemented.

**Exit:** every comparison row has an accountable disposition. No remaining candidate is silently counted as delivered. Any scope reduction requires the user's actual decision.

### E17 — Full-system hardening and human-review candidate

**Dependency:** all in-scope implementation slices agent-verified; blocked/unimplemented slices cannot be silently included as complete. **Comparison groups:** P10 engineering readiness.

- Coordinator runs full regression on the final three-repo revision set. Agents repair defects in owned repos and review each other's contracts while maintaining single-writer ownership.
- Run Docker dev and production-image verification, migrations on supported PostgreSQL versions (17 and 18 per repository policy), fresh and upgraded SQLite, localhost browser, emulator, cross-device races/offline recovery, access expiry/revocation, backup/restore and representative large datasets.
- Measure performance against the E00 baseline and agreed budgets. Inspect generated artifacts/accessibility, logs and background-job recovery. Add missing harness coverage rather than claiming existing scripts cover new modules.
- Build a reproducible APK and web/API image set; debug emulator build may use the local CA, release artifact must not trust debug-only configuration. Verify both build paths separately.
- Prepare stable local review environment, synthetic scenarios, evidence index, version manifest, rollback instructions, known limitations and E18 checklist. Stop destructive or state-resetting suites before handing it to the user.

**Exit:** no unresolved blocker for data integrity/security/money/parity, all required tests have evidence, and every in-scope feature is ready for human verification. No production deployment is implied.

### E18 — Final human flow and UX verification

**Dependency:** E17. **Owner:** user; agents support and fix. **This is the final acceptance phase.**

Provide the running localhost web app and prepared Android emulator with the same review shop/data, instructions for local-only mode and supported hardware checks, and a checklist the user can edit. Keep theme/style unchanged. Include walkthroughs for:

1. First use/account/activation/shop switch; owner/admin/staff, expiry and recovery.
2. Find/scan/add item → sale → payment → print/share → another sale.
3. Hold/resume, back/cancel, restart/reload and uncertain save recovery.
4. Purchase/import → payment terms → supplier payment → return/reversal.
5. Customer/supplier details → statement → due/advance/collection.
6. Quote/order/challan → partial fulfillment → conversion/cancellation.
7. Stock, units, lots/serials, transfers, manufacturing and relevant finance modules.
8. Reports, taxes, output, schedules, backup/restore and remaining delivered modules.
9. Side-by-side mobile/web sequence, terminology, defaults, validation, error messages and result actions.
10. Small-screen keyboard, search, accessibility, navigation friction and real printing where supported.

Each case records: scenario ID; build set; user result (pass/fail); observed problem; expected flow; severity; screenshot/recording if available; owning phase; fix evidence; user retest. The user decides whether the UX is acceptable; automated tests cannot supply that decision.

On failure: coordinator reproduces → assigns fix → runs focused and affected integration/regression checks → returns the same case for human retest. No test-database resets during review without preserving the review data. Freeze and identify the accepted build set after all required cases pass. Production release, if desired, is a separate authorized operation after acceptance, not an automatic final action.

## 5. Localhost, Docker and emulator verification runbook

These commands were checked against current repository scripts on 18 November 2026; they were **not executed** while writing this plan. E00 must verify compatibility with the current checkout and repair stale harness assumptions. Run from the stated repo. The coordinator owns service startup, migrations, live tests and cleanup.

### 5.1 Environment topology

| Surface | Address / setup | What it proves |
|---|---|---|
| Docker dev web + API | `https://app.storely.localhost`, `https://api.storely.localhost` | Real browser, reverse proxy, API, PostgreSQL and session/cookie behavior |
| Optional host Vite | `http://localhost:5173` via web `npm run dev` | Local dev workflow/proxy; does not replace Docker-served acceptance |
| Local mail | `http://127.0.0.1:8025` | Synthetic verification/reset email flows |
| Android emulator API | `https://10.0.2.2` | Emulator→host TLS proxy→real API |
| Android emulator mail | `http://10.0.2.2:8025` | Test-only email retrieval |
| Docker production images | `make test-platform` disposable environment | Built image bootstrap/routing/migration checks; not complete business acceptance |

Check Docker daemon, Flutter/Dart, Android SDK/ADB, Java and a booted unlocked AVD. Record tool versions and `adb devices -l`. Select an explicit device (scripts default to `emulator-5554`), not whichever device happens to be first. Do not wipe an existing emulator to obtain a clean test fixture. Host Vite needs compatible Node/dependencies; the web Docker Makefile uses the pinned container toolchain.

From API repo, choose one mode for the shared stack:

```sh
# Development mode: API + web live reload.
make dev
make dev-seed
make verify
make smoke

# Use after dependency changes when a dev image rebuild is needed.
make dev-build
```

For a built-stack checkpoint, switch modes deliberately and verify the active images/volumes:

```sh
make up
make verify
```

Do not run mode switches concurrently with agents' live tests. A plain `make up` after dev overrides must be checked for stale dev mounts/image/config; inspect resolved Compose configuration before treating it as a production-style result. `make test-platform` is a separate disposable platform simulation, not a production deployment.

`make dev-seed` stores local review login information in the ignored `.dev-login`; do not copy credentials into tracked evidence. For new tests, prefer run-owned synthetic users/shops and tracked fixture definitions. The shared review shop must not be the target of destructive regression cleanup.

### 5.2 Repo checks

| Repo | Commands | Scheduling/coverage |
|---|---|---|
| Mobile | `flutter analyze`; relevant `flutter test test/<case>.dart`; final `flutter test`; `flutter build apk --release` | Host Flutter. Pure tests can run independently of web/API pure checks; serialize Flutter invocations if they share tool/build locks or generated outputs. |
| Web | `make lint`; `make typecheck`; `make test`; `make build`; final `make check` | Docker-backed commands. `make check` also audits dependencies and checks/regenerates API types; do not run against a moving schema. |
| API | `make lint`; `make test` | Docker lint/type/security and unit tests. Confirm images contain latest code. |
| Contract | API `make openapi`; then web `make api-types`; later web `make api-types-check` | Serial cross-repo mutation; web checks use a fixed `/tmp` file and rewrite generated output. |
| Calculation compatibility | API `make vectors-check` | Existing mobile-generated regression vectors; add independent expected-result fixtures for new rules. |

Use targeted tests during iteration; run the agreed wider regression at integration/phase boundaries and E17. Do not rerun unrelated expensive suites without a reason or call a full suite unnecessary when the change affects its shared financial/schema contract.

### 5.3 Shared-stack tests — serialized until isolation is implemented

From API repo:

```sh
make test-integration
make test-sql
make test-decimal-upgrade
make test-mobile
make test-device DEVICE=emulator-5554
make test-device-premium DEVICE=emulator-5554
make test-device-web-premium DEVICE=emulator-5554
make test-platform-console
make test-subscription-lifecycle
make test-web-premium
make test-backup-restore
make test-local-load
make test-platform
```

From web repo:

```sh
make e2e
```

Run only applicable suites per slice; run the full applicable set for E17. Capture command, start/end, exit status, build manifest and redacted artifact location. A script's cleanup failure is a test-environment incident to resolve before the next run.

**Existing harness limits that E00 must address:**

- `make test-mobile` exercises host Flutter sync, not Android UI.
- `make test-device` covers CloudService/auth/security behavior, not every checkout screen.
- `make test-device-restore` is an alias for premium acceptance, not a distinct general restore suite.
- SQL tests explicitly reapply older migrations 0002–0007; new migration replay/upgrade scenarios need additional coverage.
- `storelyweb/e2e/live.cjs` still contains historical unrestricted “Create shop” onboarding and old navigation expectations. Audit and update those fixtures/assertions before relying on `make e2e`; no current runtime failure is asserted here because it was not run.
- Live mobile/device/browser suites adjust and restore the same API rate-limit setting; concurrent runs can restart each other's API.
- Integration/purchase tests reuse `storely_apitest`; SQL tests reuse `storely_sqltest`; logs have fixed paths. Two copies can destroy each other's fixture DB.
- Device tests share the emulator app/package/preferences/Keystore and some artifact paths; one runner owns an emulator.
- Production simulation uses disposable containers but fixed image tags; simultaneous builds can invalidate evidence.
- Browser tests can ignore development certificate errors. Retain explicit `make verify` and mobile certificate refusal tests; never globally disable TLS verification.

E00 may implement run-scoped harness isolation as an infrastructure slice before business changes. Full isolation requires distinct ports, database names, Compose projects/volumes, image tags, endpoints, log paths and emulator identities. Setting only `COMPOSE_PROJECT_NAME` is insufficient with fixed ports 80/443/8025.

### 5.4 Debug emulator walkthrough

The existing API helper `scripts/mobile-dev-defines.sh` prints test endpoints and a base64 development CA. The flags are honored in debug builds only. Run from mobile using an explicit device and the helper's printed flags. A shell-safe example that avoids evaluating the helper output as shell code:

```sh
python3 - <<'PY'
import shlex
import subprocess
flags = shlex.split(subprocess.check_output(
    ['bash', '/Users/rudra/projects/storelyapi/scripts/mobile-dev-defines.sh'],
    text=True,
))
subprocess.run(
    ['flutter', 'run', '-d', 'emulator-5554', *flags],
    cwd='/Users/rudra/projects/Storely',
    check=True,
)
PY
```

Replace the device ID with the observed unlocked emulator. Use the existing `DEVICE=... make test-device...` wrappers for their corresponding suites. New business UI scenarios must be added under `integration_test` and wired to a dedicated runner that supplies the same verified endpoints; do not claim a future runner already exists.

Do not use the emulator's `localhost` as the host API. Do not bake test CA credentials/endpoints into release builds. Real handset/printer verification needs its own supported network/USB setup; `10.0.2.2` is an emulator convention.

## 6. Required paired end-to-end scenarios

Create an executable scenario manifest in E00/E01; extend it per feature. Scenario IDs below are planned acceptance IDs, not existing test commands.

| ID | Actions on both clients / across clients | Required assertion |
|---|---|---|
| E2E-01 | Same owner/role/settings → same sale input → same review/result | Equal required fields/defaults/errors, totals and allowed next actions |
| E2E-02 | Web creates invoice → mobile pulls → mobile payment/return → web refreshes | Same identity, original snapshots, stock and remaining due |
| E2E-03 | Mobile offline sale → restart → reconnect → web detail | Exactly one accepted aggregate; clear pending/conflict state |
| E2E-04 | Save reaches server but response is lost; reload/relaunch and retry | Recover original result using persisted operation ID |
| E2E-05 | Both clients sell/return/allocate the same remainder concurrently | No illegal over-allocation; one clear reconciled outcome |
| E2E-06 | Purchase/import → partial payment → return/reversal | Supplier, inventory, tax and accounting projections reconcile |
| E2E-07 | Hold/edit/resume/discard, storage failure, cross-tab ownership change | No lost or double-consumed draft; complete recovery fields |
| E2E-08 | Change shop, revoke staff, expire subscription while editor is open | No cross-tenant writes/cache exposure or unauthorized commit |
| E2E-09 | Quote/order/challan partial conversion and cancellation/retry | Remaining quantities correct, no double stock posting |
| E2E-10 | Unit conversion, lot/serial receive/sale/return/transfer | Quantity and identity invariants; matching ledger/report |
| E2E-11 | Cash/bank transfer, journal, loan/asset/cheque actions | Balanced entries and correct state-dependent actions |
| E2E-12 | Tax generation success/timeout/cancel/provider retry | Reconciled provider status, no duplicate e-document |
| E2E-13 | Same report filters/as-of → UI/API/local/export | Equal totals and inclusion rules; explicit freshness |
| E2E-14 | Print/share long invoice/credit note in supported formats | Same financial content, correct copy/title/pagination; save unaffected by print failure |
| E2E-15 | Backup → corrupt-file refusal → valid restore → sync | Original remains safe; identity and balances preserved |
| E2E-16 | Old populated DB/client → migration → interrupted restart | No lost data; compatible recovery; no duplicate queue replay |
| E2E-17 | Schedule triggers/retries/cancellation/role loss | One authorized execution and accurate delivery/job status |
| E2E-18 | Delivered loyalty/storefront/payment/field module lifecycle | Module ledger, public/private boundary and paired merchant flow pass |
| E2E-19 | Free mobile without network/account | Local core work remains functional and is not forced into cloud onboarding |
| E2E-20 | User's E18 walkthrough | Human pass/fail recorded by user; no inferred approval |

For comparisons use separate equivalent seed shops or reset only run-owned fixtures; do not compare two successive sales against a stock balance altered by the first. For cross-client tests use a shared run-owned shop and compare at a recorded sync watermark. Include an as-of date and shop timezone in report fixtures.

## 7. Tracking, evidence and phase handoffs

Files to create as work proceeds (these are conventions, not claims that evidence exists now):

```text
Storely/docs/refactor/
  feature-tracker.md                 # Created with this plan
  contracts/Exx-slice.md             # Versioned workflow/API/domain decisions
  decisions.md                      # Unknowns resolved; chosen policy and evidence
  scenarios.json                    # Seed IDs, action sequences, expected effects
  evidence/Exx/run-id/summary.md     # Build set, commands, results, reproduction
  human-verification.md             # E18 cases, findings and user sign-off
```

Keep large videos/APKs/database dumps and credentials out of Git; store local artifacts in an ignored run directory and link their manifest/checksums from evidence. Redact personal data and secrets. Test cleanup must delete only records/artifacts owned by the recorded run.

Phase report template:

```text
Phase / slice / feature IDs:
API, web, mobile revisions and dirty patch IDs:
Contract version / migration versions / fixture ID:
Implementation summary and reference decisions:
Repo checks: command → result → evidence
Docker integration: command → result → evidence
Localhost browser: scenario → result → evidence
Android emulator: device/build/scenario → result → evidence
Cross-client reconciliation: expected → actual
Upgrade/rollback/restore checks:
Not run / blocked / not applicable, each with reason:
Remaining defects and owning phase:
Ready dependent slices:
Coordinator acceptance: agent-verified or incomplete
```

The tracker is authoritative for progress; the audit remains authoritative for the original observations. New findings are added as new IDs, never hidden by changing an old comparison status. No phase is complete merely because all agents ended their turns.

## 8. Starting implementation

The first implementation assignment, once requested, is **E00**, using the three repo lanes. Do not begin advanced feature coding before the baseline and E01 contracts. The coordinator then follows the dependency order and performs shared environment tests, while agents build independent repo changes in parallel.

Required outputs before E18: integrated implementation, paired acceptance evidence, successful migration/recovery checks, reviewable build artifacts, a stable localhost/emulator review setup and an honest remaining-limitations list. Required output after E18: the user's recorded flow/UX acceptance of the final identified build set. Deployment is not part of this planning task.
