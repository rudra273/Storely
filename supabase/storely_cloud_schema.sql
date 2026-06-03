-- Storely optional cloud sync schema.
-- Run this in the customer's Supabase project. The Flutter app must use only
-- the project URL and anon key. Never paste a service_role key into the app.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  full_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.shops (
  uuid text primary key,
  name text not null,
  phone text,
  email text,
  gstin text,
  address text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.shop_members (
  shop_id text not null references public.shops(uuid) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'staff')),
  created_at timestamptz not null default now(),
  primary key (shop_id, user_id)
);

create table if not exists public.app_settings (
  key text not null,
  shop_id text not null references public.shops(uuid) on delete cascade,
  value text,
  updated_at text not null,
  deleted_at text,
  primary key (shop_id, key)
);

create table if not exists public.bill_settings (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  invoice_title text not null default 'TAX INVOICE',
  footer_text text not null default 'Thank you for your business.',
  show_invoice_title integer not null default 1,
  show_shop_logo integer not null default 1,
  shop_logo_base64 text,
  show_digital_signature integer not null default 0,
  digital_signature_base64 text,
  show_shop_name integer not null default 1,
  show_shop_address integer not null default 1,
  show_shop_phone integer not null default 1,
  show_shop_email integer not null default 1,
  show_shop_gstin integer not null default 1,
  show_customer_name integer not null default 1,
  show_customer_phone integer not null default 1,
  show_customer_address integer not null default 1,
  show_customer_gstin integer not null default 1,
  show_customer_legal_name integer not null default 1,
  show_customer_trade_name integer not null default 1,
  show_customer_place_of_supply integer not null default 1,
  show_invoice_number integer not null default 1,
  show_invoice_date integer not null default 1,
  show_invoice_place_of_supply integer not null default 1,
  show_invoice_supply_type integer not null default 1,
  show_payment_details integer not null default 1,
  show_gst_breakdown integer not null default 1,
  show_item_serial_column integer not null default 1,
  show_item_name_column integer not null default 1,
  show_hsn_column integer not null default 1,
  show_quantity_column integer not null default 1,
  show_rate_column integer not null default 1,
  show_gst_percent_column integer not null default 1,
  show_gst_amount_column integer not null default 1,
  show_amount_column integer not null default 1,
  show_subtotal integer not null default 1,
  show_discount integer not null default 1,
  show_taxable_amount integer not null default 1,
  show_cgst_sgst_igst integer not null default 1,
  show_gst_total integer not null default 1,
  show_grand_total integer not null default 1,
  show_footer_text integer not null default 1,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.categories (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  name text not null,
  hsn_code text,
  hsn_type text,
  hsn_description text,
  gst_percent double precision,
  overhead_cost double precision,
  profit_margin_percent double precision,
  commission_percent double precision,
  direct_price_toggle integer not null default 0,
  manual_price double precision,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.units (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  name text not null,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.suppliers (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  name text not null,
  phone text,
  email text,
  gstin text,
  address text,
  notes text,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.customers (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  name text not null default 'Walk-in Customer',
  phone text,
  email text,
  address text,
  notes text,
  gstin text,
  gst_legal_name text,
  gst_trade_name text,
  gst_registration_status text,
  gst_taxpayer_type text,
  gst_verified_at text,
  gst_source text,
  place_of_supply_state_code text,
  total_purchase_amount double precision not null default 0,
  bill_count integer not null default 0,
  last_purchase_at text,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.products (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  product_code text,
  barcode text,
  name text not null,
  hsn_code text,
  hsn_type text,
  hsn_description text,
  category_uuid text references public.categories(uuid),
  supplier_uuid text references public.suppliers(uuid),
  selling_price double precision not null default 0,
  purchase_price double precision not null default 0,
  gst_percent double precision,
  overhead_cost double precision,
  profit_margin_percent double precision,
  direct_price_toggle integer not null default 0,
  manual_price double precision,
  quantity_cache double precision not null default 0,
  unit_uuid text references public.units(uuid),
  source text not null default 'mobile',
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.bills (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  bill_number text not null,
  invoice_series_uuid text,
  bill_type text not null default 'b2c',
  customer_uuid text references public.customers(uuid),
  customer_name text not null default 'Walk-in Customer',
  customer_phone text,
  customer_gstin text,
  customer_gst_legal_name text,
  customer_gst_trade_name text,
  customer_address_snapshot text,
  place_of_supply_state_code text,
  subtotal_amount double precision not null default 0,
  discount_percent double precision not null default 0,
  discount_amount double precision not null default 0,
  profit_commission_percent double precision not null default 0,
  taxable_amount double precision not null default 0,
  cgst_amount double precision not null default 0,
  sgst_amount double precision not null default 0,
  igst_amount double precision not null default 0,
  total_amount double precision not null,
  item_count integer not null,
  is_paid integer not null default 1,
  payment_method text not null default 'cash',
  paid_amount double precision not null default 0,
  balance_due double precision not null default 0,
  payment_status text not null default 'unpaid',
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create table if not exists public.bill_items (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  bill_uuid text not null references public.bills(uuid) on delete cascade,
  product_uuid text references public.products(uuid),
  product_name text not null,
  hsn_code_snapshot text,
  hsn_type_snapshot text,
  unit_name text,
  purchase_price_snapshot double precision not null default 0,
  selling_price_snapshot double precision not null default 0,
  cost_snapshot double precision not null default 0,
  profit_snapshot double precision not null default 0,
  commission_snapshot double precision not null default 0,
  gst_snapshot double precision not null default 0,
  gst_percent_snapshot double precision,
  taxable_value_snapshot double precision not null default 0,
  cgst_amount_snapshot double precision not null default 0,
  sgst_amount_snapshot double precision not null default 0,
  igst_amount_snapshot double precision not null default 0,
  was_direct_price integer not null default 1,
  quantity double precision not null default 0,
  subtotal double precision not null,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

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

create table if not exists public.stock_movements (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  product_uuid text not null references public.products(uuid),
  movement_type text not null,
  quantity_delta double precision not null,
  unit_cost double precision,
  source_type text,
  supplier_uuid text references public.suppliers(uuid),
  source_document_type text,
  source_document_uuid text,
  import_batch_key text,
  import_row_number integer,
  notes text,
  device_id text,
  created_at text not null,
  updated_at text not null,
  deleted_at text
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, new.raw_user_meta_data ->> 'full_name')
  on conflict (id) do update
  set email = excluded.email,
      updated_at = now();
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_shop_member(target_shop_id text)
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
  );
$$;

create or replace function public.is_shop_admin(target_shop_id text)
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
      and role in ('owner', 'admin')
  );
$$;

create or replace function public.get_shop_role(target_shop_id text)
returns text
language sql
security definer
set search_path = public
as $$
  select role
  from public.shop_members
  where shop_id = target_shop_id
    and user_id = auth.uid()
  limit 1;
$$;

create or replace function public.can_manage_shop_members(target_shop_id text)
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
      and role in ('owner', 'admin')
  );
$$;

create or replace function public.shop_has_no_members(target_shop_id text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select not exists (
    select 1
    from public.shop_members
    where shop_id = target_shop_id
  );
$$;

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_members enable row level security;
alter table public.app_settings enable row level security;
alter table public.bill_settings enable row level security;
alter table public.categories enable row level security;
alter table public.units enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.invoice_series enable row level security;
alter table public.bills enable row level security;
alter table public.bill_items enable row level security;
alter table public.bill_payments enable row level security;
alter table public.stock_movements enable row level security;

-- ── Profiles ──
drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
on public.profiles for select
using ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- ── Shops ──
-- Any authenticated user can create a shop (first sync).
drop policy if exists "Authenticated users can create shop" on public.shops;
create policy "Authenticated users can create shop"
on public.shops for insert
with check ((select auth.uid()) is not null);

-- Any member can read shop details.
drop policy if exists "Members can sync shops" on public.shops;
drop policy if exists "Members can view shops" on public.shops;
create policy "Members can view shops"
on public.shops for select
using (public.is_shop_member(uuid));

-- Only owner/admin can update shop details.
drop policy if exists "Admins can update shops" on public.shops;
create policy "Admins can update shops"
on public.shops for update
using (public.is_shop_admin(uuid))
with check (public.is_shop_admin(uuid));

-- Only owner/admin can delete shops.
drop policy if exists "Admins can delete shops" on public.shops;
create policy "Admins can delete shops"
on public.shops for delete
using (public.is_shop_admin(uuid));

-- ── Shop members ──
drop policy if exists "Members can view shop members" on public.shop_members;
create policy "Members can view shop members"
on public.shop_members for select
using (public.is_shop_member(shop_id));

-- First user to join an empty shop becomes owner.
drop policy if exists "First owner can join empty shop" on public.shop_members;
create policy "First owner can join empty shop"
on public.shop_members for insert
with check (
  (select auth.uid()) = user_id
  and role = 'owner'
  and public.shop_has_no_members(shop_id)
);

-- Staff membership must be granted by an owner/admin. The app must never
-- allow arbitrary authenticated users to self-join an existing shop.
drop policy if exists "Authenticated users can join as staff" on public.shop_members;

-- Owners/admins can manage (update/delete) shop members.
drop policy if exists "Owners and admins can manage shop members" on public.shop_members;
create policy "Owners and admins can manage shop members"
on public.shop_members for all
using (public.can_manage_shop_members(shop_id))
with check (public.can_manage_shop_members(shop_id));

-- ── Admin-managed tables: members can read, only owner/admin can write ──
drop policy if exists "Members can sync app_settings" on public.app_settings;
create policy "Members can read app_settings" on public.app_settings
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert app_settings" on public.app_settings
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update app_settings" on public.app_settings
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete app_settings" on public.app_settings
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync bill_settings" on public.bill_settings;
create policy "Members can read bill_settings" on public.bill_settings
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert bill_settings" on public.bill_settings
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update bill_settings" on public.bill_settings
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete bill_settings" on public.bill_settings
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync categories" on public.categories;
create policy "Members can read categories" on public.categories
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert categories" on public.categories
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update categories" on public.categories
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete categories" on public.categories
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync units" on public.units;
create policy "Members can read units" on public.units
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert units" on public.units
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update units" on public.units
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete units" on public.units
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync suppliers" on public.suppliers;
create policy "Members can read suppliers" on public.suppliers
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert suppliers" on public.suppliers
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update suppliers" on public.suppliers
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete suppliers" on public.suppliers
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync customers" on public.customers;
create policy "Members can sync customers"
on public.customers for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync products" on public.products;
create policy "Members can read products" on public.products
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert products" on public.products
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update products" on public.products
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete products" on public.products
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync invoice_series" on public.invoice_series;
create policy "Members can read invoice_series" on public.invoice_series
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert invoice_series" on public.invoice_series
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update invoice_series" on public.invoice_series
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete invoice_series" on public.invoice_series
for delete using (public.is_shop_admin(shop_id));

-- ── Operating tables: shop members can create billing/customer activity ──
drop policy if exists "Members can sync bills" on public.bills;
create policy "Members can sync bills"
on public.bills for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync bill_items" on public.bill_items;
create policy "Members can sync bill_items"
on public.bill_items for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync bill_payments" on public.bill_payments;
create policy "Members can sync bill_payments"
on public.bill_payments for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync stock_movements" on public.stock_movements;
create policy "Members can sync stock_movements"
on public.stock_movements for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

create index if not exists idx_shop_members_user on public.shop_members(user_id);
create index if not exists idx_products_shop_updated on public.products(shop_id, updated_at);
create unique index if not exists idx_products_shop_product_code_active
on public.products(shop_id, lower(product_code))
where product_code is not null and btrim(product_code) <> '' and deleted_at is null;
create unique index if not exists idx_products_shop_barcode_active
on public.products(shop_id, lower(barcode))
where barcode is not null and btrim(barcode) <> '' and deleted_at is null;
create unique index if not exists idx_bill_settings_shop_active
on public.bill_settings(shop_id)
where deleted_at is null;
create index if not exists idx_bill_settings_shop_updated
on public.bill_settings(shop_id, updated_at);
create index if not exists idx_invoice_series_shop_updated on public.invoice_series(shop_id, updated_at);
create index if not exists idx_bills_shop_updated on public.bills(shop_id, updated_at);
create index if not exists idx_bill_items_shop_updated on public.bill_items(shop_id, updated_at);
create index if not exists idx_bill_payments_shop_updated on public.bill_payments(shop_id, updated_at);
create index if not exists idx_bill_payments_bill_uuid on public.bill_payments(bill_uuid);
create index if not exists idx_stock_movements_shop_updated on public.stock_movements(shop_id, updated_at);
create index if not exists idx_stock_movements_source_document
on public.stock_movements(source_document_type, source_document_uuid);
