# Premium requests from the web — 2026-10-29

Available locally at [Request Premium](https://app.storely.localhost/request-premium).
There are links in onboarding, the subscription screen and developer navigation.
Sign in with a verified account, choose the shop type, enter shop/contact name and
phone with country code, and consent to contact. Submission creates a pending
request in the existing developer queue; it does not create cloud access or charge.

## Existing Android shop

1. In the updated Android app, open Store → Cloud Backup & Sync → Request Premium.
   Copy the displayed shop code. The code is visible even without an API configured.
2. Choose **My existing Android shop** in the web form and paste that code.
3. A developer reviews the phone/contact request and approves the requesting verified
   account and premium dates. Status is available on the web under that account.
4. In an API-enabled Android build, sign in with that same account on Request Premium
   and use **Find my web request** if needed. The app matches the local shop code.
5. Confirm the backup/upload checkbox, then activate. A durable local backup precedes
   the account-bound claim and upload. Existing IDs/data and all 17 synced tables
   follow the existing restore/round-trip contract; there is no implicit merge.

An existing-Android request does not offer web activation. An offline-only Android
build can show/copy the code, but cloud activation still needs the configured API.
The ordinary Android receipt request/activation flow also remains supported.

## New shop starting on the web

Choose **A new shop starting on the web**, then submit contact details. After your
review/approval, the requester confirms **Create a new empty cloud shop** and clicks
**Activate new web shop**. The server atomically creates one shop, owner membership,
approved subscription and audit event; the web opens that shop. This option must
not be used to transfer an existing Android dataset. Replay cannot duplicate,
renew or re-enable a suspended subscription.

Already registered cloud shops still use manual developer renewal/recovery; the
first-activation form does not overwrite an existing registration. No automatic
subscription payments or renewals were added.

## Account safety and retries

Backend migration 0013 adds source/kind/requester fields to private request metadata.
Web requests are tied to the authenticated UUID; developer approval cannot assign a
different account. Android receipts retain their separate possession proof. Web
receipts/tokens are never placed in browser storage or URLs. Own status now includes
pending/contacted/rejected web requests, while Android-origin pending requests stay
private to their phone until account approval. Phone is contact information only.

The form retries the same UUID/body after an uncertain response. A refresh recovers
accepted status through the account. The backend serializes account submissions,
allows one open web request per account and one live request per shop, and enforces
fingerprints and account/IP/hashed-phone rate limits. No business data is uploaded
by submitting or approving a request.

## Verification

- Web: **116 tests**, typecheck, lint and production build pass; cases cover both
  modes, contact validation, explicit consent, lost-response retry identity and
  confirmed activation limited to approved new-cloud requests.
- API: **252 unit and 220 PostgreSQL integration tests** pass, including ten new
  web-request cases: private pending status, spoofed fields/account, immutable retry
  body, conflicting submissions, requester-bound review, wrong mode/code/account,
  atomic/idempotent activation, suspended replay and migration reapplication.
- Mobile: **254 tests pass, 16 live tests skipped**, analyzer clean; a new secure
  draft case covers account/shop-scoped web import without anonymous receipt calls
  or premature upload authorization.
- Real Chromium `make test-web-premium` passes UI submission → pending developer
  queue → readonly requesting-email review → explicit new-web activation → paid
  workspace, and existing-Android submission/approval with no web activation button.
- Native `make test-device-web-premium` passes web-origin API submission → matching
  Android request discovery → backup/consent → claim/upload → all-table clean restore
  and mobile/API round trip. `make test-device-premium` also passes the original
  Android-origin request flow. These use one emulator with independent SQLite
  databases/device UUIDs, not two physical phones. An initial local compiler-startup
  hang was repaired before the successful runs; the test scrolls the consent form.
- Dependency, secret and production-image checks pass; generated API types match.
  The updated schema passes the 38-table consistent backup/restore drill.
- Temporary web fixture accounts, requests and shops were removed; real developer
  accounts/MFA were not changed by these tests. Production deployment remains deferred.

Screenshots (temporary development fixture data):
[activated web workspace](../../storelyweb/docs/screenshots/web-request-activated.png),
[Android request approved on web](../../storelyweb/docs/screenshots/web-request-android-approved.png),
[Android activation](screenshots/web-premium-android-activated.png).
The browser screenshots were visually inspected.
