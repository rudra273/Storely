-- 2.0 Sync v2 (server side). Additive and idempotent: safe to re-run.
--
-- 1. server_updated_at: set by the server on every write. Devices pull by
--    this server clock (never by their own clock), so a row uploaded late by
--    an offline phone is still seen by everyone.
-- 2. storely_sync_before_write(): conflict rules enforced on the server,
--    whoever uploads first:
--    - latest edit wins: an upload older (by updated_at) than the stored row
--      is ignored;
--    - deletion / cancellation always wins, even when it is the older edit;
--    - deleted billing records stay deleted (a stale copy cannot bring a
--      cancelled bill back).
-- 3. sync_pull(): one page of a table's changes, ordered by
--    (server_updated_at, key) for stable keyset paging. Runs as the caller,
--    so Row Level Security still decides what is visible.

create or replace function public.storely_sync_before_write()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  sticky boolean := tg_table_name in (
    'bills', 'bill_items', 'bill_payments', 'stock_movements'
  );
  incoming_ts timestamptz;
  stored_ts timestamptz;
  deletion jsonb;
begin
  new.server_updated_at := now();
  if tg_op = 'INSERT' then
    return new;
  end if;

  -- Deleted billing records stay deleted.
  if sticky and old.deleted_at is not null and new.deleted_at is null then
    new.deleted_at := old.deleted_at;
    if tg_table_name = 'bills' then
      new := jsonb_populate_record(new, jsonb_build_object(
        'lifecycle_status', to_jsonb(old) ->> 'lifecycle_status',
        'cancelled_at', to_jsonb(old) ->> 'cancelled_at',
        'cancel_reason', to_jsonb(old) ->> 'cancel_reason'
      ));
    end if;
  end if;

  incoming_ts := nullif(new.updated_at, '')::timestamptz;
  stored_ts := nullif(old.updated_at, '')::timestamptz;
  if incoming_ts is null or stored_ts is null or incoming_ts >= stored_ts then
    return new;
  end if;

  -- The upload is older than what is stored. Keep the stored row, except
  -- that a deletion still applies.
  if old.deleted_at is null and new.deleted_at is not null then
    deletion := jsonb_build_object('deleted_at', new.deleted_at);
    if tg_table_name = 'bills' then
      deletion := deletion || jsonb_build_object(
        'lifecycle_status', to_jsonb(new) ->> 'lifecycle_status',
        'cancelled_at', to_jsonb(new) ->> 'cancelled_at',
        'cancel_reason', to_jsonb(new) ->> 'cancel_reason'
      );
    end if;
    new := jsonb_populate_record(old, deletion);
    new.server_updated_at := now();
    return new;
  end if;
  return null;
end;
$$;

do $$
declare
  t text;
  key_column text;
begin
  foreach t in array array[
    'shops', 'app_settings', 'bill_settings', 'categories', 'units',
    'suppliers', 'customers', 'products', 'invoice_series', 'bills',
    'bill_items', 'bill_payments', 'stock_movements'
  ] loop
    execute format(
      'alter table public.%I add column if not exists server_updated_at '
      'timestamptz not null default now()', t);
    execute format(
      'drop trigger if exists storely_sync_before_write on public.%I', t);
    execute format(
      'create trigger storely_sync_before_write before insert or update '
      'on public.%I for each row execute function '
      'public.storely_sync_before_write()', t);
    key_column := case t when 'app_settings' then 'key' else 'uuid' end;
    if t = 'shops' then
      execute 'create index if not exists idx_shops_server_updated '
        'on public.shops (server_updated_at, uuid)';
    else
      execute format(
        'create index if not exists %I on public.%I '
        '(shop_id, server_updated_at, %I)',
        'idx_' || t || '_shop_server_updated', t, key_column);
    end if;
  end loop;
end;
$$;

create or replace function public.sync_pull(
  p_table text,
  p_shop_id text,
  p_after_ts timestamptz,
  p_after_key text,
  p_limit integer default 500
)
returns setof jsonb
language plpgsql
stable
security invoker
set search_path = public
as $$
declare
  key_column text;
  shop_column text;
begin
  if p_table not in (
    'shops', 'app_settings', 'bill_settings', 'categories', 'units',
    'suppliers', 'customers', 'products', 'invoice_series', 'bills',
    'bill_items', 'bill_payments', 'stock_movements'
  ) then
    raise exception 'sync_pull: unknown table %', p_table;
  end if;
  key_column := case p_table when 'app_settings' then 'key' else 'uuid' end;
  shop_column := case p_table when 'shops' then 'uuid' else 'shop_id' end;
  return query execute format(
    'select to_jsonb(t) from public.%I t '
    'where t.%I = $1 and (t.server_updated_at, t.%I) > ($2, $3) '
    'order by t.server_updated_at, t.%I limit $4',
    p_table, shop_column, key_column, key_column)
  using p_shop_id, p_after_ts, coalesce(p_after_key, ''),
        least(greatest(coalesce(p_limit, 500), 1), 1000);
end;
$$;

grant execute on function public.sync_pull(text, text, timestamptz, text, integer)
  to authenticated;
