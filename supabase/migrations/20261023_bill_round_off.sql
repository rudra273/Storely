-- 2.0 Phase 1: whole-rupee grand total with an explicit round-off line.
-- bills.round_off_amount  : amount added to the line total (+/- < 0.50)
-- bill_settings.round_off_total : shop setting, on by default
-- Additive and idempotent.

alter table public.bills
  add column if not exists round_off_amount double precision not null default 0;

alter table public.bill_settings
  add column if not exists round_off_total integer not null default 1;
