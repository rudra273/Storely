-- 2.0: one bill-number letter per device, so phones billing offline never
-- issue the same number. The shop's first device gets '' (clean numbers,
-- INV/2627/0001); later devices get B, C, ... Z, then BA, BB, ...
-- (INV/2627/B0001). Additive and idempotent.

create table if not exists public.shop_devices (
  shop_id text not null references public.shops(uuid) on delete cascade,
  device_id text not null,
  code text not null,
  registered_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (shop_id, device_id),
  unique (shop_id, code)
);

alter table public.shop_devices enable row level security;

drop policy if exists "Members can view shop devices" on public.shop_devices;
create policy "Members can view shop devices"
on public.shop_devices for select
using (public.is_shop_member(shop_id));
-- No insert/update/delete policies: devices are registered only through
-- register_device(), which assigns the code.

create or replace function public.register_device(
  target_shop_id text,
  device_uuid text
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing text;
  n integer;
  next_code text;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if not public.is_shop_member(target_shop_id) then
    raise exception 'Not a member of this shop';
  end if;
  if coalesce(device_uuid, '') = '' then
    raise exception 'device_uuid is required';
  end if;

  -- Serialise registrations per shop so two phones never get one code.
  perform pg_advisory_xact_lock(hashtext('storely_device:' || target_shop_id));

  select code into existing
  from public.shop_devices
  where shop_id = target_shop_id and device_id = device_uuid;
  if found then
    return existing;
  end if;

  select count(*) into n from public.shop_devices where shop_id = target_shop_id;
  if n = 0 then
    next_code := '';
  elsif n < 26 then
    next_code := chr(65 + n);
  else
    next_code := chr(65 + n / 26) || chr(65 + n % 26);
  end if;

  insert into public.shop_devices (shop_id, device_id, code, registered_by)
  values (target_shop_id, device_uuid, next_code, auth.uid());
  return next_code;
end;
$$;

grant execute on function public.register_device(text, text) to authenticated;
