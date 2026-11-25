# Stock valuation parity

Use the existing API report as the proposed contract for Android, web and exports. Value on-hand inventory from active tracked products with nonzero stock, including signed negative quantities. Regular GST excludes recoverable purchase GST from cost. Composition and unregistered shops include purchase GST. Resolve GST and overhead from product overrides, then category, then shop. Explicit zero is an override. Use the saved selling price for the selling-value column. Margin affects neither the cost basis nor the stored selling price read by this report.

Multiply the signed quantity by the full-precision cost or selling price. Round each row to paise, with ties away from zero. Sum the rounded rows. Sort by descending cost value, then case-insensitive name. The report reads current stock and pricing and does not rewrite stock, prices, or previously issued invoices.

For ten units at ₹100 purchase cost, 18% GST and ₹5 overhead, the cost is ₹1,050.00 in a regular GST shop and ₹1,230.00 in a composition or unregistered shop. The independent fixture also needs fractional and negative stock, explicit zero overrides, zero stock, untracked and deleted items. Verify the same rows and totals through the API, web report and export, and Android SQLite and emulator views.
