# Phase 14: Paid access and lifecycle verification

Implemented paid web guards and lifecycle status, with Android transport preflight.
The offline Android release remains independent of backend deployment.

The web loads shop entitlement before mounting business screens. Free, expired,
suspended and scheduled shops see subscription/activation instructions. Owners can
arrange manual renewal for the existing shop; staff are directed to their owner.
There is no new free cloud-shop creation form, automatic payment or automatic
renewal. Account/security/deletion remains reachable without shop access.

Entitlements refresh on shop/role change, focus, minute polling, server rejection
and server-relative subscription boundaries. Business queries are cancelled/removed
on access loss or switching shop/role. A failed check closes business views. A
removed member's roster refreshes, while role denials refresh the current role.
Account-bound request status contains only approved/activated requests; pending
phone requests remain private to their receipt until approval binds an account UUID.

Android checks cloud capability before registering a device or importing/uploading
records. An inactive plan pauses sync and retains local bills, IDs and dirty rows.
The owner's role remains usable for local work; renewal resumes the same queue.

## Completed checks

- Flutter: **253 passed, 16 live tests skipped**, analyzer clean. New cases exercise
  all four inactive states with the real API transport, real SQLite and a fake sync
  server, then renewal/idempotent billing upload. Existing interruption, conflict,
  stock/payment, migration and clean restore coverage remains.
- Native Android: the real request/activation/17-table clean restore and mobile/API
  round-trip test passed on `storely_pixel` against local TLS API/PostgreSQL. The
  emulator briefly disconnected on the first attempt; a reconnected rerun passed.
  It models two device identities using independent SQLite files on one emulator.
- API: **252 unit and 210 PostgreSQL integration tests passed** after the local
  observability additions. The new account-status test proves pending/unrelated
  account isolation, safe fields, approved/activated state and access on expiry.
- Web: **108 tests**, TypeScript, lint and production build passed. Cases cover all
  inactive states, server-clock expiry, renewal, shop switches, denial handling,
  failure/retry, account security without shop calls and activation guidance.
- Real Chromium: `make test-subscription-lifecycle` passed developer MFA/review,
  approved owner claim, active owner catalogue, suspension blocking requests,
  account-security access while paused, elapsed expiry, renewal preserving the
  original product, and revoked staff losing their workspace. The final bounded
  load run also exercised premium rejection through a live catalogue search,
  closing the page without a reload. Temporary users/grants were removed.
- API and web dependency/secret/production-image gates passed; generated OpenAPI
  types match. API Ruff, strict mypy and Bandit pass.

Screenshots (development fixture data):
[active](../../storelyweb/docs/screenshots/lifecycle-active.png),
[suspended](../../storelyweb/docs/screenshots/lifecycle-suspended.png),
[expired](../../storelyweb/docs/screenshots/lifecycle-expired.png),
[revoked staff](../../storelyweb/docs/screenshots/lifecycle-revoked-staff.png).
The suspended/expired screens were visually checked.

## Limits and outstanding acceptance

Renewal is a developer subscription update following contact with the Storely team;
there is no self-service payment/renewal request workflow. Request approval status
is historical and never itself grants access. No expiry job deletes cloud/local
records. Commercial retention/export/recovery promises remain to be agreed.

Revoked staff are denied by the API; copies already downloaded to an offline phone
cannot be remotely erased. Cached-data/sign-out/revocation policy still needs review.
The native test verifies restore/round trips; inactive-plan queue behavior is tested
with SQLite/API transport fixtures, not a physical second phone or mobile production
backend. Customer invoice-layout/real-printing review, older physical-device upgrade
and production lifecycle checks remain before premium release acceptance.
