# E02.3 Shop low-stock threshold verification

21 November 2026

Everyone who can read the shop sees the effective low-stock default. Owners and admins can change it. Web uses the Stock alerts field in Shop details, and Android uses the existing Store and Home controls. The [contract](../../contracts/E02-slice-3-low-stock-threshold.md) documents fallback, four-decimal precision, override precedence and stock counts.

| Check | Result |
| --- | --- |
| API | 390 unit and 402 PostgreSQL integration tests passed. A final focused 12-test run covered canonical storage of signed numeric zero and settings revisions. Ruff, mypy and Bandit passed. |
| PostgreSQL | Verified owner/admin permissions, staff reads, tenant isolation, stale revision rejection after native sync, audit trail, malformed or oversized text fallback, and the same boundary across detail, exact lookup, list, bulk selection and reporting. |
| Web | Typecheck, lint, 612 tests, build and generated API types passed. The first unrestricted full run timed out on several test files during parallel builds. The full retry passed with two test workers. |
| Localhost Chromium and Docker API | Invalid edit retained and focused with no PATCH. `9.9999` survived a page reload and left a product with stock `10` above threshold. `10` flagged the product in catalog and the dashboard. Zero shop threshold and zero product overrides behaved as expected. No stock movements were posted. |
| Flutter | 483 tests passed and 17 opt-in live tests skipped. Analyzer found no issues. |
| Offline Android | Store rejected a five-decimal entry, retained the input, and saved `5.5001` after correction. Home used that value, included the boundary product, and excluded both a product above the boundary and untracked stock. Home saved `5.5002`, and the second product appeared. SQLite reopen retained the change. |
| Android restore and live API sync | The isolated Android device wrote `23.5012` and uploaded it. A second REST session read it and saved `18.2501` against the current settings revision. Both Android test databases pulled the new value through the real TLS API. |
| Production Docker | Bootstrap, repeated migrations, verified database TLS, frontend proxy, deep links and security headers passed. |

The browser and Android restore test accounts and shops were removed. The local API rate limit returned to its regular value after testing. Human UX review remains open for the final phase.

Commits are API `16f16af` and `57567eb`, generated web types `d3a5bf1`, web `f891608` and Android `989c5c0`.

Test logs are under `/tmp/` with the prefixes `storely-e023-low-stock-`, `e023-low-stock-`, and `storely-web-lowstock-`. The next gap is portable preferences. Android reads cloud rows by shop and owner but applies them to device-wide preference keys. A destination account can inherit the previous value when its own row is missing.
