# Bank transfer compatibility

Both `bank` and `bank_transfer` now represent Bank transfer at the API input boundary. The API normalizes the alias before binding it to an idempotency key. Sales, customer collections, refunds and expenses keep `bank` as their canonical code. Purchase and supplier commands keep `bank_transfer`. Stored history and frozen client retry payloads retain their original values.

- API `b4225a0` passed 399 unit tests, lint, and three PostgreSQL integration scenarios covering sale, payment, refund, customer collection, purchase and supplier replay and recovery.
- Web `8c60977` explicitly labels both historical spellings as Bank transfer. The 138 targeted tests, typecheck, lint and build passed. Generated API types `f958041` document both accepted inputs. Production Docker smoke passed. Web display coverage used component tests.
- Android `733f9e6` recognizes the alias in editable checkout drafts and uses the shared label in billing. Supplier payment staging uses its existing wire spelling. The analyzer and 13 focused tests passed. The emulator restored a draft containing `bank_transfer`, retained reference `NEFT-901`, and saved the partial Bank transfer payment through the normal checkout.
