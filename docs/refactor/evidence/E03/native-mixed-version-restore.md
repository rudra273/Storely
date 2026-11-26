# E03.2 mixed-version upgrade, downgrade & restore verification

Run date: 27 November 2026. [Atomic sale sync contract](../../contracts/E03-atomic-sale-sync.md) (Rollout gate 2) and [Atomic billing commands contract](../../contracts/E03-atomic-billing-commands.md).

Verified safe SQLite schema upgrades, local backup/restore, downgraded/flag-off builds, server capability loss, cross-account isolation, legacy `/sync/push` vs native command collisions, and PostgreSQL backup/restore across API and Android.

- **API mixed-version & restore checks (`tests/test_native_mixed_version_compat.py`)**: `make lint` clean across 207 files (0 `mypy` issues in 184 files, `bandit` clean); all 4 integration tests passed (`1.40s`):
  1. Legacy `/sync/push`-uploaded invoice blocks `POST /bills/native` and `POST /bills/native/reconcile` (`409 native_sale_identity_exists`, unconsumed `Idempotency-Key`) and reports `status == "identity_conflict"`, `can_reconcile == False` on `reconcile/inspect` without overwriting legacy rows.
  2. Native follow-up commands (`payments/native`, `credit-note/native`, `cancel/native`) work cleanly on legacy-uploaded invoices and propagate exact balances, stock (`quantity_cache`), and rows to `/sync/pull`.
  3. Restored device replaying committed native sale, payment, and credit note with original `Idempotency-Key`s receives `200 Idempotent-Replay: true`, while fresh keys are blocked with `409 native_sale_identity_exists` and zero duplicate rows.
  4. Proofless v1 native sale interoperates cleanly with v1 `native_billing_commands`.
- **PostgreSQL backup/restore drill (`make test-backup-restore`)**: `PASS 45 tables restored with matching content; RLS preserved; scratch DB/dump removed`.
- **Android upgrade, backup/restore & downgrade checks (`test/native_mixed_version_restore_test.dart`)**: `flutter analyze` clean; opt-in suite (`STORELY_NATIVE_SALE_POSTING=true`) passed **31/31** tests across `native_sale_sync_test.dart`, `native_sale_reconciliation_test.dart`, `native_billing_commands_test.dart`, and `native_mixed_version_restore_test.dart`; default-build (`STORELY_NATIVE_SALE_POSTING=false`) passed **10/10** non-skipped tests across `native_mixed_version_restore_test.dart`, `db_upgrade_test.dart`, and `backup_test.dart`:
  - Upgrading a pre-`native_billing_commands` v27 SQLite DB creates `native_billing_commands` and its pending index while preserving legacy null-snapshot, proofless v1, and strict v1 `checkout_acceptances` rows untouched.
  - Flag-off / downgraded builds never leak reserved `checkout_acceptances` or `native_billing_commands` rows into legacy row sync.
  - Full SQLite `BackupService` backup & restore preserves pending sale, payment, and credit-note reservations, frozen payloads, and operation keys, delivering them in order (`['sale', 'payment', 'credit_note']`) on sync.
  - Server capability loss keeps existing reservations on their command routes while falling back new writes to legacy row sync; switching accounts on a restored DB isolates the original owner's reservations.

`STORELY_NATIVE_SALE_POSTING` remains `false` by default until final E17 release hardening and E18 human approval.
