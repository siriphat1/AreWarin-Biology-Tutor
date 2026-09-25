-- ============================================================
-- Supabase Upgrade: Alumni Directory / ทำเนียบศิษย์เก่า
-- Wat Nongwang Wittaya School
-- Run in Supabase > SQL Editor. Safe to run again.
-- ============================================================

create or replace function public.is_site_admin()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false;
$$;

revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

create table if not exists public.alumni (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  photo_url text not null default '',
  batch text not null,
  graduation_year text not null default '',
  graduation_level text not null default '',
  current_position text not null default '',
  occupation text not null default '',
  organization text not null default '',
  education text not null default '',
  phone text not null default '',
  email text not null default '',
  facebook_url text not null default '',
  bio text not null default '',
  show_contact boolean not null default false,
  featured boolean not null default false,
  published boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create index if not exists alumni_public_idx
  on public.alumni (published, batch, sort_order, full_name);
create index if not exists alumni_batch_idx
  on public.alumni (batch);

alter table public.alumni enable row level security;

drop policy if exists "public read published alumni" on public.alumni;
create policy "public read published alumni" on public.alumni
for select using (published = true);

drop policy if exists "admin read all alumni" on public.alumni;
create policy "admin read all alumni" on public.alumni
for select to authenticated using (public.is_site_admin());

drop policy if exists "admin insert alumni" on public.alumni;
create policy "admin insert alumni" on public.alumni
for insert to authenticated with check (public.is_site_admin());

drop policy if exists "admin update alumni" on public.alumni;
create policy "admin update alumni" on public.alumni
for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

drop policy if exists "admin delete alumni" on public.alumni;
create policy "admin delete alumni" on public.alumni
for delete to authenticated using (public.is_site_admin());

grant select on public.alumni to anon, authenticated;
grant insert, update, delete on public.alumni to authenticated;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists alumni_updated_at on public.alumni;
create trigger alumni_updated_at before update on public.alumni
for each row execute function public.set_updated_at();

comment on table public.alumni is
'Alumni directory records. Staff marked isAlumni remain in site_settings and are merged by the alumni subweb automatically.';


-- structured alumni fields 2026-09-25
alter table public.alumni add column if not exists naktham_level text not null default '';
alter table public.alumni add column if not exists pali_level text not null default '';
alter table public.alumni add column if not exists is_royal_scholarship boolean not null default false;
alter table public.alumni add column if not exists royal_scholarship_batch text not null default '';
alter table public.alumni add column if not exists royal_scholarship_phase text not null default '';
