# Android purchase composer — stage 6

Products now shows Add product and Add purchase as separate labeled actions.
Add product retains the existing quick catalog/opening-stock form. Add purchase
opens one editable composer instead of a preliminary date/supplier sheet. It resumes
the active draft for the current shop on this device. Dates default to today in
Asia/Kolkata; the picker excludes future receipt dates. Supplier is optional and can
be selected, cleared or created inline without losing staged items.

Search or scan existing product opens a searchable tracked-product list with stock,
code and barcode. Selection keeps the exact product UUID; it does not resolve an
ordinary restock by product name. The quick sheet asks for quantity received and
unit purchase cost, with optional batch/expiry. Last cost is a suggestion. Costs and
quantities accept up to four decimal places; received quantity must be positive.
The composer shows exact rounded line amounts and a sticky stock-cost subtotal.
Payment remains explicitly Not recorded.

Restocking resolves the current product by UUID inside confirmation, even if its
local row ID changed. Removed products and changed stock units/tracking stop the
whole confirmation with an actionable error. Restocking preserves current catalog
metadata, fixed selling prices and pricing formulas. Existing automatic-price behavior
continues to derive prices from weighted stock cost and configured pricing rules;
the quick sheet explains that automatic selling prices may change. It does not
silently switch pricing modes or apply a file's selling price to an existing item.

## Recovery and posting

SQLite schema 24 adds purchase_drafts, a device-local table outside generic cloud
sync. One editing draft per shop stores the date, supplier, completed line snapshots,
restock target UUIDs and imported rows. Header changes and completed add/edit/remove
operations save immediately. Returning to Add purchase restores them after navigation
or process restart. Partial input inside an open line editor is not persisted until
Add to purchase or Update line is pressed. The status label describes header and
added-item recovery, not cloud draft synchronization.

Optimistic revisions reject stale editors. Failed persistence keeps recent edits
visible, offers Retry saving draft and disables confirmation. Leaving after a save
failure requires a deliberate choice; the previous saved revision is preserved.
Discard requires confirmation and removes only the draft, without touching stock.
Owner/admin and active-shop checks protect read/save/discard/confirmation; role changes
hide the composer and quick-sheet costs while retaining saved data.

Confirmation verifies the saved revision/payload and uses that snapshot as its input.
The same SQLite transaction writes all products/restocks, receipt and posted-draft
marker. The draft UUID becomes the native receipt UUID. Replaying a posted draft
returns the original item count without receiving stock again, including zero-stock
catalog-only batches. A failed line rolls back everything and leaves the editing
draft recoverable. Posted markers are retained locally to protect lost acknowledgements.
Full SQLite backup includes drafts; they are not promised on another device.

## Import safety and remaining work

Stage 7 adds row-by-row review, explicit name-match choices, source-row provenance
and shared new-product identities for multiple lots. Reviewed source details survive
line edits and removal of other rows. See [Android import review](android-purchase-import-review.md).
Local Android duplicate warnings do not yet guarantee web/cross-device detection.
A shared fingerprint and posting protocol remain open, as do unfinished editor-field
recovery, supplier history/filtering, payments, tax/charges, attachments, and audited
corrections/returns. Opening-cost unknown semantics are unchanged.

No API or web changes, remote deployment, data backfill or device installation are
part of this stage. This build continues using the stage-5 API/migration 0016.

Validation (29 October 2026): 295 Flutter tests passed; 16 environment-dependent live
tests skipped. Analysis is clean and the debug APK builds. Dedicated tests include
12 persistence/confirmation cases and 8 composer UI cases, alongside the full
existing inventory, purchase-document, sync and billing regression suite.
