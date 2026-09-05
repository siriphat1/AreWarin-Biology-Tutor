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
-- ============================================================
-- AreWarin Biology · V15 Unified System Upgrade
-- Existing project upgrade: V14 -> V15
-- Goal: one data flow across Enrollment, Tutor OS, Student Portal,
--       Course Offering, Teaching Time, Hour Ledger and future subwebs.
-- Idempotent where practical.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- ============================================================
-- 1) Shared Course Offering = single switch for every public app
-- ============================================================
create table if not exists public.course_offerings (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.courses(id) on delete cascade,
  status text not null default 'open' check (status in ('draft','open','paused','closed')),
  enrollment_open boolean not null default true,
  student_portal_open boolean not null default true,
  starts_on date,
  ends_on date,
  capacity integer,
  default_hours numeric(10,2),
  display_price numeric(12,2),
  public_note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(course_id)
);

insert into public.course_offerings(course_id,status,enrollment_open,student_portal_open,created_at,updated_at)
select c.id, case when c.active then 'open' else 'closed' end, c.active, c.active, now(), now()
from public.courses c
on conflict(course_id) do nothing;

create or replace function public.aw_sync_course_offering_from_course()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if tg_op='INSERT' then
    insert into public.course_offerings(course_id,status,enrollment_open,student_portal_open,updated_at)
    values(new.id,case when new.active then 'open' else 'closed' end,new.active,new.active,now())
    on conflict(course_id) do nothing;
  elsif new.active=false then
    update public.course_offerings set status='closed',enrollment_open=false,student_portal_open=false,updated_at=now() where course_id=new.id;
  elsif old.active=false and new.active=true then
    insert into public.course_offerings(course_id,status,enrollment_open,student_portal_open,updated_at)
    values(new.id,'open',true,true,now())
    on conflict(course_id) do update set status='open',enrollment_open=true,student_portal_open=true,updated_at=now();
  end if;
  return new;
end $$;

drop trigger if exists trg_aw_course_offering_sync on public.courses;
create trigger trg_aw_course_offering_sync
after insert or update of active on public.courses
for each row execute function public.aw_sync_course_offering_from_course();

-- ============================================================
-- 2) Canonical enrollment line items (multi-course safe)
-- ============================================================
create table if not exists public.enrollment_items (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  course_id uuid references public.courses(id) on delete restrict,
  tutor_id uuid references public.tutors(id) on delete set null,
  offering_id uuid references public.course_offerings(id) on delete set null,
  course_name_snapshot text,
  tutor_name_snapshot text,
  package_code text,
  share_mode text not null default 'shared' check (share_mode in ('shared','separate')),
  hours_allocated numeric(10,2),
  hours_unlimited boolean not null default false,
  amount_allocated numeric(12,2) not null default 0,
  status text not null default 'pending' check(status in ('pending','active','paused','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(enrollment_id,course_id)
);
create index if not exists enrollment_items_enrollment_idx on public.enrollment_items(enrollment_id,status);
create index if not exists enrollment_items_course_idx on public.enrollment_items(course_id,status);

-- Existing V14 schema only allowed one OS course row per enrollment. V15 supports carts.
alter table public.os_student_course_enrollments drop constraint if exists os_student_course_enrollments_source_enrollment_id_key;
alter table public.os_student_course_enrollments add column if not exists enrollment_item_id uuid references public.enrollment_items(id) on delete set null;
alter table public.os_student_course_enrollments add column if not exists offering_id uuid references public.course_offerings(id) on delete set null;
alter table public.os_student_course_enrollments add column if not exists hour_pool_id uuid;
create unique index if not exists os_sce_enrollment_item_unique on public.os_student_course_enrollments(enrollment_item_id) where enrollment_item_id is not null;
create index if not exists os_sce_source_enrollment_idx on public.os_student_course_enrollments(source_enrollment_id);

-- ============================================================
-- 3) Student identity + Portal account bridge
-- ============================================================
alter table public.os_students add column if not exists student_code text;
alter table public.os_students add column if not exists birth_date date;
alter table public.os_students add column if not exists address text;
alter table public.os_students add column if not exists guardian_name text;
alter table public.os_students add column if not exists guardian_relationship text;
alter table public.os_students add column if not exists guardian_phone text;
alter table public.os_students add column if not exists guardian_line text;
create unique index if not exists os_students_student_code_unique on public.os_students(student_code) where student_code is not null;

create table if not exists public.student_code_sequences (
  year_no integer primary key,
  last_no integer not null default 0
);

create or replace function public.aw_next_student_code()
returns text language plpgsql security definer set search_path=public as $$
declare y int:=extract(year from now())::int; n int;
begin
  insert into public.student_code_sequences(year_no,last_no) values(y,1)
  on conflict(year_no) do update set last_no=public.student_code_sequences.last_no+1
  returning last_no into n;
  return 'AWS-'||y::text||'-'||lpad(n::text,6,'0');
end $$;

update public.os_students set student_code=public.aw_next_student_code() where student_code is null;

create or replace function public.aw_assign_student_code()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.student_code is null or btrim(new.student_code)='' then new.student_code:=public.aw_next_student_code(); end if;
  return new;
end $$;
drop trigger if exists trg_aw_student_code on public.os_students;
create trigger trg_aw_student_code before insert on public.os_students for each row execute function public.aw_assign_student_code();

create table if not exists public.os_student_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  student_id uuid not null unique references public.os_students(id) on delete cascade,
  pin_hash text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ============================================================
-- 4) Shared hour pools + auditable hour ledger
-- ============================================================
create table if not exists public.os_hour_pools (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  source_enrollment_id uuid references public.enrollments(id) on delete set null,
  pool_key text not null,
  package_code text,
  total_hours numeric(10,2),
  used_hours numeric(10,2) not null default 0,
  unlimited boolean not null default false,
  status text not null default 'active' check(status in ('pending','active','paused','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(student_id,source_enrollment_id,pool_key)
);

do $$ begin
  if not exists (select 1 from pg_constraint where conname='os_sce_hour_pool_fk' and conrelid='public.os_student_course_enrollments'::regclass) then
    alter table public.os_student_course_enrollments add constraint os_sce_hour_pool_fk foreign key (hour_pool_id) references public.os_hour_pools(id) on delete set null not valid;
    alter table public.os_student_course_enrollments validate constraint os_sce_hour_pool_fk;
  end if;
end $$;

create table if not exists public.os_hour_ledger (
  id uuid primary key default gen_random_uuid(),
  pool_id uuid not null references public.os_hour_pools(id) on delete cascade,
  student_id uuid not null references public.os_students(id) on delete cascade,
  student_course_enrollment_id uuid references public.os_student_course_enrollments(id) on delete set null,
  course_id uuid references public.courses(id) on delete set null,
  session_id uuid references public.os_attendance_sessions(id) on delete set null,
  entry_type text not null default 'usage' check(entry_type in ('usage','restore','adjustment','opening')),
  hours_delta numeric(10,2) not null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create unique index if not exists os_hour_ledger_session_course_unique
on public.os_hour_ledger(session_id,student_course_enrollment_id,entry_type)
where session_id is not null and student_course_enrollment_id is not null and entry_type in ('usage','restore');
create index if not exists os_hour_ledger_student_idx on public.os_hour_ledger(student_id,created_at desc);

create or replace function public.aw_refresh_hour_pool(p_pool_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_used numeric(10,2);
begin
  select greatest(0,coalesce(sum(hours_delta),0)) into v_used from public.os_hour_ledger where pool_id=p_pool_id;
  update public.os_hour_pools set used_hours=v_used,updated_at=now(),
    status=case when unlimited then status when total_hours is not null and v_used>=total_hours then 'completed' else case when status='completed' then 'active' else status end end
  where id=p_pool_id;
  update public.os_student_course_enrollments sce
     set hours_used=v_used,
         hours_total=coalesce(p.total_hours,sce.hours_total),
         updated_at=now()
    from public.os_hour_pools p
   where p.id=p_pool_id and sce.hour_pool_id=p.id;
end $$;

create or replace function public.aw_hour_ledger_refresh_trg()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  perform public.aw_refresh_hour_pool(coalesce(new.pool_id,old.pool_id));
  return coalesce(new,old);
end $$;
drop trigger if exists trg_aw_hour_ledger_refresh on public.os_hour_ledger;
create trigger trg_aw_hour_ledger_refresh after insert or update or delete on public.os_hour_ledger
for each row execute function public.aw_hour_ledger_refresh_trg();

-- ============================================================
-- 5) Teaching time clock / attendance / deduct hours
-- ============================================================
alter table public.os_attendance_sessions add column if not exists actual_start_at timestamptz;
alter table public.os_attendance_sessions add column if not exists actual_end_at timestamptz;
alter table public.os_attendance_sessions add column if not exists duration_minutes integer;
alter table public.os_attendance_sessions add column if not exists billable_hours numeric(8,2);
alter table public.os_attendance_sessions add column if not exists duration_source text default 'scheduled';
alter table public.os_attendance_sessions add column if not exists deduction_status text default 'not_deducted';
alter table public.os_attendance_sessions add column if not exists deducted_at timestamptz;
alter table public.os_attendance_sessions add column if not exists deducted_by uuid references auth.users(id) on delete set null;
alter table public.os_attendance_sessions add column if not exists deduction_note text;
alter table public.os_student_attendance add column if not exists billable boolean not null default true;

create or replace function public.os_start_session(p_session_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.os_attendance_sessions;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  update public.os_attendance_sessions set actual_start_at=coalesce(actual_start_at,now()),status='open',updated_at=now()
  where id=p_session_id returning * into s;
  if s.id is null then raise exception 'Session not found'; end if;
  return to_jsonb(s);
end $$;

create or replace function public.os_stop_session(p_session_id uuid, p_manual_hours numeric default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.os_attendance_sessions; mins integer; hrs numeric(8,2);
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  select * into s from public.os_attendance_sessions where id=p_session_id for update;
  if s.id is null then raise exception 'Session not found'; end if;
  if s.actual_start_at is null then s.actual_start_at:=now(); end if;
  s.actual_end_at:=now();
  mins:=greatest(0,round(extract(epoch from (s.actual_end_at-s.actual_start_at))/60.0)::int);
  hrs:=case when p_manual_hours is not null then greatest(0,p_manual_hours) else round((mins/60.0)::numeric,2) end;
  update public.os_attendance_sessions set actual_start_at=s.actual_start_at,actual_end_at=s.actual_end_at,
    duration_minutes=mins,billable_hours=hrs,duration_source=case when p_manual_hours is null then 'actual' else 'manual' end,updated_at=now()
  where id=p_session_id returning * into s;
  return to_jsonb(s);
end $$;

create or replace function public.os_deduct_session_hours(p_session_id uuid, p_hours numeric default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  s public.os_attendance_sessions;
  a record; sce record; h numeric(8,2); used_count int:=0; skipped jsonb:='[]'::jsonb;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  select * into s from public.os_attendance_sessions where id=p_session_id for update;
  if s.id is null then raise exception 'Session not found'; end if;
  if s.deduction_status='deducted' then raise exception 'This session was already deducted'; end if;

  h:=coalesce(p_hours,s.billable_hours);
  if h is null or h<=0 then
    if s.actual_start_at is not null and s.actual_end_at is not null then
      h:=round((extract(epoch from (s.actual_end_at-s.actual_start_at))/3600.0)::numeric,2);
    elsif s.start_time is not null and s.end_time is not null then
      h:=round((extract(epoch from ((current_date+s.end_time)-(current_date+s.start_time)))/3600.0)::numeric,2);
    end if;
  end if;
  if h is null or h<=0 then raise exception 'Billable hours must be greater than 0'; end if;

  for a in
    select sa.* from public.os_student_attendance sa
    where sa.session_id=p_session_id and sa.billable=true and sa.status in ('present','late')
  loop
    select sce2.* into sce
      from public.os_student_course_enrollments sce2
     where sce2.student_id=a.student_id
       and sce2.course_id=s.course_id
       and sce2.status in ('active','paused')
     order by case when sce2.status='active' then 0 else 1 end, sce2.created_at desc
     limit 1;
    if sce.id is null or sce.hour_pool_id is null then
      skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',a.student_id,'reason','no active hour pool'));
      continue;
    end if;
    insert into public.os_hour_ledger(pool_id,student_id,student_course_enrollment_id,course_id,session_id,entry_type,hours_delta,note,created_by)
    values(sce.hour_pool_id,a.student_id,sce.id,s.course_id,p_session_id,'usage',h,coalesce(p_note,'ตัดชั่วโมงจากคาบเรียน'),auth.uid())
    on conflict do nothing;
    if found then used_count:=used_count+1; end if;
  end loop;

  update public.os_attendance_sessions set status='completed',billable_hours=h,deduction_status='deducted',deducted_at=now(),deducted_by=auth.uid(),deduction_note=p_note,updated_at=now()
  where id=p_session_id returning * into s;

  insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
  select distinct sa.student_id,'อัปเดตชั่วโมงเรียน',
         coalesce(s.title,'คาบเรียน')||' ตัดเวลา '||trim(to_char(h,'FM999990.00'))||' ชม.',
         'hours','teaching_session',p_session_id::text
  from public.os_student_attendance sa
  where sa.session_id=p_session_id and sa.status in ('present','late') and sa.billable=true;

  return jsonb_build_object('success',true,'session_id',p_session_id,'hours',h,'deducted_students',used_count,'skipped',skipped);
end $$;

create or replace function public.os_restore_session_hours(p_session_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; n int:=0;
begin
  if not public.os_is_admin() then raise exception 'Admin permission required'; end if;
  for r in select * from public.os_hour_ledger where session_id=p_session_id and entry_type='usage' loop
    insert into public.os_hour_ledger(pool_id,student_id,student_course_enrollment_id,course_id,session_id,entry_type,hours_delta,note,created_by)
    values(r.pool_id,r.student_id,r.student_course_enrollment_id,r.course_id,p_session_id,'restore',-abs(r.hours_delta),coalesce(p_note,'คืนชั่วโมงจากการแก้ไขคาบ'),auth.uid())
    on conflict do nothing;
    if found then n:=n+1; end if;
  end loop;
  update public.os_attendance_sessions set deduction_status='restored',updated_at=now() where id=p_session_id;
  return jsonb_build_object('success',true,'restored_students',n);
end $$;

-- ============================================================
-- 6) Student Portal data tables
-- ============================================================
create table if not exists public.portal_learning_progress (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  topic_id uuid not null references public.os_learning_topics(id) on delete cascade,
  status text not null default 'opened' check(status in ('opened','in_progress','completed')),
  last_opened_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  unique(student_id,topic_id)
);

create table if not exists public.portal_notifications (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  title text not null,
  body text,
  notification_type text not null default 'info',
  source_type text,
  source_id text,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists portal_notifications_student_idx on public.portal_notifications(student_id,is_read,created_at desc);

create table if not exists public.portal_course_codes (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  course_id uuid references public.courses(id) on delete cascade,
  title text not null default 'Course code',
  code_value text not null,
  note text,
  created_at timestamptz not null default now()
);

create table if not exists public.portal_payment_plans (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  source_enrollment_id uuid references public.enrollments(id) on delete set null,
  course_id uuid references public.courses(id) on delete set null,
  title text not null,
  total_amount numeric(12,2) not null default 0,
  amount_paid numeric(12,2) not null default 0,
  balance_amount numeric(12,2) not null default 0,
  promptpay_id text default '1901001151577',
  status text not null default 'active' check(status in ('active','paid','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_payment_installments (
  id uuid primary key default gen_random_uuid(),
  payment_plan_id uuid not null references public.portal_payment_plans(id) on delete cascade,
  installment_no integer not null,
  due_date date,
  amount_due numeric(12,2) not null default 0,
  amount_paid numeric(12,2) not null default 0,
  status text not null default 'pending' check(status in ('pending','partial','paid','overdue','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(payment_plan_id,installment_no)
);

create table if not exists public.portal_payment_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  enrollment_id uuid references public.enrollments(id) on delete set null,
  payment_plan_id uuid references public.portal_payment_plans(id) on delete cascade,
  installment_id uuid references public.portal_payment_installments(id) on delete cascade,
  title text not null,
  amount numeric(12,2) not null default 0,
  promptpay_id text default '1901001151577',
  note text,
  status text not null default 'pending' check(status in ('pending','slip_submitted','paid','rejected','expired','cancelled')),
  expires_at timestamptz not null default (now()+interval '15 minutes'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.portal_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  payment_request_id uuid not null references public.portal_payment_requests(id) on delete cascade,
  student_id uuid not null references public.os_students(id) on delete cascade,
  storage_path text not null,
  original_filename text,
  amount numeric(12,2),
  note text,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ============================================================
-- 7) Integration registry + event bus for future subwebs
-- ============================================================
create table if not exists public.os_module_registry (
  module_key text primary key,
  title text not null,
  description text,
  path text not null,
  icon text,
  area text not null default 'operations',
  required_role text not null default 'staff' check(required_role in ('public','student','staff','admin')),
  is_active boolean not null default true,
  sort_order integer not null default 100,
  config jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.os_module_registry(module_key,title,description,path,icon,area,required_role,sort_order) values
('enrollment','สมัครเรียน','Enrollment & renewal','../','fa-solid fa-file-signature','admissions','public',10),
('student_portal','Student Portal','คอร์ส ชั่วโมง Attendance และการชำระ','../student/','fa-solid fa-graduation-cap','learning','student',20),
('manager','Manager','Catalog, Payment, Branding, Policy','../manager/','fa-solid fa-table-cells-large','admin','admin',30),
('tutor_os','Tutor OS','Teaching & Operations','./','fa-solid fa-chalkboard-user','operations','staff',40),
('tutor_apply','สมัครติวเตอร์','Tutor recruitment TH/EN','../tutor-apply/','fa-solid fa-user-plus','recruitment','public',50),
('reviews','รีวิว','Student reviews','../reviews/','fa-solid fa-comment-dots','content','public',60)
on conflict(module_key) do update set title=excluded.title,description=excluded.description,path=excluded.path,icon=excluded.icon,area=excluded.area,required_role=excluded.required_role,is_active=true,sort_order=excluded.sort_order,updated_at=now();

create table if not exists public.os_system_events (
  id bigint generated by default as identity primary key,
  event_key text not null,
  entity_type text not null,
  entity_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  processed_at timestamptz
);
create index if not exists os_system_events_key_idx on public.os_system_events(event_key,created_at desc);

create or replace function public.aw_emit_event(p_event_key text,p_entity_type text,p_entity_id text,p_payload jsonb default '{}'::jsonb)
returns bigint language plpgsql security definer set search_path=public as $$
declare v_id bigint;
begin
  insert into public.os_system_events(event_key,entity_type,entity_id,payload)
  values(p_event_key,p_entity_type,p_entity_id,coalesce(p_payload,'{}'::jsonb)) returning id into v_id;
  return v_id;
end $$;

create or replace function public.aw_event_trigger()
returns trigger language plpgsql security definer set search_path=public as $$
declare rec jsonb; rid text;
begin
  rec:=to_jsonb(coalesce(new,old)); rid:=coalesce(rec->>'id','');
  perform public.aw_emit_event(TG_TABLE_NAME||'.'||lower(TG_OP),TG_TABLE_NAME,rid,rec);
  return coalesce(new,old);
end $$;

do $$ declare t text; begin
  foreach t in array array['courses','course_offerings','enrollments','enrollment_items','payments','os_attendance_sessions','os_hour_ledger','portal_notifications'] loop
    execute format('drop trigger if exists %I on public.%I','trg_aw_event_'||t,t);
    execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.aw_event_trigger()','trg_aw_event_'||t,t);
  end loop;
end $$;

-- ============================================================
-- 8) Course-request approval creates a real Course + Offering
-- ============================================================
alter table public.os_course_requests add column if not exists created_course_id uuid references public.courses(id) on delete set null;
alter table public.os_course_requests add column if not exists created_offering_id uuid references public.course_offerings(id) on delete set null;

create or replace function public.os_approve_course_request(
  p_request_id uuid,
  p_tutor_id uuid,
  p_course_type text default 'content',
  p_open_enrollment boolean default true,
  p_capacity integer default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare r public.os_course_requests; c public.courses; o public.course_offerings;
begin
  if not public.os_is_admin() then raise exception 'Admin permission required'; end if;
  select * into r from public.os_course_requests where id=p_request_id for update;
  if r.id is null then raise exception 'Course request not found'; end if;
  if r.created_course_id is not null then
    return jsonb_build_object('success',true,'course_id',r.created_course_id,'offering_id',r.created_offering_id,'already_created',true);
  end if;
  insert into public.courses(tutor_id,name,course_type,short_detail,full_description,target_text,active,sort_order)
  values(p_tutor_id,r.title,case when p_course_type in ('content','exam') then p_course_type else 'content' end,r.description,r.description,array_to_string(r.target_levels,' / '),true,100)
  returning * into c;
  insert into public.course_offerings(course_id,status,enrollment_open,student_portal_open,capacity,default_hours,display_price,created_by)
  values(c.id,case when p_open_enrollment then 'open' else 'draft' end,p_open_enrollment,p_open_enrollment,p_capacity,r.proposed_hours,r.proposed_price,auth.uid())
  on conflict(course_id) do update set status=excluded.status,enrollment_open=excluded.enrollment_open,student_portal_open=excluded.student_portal_open,capacity=excluded.capacity,default_hours=excluded.default_hours,display_price=excluded.display_price,updated_at=now()
  returning * into o;
  update public.os_course_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),created_course_id=c.id,created_offering_id=o.id,updated_at=now() where id=r.id;
  return jsonb_build_object('success',true,'course_id',c.id,'offering_id',o.id);
end $$;

create or replace function public.os_set_course_enrollment_state(p_course_id uuid,p_open boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.course_offerings;
begin
  if not public.os_is_admin() then raise exception 'Admin permission required'; end if;
  if not exists(select 1 from public.courses where id=p_course_id and active=true) then raise exception 'Course is inactive in the master catalog'; end if;
  insert into public.course_offerings(course_id,status,enrollment_open,student_portal_open,updated_at)
  values(p_course_id,case when p_open then 'open' else 'closed' end,p_open,p_open,now())
  on conflict(course_id) do update set status=excluded.status,enrollment_open=excluded.enrollment_open,student_portal_open=excluded.student_portal_open,updated_at=now()
  returning * into o;
  return to_jsonb(o);
end $$;

-- ============================================================
-- 9) Enrollment -> Student -> Course -> Hour Pool synchronization
-- ============================================================
create or replace function public.os_sync_enrollment()
returns trigger language plpgsql security definer set search_path=public as $$
declare v_phone text; v_student_id uuid; v_status text;
begin
  v_phone:=regexp_replace(coalesce(new.phone,''),'[^0-9+]','','g');
  if v_phone='' then v_phone:='enrollment:'||new.id::text; end if;
  v_status:=case when new.status='confirmed' then 'active' when new.status in ('cancelled','rejected') then 'inactive' else 'pending' end;
  insert into public.os_students(source_enrollment_id,phone_key,display_name,nickname,phone,email,line_id,school,grade,faculty,province,parent_name,parent_phone,guardian_name,guardian_relationship,guardian_phone,status,course_summary,study_type,updated_at)
  values(new.id,v_phone,new.fullname,new.nickname,new.phone,new.email,new.line_id,new.school,new.grade,new.faculty,new.province,new.parent_name,new.parent_phone,new.parent_name,new.parent_relation,new.parent_phone,v_status,new.course_text,new.study_type,now())
  on conflict(phone_key) do update set
    source_enrollment_id=excluded.source_enrollment_id,display_name=excluded.display_name,nickname=excluded.nickname,phone=excluded.phone,
    email=coalesce(excluded.email,public.os_students.email),line_id=coalesce(excluded.line_id,public.os_students.line_id),school=coalesce(excluded.school,public.os_students.school),
    grade=coalesce(excluded.grade,public.os_students.grade),faculty=coalesce(excluded.faculty,public.os_students.faculty),province=coalesce(excluded.province,public.os_students.province),
    parent_name=coalesce(excluded.parent_name,public.os_students.parent_name),parent_phone=coalesce(excluded.parent_phone,public.os_students.parent_phone),
    guardian_name=coalesce(excluded.guardian_name,public.os_students.guardian_name),guardian_relationship=coalesce(excluded.guardian_relationship,public.os_students.guardian_relationship),
    guardian_phone=coalesce(excluded.guardian_phone,public.os_students.guardian_phone),status=excluded.status,course_summary=excluded.course_summary,study_type=excluded.study_type,updated_at=now()
  returning id into v_student_id;

  update public.enrollment_items set status=case when new.status='confirmed' then 'active' when new.status in ('cancelled','rejected') then 'cancelled' else 'pending' end,updated_at=now()
  where enrollment_id=new.id;
  update public.os_student_course_enrollments set status=case when new.status='confirmed' then 'active' when new.status in ('cancelled','rejected') then 'cancelled' else status end,updated_at=now()
  where source_enrollment_id=new.id;
  update public.os_hour_pools set status=case when new.status='confirmed' then 'active' when new.status in ('cancelled','rejected') then 'cancelled' else 'pending' end,updated_at=now()
  where source_enrollment_id=new.id;

  if tg_op='UPDATE' and old.status is distinct from new.status then
    insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
    values(v_student_id,'สถานะการสมัครอัปเดต','สถานะล่าสุด: '||new.status,'enrollment','enrollment',new.id::text);
  end if;
  return new;
end $$;

drop trigger if exists trg_os_sync_enrollment on public.enrollments;
create trigger trg_os_sync_enrollment after insert or update on public.enrollments for each row execute function public.os_sync_enrollment();

create or replace function public.aw_sync_enrollment_item_to_os()
returns trigger language plpgsql security definer set search_path=public as $$
declare e public.enrollments; s public.os_students; p public.os_hour_pools; v_pool_key text; v_status text;
begin
  select * into e from public.enrollments where id=new.enrollment_id;
  select * into s from public.os_students where phone_key=case when regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g') end limit 1;
  if s.id is null then return new; end if;
  v_pool_key:=case when new.share_mode='shared' then 'shared' else coalesce(new.course_id::text,new.id::text) end;
  v_status:=case when e.status='confirmed' then 'active' when e.status in ('cancelled','rejected') then 'cancelled' else 'pending' end;
  insert into public.os_hour_pools(student_id,source_enrollment_id,pool_key,package_code,total_hours,unlimited,status)
  values(s.id,e.id,v_pool_key,new.package_code,new.hours_allocated,new.hours_unlimited,v_status)
  on conflict(student_id,source_enrollment_id,pool_key) do update set package_code=excluded.package_code,total_hours=excluded.total_hours,unlimited=excluded.unlimited,status=excluded.status,updated_at=now()
  returning * into p;

  insert into public.os_student_course_enrollments(student_id,course_id,tutor_id,source_enrollment_id,enrollment_item_id,offering_id,hour_pool_id,course_label,tutor_label,status,enrolled_at,hours_total,hours_used,price,note)
  values(s.id,new.course_id,new.tutor_id,e.id,new.id,new.offering_id,p.id,new.course_name_snapshot,new.tutor_name_snapshot,v_status,e.created_at::date,coalesce(p.total_hours,0),p.used_hours,new.amount_allocated,'Synced from enrollment item')
  on conflict(enrollment_item_id) do update set course_id=excluded.course_id,tutor_id=excluded.tutor_id,offering_id=excluded.offering_id,hour_pool_id=excluded.hour_pool_id,course_label=excluded.course_label,tutor_label=excluded.tutor_label,status=excluded.status,hours_total=excluded.hours_total,price=excluded.price,updated_at=now();
  return new;
end $$;

drop trigger if exists trg_aw_enrollment_item_sync on public.enrollment_items;
create trigger trg_aw_enrollment_item_sync after insert or update on public.enrollment_items for each row execute function public.aw_sync_enrollment_item_to_os();

-- Backfill V14 single-course links with a pool so time deduction can work immediately.
insert into public.os_hour_pools(student_id,source_enrollment_id,pool_key,total_hours,used_hours,unlimited,status)
select sce.student_id,sce.source_enrollment_id,coalesce(sce.course_id::text,'legacy'),nullif(sce.hours_total,0),coalesce(sce.hours_used,0),false,
       case when sce.status in ('active','paused','completed','cancelled') then sce.status else 'active' end
from public.os_student_course_enrollments sce
where sce.hour_pool_id is null and sce.source_enrollment_id is not null
on conflict(student_id,source_enrollment_id,pool_key) do nothing;

update public.os_student_course_enrollments sce set hour_pool_id=p.id
from public.os_hour_pools p
where sce.hour_pool_id is null and p.student_id=sce.student_id and p.source_enrollment_id=sce.source_enrollment_id
  and p.pool_key=coalesce(sce.course_id::text,'legacy');

-- ============================================================
-- 10) Payment status -> Portal payment + Finance
-- ============================================================
create or replace function public.aw_sync_core_payment_to_portal()
returns trigger language plpgsql security definer set search_path=public as $$
declare e public.enrollments; s public.os_students; r public.portal_payment_requests;
begin
  select * into e from public.enrollments where id=new.enrollment_id;
  select * into s from public.os_students where phone_key=case when regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g') end limit 1;
  if s.id is null then return new; end if;
  select * into r from public.portal_payment_requests where enrollment_id=e.id order by created_at desc limit 1;
  if r.id is null then
    insert into public.portal_payment_requests(student_id,enrollment_id,title,amount,note,status,expires_at)
    values(s.id,e.id,'ค่าคอร์ส '||coalesce(e.course_text,''),coalesce(new.verified_amount,new.amount_submitted,e.amount_quoted,0),'รายการจากระบบสมัครเรียน',
      case when new.status='paid' then 'paid' when new.status='rejected' then 'rejected' else case when new.slip_path is not null then 'slip_submitted' else 'pending' end end,
      now()+interval '15 minutes');
  else
    update public.portal_payment_requests set amount=coalesce(new.verified_amount,new.amount_submitted,e.amount_quoted,amount),
      status=case when new.status='paid' then 'paid' when new.status='rejected' then 'rejected' else case when new.slip_path is not null then 'slip_submitted' else status end end,updated_at=now()
    where id=r.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_aw_core_payment_portal on public.payments;
create trigger trg_aw_core_payment_portal after insert or update on public.payments for each row execute function public.aw_sync_core_payment_to_portal();

-- ============================================================
-- 11) Student Portal secure functions
-- ============================================================
create or replace function public.aw_my_student_id()
returns uuid language sql stable security definer set search_path=public as $$
  select a.student_id from public.os_student_accounts a where a.user_id=auth.uid() and a.is_active=true limit 1;
$$;

create or replace function public.lookup_student_by_phone(p_phone text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); s public.os_students; claimed boolean;
begin
  if length(p)<9 then return jsonb_build_object('found',false,'message','กรุณากรอกเบอร์ให้ครบ'); end if;
  select * into s from public.os_students where regexp_replace(coalesce(phone,''),'\D','','g')=p order by updated_at desc limit 1;
  if s.id is null then return jsonb_build_object('found',false,'message','ไม่พบข้อมูลนักเรียนจากเบอร์นี้'); end if;
  select exists(select 1 from public.os_student_accounts a where a.student_id=s.id and a.is_active) into claimed;
  return jsonb_build_object('found',true,'student_id',s.id,'display_name',s.display_name,'name',s.display_name,'student_code',s.student_code,'school',s.school,'education_level',s.grade,'account_exists',claimed);
end $$;

create or replace function public.claim_student_account_by_phone(p_phone text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare p text:=regexp_replace(coalesce(p_phone,''),'\D','','g'); s public.os_students; auth_email text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into s from public.os_students where regexp_replace(coalesce(phone,''),'\D','','g')=p order by updated_at desc limit 1;
  if s.id is null then raise exception 'ไม่พบข้อมูลนักเรียน'; end if;
  auth_email:=lower(coalesce(auth.jwt()->>'email',''));
  if s.email is not null and btrim(s.email)<>'' and auth_email<>lower(btrim(s.email)) then raise exception 'อีเมลบัญชีไม่ตรงกับข้อมูลสมัครเรียน'; end if;
  if exists(select 1 from public.os_student_accounts where student_id=s.id and user_id<>auth.uid()) then raise exception 'ข้อมูลนักเรียนนี้เชื่อมกับบัญชีอื่นแล้ว'; end if;
  insert into public.os_student_accounts(user_id,student_id,is_active,updated_at) values(auth.uid(),s.id,true,now())
  on conflict(user_id) do update set student_id=excluded.student_id,is_active=true,updated_at=now();
  return jsonb_build_object('success',true,'student_id',s.id,'student_code',s.student_code,'display_name',s.display_name);
end $$;

create or replace function public.portal_set_pin(p_user_id uuid,p_pin text)
returns void language plpgsql security definer set search_path=public as $$
begin
  if current_setting('request.jwt.claim.role',true) is distinct from 'service_role' and auth.role() is distinct from 'service_role' then raise exception 'service_role only'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN must be 4 digits'; end if;
  update public.os_student_accounts set pin_hash=crypt(p_pin,gen_salt('bf')),updated_at=now() where user_id=p_user_id;
end $$;

create or replace function public.portal_verify_pin(p_phone text,p_email text,p_pin text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare s public.os_students; a public.os_student_accounts; p text:=regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  select * into s from public.os_students where regexp_replace(coalesce(phone,''),'\D','','g')=p and lower(coalesce(email,''))=lower(coalesce(p_email,'')) order by updated_at desc limit 1;
  if s.id is null then return jsonb_build_object('ok',false); end if;
  select * into a from public.os_student_accounts where student_id=s.id and is_active=true limit 1;
  if a.user_id is null or a.pin_hash is null or crypt(p_pin,a.pin_hash)<>a.pin_hash then return jsonb_build_object('ok',false); end if;
  return jsonb_build_object('ok',true,'user_id',a.user_id,'student_id',s.id);
end $$;

create or replace function public.student_v8_open_lesson(p_topic_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); r public.portal_learning_progress;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  insert into public.portal_learning_progress(student_id,topic_id,status,last_opened_at,updated_at)
  values(sid,p_topic_id,'in_progress',now(),now())
  on conflict(student_id,topic_id) do update set last_opened_at=now(),status=case when public.portal_learning_progress.status='completed' then 'completed' else 'in_progress' end,updated_at=now()
  returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.student_v8_complete_lesson(p_topic_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); r public.portal_learning_progress;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  insert into public.portal_learning_progress(student_id,topic_id,status,last_opened_at,completed_at,updated_at)
  values(sid,p_topic_id,'completed',now(),now(),now())
  on conflict(student_id,topic_id) do update set status='completed',last_opened_at=now(),completed_at=now(),updated_at=now()
  returning * into r;
  return to_jsonb(r);
end $$;

create or replace function public.student_v8_mark_notification_read(p_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
  update public.portal_notifications set is_read=true where id=p_id and student_id=public.aw_my_student_id();
end $$;

create or replace function public.update_my_student_profile(p_profile jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); s public.os_students;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  update public.os_students set
    first_name=coalesce(nullif(p_profile->>'first_name',''),first_name),last_name=coalesce(nullif(p_profile->>'last_name',''),last_name),
    phone=coalesce(nullif(p_profile->>'phone',''),phone),birth_date=coalesce(nullif(p_profile->>'birth_date','')::date,birth_date),
    address=coalesce(p_profile->>'address',address),guardian_name=coalesce(p_profile->>'guardian_name',guardian_name),
    guardian_relationship=coalesce(p_profile->>'guardian_relationship',guardian_relationship),guardian_phone=coalesce(p_profile->>'guardian_phone',guardian_phone),
    guardian_line=coalesce(p_profile->>'guardian_line',guardian_line),updated_at=now()
  where id=sid returning * into s;
  return to_jsonb(s);
end $$;

create or replace function public.student_v11_bootstrap()
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); result jsonb;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  select jsonb_build_object(
    'student',(select to_jsonb(s) from public.os_students s where s.id=sid),
    'courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'course_type',c.course_type,'cover_url',c.image_url,'description',c.full_description,'public_description',c.short_detail,'renewal_alert_hours',3)) from public.courses c where c.id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid and sce.course_id is not null)),'[]'::jsonb),
    'open_courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'course_type',c.course_type,'cover_url',c.image_url,'description',c.full_description,'public_description',coalesce(o.public_note,c.short_detail),'hours',coalesce(o.default_hours,0),'price',coalesce(o.display_price,0))) from public.courses c join public.course_offerings o on o.course_id=c.id where c.active=true and o.status='open' and o.student_portal_open=true and o.enrollment_open=true and (o.starts_on is null or o.starts_on<=current_date) and (o.ends_on is null or o.ends_on>=current_date)),'[]'::jsonb),
    'enrollments',coalesce((select jsonb_agg(jsonb_build_object('id',sce.id,'course_id',sce.course_id,'status',sce.status,'hours_total',coalesce(p.total_hours,sce.hours_total),'hours_used',coalesce(p.used_hours,sce.hours_used),'hours_unlimited',coalesce(p.unlimited,false),'hour_pool_id',sce.hour_pool_id)) from public.os_student_course_enrollments sce left join public.os_hour_pools p on p.id=sce.hour_pool_id where sce.student_id=sid),'[]'::jsonb),
    'topics',coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order,t.created_at) from public.os_learning_topics t where t.is_active=true and t.course_id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid and sce.status in ('active','paused','completed')) and t.publish_at<=now() and (t.available_until is null or t.available_until>now())),'[]'::jsonb),
    'assets',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'topic_id',a.topic_id,'title',a.title,'asset_type',case a.asset_type when 'video' then 'external_video' when 'link' then 'external_link' when 'file' then 'file' else a.asset_type end,'url',a.url,'storage_path',a.storage_path,'description','')) from public.os_learning_assets a where a.is_active=true and a.topic_id in (select t.id from public.os_learning_topics t where t.course_id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid))),'[]'::jsonb),
    'progress',coalesce((select jsonb_agg(to_jsonb(p)) from public.portal_learning_progress p where p.student_id=sid),'[]'::jsonb),
    'notifications',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.portal_notifications n where n.student_id=sid),'[]'::jsonb),
    'attendance',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.os_student_attendance a where a.student_id=sid),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(to_jsonb(ses) order by ses.session_date desc) from public.os_attendance_sessions ses where ses.id in (select a.session_id from public.os_student_attendance a where a.student_id=sid)),'[]'::jsonb),
    'payment_requests',coalesce((select jsonb_agg(to_jsonb(pr) order by pr.created_at desc) from public.portal_payment_requests pr where pr.student_id=sid),'[]'::jsonb),
    'payment_submissions',coalesce((select jsonb_agg(to_jsonb(ps) order by ps.created_at desc) from public.portal_payment_submissions ps where ps.student_id=sid),'[]'::jsonb),
    'codes',coalesce((select jsonb_agg(to_jsonb(cc) order by cc.created_at desc) from public.portal_course_codes cc where cc.student_id=sid),'[]'::jsonb),
    'library_new_books',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'title',l.title,'url',l.url)) from public.os_library_items l where l.item_type='book' and l.is_active=true and l.audience in ('student','both') and l.created_at>now()-interval '30 days'),'[]'::jsonb),
    'hour_ledger',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from public.os_hour_ledger h where h.student_id=sid),'[]'::jsonb)
  ) into result;
  return result;
end $$;

create or replace function public.student_v8_refresh_payment(p_payment_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); r public.portal_payment_requests;
begin
  update public.portal_payment_requests set status='pending',expires_at=now()+interval '15 minutes',updated_at=now()
  where id=p_payment_request_id and student_id=sid returning * into r;
  if r.id is null then raise exception 'Payment request not found'; end if;
  return to_jsonb(r);
end $$;

create or replace function public.student_v8_submit_slip(p_payment_request_id uuid,p_storage_path text,p_original_filename text,p_amount numeric,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); r public.portal_payment_submissions;
begin
  if not exists(select 1 from public.portal_payment_requests where id=p_payment_request_id and student_id=sid) then raise exception 'Payment request not found'; end if;
  insert into public.portal_payment_submissions(payment_request_id,student_id,storage_path,original_filename,amount,note)
  values(p_payment_request_id,sid,p_storage_path,p_original_filename,p_amount,p_note) returning * into r;
  update public.portal_payment_requests set status='slip_submitted',updated_at=now() where id=p_payment_request_id;
  insert into public.os_payment_slips(student_id,storage_path,original_filename,payment_amount,payment_date,note,uploaded_by)
  values(sid,p_storage_path,p_original_filename,p_amount,current_date,p_note,auth.uid());
  return to_jsonb(r);
end $$;

create or replace function public.student_v9_payment_bootstrap()
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id();
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  return jsonb_build_object(
    'plans',coalesce((select jsonb_agg(to_jsonb(p)) from public.portal_payment_plans p where p.student_id=sid),'[]'::jsonb),
    'installments',coalesce((select jsonb_agg(to_jsonb(i)) from public.portal_payment_installments i where i.payment_plan_id in (select id from public.portal_payment_plans where student_id=sid)),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(r)) from public.portal_payment_requests r where r.student_id=sid),'[]'::jsonb),
    'submissions',coalesce((select jsonb_agg(to_jsonb(s)) from public.portal_payment_submissions s where s.student_id=sid),'[]'::jsonb),
    'teaching_notes',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'topic',l.topic,'lesson_date',l.lesson_date,'lesson_summary',coalesce(l.outcome,l.notes),'homework','')) from public.os_teaching_logs l where l.student_id=sid order by l.lesson_date desc),'[]'::jsonb)
  );
end $$;

create or replace function public.student_v9_create_installment_qr(p_installment_id uuid,p_amount numeric)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); i public.portal_payment_installments; p public.portal_payment_plans; r public.portal_payment_requests; bal numeric;
begin
  select i2.* into i from public.portal_payment_installments i2 join public.portal_payment_plans p2 on p2.id=i2.payment_plan_id where i2.id=p_installment_id and p2.student_id=sid;
  if i.id is null then raise exception 'Installment not found'; end if;
  select * into p from public.portal_payment_plans where id=i.payment_plan_id;
  bal:=greatest(0,i.amount_due-i.amount_paid);
  if p_amount<=0 or p_amount>bal then raise exception 'Amount exceeds installment balance'; end if;
  insert into public.portal_payment_requests(student_id,payment_plan_id,installment_id,title,amount,promptpay_id,status,expires_at)
  values(sid,p.id,i.id,p.title||' · งวด '||i.installment_no,p_amount,p.promptpay_id,'pending',now()+interval '15 minutes') returning * into r;
  return to_jsonb(r);
end $$;

-- Student catalog action becomes a connected request, not an isolated enrollment.
create table if not exists public.student_course_change_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  request_type text not null check(request_type in ('new','renewal','change')),
  note text,
  status text not null default 'pending' check(status in ('pending','contacted','approved','rejected','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.student_v8_request_enrollment(p_course_id uuid,p_request_type text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); r public.student_course_change_requests;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  if not exists(select 1 from public.course_offerings o join public.courses c on c.id=o.course_id where c.id=p_course_id and c.active and o.enrollment_open and o.status='open') then raise exception 'คอร์สนี้ยังไม่เปิดรับสมัคร'; end if;
  insert into public.student_course_change_requests(student_id,course_id,request_type,note)
  values(sid,p_course_id,case when p_request_type in ('new','renewal','change') then p_request_type else 'new' end,p_note) returning * into r;
  insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
  values(sid,'รับคำขอคอร์สแล้ว','ทีมงานได้รับคำขอและจะดำเนินการต่อในระบบสมัครเรียน','course_request','student_course_change_request',r.id::text);
  return to_jsonb(r);
end $$;

-- ============================================================
-- 12) RLS / Grants
-- ============================================================
alter table public.course_offerings enable row level security;
drop policy if exists "Public read open course offerings" on public.course_offerings;
drop policy if exists "Authenticated read course offerings" on public.course_offerings;
create policy "Public read open course offerings" on public.course_offerings for select to anon using(enrollment_open=true and status='open' and (starts_on is null or starts_on<=current_date) and (ends_on is null or ends_on>=current_date));
create policy "Authenticated read course offerings" on public.course_offerings for select to authenticated using((enrollment_open=true and status='open') or public.is_manager() or public.os_is_staff());
drop policy if exists "Manager write course offerings" on public.course_offerings;
create policy "Manager write course offerings" on public.course_offerings for all to authenticated using(public.is_manager() or public.os_is_admin()) with check(public.is_manager() or public.os_is_admin());

alter table public.enrollment_items enable row level security;
drop policy if exists "Manager read enrollment items" on public.enrollment_items;
create policy "Manager read enrollment items" on public.enrollment_items for select to authenticated using(public.is_manager() or public.os_is_admin());
drop policy if exists "Manager write enrollment items" on public.enrollment_items;
create policy "Manager write enrollment items" on public.enrollment_items for all to authenticated using(public.is_manager() or public.os_is_admin()) with check(public.is_manager() or public.os_is_admin());

-- Operational tables: staff can work; sensitive account table is function-only.
do $$ declare t text; begin
  foreach t in array array['os_hour_pools','os_hour_ledger','student_course_change_requests'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists %I on public.%I','V15 staff access '||t,t);
    execute format('create policy %I on public.%I for all to authenticated using(public.os_is_staff()) with check(public.os_is_staff())','V15 staff access '||t,t);
  end loop;
end $$;

alter table public.os_student_accounts enable row level security;
drop policy if exists "Student own account link" on public.os_student_accounts;
create policy "Student own account link" on public.os_student_accounts for select to authenticated using(user_id=auth.uid());

-- Student Realtime/read policies for the rows that power the live portal.
drop policy if exists "Student read own hour pools" on public.os_hour_pools;
create policy "Student read own hour pools" on public.os_hour_pools for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own hour ledger" on public.os_hour_ledger;
create policy "Student read own hour ledger" on public.os_hour_ledger for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own course links" on public.os_student_course_enrollments;
create policy "Student read own course links" on public.os_student_course_enrollments for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own attendance" on public.os_student_attendance;
create policy "Student read own attendance" on public.os_student_attendance for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own sessions" on public.os_attendance_sessions;
create policy "Student read own sessions" on public.os_attendance_sessions for select to authenticated using(exists(select 1 from public.os_student_attendance a where a.session_id=os_attendance_sessions.id and a.student_id=public.aw_my_student_id()));

-- Portal tables are exposed to students through RPCs and own-row read policies for Realtime.
do $$ declare t text; begin
  foreach t in array array['portal_learning_progress','portal_notifications','portal_course_codes','portal_payment_plans','portal_payment_installments','portal_payment_requests','portal_payment_submissions'] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('drop policy if exists %I on public.%I','V15 staff portal '||t,t);
    execute format('create policy %I on public.%I for all to authenticated using(public.os_is_staff()) with check(public.os_is_staff())','V15 staff portal '||t,t);
  end loop;
end $$;

drop policy if exists "Student read own portal notifications" on public.portal_notifications;
create policy "Student read own portal notifications" on public.portal_notifications for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own learning progress" on public.portal_learning_progress;
create policy "Student read own learning progress" on public.portal_learning_progress for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own payment requests" on public.portal_payment_requests;
create policy "Student read own payment requests" on public.portal_payment_requests for select to authenticated using(student_id=public.aw_my_student_id());
drop policy if exists "Student read own payment submissions" on public.portal_payment_submissions;
create policy "Student read own payment submissions" on public.portal_payment_submissions for select to authenticated using(student_id=public.aw_my_student_id());

alter table public.os_module_registry enable row level security;
drop policy if exists "Public module registry" on public.os_module_registry;
create policy "Public module registry" on public.os_module_registry for select to anon,authenticated using(is_active=true);
drop policy if exists "Admin module registry" on public.os_module_registry;
create policy "Admin module registry" on public.os_module_registry for all to authenticated using(public.os_is_admin()) with check(public.os_is_admin());

alter table public.os_system_events enable row level security;
drop policy if exists "Staff read system events" on public.os_system_events;
create policy "Staff read system events" on public.os_system_events for select to authenticated using(public.os_is_staff());

-- Storage used by Student Portal slips.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('portal-slips','portal-slips',false,10485760,array['image/jpeg','image/png','image/webp','application/pdf'])
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists "Student upload portal slips" on storage.objects;
create policy "Student upload portal slips" on storage.objects for insert to authenticated
with check(bucket_id='portal-slips' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists "Student read own portal slips" on storage.objects;
create policy "Student read own portal slips" on storage.objects for select to authenticated
using(bucket_id='portal-slips' and ((storage.foldername(name))[1]=auth.uid()::text or public.os_is_admin()));
drop policy if exists "Admin portal slips" on storage.objects;
create policy "Admin portal slips" on storage.objects for all to authenticated
using(bucket_id='portal-slips' and public.os_is_admin()) with check(bucket_id='portal-slips' and public.os_is_admin());

-- Student may request signed URLs only for paths returned by the portal RPC.
-- The bucket stays private; no public URL is exposed.
drop policy if exists "Student read tutor os learning assets" on storage.objects;
create policy "Student read tutor os learning assets" on storage.objects for select to authenticated
using(bucket_id='tutor-os-assets' and public.aw_my_student_id() is not null);

-- Function grants
revoke all on function public.lookup_student_by_phone(text) from public;
grant execute on function public.lookup_student_by_phone(text) to anon,authenticated;
grant execute on function public.claim_student_account_by_phone(text) to authenticated;
grant execute on function public.aw_my_student_id() to authenticated;
grant execute on function public.student_v11_bootstrap() to authenticated;
grant execute on function public.student_v8_open_lesson(uuid) to authenticated;
grant execute on function public.student_v8_complete_lesson(uuid) to authenticated;
grant execute on function public.student_v8_mark_notification_read(uuid) to authenticated;
grant execute on function public.update_my_student_profile(jsonb) to authenticated;
grant execute on function public.student_v8_refresh_payment(uuid) to authenticated;
grant execute on function public.student_v8_submit_slip(uuid,text,text,numeric,text) to authenticated;
grant execute on function public.student_v9_payment_bootstrap() to authenticated;
grant execute on function public.student_v9_create_installment_qr(uuid,numeric) to authenticated;
grant execute on function public.student_v8_request_enrollment(uuid,text,text) to authenticated;
grant execute on function public.os_start_session(uuid) to authenticated;
grant execute on function public.os_stop_session(uuid,numeric) to authenticated;
grant execute on function public.os_deduct_session_hours(uuid,numeric,text) to authenticated;
grant execute on function public.os_restore_session_hours(uuid,text) to authenticated;
grant execute on function public.os_approve_course_request(uuid,uuid,text,boolean,integer) to authenticated;
grant execute on function public.os_set_course_enrollment_state(uuid,boolean) to authenticated;
grant execute on function public.portal_set_pin(uuid,text) to service_role;
grant execute on function public.portal_verify_pin(text,text,text) to service_role;

grant select on public.course_offerings,public.os_module_registry to anon,authenticated;
grant select,insert,update,delete on public.enrollment_items,public.os_hour_pools,public.os_hour_ledger,public.student_course_change_requests to authenticated;
grant select,insert,update,delete on public.portal_learning_progress,public.portal_notifications,public.portal_course_codes,public.portal_payment_plans,public.portal_payment_installments,public.portal_payment_requests,public.portal_payment_submissions to authenticated;
grant select on public.os_system_events to authenticated;


-- ============================================================
-- 15) Atomic Student Portal payment review
--     One approval updates slip, request, installment/plan,
--     finance ledger and student notification in one transaction.
-- ============================================================
alter table public.os_finance_entries
  add column if not exists source_portal_submission_id uuid unique references public.portal_payment_submissions(id) on delete set null;

create or replace function public.os_review_portal_payment_submission(
  p_submission_id uuid,
  p_status text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  v_sub public.portal_payment_submissions;
  v_req public.portal_payment_requests;
  v_inst public.portal_payment_installments;
  v_plan public.portal_payment_plans;
  v_paid numeric(12,2);
  v_plan_paid numeric(12,2);
  v_plan_balance numeric(12,2);
begin
  if not public.os_is_staff() then raise exception 'Tutor OS staff only'; end if;
  if p_status not in ('approved','rejected') then raise exception 'Invalid review status'; end if;

  select * into v_sub from public.portal_payment_submissions where id=p_submission_id for update;
  if v_sub.id is null then raise exception 'Payment submission not found'; end if;
  select * into v_req from public.portal_payment_requests where id=v_sub.payment_request_id for update;
  if v_req.id is null then raise exception 'Payment request not found'; end if;

  -- Idempotent: repeating the same review returns current state without charging twice.
  if v_sub.status <> 'pending' then
    return jsonb_build_object('ok',true,'already_reviewed',true,'submission_status',v_sub.status,'request_status',v_req.status);
  end if;

  update public.portal_payment_submissions
  set status=p_status,reviewed_by=auth.uid(),reviewed_at=now(),note=coalesce(p_note,note)
  where id=p_submission_id
  returning * into v_sub;

  if p_status='rejected' then
    update public.portal_payment_requests set status='rejected',updated_at=now() where id=v_req.id returning * into v_req;
    insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
    values(v_sub.student_id,'สลิปต้องแก้ไข','รายการชำระเงินยังไม่ผ่านการตรวจสอบ กรุณาตรวจสอบและส่งใหม่','payment','portal_payment_submission',v_sub.id::text);
    return jsonb_build_object('ok',true,'submission_status','rejected','request_status','rejected');
  end if;

  v_paid:=greatest(0,coalesce(v_sub.amount,v_req.amount,0));
  update public.portal_payment_requests set status='paid',updated_at=now() where id=v_req.id returning * into v_req;

  if v_req.installment_id is not null then
    select * into v_inst from public.portal_payment_installments where id=v_req.installment_id for update;
    if v_inst.id is not null then
      update public.portal_payment_installments
      set amount_paid=least(amount_due,coalesce(amount_paid,0)+v_paid),
          status=case when coalesce(amount_paid,0)+v_paid>=amount_due then 'paid' else 'partial' end,
          updated_at=now()
      where id=v_inst.id
      returning * into v_inst;
    end if;
  end if;

  if v_req.payment_plan_id is not null then
    select * into v_plan from public.portal_payment_plans where id=v_req.payment_plan_id for update;
    if v_plan.id is not null then
      select coalesce(sum(amount_paid),0) into v_plan_paid from public.portal_payment_installments where payment_plan_id=v_plan.id;
      -- A plan may also receive a direct request without an installment.
      if v_req.installment_id is null then v_plan_paid:=least(v_plan.total_amount,coalesce(v_plan.amount_paid,0)+v_paid); end if;
      v_plan_balance:=greatest(0,v_plan.total_amount-v_plan_paid);
      update public.portal_payment_plans
      set amount_paid=v_plan_paid,balance_amount=v_plan_balance,
          status=case when v_plan_balance<=0 then 'paid' else 'active' end,
          updated_at=now()
      where id=v_plan.id returning * into v_plan;
    end if;
  end if;

  insert into public.os_finance_entries(
    source_portal_submission_id,student_id,course_id,transaction_date,description,amount,entry_type,note,created_by
  ) values(
    v_sub.id,v_sub.student_id,v_plan.course_id,current_date,coalesce(v_req.title,'Student Portal payment'),v_paid,'income',coalesce(p_note,'Approved from Student Portal'),auth.uid()
  ) on conflict(source_portal_submission_id) do nothing;

  insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
  values(v_sub.student_id,'ยืนยันการชำระเงินแล้ว',coalesce(v_req.title,'รายการชำระเงิน')||' · ยอด '||to_char(v_paid,'FM999G999G990D00')||' บาท','payment','portal_payment_submission',v_sub.id::text);

  return jsonb_build_object(
    'ok',true,'submission_status','approved','request_status','paid','amount',v_paid,
    'installment',case when v_inst.id is null then null else to_jsonb(v_inst) end,
    'plan',case when v_plan.id is null then null else to_jsonb(v_plan) end
  );
end $$;

revoke all on function public.os_review_portal_payment_submission(uuid,text,text) from public,anon;
grant execute on function public.os_review_portal_payment_submission(uuid,text,text) to authenticated;


-- ============================================================
-- 16) Shared Library: Tutor OS manages, Student Library consumes
-- ============================================================
alter table public.os_library_items add column if not exists audience text not null default 'staff';
do $$ begin
  begin alter table public.os_library_items add constraint os_library_items_audience_check check(audience in ('staff','student','both')); exception when duplicate_object then null; end;
end $$;

insert into public.os_module_registry(module_key,title,description,path,icon,area,required_role,sort_order) values
('library','AreWarin Library','คลังหนังสือ ชีท วิดีโอ และลิงก์ที่ Tutor OS เผยแพร่ให้นักเรียน','../library/','fa-solid fa-book-open','learning','student',25)
on conflict(module_key) do update set title=excluded.title,description=excluded.description,path=excluded.path,icon=excluded.icon,area=excluded.area,required_role=excluded.required_role,is_active=true,sort_order=excluded.sort_order,updated_at=now();

create or replace function public.student_library_bootstrap()
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id();
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  return jsonb_build_object(
    'student',(select jsonb_build_object('id',s.id,'student_code',s.student_code,'display_name',s.display_name) from public.os_students s where s.id=sid),
    'items',coalesce((select jsonb_agg(to_jsonb(l) order by l.sort_order,l.created_at desc) from public.os_library_items l where l.is_active=true and l.audience in ('student','both')),'[]'::jsonb)
  );
end $$;
revoke all on function public.student_library_bootstrap() from public,anon;
grant execute on function public.student_library_bootstrap() to authenticated;


-- ============================================================
-- 17) Unified system diagnostics
-- ============================================================
create or replace function public.os_unified_health()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.os_is_staff() then raise exception 'Tutor OS staff only'; end if;
  return jsonb_build_object(
    'version','V15',
    'checked_at',now(),
    'modules',(select count(*) from public.os_module_registry where is_active=true),
    'open_courses',(select count(*) from public.course_offerings where status='open' and enrollment_open=true),
    'courses_without_offering',(select count(*) from public.courses c where c.active=true and not exists(select 1 from public.course_offerings o where o.course_id=c.id)),
    'enrollment_items_missing_course',(select count(*) from public.enrollment_items where course_id is null and status<>'cancelled'),
    'active_student_courses_without_pool',(select count(*) from public.os_student_course_enrollments where status in ('active','paused') and hour_pool_id is null),
    'pending_portal_slips',(select count(*) from public.portal_payment_submissions where status='pending'),
    'undeducted_completed_sessions',(select count(*) from public.os_attendance_sessions where status='completed' and coalesce(deduction_status,'pending')<>'deducted'),
    'events_24h',(select count(*) from public.os_system_events where created_at>now()-interval '24 hours')
  );
end $$;
revoke all on function public.os_unified_health() from public,anon;
grant execute on function public.os_unified_health() to authenticated;

insert into public.os_settings(key,value,description) values
('UNIFIED_SYSTEM_VERSION','"V15"'::jsonb,'Shared integration schema version'),
('UNIFIED_SINGLE_SOURCE','true'::jsonb,'Courses, students, enrollments and hours use canonical shared records')
on conflict(key) do update set value=excluded.value,description=excluded.description,updated_at=now();

-- Realtime tables. Ignore duplicate-publication errors.
do $$ begin
  begin alter publication supabase_realtime add table public.os_hour_pools; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.os_hour_ledger; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.os_student_course_enrollments; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.os_student_attendance; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.os_attendance_sessions; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.portal_notifications; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.course_offerings; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.os_system_events; exception when duplicate_object then null; end;
end $$;

-- Useful defaults
insert into public.os_settings(key,value,description) values
('integration_version','"V15"'::jsonb,'Unified integration contract version'),
('student_portal_path','"../student/"'::jsonb,'Student Portal subweb'),
('hour_deduction_rule','"present_and_late"'::jsonb,'Attendance statuses deducted automatically')
on conflict(key) do update set value=excluded.value,description=excluded.description,updated_at=now();

commit;

-- Diagnostics
select
  'V15 READY' as status,
  (select count(*) from public.course_offerings) as course_offerings,
  (select count(*) from public.os_students) as students,
  (select count(*) from public.os_hour_pools) as hour_pools,
  (select count(*) from public.os_module_registry where is_active) as modules;
-- ============================================================
-- AreWarin Biology · V15.1 Group Lockers Upgrade
-- Existing project upgrade: V15 -> V15.1
-- Adds class/group lockers, roster-first attendance, per-student hour
-- deduction, quick hour check by Student Code + PIN and realtime links.
-- Safe to rerun where practical.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1) Group / Locker master data
-- ------------------------------------------------------------
create table if not exists public.os_student_group_sequences (
  year_no integer primary key,
  last_no integer not null default 0
);

create or replace function public.aw_next_student_group_code()
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  y integer:=extract(year from now())::integer;
  n integer;
begin
  insert into public.os_student_group_sequences(year_no,last_no)
  values(y,1)
  on conflict(year_no) do update
    set last_no=public.os_student_group_sequences.last_no+1
  returning last_no into n;
  return 'AWG-'||y::text||'-'||lpad(n::text,4,'0');
end $$;

create table if not exists public.os_student_groups (
  id uuid primary key default gen_random_uuid(),
  group_code text not null unique default public.aw_next_student_group_code(),
  name text not null,
  course_id uuid not null references public.courses(id) on delete restrict,
  tutor_id uuid references public.tutors(id) on delete set null,
  default_billable_hours numeric(8,2) not null default 1.50,
  mode text not null default 'online' check(mode in ('online','onsite','hybrid')),
  location text,
  color_key text not null default 'sky',
  note text,
  status text not null default 'active' check(status in ('active','paused','archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists os_student_groups_course_idx on public.os_student_groups(course_id,status);
create index if not exists os_student_groups_tutor_idx on public.os_student_groups(tutor_id,status);

create table if not exists public.os_student_group_members (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.os_student_groups(id) on delete cascade,
  student_id uuid not null references public.os_students(id) on delete cascade,
  student_course_enrollment_id uuid references public.os_student_course_enrollments(id) on delete set null,
  seat_label text,
  default_deduct_hours numeric(8,2),
  note text,
  is_active boolean not null default true,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(group_id,student_id)
);
create index if not exists os_student_group_members_student_idx on public.os_student_group_members(student_id,is_active);
create index if not exists os_student_group_members_group_idx on public.os_student_group_members(group_id,is_active);

-- ------------------------------------------------------------
-- 2) Attendance sessions understand Group Locker + pending roster
-- ------------------------------------------------------------
alter table public.os_attendance_sessions
  add column if not exists group_id uuid references public.os_student_groups(id) on delete set null;
create index if not exists os_attendance_sessions_group_idx on public.os_attendance_sessions(group_id,session_date desc);

alter table public.os_student_attendance
  add column if not exists deducted_hours numeric(8,2) not null default 0;

alter table public.os_student_attendance
  drop constraint if exists os_student_attendance_status_check;
alter table public.os_student_attendance
  add constraint os_student_attendance_status_check
  check(status in ('pending','present','late','absent','leave'));

-- ------------------------------------------------------------
-- 3) Group member helper RPCs
-- ------------------------------------------------------------
create or replace function public.os_group_add_member(
  p_group_id uuid,
  p_student_id uuid,
  p_default_deduct_hours numeric default null,
  p_seat_label text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  g public.os_student_groups;
  sce public.os_student_course_enrollments;
  m public.os_student_group_members;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  select * into g from public.os_student_groups where id=p_group_id and status<>'archived';
  if g.id is null then raise exception 'Group not found'; end if;
  select * into sce
    from public.os_student_course_enrollments
   where student_id=p_student_id
     and course_id=g.course_id
     and status in ('active','paused')
   order by case when status='active' then 0 else 1 end, created_at desc
   limit 1;
  if sce.id is null then raise exception 'Student has no active enrollment for this group course'; end if;

  insert into public.os_student_group_members(
    group_id,student_id,student_course_enrollment_id,default_deduct_hours,seat_label,note,is_active,left_at,updated_at
  ) values(
    p_group_id,p_student_id,sce.id,p_default_deduct_hours,p_seat_label,p_note,true,null,now()
  )
  on conflict(group_id,student_id) do update set
    student_course_enrollment_id=excluded.student_course_enrollment_id,
    default_deduct_hours=excluded.default_deduct_hours,
    seat_label=excluded.seat_label,
    note=excluded.note,
    is_active=true,
    left_at=null,
    updated_at=now()
  returning * into m;

  perform public.aw_emit_event('group.member_added','os_student_group_members',m.id::text,to_jsonb(m));
  return to_jsonb(m);
end $$;

create or replace function public.os_group_add_members(
  p_group_id uuid,
  p_student_ids uuid[],
  p_default_deduct_hours numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  sid uuid;
  added integer:=0;
  skipped jsonb:='[]'::jsonb;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  foreach sid in array coalesce(p_student_ids,array[]::uuid[])
  loop
    begin
      perform public.os_group_add_member(p_group_id,sid,p_default_deduct_hours,null,null);
      added:=added+1;
    exception when others then
      skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',sid,'reason',sqlerrm));
    end;
  end loop;
  return jsonb_build_object('ok',true,'added',added,'skipped',skipped);
end $$;

create or replace function public.os_group_remove_member(
  p_group_id uuid,
  p_student_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare m public.os_student_group_members;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  update public.os_student_group_members
     set is_active=false,left_at=now(),note=coalesce(p_note,note),updated_at=now()
   where group_id=p_group_id and student_id=p_student_id
   returning * into m;
  if m.id is null then raise exception 'Group member not found'; end if;
  perform public.aw_emit_event('group.member_removed','os_student_group_members',m.id::text,to_jsonb(m));
  return to_jsonb(m);
end $$;

-- ------------------------------------------------------------
-- 4) Open a teaching session from a Group Locker
--    Prefills roster as pending so nobody is billed accidentally.
-- ------------------------------------------------------------
create or replace function public.os_group_open_session(
  p_group_id uuid,
  p_session_date date,
  p_start_time time default null,
  p_end_time time default null,
  p_title text default null,
  p_billable_hours numeric default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  g public.os_student_groups;
  s public.os_attendance_sessions;
  roster_count integer:=0;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  select * into g from public.os_student_groups where id=p_group_id and status='active';
  if g.id is null then raise exception 'Active group not found'; end if;

  insert into public.os_attendance_sessions(
    course_id,tutor_id,group_id,session_date,start_time,end_time,title,mode,location,status,note,
    billable_hours,duration_source,created_by,updated_at
  ) values(
    g.course_id,g.tutor_id,g.id,coalesce(p_session_date,current_date),p_start_time,p_end_time,
    coalesce(nullif(btrim(p_title),''),g.name),g.mode,g.location,'open',p_note,
    coalesce(p_billable_hours,g.default_billable_hours),'group-locker',auth.uid(),now()
  ) returning * into s;

  insert into public.os_student_attendance(session_id,student_id,status,source,billable,note,updated_at)
  select s.id,m.student_id,'pending','group-locker',false,'รอเช็กชื่อจาก Group Locker',now()
    from public.os_student_group_members m
   where m.group_id=g.id and m.is_active=true
  on conflict(session_id,student_id) do nothing;
  get diagnostics roster_count=row_count;

  perform public.aw_emit_event('group.session_opened','os_attendance_sessions',s.id::text,
    jsonb_build_object('group_id',g.id,'group_code',g.group_code,'roster_count',roster_count));
  return jsonb_build_object('ok',true,'session',to_jsonb(s),'roster_count',roster_count);
end $$;

-- ------------------------------------------------------------
-- 5) Per-student hour deduction / adjustment
--    p_rows = [{"student_id":"uuid","hours":1.5}, ...]
--    Re-running adjusts the net hours instead of double-charging.
-- ------------------------------------------------------------
create or replace function public.os_deduct_session_hours_v2(
  p_session_id uuid,
  p_rows jsonb,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.os_attendance_sessions;
  item jsonb;
  sid uuid;
  target_hours numeric(8,2);
  att public.os_student_attendance;
  sce public.os_student_course_enrollments;
  gm public.os_student_group_members;
  current_hours numeric(10,2);
  delta numeric(10,2);
  has_usage boolean;
  processed integer:=0;
  skipped jsonb:='[]'::jsonb;
  results jsonb:='[]'::jsonb;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;
  select * into s from public.os_attendance_sessions where id=p_session_id for update;
  if s.id is null then raise exception 'Session not found'; end if;
  if jsonb_typeof(coalesce(p_rows,'[]'::jsonb))<>'array' then raise exception 'p_rows must be a JSON array'; end if;

  for item in select * from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb))
  loop
    begin
      sid:=(item->>'student_id')::uuid;
      target_hours:=round(greatest(0,coalesce((item->>'hours')::numeric,0)),2);
    exception when others then
      skipped:=skipped||jsonb_build_array(jsonb_build_object('row',item,'reason','invalid student_id/hours'));
      continue;
    end;

    select * into att from public.os_student_attendance
     where session_id=p_session_id and student_id=sid
     limit 1;
    if att.id is null or att.status not in ('present','late') or att.billable=false then
      skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',sid,'reason','attendance is not billable present/late'));
      continue;
    end if;

    sce:=null;
    if s.group_id is not null then
      select * into gm from public.os_student_group_members
       where group_id=s.group_id and student_id=sid and is_active=true limit 1;
      if gm.student_course_enrollment_id is not null then
        select * into sce from public.os_student_course_enrollments
         where id=gm.student_course_enrollment_id and status in ('active','paused') limit 1;
      end if;
    end if;
    if sce.id is null then
      select * into sce
        from public.os_student_course_enrollments
       where student_id=sid and course_id=s.course_id and status in ('active','paused')
       order by case when status='active' then 0 else 1 end, created_at desc
       limit 1;
    end if;
    if sce.id is null or sce.hour_pool_id is null then
      skipped:=skipped||jsonb_build_array(jsonb_build_object('student_id',sid,'reason','no active hour pool'));
      continue;
    end if;

    select coalesce(sum(hours_delta),0), bool_or(entry_type='usage')
      into current_hours,has_usage
      from public.os_hour_ledger
     where session_id=p_session_id
       and student_course_enrollment_id=sce.id;
    has_usage:=coalesce(has_usage,false);
    delta:=round(target_hours-current_hours,2);

    if abs(delta)>0.0001 then
      insert into public.os_hour_ledger(
        pool_id,student_id,student_course_enrollment_id,course_id,session_id,entry_type,hours_delta,note,created_by
      ) values(
        sce.hour_pool_id,sid,sce.id,s.course_id,p_session_id,
        case when not has_usage and current_hours=0 and target_hours>0 then 'usage' else 'adjustment' end,
        delta,
        coalesce(p_note,'ตัด/ปรับชั่วโมงรายคนจาก Tutor OS Group Locker'),
        auth.uid()
      );
    end if;

    update public.os_student_attendance
       set deducted_hours=target_hours,updated_at=now()
     where id=att.id;

    insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
    values(
      sid,
      'อัปเดตชั่วโมงเรียน',
      coalesce(s.title,'คาบเรียน')||' · ชั่วโมงของคาบนี้ '||trim(to_char(target_hours,'FM999990.00'))||' ชม.',
      'hours','teaching_session',p_session_id::text
    );

    processed:=processed+1;
    results:=results||jsonb_build_array(jsonb_build_object(
      'student_id',sid,'target_hours',target_hours,'previous_hours',current_hours,'delta',delta,'hour_pool_id',sce.hour_pool_id
    ));
  end loop;

  if processed>0 then
    update public.os_attendance_sessions
       set status='completed',
           deduction_status='deducted',
           deducted_at=coalesce(deducted_at,now()),
           deducted_by=auth.uid(),
           deduction_note=coalesce(p_note,deduction_note),
           updated_at=now()
     where id=p_session_id;
  end if;

  perform public.aw_emit_event('teaching.hours_updated','os_attendance_sessions',p_session_id::text,
    jsonb_build_object('processed',processed,'results',results,'skipped',skipped));

  return jsonb_build_object('ok',true,'processed',processed,'results',results,'skipped',skipped);
end $$;

create or replace function public.os_restore_student_session_hours(
  p_session_id uuid,
  p_student_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.os_attendance_sessions;
  sce public.os_student_course_enrollments;
  gm public.os_student_group_members;
  current_hours numeric(10,2):=0;
begin
  if not public.os_is_admin() then raise exception 'Admin permission required'; end if;
  select * into s from public.os_attendance_sessions where id=p_session_id;
  if s.id is null then raise exception 'Session not found'; end if;
  if s.group_id is not null then
    select * into gm from public.os_student_group_members where group_id=s.group_id and student_id=p_student_id limit 1;
    if gm.student_course_enrollment_id is not null then
      select * into sce from public.os_student_course_enrollments where id=gm.student_course_enrollment_id limit 1;
    end if;
  end if;
  if sce.id is null then
    select * into sce from public.os_student_course_enrollments
     where student_id=p_student_id and course_id=s.course_id
     order by created_at desc limit 1;
  end if;
  if sce.id is null or sce.hour_pool_id is null then raise exception 'No hour pool found'; end if;
  select coalesce(sum(hours_delta),0) into current_hours from public.os_hour_ledger
   where session_id=p_session_id and student_course_enrollment_id=sce.id;
  if current_hours>0 then
    insert into public.os_hour_ledger(pool_id,student_id,student_course_enrollment_id,course_id,session_id,entry_type,hours_delta,note,created_by)
    values(sce.hour_pool_id,p_student_id,sce.id,s.course_id,p_session_id,'adjustment',-current_hours,coalesce(p_note,'คืนชั่วโมงรายคนโดย Admin'),auth.uid());
  end if;
  update public.os_student_attendance set deducted_hours=0,updated_at=now() where session_id=p_session_id and student_id=p_student_id;
  insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
  values(p_student_id,'คืนชั่วโมงเรียนแล้ว',coalesce(s.title,'คาบเรียน')||' · คืน '||trim(to_char(current_hours,'FM999990.00'))||' ชม.','hours','teaching_session',p_session_id::text);
  perform public.aw_emit_event('teaching.hours_restored_student','os_attendance_sessions',p_session_id::text,jsonb_build_object('student_id',p_student_id,'hours',current_hours));
  return jsonb_build_object('ok',true,'student_id',p_student_id,'restored_hours',current_hours);
end $$;


-- Quick-check abuse protection for 4-digit PIN access.
alter table public.os_student_accounts add column if not exists quick_fail_count integer not null default 0;
alter table public.os_student_accounts add column if not exists quick_last_failed_at timestamptz;
alter table public.os_student_accounts add column if not exists quick_locked_until timestamptz;


-- V15.1 replaces the old whole-session restore so it also reverses later adjustments.
create or replace function public.os_restore_session_hours(p_session_id uuid, p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare
  r record;
  current_hours numeric(10,2);
  n integer:=0;
begin
  if not public.os_is_admin() then raise exception 'Admin permission required'; end if;
  for r in
    select distinct h.student_id,h.student_course_enrollment_id,h.pool_id,h.course_id
    from public.os_hour_ledger h
    where h.session_id=p_session_id and h.student_course_enrollment_id is not null
  loop
    select coalesce(sum(hours_delta),0) into current_hours
    from public.os_hour_ledger
    where session_id=p_session_id and student_course_enrollment_id=r.student_course_enrollment_id;
    if current_hours>0 then
      insert into public.os_hour_ledger(pool_id,student_id,student_course_enrollment_id,course_id,session_id,entry_type,hours_delta,note,created_by)
      values(r.pool_id,r.student_id,r.student_course_enrollment_id,r.course_id,p_session_id,'adjustment',-current_hours,coalesce(p_note,'คืนชั่วโมงทั้งคาบโดย Admin'),auth.uid());
      n:=n+1;
    end if;
    update public.os_student_attendance set deducted_hours=0,updated_at=now()
    where session_id=p_session_id and student_id=r.student_id;
  end loop;
  update public.os_attendance_sessions set deduction_status='restored',updated_at=now() where id=p_session_id;
  perform public.aw_emit_event('teaching.hours_restored_session','os_attendance_sessions',p_session_id::text,jsonb_build_object('restored_students',n));
  return jsonb_build_object('success',true,'restored_students',n);
end $$;

-- ------------------------------------------------------------
-- 6) Student quick hour check with personal Student Code + PIN
--    Returns minimal data only. No phone/email/address is exposed.
-- ------------------------------------------------------------
create or replace function public.student_quick_hours(
  p_student_code text,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  s public.os_students;
  a public.os_student_accounts;
  courses_json jsonb;
  groups_json jsonb;
  fail_count integer;
begin
  if coalesce(p_student_code,'')='' or p_pin !~ '^[0-9]{4}$' then
    return jsonb_build_object('ok',false,'message','รหัสนักเรียนหรือ PIN ไม่ถูกต้อง');
  end if;
  select * into s from public.os_students where upper(student_code)=upper(btrim(p_student_code)) and archived=false limit 1;
  if s.id is null then return jsonb_build_object('ok',false,'message','รหัสนักเรียนหรือ PIN ไม่ถูกต้อง'); end if;
  select * into a from public.os_student_accounts where student_id=s.id and is_active=true limit 1;
  if a.user_id is null or a.pin_hash is null then return jsonb_build_object('ok',false,'message','บัญชียังไม่ได้ตั้ง PIN'); end if;
  if a.quick_locked_until is not null and a.quick_locked_until>now() then
    return jsonb_build_object('ok',false,'message','ลองผิดหลายครั้ง กรุณารอ 15 นาทีแล้วลองใหม่');
  end if;
  if crypt(p_pin,a.pin_hash)<>a.pin_hash then
    fail_count:=case when a.quick_last_failed_at is null or a.quick_last_failed_at<now()-interval '15 minutes' then 1 else coalesce(a.quick_fail_count,0)+1 end;
    update public.os_student_accounts set
      quick_fail_count=fail_count,quick_last_failed_at=now(),
      quick_locked_until=case when fail_count>=5 then now()+interval '15 minutes' else null end,
      updated_at=now()
    where user_id=a.user_id;
    return jsonb_build_object('ok',false,'message',case when fail_count>=5 then 'ลองผิดหลายครั้ง ระบบล็อก 15 นาที' else 'รหัสนักเรียนหรือ PIN ไม่ถูกต้อง' end);
  end if;
  update public.os_student_accounts set quick_fail_count=0,quick_last_failed_at=null,quick_locked_until=null,updated_at=now() where user_id=a.user_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'course_id',sce.course_id,
    'course_name',coalesce(c.name,sce.course_label,'คอร์ส'),
    'status',sce.status,
    'total_hours',coalesce(p.total_hours,sce.hours_total),
    'used_hours',coalesce(p.used_hours,sce.hours_used),
    'remaining_hours',case when coalesce(p.unlimited,false) then null else greatest(0,coalesce(p.total_hours,sce.hours_total)-coalesce(p.used_hours,sce.hours_used)) end,
    'unlimited',coalesce(p.unlimited,false)
  ) order by sce.created_at desc),'[]'::jsonb)
  into courses_json
  from public.os_student_course_enrollments sce
  left join public.os_hour_pools p on p.id=sce.hour_pool_id
  left join public.courses c on c.id=sce.course_id
  where sce.student_id=s.id and sce.status in ('active','paused');

  select coalesce(jsonb_agg(jsonb_build_object(
    'group_code',g.group_code,'name',g.name,'course_name',c.name
  ) order by g.name),'[]'::jsonb)
  into groups_json
  from public.os_student_group_members m
  join public.os_student_groups g on g.id=m.group_id and g.status='active'
  left join public.courses c on c.id=g.course_id
  where m.student_id=s.id and m.is_active=true;

  return jsonb_build_object(
    'ok',true,
    'student_code',s.student_code,
    'display_name',s.display_name,
    'courses',courses_json,
    'groups',groups_json,
    'checked_at',now()
  );
end $$;

-- ------------------------------------------------------------
-- 7) Student Portal bootstrap now includes Group Lockers
-- ------------------------------------------------------------
create or replace function public.student_v11_bootstrap()
returns jsonb language plpgsql security definer set search_path=public as $$
declare sid uuid:=public.aw_my_student_id(); result jsonb;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  select jsonb_build_object(
    'student',(select to_jsonb(s) from public.os_students s where s.id=sid),
    'courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'course_type',c.course_type,'cover_url',c.image_url,'description',c.full_description,'public_description',c.short_detail,'renewal_alert_hours',3)) from public.courses c where c.id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid and sce.course_id is not null)),'[]'::jsonb),
    'open_courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'course_type',c.course_type,'cover_url',c.image_url,'description',c.full_description,'public_description',coalesce(o.public_note,c.short_detail),'hours',coalesce(o.default_hours,0),'price',coalesce(o.display_price,0))) from public.courses c join public.course_offerings o on o.course_id=c.id where c.active=true and o.status='open' and o.student_portal_open=true and o.enrollment_open=true and (o.starts_on is null or o.starts_on<=current_date) and (o.ends_on is null or o.ends_on>=current_date)),'[]'::jsonb),
    'enrollments',coalesce((select jsonb_agg(jsonb_build_object('id',sce.id,'course_id',sce.course_id,'status',sce.status,'hours_total',coalesce(p.total_hours,sce.hours_total),'hours_used',coalesce(p.used_hours,sce.hours_used),'hours_unlimited',coalesce(p.unlimited,false),'hour_pool_id',sce.hour_pool_id)) from public.os_student_course_enrollments sce left join public.os_hour_pools p on p.id=sce.hour_pool_id where sce.student_id=sid),'[]'::jsonb),
    'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'group_code',g.group_code,'name',g.name,'course_id',g.course_id,'tutor_id',g.tutor_id,'mode',g.mode,'location',g.location,'default_billable_hours',g.default_billable_hours)) from public.os_student_group_members m join public.os_student_groups g on g.id=m.group_id where m.student_id=sid and m.is_active=true and g.status='active'),'[]'::jsonb),
    'topics',coalesce((select jsonb_agg(to_jsonb(t) order by t.sort_order,t.created_at) from public.os_learning_topics t where t.is_active=true and t.course_id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid and sce.status in ('active','paused','completed')) and t.publish_at<=now() and (t.available_until is null or t.available_until>now())),'[]'::jsonb),
    'assets',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'topic_id',a.topic_id,'title',a.title,'asset_type',case a.asset_type when 'video' then 'external_video' when 'link' then 'external_link' when 'file' then 'file' else a.asset_type end,'url',a.url,'storage_path',a.storage_path,'description','')) from public.os_learning_assets a where a.is_active=true and a.topic_id in (select t.id from public.os_learning_topics t where t.course_id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid))),'[]'::jsonb),
    'progress',coalesce((select jsonb_agg(to_jsonb(p)) from public.portal_learning_progress p where p.student_id=sid),'[]'::jsonb),
    'notifications',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.portal_notifications n where n.student_id=sid),'[]'::jsonb),
    'attendance',coalesce((select jsonb_agg(to_jsonb(a) order by a.created_at desc) from public.os_student_attendance a where a.student_id=sid),'[]'::jsonb),
    'sessions',coalesce((select jsonb_agg(to_jsonb(ses) order by ses.session_date desc) from public.os_attendance_sessions ses where ses.id in (select a.session_id from public.os_student_attendance a where a.student_id=sid)),'[]'::jsonb),
    'payment_requests',coalesce((select jsonb_agg(to_jsonb(pr) order by pr.created_at desc) from public.portal_payment_requests pr where pr.student_id=sid),'[]'::jsonb),
    'payment_submissions',coalesce((select jsonb_agg(to_jsonb(ps) order by ps.created_at desc) from public.portal_payment_submissions ps where ps.student_id=sid),'[]'::jsonb),
    'codes',coalesce((select jsonb_agg(to_jsonb(cc) order by cc.created_at desc) from public.portal_course_codes cc where cc.student_id=sid),'[]'::jsonb),
    'library_new_books',coalesce((select jsonb_agg(jsonb_build_object('id',l.id,'title',l.title,'url',l.url)) from public.os_library_items l where l.item_type='book' and l.is_active=true and l.audience in ('student','both') and l.created_at>now()-interval '30 days'),'[]'::jsonb),
    'hour_ledger',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from public.os_hour_ledger h where h.student_id=sid),'[]'::jsonb)
  ) into result;
  return result;
end $$;

-- ------------------------------------------------------------
-- 8) RLS / grants
-- ------------------------------------------------------------
alter table public.os_student_groups enable row level security;
alter table public.os_student_group_members enable row level security;

drop policy if exists "Tutor OS staff access" on public.os_student_groups;
create policy "Tutor OS staff access" on public.os_student_groups
for all to authenticated using(public.os_is_staff()) with check(public.os_is_staff());

drop policy if exists "Tutor OS staff access" on public.os_student_group_members;
create policy "Tutor OS staff access" on public.os_student_group_members
for all to authenticated using(public.os_is_staff()) with check(public.os_is_staff());

-- Students can only read the locker(s) they themselves belong to.
drop policy if exists "Student own group read" on public.os_student_groups;
create policy "Student own group read" on public.os_student_groups
for select to authenticated using(
  exists(
    select 1 from public.os_student_group_members m
    join public.os_student_accounts a on a.student_id=m.student_id
    where m.group_id=os_student_groups.id and m.is_active=true and a.user_id=auth.uid() and a.is_active=true
  )
);

drop policy if exists "Student own group membership read" on public.os_student_group_members;
create policy "Student own group membership read" on public.os_student_group_members
for select to authenticated using(
  exists(select 1 from public.os_student_accounts a where a.student_id=os_student_group_members.student_id and a.user_id=auth.uid() and a.is_active=true)
);

revoke all on function public.student_quick_hours(text,text) from public;
grant execute on function public.student_quick_hours(text,text) to anon,authenticated;
grant execute on function public.os_group_add_member(uuid,uuid,numeric,text,text) to authenticated;
grant execute on function public.os_group_add_members(uuid,uuid[],numeric) to authenticated;
grant execute on function public.os_group_remove_member(uuid,uuid,text) to authenticated;
grant execute on function public.os_group_open_session(uuid,date,time,time,text,numeric,text) to authenticated;
grant execute on function public.os_deduct_session_hours_v2(uuid,jsonb,text) to authenticated;
grant execute on function public.os_restore_student_session_hours(uuid,uuid,text) to authenticated;
grant execute on function public.student_v11_bootstrap() to authenticated;

grant select,insert,update,delete on public.os_student_groups,public.os_student_group_members to authenticated;


-- ------------------------------------------------------------
-- Unified health now also checks Group Locker links.
-- ------------------------------------------------------------
create or replace function public.os_unified_health()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.os_is_staff() then raise exception 'Tutor OS staff only'; end if;
  return jsonb_build_object(
    'version','V15.1',
    'checked_at',now(),
    'modules',(select count(*) from public.os_module_registry where is_active=true),
    'open_courses',(select count(*) from public.course_offerings where status='open' and enrollment_open=true),
    'courses_without_offering',(select count(*) from public.courses c where c.active=true and not exists(select 1 from public.course_offerings o where o.course_id=c.id)),
    'enrollment_items_missing_course',(select count(*) from public.enrollment_items where course_id is null and status<>'cancelled'),
    'active_student_courses_without_pool',(select count(*) from public.os_student_course_enrollments where status in ('active','paused') and hour_pool_id is null),
    'pending_portal_slips',(select count(*) from public.portal_payment_submissions where status='pending'),
    'undeducted_completed_sessions',(select count(*) from public.os_attendance_sessions where status='completed' and coalesce(deduction_status,'pending') not in ('deducted','restored')),
    'active_groups',(select count(*) from public.os_student_groups where status='active'),
    'groups_without_members',(select count(*) from public.os_student_groups g where g.status='active' and not exists(select 1 from public.os_student_group_members m where m.group_id=g.id and m.is_active=true)),
    'group_members_missing_enrollment',(select count(*) from public.os_student_group_members m join public.os_student_groups g on g.id=m.group_id where m.is_active=true and (m.student_course_enrollment_id is null or not exists(select 1 from public.os_student_course_enrollments sce where sce.id=m.student_course_enrollment_id and sce.student_id=m.student_id and sce.course_id=g.course_id))),
    'group_sessions_today',(select count(*) from public.os_attendance_sessions where group_id is not null and session_date=current_date and status<>'cancelled'),
    'events_24h',(select count(*) from public.os_system_events where created_at>now()-interval '24 hours')
  );
end $$;
revoke all on function public.os_unified_health() from public,anon;
grant execute on function public.os_unified_health() to authenticated;

insert into public.os_settings(key,value,description) values
('UNIFIED_SYSTEM_VERSION','"V15.1"'::jsonb,'Shared integration schema version with Group Lockers'),
('integration_version','"V15.1"'::jsonb,'Unified integration contract version'),
('group_locker_enabled','true'::jsonb,'Group Locker roster and per-student hour deduction')
on conflict(key) do update set value=excluded.value,description=excluded.description,updated_at=now();

-- ------------------------------------------------------------
-- 9) Event Bus + Realtime
-- ------------------------------------------------------------
drop trigger if exists trg_aw_event_os_student_groups on public.os_student_groups;
create trigger trg_aw_event_os_student_groups
after insert or update or delete on public.os_student_groups
for each row execute function public.aw_event_trigger();

drop trigger if exists trg_aw_event_os_student_group_members on public.os_student_group_members;
create trigger trg_aw_event_os_student_group_members
after insert or update or delete on public.os_student_group_members
for each row execute function public.aw_event_trigger();

do $$ begin
  begin alter publication supabase_realtime add table public.os_student_groups; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.os_student_group_members; exception when duplicate_object then null; end;
end $$;

-- Register module for future unified subweb discovery.
insert into public.os_module_registry(module_key,title,path,description,icon,area,required_role,sort_order,is_active,updated_at)
values('group_lockers','Group Lockers','./?section=groups','จัดกลุ่มนักเรียนเป็น Locker สำหรับเช็กชื่อ เปิดคาบ และตัดชั่วโมงรายคน','fa-solid fa-people-group','teaching','staff',35,true,now())
on conflict(module_key) do update set title=excluded.title,path=excluded.path,description=excluded.description,icon=excluded.icon,area=excluded.area,required_role=excluded.required_role,sort_order=excluded.sort_order,is_active=true,updated_at=now();

commit;

-- Verification
select
  (select count(*) from public.os_student_groups) as groups,
  (select count(*) from public.os_student_group_members where is_active) as active_members,
  (select count(*) from public.os_attendance_sessions where group_id is not null) as group_sessions;
