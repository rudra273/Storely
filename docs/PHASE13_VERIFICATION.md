# Phase 13 verification — 2026-10-28

The developer console is available locally at
[app.storely.localhost/platform](https://app.storely.localhost/platform).
It is independent of shop onboarding and includes:

- KPI overview with definitions and timestamps.
- Premium request queue: contact/phone/consent, pending/contacted/approved/rejected/
  activated filters, verified-owner approval intervals and review reasons.
- Searchable, paged shop metadata and effective subscription status.
- Explicit grant/renew/extend/resume intervals, suspend/expire actions, reason,
  confirmation and optimistic revision checks.
- Append-only audit history, optionally filtered by shop, with actor UUID and
  safe before/after state. No product/customer/bill inspection or impersonation.

## Access

Use an existing verified developer account or create/verify a dedicated account.
An operator provisions it from the API repository:

```sh
docker compose run --rm migrate python -m scripts.platform_admin grant EMAIL
```

Open `/platform/account/security`, enable two-factor authentication, save recovery
codes, then sign out and sign in again. A password-only session cannot open the
console. To revoke the grant and its sessions:

```sh
docker compose run --rm migrate python -m scripts.platform_admin revoke EMAIL
```

No production developer account or bundled password was created by this phase.

## Evidence

- API: 251 unit tests and 209 real PostgreSQL integration tests passed, including
  endpoint authorization inventory, all three shop roles denied metadata access,
  password-only sessions denied, exact safe DTO fields, stale-revision rejection,
  business-access isolation, sync timestamp recording, revocation, subscription
  state filters and additive migration 0011 reapplication.
- Web: 97 tests, TypeScript, lint and production build passed. Regression tests
  cover login destination, access denial without shop queries, KPI definitions,
  request review payloads, subscription confirmation/concurrency, empty/error/
  retry/filter states and filtered read-only history. Generated types match OpenAPI.
- The final web image scan identified CVE-2026-116587 in go-jose/v4 4.1.5.
  The pinned Caddy build now uses 4.1.6 (`v2.11.7-storely.2`); the rebuilt
  production image passes the high/critical scan.
- API/web security: dependency audits, secret scans and production-image
  high/critical vulnerability gates passed; API Ruff, strict mypy and Bandit pass.
- Real Chromium against local TLS proxy/React/API/PostgreSQL/Mailpit:
  `make test-platform-console` in the API repository passed all steps. Browser
  UI exercised actual MFA enrollment and recovery-code sign-in, review approval,
  subscription suspend/resume and audit history. A separate owner API session
  claimed the approval, then verified business access changed from 403 to 200.
  Android activation itself was verified in Phases 11–12.
- Screenshots were visually inspected. They show development fixture data:
  [overview](../../storelyweb/docs/screenshots/platform-overview.png),
  [shop metadata](../../storelyweb/docs/screenshots/platform-shops.png),
  [audit history](../../storelyweb/docs/screenshots/platform-history.png).
- Unique temporary fixture accounts/grants were removed after the browser run;
  a database check confirmed zero remaining fixture developer/owner accounts.

## Limits and next phase

KPIs count non-deleted registered API shops; offline-only installs are unknown.
Active requires an effective interval, scheduled means before start, and suspended
status takes precedence. Backlog includes pending/contacted requests; oldest means
earliest submission. Expiring counts active intervals ending in seven days. Recent
sync counts distinct shops with a completed pull or a push without rejected rows
within 24 hours. This activity starts with migration 0011; it is not historical
backfill, browser activity, uptime/error-rate monitoring or revenue tracking.

The browser harness grants only its exact UUID-tagged test account using a local
operator fixture; it does not add a runtime approval bypass. No shop business
policies are widened. Customer review and production deployment remain. Phase 14
will integrate paid web access/lifecycle states and broader cross-device workflows.
