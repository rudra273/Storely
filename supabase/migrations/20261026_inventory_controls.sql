-- 2.0 Phase 4: inventory controls.
-- products.track_stock     : 0 for services / loose items (billing never checks stock)
-- products.reorder_level   : per-product "running low" level (null = shop default)
-- stock_movements.reason   : why a manual adjustment was made
--                            (damage, theft, expired, return, count, other)
-- Additive and idempotent.

alter table public.products
  add column if not exists track_stock integer not null default 1;

alter table public.products
  add column if not exists reorder_level double precision;

alter table public.stock_movements
  add column if not exists reason text;
