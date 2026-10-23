-- 2.0: permissions enforced by the server, not just hidden in the app.
-- Additive and idempotent: safe to re-run.
--
-- - Admins manage staff/admins but can never touch the owner: no promoting
--   anyone (or themselves) to owner, no demoting or removing the owner.
--   Only the owner can delete the shop.
-- - Billing records (bills, items, payments, stock movements) and customers
--   can never be hard-deleted by anyone; cancelling is a soft delete.
-- - Staff can create bills, items, sale stock movements, payments and
--   customers, but cannot change or cancel existing billing records, or
--   post stock adjustments. Owners/admins can.

create or replace function public.is_shop_owner(target_shop_id text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.shop_members
    where shop_id = target_shop_id
      and user_id = auth.uid()
      and role = 'owner'
  );
$$;

-- ── Shop members ──
drop policy if exists "Owners and admins can manage shop members" on public.shop_members;

drop policy if exists "Admins can add members" on public.shop_members;
create policy "Admins can add members"
on public.shop_members for insert
with check (public.can_manage_shop_members(shop_id) and role <> 'owner');

drop policy if exists "Admins can change member roles" on public.shop_members;
create policy "Admins can change member roles"
on public.shop_members for update
using (public.can_manage_shop_members(shop_id) and role <> 'owner')
with check (public.can_manage_shop_members(shop_id) and role <> 'owner');

drop policy if exists "Admins can remove members" on public.shop_members;
create policy "Admins can remove members"
on public.shop_members for delete
using (public.can_manage_shop_members(shop_id) and role <> 'owner');

drop policy if exists "Members can leave a shop" on public.shop_members;
create policy "Members can leave a shop"
on public.shop_members for delete
using ((select auth.uid()) = user_id and role <> 'owner');

-- ── Shops ──
drop policy if exists "Admins can delete shops" on public.shops;
drop policy if exists "Owner can delete shop" on public.shops;
create policy "Owner can delete shop"
on public.shops for delete
using (public.is_shop_owner(uuid));

-- ── Operating tables: read/insert/update for members, never delete ──
do $$
declare
  t text;
begin
  foreach t in array array[
    'customers', 'bills', 'bill_items', 'bill_payments', 'stock_movements'
  ] loop
    execute format('drop policy if exists %I on public.%I',
      'Members can sync ' || t, t);
    execute format('drop policy if exists %I on public.%I',
      'Members can read ' || t, t);
    execute format('create policy %I on public.%I for select '
      'using (public.is_shop_member(shop_id))', 'Members can read ' || t, t);
    execute format('drop policy if exists %I on public.%I',
      'Members can add ' || t, t);
    execute format('create policy %I on public.%I for insert '
      'with check (public.is_shop_member(shop_id))', 'Members can add ' || t, t);
    execute format('drop policy if exists %I on public.%I',
      'Members can update ' || t, t);
    execute format('create policy %I on public.%I for update '
      'using (public.is_shop_member(shop_id)) '
      'with check (public.is_shop_member(shop_id))', 'Members can update ' || t, t);
  end loop;
end;
$$;

-- What staff may write on billing tables. Runs after the sync trigger
-- (triggers fire in name order), so a stale upload it skipped never gets
-- here and sticky deletions are already restored.
create or replace function public.storely_zz_guard_staff_write()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  -- Derived or link columns any device may refresh.
  ignored text[] := array[
    'server_updated_at', 'updated_at', 'paid_amount', 'balance_due',
    'payment_status', 'is_paid', 'payment_method', 'customer_uuid'
  ];
begin
  -- Service role / dashboard (no end user) and owners/admins are not limited.
  if auth.uid() is null or public.is_shop_admin(new.shop_id) then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.deleted_at is not null then
      raise exception 'Staff cannot create cancelled records'
        using errcode = '42501';
    end if;
    if tg_table_name = 'stock_movements'
       and (to_jsonb(new) ->> 'movement_type') is distinct from 'sale' then
      raise exception 'Staff can only record sales stock movements'
        using errcode = '42501';
    end if;
    return new;
  end if;

  if (to_jsonb(new) - ignored) is distinct from (to_jsonb(old) - ignored) then
    raise exception 'Only the owner or an admin can change or cancel %',
      tg_table_name using errcode = '42501';
  end if;
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'bills', 'bill_items', 'bill_payments', 'stock_movements'
  ] loop
    execute format(
      'drop trigger if exists storely_zz_guard_staff_write on public.%I', t);
    execute format(
      'create trigger storely_zz_guard_staff_write before insert or update '
      'on public.%I for each row execute function '
      'public.storely_zz_guard_staff_write()', t);
  end loop;
end;
$$;
