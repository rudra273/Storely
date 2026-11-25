# First-invoice onboarding verification

Run date: 21 November 2026. [Acceptance contract](../../contracts/E02-first-invoice-onboarding.md).

The paired sale uses one tracked product at ₹118, opening stock ten and a partial cash payment of ₹50. Expected results are one invoice, ₹68 outstanding and stock nine. The Android journey starts from a local shop. The browser journey starts from an empty paid shop in the local Docker environment. Both use the existing product and checkout screens.

## API and prerequisites

- API commit `130b131` adds a focused regression using existing routes. An unpaid shop cannot commit a bill. After a test operator grants paid access, preview and rejected settlement leave the milestone incomplete. A successful save and exact retry return the same invoice. Its cancellation leaves the original in history and leaves a second shop empty.
- `bash scripts/integration-tests.sh tests/test_first_invoice_onboarding.py tests/test_subscriptions.py tests/test_checkout_review.py -q` passed 37 tests. `make test-integration` passed all 409 integration tests with the existing duplicate health operation ID warning.
- `node e2e/onboarding.cjs` passed on localhost. A verified account without a shop can reload the welcome screen, see the empty invitation state and open the Premium request page. Merely viewing those pages creates neither a shop nor a request. The disposable account and mail were cleaned up by the harness.
- `make test-platform` passed with the updated web image. It exercised production database bootstrap and repeat migrations, database TLS, the frontend proxy, checkout deep links, and baseline security headers in a disposable Docker stack.

## Browser

- Web commit `24e3270`. Typecheck, lint, production build and all 629 tests passed. The build reported its existing bundle size warning.
- `node e2e/first-invoice-onboarding.cjs` passed against current-source Vite and the local Docker API. The existing Home card recovered from a failed progress request, advanced after the first product, and remained visible while the invoice was held or recovered after reload.
- The first write reached the API and the browser lost its response. After reload, retry sent the same request body and idempotency key. The resulting invoice matched ₹118 total, ₹50 paid and ₹68 due, linked to the expected product and moved stock to nine once. After saving and after voiding the original, the first-invoice prompt stayed hidden.
- The browser test shop, account and verification email were removed by exact identifier after the run.

## Android

- Android commit `94a432c`. Analyzer and the full Flutter suite passed with 503 tests and 17 existing opt-in skips. The five focused tests cover setup retries, role and tenant isolation, and the lasting completion milestone.
- `flutter test --no-pub integration_test/first_invoice_onboarding_test.dart --no-uninstall -d emulator-5556` passed on the disposable emulator. Start Fresh accepted the literal name “My Shop”, opened the existing product editor, and advanced Home to the manual checkout entry point.
- Leaving checkout and re-entering restored the line item, customer and partial settlement. An injected local acceptance-write failure rolled back the invoice. Retry used the same attempt and saved exactly one invoice at ₹118 total, ₹50 paid and ₹68 due, with stock nine. Home guidance disappeared and completion persisted after reopening the database.
- The first emulator run exposed an unpaid-bill summary ink rendering assertion and a snackbar update while checkout was unmounting. The passing rerun included fixes for both. The existing Gradle plugin migration warnings remain.

Human UX review is pending. The emulator test covers the offline shop path. The web test uses a pre-activated disposable shop and the real Docker API. The separate no-shop smoke and API checks cover their respective access gates.
