-- register_device: stable per device, unique per shop, members only.
\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.check(ok boolean, what text) returns void
language plpgsql as $$
begin
  if not coalesce(ok, false) then raise exception 'FAILED: %', what; end if;
end $$;

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in'),
  ('00000000-0000-0000-0000-0000000000b2', 'stranger@other.in');

select tests.login('00000000-0000-0000-0000-0000000000a1', 'owner@shop.in');
select public.create_shop('shop-1', 'Sharma Kirana');

select pg_temp.check(public.register_device('shop-1', 'phone-1') = '',
  'first device gets no letter');
select pg_temp.check(public.register_device('shop-1', 'phone-2') = 'B',
  'second device gets B');
select pg_temp.check(public.register_device('shop-1', 'phone-1') = '',
  're-registering returns the same code');
select pg_temp.check(public.register_device('shop-1', 'phone-3') = 'C',
  'third device gets C');

do $$
declare i int;
begin
  for i in 4..27 loop
    perform public.register_device('shop-1', 'phone-' || i);
  end loop;
  perform pg_temp.check(public.register_device('shop-1', 'phone-27') = 'BA',
    '27th device rolls over to two letters');
  perform pg_temp.check(
    (select count(distinct code) = count(*) from public.shop_devices
     where shop_id = 'shop-1'),
    'codes are unique within the shop');
end $$;

-- Devices cannot be written directly.
do $$ begin
  insert into public.shop_devices (shop_id, device_id, code)
  values ('shop-1', 'sneaky', 'Z');
  raise exception 'FAILED: direct insert allowed';
exception when insufficient_privilege then null;
end $$;

select tests.logout();
select tests.login('00000000-0000-0000-0000-0000000000b2', 'stranger@other.in');
do $$ begin
  perform public.register_device('shop-1', 'intruder');
  raise exception 'FAILED: non-member registered a device';
exception when others then
  if sqlerrm like 'FAILED%' then raise; end if;
end $$;
select tests.logout();

rollback;
