-- Fix: "Could not find a relationship between 'shop_members' and 'profiles'
-- in the schema cache" when an owner/admin opens the Members sheet.
--
-- listMembers() embeds profiles(email) via PostgREST:
--   .select('user_id, role, created_at, profiles(email)')
-- PostgREST resolves embeds from foreign keys. shop_members.user_id only had
-- an FK to auth.users(id), and profiles.id also references auth.users(id), so
-- the two tables were only indirectly related through the auth schema —
-- which PostgREST will not traverse. Adding a direct FK from
-- shop_members.user_id -> profiles.id lets PostgREST resolve the embed.
--
-- This migration is idempotent and safe to re-run.

-- ── Step 1: Backfill any missing profiles ────────────────────────────────
-- Normally public.handle_new_user() inserts a profile for every auth user,
-- so every shop_members.user_id already has a matching profiles row. But to
-- guarantee the FK below can be validated even on projects where a profile
-- row is somehow missing, backfill from auth.users first. Mirrors the columns
-- handle_new_user() populates. on conflict keeps this safe to re-run.
insert into public.profiles (id, email, full_name)
select u.id, u.email, u.raw_user_meta_data ->> 'full_name'
from auth.users u
where exists (
    select 1 from public.shop_members m where m.user_id = u.id
  )
  and not exists (
    select 1 from public.profiles p where p.id = u.id
  )
on conflict (id) do nothing;

-- ── Step 2: Add the foreign key ──────────────────────────────────────────
-- Added as NOT VALID first so existing rows are not scanned while the lock is
-- held (cheap, brief lock), then validated separately. Guarded so the whole
-- block is a no-op if the constraint already exists.
do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'shop_members_user_profile_fk'
      and conrelid = 'public.shop_members'::regclass
  ) then
    alter table public.shop_members
      add constraint shop_members_user_profile_fk
      foreign key (user_id)
      references public.profiles(id)
      on delete cascade
      not valid;
  end if;
end $$;

-- Validate existing rows. Idempotent: validating an already-valid constraint
-- is a harmless no-op. After step 1 there should be no orphan rows.
do $$
begin
  if exists (
    select 1
    from pg_constraint
    where conname = 'shop_members_user_profile_fk'
      and conrelid = 'public.shop_members'::regclass
      and not convalidated
  ) then
    alter table public.shop_members
      validate constraint shop_members_user_profile_fk;
  end if;
end $$;

-- ── Step 3: Refresh PostgREST schema cache ───────────────────────────────
-- So the new relationship is picked up without waiting for a restart.
notify pgrst, 'reload schema';
