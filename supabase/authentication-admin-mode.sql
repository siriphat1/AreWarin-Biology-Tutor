-- ============================================================
-- Upgrade an EXISTING installation to Authentication-first Admin Mode
-- Run this ONCE in Supabase > SQL Editor.
-- Safe to run again.
-- ============================================================

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  -- Authentication-first manager mode. Supabase anonymous users also use the
  -- authenticated Postgres role, so explicitly reject the is_anonymous claim.
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false;
$$;

revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

comment on function public.is_site_admin() is
'Website Manager authorization: every non-anonymous Supabase Authentication user is an admin. Disable public signup and anonymous sign-ins.';

-- Existing RLS policies already call public.is_site_admin(), so no policy
-- recreation is required after replacing this function.

-- SECURITY: In Authentication > General Configuration, disable:
--   * Allow new users to sign up
--   * Allow anonymous sign-ins
