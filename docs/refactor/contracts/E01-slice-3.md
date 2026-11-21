# E01 slice 3 — supplier payment intent and verified recovery

19 November 2026. Status: implemented and verified; see [evidence](../evidence/E01/slice-3.md). Scope closes E01-FOLLOWUP-01 and extends the existing production supplier-payment adapters. No theme redesign or generic sales-sync replacement.

## Versioned allocation intent

Add supplier-payment binding version 1/2 and nullable original selected-purchase UUID through an additive Alembic migration. Existing rows retain their original hash and version 1; new rows explicitly write version 2. Version 2 binds the original selection including explicit null (oldest-first) as part of the fingerprint. Same-key selected→different-selected, selected→unselected and unselected→selected changes conflict without further financial or audit effects.

Version 1 cannot prove original selection from resulting allocations. Unselected legacy replay retains original hash compatibility. Explicit-target legacy replay returns stable `legacy_payment_intent_unknown` conflict, directing review of the original supplier statement. Never generate a replacement key to bypass that conflict, infer intent from allocation amounts, rewrite historical hashes or create a second payment during recovery.

## Proof of original request

The existing typed GET operation lookup identifies a ledger/key but does not bind the caller's saved body or supplier. It is insufficient alone to acknowledge a potentially conflicting restored request. Add a no-effect supplier-payment recovery endpoint accepting the same request body and supplier scope, reusing versioned replay validation. A verified committed response identifies the existing result; not-found allows retry of the exact original body/key. Current tenant membership, admin role and premium entitlement are checked for recovery as for mutation. Legacy explicit selection remains a conflict requiring inspection.

Frozen endpoint: `POST /v1/shops/{shop}/suppliers/{supplier}/payments/recover`, same `SupplierPaymentIn`. Response: `{contract_version:1,status:committed|not_found,uuid:string|null,request_binding_version:1|2|null}`. Not-found has null UUID/version; committed has a valid result UUID and binding version. Existing create response remains `{uuid}`. Generated clients follow this additive API contract. This does not permit recovery to bypass revoked access or expose other tenants' payments.

## Mobile

An optional exact-body recovery capability keeps older purchase-only fake/backend implementations compatible. Unknown attempts first verify the original request when supported, then acknowledge a verified result or resend the exact original request after not-found. Older servers without the recovery route can receive the same idempotent POST; there is no new request identity. Permission, network, malformed-response and conflicting-intent failures retain uncertainty and the conservative balance reservation. Current state/claim and captured-shop guards remain.

## Web

Reuse browser exclusive persistence for supplier payments. Persist and verify the exact request before sending, retain legacy saved request keys, discover unresolved selected-purchase attempts under the same supplier, and fail closed on malformed or competing stored requests. An unresolved payment cannot be replaced by switching between selected-purchase and oldest-first paths. User/shop lifetime checks prevent stale network sends and draft recreation after explicit signout.

Timeout, permission loss and intent conflicts preserve frozen attempts. A restored or previously uncertain request is not proven rejected merely because a later replay receives 422; first-send validation rejection and unknown-result recovery remain distinct. Explicit signout keeps the privacy policy of clearing browser operation drafts and is not cross-session server recovery.

## Acceptance

API: populated version-1 migration/hash preservation and repeat migration, version-2 target changes, exact-body no-effect recovery, current permissions/tenant, concurrent replay and audit atomicity. Mobile: verified committed/not-found/unsupported/error outcomes and reservation reconciliation plus analyzer. Web: storage failure means no send, exact selected payload survives reload/lost response, malformed and cross-path races fail closed, authorization failures retain unknown, signout/unmount safety, generated types plus browser acceptance. Coordinator serializes live migration/restart and fixture cleanup and records Docker/emulator results.

## Cleanup-discovered lifecycle correction

Migration 0022 restores owner-confirmed whole-shop deletion for posted purchase/payment aggregates. Snapshot references remain restrictive with deferred checks; posted stock deletion remains blocked while its real parent shop exists. No per-document delete grants or caller-editable guard bypass were added. Full PostgreSQL regression and normal synthetic-shop API cleanup verified this correction.
