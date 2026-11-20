# E02.3 catalog entry from checkout

Status: implemented and verified, 20 November 2026; [acceptance evidence](../evidence/E02/slice-3-catalog.md). This is the catalog-entry part of E02.3. Broader account, settings and language parity remain separate work within the phase.

Checkout should resolve a product by exact code and ask the cashier to choose when search only finds suggestions. If a safe code has no match, an authorized cashier can add a catalog product using the existing editor with the barcode prefilled. The current invoice is saved before the editor opens. Cancel and validation failure retain the cart and checkout entries. A successful edit returns the saved product identity even if the cashier changes its barcode in the editor.

## Acceptance boundaries

- Exact barcode or product code can add the corresponding product. An ambiguous code is a catalog conflict. A partial name search requires selection. A single exact full name may serve as a convenience after an exact code miss.
- Creation from an unmatched identifier accepts an ASCII letter or digit followed by up to 63 letters, digits, periods, underscores or hyphens. Reject control characters, URLs, structured scan payloads and internal UUIDs for that prefill. Existing valid labels keep resolving by identity.
- Use the current captured shop, account and permissions at the storage and return boundaries. A pending financial save locks draft changes. Stale async callbacks must stop when the checkout unmounts or changes context.
- Save the current work before entering the editor. Return by the exact saved product identity, preserve existing quantities and raw fields, and update the draft. A change in invoice pricing requires fresh settlement review. A tracked product with zero stock stays in the catalog and is available after stock is added.
- Reuse the existing product editor and checkout layout. Free mobile checkout continues to work offline. Verify real localhost and Android flows with an edited barcode, a cancelled editor and preserved invoice entries.
