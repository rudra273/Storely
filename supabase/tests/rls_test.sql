-- Row Level Security: owner/admin/staff/outsider permissions.
\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.check(ok boolean, what text) returns void
language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', what; end if;
end $$;

-- Runs sql as the current user and returns true if it was refused.
create or replace function pg_temp.refused(sql text) returns boolean
language plpgsql as $$
begin
  execute sql;
  return false;
exception when insufficient_privilege or check_violation then
  return true;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in'),
  ('00000000-0000-0000-0000-0000000000a2', 'admin@shop.in'),
  ('00000000-0000-0000-0000-0000000000a3', 'staff@shop.in'),
  ('00000000-0000-0000-0000-0000000000a4', 'stranger@other.in');
insert into public.profiles (id, email)
select id, email from auth.users on conflict (id) do nothing;

-- Owner registers the shop and adds an admin and a staff member.
select tests.login('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in');
select public.create_shop('shop-1', 'Sharma Kirana');
insert into public.shop_members (shop_id, user_id, role) values
  ('shop-1', '00000000-0000-0000-0000-0000000000a2', 'admin'),
  ('shop-1', '00000000-0000-0000-0000-0000000000a3', 'staff');
insert into public.products (uuid, shop_id, name, created_at, updated_at)
values ('prod-1', 'shop-1', 'Rice', '2026-10-01T00:00:00Z', '2026-10-01T00:00:00Z');
select tests.logout();

-- ── Admin cannot take over the shop ──
select tests.login('00000000-0000-0000-0000-0000000000a2', 'admin@shop.in');
update public.shop_members set role = 'staff'
where shop_id = 'shop-1' and user_id = '00000000-0000-0000-0000-0000000000a1';
delete from public.shop_members
where shop_id = 'shop-1' and user_id = '00000000-0000-0000-0000-0000000000a1';
select pg_temp.check(
  public.get_shop_role('shop-1') = 'admin', 'admin is still admin');
select pg_temp.check(
  pg_temp.refused($$update public.shop_members set role = 'owner'
    where shop_id = 'shop-1'
      and user_id = '00000000-0000-0000-0000-0000000000a2'$$),
  'admin cannot promote self to owner');
select pg_temp.check(
  pg_temp.refused($$insert into public.shop_members (shop_id, user_id, role)
    values ('shop-1', '00000000-0000-0000-0000-0000000000a4', 'owner')$$),
  'admin cannot add an owner');
delete from public.shops where uuid = 'shop-1';
select pg_temp.check(
  exists (select 1 from public.shops where uuid = 'shop-1'),
  'admin cannot delete the shop');
-- Admin can still manage staff.
update public.shop_members set role = 'admin'
where shop_id = 'shop-1' and user_id = '00000000-0000-0000-0000-0000000000a3';
update public.shop_members set role = 'staff'
where shop_id = 'shop-1' and user_id = '00000000-0000-0000-0000-0000000000a3';
select tests.logout();

select tests.login('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in');
select pg_temp.check(
  (select role from public.shop_members
   where shop_id = 'shop-1'
     and user_id = '00000000-0000-0000-0000-0000000000a1') = 'owner',
  'owner row untouched');
select pg_temp.check(
  (select role from public.shop_members
   where shop_id = 'shop-1'
     and user_id = '00000000-0000-0000-0000-0000000000a3') = 'staff',
  'admin managed staff role');
select tests.logout();

-- ── Staff: bill and collect only ──
select tests.login('00000000-0000-0000-0000-0000000000a3', 'staff@shop.in');
insert into public.bills (uuid, shop_id, bill_number, customer_name,
  total_amount, item_count, created_at, updated_at)
values ('bill-1', 'shop-1', 'INV/2627/B0001', 'Asha', 100, 1,
  '2026-10-01T09:00:00Z', '2026-10-01T09:00:00Z');
insert into public.bill_items (uuid, shop_id, bill_uuid, product_uuid,
  product_name, quantity, subtotal, created_at, updated_at)
values ('item-1', 'shop-1', 'bill-1', 'prod-1', 'Rice', 1, 100,
  '2026-10-01T09:00:00Z', '2026-10-01T09:00:00Z');
insert into public.stock_movements (uuid, shop_id, product_uuid,
  movement_type, quantity_delta, created_at, updated_at)
values ('mv-1', 'shop-1', 'prod-1', 'sale', -1,
  '2026-10-01T09:00:00Z', '2026-10-01T09:00:00Z');
insert into public.bill_payments (uuid, shop_id, bill_uuid, amount,
  payment_method, received_at, created_at, updated_at)
values ('pay-1', 'shop-1', 'bill-1', 100, 'cash',
  '2026-10-01T09:00:00', '2026-10-01T09:00:00Z', '2026-10-01T09:00:00Z');

-- An identical re-upload (retry) is fine; so is refreshing derived fields.
insert into public.bills (uuid, shop_id, bill_number, customer_name,
  total_amount, item_count, created_at, updated_at)
values ('bill-1', 'shop-1', 'INV/2627/B0001', 'Asha', 100, 1,
  '2026-10-01T09:00:00Z', '2026-10-01T09:00:00Z')
on conflict (uuid) do update set total_amount = excluded.total_amount;
update public.bills set paid_amount = 100, payment_status = 'paid'
where uuid = 'bill-1';

select pg_temp.check(
  pg_temp.refused($$update public.bills set deleted_at = '2026-10-02T00:00:00Z',
    lifecycle_status = 'cancelled', updated_at = '2026-10-02T00:00:00Z'
    where uuid = 'bill-1'$$),
  'staff cannot cancel a bill');
select pg_temp.check(
  pg_temp.refused($$update public.bills set total_amount = 1,
    updated_at = '2026-10-02T00:00:00Z' where uuid = 'bill-1'$$),
  'staff cannot change a bill amount');
select pg_temp.check(
  pg_temp.refused($$update public.bill_payments set amount = 1,
    updated_at = '2026-10-02T00:00:00Z' where uuid = 'pay-1'$$),
  'staff cannot change a payment');
select pg_temp.check(
  pg_temp.refused($$insert into public.bills (uuid, shop_id, bill_number,
    customer_name, total_amount, item_count, document_type,
    original_bill_uuid, created_at, updated_at)
    values ('cn-1', 'shop-1', 'CN/2627/B0001', 'Asha', -50, 1, 'credit_note',
    'bill-1', '2026-10-01T10:00:00Z', '2026-10-01T10:00:00Z')$$),
  'staff cannot issue credit notes');
select pg_temp.check(
  pg_temp.refused($$insert into public.stock_movements (uuid, shop_id,
    product_uuid, movement_type, quantity_delta, created_at, updated_at)
    values ('mv-x', 'shop-1', 'prod-1', 'adjustment', 50,
    '2026-10-01T09:00:00Z', '2026-10-01T09:00:00Z')$$),
  'staff cannot post stock adjustments');
select pg_temp.check(
  pg_temp.refused($$update public.products set name = 'Free Rice'
    where uuid = 'prod-1'$$)
  or (select name from public.products where uuid = 'prod-1') = 'Rice',
  'staff cannot edit products');

delete from public.bills where uuid = 'bill-1';
delete from public.bill_payments where uuid = 'pay-1';
select pg_temp.check(
  exists (select 1 from public.bills where uuid = 'bill-1')
  and exists (select 1 from public.bill_payments where uuid = 'pay-1'),
  'staff cannot hard-delete billing records');
select tests.logout();

-- ── Admin can cancel, but nobody can hard-delete ──
select tests.login('00000000-0000-0000-0000-0000000000a2', 'admin@shop.in');
update public.bills set deleted_at = '2026-10-02T00:00:00Z',
  lifecycle_status = 'cancelled', updated_at = '2026-10-02T00:00:00Z'
where uuid = 'bill-1';
select pg_temp.check(
  (select deleted_at is not null from public.bills where uuid = 'bill-1'),
  'admin can cancel a bill');
delete from public.bills where uuid = 'bill-1';
select pg_temp.check(
  exists (select 1 from public.bills where uuid = 'bill-1'),
  'admin cannot hard-delete a bill');
select tests.logout();

-- ── Expenses: admins write, staff only read ──
select tests.login('00000000-0000-0000-0000-0000000000a2', 'admin@shop.in');
insert into public.expenses (uuid, shop_id, expense_date, amount, category,
  created_at, updated_at)
values ('exp-1', 'shop-1', '2026-10-23T10:00:00', 1500, 'Rent',
  '2026-10-23T10:00:00Z', '2026-10-23T10:00:00Z');
select tests.logout();
select tests.login('00000000-0000-0000-0000-0000000000a3', 'staff@shop.in');
select pg_temp.check(
  (select count(*) = 1 from public.expenses), 'staff can read expenses');
select pg_temp.check(
  pg_temp.refused($$insert into public.expenses (uuid, shop_id, expense_date,
    amount, created_at, updated_at)
    values ('exp-2', 'shop-1', 'x', 10, 'x', 'x')$$),
  'staff cannot add expenses');
update public.expenses set amount = 1 where uuid = 'exp-1';
select tests.logout();
select pg_temp.check(
  (select amount = 1500 from public.expenses where uuid = 'exp-1'),
  'staff cannot change expenses');

-- ── Audit log: anyone in the shop adds, nobody rewrites ──
select tests.login('00000000-0000-0000-0000-0000000000a3', 'staff@shop.in');
insert into public.audit_log (uuid, shop_id, entity_type, entity_uuid, action,
  details, created_at, updated_at)
values ('aud-1', 'shop-1', 'bill', 'bill-1', 'payment', 'Rs 100 cash',
  '2026-10-23T10:00:00Z', '2026-10-23T10:00:00Z');
select tests.logout();
select tests.login('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in');
update public.audit_log set details = 'nothing happened' where uuid = 'aud-1';
select pg_temp.check(
  (select details = 'Rs 100 cash' from public.audit_log where uuid = 'aud-1'),
  'audit entries cannot be rewritten, even by the owner');
delete from public.audit_log where uuid = 'aud-1';
select pg_temp.check(
  exists (select 1 from public.audit_log where uuid = 'aud-1'),
  'audit entries cannot be deleted');
select tests.logout();

-- ── Outsider sees nothing ──
select tests.login('00000000-0000-0000-0000-0000000000a4', 'stranger@other.in');
select pg_temp.check(
  (select count(*) = 0 from public.bills), 'outsider cannot read bills');
select pg_temp.check(
  pg_temp.refused($$insert into public.bills (uuid, shop_id, bill_number,
    customer_name, total_amount, item_count, created_at, updated_at)
    values ('evil', 'shop-1', 'X', 'X', 1, 1, 'x', 'x')$$),
  'outsider cannot write bills');
select tests.logout();

-- ── Owner can delete the shop ──
select tests.login('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in');
delete from public.shops where uuid = 'shop-1';
select pg_temp.check(
  not exists (select 1 from public.shops where uuid = 'shop-1'),
  'owner can delete the shop');
select tests.logout();

rollback;
