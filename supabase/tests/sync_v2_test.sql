-- Sync v2 server rules: server clock, latest-edit-wins, deletion wins,
-- sticky cancellations, keyset paging, RLS on sync_pull.
\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.check(ok boolean, what text) returns void
language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', what; end if;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in'),
  ('00000000-0000-0000-0000-0000000000b2', 'stranger@other.in');

select tests.login('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in');
select public.create_shop('shop-1', 'Sharma Kirana');

insert into public.categories (uuid, shop_id, name, created_at, updated_at)
values ('cat-1', 'shop-1', 'Snacks', '2026-10-01T10:00:00Z', '2026-10-01T10:00:00Z');

-- Latest edit wins: an older upload is ignored.
insert into public.categories (uuid, shop_id, name, created_at, updated_at)
values ('cat-1', 'shop-1', 'Old name', '2026-10-01T10:00:00Z', '2026-10-01T09:00:00Z')
on conflict (uuid) do update set name = excluded.name, updated_at = excluded.updated_at;
select pg_temp.check(
  (select name from public.categories where uuid = 'cat-1') = 'Snacks',
  'older upload must not overwrite a newer row');

-- A newer upload applies.
insert into public.categories (uuid, shop_id, name, created_at, updated_at)
values ('cat-1', 'shop-1', 'Namkeen', '2026-10-01T10:00:00Z', '2026-10-01T11:00:00Z')
on conflict (uuid) do update set name = excluded.name, updated_at = excluded.updated_at;
select pg_temp.check(
  (select name from public.categories where uuid = 'cat-1') = 'Namkeen',
  'newer upload must apply');

-- Bill: edited on phone B at 10:05, cancelled on phone A at 10:00 but
-- uploaded later. The cancellation still wins.
insert into public.bills (uuid, shop_id, bill_number, customer_name,
  total_amount, item_count, created_at, updated_at)
values ('bill-1', 'shop-1', 'INV/2627/0001', 'Asha', 100, 1,
  '2026-10-01T09:00:00Z', '2026-10-01T10:05:00Z');
insert into public.bills (uuid, shop_id, bill_number, customer_name,
  total_amount, item_count, lifecycle_status, cancelled_at, cancel_reason,
  created_at, updated_at, deleted_at)
values ('bill-1', 'shop-1', 'INV/2627/0001', 'Asha', 100, 1, 'cancelled',
  '2026-10-01T10:00:00Z', 'Wrong item',
  '2026-10-01T09:00:00Z', '2026-10-01T10:00:00Z', '2026-10-01T10:00:00Z')
on conflict (uuid) do update set
  lifecycle_status = excluded.lifecycle_status,
  cancelled_at = excluded.cancelled_at,
  cancel_reason = excluded.cancel_reason,
  updated_at = excluded.updated_at,
  deleted_at = excluded.deleted_at;
select pg_temp.check(
  (select deleted_at is not null and lifecycle_status = 'cancelled'
     and cancel_reason = 'Wrong item'
   from public.bills where uuid = 'bill-1'),
  'older cancellation must still cancel the bill');

-- A stale, newer-looking copy cannot bring the cancelled bill back.
insert into public.bills (uuid, shop_id, bill_number, customer_name,
  total_amount, item_count, lifecycle_status, created_at, updated_at)
values ('bill-1', 'shop-1', 'INV/2627/0001', 'Asha', 100, 1, 'finalized',
  '2026-10-01T09:00:00Z', '2026-10-01T12:00:00Z')
on conflict (uuid) do update set
  lifecycle_status = excluded.lifecycle_status,
  updated_at = excluded.updated_at,
  deleted_at = excluded.deleted_at;
select pg_temp.check(
  (select deleted_at is not null and lifecycle_status = 'cancelled'
   from public.bills where uuid = 'bill-1'),
  'cancelled bill must stay cancelled');

-- Every write is stamped with the server clock.
select pg_temp.check(
  (select count(*) = 0 from public.categories where server_updated_at is null),
  'server_updated_at is always set');

-- Keyset paging returns every row exactly once, in order.
insert into public.categories (uuid, shop_id, name, created_at, updated_at)
select 'cat-p' || lpad(i::text, 3, '0'), 'shop-1', 'Cat ' || i,
       '2026-10-01T10:00:00Z', '2026-10-01T10:00:00Z'
from generate_series(1, 25) i;
do $$
declare
  after_ts timestamptz := '-infinity';
  after_key text := '';
  page jsonb[];
  seen int := 0;
  pages int := 0;
begin
  loop
    select array_agg(r) into page
    from public.sync_pull('categories', 'shop-1', after_ts, after_key, 10) r;
    exit when page is null;
    pages := pages + 1;
    seen := seen + array_length(page, 1);
    after_ts := (page[array_length(page, 1)] ->> 'server_updated_at')::timestamptz;
    after_key := page[array_length(page, 1)] ->> 'uuid';
  end loop;
  perform pg_temp.check(seen = 26, 'paging must return all 26 rows, got ' || seen);
  perform pg_temp.check(pages = 3, 'expected 3 pages of 10, got ' || pages);
end $$;

-- app_settings pages by key.
insert into public.app_settings (key, shop_id, value, updated_at)
values ('gst_scheme', 'shop-1', 'regular', '2026-10-01T10:00:00Z');
select pg_temp.check(
  (select count(*) = 1 from public.sync_pull('app_settings', 'shop-1', '-infinity', '', 10)),
  'app_settings pull by key');

-- RLS: another user sees nothing of this shop through sync_pull.
select tests.logout();
select tests.login('00000000-0000-0000-0000-0000000000b2', 'stranger@other.in');
select pg_temp.check(
  (select count(*) = 0 from public.sync_pull('categories', 'shop-1', '-infinity', '', 100)),
  'non-member must not see shop rows via sync_pull');
select tests.logout();

do $$ begin
  perform public.sync_pull('profiles', 'shop-1', '-infinity', '', 10);
  raise exception 'FAILED: unknown table accepted';
exception when others then
  if sqlerrm like 'FAILED%' then raise; end if;
end $$;

rollback;
