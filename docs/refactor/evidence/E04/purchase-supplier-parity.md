# E04.1 Evidence — Purchase & Supplier Parity (`D06–D08`, `T02`, `T04`, `T08`, `T09`)

Date: 2026-11-27

## Scope
- Closed confirmed mobile/web divergences `D06`, `D07`, `D08`.
- Implemented partial & full Purchase Returns / Debit Notes (`T08`) with stock-out, weighted-average cost removal, payable credit + refund settlement, and reversal guards (`T09`).
- Fixed `native_purchases.py` duplicate-invoice check (ignoring reversed receipts) and `GET /purchase-receipts?status=reversed`.
- Synced `purchase_returns` and `purchase_return_items` into `server_managed_public_tables` in `sync_data_contract.json`.

## Verification Gates
- **API (`storelyapi`, migration `0029_e04_1_purchase_returns`)**:
  - `make lint`: PASS (ruff, ruff format, mypy strict, bandit — 0 issues)
  - `make test`: PASS (443 passed)
  - `make migrate`: PASS (applied `0029` to live Docker DB)
  - `make test-integration`: PASS (**466 passed**, including `test_purchase_returns.py`, `test_complete_sync.py`, `test_authorization_matrix.py`, `test_purchase_corrections.py`, `test_supplier_payments.py`)
- **Web (`storelyweb`)**:
  - `make typecheck`: PASS
  - `make api-types-check`: PASS
  - `make lint`: PASS (0 warnings, 0 errors)
  - `make test`: PASS (**711 passed** across 60 files)
  - `make build`: PASS
- **Mobile (`Storely`)**:
  - `flutter analyze`: PASS (0 issues)
  - `flutter test test/e04_1_purchase_supplier_parity_test.dart test/sync_data_contract_test.dart test/purchase_history_screen_test.dart test/purchase_documents_test.dart test/purchase_api_sync_backend_test.dart`: PASS (**48 passed**)
- **Contract**: [E04-1-purchase-supplier-parity.md](../../contracts/E04-1-purchase-supplier-parity.md)
