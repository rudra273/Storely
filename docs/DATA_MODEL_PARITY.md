# Business-data parity

The authoritative field inventory is [sync_data_contract.json](sync_data_contract.json).
It classifies every column in the real SQLite schema: 17 row-synced tables, 346 row-sync columns,
31 nested cart-item fields, and nine portable preference keys. Its matching API
fixture is checked against PostgreSQL columns, money types, private validators and
public-table inventory. Adding an unclassified table or field fails the checks.

Models share business meaning and UUID identity. SQLite integer row IDs are local:
relationships travel as UUIDs and resolve to new row IDs during restore. Bill-line
and cart snapshots retain their prices, discounts, tax, units and product identity.
Stock derives from movements; payment summaries derive from durable payments;
customer aggregates reconcile from bills when customer data loads. Invoice counters
remain device-specific and a restored device registers its own invoice letter.

Schema 23 also has a separate purchase_documents snapshot table. Its nine columns
are classified under document_tables in the manifest. Whole purchase headers/lines
use the native publication and sequence-feed APIs, outside generic row sync; see
[Android purchase documents](android-purchase-documents.md). Downloading a document
never inserts stock. Schema 24 adds a six-column device-local purchase_drafts table,
classified under local_draft_tables. Its posted marker commits with stock so draft
recovery cannot post a purchase twice; see [Android composer](android-purchase-composer.md).

Coverage includes shop profile/logo/signature/bank/footer, settings, products,
categories, units, suppliers, customers, bills/items/payments, stock movements,
expenses, audit, invoice series, held/draft carts and portable preferences.

Carts have immutable account and origin-device ownership. Only the origin device
can resume/consume a live cart, atomically, leaving a sticky tombstone. A different
device can inspect restored held/draft snapshots, but cannot resume or delete them.
This avoids accidental duplicate checkout; it does not provide remote cart handoff.

Portable preferences are language, theme, billing search mode, home section
counts/sort/visibility and enabled analytics KPIs. Account-specific preferences and
carts require current membership and matching account identity on the server and
client. Other members do not receive them. Local printer pairing, app lock,
credentials, premium receipts, backup runtime, sync cursors and device identity
are excluded. API-managed membership/invite/device/counter/idempotency tables and
migration metadata are listed separately from mobile business models.

Run `flutter test test/sync_data_contract_test.dart` to verify the reviewed
manifest. After intentionally reviewing schema changes, regenerate with
`STORELY_WRITE_CONTRACT=1 flutter test test/sync_data_contract_test.dart`, then run
API `bash scripts/integration-tests.sh tests/test_complete_sync.py` to verify the
matching server fixture. Regeneration writes the sibling API fixture when present.
