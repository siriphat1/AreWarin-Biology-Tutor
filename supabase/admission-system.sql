-- ============================================================
-- Wat Nongwang Wittaya - Admission Subweb / Supabase backend
-- Public: submit applications + check limited status
-- Staff (Supabase Authentication): read/review/approve/reject/print
-- Documents: private Storage bucket admission-files
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- 1) Applications table ----------
create sequence if not exists public.admission_app_number_seq start 1;

create table if not exists public.admission_applications (
  id uuid primary key default gen_random_uuid(),
  app_number text unique,
  academic_year integer not null default 2569,

  submission_state text not null default 'uploading'
    check (submission_state in ('uploading','submitted')),
  status text not null default 'pending'
    check (status in ('pending','under_review','approved','rejected','waitlist')),

  title text,
  fname text not null,
  lname text not null,
  chaya text,
  id_card text not null,
  dob date,
  age integer,
  phone text,
  email text,
  address text,

  level_id text not null,
  level text not null,
  study_plan text,

  ordination_status text,
  temple_residence text,
  ordination_intention text,

  old_school text,
  old_province text,
  gpa numeric(4,2),

  father_name text,
  father_status text,
  father_id_card text,
  father_occupation text,
  mother_name text,
  mother_status text,
  mother_id_card text,
  mother_occupation text,
  parents_status text,
  sibling_count integer default 0,

  guardian_name text,
  guardian_relation text,
  guardian_phone text,

  has_dhamma boolean not null default false,
  is_nongwang_alumni boolean not null default false,

  -- Keeps every field from the current/future admission form.
  form_data jsonb not null default '{}'::jsonb,
  -- Private Storage object metadata: path/name/type/size/label.
  attachments jsonb not null default '{}'::jsonb,

  admin_note text,
  public_message text,
  reviewed_by uuid,
  reviewed_at timestamptz,
  decision_at timestamptz,

  pdpa_accepted_at timestamptz,
  upload_token uuid,
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  updated_at timestamptz not null default now()
);

create index if not exists admission_applications_id_card_idx
  on public.admission_applications (id_card);
create index if not exists admission_applications_status_idx
  on public.admission_applications (status, submitted_at desc);
create index if not exists admission_applications_level_idx
  on public.admission_applications (level_id, submitted_at desc);

create or replace function public.set_admission_app_number()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_year integer;
  v_seq bigint;
begin
  if new.app_number is null or btrim(new.app_number) = '' then
    v_year := coalesce(new.academic_year, extract(year from timezone('Asia/Bangkok', now()))::integer + 543);
    v_seq := nextval('public.admission_app_number_seq');
    new.app_number := 'NW'
      || right(v_year::text, 2)
      || upper(coalesce(nullif(new.level_id,''), 'XX'))
      || '-'
      || lpad(v_seq::text, 5, '0');
  end if;
  return new;
end;
$$;

drop trigger if exists trg_admission_app_number on public.admission_applications;
create trigger trg_admission_app_number
before insert on public.admission_applications
for each row execute function public.set_admission_app_number();

create or replace function public.touch_admission_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trg_admission_updated_at on public.admission_applications;
create trigger trg_admission_updated_at
before update on public.admission_applications
for each row execute function public.touch_admission_updated_at();

-- ---------- 2) Row Level Security ----------
alter table public.admission_applications enable row level security;

-- No direct anonymous reads/writes. Public submission/status use SECURITY DEFINER RPCs.
drop policy if exists "staff read admission applications" on public.admission_applications;
create policy "staff read admission applications"
on public.admission_applications for select
to authenticated
using (true);

drop policy if exists "staff update admission applications" on public.admission_applications;
create policy "staff update admission applications"
on public.admission_applications for update
to authenticated
using (true)
with check (true);

drop policy if exists "staff delete admission applications" on public.admission_applications;
create policy "staff delete admission applications"
on public.admission_applications for delete
to authenticated
using (true);

revoke all on table public.admission_applications from anon;
grant select, update, delete on table public.admission_applications to authenticated;

-- ---------- 3) Secure public submission RPC ----------
create or replace function public.create_admission_application(p_payload jsonb)
returns table(id uuid, app_number text, upload_token uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.admission_applications;
  v_dob date;
  v_age integer;
  v_gpa numeric(4,2);
begin
  if coalesce((p_payload->>'pdpaAccepted')::boolean, false) is not true then
    raise exception 'กรุณายอมรับเงื่อนไข PDPA ก่อนส่งใบสมัคร';
  end if;
  if coalesce(btrim(p_payload->>'fname'),'') = '' or coalesce(btrim(p_payload->>'lname'),'') = '' then
    raise exception 'กรุณาระบุชื่อและนามสกุล';
  end if;
  if coalesce(p_payload->>'idCard','') !~ '^\d{13}$' then
    raise exception 'เลขประจำตัวประชาชนต้องมี 13 หลัก';
  end if;
  if coalesce(btrim(p_payload->>'levelId'),'') = '' then
    raise exception 'กรุณาเลือกระดับชั้น';
  end if;

  if coalesce(p_payload->>'dob','') ~ '^\d{4}-\d{2}-\d{2}$' then
    v_dob := (p_payload->>'dob')::date;
  end if;
  if coalesce(p_payload->>'age','') ~ '^\d+$' then
    v_age := (p_payload->>'age')::integer;
  end if;
  if coalesce(p_payload->>'gpa','') ~ '^\d+(\.\d+)?$' then
    v_gpa := (p_payload->>'gpa')::numeric(4,2);
  end if;

  insert into public.admission_applications (
    academic_year, submission_state, status,
    title, fname, lname, chaya, id_card, dob, age, phone, email, address,
    level_id, level, study_plan,
    ordination_status, temple_residence, ordination_intention,
    old_school, old_province, gpa,
    father_name, father_status, father_id_card, father_occupation,
    mother_name, mother_status, mother_id_card, mother_occupation,
    parents_status, sibling_count,
    guardian_name, guardian_relation, guardian_phone,
    has_dhamma, is_nongwang_alumni,
    form_data, pdpa_accepted_at, upload_token
  ) values (
    coalesce(nullif(p_payload->>'academicYear','')::integer, 2569), 'uploading', 'pending',
    nullif(p_payload->>'title',''), p_payload->>'fname', p_payload->>'lname', nullif(p_payload->>'chaya',''), p_payload->>'idCard', v_dob, v_age,
    nullif(p_payload->>'phone',''), nullif(p_payload->>'email',''), nullif(p_payload->>'address',''),
    p_payload->>'levelId', coalesce(nullif(p_payload->>'level',''), p_payload->>'levelId'), nullif(p_payload->>'plan',''),
    nullif(p_payload->>'ordinationStatus',''), nullif(p_payload->>'templeResidence',''), nullif(p_payload->>'ordinationIntention',''),
    nullif(p_payload->>'oldSchool',''), nullif(p_payload->>'oldProvince',''), v_gpa,
    nullif(p_payload->>'fatherName',''), nullif(p_payload->>'fatherStatus',''), nullif(p_payload->>'fatherIdCard',''), nullif(p_payload->>'fatherOcc',''),
    nullif(p_payload->>'motherName',''), nullif(p_payload->>'motherStatus',''), nullif(p_payload->>'motherIdCard',''), nullif(p_payload->>'motherOcc',''),
    nullif(p_payload->>'parentsStatus',''), coalesce(nullif(p_payload->>'siblingCount','')::integer,0),
    nullif(p_payload->>'parentFullName',''), nullif(p_payload->>'parentRelation',''), nullif(p_payload->>'parentPhone',''),
    coalesce((p_payload->>'hasDhamma')::boolean,false), coalesce((p_payload->>'isNongwangAlumni')::boolean,false),
    p_payload, now(), gen_random_uuid()
  ) returning * into v_row;

  return query select v_row.id, v_row.app_number, v_row.upload_token;
end;
$$;

revoke all on function public.create_admission_application(jsonb) from public;
grant execute on function public.create_admission_application(jsonb) to anon, authenticated;

-- ---------- 4) Storage upload authorization helper ----------
-- Public objects must be placed under: <application-id>/<upload-token>/<filename>
create or replace function public.can_upload_admission_file(object_name text)
returns boolean
language plpgsql
security definer
stable
set search_path = public
as $$
declare
  v_id uuid;
  v_token uuid;
begin
  begin
    v_id := split_part(object_name, '/', 1)::uuid;
    v_token := split_part(object_name, '/', 2)::uuid;
  exception when others then
    return false;
  end;

  return exists (
    select 1
    from public.admission_applications a
    where a.id = v_id
      and a.upload_token = v_token
      and a.submission_state = 'uploading'
  );
end;
$$;

revoke all on function public.can_upload_admission_file(text) from public;
grant execute on function public.can_upload_admission_file(text) to anon, authenticated;

-- ---------- 5) Finalize after uploads ----------
create or replace function public.finalize_admission_application(
  p_id uuid,
  p_upload_token uuid,
  p_attachments jsonb
)
returns table(app_number text, submitted_at timestamptz, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.admission_applications;
begin
  update public.admission_applications
  set attachments = coalesce(p_attachments, '{}'::jsonb),
      submission_state = 'submitted',
      submitted_at = now(),
      upload_token = null
  where id = p_id
    and upload_token = p_upload_token
    and submission_state = 'uploading'
  returning * into v_row;

  if v_row.id is null then
    raise exception 'ไม่สามารถยืนยันใบสมัครได้ กรุณาลองใหม่';
  end if;

  return query select v_row.app_number, v_row.submitted_at, v_row.status;
end;
$$;

revoke all on function public.finalize_admission_application(uuid,uuid,jsonb) from public;
grant execute on function public.finalize_admission_application(uuid,uuid,jsonb) to anon, authenticated;

-- ---------- 6) Public limited status lookup ----------
create or replace function public.check_admission_status(p_id_card text)
returns table(
  app_number text,
  full_name text,
  level text,
  study_plan text,
  status text,
  public_message text,
  submitted_at timestamptz
)
language sql
security definer
stable
set search_path = public
as $$
  select
    a.app_number,
    concat_ws(' ', concat(coalesce(a.title,''), coalesce(a.fname,'')), nullif(a.chaya,''), a.lname) as full_name,
    a.level,
    coalesce(a.study_plan,'-') as study_plan,
    a.status,
    a.public_message,
    a.submitted_at
  from public.admission_applications a
  where a.id_card = p_id_card
    and a.submission_state = 'submitted'
  order by a.submitted_at desc
  limit 1;
$$;

revoke all on function public.check_admission_status(text) from public;
grant execute on function public.check_admission_status(text) to anon, authenticated;

-- ---------- 7) Private Storage bucket ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'admission-files',
  'admission-files',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp','image/heic','image/heif','application/pdf']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Drop/recreate policies so this SQL can safely be rerun.
drop policy if exists "public upload admission files" on storage.objects;
create policy "public upload admission files"
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'admission-files'
  and public.can_upload_admission_file(name)
);

drop policy if exists "staff read admission files" on storage.objects;
create policy "staff read admission files"
on storage.objects for select
to authenticated
using (bucket_id = 'admission-files');

drop policy if exists "staff update admission files" on storage.objects;
create policy "staff update admission files"
on storage.objects for update
to authenticated
using (bucket_id = 'admission-files')
with check (bucket_id = 'admission-files');

drop policy if exists "staff delete admission files" on storage.objects;
create policy "staff delete admission files"
on storage.objects for delete
to authenticated
using (bucket_id = 'admission-files');

-- Optional cleanup helper for abandoned, never-finalized applications older than 48h.
create or replace function public.cleanup_abandoned_admissions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  delete from public.admission_applications
  where submission_state = 'uploading'
    and created_at < now() - interval '48 hours';
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

revoke all on function public.cleanup_abandoned_admissions() from public;
grant execute on function public.cleanup_abandoned_admissions() to authenticated;

-- End.

-- ---------- 8) Point the main website's Admission quick link to this subweb ----------
do $$
declare
  v_links jsonb;
begin
  if to_regclass('public.site_settings') is not null then
    select jsonb_agg(
      case
        when elem->>'label' = 'รับสมัครนักเรียน'
          then jsonb_set(elem, '{url}', to_jsonb('./admission/'::text), true)
        else elem
      end
    )
    into v_links
    from public.site_settings s,
         jsonb_array_elements(coalesce(s.data->'quickLinks','[]'::jsonb)) elem
    where s.id = 1;

    if v_links is not null then
      update public.site_settings
      set data = jsonb_set(data, '{quickLinks}', v_links, true),
          updated_at = now()
      where id = 1;
    end if;
  end if;
end $$;
