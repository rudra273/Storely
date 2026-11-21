# E02.3 GST scheme and pricing defaults

This slice aligns the pricing defaults used by the API and Android SQLite. Web uses the API's effective settings and price preview. The existing settings screens and navigation remain the entry points.

## Effective settings

| Setting | Rule |
| --- | --- |
| `gst_scheme` | Exact `regular`, `composition`, or `unregistered` takes precedence. Only `regular` uses the registered pricing branch. |
| `gst_registered` | With an absent, deleted, or unknown scheme, the exact legacy value `1` means regular and any other value means unregistered. |
| `default_gst_percent` | Effective range 0–100, fallback 18. |
| `default_profit_margin_percent` | Effective range 0–100, fallback 0. |
| `default_overhead_cost` | Effective range ₹0–₹999,999,999, fallback 0. |

Effective numeric reads accept finite ASCII decimal values, including signed and scientific representations, with up to 18 fractional places after removing trailing zeroes. Missing, deleted, malformed, out-of-range, or finer values use the corresponding fallback. Legacy GST values in range can still be read. The resolver leaves stored rows, sync timestamps, and settings revisions as they were.

Editing a default uses the API's existing constraints. GST accepts 0, 0.25, 3, 5, 12, 18, 28, or 40. Margin accepts up to three decimal places and overhead up to two, with trailing zeroes ignored. A failed validation preserves the open draft. An untouched legacy default can coexist with a valid edit to another setting. Web uses the existing revision-protected PATCH and Android uses its existing local settings baseline.

Product and category overrides retain precedence over shop defaults. The API continues to own web checkout pricing. Posted invoice amounts and snapshots retain their historical values. This is a description of Storely's calculation behavior.

## Cross-platform example

For a formula-priced product costing ₹1,000, set GST to 18%, overhead to ₹10 and margin to 12.345%. The effective regular scheme adds GST to the sale price and yields ₹1,338.92771 before paise rounding. Composition includes purchase GST in cost and yields ₹1,336.90550 before rounding. In both cases a stale legacy flag must yield to the explicit scheme.
