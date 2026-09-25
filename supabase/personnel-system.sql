-- ============================================================
-- Supabase Upgrade: Dedicated Personnel / บุคลากร
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

create table if not exists public.personnel (
  id uuid primary key default gen_random_uuid(),
  staff_type text not null check (staff_type in ('executives','teachers','specialTeachers')),
  full_name text not null,
  position text not null default '',
  department text not null default '',
  image_url text not null default '',
  education text not null default '',
  phone text not null default '',
  email text not null default '',
  is_alumni boolean not null default false,
  alumni_batch text not null default '',
  is_royal_scholarship boolean not null default false,
  royal_scholarship_batch text not null default '',
  royal_scholarship_phase text not null default '',
  published boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

alter table public.personnel add column if not exists is_royal_scholarship boolean not null default false;
alter table public.personnel add column if not exists royal_scholarship_batch text not null default '';
alter table public.personnel add column if not exists royal_scholarship_phase text not null default '';

create index if not exists personnel_public_order_idx
  on public.personnel (published, staff_type, sort_order, created_at);
create index if not exists personnel_alumni_idx
  on public.personnel (is_alumni, alumni_batch);

alter table public.personnel enable row level security;

drop policy if exists "public read published personnel" on public.personnel;
create policy "public read published personnel" on public.personnel
for select using (published = true);

drop policy if exists "admin read all personnel" on public.personnel;
create policy "admin read all personnel" on public.personnel
for select to authenticated using (public.is_site_admin());

drop policy if exists "admin insert personnel" on public.personnel;
create policy "admin insert personnel" on public.personnel
for insert to authenticated with check (public.is_site_admin());

drop policy if exists "admin update personnel" on public.personnel;
create policy "admin update personnel" on public.personnel
for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

drop policy if exists "admin delete personnel" on public.personnel;
create policy "admin delete personnel" on public.personnel
for delete to authenticated using (public.is_site_admin());

grant select on public.personnel to anon, authenticated;
grant insert, update, delete on public.personnel to authenticated;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists personnel_updated_at on public.personnel;
create trigger personnel_updated_at before update on public.personnel
for each row execute function public.set_updated_at();

-- Migrate legacy personnel arrays from site_settings only when the new table is empty.
-- The old JSON is intentionally left untouched as a rollback copy; the upgraded app
-- reads/writes personnel from public.personnel and no longer saves duplicate staff JSON.
do $$
begin
  if not exists (select 1 from public.personnel limit 1) then
    insert into public.personnel (
      staff_type, full_name, position, department, image_url,
      education, phone, email, is_alumni, alumni_batch,
      is_royal_scholarship, royal_scholarship_batch, royal_scholarship_phase,
      published, sort_order
    )
    select
      src.staff_type,
      coalesce(nullif(src.item->>'name',''), 'ไม่ระบุชื่อ'),
      coalesce(src.item->>'position',''),
      coalesce(src.item->>'department',''),
      coalesce(src.item->>'img',''),
      coalesce(src.item->>'education',''),
      coalesce(src.item->>'phone',''),
      coalesce(src.item->>'email',''),
      case when lower(coalesce(src.item->>'isAlumni','false')) in ('true','1','yes','on') then true else false end,
      coalesce(src.item->>'alumniBatch',''),
      case when lower(coalesce(src.item->>'isRoyalScholarship','false')) in ('true','1','yes','on') then true else false end,
      coalesce(src.item->>'royalScholarshipBatch',''),
      coalesce(src.item->>'royalScholarshipPhase',''),
      case when lower(coalesce(src.item->>'published','true')) in ('false','0','no','off') then false else true end,
      ((src.ord - 1)::integer) * 10
    from public.site_settings s
    cross join lateral (
      select 'executives'::text as staff_type, e.item, e.ord
      from jsonb_array_elements(coalesce(s.data->'executives','[]'::jsonb)) with ordinality as e(item,ord)
      union all
      select 'teachers'::text as staff_type, t.item, t.ord
      from jsonb_array_elements(coalesce(s.data->'teachers','[]'::jsonb)) with ordinality as t(item,ord)
      union all
      select 'specialTeachers'::text as staff_type, sp.item, sp.ord
      from jsonb_array_elements(coalesce(s.data->'specialTeachers','[]'::jsonb)) with ordinality as sp(item,ord)
    ) src
    where s.id = 1;
  end if;
end $$;

comment on table public.personnel is
'Dedicated personnel directory. Website and Manager read/write this table directly; public can read published rows only.';
