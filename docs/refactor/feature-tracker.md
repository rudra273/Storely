# Refactor feature execution tracker

Created 18 November 2026. Status reflects execution under the [implementation plan](../../implementation-plan.md), not whether an existing basic feature exists. Original findings remain in the [comparison](<../../refactor plan.md>).

One accountable completion phase is assigned to each of the 145 audit rows. Earlier phases can deliver prerequisites or basic parity, but the owner phase must close the entire row or record an explicit user-approved scope decision. E00/E01 are shared prerequisites; E17 performs final regression and E18 records human acceptance. Some rows contain multiple capabilities: expand them into sub-IDs in the phase contract before coding.

**Baseline** is copied from the original audit as M/W/A (mobile/web/API), with E existing, P partial, N not found, D divergent, U unknown. Execution states reflect scoped verification through 26 November 2026. A verified milestone can complete part of an audit row while its broader scope remains open.

For each row, record four separate gates: repo/domain checks; Docker integration; localhost browser; Android emulator. Cross-client reconciliation is also required. Add provider/hardware gates where applicable; explicitly state not-applicable reasons. A parent phase pass alone does not prove every row.

| Feature ID | Capability | Audit baseline M/W/A | Owner phase | Execution state | Evidence / remaining work |
|---|---|---|---|---|---|
| A01 | Email/password, verification, reset, sessions, MFA | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A02 | Phone OTP / Google sign-in | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A03 | Local first use versus paid cloud activation | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A04 | Shop selection / company management | P/E/E | E02 | implementing | Web remembers shop per account, opens the newly activated workspace and restores only the selected shop’s draft and role. Mobile company management parity remains open. |
| A05 | Multiple firms inside one business | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A06 | Warehouses/godowns inside one shop | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A07 | Owner/admin/staff and invitations | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A08 | Configurable permissions / category access | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A09 | App lock / sensitive-action authentication | P/P/P | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A10 | Audit/security history | P/P/E | E03 | verified | Shop-wide audit & security history with date/action filters on API/Web (`Activity & audit`), local product/stock/bill audit logging and `AuditLogScreen` on Android. See [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md). |
| A11 | Onboarding tutorial and first invoice | P/P/P | E02 | implementing | Home guidance through a first saved invoice passed paired localhost and Android checks. Broader tutorial scope and human UX review remain open. See `evidence/E02/first-invoice-onboarding.md`. |
| A12 | Global search / settings search / notification routing | P/P/P | E02 | verified | Workspace search, settings search, and in-app alert routing passed on localhost, Docker and Android. Human UX review remains open. See `evidence/E02/notification-routing.md` and the search evidence records. |
| A13 | Themes / seasonal launcher variants | E/E/— | — | excluded visual scope | Preserve existing theme; no seasonal/visual cloning. |
| T01 | Sales invoice, B2B/B2C | E/E/E | E03 | verified | Reviewed checkout, exact decimal math (`D09`), line/doc discounts, inclusive/exclusive tax modes, round-off modes/increments, backdating, series settings, notes/metadata edit, and opt-in atomic Android posting/reconciliation verified. (`STORELY_NATIVE_SALE_POSTING` stays opt-in until E17/E18.) See E03 evidence records. |
| T02 | Purchase invoice/stock receipt | P/P/P | E04 | implementing | E04.1 receipt parity, `status=reversed` filter, and native duplicate-after-reversal fix verified (`evidence/E04/purchase-supplier-parity.md`). Typed line-level purchase GST/SAC charges remain E04.2 (M1). |
| T03 | Customer payment-in | E/E/E | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T04 | Supplier payment-out | P/E/E | E04 | verified | Mobile/web field parity (`purchase_uuid`, `reference`, `notes`), confirmed-vs-pending separation (`D07`/`D08`), and payment reversal verified across API, web, and Android. See [E04.1 evidence](evidence/E04/purchase-supplier-parity.md). |
| T05 | Expense | E/E/E | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T06 | Other income | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T07 | Sales return / credit note | E/E/E | E03 | verified | Fractional return validation, exact remaining quantities, original bill tax/round-off/discount snapshot carry-over, opt-in atomic Android credit-note delivery/replay, and mixed-version compatibility verified. See [return quantity](evidence/E03/return-quantity.md), [billing commands](evidence/E03/native-billing-commands.md), and [billing controls](evidence/E03/billing-controls.md). |
| T08 | Purchase return / debit note | N/N/N | E04 | verified | Partial/full purchase returns (`DN/{FY}/{seq}`), stock-out, WAC removal, payable credit + refund settlement, reversal guard (`409 returns_recorded`), and supplier statement integration verified across API, web, and Android. See [E04.1 evidence](evidence/E04/purchase-supplier-parity.md). |
| T09 | Full purchase/payment reversal | P/E/E | E04 | verified | Full purchase and supplier payment reversal actions, reason dialogs, and stock/payment/return guards aligned across API, web, and Android (`D06`). See [E04.1 evidence](evidence/E04/purchase-supplier-parity.md). |
| T10 | Quotation/estimate | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T11 | Proforma invoice | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T12 | Sales order | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T13 | Purchase order | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T14 | Delivery challan | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T15 | Repeat/recurring invoices | N/N/N | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T16 | Asset sale/purchase | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T17 | Party-to-party balance transfer | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T18 | Save / Save and new / post-save preview | P/P/P | E02 | verified | Localhost and Android verified saved settlement summary, clean New invoice and saved invoice view. Printing transport verification remains E12. See evidence/E02/slice-3-payment-completion.md. |
| T19 | Editing posted documents | P/P/P | E03 | verified | Admin-only non-financial metadata & notes editing (`PATCH /bills/{id}` on API/Web, `_EditBuyerDetailsSheet` on Android) with field-diff audit trail, cancelled-bill `409` guard, and immutable financial lines/totals. See [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md). |
| T20 | Cancellation / dependency guards | E/E/E | E03 | verified | Atomic native cancellation command with credit-note dependency guard, deterministic stock void, sticky cancellation, `409` metadata-edit guard, and mixed-version compatibility verified across API, web, and Android. See [billing commands](evidence/E03/native-billing-commands.md) and [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md). |
| T21 | Recycle bin and restore | N/N/N | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T22 | POS mode | P/P/P | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F01 | Cash/credit and full/partial/unpaid | D/D/E | E02 | verified | Explicit settlement, five payment methods, exact paise cash change and invoice payment reference handling verified across API, web and Android. See evidence/E02/slice-3-payment-completion.md. |
| F02 | Date/time/backdating | P/P/P | E03 | verified | Admin-only invoice backdating (`bill_date` on API/Web, date picker in Android checkout) with future/range guards, staff `403`, FY series alignment, and audit logging. See [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md). |
| F03 | Prefix/number/series | P/P/E | E03 | verified | Configurable template/prefix, padding, reset period, forward-only `next_sequence`, and live preview across API `invoice-settings`, Web `InvoiceSettingsPage`, and Android `BillSettingsScreen`. See [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md). |
| F04 | Billing name distinct from party master | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F05 | Billing and multiple shipping addresses | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F06 | Country/currency/exchange rate | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F07 | Payment terms/due date | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F08 | Customer PO number/date | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F09 | E-way bill / IRN fields | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F10 | Document discount percentage | E/E/E | E03 | verified | Exact decimal document `%` discount before tax verified across API, web, mobile, Docker, browser, and emulator. See [billing controls](evidence/E03/billing-controls.md). |
| F11 | Fixed document discount / alternate discount controls | P/P/P | E03 | verified | Fixed `₹` document discount with exact-paisa proration across GST lines, overflow guards, and `%`/`₹` toggle verified across API, web, and Android. See [billing controls](evidence/E03/billing-controls.md). |
| F12 | Line discount percent/amount | N/N/N | E03 | verified | Per-line `%` and `₹` discounts with held-cart/draft persistence, invoice display/PDF, and credit-note carry-over verified across API, web, and Android. See [billing controls](evidence/E03/billing-controls.md). |
| F13 | Inclusive/exclusive rate per document/line | P/P/P | E03 | verified | Shop default, per-document, and per-line inclusive/exclusive tax modes verified with mixed-mode oracle fixtures across API, web, and Android. See [billing controls](evidence/E03/billing-controls.md). |
| F14 | Transaction-level tax and tax conflicts | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F15 | Cess, additional cess, TCS/TDS, ITC and reverse charge | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F16 | Taxable additional charges with SAC | P/P/P | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F17 | Round-off modes/increments | P/P/P | E03 | verified | Shop default and per-bill `none`/`nearest`/`up`/`down` round-off across `₹0.50`/`₹1`/`₹5`/`₹10` increments verified across API, web, and Android. See [billing controls](evidence/E03/billing-controls.md). |
| F18 | Split tender | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F19 | Settlement discount/write-off | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F20 | Advances/unallocated credits | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F21 | Free quantity / packet count | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F22 | Catalog rate override / last five prices | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F23 | Line notes/service period | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F24 | Item/party/transaction custom fields | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F25 | Business notes, attachments and images | P/P/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F26 | Terms and conditions by document type | P/P/P | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F27 | Transport fields and delivery acknowledgement | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F28 | Loyalty earning/redemption | N/N/N | E15 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I01 | Product catalog, category, unit and codes | E/E/E | E02 | implementing | E02.3 catalog entry from checkout verified (exact code lookup, concurrent race mapping, zero-stock save, staff guard); evidence/E02/slice-3-catalog.md. Broader E02.3 account/settings/locale parity remains open. |
| I02 | Service/non-stock items | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I03 | HSN/SAC metadata | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I04 | Product photos / description | P/P/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I05 | MRP | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I06 | Wholesale quantity tiers | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I07 | Party-specific item prices | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I08 | Primary/secondary units and conversions | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I09 | Opening stock / opening valuation date | P/P/P | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I10 | Reorder/low stock and stock ledger | E/E/E | E03 | verified | Shop-wide & per-product stock ledger (`GET /stock-movements` + `ShopStockLedger` on Web, running balance & type filter chips in Android `StockMovementHistorySheet`), low-stock thresholds, and reorder levels verified. See [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md). |
| I11 | Batch and expiry | P/P/P | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I12 | Manufacturing date/size/model/batch attributes | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I13 | Serial/IMEI tracking | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I14 | Multi-store stock transfers | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I15 | Manufacturing/BOM | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I16 | Product import/export | E/E/E | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I17 | Import catalog without posting stock | P/P/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I18 | Barcode/QR scan and labels | E/E/E | E02 | implementing | E02.3 checkout scan/search/unmatched-code creation and edited-barcode UUID return verified on localhost and Android; evidence/E02/slice-3-catalog.md. E02.3 non-checkout parity and E08 serial scan remain open. |
| I19 | Customer/supplier master and balances | E/E/E | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I20 | Party opening balance/date/direction | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I21 | Party groups | N/N/N | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I22 | Credit limits | N/N/N | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I23 | GSTIN verification / party details retrieval | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I24 | Party spreadsheet/contact import | N/N/N | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I25 | Party self-registration/review link | N/N/N | E15 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I26 | Party statements/collections/reminders | P/P/P | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I27 | CRM leads/tasks/field sales | N/N/N | E15 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I28 | Customer profiling / partner/network / voice candidate | U/U/U | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R01 | Day book | E/E/E | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R02 | Profit and loss | P/P/P | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R03 | Receivables aging | E/E/E | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R04 | Payables aging | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R05 | Stock valuation | D/D/D | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R06 | Purchase register | E/E/E | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R07 | Expiry/low-stock reports | P/P/P | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R08 | Tax summary and GSTR-1 export | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R09 | GSTR-2, 3B, 4, 9, 9A | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R10 | HSN/SAC summary and tax-rate detail | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R11 | TCS/TDS reports | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R12 | UAE VAT 201 / regional taxes | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R13 | Balance sheet / chart of accounts / journals | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R14 | Cash ledger / adjustments / cash flow | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R15 | Bank accounts / statement / transfers | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R16 | Cheques: open/closed/deposit/reopen | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R17 | Loans / EMI / fees / interest | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R18 | Fixed assets/depreciation/appreciation | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R19 | Party/item/category profit reports | P/P/P | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R20 | Party groups, items by party, parties by item | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R21 | Item/document discount reports | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R22 | Order, serial, manufacturing and transfer reports | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R23 | Scheduled email reports | N/N/N | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R24 | Custom reports / saved filters | P/P/P | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R25 | Financial year closing / period locks | N/N/N | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R26 | E-invoice generation/status/cancel | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| R27 | E-way bill generation/status/cancel | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O01 | Invoice PDF/preview/share/print | E/E/E | E12 | verified | A4/A5/80mm/58mm PDF and thermal output aligned across API, web, and Android with E03.3 line/doc discounts, tax mode, notes, and VOID banner. See [E12 evidence](evidence/E12/invoice-output-parity.md). |
| O02 | PDF/image sharing choice | P/P/P | E12 | verified | Android unified Share sheet (PDF / WhatsApp-ready PNG image / WhatsApp text + paper choice) and Web native `Share PDF` + updated WhatsApp message verified. See [E12 evidence](evidence/E12/invoice-output-parity.md). |
| O03 | Original/duplicate/triplicate copies | U/U/U | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O04 | Logo/signature, header/footer, columns | E/E/E | E12 | verified | All 39 `show_*` flags (including `show_customer_trade_name`, `show_gst_breakdown`, `show_gst_total`), 4 paper sizes, logo, signature, and terms aligned across API, web, and Android. See [E12 evidence](evidence/E12/invoice-output-parity.md). |
| O05 | Custom document titles/per-type print settings | P/P/P | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O06 | Table headers/widths/min rows/header repeat/page numbers | P/P/P | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O07 | Bluetooth thermal | E/N/— | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O08 | Wi-Fi and USB thermal | N/N/— | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O09 | Feed/copies/cut/drawer/custom width/local-language raster | P/P/— | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O10 | Shared settings registry | P/P/P | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O11 | Currency/date/quantity/amount display preferences | P/P/P | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O12 | Local backup/restore | E/N/P | E13 | implementing | Android SQLite v30 local backup/restore and cross-account isolation verified (`evidence/E17/pilot-release-hardening.md`). Cloud/web business backup belongs to E13 (M1). |
| O13 | Automatic backup and reminder/retention | P/N/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O14 | Encrypted portable backups | U/N/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O15 | Sync/conflicts/account-owned drafts | E/P/E | E03 | verified | Owner-scoped Android preferences, opted-in sale reservation/replay, explicit reconciliation, atomic payment/cancel/credit-note commands, mixed-version upgrade/restore safety, and complete sync field contract verified. See [mixed-version restore](evidence/E03/native-mixed-version-restore.md) and [draft handoff](evidence/E03/draft-handoff.md). |
| O16 | Cross-device draft handoff | P/N/P | E03 | verified | Server-mediated single-consumer `draft_handoffs` with atomic claim (`409 draft_already_claimed` on race), RLS isolation, Web↔Mobile handoff UI, and preserved local-only mode verified. See [draft handoff](evidence/E03/draft-handoff.md). |
| O17 | Vyapar/MyBillBook/Tally interoperability | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O18 | Automatic transaction messaging | N/N/N | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O19 | Service reminders | N/N/N | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O20 | Online storefront/catalogue/orders | N/N/N | E15 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O21 | Payment links / gateway / KYC | N/N/N | E15 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O22 | Loyalty setup/party points/expiry | N/N/N | E15 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O23 | Smart Ads | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O24 | Facebook/WhatsApp marketing integrations | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O25 | Referral/scratch cards/rewards/greetings | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O26 | Inbox/help/tutorials/NPS/what's new | P/P/P | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O27 | License/subscription/premium administration | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |

## Confirmed-divergence closure

Source divergences must be reproduced/characterized in E00 and closed by the phase below. The audit remains a historical snapshot.

| ID | Owner phase | State | Closure evidence |
|---|---|---|---|
| D01 | E02 | verified | Paired localhost browser (`checkout-payment-completion.cjs`) and Android emulator (`checkout_payment_completion_test.dart`) verified the same logical Item → Party/details → Settlement/review → Save/result sequence on the ₹118 fixture. See `evidence/E02/phase-exit.md`. |
| D02 | E02 | verified | Both clients require an explicit settlement decision. A new or duplicated invoice starts unsettled. See evidence/E02/slice-1.md and evidence/E02/slice-3-payment-completion.md. |
| D03 | E03 | verified | Android uses the same stock cost basis, signed quantities and row rounding as API/web. Shared fixture and emulator/browser/CSV evidence in `evidence/E03/stock-valuation.md`. |
| D04 | E02 | verified | Paired localhost and offline Android hold/swap, safe discard and failed-write retention. See evidence/E02/slice-2.md. |
| D05 | E02 | verified | Browser reload and Android database reopen preserve checkout. Two Android force-stops and cold launches preserved fields and step, then verified one invoice, payment and stock deduction. See `evidence/E02/slice-2.md`. |
| D06 | E04 | verified | Mobile `PurchaseHistoryScreen` now exposes `Pay supplier`, `Record payment terms`, `Return items (Debit note)`, and `Reverse purchase` with server guard parity. See [E04.1 evidence](evidence/E04/purchase-supplier-parity.md). |
| D07 | E04 | verified | Mobile `SupplierPaymentsScreen` supports `purchase_uuid`, `reference`, `notes`, confirmed-vs-pending badges, and confirmed payment reversal; Web adds `notes`. See [E04.1 evidence](evidence/E04/purchase-supplier-parity.md). |
| D08 | E04 | verified | Mobile separates Confirmed balance, Pending on this device, and Projected balance after sync, excludes reversed receipts, and converges to `0.00` diff against API/Web. See [E04.1 evidence](evidence/E04/purchase-supplier-parity.md). |
| D09 | E03 | verified | Exact decimal/rational math across API (`Decimal`), Mobile (`ExactDecimal`), and Web (`BigInt` paise) verified against 12 v1 + 14 v2 independent oracle fixtures and 91 shared vectors at 0.00 tolerance. See [billing controls](evidence/E03/billing-controls.md). |
| D10 | E03 | implementing | New sale and return quantity validation verified across clients and API, including exact remaining-stock guards. Broader unit conversion precision remains open. See `evidence/E03/sale-quantity.md` and `evidence/E03/return-quantity.md`. |
| D11 | E03 | verified | Bank transfer aliases accepted with compatible wire codes and same-key replay. Android recovery, web history display and Docker integration passed. See `evidence/E03/payment-method-aliases.md`. |
| D12 | E02 | verified | Sales checkout uses its dedicated durable store. Legacy meaningful drafts survive age, failed writes keep the prior revision, and an unconfirmed request cannot be replaced or cleared. Rechecked 122 web billing and draft-store tests. See `evidence/E02/slice-2.md` and `evidence/E02/notification-routing.md`. |
| D13 | E12 | verified | Print/share intent, settings (A4/A5/80mm/58mm), E03.3 receipt fields, and actionable Retry error states aligned across Web (browser/PDF/Web Share) and Android (Bluetooth ESC/POS + 203 dpi raster). Physical printer hardware verification remains E18. See [E12 evidence](evidence/E12/invoice-output-parity.md). |
| D14 | E02 | deferred | Owner deferred web Hindi localization and portable web language selection. |
| D15 | E03 | verified | Local capture, API preflight/post, opt-in Android command transport, device negotiation, exact replay, historical snapshot proof, explicit reconciliation, atomic payment/cancel/credit-note commands, and mixed-version upgrade/downgrade/restore compatibility verified (`STORELY_NATIVE_SALE_POSTING` remains opt-in until E17/E18 release gate). See [mixed-version restore](evidence/E03/native-mixed-version-restore.md). |

## Verified delivery milestones

| Scope | State | Evidence |
|---|---|---|
| E00 API baseline repairs, localhost onboarding, Android security checks and paid restore/roundtrip | verified | [Baseline and outstanding gates](evidence/E00/initial/summary.md) |
| E01 compatibility, command/recovery/settings, jobs and financial posting foundations | complete | [Closing audit](evidence/E01/closing-audit.md) |
| E02 checkout settlement, durable drafts, held carts, process-death recovery, catalog entry, payment and completion | verified | [Settlement](evidence/E02/slice-1.md), [drafts](evidence/E02/slice-2.md), [catalog entry](evidence/E02/slice-3-catalog.md), [payment/completion](evidence/E02/slice-3-payment-completion.md) |
| E02 pricing and GST defaults, low-stock threshold, portable preferences and first-invoice guidance | verified | [Pricing](evidence/E02/slice-3-pricing-settings.md), [low stock](evidence/E02/slice-3-low-stock-threshold.md), [preferences](evidence/E02/slice-3-portable-preferences.md), [first invoice](evidence/E02/first-invoice-onboarding.md) |
| E02 workspace search, settings search and in-app notification routing | verified | [Workspace search](evidence/E02/workspace-search.md), [settings search](evidence/E02/settings-search.md), [notifications](evidence/E02/notification-routing.md) |
| E03 stock valuation, sale and return quantities, bank-transfer aliases | verified | [Valuation](evidence/E03/stock-valuation.md), [sales](evidence/E03/sale-quantity.md), [returns](evidence/E03/return-quantity.md), [bank transfer](evidence/E03/payment-method-aliases.md) |
| E03.2 immutable local sale capture, API preflight and atomic sale publication | verified | [Local capture](evidence/E03/local-sale-posting.md), [API preflight](evidence/E03/native-sale-preflight.md), [API posting](evidence/E03/native-sale-posting.md) |
| E03.2 opt-in Android delivery, same-key replay and historical invoice line proof | verified | [Android delivery](evidence/E03/android-native-sale-delivery.md), [historical snapshot proof](evidence/E03/native-sale-snapshot-proof.md) |
| E03.2 reconciliation of reserved Android sales (shortages, snapshot drift, local edits, lost responses) | verified | [Reconciliation](evidence/E03/native-sale-reconciliation.md) |
| E03.2 atomic Android payment, cancellation, and credit-note commands | verified | [Billing commands](evidence/E03/native-billing-commands.md) |
| E03.2 mixed-version upgrade, downgrade, and backup/restore compatibility | verified | [Mixed-version restore](evidence/E03/native-mixed-version-restore.md) |
| E03.3A billing controls (line/doc discounts, inclusive/exclusive tax modes, round-off modes/increments, exact decimal `D09`) | verified | [Billing controls](evidence/E03/billing-controls.md) |
| E03.3B document date/series, posted-bill metadata edit, audit history, and shop stock ledger (`F02`, `F03`, `T19`, `A10`, `I10`) | verified | [E03.3B evidence](evidence/E03/billing-metadata-audit-ledger.md) |
| E03.3C cross-device single-consumer draft handoff (`O16`) and E03 phase exit | verified | [Draft handoff](evidence/E03/draft-handoff.md) |
| E04.1 purchase & supplier parity (`D06–D08`, `T04`, `T08`, `T09`) and purchase returns / debit notes | verified | [Purchase & supplier parity](evidence/E04/purchase-supplier-parity.md) |
| E12.1–E12.2 invoice PDF, print & share parity (`O01`, `O02`, `O04`, `D13`) across A4/A5/80mm/58mm | verified | [Invoice output parity](evidence/E12/invoice-output-parity.md) |
| E17 (lite) Base v1 pilot release hardening (PG 18.6 migration `0029`, `O12` backup/restore, clean release APK) | verified | [Pilot release hardening](evidence/E17/pilot-release-hardening.md) |

## Phase readiness

| Phase | State | Blocking prerequisite |
|---|---|---|
| E00 | implementing | Baseline checks and paid roundtrip verified. Close the broad browser harness, fixture and final environment gaps against current revisions. See [E00 evidence](evidence/E00/initial/summary.md). |
| E01 | complete | Foundation verification passed. See [closing audit](evidence/E01/closing-audit.md) and [command contract](contracts/E01-command-foundations.md). Final human acceptance belongs to E18. |
| E02 | agent-verified | Paired checkout sequence (`D01`) and E02 phase-exit checks passed on localhost browser and Android emulator (`evidence/E02/phase-exit.md`), joining verified E02.1–E02.3 deliverables (settlement, drafts, held carts, process-death recovery, catalog entry, payment/completion, pricing/GST defaults, low-stock threshold, portable preferences, first-invoice onboarding, workspace/settings search, notification routing). Web Hindi localization (`D14`) is deferred by owner. Human UX review belongs to E18. |
| E03 | agent-verified | All E03.1–E03.3 deliverables (`D03`, `D09`, `D11`, `D15`, `T01`, `T07`, `T19`, `T20`, `F02`, `F03`, `F10–F13`, `F17`, `A10`, `I10`, `O15`, `O16`) are verified across API, web, and Android (`STORELY_NATIVE_SALE_POSTING` remains opt-in until E17/E18; unit conversion precision under `D10` continues in E08). Human UX review belongs to E18. |
| E04 | implementing (E04.1 verified) | Base (v1) slice `E04.1` (`D06–D08`, `T04`, `T08`, `T09`, purchase returns/debit notes & reversals) is agent-verified (`evidence/E04/purchase-supplier-parity.md`). Remaining typed purchase GST/SAC charges (`E04.2`, `F16`, `T05`, `R06`) are scheduled in **M1**. |
| E05 | planned (M1) | Scheduled in **M1** (Parties, receivables, credit limits, aging, split tender, advances). |
| E06 | planned (M1) | Scheduled in **M1** (Accounting, cashbook, bank accounts, P&L, balance sheet). |
| E07 | planned (M1) | Scheduled in **M1** (Quotations, proforma, sales/purchase orders, delivery challans). |
| E08 | planned (M2) | Scheduled in **M2** (Multi-firm, warehouses, alternate units `D10`, batch/expiry/serials, transfers). |
| E09 | planned (M2) | Scheduled in **M2** (Wholesale tiers, party pricing, BOM/manufacturing, deep reports). |
| E10 | planned (M2) | Scheduled in **M2** (Granular permissions, app lock, cheques, loans, fixed assets, POS shift). |
| E11 | planned (M1/M2) | Core GST/HSN/TCS/TDS reports scheduled in **M1**; provider-gated GSTIN/e-Invoice/e-Way scheduled in **M2**. |
| E12 | implementing (E12.1–E12.2 verified) | Base (v1) slices `E12.1–E12.2` (`O01`, `O02`, `O04`, `D13`) are agent-verified across API, web, and Android (`evidence/E12/invoice-output-parity.md`). Physical Bluetooth printer check belongs to E18; Wi-Fi/USB adapters (`E12.3`) are scheduled in **M2**. |
| E13 | planned (M1) | Android local backup/restore (`O12`) verified in Base v1; full imports, recycle bin, encrypted/auto backups, and FY closing are scheduled in **M1**. |
| E14 | planned (M2) | Scheduled in **M2** (Recurring invoices, automated reminders, scheduled email reports). |
| E15 | planned (M2) | Scheduled in **M2** (Storefront, payment links, loyalty, CRM). |
| E16 | planned (M2) | Scheduled in **M2** (Phone/Google auth, multi-currency/regional, Tally/Vyapar interop, deferred `D14`). |
| E17 | implementing (E17 lite verified) | Base (v1) pilot release hardening verified (`evidence/E17/pilot-release-hardening.md`: PG 18.6 migration `0029`, `O12` restore, clean release APK without debug CA). Full regression repeats for M1/M2. |
| E18 | ready for pilot walkthrough | Base (v1) pilot is ready for human UX walkthrough on `https://localhost` and `app-release.apk`, decision on `STORELY_NATIVE_SALE_POSTING`, and production deploy. |

## Feature evidence record template

```text
Feature/subfeature ID:
Owner phase/slice:
Source evidence and confidence:
Exact implementation scope / explicitly excluded portion:
API / mobile / web changed paths and build revisions:
Contract/fixture/scenario IDs:
Repo checks: pass/fail/not-run/not-applicable + evidence
Docker: pass/fail/not-run/not-applicable + evidence
Localhost browser: pass/fail/not-run/not-applicable + evidence
Android emulator: pass/fail/not-run/not-applicable + evidence
Cross-client reconciliation: pass/fail/not-run + evidence
Migration/retry/offline/permission coverage:
Provider/hardware acceptance where required:
Remaining blocker and owner:
Human review case/result (E18):
```

A blocked provider or unresolved reference formula remains visible. “Discovery completed” does not mean “feature implemented.” Growth/regional features are not automatically deferred. A13 is excluded because the user explicitly asked to preserve theme/UI identity; all other scope reductions require an actual user decision.
