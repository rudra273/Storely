# Refactor feature execution tracker

Created 18 November 2026. Status reflects execution under the [implementation plan](../../implementation-plan.md), not whether an existing basic feature exists. Original findings remain in the [comparison](<../../refactor plan.md>).

One accountable completion phase is assigned to each of the 145 audit rows. Earlier phases can deliver prerequisites or basic parity, but the owner phase must close the entire row or record an explicit user-approved scope decision. E00/E01 are shared prerequisites; E17 performs final regression and E18 records human acceptance. Some rows contain multiple capabilities: expand them into sub-IDs in the phase contract before coding.

**Baseline** is copied from the audit as M/W/A (mobile/web/API), with E existing, P partial, N not found, D divergent, U unknown. It is not current test evidence. All nonexcluded execution rows start planned. No Docker/browser/emulator test was run to produce this tracker.

For each row, record four separate gates: repo/domain checks; Docker integration; localhost browser; Android emulator. Cross-client reconciliation is also required. Add provider/hardware gates where applicable; explicitly state not-applicable reasons. A parent phase pass alone does not prove every row.

| Feature ID | Capability | Audit baseline M/W/A | Owner phase | Execution state | Evidence / remaining work |
|---|---|---|---|---|---|
| A01 | Email/password, verification, reset, sessions, MFA | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A02 | Phone OTP / Google sign-in | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A03 | Local first use versus paid cloud activation | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A04 | Shop selection / company management | P/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A05 | Multiple firms inside one business | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A06 | Warehouses/godowns inside one shop | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A07 | Owner/admin/staff and invitations | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A08 | Configurable permissions / category access | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A09 | App lock / sensitive-action authentication | P/P/P | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A10 | Audit/security history | P/P/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A11 | Onboarding tutorial and first invoice | P/P/P | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A12 | Global search / settings search / notification routing | P/P/P | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| A13 | Themes / seasonal launcher variants | E/E/— | — | excluded visual scope | Preserve existing theme; no seasonal/visual cloning. |
| T01 | Sales invoice, B2B/B2C | E/E/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T02 | Purchase invoice/stock receipt | P/P/P | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T03 | Customer payment-in | E/E/E | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T04 | Supplier payment-out | P/E/E | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T05 | Expense | E/E/E | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T06 | Other income | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T07 | Sales return / credit note | E/E/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T08 | Purchase return / debit note | N/N/N | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T09 | Full purchase/payment reversal | P/E/E | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T10 | Quotation/estimate | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T11 | Proforma invoice | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T12 | Sales order | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T13 | Purchase order | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T14 | Delivery challan | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T15 | Repeat/recurring invoices | N/N/N | E14 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T16 | Asset sale/purchase | N/N/N | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T17 | Party-to-party balance transfer | N/N/N | E06 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T18 | Save / Save and new / post-save preview | P/P/P | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T19 | Editing posted documents | P/P/P | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T20 | Cancellation / dependency guards | E/E/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T21 | Recycle bin and restore | N/N/N | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| T22 | POS mode | P/P/P | E10 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F01 | Cash/credit and full/partial/unpaid | D/D/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F02 | Date/time/backdating | P/P/P | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F03 | Prefix/number/series | P/P/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F04 | Billing name distinct from party master | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F05 | Billing and multiple shipping addresses | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F06 | Country/currency/exchange rate | N/N/N | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F07 | Payment terms/due date | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F08 | Customer PO number/date | N/N/N | E07 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F09 | E-way bill / IRN fields | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F10 | Document discount percentage | E/E/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F11 | Fixed document discount / alternate discount controls | P/P/P | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F12 | Line discount percent/amount | N/N/N | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F13 | Inclusive/exclusive rate per document/line | P/P/P | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F14 | Transaction-level tax and tax conflicts | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F15 | Cess, additional cess, TCS/TDS, ITC and reverse charge | N/N/N | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F16 | Taxable additional charges with SAC | P/P/P | E04 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| F17 | Round-off modes/increments | P/P/P | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
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
| I01 | Product catalog, category, unit and codes | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I02 | Service/non-stock items | P/P/P | E05 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I03 | HSN/SAC metadata | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I04 | Product photos / description | P/P/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I05 | MRP | P/P/P | E11 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I06 | Wholesale quantity tiers | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I07 | Party-specific item prices | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I08 | Primary/secondary units and conversions | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I09 | Opening stock / opening valuation date | P/P/P | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I10 | Reorder/low stock and stock ledger | E/E/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I11 | Batch and expiry | P/P/P | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I12 | Manufacturing date/size/model/batch attributes | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I13 | Serial/IMEI tracking | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I14 | Multi-store stock transfers | N/N/N | E08 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I15 | Manufacturing/BOM | N/N/N | E09 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I16 | Product import/export | E/E/E | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I17 | Import catalog without posting stock | P/P/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| I18 | Barcode/QR scan and labels | E/E/E | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
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
| O01 | Invoice PDF/preview/share/print | E/E/E | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O02 | PDF/image sharing choice | P/P/P | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O03 | Original/duplicate/triplicate copies | U/U/U | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O04 | Logo/signature, header/footer, columns | E/E/E | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O05 | Custom document titles/per-type print settings | P/P/P | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O06 | Table headers/widths/min rows/header repeat/page numbers | P/P/P | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O07 | Bluetooth thermal | E/N/— | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O08 | Wi-Fi and USB thermal | N/N/— | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O09 | Feed/copies/cut/drawer/custom width/local-language raster | P/P/— | E12 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O10 | Shared settings registry | P/P/P | E02 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O11 | Currency/date/quantity/amount display preferences | P/P/P | E16 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O12 | Local backup/restore | E/N/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O13 | Automatic backup and reminder/retention | P/N/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O14 | Encrypted portable backups | U/N/P | E13 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O15 | Sync/conflicts/account-owned drafts | E/P/E | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
| O16 | Cross-device draft handoff | P/N/P | E03 | planned | Not run; add slice contract, implementation and paired acceptance evidence. |
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
| D01 | E02 | planned | Not run; paired before/after scenario and regression required. |
| D02 | E02 | planned | Not run; paired before/after scenario and regression required. |
| D03 | E03 | planned | Not run; paired before/after scenario and regression required. |
| D04 | E02 | planned | Not run; paired before/after scenario and regression required. |
| D05 | E02 | planned | Not run; paired before/after scenario and regression required. |
| D06 | E04 | planned | Not run; paired before/after scenario and regression required. |
| D07 | E04 | planned | Not run; paired before/after scenario and regression required. |
| D08 | E04 | planned | Not run; paired before/after scenario and regression required. |
| D09 | E03 | planned | Not run; paired before/after scenario and regression required. |
| D10 | E03 | planned | Not run; paired before/after scenario and regression required. |
| D11 | E03 | planned | Not run; paired before/after scenario and regression required. |
| D12 | E02 | planned | Not run; paired before/after scenario and regression required. |
| D13 | E12 | planned | Not run; paired before/after scenario and regression required. |
| D14 | E02 | planned | Not run; paired before/after scenario and regression required. |
| D15 | E03 | planned | Not run; paired before/after scenario and regression required. |

## Phase readiness

| Phase | State | Blocking prerequisite |
|---|---|---|
| E00 | implementing | Baselines running; see evidence/E00/initial/summary.md and repo reports. |
| E01 | implementing | Slices 1–4 verified, including durable report jobs, shared capabilities and guarded product edits; see evidence/E01/summary.md. Emulator/localhost/Docker pass. Shared posting adapters and aggregate settings revision semantics remain open. |
| E02 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E03 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E04 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E05 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E06 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E07 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E08 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E09 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E10 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E11 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E12 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E13 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E14 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E15 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E16 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E17 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |
| E18 | planned | See explicit dependency list in implementation plan; no gate has passed yet. |

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
