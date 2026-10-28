# Phase 12 verification — 2026-10-28

Implemented SQLite v22 and PostgreSQL migration 0010. Sync now covers 17 tables,
including held/draft carts and portable preferences. The executable contract
classifies 346 SQLite columns, 31 nested cart fields and nine preference keys.
See [data mapping](DATA_MODEL_PARITY.md) and [master plan](../plan.md).

Validation completed locally:

- Flutter: 245 tests passed, 16 live tests skipped; analyzer clean; release APK built.
- API: 251 unit tests and 207 PostgreSQL integration tests passed. The final
  migration passed all three targeted parity/RLS/reapplication integration tests.
  Ruff, strict mypy, Bandit, dependency audit, secret scan and production-image
  high/critical vulnerability gate passed.
- Web: generated API contract/typecheck and 89 tests passed.
- Native Android: `bash scripts/device-premium-tests.sh` in the API repo passed on
  the fresh unlocked `storely_pixel`, Pixel 6/API 35 arm64, against local TLS API,
  PostgreSQL and Mailpit. It includes real request UI, verified activation, consent
  and backup before first upload, all-table restore and mobile/REST round trips.

The native fixture populates all 17 tables, including decimal stock, GST/HSN,
product metadata, supplier movements, payments, credit notes, cancellation,
expenses, audit, shop image/signature and invoice settings. It restores into an
empty SQLite database with a new device UUID and deliberately different product
integer IDs, compares stored business fields and UUID relationships, and checks
stock, customer/payment summaries and distinct device invoice numbers. It verifies
portable preferences while printer/app-lock remain local, and refuses second-device
cart resume. A separate authenticated REST client reads mobile products and writes
a product edit/bill; both restored and source mobile databases then see those changes.
Local tests cover interrupted accepted uploads, idempotent retries, account switches,
cart tombstones/atomic consume and additive v21-to-v22 migration.

This is one real emulator using independent SQLite databases and device UUIDs,
not two physical phones. Web changes are exercised through the API, not browser UI;
browser lifecycle acceptance remains Phase 14. Other-device carts are view-only
backups, with no remote handoff. Customer review and physical-device testing remain.
The harness isolates its database and restores saved preferences/secure keys.
The normal app is reinstalled after testing and the emulator remains running.
