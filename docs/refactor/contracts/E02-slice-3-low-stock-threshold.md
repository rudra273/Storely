# E02.3 Shop low-stock threshold

The shop-wide `low_stock_threshold` exists in synced `app_settings`. Android edits it from Store and Home. Web edits it in Shop details and uses the existing settings revision workflow. The API exposes the effective threshold as a decimal string on `GET /invoice-settings` and accepts updates through the existing owner/admin `PATCH`.

- The default is `5` for a missing, deleted, malformed, or out-of-range setting. Read fallback leaves the original row untouched.
- Supported values are `0` through `999999999` with up to four meaningful fractional digits, matching the product reorder-level precision. Trailing zeroes do not count toward precision. Zero is valid.
- Stored text and UI input use ASCII digits with an optional decimal point between digits. Leading and trailing ASCII space, tab, carriage return and line feed are ignored. The API also accepts numeric JSON input under its existing decimal quantity validation and stores the result as plain decimal text.
- A product-specific reorder level takes precedence, including zero. Stock tracking must be enabled. The warning includes stock at the effective threshold. Android treats binary arithmetic residuals around equality using the existing SQLite quantity representation.
- Catalog and Android Needs Attention include out-of-stock products in their review lists. The dashboard keeps the running-low and out-of-stock counts separate.

Test a product with quantity `5.5001` and no override. It is above the default threshold of `5` and at the threshold when saved as `5.5001`. A quantity of `5.5002` remains above that threshold. An untracked product is excluded, and a product with `1` in stock and a reorder level of `0` uses its override.
