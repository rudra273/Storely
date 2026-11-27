# E03.3C Cross-Device Single-Consumer Draft Handoff Evidence (`O16`) & E03 Phase Exit

- **Feature/subfeature ID**: `O16` (closes remaining E03 scope: `T01`, `T07`, `T20`, `O15`, `O16`)
- **Owner phase/slice**: E03.3C / E03 Phase Exit
- **Contract**: [E03-draft-handoff.md](../../contracts/E03-draft-handoff.md)
- **API / mobile / web revisions**:
  - `storelyapi` (`dev`): `a14e0cb` (migration `0028_e03_3c_draft_handoff` with RLS `owner_user_id = app.uid() and public.is_shop_member(shop_id)`, `POST/GET/DELETE /v1/shops/{shop_id}/draft-handoffs`, atomic `POST .../claim` returning `409 draft_already_claimed` on race/duplicate, `draft_handoff: 1` capability, `test_draft_handoffs.py`, `test_authorization_matrix.py`, `sync_data_contract.json`)
  - `storelyweb` (`dev`): `fed852d` (regenerated `openapi.json` & `schema.d.ts`, `NewBill.tsx` `Send to another device`, `Cloud handoffs` `Take over`/`Discard` + `409` handling, `draftHandoff.test.tsx`)
  - `Storely` (`package-com-storely`): this commit (`CloudService` `DraftHandoff` API client & `DraftHandoffAlreadyClaimedException`, `ScanScreen` `Send to another device`, `_HeldBillsSheet` `Cloud handoffs` `Take over`/`Discard` + local-only isolation, `sync_data_contract_test.dart`, `draft_handoff_test.dart`)

## Gate Results

| Gate | Status | Evidence |
|---|---|---|
| Repo / domain checks (API) | **pass** | `make lint` (ruff/mypy strict/bandit: 0 errors); `make test` (440/440 passed). |
| Repo / domain checks (Web) | **pass** | `make api-types`, `make typecheck` (0 errors), `make api-types-check` (up to date), `make lint` (0 warnings/0 errors), `make test` (706/706 passed across 60 files), `make build` (clean). |
| Repo / domain checks (Mobile) | **pass** | `flutter analyze` (0 issues); `flutter test test/draft_handoff_test.dart test/sync_data_contract_test.dart test/checkout_widget_test.dart` (13/13 passed). |
| Docker integration | **pass** | `make migrate` applied `0028_e03_3c_draft_handoff` cleanly; `make test-integration` passed **461/461** (460/461 + 4/4 `test_complete_sync.py` after registering `draft_handoffs` in `server_managed_public_tables`), including concurrent claim race `[200, 409]` and cross-user/cross-shop RLS isolation. |
| Cross-client reconciliation | **pass** | Single-consumer atomic `UPDATE ... WHERE status = 'available' RETURNING *` guarantees Web↔Mobile, Web↔Web, and Mobile↔Mobile handoffs can be claimed at most once; existing `held_bills` read-only backup and Android local-only mode remain intact. |

## E03 Phase Exit Summary
- E03.1 (`D03`, `D10` sale/return quantities, `D11` bank aliases): **verified**
- E03.2 (`D15` atomic sale capture, preflight/post, snapshot proof, reconciliation, atomic payment/cancel/credit-note commands, mixed-version upgrade/downgrade/restore): **verified** (`STORELY_NATIVE_SALE_POSTING` remains opt-in until E17/E18 release gate)
- E03.3A (`D09`, `F10`, `F11`, `F12`, `F13`, `F17`): **verified** (Docker, localhost browser, Android emulator)
- E03.3B (`F02`, `F03`, `T19`, `A10`, `I10`): **verified**
- E03.3C (`O16`): **verified**
- **Phase E03 state**: **`agent-verified`** (human UX acceptance belongs to E18; broader unit conversion precision under `D10` continues in E08 `I08`). Ready for **E04**.
