# Sale quantity verification

Web commits `e47271e` and `f9479d5` and Android commit `e2b3f62` align new sale quantity validation. New inputs allow 0.001 through 1,000,000 with up to three meaningful fractional digits. Invalid input survives draft recovery and blocks review and posting. Android also separates editable restored items from the saved snapshot used to detect concurrent changes.

- Web passed 136 targeted tests, typecheck, lint, build and the localhost checkout journey against Docker. The browser recovered `1.2345`, issued no request containing that quantity, accepted `1.0000`, and retried a lost save response without creating a duplicate.
- Android passed 23 focused tests and analyzer. The disposable emulator recovered `1.2345` after reopening SQLite, rejected checkout until corrected, then held, resumed and saved a single invoice.
- API commit `e99f210` passed 27 Docker checkout review tests, including catalog and custom quantity limits at preview and posting. Production Docker smoke passed.

The paired checkout sequence review remains open. Web shows the cart and checkout together. Android opens its existing checkout sheet from the cart. This slice verifies quantity and recovery, with human UX review still pending.
