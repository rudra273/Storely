-- Destructive Storely cloud reset.
-- Run this in Supabase SQL Editor before running storely_cloud_schema.sql again.
-- This removes Storely app data, policies, indexes, triggers, and helper functions.
-- It does not delete auth.users or Supabase auth configuration.

begin;

drop trigger if exists on_auth_user_created on auth.users;

drop table if exists public.stock_movements cascade;
drop table if exists public.bill_payments cascade;
drop table if exists public.invoice_series cascade;
drop table if exists public.bill_items cascade;
drop table if exists public.bills cascade;
drop table if exists public.products cascade;
drop table if exists public.customers cascade;
drop table if exists public.suppliers cascade;
drop table if exists public.units cascade;
drop table if exists public.categories cascade;
drop table if exists public.bill_settings cascade;
drop table if exists public.app_settings cascade;
drop table if exists public.shop_members cascade;
drop table if exists public.shops cascade;
drop table if exists public.profiles cascade;

drop function if exists public.handle_new_user() cascade;
drop function if exists public.is_shop_member(text) cascade;
drop function if exists public.is_shop_admin(text) cascade;
drop function if exists public.get_shop_role(text) cascade;
drop function if exists public.can_manage_shop_members(text) cascade;
drop function if exists public.shop_has_no_members(text) cascade;

commit;
