# E02.3 GST scheme and pricing defaults verification

21 November 2026

Android's existing settings reader and its product transaction both used the legacy `gst_registered` flag even when the profile had a valid `gst_scheme`. The API already preferred the scheme but accepted invalid numeric defaults and rounded some legacy values in settings responses. Mobile editors rounded values as they opened. The [pricing settings contract](../../contracts/E02-slice-3-pricing-settings.md) defines the shared rules and preserves issued invoice snapshots.

| Check | Result |
| --- | --- |
| API unit and lint | 390 unit tests passed. Ruff, mypy and Bandit passed. Existing InvoiceSettings output schema metadata is covered. |
| API and PostgreSQL | 399 integration tests passed. Price preview with a stale legacy flag returned ₹1,338.93 for regular and ₹1,336.91 for composition. Legacy rows, unrelated keys and historical invoice snapshots survived effective settings reads. |
| Flutter | 456 tests passed and 17 opt-in live tests skipped. Analyzer found no issues. Coverage included numeric bounds, no incidental rewrite of malformed or high-precision values, stale baseline rejection and historical snapshots after product price refresh. |
| Android emulator | The existing pricing editor rejected a four-decimal margin without saving a valid overhead from the same edit. A corrected `12.345` margin survived reopening. Both price resolution and actual product insert used the effective GST scheme over a stale flag. The test used an isolated SQLite database. |
| Web | Typecheck, lint, 576 tests and production build passed. |
| Localhost Chromium and Docker API | Invalid draft retained, Pricing & tax revealed and first invalid field focused. No invalid PATCH sent. Revision-protected `12.345` saved and survived reload. Real API price previews returned ₹1,338.93 for regular and ₹1,336.91 for composition. Exact synthetic shop, owner, mail and temporary credentials were removed. |
| Production Docker | API and web images ran in a disposable stack. Bootstrap, repeated migrations, database TLS, proxying, deep links and security headers passed. |

Implementation commits are API `1c30037`, web `e7f0981` and mobile `445beaa`. Android acceptance is in `bb9066c`.

Runtime and suite logs are under `/tmp/` with the prefixes `storely-e023-pricing-`, `e023-pricing-`, `storely-pricing-mobile-` and `storely-web-gst-settings-verified.log`. The Android acceptance uses equivalent local data and the existing double-based price calculation. A live cross-device sync of the new pricing editor actions and human UX verification remain separate checks.

The next settings gap is the shop-wide low-stock threshold. Catalog and reporting API queries accept decimal text. Android reads an integer and falls back to five for an invalid value. Web does not expose a shop-wide editor. Portable account/shop preferences and EN/HI parity remain open.
