-- Exact decimal storage for billing, catalogue prices and fractional stock.
-- Forward-only widening: no table/column is dropped, no values are rounded or
-- backfilled with guessed amounts. Legacy binary values use their existing
-- decimal text. Existing records, constraints, RLS and sync field names remain.
-- Check the type first so reapplying this migration does not rewrite tables.
do $$
declare target record;
begin
  perform set_config('lock_timeout', '5s', true);
  for target in select * from (values
    ('categories', 'gst_percent'),
    ('categories', 'overhead_cost'),
    ('categories', 'profit_margin_percent'),
    ('categories', 'commission_percent'),
    ('categories', 'manual_price'),
    ('customers', 'total_purchase_amount'),
    ('products', 'selling_price'),
    ('products', 'purchase_price'),
    ('products', 'gst_percent'),
    ('products', 'overhead_cost'),
    ('products', 'profit_margin_percent'),
    ('products', 'manual_price'),
    ('products', 'quantity_cache'),
    ('products', 'reorder_level'),
    ('products', 'mrp_price'),
    ('bills', 'subtotal_amount'),
    ('bills', 'discount_percent'),
    ('bills', 'discount_amount'),
    ('bills', 'profit_commission_percent'),
    ('bills', 'taxable_amount'),
    ('bills', 'cgst_amount'),
    ('bills', 'sgst_amount'),
    ('bills', 'igst_amount'),
    ('bills', 'round_off_amount'),
    ('bills', 'total_amount'),
    ('bills', 'paid_amount'),
    ('bills', 'balance_due'),
    ('bill_items', 'purchase_price_snapshot'),
    ('bill_items', 'selling_price_snapshot'),
    ('bill_items', 'cost_snapshot'),
    ('bill_items', 'profit_snapshot'),
    ('bill_items', 'commission_snapshot'),
    ('bill_items', 'gst_snapshot'),
    ('bill_items', 'gst_percent_snapshot'),
    ('bill_items', 'taxable_value_snapshot'),
    ('bill_items', 'cgst_amount_snapshot'),
    ('bill_items', 'sgst_amount_snapshot'),
    ('bill_items', 'igst_amount_snapshot'),
    ('bill_items', 'mrp_snapshot'),
    ('bill_items', 'quantity'),
    ('bill_items', 'subtotal'),
    ('bill_payments', 'amount'),
    ('stock_movements', 'quantity_delta'),
    ('stock_movements', 'unit_cost'),
    ('expenses', 'amount')
  ) as columns_to_widen(table_name, column_name)
  loop
    if exists (
      select 1 from information_schema.columns c
      where c.table_schema = 'public' and c.table_name = target.table_name
        and c.column_name = target.column_name and c.data_type = 'double precision'
    ) then
      execute format('alter table public.%I alter column %I type numeric using %I::text::numeric',
        target.table_name, target.column_name, target.column_name);
    end if;
  end loop;
end;
$$;
