-- ============================================================
-- University Admission PR Subweb
-- Run once in Supabase SQL Editor.
-- Public: read published records only
-- Authenticated users: full CRUD (same admin model as current site)
-- ============================================================
create extension if not exists pgcrypto;

create table if not exists public.university_admissions (
  id uuid primary key default gen_random_uuid(),
  university_name text not null,
  logo_url text,
  cover_image_url text,
  faculty text,
  program_name text,
  admission_round text,
  academic_year text,
  campus text,
  status text not null default 'open' check (status in ('open','upcoming','closed')),
  start_date date,
  end_date date,
  description text,
  requirements text,
  apply_url text not null,
  announcement_url text,
  university_url text,
  featured boolean not null default false,
  published boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists university_admissions_public_idx on public.university_admissions (published, status, featured, sort_order, created_at desc);
create index if not exists university_admissions_name_idx on public.university_admissions (university_name);

create or replace function public.touch_university_admissions_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_touch_university_admissions on public.university_admissions;
create trigger trg_touch_university_admissions before update on public.university_admissions
for each row execute function public.touch_university_admissions_updated_at();

alter table public.university_admissions enable row level security;

drop policy if exists "Public can read published university admissions" on public.university_admissions;
create policy "Public can read published university admissions"
on public.university_admissions for select
to anon, authenticated
using (published = true or auth.role() = 'authenticated');

drop policy if exists "Authenticated can insert university admissions" on public.university_admissions;
create policy "Authenticated can insert university admissions"
on public.university_admissions for insert
to authenticated
with check (true);

drop policy if exists "Authenticated can update university admissions" on public.university_admissions;
create policy "Authenticated can update university admissions"
on public.university_admissions for update
to authenticated
using (true) with check (true);

drop policy if exists "Authenticated can delete university admissions" on public.university_admissions;
create policy "Authenticated can delete university admissions"
on public.university_admissions for delete
to authenticated
using (true);

grant select on public.university_admissions to anon;
grant select, insert, update, delete on public.university_admissions to authenticated;

comment on table public.university_admissions is 'ประชาสัมพันธ์การรับสมัครเรียนต่อมหาวิทยาลัย';
