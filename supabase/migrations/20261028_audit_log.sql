-- 2.0 Phase 5: audit trail for bill corrections (cancel, payment, marked
-- unpaid, customer edits, credit notes). Append-only: members can add and
-- read entries; nobody can change or delete one (an update keeps the stored
-- row). Additive and idempotent.

create table if not exists public.audit_log (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  entity_type text not null,
  entity_uuid text not null,
  action text not null,
  details text,
  actor text,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default now()
);

alter table public.audit_log enable row level security;

drop policy if exists "Members can read audit log" on public.audit_log;
create policy "Members can read audit log"
on public.audit_log for select
using (public.is_shop_member(shop_id));

drop policy if exists "Members can add audit log" on public.audit_log;
create policy "Members can add audit log"
on public.audit_log for insert
with check (public.is_shop_member(shop_id));

-- Re-uploads of an entry are accepted but never change it.
drop policy if exists "Members can resend audit log" on public.audit_log;
create policy "Members can resend audit log"
on public.audit_log for update
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

create or replace function public.storely_audit_log_immutable()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  return old;
end;
$$;

drop trigger if exists storely_audit_log_immutable on public.audit_log;
create trigger storely_audit_log_immutable before update
on public.audit_log for each row execute function
public.storely_audit_log_immutable();

drop trigger if exists storely_sync_before_write on public.audit_log;
create trigger storely_sync_before_write before insert
on public.audit_log for each row execute function
public.storely_sync_before_write();

create index if not exists idx_audit_log_shop_server_updated
on public.audit_log (shop_id, server_updated_at, uuid);
create index if not exists idx_audit_log_entity
on public.audit_log (entity_uuid);

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
    'bill_items', 'bill_payments', 'stock_movements', 'expenses', 'audit_log'
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
