-- ============================================================
-- AreWarin Manager - FIX ADMIN ROLE
-- Supabase project: ihmiqtwclnqrezsnswfz
-- Run the ENTIRE file once in Supabase > SQL Editor
-- ============================================================

begin;

-- 1) Ensure the profile table exists.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'manager' check (role in ('manager','admin')),
  created_at timestamptz not null default now()
);

-- 2) Helper used by Manager RLS policies.
create or replace function public.is_manager()
returns boolean
language sql
stable
security definer
set search_path=public
as $$
  select exists(
    select 1 from public.profiles p
    where p.id = auth.uid()
      and p.role in ('manager','admin')
  );
$$;

grant execute on function public.is_manager() to authenticated;

-- 3) Allow an authenticated user to read their own role.
alter table public.profiles enable row level security;

drop policy if exists "profile self read" on public.profiles;
create policy "profile self read"
on public.profiles
for select
to authenticated
using (id = auth.uid() or public.is_manager());

drop policy if exists "manager profiles" on public.profiles;
create policy "manager profiles"
on public.profiles
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

grant select on public.profiles to authenticated;

-- 4) Promote the Auth account the user said is the Manager account.
--    This uses auth.users.id, so the profile UUID will match Authentication exactly.
insert into public.profiles (id, display_name, role)
select
  u.id,
  'AreWarin Admin',
  'admin'
from auth.users u
where lower(trim(u.email)) = lower('arewarun.biology@gmail.com')
on conflict (id) do update
set display_name = excluded.display_name,
    role = 'admin';

commit;

-- 5) ALWAYS returns one diagnostic row.
--    Expected: auth_user_found=true, profile_found=true, profile_role=admin
select
  exists(
    select 1 from auth.users
    where lower(trim(email)) = lower('arewarun.biology@gmail.com')
  ) as auth_user_found,
  coalesce((
    select email from auth.users
    where lower(trim(email)) = lower('arewarun.biology@gmail.com')
    order by created_at desc limit 1
  ), 'NOT FOUND') as auth_email,
  exists(
    select 1
    from auth.users u
    join public.profiles p on p.id = u.id
    where lower(trim(u.email)) = lower('arewarun.biology@gmail.com')
  ) as profile_found,
  coalesce((
    select p.role
    from auth.users u
    join public.profiles p on p.id = u.id
    where lower(trim(u.email)) = lower('arewarun.biology@gmail.com')
    order by u.created_at desc limit 1
  ), 'NO PROFILE') as profile_role,
  coalesce((
    select u.id::text from auth.users u
    where lower(trim(u.email)) = lower('arewarun.biology@gmail.com')
    order by u.created_at desc limit 1
  ), 'NO USER ID') as auth_user_id;
