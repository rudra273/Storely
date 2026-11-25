# Native sale posting verification

API `f7e45f2` posts a matching recorded sale through the existing billing transaction. It retains the invoice number and UUID and the recorded line, initial payment and movement UUIDs. A conflicting row cannot be overwritten. The transaction includes the idempotency key and stock balance refresh.

- Docker tests sent the same operation concurrently and got one 201 and one 200 replay. They verified recovery by the original key, a subsequent exact replay, rejection of changed content, rejection of a second key for the same invoice, and denial when a different account tries to post from that registered device.
- A later stock movement collision rolled back the second invoice, lines, payment and key. A corrected request then used the same previously uncommitted key successfully. All 427 API integration tests and the full lint gate passed. The integration suite reported its existing duplicate health operation ID warning.
- A localhost TLS smoke posted and recovered one synthetic invoice and checked its original IDs. The shop, account and mail were removed. Production Docker smoke passed.
- Web commit `da8de34` updates the generated API types. Typecheck and API type consistency passed. The subsequent [Android delivery verification](android-native-sale-delivery.md) covers the opt-in device transport.
