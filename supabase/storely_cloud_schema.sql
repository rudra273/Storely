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
  -- Direct FK to profiles so PostgREST can resolve the profiles(email) embed
  -- in listMembers(). Indirect linkage through auth.users is not traversed by
  -- PostgREST. See migrations/20260606_shop_members_profiles_fk.sql.
  constraint shop_members_user_profile_fk
    foreign key (user_id) references public.profiles(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'staff')),
  created_at timestamptz not null default now(),
  primary key (shop_id, user_id)
);

-- Pending invites: an owner/admin invites a person by email; that person
-- signs up themselves and is linked to the shop on first sync (zero-server).
-- shop_id is text to match shops.uuid (app-generated string UUIDs); id is a
-- real Postgres uuid because it is a new server-side primary key.
create table if not exists public.shop_invites (
  id          uuid primary key default gen_random_uuid(),
  shop_id     text not null references public.shops(uuid) on delete cascade,
  email       text not null,
  role        text not null default 'staff' check (role in ('admin', 'staff')),
  invited_by  uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now(),
  accepted_at timestamptz
);

-- One pending invite per (shop, email); matched case-insensitively.
create unique index if not exists shop_invites_shop_email_uidx
  on public.shop_invites (shop_id, lower(email))
  where accepted_at is null;

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
  round_off_total integer not null default 1,
  paper_size text not null default 'a4',
  upi_id text,
  show_upi_qr integer not null default 1,
  show_amount_in_words integer not null default 1,
  show_hsn_summary integer not null default 1,
  terms_text text,
  bank_details text,
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
  track_stock integer not null default 1,
  reorder_level double precision,
  mrp_price double precision,
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
  round_off_amount double precision not null default 0,
  document_type text not null default 'invoice',
  original_bill_uuid text,
  original_bill_number text,
  total_amount double precision not null,
  item_count integer not null,
  is_paid integer not null default 1,
  payment_method text not null default 'cash',
  paid_amount double precision not null default 0,
  balance_due double precision not null default 0,
  payment_status text not null default 'unpaid',
  lifecycle_status text not null default 'finalized',
  cancelled_at text,
  cancel_reason text,
  duplicated_from_bill_uuid text,
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
  original_item_uuid text,
  mrp_snapshot double precision,
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
  reason text,
  batch_no text,
  expiry_date text,
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

-- True when target_user_id is a member of some shop that the caller
-- owns/admins. Used so admins can read their members' profile emails.
create or replace function public.shares_admin_shop(target_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.shop_members me
    join public.shop_members them on them.shop_id = me.shop_id
    where me.user_id = auth.uid()
      and me.role in ('owner', 'admin')
      and them.user_id = target_user_id
  );
$$;

grant execute on function public.shares_admin_shop(uuid) to authenticated;

-- Atomically register a new shop and make the caller its owner.
-- Runs as definer so the shops insert + owner shop_members insert happen
-- together regardless of RLS ordering. Fails if the shop already has members
-- (so two owners can't claim the same shop_id). Safe because the caller can
-- only ever make THEMSELVES the owner of a shop that has none.
create or replace function public.create_shop(
  target_shop_id text,
  shop_name       text,
  shop_phone      text default null,
  shop_email      text default null,
  shop_gstin      text default null,
  shop_address    text default null,
  shop_created_at text default null,
  shop_updated_at text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id uuid := auth.uid();
  now_iso   text := to_char(now() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
begin
  if caller_id is null then
    raise exception 'Not authenticated';
  end if;

  -- Caller already owns/belongs to this shop → nothing to do.
  if exists (
    select 1 from public.shop_members
    where shop_id = target_shop_id and user_id = caller_id
  ) then
    return 'already_member';
  end if;

  -- Someone else already registered this shop id.
  if exists (
    select 1 from public.shop_members where shop_id = target_shop_id
  ) then
    raise exception 'Shop already registered by another owner';
  end if;

  insert into public.shops (uuid, name, phone, email, gstin, address, created_at, updated_at)
  values (
    target_shop_id,
    coalesce(nullif(shop_name, ''), 'My Shop'),
    shop_phone, shop_email, shop_gstin, shop_address,
    coalesce(shop_created_at, now_iso),
    coalesce(shop_updated_at, now_iso)
  )
  on conflict (uuid) do update
    set name = excluded.name, updated_at = excluded.updated_at;

  insert into public.shop_members (shop_id, user_id, role)
  values (target_shop_id, caller_id, 'owner')
  on conflict (shop_id, user_id) do nothing;

  return 'created';
end;
$$;

grant execute on function public.create_shop(text, text, text, text, text, text, text, text) to authenticated;

-- An invited (not-yet-member) user redeems their invite. Runs as definer so a
-- non-member can insert their own shop_members row, but ONLY when a pending
-- invite for THIS shop matches the caller's own JWT email, and only with the
-- exact invited role. Returns: 'joined' | 'already_member' | 'no_invite'.
create or replace function public.accept_invite(target_shop_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_email text := lower(coalesce(auth.jwt() ->> 'email', ''));
  caller_id    uuid := auth.uid();
  invite       record;
begin
  if caller_id is null or caller_email = '' then
    raise exception 'Not authenticated';
  end if;

  if exists (
    select 1 from public.shop_members
    where shop_id = target_shop_id and user_id = caller_id
  ) then
    return 'already_member';
  end if;

  select * into invite
  from public.shop_invites
  where shop_id = target_shop_id
    and lower(email) = caller_email
    and accepted_at is null
  limit 1;

  if invite is null then
    return 'no_invite';
  end if;

  insert into public.shop_members (shop_id, user_id, role)
  values (target_shop_id, caller_id, invite.role)
  on conflict (shop_id, user_id) do nothing;

  update public.shop_invites
  set accepted_at = now()
  where id = invite.id;

  return 'joined';
end;
$$;

grant execute on function public.accept_invite(text) to authenticated;

-- Lets a freshly-signed-up user discover WHICH shop invited them, before they
-- have any local shop_id. Returns the earliest pending invite's shop id.
create or replace function public.my_pending_invite_shop()
returns text
language sql
security definer
set search_path = public
as $$
  select shop_id
  from public.shop_invites
  where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
    and accepted_at is null
  order by created_at asc
  limit 1;
$$;

grant execute on function public.my_pending_invite_shop() to authenticated;

alter table public.profiles enable row level security;
alter table public.shops enable row level security;
alter table public.shop_members enable row level security;
alter table public.shop_invites enable row level security;
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

-- Owners/admins can read profiles (for the email) of members of any shop they
-- administer, so the Members screen can show who each member is.
drop policy if exists "Admins can view member profiles" on public.profiles;
create policy "Admins can view member profiles"
on public.profiles for select
using (public.shares_admin_shop(id));

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

-- ── Shop invites ──
-- Owners/admins see & manage invites for their shop; an invited user can read
-- invites addressed to their own email (to discover where they were invited).
drop policy if exists "Admins can view shop invites" on public.shop_invites;
create policy "Admins can view shop invites"
on public.shop_invites for select
using (public.is_shop_admin(shop_id));

drop policy if exists "Invitee can view own invites" on public.shop_invites;
create policy "Invitee can view own invites"
on public.shop_invites for select
using (lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')));

drop policy if exists "Admins can create shop invites" on public.shop_invites;
create policy "Admins can create shop invites"
on public.shop_invites for insert
with check (public.is_shop_admin(shop_id));

drop policy if exists "Admins can revoke shop invites" on public.shop_invites;
create policy "Admins can revoke shop invites"
on public.shop_invites for delete
using (public.is_shop_admin(shop_id));

-- ── Admin-managed tables: members can read, only owner/admin can write ──
drop policy if exists "Members can sync app_settings" on public.app_settings;
drop policy if exists "Members can read app_settings" on public.app_settings;
create policy "Members can read app_settings" on public.app_settings
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert app_settings" on public.app_settings;
create policy "Admins can insert app_settings" on public.app_settings
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update app_settings" on public.app_settings;
create policy "Admins can update app_settings" on public.app_settings
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete app_settings" on public.app_settings;
create policy "Admins can delete app_settings" on public.app_settings
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync bill_settings" on public.bill_settings;
drop policy if exists "Members can read bill_settings" on public.bill_settings;
create policy "Members can read bill_settings" on public.bill_settings
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert bill_settings" on public.bill_settings;
create policy "Admins can insert bill_settings" on public.bill_settings
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update bill_settings" on public.bill_settings;
create policy "Admins can update bill_settings" on public.bill_settings
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete bill_settings" on public.bill_settings;
create policy "Admins can delete bill_settings" on public.bill_settings
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync categories" on public.categories;
drop policy if exists "Members can read categories" on public.categories;
create policy "Members can read categories" on public.categories
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert categories" on public.categories;
create policy "Admins can insert categories" on public.categories
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update categories" on public.categories;
create policy "Admins can update categories" on public.categories
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete categories" on public.categories;
create policy "Admins can delete categories" on public.categories
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync units" on public.units;
drop policy if exists "Members can read units" on public.units;
create policy "Members can read units" on public.units
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert units" on public.units;
create policy "Admins can insert units" on public.units
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update units" on public.units;
create policy "Admins can update units" on public.units
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete units" on public.units;
create policy "Admins can delete units" on public.units
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync suppliers" on public.suppliers;
drop policy if exists "Members can read suppliers" on public.suppliers;
create policy "Members can read suppliers" on public.suppliers
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert suppliers" on public.suppliers;
create policy "Admins can insert suppliers" on public.suppliers
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update suppliers" on public.suppliers;
create policy "Admins can update suppliers" on public.suppliers
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete suppliers" on public.suppliers;
create policy "Admins can delete suppliers" on public.suppliers
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync customers" on public.customers;
create policy "Members can sync customers"
on public.customers for all
using (public.is_shop_member(shop_id))
with check (public.is_shop_member(shop_id));

drop policy if exists "Members can sync products" on public.products;
drop policy if exists "Members can read products" on public.products;
create policy "Members can read products" on public.products
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert products" on public.products;
create policy "Admins can insert products" on public.products
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update products" on public.products;
create policy "Admins can update products" on public.products
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete products" on public.products;
create policy "Admins can delete products" on public.products
for delete using (public.is_shop_admin(shop_id));

drop policy if exists "Members can sync invoice_series" on public.invoice_series;
drop policy if exists "Members can read invoice_series" on public.invoice_series;
create policy "Members can read invoice_series" on public.invoice_series
for select using (public.is_shop_member(shop_id));
drop policy if exists "Admins can insert invoice_series" on public.invoice_series;
create policy "Admins can insert invoice_series" on public.invoice_series
for insert with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can update invoice_series" on public.invoice_series;
create policy "Admins can update invoice_series" on public.invoice_series
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
drop policy if exists "Admins can delete invoice_series" on public.invoice_series;
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

-- ── Sync v2 (mirrors migrations/20261024_sync_v2.sql) ──
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

-- ── Device bill-number letters (mirrors migrations/20261024_device_codes.sql) ──
create table if not exists public.shop_devices (
  shop_id text not null references public.shops(uuid) on delete cascade,
  device_id text not null,
  code text not null,
  registered_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (shop_id, device_id),
  unique (shop_id, code)
);

alter table public.shop_devices enable row level security;

drop policy if exists "Members can view shop devices" on public.shop_devices;
create policy "Members can view shop devices"
on public.shop_devices for select
using (public.is_shop_member(shop_id));
-- No insert/update/delete policies: devices are registered only through
-- register_device(), which assigns the code.

create or replace function public.register_device(
  target_shop_id text,
  device_uuid text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing text;
  n integer;
  next_code text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if not public.is_shop_member(target_shop_id) then
    raise exception 'Not a member of this shop';
  end if;
  if coalesce(device_uuid, '') = '' then
    raise exception 'device_uuid is required';
  end if;

  -- Serialise registrations per shop so two phones never get one code.
  perform pg_advisory_xact_lock(hashtext('storely_device:' || target_shop_id));

  select code into existing
  from public.shop_devices
  where shop_id = target_shop_id and device_id = device_uuid;
  if found then
    return existing;
  end if;

  select count(*) into n from public.shop_devices where shop_id = target_shop_id;
  if n = 0 then
    next_code := '';
  elsif n < 26 then
    next_code := chr(65 + n);
  else
    next_code := chr(65 + n / 26) || chr(65 + n % 26);
  end if;

  insert into public.shop_devices (shop_id, device_id, code, registered_by)
  values (target_shop_id, device_uuid, next_code, auth.uid());
  return next_code;
end;
$$;

grant execute on function public.register_device(text, text) to authenticated;

-- ── Permissions hardening (mirrors migrations/20261024_rls_hardening.sql) ──
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

-- ── Credit notes (mirrors migrations/20261025_credit_notes.sql) ──
create index if not exists idx_bills_original_bill
on public.bills (original_bill_uuid) where original_bill_uuid is not null;

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
    if tg_table_name = 'bills'
       and (to_jsonb(new) ->> 'document_type') = 'credit_note' then
      raise exception 'Only the owner or an admin can issue credit notes'
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

-- ── Expenses (mirrors migrations/20261027_expenses.sql) ──
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

-- ── Audit log (mirrors migrations/20261028_audit_log.sql) ──
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

