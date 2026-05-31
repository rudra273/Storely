-- Storely 1.0.3 cloud schema migration.
-- Safe for existing Supabase projects: adds columns/tables if missing,
-- creates indexes/policies if missing, and backfills payment summary data.
-- It does not drop tables and does not delete existing rows.

create extension if not exists pgcrypto;

alter table public.categories
  add column if not exists hsn_code text,
  add column if not exists hsn_type text,
  add column if not exists hsn_description text;

alter table public.products
  add column if not exists hsn_code text,
  add column if not exists hsn_type text,
  add column if not exists hsn_description text;

alter table public.customers
  add column if not exists gstin text,
  add column if not exists gst_legal_name text,
  add column if not exists gst_trade_name text,
  add column if not exists gst_registration_status text,
  add column if not exists gst_taxpayer_type text,
  add column if not exists gst_verified_at text,
  add column if not exists gst_source text,
  add column if not exists place_of_supply_state_code text;

alter table public.bills
  add column if not exists invoice_series_uuid text,
  add column if not exists bill_type text not null default 'b2c',
  add column if not exists customer_gstin text,
  add column if not exists customer_gst_legal_name text,
  add column if not exists customer_gst_trade_name text,
  add column if not exists customer_address_snapshot text,
  add column if not exists place_of_supply_state_code text,
  add column if not exists taxable_amount double precision not null default 0,
  add column if not exists cgst_amount double precision not null default 0,
  add column if not exists sgst_amount double precision not null default 0,
  add column if not exists igst_amount double precision not null default 0,
  add column if not exists paid_amount double precision not null default 0,
  add column if not exists balance_due double precision not null default 0,
  add column if not exists payment_status text not null default 'unpaid';

alter table public.bill_items
  add column if not exists hsn_code_snapshot text,
  add column if not exists hsn_type_snapshot text,
  add column if not exists gst_percent_snapshot double precision,
  add column if not exists taxable_value_snapshot double precision not null default 0,
  add column if not exists cgst_amount_snapshot double precision not null default 0,
  add column if not exists sgst_amount_snapshot double precision not null default 0,
  add column if not exists igst_amount_snapshot double precision not null default 0;

create table if not exists public.invoice_series (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  name text not null,
  format_template text not null,
  sequence_padding integer not null default 4,
  reset_period text not null default 'financial_year',
  allocation_mode text not null default 'local_device',
  next_sequence integer not null default 1,
  is_default integer not null default 0,
  is_active integer not null default 1,
  device_token_required integer not null default 1,
  last_sequence_key text,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.bill_payments (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  bill_uuid text not null references public.bills(uuid) on delete cascade,
  amount double precision not null,
  payment_method text not null default 'cash',
  payment_reference text,
  notes text,
  received_at text not null,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create index if not exists idx_invoice_series_shop_updated
  on public.invoice_series(shop_id, updated_at);

create index if not exists idx_bill_payments_shop_updated
  on public.bill_payments(shop_id, updated_at);

create index if not exists idx_bill_payments_bill_uuid
  on public.bill_payments(bill_uuid);

alter table public.invoice_series enable row level security;
alter table public.bill_payments enable row level security;

drop policy if exists "Members can sync invoice_series" on public.invoice_series;
create policy "Members can sync invoice_series"
on public.invoice_series for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync bill_payments" on public.bill_payments;
create policy "Members can sync bill_payments"
on public.bill_payments for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

insert into public.invoice_series (
  uuid,
  shop_id,
  name,
  format_template,
  sequence_padding,
  reset_period,
  allocation_mode,
  next_sequence,
  is_default,
  is_active,
  device_token_required,
  device_id,
  created_at,
  updated_at
)
select
  gen_random_uuid()::text,
  shops.uuid,
  'Default Local',
  'SHOP-LOCAL-{DEVICE}-{YYYY}{MM}{DD}-{SEQ}',
  4,
  'daily',
  'local_device',
  1,
  1,
  1,
  1,
  'local',
  now()::text,
  now()::text
from public.shops
where not exists (
  select 1
  from public.invoice_series s
  where s.shop_id = shops.uuid
    and s.deleted_at is null
);

update public.bill_items
set taxable_value_snapshot = greatest(selling_price_snapshot - gst_snapshot, 0)
where taxable_value_snapshot = 0;

update public.bills
set paid_amount = case when is_paid = 1 then total_amount else 0 end,
    balance_due = case when is_paid = 1 then 0 else total_amount end,
    payment_status = case when is_paid = 1 then 'paid' else 'unpaid' end,
    taxable_amount = case when taxable_amount = 0 then total_amount else taxable_amount end
where payment_status = 'unpaid'
  and paid_amount = 0
  and balance_due = 0;

insert into public.bill_payments (
  uuid,
  shop_id,
  bill_uuid,
  amount,
  payment_method,
  notes,
  received_at,
  created_at,
  updated_at
)
select
  gen_random_uuid()::text,
  b.shop_id,
  b.uuid,
  b.total_amount,
  b.payment_method,
  'Migrated from paid status',
  b.created_at,
  now()::text,
  now()::text
from public.bills b
where b.deleted_at is null
  and b.is_paid = 1
  and not exists (
    select 1
    from public.bill_payments p
    where p.bill_uuid = b.uuid
      and p.deleted_at is null
  );
