# E03.3C Cross-Device Single-Consumer Draft Handoff Contract

**Slice:** E03.3C  
**Feature ID:** `O16`  
**Status:** Frozen for parallel implementation across `storelyapi`, `Storely` (mobile), and `storelyweb`.

## 1. Single-Consumer Ownership Model

Existing `held_bills` sync remains a read-only backup for offline mobile devices (preserving `guard_private_sync_row()` and `origin_device_id` immutability). True cross-device handoff (Web ↔ Mobile, Web ↔ Web, Mobile ↔ Mobile) is mediated by a dedicated server-authoritative `public.draft_handoffs` ledger with atomic single-consumer claiming:

1. **Publish / Send to another device**: A device uploads a complete checkout snapshot (`label`, `items`, `metadata`) and removes (or parks) its local active cart once the server returns `201 Created`.
2. **List available handoffs**: Any device signed in as the same `(shop_id, owner_user_id)` sees available (`status = 'available'`) handoffs (and clearly labels which device sent them).
3. **Atomic Claim (Single Consumer)**: Claiming executes a single atomic SQL `UPDATE public.draft_handoffs SET status = 'claimed', claimed_by_device = :device, claimed_at = now() WHERE uuid = :id AND shop_id = :shop AND owner_user_id = :user AND status = 'available' RETURNING *`.
   - Exactly **one** caller receives `200 OK` with the full `items` + `metadata` payload and hydrates its local checkout draft.
   - Any concurrent or duplicate claim receives **`409 draft_already_claimed`** — preventing duplicate billing across devices.
4. **Discard**: An unclaimed handoff (`status = 'available'`) can be discarded (`DELETE`, setting `status = 'discarded'`). Claimed handoffs cannot be discarded (`409 draft_already_claimed`).

## 2. Schema (`0028_e03_3c_draft_handoff`, `revision = "0028"`, `down_revision = "0027"`)

```sql
create table if not exists public.draft_handoffs (
    uuid uuid primary key default gen_random_uuid(),
    shop_id uuid not null references public.shops(id) on delete cascade,
    owner_user_id uuid not null references app.users(id) on delete cascade,
    source_device_label text not null,
    label text not null default '',
    items_json jsonb not null,
    metadata_json jsonb not null default '{}'::jsonb,
    status text not null default 'available' check (status in ('available', 'claimed', 'discarded')),
    claimed_by_device text,
    claimed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
```
- Enable RLS on `public.draft_handoffs` with policy restricting all operations to `owner_user_id = app.uid() and public.is_shop_member(shop_id)`.
- Index on `(shop_id, owner_user_id, status, created_at desc)`.

## 3. API Endpoints & Capability

- Advertise `"draft_handoff": 1` in `GET /v1/shops/{shop_id}/capabilities`.
- All 4 routes require `shops.ANY_MEMBER` and `require_premium=True`, and MUST be registered in `tests/test_authorization_matrix.py`:
  1. `POST /v1/shops/{shop_id}/draft-handoffs` (`201 Created`):
     - Body (`DraftHandoffIn`, `extra="forbid"`): `source_device_label: str` (1..80 chars), `label: str = ""` (0..120 chars), `items: list[dict[str, Any]]` (1..200 items), `metadata: dict[str, Any] = {}`.
     - Returns `DraftHandoffOut` (`uuid`, `source_device_label`, `label`, `item_count`, `items`, `metadata`, `status`, `claimed_by_device`, `claimed_at`, `created_at`).
  2. `GET /v1/shops/{shop_id}/draft-handoffs` (`200 OK`):
     - Returns `DraftHandoffListOut` (`items: list[DraftHandoffSummary]` of `status = 'available'` handoffs for `(shop_id, user.id)`, newest first, limit 50).
  3. `POST /v1/shops/{shop_id}/draft-handoffs/{handoff_id}/claim` (`200 OK`):
     - Body (`DraftHandoffClaimIn`, `extra="forbid"`): `device_label: str` (1..80 chars).
     - Atomically transitions `available -> claimed` and returns `DraftHandoffOut` (with full `items` and `metadata`).
     - Returns `404 not_found` if absent or another user's/shop's, `409 draft_already_claimed` if already claimed or discarded.
  4. `DELETE /v1/shops/{shop_id}/draft-handoffs/{handoff_id}` (`204 No Content`):
     - Transitions `available -> discarded`. Returns `404` if not found, `409 draft_already_claimed` if already claimed.

## 4. Client Workflows

- **Web (`NewBill.tsx`)**:
  - In the Held invoices / checkout actions area: add `Send to another device` button (publishes current cart + metadata via `POST /draft-handoffs`, then clears active cart cleanly) and a `Cloud handoffs` section showing available `GET /draft-handoffs` items with `Take over` (`POST .../claim` -> hydrates cart & metadata) and `Discard` (`DELETE ...`).
  - Existing browser-local held carts remain clearly labeled `"Saved in this browser for this account and shop."`.
- **Mobile (`ScanScreen`, `CloudService`, `_HeldBillsSheet`)**:
  - Add `CloudService` methods: `publishDraftHandoff`, `listDraftHandoffs`, `claimDraftHandoff`, `discardDraftHandoff`.
  - In `ScanScreen` / `_HeldBillsSheet` (when cloud-signed-in & premium; local-only mode unaffected): add `Send to another device` action and a `Cloud handoffs` section with `Take over` (atomically claims from API and loads into active cart) and `Discard`. Existing synced `held_bills` backups remain clearly labeled read-only.

## 5. Acceptance Scenarios
- `S-E03.3C-1`: API integration test verifies publish -> list -> atomic claim -> second claim returns `409 draft_already_claimed`, cross-user/cross-shop RLS isolation (`404`), discard guard, and `test_authorization_matrix.py`.
- `S-E03.3C-2`: Web tests verify publishing a draft handoff, listing & claiming a remote handoff into `NewBill`, handling `409 draft_already_claimed`, and discarding.
- `S-E03.3C-3`: Mobile tests verify `CloudService` handoff client + `ScanScreen` / `_HeldBillsSheet` publish/claim/409 handling while keeping local-only mode completely unaffected.
