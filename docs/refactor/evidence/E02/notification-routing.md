# In-app notification routing verification

Run date: 22 November 2026. [Acceptance contract](../../contracts/E02-notification-routing.md).

- Web commit `648d990`. Typecheck, lint, build and 652 tests passed. The browser test used disposable shops and accounts, which were removed after verification.
- The localhost browser ran against the live Docker API. A ₹118.25 balance at 31 days appeared in the overdue report and the ₹89.50 balance at 30 days was excluded. The expiry alert opened the existing seven-day stock report and included a batch expiring on day seven. The browser also verified independent retry, no alerts in the empty second shop and no report requests from a staff account.
- `make test-platform` passed the production web build and disposable Docker bootstrap, TLS, frontend proxy and route smoke tests. The alerts use existing report endpoints and require no API schema change.
- The Android emulator opened the filtered overdue and seven-day expiry reports and the existing backup and sync sheets. An account transition exposed a missed alert refresh in the first run. The corrected run refreshed the alerts and hid the sync sheet contents after role revocation. The test opened the backup sheet without restoring a file.
- Six focused Flutter tests verified exact paise, overdue age buckets, the inclusive expiry window, shop isolation, suppression for staff, stale taps and a rejected stale stock adjustment. The analyzer passed.
- Android commit `257fdaf`. The full Flutter suite passed 521 tests, with 17 opt-in skips.

## E02 exit review

The sales checkout no longer uses the generic expiring draft helper. The dedicated invoice store retains meaningful older drafts, preserves saved work after a storage failure, refuses conflicting tabs, and protects an unconfirmed request from replacement or clearing. `npm test -- --maxWorkers=2 src/billing/checkout/invoiceDraftStore.test.ts src/billing/Billing.test.tsx` passed 122 tests. The generic draft helper still serves product forms.

Android process-kill and relaunch passed in the subsequent [checkout acceptance](slice-2.md). Human UX review remains open.
