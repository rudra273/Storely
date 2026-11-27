# E12.1–E12.2 Evidence — Invoice PDF, Print & Share Parity (`O01`, `O02`, `O04`, `D13`)

Date: 2026-11-27

## Scope
- Aligned A4, A5, 80mm, and 58mm invoice PDF / thermal output across API (`invoice_pdf.py`), Web (`InvoiceDocument.tsx`), and Android (`BillPdfGenerator`, `ReceiptBuilder`, `ReceiptImage`).
- Reflected all E03.3 billing controls across outputs: per-line `%`/`₹` discounts, fixed-₹ document discount label (`Discount (₹X off)`), tax mode indicator (`Prices incl. GST` / `Prices excl. GST`), dedicated `Notes` block, and `VOID` banner (suppressing balance due & UPI QR).
- Exposed all 4 paper sizes (`A4`, `A5`, `80mm`, `58mm`) in Android `BillSettingsScreen` and missing `O04` visibility switches (`show_customer_trade_name`, `show_gst_breakdown`, `show_gst_total`) in Web `InvoiceSettingsPage` + `InvoiceDocument` + API `invoice_pdf.py`.
- Added Android PDF-to-PNG WhatsApp-ready image share + unified Share chooser sheet (`O02`), Web native `Share PDF` (`navigator.share` when supported), and actionable `Retry` print error states (`D13`).

## Verification Gates
- **API (`storelyapi`)**:
  - `make lint`: PASS (ruff, ruff format, mypy strict, bandit — 0 issues)
  - `make test`: PASS (**448 passed**, including `tests/test_invoice_pdf_parity.py`)
- **Web (`storelyweb`)**:
  - `make typecheck`: PASS
  - `make lint`: PASS (0 warnings, 0 errors)
  - `make test`: PASS (**714 passed** across 61 files, including `src/billing/e12OutputParity.test.tsx`)
  - `make build`: PASS
- **Mobile (`Storely`)**:
  - `flutter analyze`: PASS (0 issues)
  - `flutter test test/e12_invoice_output_parity_test.dart test/billing_controls_test.dart test/settings_concurrency_test.dart`: PASS (**19 passed**)
- **Contract**: [E12-invoice-output-parity.md](../../contracts/E12-invoice-output-parity.md)
- **Hardware note**: Physical Bluetooth thermal printer transmission remains an on-device check for E18 walkthrough; ESC/POS byte output and 203 dpi raster PDF generation are verified in automated tests.
