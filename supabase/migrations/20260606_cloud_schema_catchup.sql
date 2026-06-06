-- Storely cloud schema catch-up migration.
--
-- Purpose: bring a Supabase project that was created from an EARLIER version of
-- storely_cloud_schema.sql fully up to the current schema. The create file uses
-- `create table if not exists`, so re-running it does NOT add new columns,
-- indexes, RLS changes, or new tables to tables that already existed. This file
-- fills exactly those gaps.
--
-- It is idempotent and safe to run multiple times. It is also harmless to run on
-- a project that is already current (everything is `if not exists` / `if exists`
-- / `or replace`). Run it once in the Supabase SQL editor.
--
-- Covers drift introduced after the early schema:
--   * new table:        bill_settings (+ RLS + indexes)
--   * bills:            lifecycle_status, cancelled_at, cancel_reason,
--                       duplicated_from_bill_uuid
--   * bill_settings:    the show_* display toggle columns
--   * stock_movements:  source_document_type, source_document_uuid,
--                       import_row_number (and drops legacy source_uuid)
--   * RLS:              members-read / admins-write split on admin-managed
--                       tables; removes the staff self-join policy
--   * indexes:          product code/barcode active-unique, bill_settings,
--                       stock_movements source document
--
-- NOTE: helper functions (is_shop_member / is_shop_admin / etc.) are assumed to
-- already exist from the create file. They are re-created here defensively so
-- the policy definitions below are guaranteed to resolve.

create extension if not exists pgcrypto;

-- ── Helper functions (defensive re-create; no-op if already current) ─────────
create or replace function public.is_shop_member(target_shop_id text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.shop_members
    where shop_id = target_shop_id and user_id = auth.uid()
  );
$$;

create or replace function public.is_shop_admin(target_shop_id text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.shop_members
    where shop_id = target_shop_id
      and user_id = auth.uid()
      and role in ('owner', 'admin')
  );
$$;

-- ── New table: bill_settings ─────────────────────────────────────────────────
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

-- bill_settings display toggle columns (for projects where the table already
-- existed without them).
alter table public.bill_settings
  add column if not exists show_invoice_title integer not null default 1,
  add column if not exists show_shop_logo integer not null default 1,
  add column if not exists shop_logo_base64 text,
  add column if not exists show_digital_signature integer not null default 0,
  add column if not exists digital_signature_base64 text,
  add column if not exists show_shop_name integer not null default 1,
  add column if not exists show_shop_address integer not null default 1,
  add column if not exists show_shop_phone integer not null default 1,
  add column if not exists show_shop_email integer not null default 1,
  add column if not exists show_shop_gstin integer not null default 1,
  add column if not exists show_customer_name integer not null default 1,
  add column if not exists show_customer_phone integer not null default 1,
  add column if not exists show_customer_address integer not null default 1,
  add column if not exists show_customer_gstin integer not null default 1,
  add column if not exists show_customer_legal_name integer not null default 1,
  add column if not exists show_customer_trade_name integer not null default 1,
  add column if not exists show_customer_place_of_supply integer not null default 1,
  add column if not exists show_invoice_number integer not null default 1,
  add column if not exists show_invoice_date integer not null default 1,
  add column if not exists show_invoice_place_of_supply integer not null default 1,
  add column if not exists show_invoice_supply_type integer not null default 1,
  add column if not exists show_payment_details integer not null default 1,
  add column if not exists show_gst_breakdown integer not null default 1,
  add column if not exists show_item_serial_column integer not null default 1,
  add column if not exists show_item_name_column integer not null default 1,
  add column if not exists show_hsn_column integer not null default 1,
  add column if not exists show_quantity_column integer not null default 1,
  add column if not exists show_rate_column integer not null default 1,
  add column if not exists show_gst_percent_column integer not null default 1,
  add column if not exists show_gst_amount_column integer not null default 1,
  add column if not exists show_amount_column integer not null default 1,
  add column if not exists show_subtotal integer not null default 1,
  add column if not exists show_discount integer not null default 1,
  add column if not exists show_taxable_amount integer not null default 1,
  add column if not exists show_cgst_sgst_igst integer not null default 1,
  add column if not exists show_gst_total integer not null default 1,
  add column if not exists show_grand_total integer not null default 1,
  add column if not exists show_footer_text integer not null default 1;

-- ── bills: lifecycle + cancel/duplicate columns ──────────────────────────────
alter table public.bills
  add column if not exists lifecycle_status text not null default 'finalized',
  add column if not exists cancelled_at text,
  add column if not exists cancel_reason text,
  add column if not exists duplicated_from_bill_uuid text;

-- ── stock_movements: source document columns (drops legacy source_uuid) ──────
alter table public.stock_movements
  add column if not exists supplier_uuid text references public.suppliers(uuid),
  add column if not exists source_document_type text,
  add column if not exists source_document_uuid text,
  add column if not exists import_row_number integer;

-- Legacy single-column reference replaced by the typed source document pair.
-- (No production data, so we simply drop it rather than copying.)
alter table public.stock_movements
  drop column if exists source_uuid;

-- ── RLS: enable + member-read / admin-write split ────────────────────────────
alter table public.bill_settings enable row level security;

-- Remove the legacy "staff can self-join" policy. Staff membership must be
-- granted by an owner/admin from now on.
drop policy if exists "Authenticated users can join as staff" on public.shop_members;

-- app_settings
drop policy if exists "Members can sync app_settings" on public.app_settings;
drop policy if exists "Members can read app_settings" on public.app_settings;
drop policy if exists "Admins can insert app_settings" on public.app_settings;
drop policy if exists "Admins can update app_settings" on public.app_settings;
drop policy if exists "Admins can delete app_settings" on public.app_settings;
create policy "Members can read app_settings" on public.app_settings
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert app_settings" on public.app_settings
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update app_settings" on public.app_settings
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete app_settings" on public.app_settings
for delete using (public.is_shop_admin(shop_id));

-- bill_settings
drop policy if exists "Members can sync bill_settings" on public.bill_settings;
drop policy if exists "Members can read bill_settings" on public.bill_settings;
drop policy if exists "Admins can insert bill_settings" on public.bill_settings;
drop policy if exists "Admins can update bill_settings" on public.bill_settings;
drop policy if exists "Admins can delete bill_settings" on public.bill_settings;
create policy "Members can read bill_settings" on public.bill_settings
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert bill_settings" on public.bill_settings
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update bill_settings" on public.bill_settings
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete bill_settings" on public.bill_settings
for delete using (public.is_shop_admin(shop_id));

-- categories
drop policy if exists "Members can sync categories" on public.categories;
drop policy if exists "Members can read categories" on public.categories;
drop policy if exists "Admins can insert categories" on public.categories;
drop policy if exists "Admins can update categories" on public.categories;
drop policy if exists "Admins can delete categories" on public.categories;
create policy "Members can read categories" on public.categories
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert categories" on public.categories
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update categories" on public.categories
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete categories" on public.categories
for delete using (public.is_shop_admin(shop_id));

-- units
drop policy if exists "Members can sync units" on public.units;
drop policy if exists "Members can read units" on public.units;
drop policy if exists "Admins can insert units" on public.units;
drop policy if exists "Admins can update units" on public.units;
drop policy if exists "Admins can delete units" on public.units;
create policy "Members can read units" on public.units
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert units" on public.units
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update units" on public.units
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete units" on public.units
for delete using (public.is_shop_admin(shop_id));

-- suppliers
drop policy if exists "Members can sync suppliers" on public.suppliers;
drop policy if exists "Members can read suppliers" on public.suppliers;
drop policy if exists "Admins can insert suppliers" on public.suppliers;
drop policy if exists "Admins can update suppliers" on public.suppliers;
drop policy if exists "Admins can delete suppliers" on public.suppliers;
create policy "Members can read suppliers" on public.suppliers
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert suppliers" on public.suppliers
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update suppliers" on public.suppliers
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete suppliers" on public.suppliers
for delete using (public.is_shop_admin(shop_id));

-- products
drop policy if exists "Members can sync products" on public.products;
drop policy if exists "Members can read products" on public.products;
drop policy if exists "Admins can insert products" on public.products;
drop policy if exists "Admins can update products" on public.products;
drop policy if exists "Admins can delete products" on public.products;
create policy "Members can read products" on public.products
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert products" on public.products
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update products" on public.products
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete products" on public.products
for delete using (public.is_shop_admin(shop_id));

-- invoice_series
drop policy if exists "Members can sync invoice_series" on public.invoice_series;
drop policy if exists "Members can read invoice_series" on public.invoice_series;
drop policy if exists "Admins can insert invoice_series" on public.invoice_series;
drop policy if exists "Admins can update invoice_series" on public.invoice_series;
drop policy if exists "Admins can delete invoice_series" on public.invoice_series;
create policy "Members can read invoice_series" on public.invoice_series
for select using (public.is_shop_member(shop_id));
create policy "Admins can insert invoice_series" on public.invoice_series
for insert with check (public.is_shop_admin(shop_id));
create policy "Admins can update invoice_series" on public.invoice_series
for update using (public.is_shop_admin(shop_id)) with check (public.is_shop_admin(shop_id));
create policy "Admins can delete invoice_series" on public.invoice_series
for delete using (public.is_shop_admin(shop_id));

-- ── Indexes added after the early schema ─────────────────────────────────────
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

create index if not exists idx_stock_movements_source_document
on public.stock_movements(source_document_type, source_document_uuid);
