# Workspace search verification

Run date: 22 November 2026. [Acceptance contract](../../contracts/E02-workspace-search.md).

Search uses active shop records and opens the existing detail for the selected ID. The browser test uses a disposable paid owner with two shops and one staff member. Android uses a separate emulator and a local database containing active and retained foreign-shop records.

## API and Docker

- The optional search parameter reuses existing list endpoints and requires no database migration. Tests exercise literal `%`, `_` and backslash, formatted phones, mixed text and digits, the legacy invoice number alias, active and deleted records, outsider denial, and isolation between two shops with the same owner. Supplier-name matches retain the existing owner/admin visibility boundary.
- API commit `230dbba`. All 413 integration tests, 390 unit tests and `make lint` passed. The integration run reported the existing duplicate health operation ID warning. `make api-types-check` passed for web commit `c51d347`.
- `make test-platform` built the API and web images and passed the disposable production bootstrap, TLS, frontend proxy and route smoke tests.

## Android

- Android commit `8e9f8fb`. The full Flutter suite passed 511 tests with 17 opt-in skips.
- The focused suite passed eight tests. They cover the five-record cap and stable order, literal matches, same-phone foreign bill exclusion, retired or foreign category/supplier links, missing and deleted records, role transitions, and staff-safe product details. The analyzer passed.
- `flutter test --no-pub integration_test/home_global_search_test.dart --no-uninstall -d emulator-5556` passed on the disposable emulator. Product, invoice and customer results opened the selected record. Returning preserved the Home query, and a formatted phone matched without including retained records from another shop.
- The emulator exposed an existing product editor ink assertion in the stock switch. The final passing run used a transparent Material wrapper around the switch.

## Browser

- Web commit `e45a543`. Typecheck, lint, build and 642 tests passed.
- `node e2e/workspace-search.cjs` passed against localhost and Docker. It verified literal punctuation, formatted phone, exact record routes, void exclusion, partial outage retry, a delayed response during shop switching and staff access. The disposable accounts, shops and mail were removed.
- Android retains the query on return from a record. Browser Back can restore the field value, so a blank field on history navigation was not used as an acceptance condition. Account and shop resets passed. Human UX review remains open.
