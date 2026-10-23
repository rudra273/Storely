-- 2.0 Phase 4b: shop expenses (rent, salary, tea, transport...).
-- Feeds the day book (closing cash) and the P&L.
-- Members can read; only the owner or an admin can add or change them
-- (staff only bill and collect payments). Never hard-deleted: deleted_at.
-- Additive and idempotent.

create table if not exists public.expenses (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  expense_date text not null,
  amount double precision not null check (amount >= 0),
  category text not null default 'Other',
  payment_method text not null default 'cash',
  notes text,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text,
  server_updated_at timestamptz not null default now()
);

alter table public.expenses enable row level security;

drop policy if exists "Members can read expenses" on public.expenses;
create policy "Members can read expenses"
on public.expenses for select
using (public.is_shop_member(shop_id));

drop policy if exists "Admins can add expenses" on public.expenses;
create policy "Admins can add expenses"
on public.expenses for insert
with check (public.is_shop_admin(shop_id));

drop policy if exists "Admins can update expenses" on public.expenses;
create policy "Admins can update expenses"
on public.expenses for update
using (public.is_shop_admin(shop_id))
with check (public.is_shop_admin(shop_id));

drop trigger if exists storely_sync_before_write on public.expenses;
create trigger storely_sync_before_write before insert or update
on public.expenses for each row execute function
public.storely_sync_before_write();

create index if not exists idx_expenses_shop_server_updated
on public.expenses (shop_id, server_updated_at, uuid);
create index if not exists idx_expenses_shop_date
on public.expenses (shop_id, expense_date);

-- sync_pull learns the new table.
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
    'bill_items', 'bill_payments', 'stock_movements', 'expenses'
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
