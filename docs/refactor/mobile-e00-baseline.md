# E00 mobile baseline

Execution date: 18 November 2026. Inspected mobile source baseline: `eb219e6` on `package-com-storely`. Scope: Flutter host analyzer/unit/widget tests and source inventory. No emulator or shared Docker service was started or changed by this lane.

## Environment and checks

- Flutter 3.44.4 stable, framework `ad70ec4617`, Dart 3.12.2, DevTools 2.57.0.
- Installed SDK: `/opt/homebrew/share/flutter` through `/opt/homebrew/bin/flutter`.
- The initial sandboxed Flutter invocation was denied writes to the SDK engine cache. The approved elevated invocation succeeded; this was an environment restriction, not an application failure.
- `flutter analyze`: **passed**, no issues found (5.1 seconds).
- `flutter test --reporter expanded`: **passed**, 309 passed, 17 skipped opt-in live API tests, 59 seconds. Full local log: `/tmp/storely-mobile-e00-tests.log` (untracked local evidence).
- Dependency resolution reports 80 newer packages outside current constraints. This does not justify changing the dependency set during baseline capture.
- Emulator, real API, localhost UI, physical hardware and release build: **not run by this lane**; coordinator owns those integration gates.

## Persistence and migration inventory

`lib/db/database_schema.dart` opens schema version **25**, enables foreign keys, builds fresh schema directly and performs additive upgrade checks. Versioned data migrations use completion markers; reopen schema checks are idempotent. Existing tests include v16 upgrades, legacy barcode duplicates, invoice-number defaults and v21 private held-cart upgrades. These tests do not establish every historical upgrade lineage.

Important persisted aggregates:

| Store | Current contract | Refactor implication |
|---|---|---|
| Business rows | Sync triggers maintain dirty state; imported rows settle clean; derived caches excluded | Preserve existing identities and derived-field semantics during command migration |
| `purchase_documents` | UUID + whole JSON payload, origin, pending/synced/error/local state | Existing aggregate transport is a useful base for atomic commands |
| `purchase_drafts` | One active editing draft per shop, revision-checked writes and posted state | Reuse optimistic revision pattern for sale drafts; reject stale writers |
| `supplier_payment_queue` | Request key, payload, pending state, cloud result/error | General command recovery should preserve exact operation identity/payload |
| `held_bills` | UUID, shop/account/device ownership, kind, label and item JSON | Existing foreign-device restore is read-only; single-consumer transfer needs a separate contract |
| `user_preferences` | Shop/account-scoped values | Keep credentials/device security out of portable business settings |

## Confirmed source observations

1. Sale draft persistence in `lib/screens/scan_screen.dart` serializes only cart items after a 400 ms debounce. Customer, discount, payment and checkout step live separately in the checkout sheet. A complete draft contract must cover them before parity changes.
2. `_BillCheckoutSheet` initializes payment status to paid and method to cash. Web currently requires an explicit payment choice. The proposed future explicit-choice default is a contract decision; this baseline does not change it.
3. Mobile valuation in `lib/db/database_reports.dart` includes positive stock at raw purchase price. API resolved acquisition-cost valuation differs; a shared independent fixture must fix the intended policy before code changes.
4. `CloudSyncEngine` pulls and pushes business tables independently, then exchanges atomic purchase snapshots through `PurchaseSyncBackend`. Its existing first-sync choice, role checks, per-row conflicts and cursor overlap must remain compatible while financial writes adopt aggregate commands.
5. Welcome flow exposes Start Fresh; cloud entitlement denial pauses transport while retaining owner offline work. Existing offline startup/cloud-setup tests cover parts of this behavior, not emulator acceptance.

## Existing test entry points and isolation

- `test/`: host unit/widget/FFI SQLite tests, including `db_upgrade_test.dart`, `cart_and_preferences_restore_test.dart`, `purchase_composer_draft_test.dart`, `sync_engine_test.dart`, financial/report vectors, backup and access tests.
- `test/api_sync_live_test.dart`: requires `STORELY_LIVE_API`, `STORELY_LIVE_CA` and `STORELY_LIVE_MAIL`; normally skipped. Coordinator runs it using API `make test-mobile`.
- `test/supplier_payments_live_test.dart`: opt-in `STORELY_SUPPLIER_LIVE=1`; reads local review login and uses fixed test database filenames. It must not overlap another run against the same fixture state.
- `integration_test/cloud_on_device_test.dart`: actual Android CloudService/security path.
- `integration_test/premium_on_device_test.dart`: actual Android activation/restore path, with the API wrapper supplying a run identity and debug endpoints.
- `integration_test/supplier_payments_on_device_test.dart`: supplier payment device scenario; coordinator must inspect fixture isolation before execution.

Host test pass does not establish a real Android UI pass or cross-client convergence. Avoid running Flutter tool invocations simultaneously when they contend for the same SDK/build locks.

## E01 contract recommendations

Freeze a versioned command envelope containing operation ID, shop/actor/device ownership, schema version, expected revision and exact payload fingerprint. Include durable local pending/accepted/rejected/unknown states and replay/result lookup. Define posting outputs together (stock, payments, future journal entries), rather than extending independent row sync with more financial tables.

Define complete sale draft fields and continuation state, including calculation/settings version and frozen uncertain-save payload. Use the existing purchase draft revision model and atomic receipt patterns where practical. Define decimal serialization, per-unit quantity precision, settlement method aliases and an independently calculated valuation fixture. Never rewrite historical invoice snapshots to conform to a new calculator.

## Scope and remaining gates

No application logic was changed during baseline capture. The coordinator must still run emulator, live API, browser and cross-client scenarios before E00 can close. Test harness presence alone is not evidence that those gates passed.
