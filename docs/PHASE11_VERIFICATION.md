# Phase 11 — premium requests and activation

Implemented 2026-10-28 in Android and storelyapi, with regenerated web contracts.
This phase does not build the developer panel (Phase 13) or finish held/draft cart
cloud parity (Phase 12). No production deployment or Play Store upload occurred.

## Implemented flow

Store → Cloud Backup & Sync → Request Premium / View Request. No account is needed
to submit contact name, international phone, shop name/identity and contact consent.
A secure draft/receipt exists before HTTP submission and is bound to the API origin.
Offline/uncertain sends remain “Not sent”; retries reuse the same ID/body/receipt.
Business records are not included. A private status response reveals no contacts.

The team can list/review pending requests via developer-only API routes. Approval
requires an existing verified email account and dates, and binds that user's UUID.
The Android flow supports account creation/email confirmation and sign-in before
activation. Claim needs both that account and the private receipt. A copied phone
number, local UUID or receipt alone cannot claim the shop. Reviews are versioned,
MFA-protected and audited; concurrent/repeated claims activate only once.

Explicit upload consent creates a persistent private SQLite backup before claim.
Local shop UUID/profile are preserved; existing cloud registrations require
reviewed recovery instead of silent merging. A new cloud placeholder has an old
profile timestamp to avoid overwriting fuller phone fields on the first pull.
Background/auth events are gated until consent for that account. Queued dirty rows
retry through the existing sync engine. Repeat claims do not renew/suspend/resume
subscriptions. A bundled HTTPS API is required in a release build; without it the
app still works offline and does not offer a different backend.

## Validation evidence

- Flutter full suite: 238 passed, 16 skipped (live API cases require fixtures).
- Focused tests: durable before-send storage, lost-response retry across restart,
  private status, no pending-success on failed send, origin binding and matching
  local shop selection for accounts with several shops.
- API unit suite: 241 passed. Full PostgreSQL integration suite: 204 passed,
  including receipt/retry/privacy/rate limits, developer review, account binding,
  concurrent idempotent activation, no implicit existing-cloud merge and deletion
  of an approved account without transferring its identity.
- Web contract/typecheck and 89 tests passed; no developer UI claim is made.
- Flutter analyzer, ruff/format, strict mypy and Bandit passed.
- pip-audit: no known vulnerabilities. Gitleaks: no leaks. Production Trivy gate:
  no fixed HIGH/CRITICAL findings under the existing scan configuration.
- Android release APK builds successfully.

## Emulator validation — passed

The user explicitly requested deleting the locked emulator and creating a new one.
The old `storely_pixel` AVD and its local data were deleted, then a fresh AVD was
created under the same name: Pixel 6, Android 15/API 35, Google APIs arm64-v8a.
The fresh emulator boots with user state `RUNNING_UNLOCKED`.

`make test-device-premium` passed the complete native test against the local TLS
API and Mailpit. It verified:

- Actual contact/phone/consent form submission and pending status.
- Signup, email verification and approved-account sign-in with Android secure storage.
- A temporary, uniquely scoped operator reviewer fixture approves only the test
  request; the fixture is removed immediately after review.
- Approval and sign-in alone do not upload local business data.
- The actual consent checkbox and activation button create a durable SQLite backup.
- First upload preserves the local shop UUID, phone/address and product data, with
  no rejected or dirty product rows left behind.
- Repeating activation/claim does not duplicate the uploaded product.
- The screenshot is saved using Android's app-specific scoped storage, exported
  before reinstall, and reviewed. The harness uses the app's Storely theme.

The harness uses a separate SQLite filename and saves/restores app preferences and
secure keys. It keeps the APK installed for screenshot export (`--no-uninstall`).
The normal app build is restored after validation; the fresh emulator stays running.

Screenshot: [activated premium request](screenshots/phase11-premium-activated.png).

This verifies the Phase 11 native request/activation flow. It does not replace
customer review, a physical older-device check, Phase 12's full-model restore test,
or manual review of the future Phase 13 developer panel.
