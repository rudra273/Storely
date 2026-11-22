# Settings search verification

Run date: 22 November 2026. [Acceptance contract](../../contracts/E02-settings-search.md).

- Web commit `da7e56a`. Typecheck, lint, build and 647 tests passed. The build reported its existing bundle size warning.
- The localhost browser test used a disposable paid shop and the live Docker API. It verified literal aliases, focus on the existing section, exclusion of saved values, and no requests or revision changes during search. Switching sections retained the unsaved draft. An explicit save sent the original revision and persisted the edit.
- `make test-platform` passed the production web build and disposable Docker bootstrap, TLS, frontend proxy and route smoke checks. The search uses existing API contracts.
- The disposable browser shop, account and mail were removed after verification.
- Android commit `b755037`. `flutter test --no-pub integration_test/settings_search_test.dart --no-uninstall -d emulator-5556` passed. The isolated Android test opened the existing low-stock, invoice, and app settings editors and checked that search did not change settings. The emulator revealed an ink rendering assertion in the App Settings sheet. The passing run used transparent Material wrappers around the affected rows.
- The full Flutter suite passed 515 tests with 17 opt-in skips. Four focused tests and the analyzer passed, including coverage for hidden team management, excluded values, and rejecting a stale account result.
