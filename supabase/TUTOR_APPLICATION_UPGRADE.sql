-- ============================================================
-- AreWarin Biology — Tutor Application System Upgrade
-- Run once in Supabase SQL Editor for an existing project.
-- Safe to re-run.
-- ============================================================

begin;

create table if not exists public.tutor_application_sequences (
  application_year integer primary key,
  last_no bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.tutor_applications (
  id uuid primary key default gen_random_uuid(),
  application_no text not null unique,
  first_name text not null,
  last_name text not null,
  nickname text not null,
  phone text not null,
  email text not null,
  line_id text,
  province text,
  current_occupation text,
  intro text,
  education jsonb not null default '[]'::jsonb,
  work_experience jsonb not null default '[]'::jsonb,
  achievements text,
  subjects text[] not null default '{}'::text[],
  levels text[] not null default '{}'::text[],
  teaching_modes text[] not null default '{}'::text[],
  teaching_experience_years numeric(5,1) not null default 0,
  expected_rate text,
  preferred_location text,
  availability jsonb not null default '[]'::jsonb,
  teaching_style text,
  why_join text,
  additional_note text,
  profile_photo_path text,
  resume_path text,
  portfolio_path text,
  transcript_path text,
  status text not null default 'new' check(status in ('new','reviewing','interview','accepted','rejected','withdrawn')),
  public_status_note text,
  manager_notes text,
  consent_pdpa boolean not null default false,
  certified_accuracy boolean not null default false,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.next_tutor_application_no()
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  y integer := extract(year from timezone('Asia/Bangkok', now()))::integer;
  n bigint;
begin
  insert into public.tutor_application_sequences(application_year,last_no)
  values(y,1)
  on conflict(application_year) do update
    set last_no = tutor_application_sequences.last_no + 1,
        updated_at = now()
  returning last_no into n;
  return 'AWT-' || y::text || '-' || lpad(n::text,6,'0');
end $$;

create or replace function public.check_tutor_application_status(p_application_no text, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  r public.tutor_applications%rowtype;
  normalized_phone text := regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  select * into r
  from public.tutor_applications
  where upper(application_no)=upper(trim(p_application_no))
    and regexp_replace(phone,'\D','','g')=normalized_phone
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found',false);
  end if;

  return jsonb_build_object(
    'found',true,
    'application_no',r.application_no,
    'applicant_name',trim(r.first_name || ' ' || r.last_name),
    'nickname',r.nickname,
    'status',r.status,
    'public_status_note',r.public_status_note,
    'created_at',r.created_at,
    'updated_at',r.updated_at
  );
end $$;

alter table public.tutor_application_sequences enable row level security;
alter table public.tutor_applications enable row level security;

drop policy if exists "manager tutor applications" on public.tutor_applications;
create policy "manager tutor applications"
on public.tutor_applications
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

drop policy if exists "manager tutor application sequences" on public.tutor_application_sequences;
create policy "manager tutor application sequences"
on public.tutor_application_sequences
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'tutor-application-assets',
  'tutor-application-assets',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict(id) do update set
  public=false,
  file_size_limit=10485760,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists "manager read tutor application assets" on storage.objects;
create policy "manager read tutor application assets"
on storage.objects
for select
to authenticated
using (bucket_id='tutor-application-assets' and public.is_manager());

drop policy if exists "manager delete tutor application assets" on storage.objects;
create policy "manager delete tutor application assets"
on storage.objects
for delete
to authenticated
using (bucket_id='tutor-application-assets' and public.is_manager());

-- updated_at helper (safe to create/replace)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- updated_at trigger
drop trigger if exists trg_tutor_applications_updated_at on public.tutor_applications;
create trigger trg_tutor_applications_updated_at
before update on public.tutor_applications
for each row execute function public.set_updated_at();

create index if not exists tutor_applications_status_created_idx
  on public.tutor_applications(status, created_at desc);
create index if not exists tutor_applications_phone_idx
  on public.tutor_applications(phone);
create index if not exists tutor_applications_email_idx
  on public.tutor_applications(lower(email));

revoke all on function public.next_tutor_application_no() from public;
grant execute on function public.next_tutor_application_no() to service_role;

grant execute on function public.check_tutor_application_status(text,text) to anon, authenticated;

grant select, update, delete on public.tutor_applications to authenticated;
grant select on public.tutor_application_sequences to authenticated;
grant all privileges on public.tutor_applications, public.tutor_application_sequences to service_role;

commit;
