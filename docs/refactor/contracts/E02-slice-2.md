# E02.2 — Recoverable checkout and held invoices

Status: implemented and verified on 20 November 2026. See the [acceptance evidence](../evidence/E02/slice-2.md). Builds on [E02.1 settlement and reviewed saves](E02-slice-1.md).

Mobile currently stores item snapshots, while customer, discount and settlement entries live in the checkout sheet. The existing hold and resume paths depend on separate writes that leave a gap where the restored active cart can be duplicated or lost. Web stores one active draft with most invoice fields, but lacks hold and resume. Its age limit can drop an editable draft on reload.

## Expected behavior

- Preserve the active cart and raw checkout inputs across close and reopen, reload, or restart. Invalid or incomplete input stays visible for correction. After restoring a changed pricing context, keep entered details and require review and a new settlement decision. Restore unassigned credit consent only when the reviewed details still match.
- Hold saves the complete editable draft and opens a clean checkout. Resume moves the selected held draft to active. If the current checkout contains work, the same operation holds that work. A failed write leaves both drafts available. Discard is explicit and only affects the selected draft.
- Scope writes to the captured owner, shop and originating device or browser. Reject stale writes from another editor. Ordinary drafts do not disappear based on age. Browser signout retains its existing customer-data clearing behavior.
- An uncertain save keeps its original identity and exact request. It cannot move into a fresh editable draft. Matching acceptance consumes the originating draft atomically with the invoice on mobile. Web continues recovering its committed invoice with the original key after reload.

## Compatibility

Mobile preserves the existing item-only held backup format. Checkout fields, revision and retry metadata are device-local. Existing cloud backups can still be read and foreign-device backups remain read-only. Holding or resuming creates or replaces rows and tombstones the prior row in the same transaction so immutable cloud provenance remains valid. Desktop web keeps its existing browser storage ownership and lock protocol and reads old active drafts. E02.2 does not add transfer of editable drafts between devices.

## Verification

Use isolated data for reload/restart, hold, swap, discard, storage failure, stale-editor and committed-retry tests. In both paired clients, posting a resumed ₹118 invoice after recording ₹50 must leave ₹68 due, and draft operations alone must leave stock unchanged. Run the relevant contract and legacy restore tests, then verify browser and Android emulator behavior. Record any remaining scope gaps before beginning E02.3.

## Storage and ownership details

Browser work is stored under the account and shop in the current browser. The held list is capped at 20 and uses a shared record with the active draft. Capacity failures leave both the active form and saved held drafts intact. A newer review context resets settlement and consent. If a stored legacy draft lacks a review context, the first preview asks for settlement again while retaining the entered values.

Mobile restores the cart and reopens its saved checkout fields when the cashier enters checkout. A pending request has a dedicated recovery action. Full SQLite backups retain the device-local draft state with its original cart. Portable cloud restore brings back the legacy item snapshots. On first account binding, the current shop's genuinely local editable cart can move to that account with fresh settlement review. An unresolved local save or a draft belonging to another local shop blocks attachment until resolved in its original context.
