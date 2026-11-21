# E01 slice 2 — posting, payment attempts and browser ownership

18 November 2026. Scope: [slice contract](../../contracts/E01-slice-2.md). Three repository agents implemented independent production paths; coordinator reviewed recovery boundaries and owns shared environment tests.

## Committed implementation

- API `2161b5a`: shared transaction lock before receipt/payment creation and reversal replay classification. Document, stock, allocations and audit remain in one transaction. Deterministic held-lock tests verify concurrent requests emit one audit action; injected audit failure rolls back the aggregate. Negative control bypassing only the route lock reproduces duplicate audit actions. 25 purchase integration tests and 317 unit tests pass; lint/type/security pass.
- API `7a37aed`: actual route regression confirms alternate UUID spellings get 404 before posting lock. Shop IDs are exact-text tenant identities; no unnecessary canonicalization was introduced. Final posting suite: 3 passed.
- Mobile `d29405f`, contract `333ee14`: SQLite v26 adds local attempt metadata, atomic send claim and explicit uncertain recovery with captured-shop acknowledgements. Legacy pending and interrupted sending recover as unknown; exact request payload/key survive restart/backup. Definitive rejection differs from uncertain replay or conflict. 36 focused tests and analyzer pass, with an additional final migration regression pass.
- Web `ce39ed1`: Web Locks serialize draft compare/write/readback; frozen attempts cannot be overwritten by queued autosave. Unsupported/denied locks fail closed. Lifetime/owner guards prevent unmounted pages from sending and queued writes from recreating signout-cleared drafts. 370 tests, 56 focused final checkout/store tests, typecheck/lint/production build pass. Real same-origin two-tab lock contention and closed-owner release pass; real API committed/lost-response reload retry again passes with one stock decrement.

## Coordinator validation

- Generated sync mapping v5: mobile field-contract test passed; only local supplier-payment metadata added, not generic cloud row-sync fields. Diagnostic description includes rejection and uncertainty. Final mobile mapping test passed (1); API `test_complete_sync.py` passed (3) against scratch PostgreSQL. API fixture committed as `0d14ee8`.
- Browser synthetic shop/account/mail and credential files were removed by exact run-owned IDs. No user-owned fixtures were modified.
- Actual API 35 emulator: `make test-device-premium DEVICE=emulator-5554` passed (exit 0, 1 scenario), including premium activation, all-table clean restore and two-device/web roundtrip. Screenshot pull succeeded (266,474 bytes); review artifact `/tmp/storely-e01-slice2-artifacts/premium-activated.png`. This broad regression complements the focused queue tests; it does not itself exercise every new uncertain-send state.
- Isolated `make test-platform` passed (exit 0), final API image `66200457e11db208d734ad24f70eed82fc52d8101fb17d875bab445fc692e4b0`, web image `adf6abe2ea94af848666aac99ba60191a96cf02d451c5914f30d20e0c39a2fbb`. Verified production bootstrap/repeated migrations, TLS database, runtime-role restrictions, portable frontend proxy/deep links/API errors/cache/security headers and missing assets. No deployment was performed.

## Remaining E01 work and limits

This slice does not complete E01. Durable server job/outbox execution, expected-revision/version negotiation, generic local command coverage and future journal posting adapters remain open. Existing auth emails still use BackgroundTasks; sensitive delivery persistence needs an explicit lifecycle design.

API follow-up **E01-FOLLOWUP-01**: selected purchase allocation intent is currently excluded from supplier-payment fingerprinting. See `storelyapi/docs/refactor-e01-posting-boundary.md` for evidence and the proposed additive versioned binding migration. Historical hashes must not be silently rewritten.

Unresolved mobile payments conservatively reserve balance. If the server feed includes the committed payment before its UUID is recovered, the local provisional balance may understate what is available until authorized replay/reconciliation succeeds. No heuristic matching or permission bypass is used. Web locking coordinates current cooperating clients on one browser origin; an old client that writes localStorage without the lock is outside that guarantee. Explicit signout retains existing draft-clearing privacy policy. Human UX acceptance remains E18.
