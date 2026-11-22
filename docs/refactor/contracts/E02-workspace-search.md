# Workspace search

Home search finds saved products, invoices and customers in the active shop. Keep the existing Home search interaction on Android and give web Home the same entry point. Open the selected record in its existing detail view. Search does not create records or navigate through checkout.

| Results | Fields matched | Order |
|---|---|---|
| Products | Name, item code, barcode, category, and supplier name for users allowed to see supplier data | Name, then ID |
| Invoices | Invoice number (including the legacy display alias), customer name and customer phone | Latest first, then invoice number descending and ID |
| Customers | Name, phone, GSTIN and address | Name, then ID |

Search uses a trimmed, case-insensitive literal substring with at most 60 characters. Treat punctuation as text. A query consisting of digits and ordinary telephone punctuation can also match a phone number with its punctuation removed. A mixed query such as `Tea50` does not match every phone containing `50`. Show up to five active records per group. Ignore drafts and deleted records. Apply existing shop membership, entitlement, and field visibility checks.

Web uses `workspace_search=true` on the existing shop-scoped `/products`, `/bills` and `/customers/accounts` list routes. Bills include saved credit notes in their existing active list. A group can show its own error and retry without erasing successful groups. Empty input sends no search requests. Android searches local records and rechecks shop and record identity before opening a result. A query or result from an earlier shop/account scope cannot appear under the next workspace.

Verify common queries against independent shop fixtures. Include a name shared across all groups, punctuation and formatted phones, more than five matching products, an unrelated shop with a matching record, staff visibility, a missing record, and navigation to the exact selected record. Run web on localhost with the Docker API and run the offline Android path on a disposable emulator. Settings search and notification routing have separate acceptance criteria.
