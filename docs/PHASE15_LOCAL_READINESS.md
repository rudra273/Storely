# Phase 15: Local readiness completed; production gates remain

Backend deployment/connection remains deferred. This phase has local evidence and
operational guidance, not a production go-live declaration.

Implemented and verified:

- A consistent snapshot/restore drill covering **38 business/control tables** with
  matching row counts/content, matching RLS policy definitions and anonymous
  runtime-role denial. The original database is read-only during capture, scratch
  data/dump is removed, and a local Unix Docker context is required. Evidence:
  [restore report](../../storelyapi/docs/local_restore_drill.json).
- A bounded local TLS load exercise: **100 authenticated reads**, concurrency **4**,
  **zero failures**, **55 ms p95**, 114 ms maximum in the recorded run. It includes
  metadata/catalogue reads against one fixture shop, not sustained writes/sync or
  a production capacity/SLA claim. Evidence:
  [load report](../../storelyweb/docs/screenshots/local-load.json).
- Generated request IDs and structured method/route-template/status/response-header
  latency logs, excluding raw paths/queries/bodies/credentials. Raw Uvicorn access
  logging is disabled; tests verify safe correlation and template-only logging.
- Disposable production-container verification passed: fresh bootstrap, repeat
  migrations, verified DB TLS, platform ports, frontend/API proxy, SPA deep links,
  security/cache headers, unsafe runtime-login rejection and legacy-schema refusal.
- API/web dependency, secret and production-image scans passed. API unit/integration
  totals are 252/210; web totals 108; mobile totals 253 with 16 live tests skipped.

The recorded restore took approximately 4.3 seconds on the local populated database;
this is a same-cluster scratch restore using existing roles, not a provider disaster
recovery time objective. The private temporary dump is not a production encrypted
backup or off-site/PITR system. Request latency is to headers; the load report times
full local responses. Neither substitutes for real monitoring/alert delivery.

See [operations and cutover gates](../../storelyapi/docs/OPERATIONS.md) for commands
and the production checklist. Still required:

- Hosting/database/domain/email decisions and actual TLS/routing/cookie checks.
- Provider encryption/backups/PITR and an isolated provider recovery rehearsal.
- Real monitoring destinations, alert delivery and production-like sustained load.
- An independent security review, staff offline/cached-data policy and approved
  retention/export/recovery and commercial subscription rules.
- Legacy remote-data inventory/migration before any old-service shutdown.
- Customer invoice/real printing review, older Android upgrade test, correct Play
  signing identity and staged release review.

No production service, remote Supabase project, business record or subscription was
removed. No real developer credentials were provisioned; test grants were cleaned
up. Offline Android can be released separately after its remaining release checks,
with no bundled API URL and no cloud availability promised.
