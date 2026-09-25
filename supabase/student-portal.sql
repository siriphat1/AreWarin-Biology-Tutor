-- ============================================================
-- STUDENT PORTAL + STUDENT MANAGER
-- GitHub Pages + Supabase
-- Run once in Supabase SQL Editor after the existing website SQL.
-- ============================================================

create extension if not exists pgcrypto;

-- ---------- Helpers ----------
create or replace function public.is_portal_manager()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select auth.uid() is not null
     and coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) = false;
$$;

grant execute on function public.is_portal_manager() to anon, authenticated;

-- ---------- Students ----------
create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  student_code text not null unique,
  title text,
  first_name text not null,
  last_name text not null,
  class_level text not null check (class_level in ('ม.1','ม.2','ม.3','ม.4','ม.5','ม.6')),
  room text,
  phone text,
  email text,
  photo_path text,
  storage_key uuid not null default gen_random_uuid(),
  pin_hash text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists students_class_idx on public.students (class_level, room, student_code);
create index if not exists students_active_idx on public.students (active, class_level);

create or replace function public.touch_student_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_touch_students on public.students;
create trigger trg_touch_students before update on public.students
for each row execute function public.touch_student_updated_at();

-- ---------- Portal sessions ----------
create table if not exists public.student_portal_sessions (
  session_token uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  expires_at timestamptz not null default (now() + interval '12 hours'),
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);
create index if not exists student_portal_sessions_student_idx on public.student_portal_sessions(student_id, expires_at);

-- ---------- Grade uploads ----------
create table if not exists public.student_grade_uploads (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.students(id) on delete cascade,
  academic_year text not null,
  semester text not null,
  file_path text not null,
  original_file_name text,
  note text,
  uploaded_at timestamptz not null default now()
);
create index if not exists grade_uploads_student_idx on public.student_grade_uploads(student_id, uploaded_at desc);

-- ---------- Timetable ----------
create table if not exists public.student_timetables (
  id uuid primary key default gen_random_uuid(),
  class_level text not null check (class_level in ('ม.1','ม.2','ม.3','ม.4','ม.5','ม.6')),
  day_name text not null check (day_name in ('จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์','อาทิตย์')),
  day_order integer not null check (day_order between 1 and 7),
  period_no integer,
  start_time time not null,
  end_time time,
  subject_code text,
  subject_name text not null,
  teacher_name text,
  room text,
  semester text,
  academic_year text,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists timetable_class_idx on public.student_timetables(class_level, day_order, start_time);

create or replace function public.touch_timetable_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_touch_student_timetables on public.student_timetables;
create trigger trg_touch_student_timetables before update on public.student_timetables
for each row execute function public.touch_timetable_updated_at();

-- ---------- Exams ----------
create table if not exists public.student_exams (
  id uuid primary key default gen_random_uuid(),
  class_level text not null check (class_level in ('ม.1','ม.2','ม.3','ม.4','ม.5','ม.6')),
  exam_date date not null,
  start_time time,
  end_time time,
  subject_code text,
  subject_name text not null,
  exam_type text,
  room text,
  note text,
  semester text,
  academic_year text,
  published boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists exams_class_date_idx on public.student_exams(class_level, exam_date, start_time);

create or replace function public.touch_exam_updated_at()
returns trigger language plpgsql as $$ begin new.updated_at = now(); return new; end; $$;
drop trigger if exists trg_touch_student_exams on public.student_exams;
create trigger trg_touch_student_exams before update on public.student_exams
for each row execute function public.touch_exam_updated_at();

-- ---------- RLS: manager access only for direct tables ----------
alter table public.students enable row level security;
alter table public.student_portal_sessions enable row level security;
alter table public.student_grade_uploads enable row level security;
alter table public.student_timetables enable row level security;
alter table public.student_exams enable row level security;

-- Students policies
drop policy if exists "Managers read students" on public.students;
drop policy if exists "Managers insert students" on public.students;
drop policy if exists "Managers update students" on public.students;
drop policy if exists "Managers delete students" on public.students;
create policy "Managers read students" on public.students for select to authenticated using (public.is_portal_manager());
create policy "Managers insert students" on public.students for insert to authenticated with check (public.is_portal_manager());
create policy "Managers update students" on public.students for update to authenticated using (public.is_portal_manager()) with check (public.is_portal_manager());
create policy "Managers delete students" on public.students for delete to authenticated using (public.is_portal_manager());

-- Sessions: managers only directly (students use RPC)
drop policy if exists "Managers read portal sessions" on public.student_portal_sessions;
create policy "Managers read portal sessions" on public.student_portal_sessions for select to authenticated using (public.is_portal_manager());

-- Grades
drop policy if exists "Managers read grade uploads" on public.student_grade_uploads;
drop policy if exists "Managers manage grade uploads" on public.student_grade_uploads;
create policy "Managers read grade uploads" on public.student_grade_uploads for select to authenticated using (public.is_portal_manager());
create policy "Managers manage grade uploads" on public.student_grade_uploads for all to authenticated using (public.is_portal_manager()) with check (public.is_portal_manager());

-- Timetables
drop policy if exists "Managers read timetables" on public.student_timetables;
drop policy if exists "Managers manage timetables" on public.student_timetables;
create policy "Managers read timetables" on public.student_timetables for select to authenticated using (public.is_portal_manager());
create policy "Managers manage timetables" on public.student_timetables for all to authenticated using (public.is_portal_manager()) with check (public.is_portal_manager());

-- Exams
drop policy if exists "Managers read exams" on public.student_exams;
drop policy if exists "Managers manage exams" on public.student_exams;
create policy "Managers read exams" on public.student_exams for select to authenticated using (public.is_portal_manager());
create policy "Managers manage exams" on public.student_exams for all to authenticated using (public.is_portal_manager()) with check (public.is_portal_manager());

grant select, insert, update, delete on public.students to authenticated;
grant select on public.student_portal_sessions to authenticated;
grant select, insert, update, delete on public.student_grade_uploads to authenticated;
grant select, insert, update, delete on public.student_timetables to authenticated;
grant select, insert, update, delete on public.student_exams to authenticated;

-- ---------- Secure portal RPC helpers ----------
create or replace function public._portal_student_id(p_token uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid;
begin
  select s.student_id into v_id
  from public.student_portal_sessions s
  join public.students st on st.id = s.student_id and st.active = true
  where s.session_token = p_token and s.expires_at > now();
  if v_id is not null then
    update public.student_portal_sessions set last_seen_at = now() where session_token = p_token;
  end if;
  return v_id;
end; $$;

revoke all on function public._portal_student_id(uuid) from public, anon, authenticated;

create or replace function public.student_portal_login(p_student_code text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student public.students%rowtype;
  v_token uuid;
  v_exp timestamptz;
begin
  select * into v_student from public.students
  where student_code = trim(p_student_code) and active = true;

  if v_student.id is null or v_student.pin_hash is null or crypt(coalesce(p_pin,''), v_student.pin_hash) <> v_student.pin_hash then
    return jsonb_build_object('ok', false, 'message', 'รหัสนักเรียนหรือ PIN ไม่ถูกต้อง');
  end if;

  delete from public.student_portal_sessions where expires_at <= now();
  insert into public.student_portal_sessions(student_id, expires_at)
  values (v_student.id, now() + interval '12 hours')
  returning session_token, expires_at into v_token, v_exp;

  return jsonb_build_object(
    'ok', true,
    'session_token', v_token,
    'expires_at', v_exp,
    'student', jsonb_build_object(
      'id', v_student.id,
      'student_code', v_student.student_code,
      'title', v_student.title,
      'first_name', v_student.first_name,
      'last_name', v_student.last_name,
      'class_level', v_student.class_level,
      'room', v_student.room,
      'phone', v_student.phone,
      'email', v_student.email,
      'photo_path', v_student.photo_path,
      'storage_key', v_student.storage_key
    )
  );
end; $$;

grant execute on function public.student_portal_login(text,text) to anon, authenticated;

create or replace function public.student_portal_dashboard(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_student public.students%rowtype;
  v_timetable jsonb;
  v_exams jsonb;
  v_grades jsonb;
  v_tt_year text;
  v_tt_sem text;
begin
  v_student_id := public._portal_student_id(p_token);
  if v_student_id is null then return jsonb_build_object('ok',false,'message','เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่'); end if;
  select * into v_student from public.students where id = v_student_id;

  select t.academic_year, t.semester into v_tt_year, v_tt_sem
  from public.student_timetables t
  where t.class_level = v_student.class_level and t.published = true
  order by t.academic_year desc nulls last, t.semester desc nulls last, t.created_at desc
  limit 1;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'day_name',t.day_name,'day_order',t.day_order,'period_no',t.period_no,
    'start_time',to_char(t.start_time,'HH24:MI'),'end_time',case when t.end_time is null then null else to_char(t.end_time,'HH24:MI') end,
    'subject_code',t.subject_code,'subject_name',t.subject_name,'teacher_name',t.teacher_name,'room',t.room,
    'semester',t.semester,'academic_year',t.academic_year
  ) order by t.day_order, t.start_time, t.period_no), '[]'::jsonb)
  into v_timetable from public.student_timetables t
  where t.class_level = v_student.class_level and t.published = true
    and t.academic_year is not distinct from v_tt_year
    and t.semester is not distinct from v_tt_sem;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',e.id,'exam_date',e.exam_date,'start_time',case when e.start_time is null then null else to_char(e.start_time,'HH24:MI') end,
    'end_time',case when e.end_time is null then null else to_char(e.end_time,'HH24:MI') end,'subject_code',e.subject_code,
    'subject_name',e.subject_name,'exam_type',e.exam_type,'room',e.room,'note',e.note,'semester',e.semester,'academic_year',e.academic_year
  ) order by e.exam_date, e.start_time), '[]'::jsonb)
  into v_exams from public.student_exams e
  where e.class_level = v_student.class_level and e.published = true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',g.id,'academic_year',g.academic_year,'semester',g.semester,'file_path',g.file_path,
    'original_file_name',g.original_file_name,'note',g.note,'uploaded_at',g.uploaded_at
  ) order by g.uploaded_at desc), '[]'::jsonb)
  into v_grades from public.student_grade_uploads g where g.student_id = v_student_id;

  return jsonb_build_object(
    'ok',true,
    'student',jsonb_build_object(
      'id',v_student.id,'student_code',v_student.student_code,'title',v_student.title,'first_name',v_student.first_name,
      'last_name',v_student.last_name,'class_level',v_student.class_level,'room',v_student.room,'phone',v_student.phone,
      'email',v_student.email,'photo_path',v_student.photo_path,'storage_key',v_student.storage_key
    ),
    'timetable',v_timetable,'exams',v_exams,'grades',v_grades
  );
end; $$;

grant execute on function public.student_portal_dashboard(uuid) to anon, authenticated;

create or replace function public.student_portal_update_profile(p_token uuid, p_phone text, p_email text, p_photo_path text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_key uuid;
begin
  v_id := public._portal_student_id(p_token);
  if v_id is null then return jsonb_build_object('ok',false,'message','เซสชันหมดอายุ'); end if;
  select storage_key into v_key from public.students where id=v_id;
  if p_photo_path is not null and p_photo_path <> '' and p_photo_path not like (v_key::text || '/profile/%') then
    return jsonb_build_object('ok',false,'message','ตำแหน่งไฟล์รูปไม่ถูกต้อง');
  end if;
  update public.students set phone=nullif(trim(p_phone),''), email=nullif(trim(p_email),''),
    photo_path=coalesce(nullif(trim(p_photo_path),''),photo_path) where id=v_id;
  return jsonb_build_object('ok',true);
end; $$;

grant execute on function public.student_portal_update_profile(uuid,text,text,text) to anon, authenticated;

create or replace function public.student_portal_add_grade(
  p_token uuid, p_academic_year text, p_semester text, p_file_path text, p_original_file_name text, p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_key uuid; v_grade_id uuid;
begin
  v_id := public._portal_student_id(p_token);
  if v_id is null then return jsonb_build_object('ok',false,'message','เซสชันหมดอายุ'); end if;
  select storage_key into v_key from public.students where id=v_id;
  if p_file_path not like (v_key::text || '/grades/%') then return jsonb_build_object('ok',false,'message','ตำแหน่งไฟล์ไม่ถูกต้อง'); end if;
  insert into public.student_grade_uploads(student_id,academic_year,semester,file_path,original_file_name,note)
  values(v_id,trim(p_academic_year),trim(p_semester),p_file_path,p_original_file_name,nullif(trim(p_note),'')) returning id into v_grade_id;
  return jsonb_build_object('ok',true,'id',v_grade_id);
end; $$;

grant execute on function public.student_portal_add_grade(uuid,text,text,text,text,text) to anon, authenticated;

create or replace function public.student_portal_delete_grade(p_token uuid, p_grade_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_path text;
begin
  v_id := public._portal_student_id(p_token);
  if v_id is null then return jsonb_build_object('ok',false,'message','เซสชันหมดอายุ'); end if;
  delete from public.student_grade_uploads where id=p_grade_id and student_id=v_id returning file_path into v_path;
  if v_path is null then return jsonb_build_object('ok',false,'message','ไม่พบไฟล์'); end if;
  return jsonb_build_object('ok',true,'file_path',v_path);
end; $$;

grant execute on function public.student_portal_delete_grade(uuid,uuid) to anon, authenticated;

create or replace function public.student_portal_change_pin(p_token uuid, p_current_pin text, p_new_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_id uuid; v_hash text;
begin
  v_id := public._portal_student_id(p_token);
  if v_id is null then return jsonb_build_object('ok',false,'message','เซสชันหมดอายุ'); end if;
  if length(coalesce(p_new_pin,'')) < 6 then return jsonb_build_object('ok',false,'message','PIN ใหม่ต้องมีอย่างน้อย 6 ตัวอักษร'); end if;
  select pin_hash into v_hash from public.students where id=v_id;
  if crypt(coalesce(p_current_pin,''),v_hash) <> v_hash then return jsonb_build_object('ok',false,'message','PIN ปัจจุบันไม่ถูกต้อง'); end if;
  update public.students set pin_hash=crypt(p_new_pin,gen_salt('bf')) where id=v_id;
  return jsonb_build_object('ok',true);
end; $$;

grant execute on function public.student_portal_change_pin(uuid,text,text) to anon, authenticated;

-- ---------- Manager RPC: batch student import ----------
create or replace function public.manager_import_students(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  r jsonb; v_code text; v_pin text; v_id uuid; v_generated boolean; v_result jsonb := '[]'::jsonb;
begin
  if not public.is_portal_manager() then raise exception 'Not authorized'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'Rows must be an array'; end if;
  for r in select * from jsonb_array_elements(p_rows)
  loop
    v_code := trim(coalesce(r->>'student_code',''));
    if v_code = '' then continue; end if;
    v_pin := nullif(trim(coalesce(r->>'portal_pin','')), '');
    v_generated := false;
    if v_pin is null then
      if not exists(select 1 from public.students where student_code=v_code) then
        v_pin := lpad((floor(random()*1000000))::int::text,6,'0');
        v_generated := true;
      end if;
    end if;

    insert into public.students(student_code,title,first_name,last_name,class_level,room,phone,email,pin_hash,active)
    values(
      v_code, nullif(trim(r->>'title'),''), trim(coalesce(r->>'first_name','')), trim(coalesce(r->>'last_name','')),
      trim(coalesce(r->>'class_level','')), nullif(trim(r->>'room'),''), nullif(trim(r->>'phone'),''), nullif(trim(r->>'email'),''),
      crypt(coalesce(v_pin,'TEMP-NOT-USED'),gen_salt('bf')), coalesce((r->>'active')::boolean,true)
    )
    on conflict(student_code) do update set
      title=excluded.title, first_name=excluded.first_name, last_name=excluded.last_name, class_level=excluded.class_level,
      room=excluded.room, phone=excluded.phone, email=excluded.email, active=excluded.active,
      pin_hash=case when v_pin is not null then crypt(v_pin,gen_salt('bf')) else public.students.pin_hash end
    returning id into v_id;

    v_result := v_result || jsonb_build_array(jsonb_build_object('id',v_id,'student_code',v_code,'generated_pin',case when v_generated then v_pin else null end));
  end loop;
  return jsonb_build_object('ok',true,'rows',v_result);
end; $$;

grant execute on function public.manager_import_students(jsonb) to authenticated;

create or replace function public.manager_reset_student_pin(p_student_id uuid, p_new_pin text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_portal_manager() then raise exception 'Not authorized'; end if;
  if length(coalesce(p_new_pin,'')) < 6 then return jsonb_build_object('ok',false,'message','PIN ต้องมีอย่างน้อย 6 ตัวอักษร'); end if;
  update public.students set pin_hash=crypt(p_new_pin,gen_salt('bf')) where id=p_student_id;
  return jsonb_build_object('ok',true);
end; $$;

grant execute on function public.manager_reset_student_pin(uuid,text) to authenticated;

-- ---------- Storage ----------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values(
  'student-portal-files','student-portal-files',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create or replace function public.valid_student_storage_path(p_name text)
returns boolean
language sql
stable
security definer
set search_path = public, storage
as $$
  select exists(
    select 1 from public.students s
    where s.active=true
      and s.storage_key::text = (storage.foldername(p_name))[1]
      and (storage.foldername(p_name))[2] in ('profile','grades')
  );
$$;

grant execute on function public.valid_student_storage_path(text) to anon, authenticated;

-- Remove our policies if re-running.
drop policy if exists "Portal users read own secret path" on storage.objects;
drop policy if exists "Portal users upload own secret path" on storage.objects;
drop policy if exists "Portal users update own secret path" on storage.objects;
drop policy if exists "Portal users delete own secret path" on storage.objects;
drop policy if exists "Portal managers read files" on storage.objects;
drop policy if exists "Portal managers insert files" on storage.objects;
drop policy if exists "Portal managers update files" on storage.objects;
drop policy if exists "Portal managers delete files" on storage.objects;

create policy "Portal users read own secret path" on storage.objects for select to anon
using (bucket_id='student-portal-files' and public.valid_student_storage_path(name));
create policy "Portal users upload own secret path" on storage.objects for insert to anon
with check (bucket_id='student-portal-files' and public.valid_student_storage_path(name));
create policy "Portal users update own secret path" on storage.objects for update to anon
using (bucket_id='student-portal-files' and public.valid_student_storage_path(name))
with check (bucket_id='student-portal-files' and public.valid_student_storage_path(name));
create policy "Portal users delete own secret path" on storage.objects for delete to anon
using (bucket_id='student-portal-files' and public.valid_student_storage_path(name));

create policy "Portal managers read files" on storage.objects for select to authenticated
using (bucket_id='student-portal-files' and public.is_portal_manager());
create policy "Portal managers insert files" on storage.objects for insert to authenticated
with check (bucket_id='student-portal-files' and public.is_portal_manager());
create policy "Portal managers update files" on storage.objects for update to authenticated
using (bucket_id='student-portal-files' and public.is_portal_manager())
with check (bucket_id='student-portal-files' and public.is_portal_manager());
create policy "Portal managers delete files" on storage.objects for delete to authenticated
using (bucket_id='student-portal-files' and public.is_portal_manager());

comment on table public.students is 'Student Portal master data';
comment on table public.student_timetables is 'Class timetable by class level';
comment on table public.student_exams is 'Exam schedule by class level';
comment on table public.student_grade_uploads is 'Grade/result files uploaded by students';
