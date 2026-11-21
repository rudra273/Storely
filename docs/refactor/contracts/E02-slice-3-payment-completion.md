# E02.3 payment methods, cash change, post-save continuation and step metadata

Status: payment and completion scope implemented and verified. See [acceptance evidence](../evidence/E02/slice-3-payment-completion.md).

The billing checkout and invoice payment flows across API, web and mobile share the same payment-method set, counter-only cash change behaviour, post-save continuation actions, and local draft recovery guarantees while preserving the existing screen layout and free offline mobile checkout.

## Acceptance boundaries

1. **Canonical billing payment methods (`F01`)**:
   - All billing checkout and payment-recording flows support the five canonical codes and labels: `cash` (`Cash`), `upi` (`UPI`), `card` (`Card`), `bank` (`Bank transfer`), and `online` (`Online`).
   - Unpaid checkout (`paid_amount == 0`) normalizes stored bill `payment_method = 'cash'` and `payment_reference = null` and creates no payment record.
   - Cash payments (`method == 'cash'`) normalize `payment_reference = null` at both client submission and API `add_payment` persistence, even if a cashier previously typed a reference under a non-cash method before switching to `Cash`.
   - Full cash checkout (`paid` / `full` with `method == 'cash'`) offers an optional counter-only `Cash received` input (persisted in draft `raw.cash`). When the entered value is a valid 2-decimal rupee amount strictly above the invoice total, the UI displays `Change to return` computed in exact paise (`cashPaise - totalPaise`). `Cash received` never alters persisted `paid_amount`.
   - Non-cash paid or partial checkout (`method in {'upi', 'card', 'bank', 'online'}`) offers an optional `Reference` field (`maxLength: 100`, persisted in draft `raw.reference`) and displays the non-collecting hint noting that Storely records the method and reference on the invoice rather than collecting payment itself.

2. **Post-save completion summary and continuation (`T18`)**:
   - After an invoice is saved, Web and Mobile display the saved bill number, customer context, accurate settlement summary (`Total`, `Received`, and `Balance due` / `Balance`; Mobile displays accurate `Paid`, `Partial`, or `Unpaid` status rather than treating partial as `Unpaid`), and continuation actions.
   - Continuation actions let the cashier:
     - Start a **New invoice** / **New Bill**, clearing cart, draft, settlement choice, payment method, `Cash received`, `Reference`, and any prior `duplicateFromBill` lineage so the next invoice starts unsettled and clean.
     - **View invoice**, opening the saved invoice details (`navigate('/billing/:uuid')` on Web; `showBillQuickSheet` on Mobile).
     - **Print** / **Share PDF** (and thermal **Print Receipt** when configured on Mobile).

3. **Draft step & payment-entry recovery (`D01`, `D02`, `D05`)**:
   - Local checkout drafts preserve `raw.method`, `raw.reference`, and `raw.cash` across sheet close, tab reload, or database reopen.
   - Mobile `checkout_draft_state` records `'step': 'checkout'` while `_BillCheckoutSheet` is open and `'step': 'items'` when closed without completing, without auto-opening a blocking modal sheet on initial `ScanScreen` mount so item editing via `btn_scan_bill` stays unimpeded.

The counter cash field accepts up to 30 whole digits and two decimal places. Payment amounts and change are evaluated in paise, including the displayed change. Saved native and server payment history keeps its original values. The Android test verifies invoice view and New Bill. Physical printer checks remain in E12.
