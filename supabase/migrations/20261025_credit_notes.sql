-- 2.0 Phase 3: credit notes (sales returns). Additive and idempotent.
-- A credit note is a bills row with document_type = 'credit_note', negative
-- quantities/amounts and a reference to the invoice it reverses; its lines
-- point at the invoice lines returned. Only owners/admins may issue them.

alter table public.bills
  add column if not exists document_type text not null default 'invoice';
alter table public.bills add column if not exists original_bill_uuid text;
alter table public.bills add column if not exists original_bill_number text;
alter table public.bill_items add column if not exists original_item_uuid text;

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

