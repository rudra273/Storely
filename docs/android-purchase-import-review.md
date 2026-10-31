# Android reviewed purchase imports — stage 7

Add purchase → Import file now opens a read-only review before any product or stock
is created. CSV/XLSX source rows retain their original row numbers, including blank
lines; batch and expiry are parsed alongside quantities and costs. The importer
accepts up to 200 nonblank data/error rows and files up to 5 MB. Unsupported columns
are listed so the user can see what was ignored.

Each row shows its number, item, editable quantity and unit cost, exact rounded line
total, optional batch/expiry, match and validation errors. Name-only candidates
require the user to choose an existing product or create a new one. A unique matching
code/barcode is selected; conflicting identifiers, untracked targets and incompatible
base units block that row. An invalid row must be explicitly excluded or corrected
in the source file. Quantity must be positive; quantity and cost accept up to four
places. Selected rows are added together to the existing local purchase draft.
Review choices themselves are not saved until Add reviewed rows is pressed.

Same-code/barcode rows for one new product share a staged identity and retain
separate lot, quantity and cost lines. Name-only new rows remain distinct unless
explicitly linked. Conflicting metadata for a shared new identity blocks staging or
confirmation. Editing one staged new item updates its shared product metadata while
preserving each lot, cost and source row. Confirmation creates the product once and
writes a movement per lot, atomically with the receipt and posted-draft marker.

Each reviewed line stores an import fingerprint, original row and any explicit
repeat approval in its local draft. These survive restart, edits and removal of other
rows. The stock movement carries `mobile-import-v1:<fingerprint>` and the row number;
stock history displays the row and the generic sync path uploads both fields. Receipt
line snapshots do not yet include source metadata. Older drafts without these fields
remain readable and keep their existing legacy import behavior.

## Duplicate checks and limits

The Android fingerprint is based on parsed source values and errors, ignoring file
name, purchase date, header aliases and valid-row order. A match in this device's
stock history or current draft is shown before staging and requires explicit repeat
approval. Posting rechecks unapproved fingerprints within its SQLite transaction.
The previous legacy duplicate check is retained. A fingerprint applies to the source
file even when some rows are excluded or edited, so warnings may be conservative.

This is not yet a shared web/Android duplicate guarantee: web uses a different
canonical fingerprint and server registry, and this Android path syncs stock before
publishing its receipt. Another device's unsynced purchase can also be missed. The
review screen discloses this limit. A future shared parser/fingerprint contract and
posting protocol must resolve cross-device concurrency before claiming parity.
There is no new server duplicate enforcement in this stage.

No server schema change, remote deployment or device installation is included.
The API source-sync regression uses the disposable PostgreSQL test database.
