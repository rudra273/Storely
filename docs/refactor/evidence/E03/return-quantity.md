# Return quantity verification

[The return contract](../../contracts/E03-return-quantity.md) aligns the editors and posting bounds around three meaningful fractional digits. Android preserves remaining quantities without currency rounding. The API compares the exact remainder and returns full decimal precision in the credit-note preview.

- API `914cf14` passed 12 quantity tests, 13 PostgreSQL return tests, and lint. Preview preserved the historical `0.0009995` remainder, and posting `0.001` created no credit note. The existing frozen request replay still works.
- Web `a31ca85` passed 135 targeted tests, typecheck and lint. The localhost browser test rejected excessive precision, over-return, exponent and signed input without posting, then issued a real credit note for `0.5000` as `0.5`. Reopening showed `1.5` remaining. Disposable shop, account and mail were removed.
- Android `5feeda6` passed 12 focused tests and analyzer. The emulator rejected `0.1251` and `2.001`, preserved the editable text, and posted `0.12500` as a `0.125` credit note. SQLite then reported `1.875` remaining. A separate local test rejected a return of `0.001` from the historical `0.0009995` remainder.
- Production Docker smoke passed.
- The final Flutter suite passed 527 tests with 17 opt-in skips. A checkout retry test initially read before the committed invoice was available. Test-only commit `be41dee` waits for the completion screen before checking the saved effects.
