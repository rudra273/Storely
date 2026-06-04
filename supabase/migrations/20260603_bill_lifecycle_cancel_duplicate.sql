alter table public.bills
  add column if not exists lifecycle_status text not null default 'finalized',
  add column if not exists cancelled_at text,
  add column if not exists cancel_reason text,
  add column if not exists duplicated_from_bill_uuid text;

update public.bills
set lifecycle_status = coalesce(lifecycle_status, 'finalized');
