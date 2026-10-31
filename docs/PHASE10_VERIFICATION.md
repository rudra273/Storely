# Phase 10 — subscription enforcement

Implemented 2026-10-28 across storelyapi and generated storelyweb contracts.
The API database was migrated locally only; no production deployment occurred.

## Behavior

- Free Android remains independent of the API. Explicit cloud registration creates
  inactive identity metadata; it never grants premium or permits business upload.
- A shop's server subscription controls normal sync and business web/API access.
  Free, suspended, expired and future-start subscriptions are denied. Roles and
  tenant isolation are checked as well. Subscription state is not syncable.
- Expiry never deletes records. Renewal restores access to existing records.
  Account controls, membership removal/invite revocation, security review and
  confirmed owner deletion remain available while inactive.
- Platform developers are explicitly provisioned by a database operator. They
  must complete an MFA sign-in after the grant; existing password-only sessions
  cannot acquire platform access by enrollment alone. Revocation ends sessions.
- Platform subscription changes require expected revision and a reason. History
  commits atomically and is not editable by the runtime role. Shared business
  locks and exclusive subscription locks order in-flight work against revocation.
- New migration is additive/reapplicable. Existing subscriptions are preserved on
  reapplication; existing shops without a subscription are backfilled as free.

## Evidence

- API unit suite: 241 passed.
- PostgreSQL integration suite: 198 passed, including 11 new subscription cases
  and the existing authorization, billing, products, reports, sync and auth suites.
- New unit cases cover capability boundaries and invalid changes.
- Real TLS proxy/Mailpit smoke: signup/verify/login, free entitlement, denied
  sync pull/push, account/MFA/session controls, refresh and logout passed.
- Ruff/format, strict mypy and Bandit passed. pip-audit found no known
  vulnerabilities; Gitleaks found no leaks; Trivy production-image gate passed
  for fixed HIGH/CRITICAL findings under the existing scan configuration.
- OpenAPI and web types regenerated; web typecheck and all 89 tests passed.
- Existing business regression suites explicitly opt in to scratch-operator
  premium fixtures. New subscription tests do not receive automatic grants.
  Runtime code has no environment-based entitlement bypass.

## Remaining phases

Phase 11 adds the phone/contact premium request, pending receipt and verified
activation. Phase 13 builds the developer panel; Phase 14 integrates web/client
lifecycle UI. Pricing/device limits and business retention/recovery/export windows
remain release decisions. Inactive cloud data currently has no automatic purge;
normal business exports remain paid and personal-account export contains metadata.

`storely_pixel` is the existing Android AVD; ADB showed it was not running during
this phase. Complete app/emulator validation will follow the remaining integrated
flows as requested. No emulator end-to-end success is claimed here.
