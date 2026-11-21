# E01 command foundations — accepted compatibility contract

19 November 2026. E01 establishes reusable foundations through existing routes, additive capabilities and adapters. It does not replace every command or legacy sync path with a universal endpoint. This accepted mapping supersedes the earlier universal-envelope proposal; future domain phases adopt the primitives without changing historical fingerprints.

## Identity, versions and recovery

| Boundary | Accepted current contract |
|---|---|
| Sale create | Required Idempotency-Key and validated cart/payment body, tenant-scoped shared ledger. Persist the exact body/key before send. Existing sorted JSON fingerprint preserves decimal text, including trailing zeros. |
| Bill payment/credit, customer/product/expense commands | Existing optional legacy keys remain supported; operation kind and source identity bind the shared ledger. New domain adoption belongs to E03–E10. Do not describe key omission as idempotent. |
| Purchase receipt | Required body request_key, normalized quantity/cost fields and compatible omitted defaults. Native adoption checks original immutable movement identities rather than receiving stock again. Legacy per-row sync is not universally atomic. |
| Supplier payment | Body request_key plus supplier and allocation intent. Historical binding v1 remains readable; v2 binds selected purchase including null. Exact-body POST recovery version 1 returns committed/not_found; legacy explicit-target uncertainty remains manual review. |
| Operation lookup | Version 1, explicit ledger-family selector. Current caller/tenant/entitlement authorization applies on every lookup/replay. A key-only lookup is not exact-body proof. Historic unknown result kinds remain null. |
| Product edit | Capability product_expected_updated_at:1, original frozen timestamp and atomic row-lock comparison. New web editors fail closed if capability is absent, retaining input. Legacy omitted guard remains compatible. |
| Settings edit | Capability settings_revision:1; opaque s1 counter protects coherent aggregate projection and write. Web requires the capability; mobile compares canonical persisted configuration in one SQLite transaction. These tokens are distinct adapters, not interchangeable wire values. |
| Local supplier outbox | SQLite v26 durable state/attempt timestamps; pending migration becomes unknown, sending recovers to unknown. Captured shop and exact persisted body/key bind acknowledgment. Unknown attempts reserve projected balance. |
| Server job | Actor/shop/request_key/fixed kind, database lease/fencing/retry/cancel and retention. Implemented stock_valuation_csv_v1 only. External delivery, calendar scheduling and domain-specific jobs remain E11/E13/E14. |

Capabilities version 1 advertises only implemented features; it grants no permissions. Supplier binding version 2, proof version 1, settings revision and local queue schema versions have different purposes. Clients negotiate the relevant capability rather than asserting one invented global version.

## State and transaction invariants

Persist identity/body before sending. Network failure after send is unknown. Reload/retry uses the same body/key; later 422 or safe 409 does not prove a previously uncertain request never committed. Only a first fresh definitive rejection can release an invoice attempt for correction. Malformed recovery, permission failure or unsupported proof stays frozen. A not_found proof permits exact retry, never payload mutation under an uncertain identity.

Browser invoice/supplier critical sections use Web Locks for cooperating tabs plus persistent storage checks; fail closed when durable storage cannot preserve identity. Signout retains the documented privacy policy of clearing browser drafts; this is not cross-device recovery. Full checkout drafts and held carts belong to E02.

Stock, payable allocations, source snapshots and audit effects share the actual outer transaction. PostingContext binds authenticated actor/shop/source and live transaction. JournalPostingPort accepts balanced exact INR lines on that connection; missing requested port or journal failure rolls back. E06 owns actual journal storage/accounts/periods. Offline mobile cannot promise globally serialized credit/stock across devices.

## Defaults, precision and preservation

GST registration defaults false; configured rate 18, margin/overhead 0. Default document is A4, rupee round-off enabled, title TAX INVOICE and thank-you footer; registration still controls tax treatment. Device-local thermal transport defaults 58 mm separately. Mobile now preserves persisted 58/80 mm settings during unrelated edits while its existing A4/A5 editor/rendering projection remains; E12 owns thermal output parity.

Mobile currently defaults checkout fully paid/cash; web requires explicit settlement and API omitted payment means zero/cash. E02.1 must align logical payment choice explicitly. This audit does not silently change saved invoices or claim current UX parity.

Sale quantity precision is 3 places; sale custom price 2, GST rate 3, discount 2. Purchase/catalog quantity/cost can have 4 places. Money totals use paise ROUND_HALF_UP, inclusive tax, line gross/taxable rounding, aggregate intra-state tax split and optional signed rupee adjustment. API uses Decimal/NUMERIC; existing mobile billing still uses doubles with legacy rounding. Exact adapters cover implemented purchase/payment boundaries; complete domain migration belongs to owning financial phases.

Do not impose one new hash normalizer: billing preserves decimal formatting, purchase and supplier-v2 normalize selected decimal values, native adoption normalizes timestamps to UTC. Never rehash history, reprice issued snapshots, or mistake semantic equality for safe replay compatibility.

## Independent oracle and acceptance

API tests/fixtures/financial_contract_v1.json and mobile test/fixtures/financial_contract_v1.json are byte-identical, SHA-256 f08e95e14feb65800b19065b1ca46b0f3a5e8d41661831e2f7fcc4ee26abbf60. Twelve manually derived decimal examples cover registration, GST split, fractional lines, discounts, odd paise and signed returns/rounding. Both calculators check literal expectations; generated vectors remain additional regression evidence. Public create-sale still rejects negative quantities.

See [closing evidence](../evidence/E01/closing-audit.md) and slices 1–5 for tests, compatibility and practical limits. E01 acceptance covers these foundation contracts; no advanced feature, universal sync atomicity, completed UX parity, physical printer or production deployment is implied.

## Subsequent adoption

E02.1 adds an optional paired sale settlement/review guard while preserving legacy hashes and exact old retry bodies. See [current checkout contract](E02-slice-1.md); its tested behavior supersedes the historical mobile paid-by-default observation above. This does not change E01's compatibility acceptance or imply other domains have adopted guarded commands.
