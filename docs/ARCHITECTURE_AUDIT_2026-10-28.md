# Architecture audit and premium delivery specification

Date: 2026-10-28. Scope: source inspection of Storely, storelyapi and storelyweb.
This is a planning audit, not a runtime certification. No application code was
changed and no test suites were run in this pass. Existing test files and past
phase results are evidence of prior work, not a fresh successful test run.

## Verdict

**Partially implemented.** Android and web have an own-API path, and Android has
local-only operation. Supabase is still a functional Android option. Paid access,
premium requests and a platform developer console are not implemented in the
inspected application routes, schemas or screens. The earlier migration plan
intentionally kept Supabase and deferred subscriptions/admin; that no longer
matches the user's 2026-10-28 requirements.

## Confirmed requirements

- Free Android runs independently, without account, API availability or business
  data uploads. Its data stays on the phone unless the user explicitly exports it.
- Premium adds Storely cloud and the shop-owner/staff web UI, through our API.
- Android must contain no Supabase SDK, executable backend, configuration form,
  fallback or user-selectable Supabase option.
- All premium business data must have a durable backend representation and a
  tested restore path, including products, billing and store configuration.
- Android has a Request Premium action with a required contact phone number.
  Requests appear as pending for the Storely developers to manage.
- A separate developer console lists shops, manages subscriptions and displays
  platform KPIs. It must not expose shops' product details.
- This task updates the plan only; implementation begins in subsequent phases.

## Current implementation and evidence

Paths below are relative to the named repository.

| Requirement | Finding | Source evidence |
|---|---|---|
| Independent free Android | Local setup saves directly to SQLite; sync exits without backend/user. Good foundation, but no explicit free/premium lifecycle yet. | Storely: `lib/screens/welcome_screen.dart` `_saveShopName`; `lib/services/cloud_service.dart` `_sync`; `lib/db/database_helper.dart` |
| Android → API | Implemented as an available mode; not the sole backend. | Storely: `lib/services/api/api_sync_backend.dart`, `lib/services/cloud/api_cloud_backend.dart` |
| Remove Supabase completely | **Fails.** Dependency, backend implementations, saved configuration and fallback remain. | Storely: `pubspec.yaml`; `lib/services/cloud/supabase_cloud_backend.dart`; `lib/services/sync/sync_backend.dart` contains `SupabaseSyncBackend`; `lib/services/cloud_service.dart` `CloudBackendMode`, `saveConfig`, `_createBackend`; `lib/config/cloud_defaults.dart` |
| No Supabase setup UI | **Fails.** Welcome and cloud settings expose URL/key fields and advanced own-Supabase controls. | Storely: `lib/screens/welcome_screen.dart`; `lib/screens/store/cloud_setup_sheet.dart` |
| Accurate cloud messaging | **Fails.** Privacy screen still says Storely does not operate the cloud and users configure their own Supabase. | Storely: `lib/screens/privacy_policy_screen.dart` |
| Web → API | Implemented; inspected source has no Supabase client integration. | storelyweb: `src/api/client.ts`, `src/App.tsx` |
| Android/web shared business data | Existing sync and REST use the same PostgreSQL business tables. This is eventual synchronization, not an instant realtime guarantee. | storelyapi: `app/sync.py`, `app/products.py`, `app/billing.py`; Storely: `lib/services/sync/cloud_sync_engine.dart` |
| Premium-only cloud/web | **Missing.** Sync authorization checks membership/role; there is no subscription entitlement check. Web checks authentication/shop/role only. | storelyapi: `app/routers/sync.py`, `app/shops.py` `require_role`; storelyweb: `src/components/guards.tsx`, `src/shops/ShopGate.tsx` |
| Premium request + phone + pending queue | **Missing.** No matching request schema, API route or app flow found. Android's `pricing_screen.dart` is product/GST pricing, not subscriptions. | Storely: `lib/screens/pricing_screen.dart`; storelyapi: `app/main.py`, `app/routers`, `migrations` |
| Developer console | **Missing.** Existing web team/activity screens are scoped to shop owners/admins, not platform developers. | storelyweb: `src/App.tsx`, `src/pages/Team.tsx`; storelyapi: `app/main.py` |
| Every business record backed up | **Incomplete.** Fifteen tables are connected to sync, but held/draft carts are explicitly excluded. No exhaustive field parity certification was performed. | Storely: `lib/db/database_schema.dart` `_createHeldBillTables`; `lib/db/database_sync.dart`; storelyapi: `app/sync.py` `SYNC_TABLES` |

## Data coverage and contract

Both sync lists contain these 15 tables (including `shops`):

| Domain | Existing cloud representation | Required follow-up |
|---|---|---|
| Store identity | `shops` | Round-trip all profile fields and preserve shop identity on upgrade. |
| Business/pricing configuration | `app_settings`, `bill_settings` | Audit every persisted setting; logo is currently `shop_logo_base64` in bill settings. Test size limits. |
| Catalogue/reference | `categories`, `units`, `suppliers`, `products` | All fields, relationships, soft deletes, GST and price precision. |
| Customers | `customers` | Contacts, opening dues and derived balances. |
| Billing | `invoice_series`, `bills`, `bill_items`, `bill_payments` | Snapshots, credit notes/returns, cancellations, numbering, payment history. |
| Inventory/purchases | `stock_movements` | Validate purchase details and UUID relationships; no separate purchase-document sync table currently exists. |
| Expenses/audit | `expenses`, `audit_log` | Inclusion exists; verify full restoration and role restrictions. |
| Held bills and draft carts | Local `held_bills` only | Add durable cloud model, stable UUIDs, ownership and conflict/claim rules. No duplicate checkout on two devices. |
| Users, members, invites, devices | Server auth/shop tables | API-managed control data; do not blindly copy credentials to SQLite sync. |
| UI preferences | Some stored in SharedPreferences | Inventory theme/language/dashboard/KPI choices; define portable preference backup separately from shared business settings. |
| Device/runtime state | Local sync cursors, dirty flags, printer pairing, app lock and token storage | Keep device-specific secrets/config local; these are not business records to share across shops/devices. |

“Same models” means a common semantic/API contract, not identical physical tables.
SQLite uses integer IDs and cloud uses UUID relationships. `_toCloudMap` and
`_fromCloudMap` already translate these. Stock caches are rebuilt from the ledger;
per-device invoice sequences must not be overwritten by another device's counter.
Use shared fixtures for money, tax, timestamps, nulls, relationship identity and
cancel/delete behavior. Make a field-level mapping manifest and fail contract
checks when a new business field lacks a cloud mapping or documented derivation.

## Target behavior

### Free, premium and expiry

Free: SQLite only for business operations, no mandatory login or network calls.
Requesting premium is an explicit, limited online action that sends contact and
shop-identification metadata, not catalogue, customer or billing records.

Premium: Android keeps SQLite for offline work and synchronizes all business data
to the Storely API; web uses that API and database. The backend is the shared
cloud authority; locally queued changes can be newer until accepted. Show pending,
failed and complete sync status honestly. Never describe queued data as backed up.

Proposed entitlement unit: **shop**, shared by its authorized owner/admin/staff
and registered devices. Membership permissions remain separate from payment state.
An owner/admin role must not imply platform-admin privileges or paid access.

Proposed expiry behavior: stop normal cloud sync and shop web access on expiry or
suspension, retain local data and allow the owner's free offline workflow. Preserve
unsynced changes for renewal. Keep account, request/status, renewal and controlled
export/deletion/recovery access available as appropriate. Removing a staff member
must not grant that person owner-level editing rights through an offline fallback.
Define cached-role/offline access limits explicitly before implementing expiry.
Never wipe local/cloud data merely because a subscription expires. Cloud retention
and a recovery/export window need a product decision before release.

### Premium request flow (proposed implementation)

1. Free app shows Request Premium in Store/cloud settings; no bottom-nav redesign.
2. Require contact name, phone with country code, shop display name, contact consent,
   and existing local shop UUID. Keep email/password optional at request time.
3. Submit a minimal request with an idempotency key. Validate and rate-limit on the
   API. Offline submissions stay visibly “Not sent”; pending means server accepted.
4. API returns request ID plus a high-entropy receipt secret for private status
   lookup; hash the secret server-side, store it securely on Android, never use
   phone number alone to retrieve or claim a request.
5. Developers see pending requests, phone, age and contact/review notes. Actions:
   mark contacted, approve, reject, with a reason and append-only action history.
6. Approval records an offer/authorization; activation binds a verified owner
   account to the correct shop and sets explicit subscription start/end dates.
   Phone is for contact, not phone OTP login. Existing email/password auth remains.
7. Authenticated, single-use claim binds the request and local shop UUID to the
   verified owner. Never infer ownership from a supplied shop UUID or phone number.
   Lost-device recovery uses account verification or reviewed recovery.
8. Only activation permits the initial business upload. Show an explicit upload
   preview/consent, preserve local IDs/UUIDs, backup before any merge, and resume
   partial uploads without duplication. Never silently choose “start fresh.”
9. Repeated taps/retries cannot create duplicate pending requests, duplicate shops
   or duplicate subscription activations. Define audited resubmission after rejection.

### API/control-plane additions (proposals, not existing endpoints)

- `premium_requests`: local shop UUID, contact fields, consent timestamp, status,
  submitted/updated/reviewed times, receipt hash, reviewer and optional bound shop.
- `shop_subscriptions`: shop, plan, status, starts_at, ends_at, revision; constrain
  to one current entitlement per shop. History stored separately/append-only.
- `platform_admins`: explicit developer membership, revocation, separate privileges.
- `platform_audit_events`: actor, action, reason, safe before/after state, timestamp.
- Request submission/private status/claim endpoints; authenticated own-shop
  entitlement endpoint; `/v1/platform/*` request/shop/subscription/KPI endpoints.
- Server-side entitlement dependency covering sync pull/push and every business
  REST read/write/report/export/device path. Account/control/recovery exceptions
  must be individually enumerated; do not gate the entire auth API.
- Deny by default and evaluate server time/status, not a client flag or stale token
  claim. Both REST and sync must enforce the same rule. Subscription changes and
  in-flight writes need transactional ordering and revocation tests.
- Pending local-only requests must not become full cloud business shops until
  verified activation. Web onboarding must not bypass this boundary via create-shop.

### Developer console

Use a separate `/platform` area with its own layout and API authorization in the
existing React repository initially. It is not the shop “admin” role or a hidden
menu in the owner dashboard. A later separate deployment is optional.

Screens:
- Overview: platform KPIs with period/timezone and clear definitions.
- Shops: search/pagination, ID/name, owner contact, creation date, plan/status,
  expiry, member/device counts, last successful sync. Metadata only.
- Premium requests: pending/contacted/approved/rejected queue, contact phone,
  submission age, reviewer, notes and activation status.
- Subscription detail: grant, extend, suspend, resume, expire/cancel with effective
  date, required reason, confirmation and history. No payment gateway in this phase.
- Platform audit: who changed which subscription and when.

Access: bootstrap developers through a controlled server-side process, never
public signup or a shop role. Require MFA for platform access, revoke sessions
when permissions are removed, and test shop-user denial on every platform route.
Use narrow metadata queries/DTOs and bounded privileged DB functions or separate
least-privilege control-plane access; do not give the public request connection
unrestricted tenant-table access. Do not add impersonation, catalogue browsing,
customer/bill inspection or business-data export to this console.

Initial KPIs and definitions:
- Registered cloud shops (excludes unregistered offline installations).
- Active premium shops (status active and current time within entitlement dates).
- Pending requests and oldest request age; approvals/activations by period.
- Expiring within 7/30 days; expired/suspended shops as separate counts.
- Active cloud shops in last 7/30 days, based on defined successful API activity.
- Sync success/error rate and last success: requires server telemetry; distinguish
  an accepted push/page from a completed whole-device synchronization.
- API error/latency aggregates, when instrumentation is available.
- Revenue/MRR only after actual price/currency/payment records exist; otherwise
  display unavailable. Subscription counts are not payment evidence.

**Visibility limit:** there is no reliable list/count of all free offline shops.
The console can show cloud-registered shops and explicit request contacts only.
Do not introduce background registration/telemetry merely to inflate this KPI.

## Delivery and verification

Master phase order is in `../plan.md` (Phases 9–15). The following are required
acceptance scenarios, not claims that tests already pass:

- New install in airplane mode: setup, catalogue, billing, expenses and restart.
- Release artifact/source/dependency scan: no Supabase SDK, keys/config UI,
  fallback routes or startup call; old preferences cannot reactivate Supabase.
- Old installation upgrade: preserve SQLite, reject legacy backend reconnect,
  clear only obsolete cloud credentials and present safe API onboarding.
- Direct API attempts by free/expired/suspended users fail, including sync,
  create-shop bypass, reports, billing, catalog and alternate web routes.
- Request offline/retry/duplicate/status secrecy; approved request cannot be
  claimed by another person; activation is idempotent and audited.
- Existing free shop with all data → activation → complete upload → web read/edit
  → Android pull → restore onto another phone. Compare every business field.
- Interrupted upload, partial rejection, two-device edits, clock skew, deletion,
  double checkout, bill-number collision, downgrade/renewal and staff revocation.
- Developer operations do not disclose product/customer/bill details; ordinary
  owner/admin/staff cannot access platform routes or elevate their privileges.
- Apply existing security gates, update threat model and API contract, regenerate
  web types; run relevant Flutter/API/web tests and device checks in each phase.

## Decisions to settle before the affected implementation

Recommended defaults above keep this plan actionable; these are not invented
commercial commitments: per-shop pricing/duration/device limits; exact contact
fields beyond mandatory phone; expiry retention/export window; staff offline
revocation policy; portable UI preferences; developer accounts. Automatic payments
and OTP login remain later work. Existing legacy Supabase usage/data must be
verified before any shutdown: old docs contradict each other on whether real
cloud data exists. Removing the SDK does not authorize deleting a remote database.
