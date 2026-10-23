-- 2.0 Phase 3: invoice v2 settings (paper size, UPI QR, amount in words,
-- HSN summary, terms, bank details). Additive and idempotent.
alter table public.bill_settings add column if not exists paper_size text not null default 'a4';
alter table public.bill_settings add column if not exists upi_id text;
alter table public.bill_settings add column if not exists show_upi_qr integer not null default 1;
alter table public.bill_settings add column if not exists show_amount_in_words integer not null default 1;
alter table public.bill_settings add column if not exists show_hsn_summary integer not null default 1;
alter table public.bill_settings add column if not exists terms_text text;
alter table public.bill_settings add column if not exists bank_details text;
