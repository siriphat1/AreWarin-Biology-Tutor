-- ============================================================
-- AreWarin Biology · Tutor OS V14 Integration Upgrade
-- Run ONCE on an existing AreWarin V13 Supabase project.
-- Idempotent: safe to run again.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- ---------- Staff bridge: Manager/Auth -> Tutor OS ----------
create table if not exists public.os_staff_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'teacher' check (role in ('teacher','admin')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.os_is_staff()
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists(
    select 1 from public.os_staff_profiles p
    where p.user_id = auth.uid() and p.is_active = true and p.role in ('teacher','admin')
  );
$$;

create or replace function public.os_is_admin()
returns boolean
language sql stable security definer set search_path=public
as $$
  select exists(
    select 1 from public.os_staff_profiles p
    where p.user_id = auth.uid() and p.is_active = true and p.role = 'admin'
  );
$$;

revoke all on function public.os_is_staff() from public, anon;
revoke all on function public.os_is_admin() from public, anon;
grant execute on function public.os_is_staff() to authenticated;
grant execute on function public.os_is_admin() to authenticated;

create or replace function public.os_sync_manager_profile()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.os_staff_profiles(user_id, display_name, role, is_active, updated_at)
  values(
    new.id,
    coalesce(new.display_name, 'AreWarin Staff'),
    case when new.role in ('admin','manager') then 'admin' else 'teacher' end,
    true,
    now()
  )
  on conflict(user_id) do update set
    display_name = excluded.display_name,
    role = excluded.role,
    is_active = excluded.is_active,
    updated_at = now();
  return new;
end $$;

drop trigger if exists trg_os_sync_manager_profile on public.profiles;
create trigger trg_os_sync_manager_profile
after insert or update of display_name, role on public.profiles
for each row execute function public.os_sync_manager_profile();

insert into public.os_staff_profiles(user_id, display_name, role, is_active)
select id, coalesce(display_name,'AreWarin Staff'), 'admin', true
from public.profiles
where role in ('manager','admin')
on conflict(user_id) do update set
  display_name=excluded.display_name,
  role='admin',
  is_active=true,
  updated_at=now();

-- ---------- Shared operational student record ----------
create table if not exists public.os_students (
  id uuid primary key default gen_random_uuid(),
  source_enrollment_id uuid references public.enrollments(id) on delete set null,
  phone_key text unique,
  display_name text not null,
  first_name text,
  last_name text,
  nickname text,
  phone text,
  email text,
  line_id text,
  school text,
  grade text,
  faculty text,
  province text,
  parent_name text,
  parent_phone text,
  status text not null default 'active',
  course_summary text,
  study_type text,
  notes text,
  archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists os_students_phone_idx on public.os_students(phone_key);
create index if not exists os_students_status_idx on public.os_students(status,archived);

create table if not exists public.os_student_course_enrollments (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  course_id uuid references public.courses(id) on delete set null,
  tutor_id uuid references public.tutors(id) on delete set null,
  source_enrollment_id uuid unique references public.enrollments(id) on delete set null,
  course_label text,
  tutor_label text,
  status text not null default 'active',
  enrolled_at date,
  ended_at date,
  hours_total numeric(10,2) not null default 0,
  hours_used numeric(10,2) not null default 0,
  price numeric(12,2) not null default 0,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists os_sce_student_idx on public.os_student_course_enrollments(student_id,status);
create index if not exists os_sce_course_idx on public.os_student_course_enrollments(course_id,status);

-- ---------- CRM / guardian follow-up ----------
create table if not exists public.os_crm_contacts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  line_id text,
  guardian_name text,
  guardian_phone text,
  stage text not null default 'lead',
  source text,
  notes text,
  next_follow_up timestamptz,
  converted_student_id uuid references public.os_students(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Teaching / attendance ----------
create table if not exists public.os_attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references public.courses(id) on delete set null,
  tutor_id uuid references public.tutors(id) on delete set null,
  session_date date not null,
  start_time time,
  end_time time,
  title text,
  mode text,
  location text,
  status text not null default 'open' check(status in ('open','completed','cancelled')),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_student_attendance (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.os_attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.os_students(id) on delete cascade,
  status text not null default 'present' check(status in ('present','late','absent','leave')),
  checked_in_at timestamptz,
  source text not null default 'admin',
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(session_id,student_id)
);

create table if not exists public.os_teaching_logs (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.os_students(id) on delete set null,
  course_id uuid references public.courses(id) on delete set null,
  tutor_id uuid references public.tutors(id) on delete set null,
  lesson_date date not null default current_date,
  topic text not null,
  hours numeric(8,2) not null default 0,
  notes text,
  outcome text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Learning portal content ----------
create table if not exists public.os_learning_topics (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references public.courses(id) on delete cascade,
  title text not null,
  description text,
  sort_order integer not null default 100,
  publish_at timestamptz not null default now(),
  available_until timestamptz,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_learning_assets (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.os_learning_topics(id) on delete cascade,
  title text not null,
  asset_type text not null default 'link' check(asset_type in ('video','file','link','sheet')),
  url text,
  storage_path text,
  sort_order integer not null default 100,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_learning_assignments (
  id uuid primary key default gen_random_uuid(),
  topic_id uuid not null references public.os_learning_topics(id) on delete cascade,
  student_id uuid references public.os_students(id) on delete cascade,
  assignment_scope text not null default 'course' check(assignment_scope in ('course','student')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(topic_id,student_id,assignment_scope)
);

-- ---------- Tasks / communication ----------
create table if not exists public.os_tasks (
  id uuid primary key default gen_random_uuid(),
  task_text text not null,
  priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  due_date date,
  assigned_student_id uuid references public.os_students(id) on delete set null,
  assigned_to uuid references auth.users(id) on delete set null,
  note text,
  completed boolean not null default false,
  completed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  publish_at timestamptz not null default now(),
  expires_at timestamptz,
  is_active boolean not null default true,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_quick_replies (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message_text text not null,
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Finance ----------
create table if not exists public.os_finance_entries (
  id uuid primary key default gen_random_uuid(),
  source_payment_id uuid unique references public.payments(id) on delete set null,
  student_id uuid references public.os_students(id) on delete set null,
  course_id uuid references public.courses(id) on delete set null,
  transaction_date date not null default current_date,
  description text not null,
  amount numeric(12,2) not null default 0,
  entry_type text not null default 'income' check(entry_type in ('income','expense','refund','adjustment')),
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_payment_slips (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.os_students(id) on delete set null,
  source_payment_id uuid references public.payments(id) on delete set null,
  storage_path text not null,
  original_filename text,
  mime_type text,
  file_size bigint,
  payment_amount numeric(12,2),
  payment_date date,
  note text,
  uploaded_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- ---------- Library / HR / course requests ----------
create table if not exists public.os_library_items (
  id uuid primary key default gen_random_uuid(),
  category text,
  subject_key text,
  title text not null,
  description text,
  item_type text not null default 'link' check(item_type in ('book','video','file','link','worksheet','other')),
  url text,
  storage_path text,
  tags text[] not null default '{}',
  is_active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_hr_entries (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid references public.tutors(id) on delete set null,
  entry_type text not null default 'note' check(entry_type in ('note','compensation','evaluation','training')),
  entry_date date not null default current_date,
  amount numeric(12,2),
  title text not null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_course_requests (
  id uuid primary key default gen_random_uuid(),
  requested_by uuid references auth.users(id) on delete set null,
  title text not null,
  description text,
  target_levels text[] not null default '{}',
  proposed_hours numeric(10,2),
  proposed_price numeric(12,2),
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  admin_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.os_settings (
  key text primary key,
  value jsonb not null default 'null'::jsonb,
  description text,
  updated_at timestamptz not null default now()
);

create table if not exists public.os_activity_log (
  id bigint generated by default as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---------- Generic updated_at trigger ----------
create or replace function public.os_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

do $$
declare t text;
begin
  foreach t in array array[
    'os_staff_profiles','os_students','os_student_course_enrollments','os_crm_contacts',
    'os_attendance_sessions','os_student_attendance','os_teaching_logs','os_learning_topics',
    'os_learning_assets','os_tasks','os_announcements','os_quick_replies','os_finance_entries',
    'os_library_items','os_hr_entries','os_course_requests'
  ] loop
    execute format('drop trigger if exists %I on public.%I', 'trg_'||t||'_touch', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.os_touch_updated_at()', 'trg_'||t||'_touch', t);
  end loop;
end $$;

-- ---------- Core enrollment -> Tutor OS student bridge ----------
create or replace function public.os_sync_enrollment()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  v_key text;
  v_student_id uuid;
  v_course_id uuid;
  v_tutor_id uuid;
begin
  v_key := regexp_replace(coalesce(new.phone,''), '[^0-9+]', '', 'g');
  if v_key = '' then v_key := 'enrollment:' || new.id::text; end if;

  select c.id into v_course_id
  from public.courses c
  where lower(c.name)=lower(coalesce(new.course_text,''))
  order by c.active desc, c.sort_order asc limit 1;

  select t.id into v_tutor_id
  from public.tutors t
  where lower(t.display_name)=lower(coalesce(new.tutor_text,''))
  order by t.active desc, t.sort_order asc limit 1;

  insert into public.os_students(
    source_enrollment_id, phone_key, display_name, nickname, phone, email, line_id,
    school, grade, faculty, province, parent_name, parent_phone, status,
    course_summary, study_type, updated_at
  ) values (
    new.id, v_key, new.fullname, new.nickname, new.phone, new.email, new.line_id,
    new.school, new.grade, new.faculty, new.province, new.parent_name, new.parent_phone,
    case when new.status='confirmed' then 'active' when new.status in ('cancelled','rejected') then 'inactive' else 'pending' end,
    new.course_text, new.study_type, now()
  )
  on conflict(phone_key) do update set
    source_enrollment_id=excluded.source_enrollment_id,
    display_name=excluded.display_name,
    nickname=excluded.nickname,
    phone=excluded.phone,
    email=excluded.email,
    line_id=excluded.line_id,
    school=excluded.school,
    grade=excluded.grade,
    faculty=excluded.faculty,
    province=excluded.province,
    parent_name=excluded.parent_name,
    parent_phone=excluded.parent_phone,
    status=excluded.status,
    course_summary=excluded.course_summary,
    study_type=excluded.study_type,
    updated_at=now()
  returning id into v_student_id;

  insert into public.os_student_course_enrollments(
    student_id, course_id, tutor_id, source_enrollment_id, course_label, tutor_label,
    status, enrolled_at, price, note
  ) values (
    v_student_id, v_course_id, v_tutor_id, new.id, new.course_text, new.tutor_text,
    case when new.status='confirmed' then 'active' when new.status in ('cancelled','rejected') then 'cancelled' else 'pending' end,
    new.created_at::date, new.amount_quoted, 'Synced from main enrollment'
  )
  on conflict(source_enrollment_id) do update set
    student_id=excluded.student_id,
    course_id=excluded.course_id,
    tutor_id=excluded.tutor_id,
    course_label=excluded.course_label,
    tutor_label=excluded.tutor_label,
    status=excluded.status,
    price=excluded.price,
    updated_at=now();

  return new;
end $$;

drop trigger if exists trg_os_sync_enrollment on public.enrollments;
create trigger trg_os_sync_enrollment
after insert or update on public.enrollments
for each row execute function public.os_sync_enrollment();

-- Backfill existing enrollments through the same mapping logic without firing fake updates.
insert into public.os_students(source_enrollment_id,phone_key,display_name,nickname,phone,email,line_id,school,grade,faculty,province,parent_name,parent_phone,status,course_summary,study_type)
select distinct on (case when regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g') end)
  e.id,
  case when regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g') end,
  e.fullname,e.nickname,e.phone,e.email,e.line_id,e.school,e.grade,e.faculty,e.province,e.parent_name,e.parent_phone,
  case when e.status='confirmed' then 'active' when e.status in ('cancelled','rejected') then 'inactive' else 'pending' end,
  e.course_text,e.study_type
from public.enrollments e
order by (case when regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g') end), e.created_at desc
on conflict(phone_key) do update set
  source_enrollment_id=excluded.source_enrollment_id,
  display_name=excluded.display_name,
  nickname=excluded.nickname,
  phone=excluded.phone,
  email=excluded.email,
  line_id=excluded.line_id,
  school=excluded.school,
  grade=excluded.grade,
  faculty=excluded.faculty,
  province=excluded.province,
  parent_name=excluded.parent_name,
  parent_phone=excluded.parent_phone,
  status=excluded.status,
  course_summary=excluded.course_summary,
  study_type=excluded.study_type,
  updated_at=now();

insert into public.os_student_course_enrollments(student_id,course_id,tutor_id,source_enrollment_id,course_label,tutor_label,status,enrolled_at,price,note)
select s.id,
       (select c.id from public.courses c where lower(c.name)=lower(coalesce(e.course_text,'')) order by c.active desc,c.sort_order limit 1),
       (select t.id from public.tutors t where lower(t.display_name)=lower(coalesce(e.tutor_text,'')) order by t.active desc,t.sort_order limit 1),
       e.id,e.course_text,e.tutor_text,
       case when e.status='confirmed' then 'active' when e.status in ('cancelled','rejected') then 'cancelled' else 'pending' end,
       e.created_at::date,e.amount_quoted,'Backfilled from main enrollment'
from public.enrollments e
join public.os_students s on s.phone_key = case when regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g') end
on conflict(source_enrollment_id) do update set
  student_id=excluded.student_id,course_id=excluded.course_id,tutor_id=excluded.tutor_id,
  course_label=excluded.course_label,tutor_label=excluded.tutor_label,status=excluded.status,
  price=excluded.price,updated_at=now();

-- ---------- Core payment -> Tutor OS finance bridge ----------
create or replace function public.os_sync_payment()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_student uuid; v_course uuid; v_desc text; v_amount numeric;
begin
  select s.id, sce.course_id
  into v_student, v_course
  from public.enrollments e
  left join public.os_students s
    on s.phone_key = case
      when regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')='' then 'enrollment:'||e.id::text
      else regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')
    end
  left join public.os_student_course_enrollments sce on sce.source_enrollment_id=e.id
  where e.id=new.enrollment_id limit 1;

  select coalesce(e.fullname,'ผู้เรียน') || ' · ' || coalesce(e.course_text,'คอร์ส')
  into v_desc from public.enrollments e where e.id=new.enrollment_id;
  v_amount := coalesce(new.verified_amount,new.amount_submitted,0);

  insert into public.os_finance_entries(source_payment_id,student_id,course_id,transaction_date,description,amount,entry_type,note)
  values(new.id,v_student,v_course,coalesce(new.verified_at::date,new.created_at::date,current_date),coalesce(v_desc,'Payment'),v_amount,
         case when new.status='rejected' then 'adjustment' else 'income' end,
         'Synced from main payment · status='||new.status)
  on conflict(source_payment_id) do update set
    student_id=excluded.student_id,course_id=excluded.course_id,transaction_date=excluded.transaction_date,
    description=excluded.description,amount=excluded.amount,entry_type=excluded.entry_type,note=excluded.note,updated_at=now();
  return new;
end $$;

drop trigger if exists trg_os_sync_payment on public.payments;
create trigger trg_os_sync_payment
after insert or update on public.payments
for each row execute function public.os_sync_payment();

insert into public.os_finance_entries(source_payment_id,student_id,course_id,transaction_date,description,amount,entry_type,note)
select p.id,s.id,sce.course_id,coalesce(p.verified_at::date,p.created_at::date),
       coalesce(e.fullname,'ผู้เรียน')||' · '||coalesce(e.course_text,'คอร์ส'),
       coalesce(p.verified_amount,p.amount_submitted,0),
       case when p.status='rejected' then 'adjustment' else 'income' end,
       'Backfilled from main payment · status='||p.status
from public.payments p
join public.enrollments e on e.id=p.enrollment_id
left join public.os_students s on s.phone_key = case
  when regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')='' then 'enrollment:'||e.id::text
  else regexp_replace(coalesce(e.phone,''), '[^0-9+]', '', 'g')
end
left join public.os_student_course_enrollments sce on sce.source_enrollment_id=e.id
on conflict(source_payment_id) do update set
  student_id=excluded.student_id,course_id=excluded.course_id,transaction_date=excluded.transaction_date,
  description=excluded.description,amount=excluded.amount,entry_type=excluded.entry_type,note=excluded.note,updated_at=now();

-- ---------- Safe student archive/delete ----------
create or replace function public.os_archive_student(p_student_id uuid, p_mode text default 'archive')
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_name text;
begin
  if not public.os_is_admin() then raise exception 'Admin permission required'; end if;
  select display_name into v_name from public.os_students where id=p_student_id;
  if v_name is null then raise exception 'Student not found'; end if;
  if p_mode='delete' then
    delete from public.os_students where id=p_student_id;
    return jsonb_build_object('ok',true,'mode','delete','message','ลบข้อมูล Tutor OS แล้ว');
  end if;
  update public.os_students set archived=true,status='archived',updated_at=now() where id=p_student_id;
  return jsonb_build_object('ok',true,'mode','archive','message','เก็บนักเรียนเข้าคลังแล้ว');
end $$;
grant execute on function public.os_archive_student(uuid,text) to authenticated;

-- ---------- RLS ----------
-- Operational data: teachers can work with teaching/CRM content, but destructive or
-- sensitive administration remains server-side admin only.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'os_crm_contacts','os_attendance_sessions','os_student_attendance','os_teaching_logs',
    'os_learning_topics','os_learning_assets','os_learning_assignments','os_tasks',
    'os_announcements','os_quick_replies','os_library_items'
  ] LOOP
    EXECUTE format('alter table public.%I enable row level security', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS staff access', t);
    EXECUTE format('create policy %I on public.%I for all to authenticated using (public.os_is_staff()) with check (public.os_is_staff())', 'Tutor OS staff access', t);
  END LOOP;
END $$;

-- Student operational records: staff may read/create/update; permanent delete is admin-only.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['os_students','os_student_course_enrollments'] LOOP
    EXECUTE format('alter table public.%I enable row level security', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS staff access', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS staff read', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS staff insert', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS staff update', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS admin delete', t);
    EXECUTE format('create policy %I on public.%I for select to authenticated using (public.os_is_staff())', 'Tutor OS staff read', t);
    EXECUTE format('create policy %I on public.%I for insert to authenticated with check (public.os_is_staff())', 'Tutor OS staff insert', t);
    EXECUTE format('create policy %I on public.%I for update to authenticated using (public.os_is_staff()) with check (public.os_is_staff())', 'Tutor OS staff update', t);
    EXECUTE format('create policy %I on public.%I for delete to authenticated using (public.os_is_admin())', 'Tutor OS admin delete', t);
  END LOOP;
END $$;

-- Course requests: any staff can submit/read; only admin can review/update/delete.
alter table public.os_course_requests enable row level security;
drop policy if exists "Tutor OS staff access" on public.os_course_requests;
drop policy if exists "Tutor OS request read" on public.os_course_requests;
drop policy if exists "Tutor OS request insert" on public.os_course_requests;
drop policy if exists "Tutor OS request admin update" on public.os_course_requests;
drop policy if exists "Tutor OS request admin delete" on public.os_course_requests;
create policy "Tutor OS request read" on public.os_course_requests for select to authenticated using(public.os_is_staff());
create policy "Tutor OS request insert" on public.os_course_requests for insert to authenticated with check(public.os_is_staff() and requested_by=auth.uid());
create policy "Tutor OS request admin update" on public.os_course_requests for update to authenticated using(public.os_is_admin()) with check(public.os_is_admin());
create policy "Tutor OS request admin delete" on public.os_course_requests for delete to authenticated using(public.os_is_admin());

-- Staff directory: staff can read; only admins can grant/revoke Tutor OS permissions.
alter table public.os_staff_profiles enable row level security;
drop policy if exists "Tutor OS staff access" on public.os_staff_profiles;
drop policy if exists "Tutor OS own profile" on public.os_staff_profiles;
drop policy if exists "Tutor OS staff directory" on public.os_staff_profiles;
drop policy if exists "Tutor OS admin staff insert" on public.os_staff_profiles;
drop policy if exists "Tutor OS admin staff update" on public.os_staff_profiles;
drop policy if exists "Tutor OS admin staff delete" on public.os_staff_profiles;
create policy "Tutor OS staff directory" on public.os_staff_profiles for select to authenticated using(public.os_is_staff() or user_id=auth.uid());
create policy "Tutor OS admin staff insert" on public.os_staff_profiles for insert to authenticated with check(public.os_is_admin());
create policy "Tutor OS admin staff update" on public.os_staff_profiles for update to authenticated using(public.os_is_admin()) with check(public.os_is_admin());
create policy "Tutor OS admin staff delete" on public.os_staff_profiles for delete to authenticated using(public.os_is_admin());

-- Sensitive modules are admin-only at the database layer, not merely hidden in the UI.
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['os_finance_entries','os_payment_slips','os_hr_entries','os_activity_log'] LOOP
    EXECUTE format('alter table public.%I enable row level security', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS staff access', t);
    EXECUTE format('drop policy if exists %I on public.%I', 'Tutor OS admin access', t);
    EXECUTE format('create policy %I on public.%I for all to authenticated using (public.os_is_admin()) with check (public.os_is_admin())', 'Tutor OS admin access', t);
  END LOOP;
END $$;

-- OS settings are visible to staff but mutable only by admin.
alter table public.os_settings enable row level security;
drop policy if exists "Tutor OS staff access" on public.os_settings;
drop policy if exists "Tutor OS settings read" on public.os_settings;
drop policy if exists "Tutor OS settings admin write" on public.os_settings;
create policy "Tutor OS settings read" on public.os_settings for select to authenticated using(public.os_is_staff());
create policy "Tutor OS settings admin write" on public.os_settings for all to authenticated using(public.os_is_admin()) with check(public.os_is_admin());

-- Let Tutor OS staff read the current shared catalog/schedule without duplicating it.
-- Existing public/manager policies remain intact; these are additional SELECT policies only.
do $$
begin
  if to_regclass('public.tutors') is not null then
    execute 'drop policy if exists "Tutor OS staff read tutors" on public.tutors';
    execute 'create policy "Tutor OS staff read tutors" on public.tutors for select to authenticated using(public.os_is_staff())';
  end if;
  if to_regclass('public.courses') is not null then
    execute 'drop policy if exists "Tutor OS staff read courses" on public.courses';
    execute 'create policy "Tutor OS staff read courses" on public.courses for select to authenticated using(public.os_is_staff())';
  end if;
  if to_regclass('public.schedule_templates') is not null then
    execute 'drop policy if exists "Tutor OS staff read schedule templates" on public.schedule_templates';
    execute 'create policy "Tutor OS staff read schedule templates" on public.schedule_templates for select to authenticated using(public.os_is_staff())';
  end if;
  if to_regclass('public.tutor_schedules') is not null then
    execute 'drop policy if exists "Tutor OS staff read schedules" on public.tutor_schedules';
    execute 'create policy "Tutor OS staff read schedules" on public.tutor_schedules for select to authenticated using(public.os_is_staff())';
  end if;
end $$;

-- OS admins can read sensitive core workflow records even when they are not a main Manager profile.
do $$
begin
  if to_regclass('public.enrollments') is not null then
    execute 'drop policy if exists "Tutor OS admin read enrollments" on public.enrollments';
    execute 'create policy "Tutor OS admin read enrollments" on public.enrollments for select to authenticated using(public.os_is_admin())';
  end if;
  if to_regclass('public.payments') is not null then
    execute 'drop policy if exists "Tutor OS admin read payments" on public.payments';
    execute 'create policy "Tutor OS admin read payments" on public.payments for select to authenticated using(public.os_is_admin())';
  end if;
  if to_regclass('public.tutor_applications') is not null then
    execute 'drop policy if exists "Tutor OS admin read tutor applications" on public.tutor_applications';
    execute 'create policy "Tutor OS admin read tutor applications" on public.tutor_applications for select to authenticated using(public.os_is_admin())';
  end if;
  if to_regclass('public.speaker_requests') is not null then
    execute 'drop policy if exists "Tutor OS admin read speaker requests" on public.speaker_requests';
    execute 'create policy "Tutor OS admin read speaker requests" on public.speaker_requests for select to authenticated using(public.os_is_admin())';
  end if;
  if to_regclass('public.promotions') is not null then
    execute 'drop policy if exists "Tutor OS admin read promotions" on public.promotions';
    execute 'create policy "Tutor OS admin read promotions" on public.promotions for select to authenticated using(public.os_is_admin())';
  end if;
  if to_regclass('public.course_prices') is not null then
    execute 'drop policy if exists "Tutor OS admin read prices" on public.course_prices';
    execute 'create policy "Tutor OS admin read prices" on public.course_prices for select to authenticated using(public.os_is_admin())';
  end if;
end $$;

grant select,insert,update,delete on
  public.os_staff_profiles, public.os_students, public.os_student_course_enrollments,
  public.os_crm_contacts, public.os_attendance_sessions, public.os_student_attendance,
  public.os_teaching_logs, public.os_learning_topics, public.os_learning_assets,
  public.os_learning_assignments, public.os_tasks, public.os_announcements,
  public.os_quick_replies, public.os_finance_entries, public.os_payment_slips,
  public.os_library_items, public.os_hr_entries, public.os_course_requests,
  public.os_settings, public.os_activity_log
to authenticated;

grant usage, select on all sequences in schema public to authenticated;

-- ---------- Private storage for Tutor OS ----------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'tutor-os-assets','tutor-os-assets',false,15728640,
  array['image/jpeg','image/png','image/webp','application/pdf','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict(id) do update set
  public=false,
  file_size_limit=15728640;

drop policy if exists "Tutor OS staff read assets" on storage.objects;
create policy "Tutor OS staff read assets" on storage.objects
for select to authenticated using(bucket_id='tutor-os-assets' and public.os_is_staff());

drop policy if exists "Tutor OS staff upload assets" on storage.objects;
create policy "Tutor OS staff upload assets" on storage.objects
for insert to authenticated with check(bucket_id='tutor-os-assets' and public.os_is_staff());

drop policy if exists "Tutor OS staff update assets" on storage.objects;
create policy "Tutor OS staff update assets" on storage.objects
for update to authenticated using(bucket_id='tutor-os-assets' and public.os_is_staff()) with check(bucket_id='tutor-os-assets' and public.os_is_staff());

drop policy if exists "Tutor OS admin delete assets" on storage.objects;
create policy "Tutor OS admin delete assets" on storage.objects
for delete to authenticated using(bucket_id='tutor-os-assets' and public.os_is_admin());

-- ---------- Defaults ----------
insert into public.os_settings(key,value,description) values
  ('academy_status','{"holiday":false,"reason":"","return_date":null}'::jsonb,'Tutor OS academy/holiday status'),
  ('portal','{"enabled":true}'::jsonb,'Student portal settings'),
  ('finance','{"currency":"THB"}'::jsonb,'Finance settings')
on conflict(key) do nothing;

commit;

-- Verification
select
  (select count(*) from public.os_staff_profiles) as os_staff,
  (select count(*) from public.os_students) as os_students,
  (select count(*) from public.os_student_course_enrollments) as os_course_links,
  (select count(*) from public.os_finance_entries) as os_finance_entries;
