# Mobile financial/defaults audit for E01 closure

Date: 19 November 2026. Scope: independent shared-fixture tests and a compatibility-only paper-value preservation fix; no calculator, UI or default behavior changes.

## Observed defaults

| Concern | Current mobile source behavior | Disposition |
|---|---|---|
| GST registration | `GlobalPricingSettings` defaults unregistered; `ShopProfile` defaults scheme unregistered. A stored/default GST rate of 18% does not alone authorize charging GST. | Preserve registration-dependent calculation; API uses matching registration/rate defaults. |
| Pricing | Default GST rate 18, overhead 0, margin 0; purchase prices hidden globally unless enabled. | Existing defaults; no new implicit margin or cost assumption. |
| Bill rounding | `BillSettings.roundOffTotal` defaults true; nearest whole rupee after line paise rounding. Dart nearest-integer ties are away from zero. | Pin existing behavior in independent fixtures. Do not substitute the reference app's ties-to-even behavior or reprice history. |
| Line money | Legacy doubles with explicit paise rounding/nudge; line amounts/taxables rounded separately; tax is their difference; bill intra-state tax split once. | Shared fixture asserts final paise exactly, with only negative-zero display normalization. Exact decimal parsing adapters do not imply all mobile billing was converted to BigInt. |
| Payment choice | Checkout initializes paid-in-full and cash; web initializes payment selection null and asks explicitly. | Known E02 parity decision remains open. Recommended shared target: explicit payment choice, with a deliberate shared default setting if desired. No behavior changed by this audit. |
| Regular invoice paper | `BillSettings` defaults A4, supports A5. | Existing regular-paper default. |
| Thermal device paper | `ThermalPrinterService` defaults 58 mm from a device-local preference. | Separate printer capability/configuration from regular document paper; not evidence all print defaults agree. |
| Thermal settings round trip | Commit d68e00b preserves valid persisted 80 mm/58 mm metadata through unrelated copies and saves; existing UI projection remains A4/A5. Explicit paper choice replaces the raw value. | Accidental overwrite fixed; thermal rendering and UI parity remain E12. |
| Numbering | `INV/{FY}/{SEQ}`, financial-year reset, padding 4; existing per-device allocation semantics. | Preserve identity/history; scope and manual override extensions belong to their implementation phase. |
| Invoice title/output flags | Model title `TAX INVOICE`; rendering uses registration-specific titles; most visibility flags true, signature false, terms/bank/UPI blank. | Do not confuse a model's title string with authority to issue a tax invoice. Output parity remains separately verified. |

## Independent money oracle

`test/independent_financial_contract_test.dart` reads the root-owned `test/fixtures/financial_contract_v1.json`. Expectations are reviewed decimal strings derived outside the application calculator; the test cannot generate/rewrite them. Inputs pass through the existing legacy calculator and final amounts must equal the fixture's exact two-place values. Negative zero alone is normalized for display.

These fixtures cover ordinary/unregistered transactions, intra/inter GST, fractional quantities, discounts, half-paise line rounding, odd-paisa aggregate tax splitting and signed return/rounding calculations. Signed return calculator cases do not make negative quantities valid in a create-sale API request. The generated `billing_vectors_test.dart` remains useful regression coverage but is not the independent oracle.

Verification results will be appended after the root-owned fixture is available. No new deployment/compliance or physical-printer claim follows from this audit.

## Verified result and precise remaining paper gap

`flutter test test/independent_financial_contract_test.dart`: **13 passed** (12 cases plus fixture-integrity check). `flutter analyze`: clean, no issues. Logs: `/tmp/storely-mobile-e01-independent-tests.log` and `/tmp/storely-mobile-e01-independent-analyze.log`. Shared fixture bytes were checked equal to the API copy; expected literals were not regenerated or changed.

Affected paper path: `BillSettingsScreen._load` → `DatabaseHelper.getBillSettings` → `BillSettings.fromMap`, with persisted `paper_size` equal to `80mm` or `58mm`, loads an in-memory A4 projection. `_save` copies that model when editing a title/footer and `saveInvoiceSettings` persists its A4 `paper_size`. The frozen baseline still matches the original persisted row, so CAS correctly detects no concurrent writer but cannot detect that the model discarded an existing supported value. Preserve this finding for E12 and fix representation/round-trip behavior explicitly; do not describe the current aggregate guard as solving it. This audit did not change the existing paper behavior.

## Compatibility fix verified

Commit `d68e00b` fixes the data-loss path identified above: valid persisted 80mm/58mm survives load → unrelated title/footer edit → guarded save/reopen. Explicit A4/A5 selection clears preserved metadata, including A4-to-A4; malformed values retain the old fallback. Fifteen focused tests and analyzer pass. This supersedes the earlier unchanged-paper finding; native thermal rendering/UI remains E12.
