-- 2.0: printed MRP and purchase batch / expiry.
-- products.mrp_price          : MRP printed on the pack (selling price may be lower)
-- bill_items.mrp_snapshot     : MRP at the time of sale (for "You saved")
-- stock_movements.batch_no    : batch / lot number of a purchase
-- stock_movements.expiry_date : expiry (yyyy-MM-dd) of that purchase's stock
-- Additive and idempotent.

alter table public.products
  add column if not exists mrp_price double precision;

alter table public.bill_items
  add column if not exists mrp_snapshot double precision;

alter table public.stock_movements
  add column if not exists batch_no text;

alter table public.stock_movements
  add column if not exists expiry_date text;
