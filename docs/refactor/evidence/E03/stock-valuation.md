# Stock valuation verification

The shared independent fixture at `test/fixtures/stock_valuation_contract_v1.json` and the API's `tests/fixtures` copy have SHA-256 `1a1e09884f30ae0448da5eb39aa310e59a082688080d822cb407a70c35ff0486`. It covers explicit zero and product/category/shop precedence, negative and fractional stock, omitted zero/untracked/deleted products, and half-paise row rounding. The rounded cost total is ₹237.53 for regular GST and ₹276.65 for composition or unregistered. Selling value is ₹192.03 in all three cases.

- API `050af7a` passed three focused PostgreSQL integration cases with exact JSON and CSV rows and totals. The API's displayed unit cost uses its existing half-even formatting. Row amounts use full-precision cost and round ties away from zero.
- Web `f8a7b75` passed 13 report tests, typecheck, lint and build. Browser acceptance verified all three cases on localhost against the real Docker API, including displayed rows, totals and downloaded CSV. The disposable shops and owner were removed after the run.
- Android `5ab607c` passed eight focused tests, including the three independent SQLite fixtures. The disposable emulator opened the Stock value report and showed ₹1,230.00 for composition and ₹1,050.00 for regular GST on the same ten units. The report now describes its effective cost basis and displays up to four quantity decimals.
- Production Docker smoke passed for the final web/API images.
- Flutter analyzer passed. The full Flutter run passed 524 tests with 17 opt-in skips.
