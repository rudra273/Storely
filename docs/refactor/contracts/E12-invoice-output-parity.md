# E12.1–E12.2 Contract — Invoice PDF, Print & Share Parity (`O01`, `O02`, `O04`, `D13`)

Status: Frozen for Base (v1) implementation (2026-11-27)

## Scope
Aligns invoice PDF, thermal receipt, and share output across API, Web, and Android so A4/A5/80mm/58mm output, WhatsApp/image share, and Bluetooth thermal printing reflect all E03.3 billing controls (line discounts, fixed/percent document discounts, inclusive/exclusive tax mode, round-off, bill notes, and VOID/cancelled state) and provide reliable print/share workflows (`D13`).

## 1. API (`storelyapi`) — `app/domains/billing/invoice_pdf.py` & `templates/invoice.html`
1. **Line discounts**:
   - On A4/A5: display line discount as `₹X (Y%)` when `discount_mode == 'percent'` and `₹X` when `discount_mode == 'amount'`, matching Web `InvoiceDocument.tsx`.
   - On 80mm/58mm thermal: display line discount subtext (`Disc: ₹X`) beneath each discounted item, matching Web.
2. **Document discount label**:
   - Align with Web: `Discount (₹X off)` when `discount_mode == 'amount'`, `Discount (Y%)` when `discount_mode == 'percent'`.
3. **Tax mode indicator**:
   - When GST is enabled (`bill.is_gst_bill` or any GST > 0), display a subtle tax-mode indicator (`Prices incl. GST` or `Prices excl. GST` based on `bill.tax_mode`) in the invoice header/totals metadata.
4. **Bill `notes`**:
   - Move `bill.notes` out of the concatenated `payments` string into a dedicated `Notes` block in the invoice extras section, matching Web `.invoice-bill-notes`.
5. **Show flags (`O04`)**:
   - Ensure `show_customer_trade_name`, `show_gst_breakdown`, and `show_gst_total` are honored in `invoice_pdf.py` / `invoice.html`.

## 2. Web (`storelyweb`) — `InvoiceDocument.tsx`, `InvoiceSettingsPage.tsx`, `BillDetailPage.tsx`, `ShareDialog.tsx`, `share.ts`
1. **Tax mode indicator**:
   - Render the same subtle `Prices incl. GST` / `Prices excl. GST` indicator on `InvoiceDocument.tsx` when GST applies.
2. **Show flags (`O04`)**:
   - Expose the 3 missing toggles (`show_customer_trade_name`, `show_gst_breakdown`, `show_gst_total`) in `InvoiceSettingsPage.tsx` and wire them in `InvoiceDocument.tsx`.
3. **Share parity (`O02`)**:
   - In `share.ts` / `ShareDialog.tsx`: ensure WhatsApp share message includes fixed-₹ document discount label, line discount summary when present, `bill.notes`, and `VOID` status if cancelled.
   - In `BillDetailPage.tsx`: add a browser-native `Share PDF` option when `navigator.share` / `navigator.canShare` supports file sharing (falling back cleanly to Download PDF / Print / Share on WhatsApp without promising unsupported silent hardware access — `D13`).

## 3. Android (`Storely`) — `BillPdfGenerator`, `BillSettingsScreen`, `BillShare`, `ReceiptBuilder`, `ReceiptImage`, `ThermalPrinterService`
1. **PDF Parity (`O01`, `O04` — `lib/utils/bill_pdf_generator.dart`, `lib/screens/store/bill_settings_screen.dart`)**:
   - Support `80mm` and `58mm` paper sizes in `BillPdfGenerator` (generating thermal-width PDF pages) and expose `A4`, `A5`, `80mm`, `58mm` in `BillSettingsScreen` (removing the silent `_preservedPaperSize` hideaway).
   - Render per-line discounts (`Disc.` column on A4/A5 showing `₹X (Y%)` or `₹X`; `Disc: ₹X` subline on 80mm/58mm).
   - Fix document discount label: `Discount (₹X off)` when `bill.discountMode == 'amount'`, `Discount (Y%)` when `bill.discountMode == 'percent'`.
   - Render subtle `Prices incl. GST` / `Prices excl. GST` tax-mode indicator when GST applies.
   - Render `bill.notes` in a dedicated Notes block.
   - Render `VOID` banner (with cancellation reason if present) and suppress Balance Due & UPI QR when `bill.isCancelled` / `lifecycleStatus == 'cancelled'`.
2. **Share Parity (`O02` — `lib/services/bill_share.dart`, `bills_screen.dart`, `bill_quick_sheet.dart`, `bill_summary_widgets.dart`)**:
   - Add `BillShare.shareImage(bill, settings, ...)` that rasterizes the generated PDF page to PNG (`Printing.raster`) and shares via `share_plus` (`Share.shareXFiles`).
   - Add a unified Share chooser bottom sheet (`Share as PDF`, `Share as Image (WhatsApp-ready)`, `Send WhatsApp text`, plus optional paper size selector for PDF/Image).
   - Fix `_buildBillMessage` (WhatsApp text) to handle fixed-₹ document discount, line discounts, `bill.notes`, and `VOID` status.
3. **Bluetooth Thermal Print Reliability (`D13` — `lib/services/thermal/receipt_builder.dart`, `receipt_image.dart`, `bill_card.dart`, `bill_summary_widgets.dart`, `bill_quick_sheet.dart`)**:
   - Render line discounts (`Disc: ₹X`), fixed-₹ document discount label, `bill.notes`, `VOID` banner (suppressing balance due & UPI QR), and `termsText` in **both** `ReceiptBuilder` (ESC/POS) and `ReceiptImage` (raster).
   - Expand `ReceiptBuilder.needsImageMode` to check `bill.notes`, `settings.footerText`, and `settings.termsText` for non-Latin scripts.
   - Improve `D13` print workflow: show a Print / Printer Setup affordance even when no printer is paired yet (opening `PrinterSetupSheet`), and on print errors show actionable `Retry` and `Printer setup` actions instead of a dead-end SnackBar.
