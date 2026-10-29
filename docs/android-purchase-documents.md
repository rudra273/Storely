# Android purchase documents — stage 5

Grouped purchases confirmed through Products now save an immutable receipt snapshot
in the same SQLite transaction as their stock movements. Schema 23 is additive.
A failed batch leaves neither stock nor a partial document. Zero-stock catalog setup
and non-stock products remain supported without inventing a stock receipt. Historical
movements remain legacy stock history; the upgrade does not guess old bills.

Products offers Purchase history to owners/admins. History is available offline,
paginates 50 documents at a time and shows supplier/date, original product/unit/lot
snapshots, exact line amounts/subtotal and document sync status. Costs are hidden
when admin access changes. Payment is explicitly Not recorded; subtotal does not
represent a payable balance. The selected purchase supplier, including No supplier,
is independent of a product's preferred supplier.

## Sync protocol

Existing row sync uploads dependencies and stock first. Each new grouped purchase
uses a stable UUID and tags its stock movements native_purchase with that UUID.
Only after all referenced stock is acknowledged does the phone publish the saved
header/lines through POST purchase-receipts/native. The server verifies the entire
movement group and adopts metadata without inserting stock or recalculating cost.
It refreshes only the derived product quantity cache. Lost responses replay the
original IDs/content; document download never creates stock.

GET purchase-receipts/changes supplies immutable documents from both web and Android.
A sequence allocated under the shared shop receipt lock preserves committed order,
independent of device clocks and backdated receipt dates. The phone persists its
cursor per page and safely replays pages after interruption. Sync reset clears it.
These documents use the separate whole-document protocol, outside generic row sync.

Pending/error documents remain durable and visible in sync counts. A conflict keeps
the local snapshot and offers retry; Use cloud copy cannot discard it. Rejections
can leave stock uploaded while the document needs review: document and stock sync
are deliberately separate compatibility steps. Start fresh keeps existing pending
receipts Local only rather than claiming that their stock was uploaded. Owner/admin
permissions and active shop are checked again at publication/import.

## Rules and rollout

Quantities and costs support four decimal places; finite nonnegative input is
required, with positive quantities for document lines and at most 200 batch rows.
Amounts use scaled BigInt arithmetic, round half-up per line to two decimal places
and sum rounded lines. Receipt dates cannot be future dates in Asia/Kolkata. Original
phone audit time remains device_created_at after server acknowledgement.

Deploy API migration 0016 and native/feed endpoints before distributing this Android
build. Existing API migrations through 0013 are separate pre-existing workspace work
and must be included in the actual deployment chain. No remote deployment is part
of this stage. Full SQLite backups include the document table.

Stage 6 adds Android draft recovery and the simplified existing-product composer;
see [Android composer](android-purchase-composer.md). Full import review parity,
supplier payments, tax/charges, attachments,
returns or audited corrections. Standalone legacy insert/restock paths still use
stock history. Existing posting-order cost policy is retained; historical COGS is
not recalculated. These remain explicit work in the master implementation plan.

Validation covers offline reopen, rollback, acknowledgement loss, second-device
restore, conflicting payload preservation, access changes, start-fresh behavior,
version-22 upgrades, anonymous supplier selection, zero-stock setup, transport error
classification, narrow history rendering and staff privacy. API tests cover exact
movement verification, immutable groups, replay, sequence pagination and concurrent
web/native posting.
