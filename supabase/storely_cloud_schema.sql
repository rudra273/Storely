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

create table if not exists public.categories (
  uuid text primary key,
  shop_id text not null references public.shops(uuid) on delete cascade,
  name text not null,
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
  customer_uuid text references public.customers(uuid),
  customer_name text not null default 'Walk-in Customer',
  customer_phone text,
  subtotal_amount double precision not null default 0,
  discount_percent double precision not null default 0,
  discount_amount double precision not null default 0,
  profit_commission_percent double precision not null default 0,
  total_amount double precision not null,
  item_count integer not null,
  is_paid integer not null default 1,
  payment_method text not null default 'cash',
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
  unit_name text,
  purchase_price_snapshot double precision not null default 0,
  selling_price_snapshot double precision not null default 0,
  cost_snapshot double precision not null default 0,
  profit_snapshot double precision not null default 0,
  commission_snapshot double precision not null default 0,
  gst_snapshot double precision not null default 0,
  was_direct_price integer not null default 1,
  quantity double precision not null default 0,
  subtotal double precision not null,
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
  source_uuid text,
  import_batch_key text,
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
alter table public.categories enable row level security;
alter table public.units enable row level security;
alter table public.suppliers enable row level security;
alter table public.customers enable row level security;
alter table public.products enable row level security;
alter table public.bills enable row level security;
alter table public.bill_items enable row level security;
alter table public.stock_movements enable row level security;

drop policy if exists "Users can view own profile" on public.profiles;
create policy "Users can view own profile"
on public.profiles for select
using ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles for update
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists "Authenticated users can create shop" on public.shops;
create policy "Authenticated users can create shop"
on public.shops for insert
with check ((select auth.uid()) is not null);

drop policy if exists "Members can sync shops" on public.shops;
create policy "Members can sync shops"
on public.shops for all
using (public.is_shop_member(uuid))
with check (public.is_shop_member(uuid));

drop policy if exists "Members can view shop members" on public.shop_members;
create policy "Members can view shop members"
on public.shop_members for select
using (public.is_shop_member(shop_id));

drop policy if exists "First owner can join empty shop" on public.shop_members;
create policy "First owner can join empty shop"
on public.shop_members for insert
with check (
  (select auth.uid()) = user_id
  and role = 'owner'
  and public.shop_has_no_members(shop_id)
);

drop policy if exists "Owners and admins can manage shop members" on public.shop_members;
create policy "Owners and admins can manage shop members"
on public.shop_members for all
using (public.can_manage_shop_members(shop_id))
with check (public.can_manage_shop_members(shop_id));

drop policy if exists "Members can sync app_settings" on public.app_settings;
create policy "Members can sync app_settings"
on public.app_settings for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync categories" on public.categories;
create policy "Members can sync categories"
on public.categories for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync units" on public.units;
create policy "Members can sync units"
on public.units for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync suppliers" on public.suppliers;
create policy "Members can sync suppliers"
on public.suppliers for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync customers" on public.customers;
create policy "Members can sync customers"
on public.customers for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync products" on public.products;
create policy "Members can sync products"
on public.products for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

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

drop policy if exists "Members can sync stock_movements" on public.stock_movements;
create policy "Members can sync stock_movements"
on public.stock_movements for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

create index if not exists idx_shop_members_user on public.shop_members(user_id);
create index if not exists idx_products_shop_updated on public.products(shop_id, updated_at);
create index if not exists idx_bills_shop_updated on public.bills(shop_id, updated_at);
create index if not exists idx_bill_items_shop_updated on public.bill_items(shop_id, updated_at);
create index if not exists idx_stock_movements_shop_updated on public.stock_movements(shop_id, updated_at);
