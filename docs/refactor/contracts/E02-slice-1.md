# E02.1 — explicit settlement and checkout validation

Status: planned; code inspection completed 19 November 2026. Dependency: accepted E01 contracts and closing evidence. Preserve theme, navigation shell and free offline operation. This is the first implementation assignment after E01, not a claim that E02 is implemented.

## Confirmed current differences

Mobile `scan/bill_checkout_sheet.dart` initializes paid/cash; web `src/billing/NewBill.tsx` requires a payment selection. Mobile partial input can be parsed/clamped into unpaid or full payment, while web rejects invalid partial values. Mobile also permits unassigned credit without the web warning/consent. Duplicate sale must not silently inherit a settlement decision.

Checkout closes before `_completeBill` commits. Failure preserves cart items but loses checkout fields; cancellation/relaunch and held bills currently retain items rather than the entire checkout. Settings are reread at commit, so a changed round-off setting can change the payable amount after preview. These findings require explicit regression coverage, not merely relabeling controls.

## First implementation boundary

1. Both clients start settlement unselected. Require an explicit full/partial/unpaid choice; cash remains the initial method when applicable. A duplicate creates a new unsettled draft.
2. Partial payment must be a valid exact amount strictly between zero and reviewed total. Reject blank, malformed, negative, zero, equal or excess input without clamping. Preserve fields and display the reason.
3. For unpaid/partial without a resolvable customer, provide equivalent explicit unassigned-balance consent. Do not create or merge parties by name/phone automatically.
4. Generate/save must validate before closing. A commit failure must retain entered checkout state for retry. Retrying a successful-but-unacknowledged command follows E01 identity rules; do not introduce a fresh key.
5. Freeze the reviewed calculation context or detect a settings/total change and require review before commit. Never silently change the settlement to accommodate a new total.

Mobile lane owns checkout validation/state handoff and tests in `lib/screens/scan/`, `lib/screens/scan_screen.dart` and relevant DB boundaries. Web lane verifies matching settlement/consent behavior and adds tests where absent. API lane verifies existing authoritative validation and exact DTO compatibility; only add a server change after reproducing a missing guard. Coordinator owns contract, shared fixtures, runtime scheduling and cross-client evidence. Each lane commits only its verified feature files.

## Validation and acceptance

- Pure settlement cases plus real widget/form tests: unselected blocks, invalid partial retains input, valid full/partial/unpaid reconcile total/paid/due, duplicate rechooses, unassigned credit requires consent, failed commit retains state, changed settings require review.
- Mobile tests use manual entry and SQLite seeded products, no camera/network requirement. Existing money oracle and billing DB regressions remain green. Local-only shop must complete the valid flow offline.
- Web unit tests/typecheck/lint/build, API authoritative validation and Docker regression for any changed server boundary.
- Coordinator runs equivalent fixture on localhost and emulator, capturing actual steps/validation/posted totals. Human UX acceptance remains E18.

Full persisted checkout schema, held-cart lifecycle, relaunch recovery and tenant-scoped draft migration are E02.2. Catalog/account/locale parity is E02.3. Do not mark E02 complete after settlement alone; its phase exit includes paired recovery, tenant/role switching and failed-save preservation.
