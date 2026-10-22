-- Hotfix 1.0.5: local SQLite installs created on DB v16 (app 1.0.0/1.0.1)
-- were missing the v20 stock_movements source/supplier columns and kept the
-- old non-unique product barcode/code indexes. The local fix lives in
-- `_ensureV20Columns` / `_rebuildV21Indexes` (lib/db/database_schema.dart).
--
-- The cloud schema already carries these columns and unique indexes in
-- storely_cloud_schema.sql. This migration only guarantees the same shape on
-- any older cloud project, so pushes from upgraded devices never hit a
-- missing column. Additive and idempotent: safe to re-run; a no-op on an
-- up-to-date project.

alter table public.stock_movements
  add column if not exists supplier_uuid text references public.suppliers(uuid);
alter table public.stock_movements
  add column if not exists source_document_type text;
alter table public.stock_movements
  add column if not exists source_document_uuid text;
alter table public.stock_movements
  add column if not exists import_row_number integer;

create unique index if not exists idx_products_shop_product_code_active
on public.products(shop_id, lower(product_code))
where product_code is not null and btrim(product_code) <> '' and deleted_at is null;

create unique index if not exists idx_products_shop_barcode_active
on public.products(shop_id, lower(barcode))
where barcode is not null and btrim(barcode) <> '' and deleted_at is null;
