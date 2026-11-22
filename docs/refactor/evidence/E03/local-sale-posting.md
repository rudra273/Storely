# Local sale posting verification

Android commit `3ef9777` captures the invoice, lines, initial payment and sale stock movements in the same transaction as checkout acceptance. Tests verified that a late acceptance failure rolls back stock and payment, that replay after reopening preserves the original snapshot and posts nothing twice, and that earlier SQLite acceptances remain readable with a null snapshot.

The dedicated Android emulator passed `python3 integration_test/support/checkout_process_recovery.py emulator-5556` across two force-stops. The final process confirmed one invoice, one payment, one stock deduction and an immutable snapshot linked to that invoice. The analyzer passed. The full Flutter suite passed 529 tests with 17 opt-in skips.

The SQLite contract and API fixture are byte-identical. API fixture commit `59b856f` passed all four Docker `test_complete_sync.py` cases. The snapshot is local evidence. Browser-to-cloud and device-to-cloud command acceptance remain separate gates in the [atomic sale sync contract](../../contracts/E03-atomic-sale-sync.md).
