-- Minimal stand-in for Supabase's auth schema so the Storely schema, its
-- migrations and Row Level Security can be tested on plain Postgres.
-- Tests "log in" with:  select tests.login('<uuid>', '<email>');
create extension if not exists pgcrypto;

do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
end $$;

create schema if not exists auth;
create table if not exists auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb default '{}'::jsonb
);

create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create or replace function auth.jwt() returns jsonb
language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

grant usage on schema auth to authenticated, anon;
grant execute on all functions in schema auth to authenticated, anon;

create schema if not exists tests;
grant usage on schema tests to authenticated;

-- Switch the session to an authenticated user (like a PostgREST request).
create or replace function tests.login(user_id uuid, email text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', user_id::text, false);
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', user_id, 'email', email)::text, false);
  execute 'set role authenticated';
end $$;

create or replace function tests.logout() returns void
language plpgsql as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claim.sub', '', false);
  perform set_config('request.jwt.claims', '', false);
end $$;
