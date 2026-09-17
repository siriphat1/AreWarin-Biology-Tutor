-- Previous website cumulative V21.2 file not found in runtime.



-- ============================================================================
-- V22 · RETURNING STUDENT MIGRATION
-- นักเรียนเดิมที่เรียนก่อนระบบใหม่
-- ============================================================================

-- Production uses public.os_students as the canonical Student/Tutor OS profile.
do $$
begin
  if to_regclass('public.os_students') is null then
    raise exception 'Missing public.os_students. Install the current Student/Tutor OS base schema first.';
  end if;
  if to_regclass('public.enrollments') is null then
    raise exception 'Missing public.enrollments. Install the AreWarin enrollment base schema first.';
  end if;
end $$;

create or replace function public.registration_norm_phone(p_value text)
returns text
language sql
immutable
as $$
  select regexp_replace(coalesce(p_value,''), '\D', '', 'g')
$$;

alter table public.os_students
  add column if not exists legacy_student boolean not null default false,
  add column if not exists legacy_imported_at timestamptz,
  add column if not exists profile_completed_at timestamptz;

create index if not exists os_students_registration_phone_idx
  on public.os_students(public.registration_norm_phone(phone));

-- ---------------------------------------------------------------------------
-- Lookup: enrollments + profile-only migrated students
-- Returns the shape expected by the current registration UI.
-- ---------------------------------------------------------------------------
create or replace function public.registration_lookup_returning_student(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.registration_norm_phone(p_phone);
  v_student public.os_students%rowtype;
  v_latest public.enrollments%rowtype;
  v_history jsonb := '[]'::jsonb;
  v_fullname text;
begin
  if length(v_phone) < 9 then
    return jsonb_build_object('found',false,'code','INVALID_PHONE');
  end if;

  select s.*
    into v_student
    from public.os_students s
   where coalesce(s.phone_key,'') = v_phone
      or public.registration_norm_phone(s.phone) = v_phone
   order by coalesce(s.archived,false), s.created_at desc nulls last
   limit 1;

  select e.*
    into v_latest
    from public.enrollments e
   where public.registration_norm_phone(e.phone) = v_phone
   order by e.created_at desc
   limit 1;

  if v_student.id is null and v_latest.id is null then
    return jsonb_build_object('found',false,'code','NOT_FOUND');
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id',x.id,
        'course',x.course_text,
        'tutor',x.tutor_text,
        'date',to_char(x.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),
        'status',x.status
      )
      order by x.created_at desc
    ),
    '[]'::jsonb
  )
  into v_history
  from (
    select e.id,e.course_text,e.tutor_text,e.created_at,e.status
      from public.enrollments e
     where public.registration_norm_phone(e.phone) = v_phone
     order by e.created_at desc
     limit 8
  ) x;

  v_fullname := coalesce(
    nullif(trim(concat_ws(' ',v_student.first_name,v_student.last_name)),''),
    nullif(v_student.display_name,''),
    v_latest.fullname,
    ''
  );

  return jsonb_build_object(
    'found',true,
    'source',case
      when v_student.id is not null and v_latest.id is null then 'legacy_profile'
      when coalesce(v_student.legacy_student,false) and v_latest.id is null then 'legacy_profile'
      else 'system'
    end,
    'legacyProfileId',v_student.id,
    'student',jsonb_build_object(
      'id',v_student.id,
      'studentCode',v_student.student_code,
      'fullname',v_fullname,
      'nickname',coalesce(v_student.nickname,v_latest.nickname),
      'phone',coalesce(v_student.phone,v_latest.phone,p_phone),
      'lineId',coalesce(v_student.line_id,v_latest.line_id),
      'email',coalesce(v_student.email,v_latest.email),
      'school',coalesce(v_student.school,v_latest.school),
      'grade',coalesce(v_student.grade,v_latest.grade),
      'faculty',coalesce(v_student.faculty,v_latest.faculty),
      'province',coalesce(v_student.province,v_latest.province),
      'studyType',v_latest.study_type,
      'groupSize',v_latest.group_size,
      'legacyStudent',coalesce(v_student.legacy_student,false)
    ),
    'latest',case when v_latest.id is null then null else jsonb_build_object(
      'id',v_latest.id,
      'name',v_latest.fullname,
      'course',v_latest.course_text,
      'tutor',v_latest.tutor_text,
      'date',to_char(v_latest.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),
      'status',v_latest.status
    ) end,
    'history',v_history
  );
end;
$$;

grant execute on function public.registration_lookup_returning_student(text)
to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Profile-only migration / pre-registration profile creation.
-- Does NOT create a fake enrollment.
-- ---------------------------------------------------------------------------
create or replace function public.registration_upsert_legacy_student_profile(
  p_fullname text,
  p_nickname text,
  p_phone text,
  p_email text default '',
  p_line_id text default '',
  p_school text default '',
  p_grade text default '',
  p_faculty text default '',
  p_province text default '',
  p_parent_name text default '',
  p_parent_phone text default ''
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_phone text := public.registration_norm_phone(p_phone);
  v_name text := trim(coalesce(p_fullname,''));
  v_nick text := trim(coalesce(p_nickname,''));
  v_id uuid;
  v_code text;
begin
  if length(v_phone) < 9 then
    raise exception 'กรุณาตรวจสอบเบอร์โทร';
  end if;
  if v_name = '' then
    raise exception 'กรุณากรอกชื่อ-นามสกุล';
  end if;
  if v_nick = '' then
    raise exception 'กรุณากรอกชื่อเล่น';
  end if;

  select s.id
    into v_id
    from public.os_students s
   where coalesce(s.phone_key,'') = v_phone
      or public.registration_norm_phone(s.phone) = v_phone
   order by coalesce(s.archived,false), s.created_at desc nulls last
   limit 1;

  if v_id is null then
    insert into public.os_students(
      phone_key,display_name,first_name,last_name,nickname,phone,email,line_id,
      school,grade,faculty,province,guardian_name,guardian_phone,
      status,archived,legacy_student,legacy_imported_at,profile_completed_at
    )
    values(
      v_phone,
      coalesce(nullif(v_nick,''),v_name),
      v_name,null,
      v_nick,p_phone,
      nullif(trim(coalesce(p_email,'')),''),
      nullif(trim(coalesce(p_line_id,'')),''),
      nullif(trim(coalesce(p_school,'')),''),
      nullif(trim(coalesce(p_grade,'')),''),
      nullif(trim(coalesce(p_faculty,'')),''),
      nullif(trim(coalesce(p_province,'')),''),
      nullif(trim(coalesce(p_parent_name,'')),''),
      nullif(trim(coalesce(p_parent_phone,'')),''),
      'active',false,true,now(),now()
    )
    returning id into v_id;
  else
    update public.os_students
       set phone_key = v_phone,
           display_name = coalesce(nullif(v_nick,''),v_name),
           first_name = v_name,
           nickname = v_nick,
           phone = p_phone,
           email = coalesce(nullif(trim(coalesce(p_email,'')),''),email),
           line_id = coalesce(nullif(trim(coalesce(p_line_id,'')),''),line_id),
           school = coalesce(nullif(trim(coalesce(p_school,'')),''),school),
           grade = coalesce(nullif(trim(coalesce(p_grade,'')),''),grade),
           faculty = coalesce(nullif(trim(coalesce(p_faculty,'')),''),faculty),
           province = coalesce(nullif(trim(coalesce(p_province,'')),''),province),
           guardian_name = coalesce(nullif(trim(coalesce(p_parent_name,'')),''),guardian_name),
           guardian_phone = coalesce(nullif(trim(coalesce(p_parent_phone,'')),''),guardian_phone),
           status = 'active',
           archived = false,
           legacy_student = true,
           legacy_imported_at = coalesce(legacy_imported_at,now()),
           profile_completed_at = now(),
           updated_at = now()
     where id = v_id;
  end if;

  -- Existing production trigger normally assigns student_code.
  -- Deterministic UUID fallback prevents a blank profile card if no trigger exists.
  update public.os_students
     set student_code = 'AW-' || upper(substr(replace(id::text,'-',''),1,8))
   where id = v_id
     and nullif(student_code,'') is null;

  select student_code into v_code
  from public.os_students
  where id=v_id;

  return jsonb_build_object(
    'ok',true,
    'student_id',v_id,
    'student_code',v_code,
    'phone_key',v_phone,
    'legacy_student',true
  );
end;
$$;

grant execute on function public.registration_upsert_legacy_student_profile(
  text,text,text,text,text,text,text,text,text,text,text
) to anon, authenticated;

notify pgrst, 'reload schema';


-- ============================================================================
-- AreWarin V23 · LEGACY STUDENT RECORDS SUBWEB
-- Manager/Admin only
-- ============================================================================

begin;
create extension if not exists pgcrypto;

do $$
begin
  if to_regclass('public.os_students') is null then
    raise exception 'Missing public.os_students';
  end if;
  if to_regclass('public.courses') is null then
    raise exception 'Missing public.courses';
  end if;
  if to_regclass('public.enrollments') is null then
    raise exception 'Missing public.enrollments';
  end if;
end $$;

-- Compatibility fields used by V22/V23.
alter table public.os_students
  add column if not exists legacy_student boolean not null default false,
  add column if not exists legacy_imported_at timestamptz,
  add column if not exists profile_completed_at timestamptz,
  add column if not exists line_id text;

-- Keep production guardian columns as canonical; no duplicate parent_name columns required.
alter table public.os_students
  add column if not exists guardian_name text,
  add column if not exists guardian_phone text;

create or replace function public.registration_norm_phone(p_value text)
returns text language sql immutable
as $$ select regexp_replace(coalesce(p_value,''), '\D', '', 'g') $$;

create index if not exists os_students_registration_phone_idx
  on public.os_students(public.registration_norm_phone(phone));

-- Historical courses before the current enrollment system.
create table if not exists public.legacy_student_course_history (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  course_id uuid null references public.courses(id) on delete set null,
  tutor_id uuid null references public.tutors(id) on delete set null,
  course_name text not null,
  tutor_name text null,
  academic_year integer null,
  study_period text null,
  hours numeric(10,2) null check (hours is null or hours >= 0),
  status text not null default 'completed'
    check (status in ('completed','active','paused','unknown')),
  note text null,
  source text not null default 'manager'
    check (source in ('manager','student_migration','import')),
  created_by uuid null references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists legacy_student_course_history_student_idx
  on public.legacy_student_course_history(student_id, academic_year desc nulls last, created_at desc);
create index if not exists legacy_student_course_history_course_idx
  on public.legacy_student_course_history(course_id)
  where course_id is not null;

alter table public.legacy_student_course_history enable row level security;

drop policy if exists "manager legacy course history" on public.legacy_student_course_history;
create policy "manager legacy course history"
on public.legacy_student_course_history
for all to authenticated
using (public.is_manager())
with check (public.is_manager());

-- No public select policy: this subweb is staff-only.

-- Touch timestamp.
create or replace function public.legacy_students_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end $$;

drop trigger if exists legacy_student_course_history_touch on public.legacy_student_course_history;
create trigger legacy_student_course_history_touch
before update on public.legacy_student_course_history
for each row execute function public.legacy_students_touch_updated_at();

-- Staff identity.
create or replace function public.legacy_students_manager_me()
returns jsonb
language sql stable security definer set search_path=public
as $$
  select jsonb_build_object(
    'allowed',public.is_manager(),
    'user_id',auth.uid()
  )
$$;
grant execute on function public.legacy_students_manager_me() to authenticated;

-- Catalog for linking legacy history to current courses.
create or replace function public.legacy_students_manager_catalog()
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare v_rows jsonb;
begin
  if not public.is_manager() then raise exception 'Manager permission required'; end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'name',coalesce(nullif(c.title,''),c.name),
    'tutor_id',c.tutor_id,
    'tutor_name',t.display_name
  ) order by coalesce(nullif(c.title,''),c.name)),'[]'::jsonb)
  into v_rows
  from public.courses c
  left join public.tutors t on t.id=c.tutor_id
  where coalesce(c.is_active,c.active,true)=true;
  return v_rows;
end $$;
grant execute on function public.legacy_students_manager_catalog() to authenticated;

-- Dashboard/list. Course names include BOTH legacy history and current enrollments.
create or replace function public.legacy_students_manager_bootstrap()
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_summary jsonb;
  v_students jsonb;
begin
  if not public.is_manager() then raise exception 'Manager permission required'; end if;

  select jsonb_build_object(
    'legacy_students',(select count(*) from public.os_students s where coalesce(s.legacy_student,false)=true and coalesce(s.archived,false)=false),
    'legacy_course_records',(select count(*) from public.legacy_student_course_history),
    'linked_course_records',(select count(*) from public.legacy_student_course_history where course_id is not null),
    'unmatched_course_records',(select count(*) from public.legacy_student_course_history where course_id is null)
  ) into v_summary;

  with legacy_names as (
    select h.student_id,array_agg(distinct h.course_name) as names
    from public.legacy_student_course_history h group by h.student_id
  ),
  enrollment_names as (
    select s.id student_id,array_agg(distinct coalesce(i.course_name_snapshot,e.course_text)) filter(where coalesce(i.course_name_snapshot,e.course_text) is not null) as names
    from public.os_students s
    left join public.enrollments e
      on public.registration_norm_phone(e.phone)=coalesce(nullif(s.phone_key,''),public.registration_norm_phone(s.phone))
    left join public.enrollment_items i on i.enrollment_id=e.id
    group by s.id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',s.id,
    'student_code',s.student_code,
    'display_name',s.display_name,
    'fullname',coalesce(nullif(trim(concat_ws(' ',s.first_name,s.last_name)),''),s.display_name),
    'nickname',s.nickname,
    'phone',s.phone,
    'email',s.email,
    'school',s.school,
    'grade',s.grade,
    'faculty',s.faculty,
    'legacy_student',coalesce(s.legacy_student,false),
    'course_names',coalesce(to_jsonb(ln.names),'[]'::jsonb)||coalesce(to_jsonb(en.names),'[]'::jsonb)
  ) order by coalesce(s.legacy_student,false) desc,s.updated_at desc nulls last),'[]'::jsonb)
  into v_students
  from public.os_students s
  left join legacy_names ln on ln.student_id=s.id
  left join enrollment_names en on en.student_id=s.id
  where coalesce(s.archived,false)=false;

  return jsonb_build_object('summary',v_summary,'students',v_students);
end $$;
grant execute on function public.legacy_students_manager_bootstrap() to authenticated;

-- Complete student detail + merged course timeline.
create or replace function public.legacy_students_manager_student_detail(p_student_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_student public.os_students%rowtype;
  v_courses jsonb;
begin
  if not public.is_manager() then raise exception 'Manager permission required'; end if;
  select * into v_student from public.os_students where id=p_student_id;
  if not found then raise exception 'Student not found'; end if;

  with legacy_rows as (
    select
      'legacy'::text source,
      h.id,h.course_id,h.course_name,h.tutor_name,h.academic_year,h.study_period,h.hours,h.status,h.note,
      h.created_at as sort_at
    from public.legacy_student_course_history h
    where h.student_id=p_student_id
  ),
  system_rows as (
    select distinct on (coalesce(i.id,e.id))
      'system'::text source,
      coalesce(i.id,e.id) id,
      i.course_id,
      coalesce(i.course_name_snapshot,e.course_text,'ไม่ระบุคอร์ส') course_name,
      coalesce(i.tutor_name_snapshot,e.tutor_text) tutor_name,
      null::integer academic_year,
      to_char(e.created_at at time zone 'Asia/Bangkok','Mon YYYY') study_period,
      i.hours_allocated hours,
      coalesce(i.status,e.status) status,
      null::text note,
      e.created_at sort_at
    from public.enrollments e
    left join public.enrollment_items i on i.enrollment_id=e.id
    where public.registration_norm_phone(e.phone)=coalesce(nullif(v_student.phone_key,''),public.registration_norm_phone(v_student.phone))
    order by coalesce(i.id,e.id),e.created_at desc
  ),
  all_rows as (
    select * from legacy_rows union all select * from system_rows
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'source',source,'id',id,'course_id',course_id,'course_name',course_name,
    'tutor_name',tutor_name,'academic_year',academic_year,'study_period',study_period,
    'hours',hours,'status',status,'note',note,'sort_at',sort_at
  ) order by sort_at desc nulls last),'[]'::jsonb)
  into v_courses from all_rows;

  return jsonb_build_object(
    'student',jsonb_build_object(
      'id',v_student.id,'student_code',v_student.student_code,'display_name',v_student.display_name,
      'fullname',coalesce(nullif(trim(concat_ws(' ',v_student.first_name,v_student.last_name)),''),v_student.display_name),
      'nickname',v_student.nickname,'phone',v_student.phone,'email',v_student.email,'line_id',v_student.line_id,
      'school',v_student.school,'grade',v_student.grade,'education_level',v_student.education_level,
      'faculty',v_student.faculty,'province',v_student.province,'status',v_student.status,
      'legacy_student',coalesce(v_student.legacy_student,false),'legacy_imported_at',v_student.legacy_imported_at,
      'updated_at',v_student.updated_at
    ),
    'courses',v_courses
  );
end $$;
grant execute on function public.legacy_students_manager_student_detail(uuid) to authenticated;

-- Create/update a legacy student profile.
create or replace function public.legacy_students_manager_upsert_student(
  p_student_id uuid,
  p_fullname text,
  p_nickname text,
  p_phone text,
  p_email text default '',
  p_line_id text default '',
  p_school text default '',
  p_grade text default '',
  p_faculty text default '',
  p_province text default ''
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_id uuid:=p_student_id;
  v_phone text:=public.registration_norm_phone(p_phone);
  v_code text;
begin
  if not public.is_manager() then raise exception 'Manager permission required'; end if;
  if trim(coalesce(p_fullname,''))='' then raise exception 'กรุณากรอกชื่อ-นามสกุล'; end if;
  if trim(coalesce(p_nickname,''))='' then raise exception 'กรุณากรอกชื่อเล่น'; end if;
  if length(v_phone)<9 then raise exception 'กรุณาตรวจสอบเบอร์โทร'; end if;

  if v_id is null then
    select id into v_id from public.os_students
    where coalesce(phone_key,'')=v_phone or public.registration_norm_phone(phone)=v_phone
    order by created_at desc nulls last limit 1;
  end if;

  if v_id is null then
    insert into public.os_students(
      phone_key,display_name,first_name,nickname,phone,email,line_id,school,grade,faculty,province,
      status,archived,legacy_student,legacy_imported_at,profile_completed_at
    ) values(
      v_phone,p_nickname,p_fullname,p_nickname,p_phone,
      nullif(trim(coalesce(p_email,'')),''),nullif(trim(coalesce(p_line_id,'')),''),
      nullif(trim(coalesce(p_school,'')),''),nullif(trim(coalesce(p_grade,'')),''),
      nullif(trim(coalesce(p_faculty,'')),''),nullif(trim(coalesce(p_province,'')),''),
      'active',false,true,now(),now()
    ) returning id into v_id;
  else
    update public.os_students set
      phone_key=v_phone,display_name=p_nickname,first_name=p_fullname,nickname=p_nickname,phone=p_phone,
      email=nullif(trim(coalesce(p_email,'')),''),
      line_id=nullif(trim(coalesce(p_line_id,'')),''),
      school=nullif(trim(coalesce(p_school,'')),''),
      grade=nullif(trim(coalesce(p_grade,'')),''),
      faculty=nullif(trim(coalesce(p_faculty,'')),''),
      province=nullif(trim(coalesce(p_province,'')),''),
      legacy_student=true,legacy_imported_at=coalesce(legacy_imported_at,now()),
      profile_completed_at=now(),status='active',archived=false,updated_at=now()
    where id=v_id;
  end if;

  update public.os_students set student_code='AW-'||upper(substr(replace(id::text,'-',''),1,8))
  where id=v_id and nullif(student_code,'') is null;
  select student_code into v_code from public.os_students where id=v_id;
  return jsonb_build_object('ok',true,'student_id',v_id,'student_code',v_code);
end $$;
grant execute on function public.legacy_students_manager_upsert_student(uuid,text,text,text,text,text,text,text,text,text) to authenticated;

-- Add/edit historical course.
create or replace function public.legacy_students_manager_upsert_course(
  p_history_id uuid,
  p_student_id uuid,
  p_course_id uuid,
  p_course_name text,
  p_tutor_name text default '',
  p_academic_year integer default null,
  p_study_period text default '',
  p_hours numeric default null,
  p_status text default 'completed',
  p_note text default ''
)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_id uuid:=p_history_id;
  v_name text:=trim(coalesce(p_course_name,''));
  v_tutor_id uuid;
  v_tutor_name text:=nullif(trim(coalesce(p_tutor_name,'')),'');
begin
  if not public.is_manager() then raise exception 'Manager permission required'; end if;
  if not exists(select 1 from public.os_students where id=p_student_id) then raise exception 'Student not found'; end if;
  if p_status not in ('completed','active','paused','unknown') then raise exception 'Invalid status'; end if;

  if p_course_id is not null then
    select c.tutor_id,coalesce(nullif(c.title,''),c.name),coalesce(v_tutor_name,t.display_name)
      into v_tutor_id,v_name,v_tutor_name
    from public.courses c left join public.tutors t on t.id=c.tutor_id
    where c.id=p_course_id;
    if not found then raise exception 'Course not found'; end if;
  end if;
  if v_name='' then raise exception 'กรุณากรอกชื่อคอร์ส'; end if;

  if v_id is null then
    insert into public.legacy_student_course_history(
      student_id,course_id,tutor_id,course_name,tutor_name,academic_year,study_period,hours,status,note,source,created_by
    ) values(
      p_student_id,p_course_id,v_tutor_id,v_name,v_tutor_name,p_academic_year,nullif(trim(coalesce(p_study_period,'')),''),
      p_hours,p_status,nullif(trim(coalesce(p_note,'')),''),'manager',auth.uid()
    ) returning id into v_id;
  else
    update public.legacy_student_course_history set
      course_id=p_course_id,tutor_id=v_tutor_id,course_name=v_name,tutor_name=v_tutor_name,
      academic_year=p_academic_year,study_period=nullif(trim(coalesce(p_study_period,'')),''),
      hours=p_hours,status=p_status,note=nullif(trim(coalesce(p_note,'')),'')
    where id=v_id and student_id=p_student_id;
    if not found then raise exception 'Course history not found'; end if;
  end if;

  return jsonb_build_object('ok',true,'history_id',v_id);
end $$;
grant execute on function public.legacy_students_manager_upsert_course(uuid,uuid,uuid,text,text,integer,text,numeric,text,text) to authenticated;

create or replace function public.legacy_students_manager_delete_course(p_history_id uuid)
returns jsonb
language plpgsql security definer set search_path=public
as $$
begin
  if not public.is_manager() then raise exception 'Manager permission required'; end if;
  delete from public.legacy_student_course_history where id=p_history_id;
  return jsonb_build_object('ok',true);
end $$;
grant execute on function public.legacy_students_manager_delete_course(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- V22 lookup upgrade: include legacy course history in returning-student flow.
-- ---------------------------------------------------------------------------
create or replace function public.registration_lookup_returning_student(p_phone text)
returns jsonb
language plpgsql security definer set search_path=public
as $$
declare
  v_phone text:=public.registration_norm_phone(p_phone);
  v_student public.os_students%rowtype;
  v_latest public.enrollments%rowtype;
  v_history jsonb:='[]'::jsonb;
  v_fullname text;
begin
  if length(v_phone)<9 then return jsonb_build_object('found',false,'code','INVALID_PHONE'); end if;

  select * into v_student from public.os_students s
  where coalesce(s.phone_key,'')=v_phone or public.registration_norm_phone(s.phone)=v_phone
  order by coalesce(s.archived,false),s.created_at desc nulls last limit 1;

  select * into v_latest from public.enrollments e
  where public.registration_norm_phone(e.phone)=v_phone
  order by e.created_at desc limit 1;

  if v_student.id is null and v_latest.id is null then
    return jsonb_build_object('found',false,'code','NOT_FOUND');
  end if;

  with combined as (
    select
      h.id,h.course_name course,h.tutor_name tutor,
      coalesce(h.study_period,case when h.academic_year is not null then 'ปี '||h.academic_year::text else null end) date,
      h.created_at sort_at,'legacy'::text source
    from public.legacy_student_course_history h where h.student_id=v_student.id
    union all
    select e.id,e.course_text,e.tutor_text,to_char(e.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),
      e.created_at,'system'
    from public.enrollments e where public.registration_norm_phone(e.phone)=v_phone
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'course',course,'tutor',tutor,'date',date,'source',source
  ) order by sort_at desc),'[]'::jsonb)
  into v_history from (select * from combined order by sort_at desc limit 12) x;

  v_fullname:=coalesce(
    nullif(trim(concat_ws(' ',v_student.first_name,v_student.last_name)),''),
    nullif(v_student.display_name,''),v_latest.fullname,''
  );

  return jsonb_build_object(
    'found',true,
    'source',case when v_student.id is not null and v_latest.id is null then 'legacy_profile' else 'system' end,
    'legacyProfileId',v_student.id,
    'student',jsonb_build_object(
      'id',v_student.id,'studentCode',v_student.student_code,'fullname',v_fullname,'nickname',coalesce(v_student.nickname,v_latest.nickname),
      'phone',coalesce(v_student.phone,v_latest.phone,p_phone),'lineId',coalesce(v_student.line_id,v_latest.line_id),
      'email',coalesce(v_student.email,v_latest.email),'school',coalesce(v_student.school,v_latest.school),
      'grade',coalesce(v_student.grade,v_latest.grade),'faculty',coalesce(v_student.faculty,v_latest.faculty),
      'province',coalesce(v_student.province,v_latest.province),'legacyStudent',coalesce(v_student.legacy_student,false)
    ),
    'latest',case when v_latest.id is null then null else jsonb_build_object(
      'id',v_latest.id,'name',v_latest.fullname,'course',v_latest.course_text,'tutor',v_latest.tutor_text,
      'date',to_char(v_latest.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),'status',v_latest.status
    ) end,
    'history',v_history
  );
end $$;
grant execute on function public.registration_lookup_returning_student(text) to anon,authenticated;

notify pgrst,'reload schema';
commit;

-- Verification
select jsonb_build_object(
  'ok',true,
  'legacy_course_table',to_regclass('public.legacy_student_course_history') is not null,
  'manager_bootstrap',to_regprocedure('public.legacy_students_manager_bootstrap()') is not null,
  'student_detail',to_regprocedure('public.legacy_students_manager_student_detail(uuid)') is not null,
  'registration_lookup',to_regprocedure('public.registration_lookup_returning_student(text)') is not null
) as arewarin_v23_status;


-- ============================================================================
-- AreWarin V24 · GROUP CLASS / COHORT SYSTEM
-- Manager Group Class + Public registration + seats + attendance policy + recording
-- ============================================================================

begin;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- 0) Preflight
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.courses') is null then raise exception 'Missing public.courses'; end if;
  if to_regclass('public.tutors') is null then raise exception 'Missing public.tutors'; end if;
  if to_regclass('public.os_students') is null then raise exception 'Missing public.os_students'; end if;
  if to_regclass('public.os_student_course_enrollments') is null then raise exception 'Missing public.os_student_course_enrollments'; end if;
  if to_regclass('public.enrollments') is null then raise exception 'Missing public.enrollments'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- 1) Existing Tutor OS group master -> real public Group Class / Cohort
-- ---------------------------------------------------------------------------
create table if not exists public.os_student_groups (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid references public.tutors(id) on delete set null,
  course_id uuid references public.courses(id) on delete set null,
  group_code text,
  name text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.os_student_groups
  add column if not exists image_url text,
  add column if not exists description text,
  add column if not exists capacity integer not null default 12,
  add column if not exists price_amount numeric(12,2) not null default 0,
  add column if not exists included_hours numeric(10,2),
  add column if not exists included_sessions integer,
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists mode text not null default 'onsite',
  add column if not exists location text,
  add column if not exists enrollment_open boolean not null default false,
  add column if not exists public_visible boolean not null default false,
  add column if not exists status text not null default 'draft',
  add column if not exists absence_deduct_hours boolean not null default true,
  add column if not exists recording_on_absence boolean not null default true,
  add column if not exists recording_visibility text not null default 'absent_only',
  add column if not exists allow_promotions boolean not null default false,
  add column if not exists waitlist_enabled boolean not null default true,
  add column if not exists seat_hold_minutes integer not null default 1440,
  add column if not exists sort_order integer not null default 100,
  add column if not exists created_by uuid references auth.users(id) on delete set null;

create unique index if not exists os_student_groups_group_code_uidx
  on public.os_student_groups(group_code) where group_code is not null;
create index if not exists os_student_groups_public_idx
  on public.os_student_groups(course_id,public_visible,enrollment_open,status,is_active,sort_order);

-- Existing membership table remains the single group membership source.
create table if not exists public.os_student_group_members (
  group_id uuid not null references public.os_student_groups(id) on delete cascade,
  student_id uuid not null references public.os_students(id) on delete cascade,
  student_course_enrollment_id uuid references public.os_student_course_enrollments(id) on delete set null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  primary key(group_id,student_id)
);
alter table public.os_student_group_members add column if not exists active boolean not null default true;
alter table public.os_student_group_members add column if not exists created_at timestamptz not null default now();

-- Recurring weekly schedule owned by the cohort (not tutor availability).
create table if not exists public.os_student_group_schedules (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.os_student_groups(id) on delete cascade,
  weekday smallint not null check(weekday between 1 and 7),
  start_time time not null,
  end_time time not null,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(end_time > start_time)
);
create unique index if not exists os_student_group_schedules_uidx
  on public.os_student_group_schedules(group_id,weekday,start_time,end_time);

-- Seat lifecycle. Confirmed reservations become os_student_group_members.
create table if not exists public.os_student_group_reservations (
  id uuid primary key default gen_random_uuid(),
  reservation_token uuid not null default gen_random_uuid(),
  group_id uuid not null references public.os_student_groups(id) on delete cascade,
  enrollment_id uuid references public.enrollments(id) on delete cascade,
  student_id uuid references public.os_students(id) on delete set null,
  phone_key text,
  fullname text,
  seats integer not null default 1 check(seats between 1 and 20),
  status text not null default 'held' check(status in ('held','pending_payment','confirmed','cancelled','expired','waitlist')),
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(reservation_token)
);
create unique index if not exists os_group_reservation_enrollment_uidx on public.os_student_group_reservations(group_id,enrollment_id) where enrollment_id is not null;
create index if not exists os_group_reservation_capacity_idx on public.os_student_group_reservations(group_id,status,expires_at);

-- Recording attached to an actual group attendance session.
create table if not exists public.os_student_group_recordings (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.os_student_groups(id) on delete cascade,
  session_id uuid references public.os_attendance_sessions(id) on delete set null,
  title text,
  video_url text not null,
  visibility text not null default 'absent_only' check(visibility in ('absent_only','all_members')),
  note text,
  active boolean not null default true,
  published_at timestamptz not null default now(),
  expires_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists os_group_recordings_group_idx on public.os_student_group_recordings(group_id,published_at desc);

-- ---------------------------------------------------------------------------
-- 2) RLS
-- ---------------------------------------------------------------------------
alter table public.os_student_groups enable row level security;
alter table public.os_student_group_members enable row level security;
alter table public.os_student_group_schedules enable row level security;
alter table public.os_student_group_reservations enable row level security;
alter table public.os_student_group_recordings enable row level security;

drop policy if exists "manager group class master v24" on public.os_student_groups;
create policy "manager group class master v24" on public.os_student_groups for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager group class members v24" on public.os_student_group_members;
create policy "manager group class members v24" on public.os_student_group_members for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager group class schedules v24" on public.os_student_group_schedules;
create policy "manager group class schedules v24" on public.os_student_group_schedules for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager group class reservations v24" on public.os_student_group_reservations;
create policy "manager group class reservations v24" on public.os_student_group_reservations for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager group class recordings v24" on public.os_student_group_recordings;
create policy "manager group class recordings v24" on public.os_student_group_recordings for all to authenticated using(public.is_manager()) with check(public.is_manager());

-- Tutor can read own class master/schedules/members/recordings when tutor mapping exists.
do $$
begin
  if to_regprocedure('public.tutor_os_current_tutor_id()') is not null then
    if not exists(select 1 from pg_policies where schemaname='public' and tablename='os_student_groups' and policyname='tutor own group class v24') then
      execute 'create policy "tutor own group class v24" on public.os_student_groups for select to authenticated using(tutor_id=public.tutor_os_current_tutor_id() or public.is_manager())';
    end if;
    if not exists(select 1 from pg_policies where schemaname='public' and tablename='os_student_group_schedules' and policyname='tutor own group schedules v24') then
      execute 'create policy "tutor own group schedules v24" on public.os_student_group_schedules for select to authenticated using(exists(select 1 from public.os_student_groups g where g.id=group_id and (g.tutor_id=public.tutor_os_current_tutor_id() or public.is_manager())))';
    end if;
    if not exists(select 1 from pg_policies where schemaname='public' and tablename='os_student_group_members' and policyname='tutor own group members v24') then
      execute 'create policy "tutor own group members v24" on public.os_student_group_members for select to authenticated using(exists(select 1 from public.os_student_groups g where g.id=group_id and (g.tutor_id=public.tutor_os_current_tutor_id() or public.is_manager())))';
    end if;
    if not exists(select 1 from pg_policies where schemaname='public' and tablename='os_student_group_recordings' and policyname='tutor own group recordings v24') then
      execute 'create policy "tutor own group recordings v24" on public.os_student_group_recordings for all to authenticated using(exists(select 1 from public.os_student_groups g where g.id=group_id and (g.tutor_id=public.tutor_os_current_tutor_id() or public.is_manager()))) with check(exists(select 1 from public.os_student_groups g where g.id=group_id and (g.tutor_id=public.tutor_os_current_tutor_id() or public.is_manager())))';
    end if;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 3) Seat helpers
-- ---------------------------------------------------------------------------
create or replace function public.group_class_used_seats(p_group_id uuid)
returns integer language sql stable security definer set search_path=public as $$
  select
    coalesce((select sum(r.seats)::integer from public.os_student_group_reservations r
      where r.group_id=p_group_id
        and r.status in ('held','pending_payment','confirmed')
        and (r.status='confirmed' or r.expires_at is null or r.expires_at>now())),0)
    +
    coalesce((select count(*)::integer from public.os_student_group_members m
      where m.group_id=p_group_id and m.active=true
        and not exists(select 1 from public.os_student_group_reservations r
          where r.group_id=m.group_id and r.student_id=m.student_id
            and r.status in ('held','pending_payment','confirmed')
            and (r.status='confirmed' or r.expires_at is null or r.expires_at>now()))),0)
$$;

create or replace function public.group_class_remaining_seats(p_group_id uuid)
returns integer language sql stable security definer set search_path=public as $$
  select greatest(coalesce(g.capacity,0)-public.group_class_used_seats(g.id),0)
  from public.os_student_groups g where g.id=p_group_id
$$;

create or replace function public.group_class_refresh_status(p_group_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_remaining integer; v_status text;
begin
  select status into v_status from public.os_student_groups where id=p_group_id;
  if not found then return; end if;
  v_remaining:=public.group_class_remaining_seats(p_group_id);
  if v_status in ('open','full') then
    update public.os_student_groups set status=case when v_remaining<=0 then 'full' else 'open' end,updated_at=now() where id=p_group_id;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- 4) Public registration feed: no student/member PII
-- ---------------------------------------------------------------------------
create or replace function public.public_group_classes_for_course(p_course_id uuid)
returns jsonb language sql stable security definer set search_path=public as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',g.id,'group_code',g.group_code,'name',g.name,'course_id',g.course_id,'course_name',c.name,
    'tutor_id',g.tutor_id,'tutor_name',t.display_name,'image_url',g.image_url,'description',g.description,
    'capacity',g.capacity,'seats_taken',public.group_class_used_seats(g.id),'remaining_seats',public.group_class_remaining_seats(g.id),
    'price_amount',g.price_amount,'included_hours',g.included_hours,'included_sessions',g.included_sessions,
    'start_date',g.start_date,'end_date',g.end_date,'mode',g.mode,'location',g.location,
    'absence_deduct_hours',g.absence_deduct_hours,'recording_on_absence',g.recording_on_absence,'recording_visibility',g.recording_visibility,
    'allow_promotions',g.allow_promotions,'waitlist_enabled',g.waitlist_enabled,
    'status',case when public.group_class_remaining_seats(g.id)<=0 then 'full' else g.status end,
    'schedules',coalesce((select jsonb_agg(jsonb_build_object('weekday',s.weekday,'start_time',to_char(s.start_time,'HH24:MI'),'end_time',to_char(s.end_time,'HH24:MI')) order by s.weekday,s.start_time) from public.os_student_group_schedules s where s.group_id=g.id and s.active=true),'[]'::jsonb)
  ) order by g.sort_order,g.start_date,g.name),'[]'::jsonb)
  from public.os_student_groups g
  join public.courses c on c.id=g.course_id
  left join public.tutors t on t.id=g.tutor_id
  where g.course_id=p_course_id and g.is_active=true and g.public_visible=true and g.enrollment_open=true
    and g.status in ('open','full') and (g.end_date is null or g.end_date>=current_date)
$$;
grant execute on function public.public_group_classes_for_course(uuid) to anon,authenticated;

-- ---------------------------------------------------------------------------
-- 5) Manager RPCs
-- ---------------------------------------------------------------------------
create or replace function public.manager_group_class_bootstrap()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_classes jsonb;v_courses jsonb;v_tutors jsonb;v_summary jsonb;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
   'id',g.id,'group_code',g.group_code,'name',g.name,'course_id',g.course_id,'course_name',c.name,'tutor_id',g.tutor_id,'tutor_name',t.display_name,
   'image_url',g.image_url,'description',g.description,'capacity',g.capacity,'price_amount',g.price_amount,'included_hours',g.included_hours,'included_sessions',g.included_sessions,
   'start_date',g.start_date,'end_date',g.end_date,'mode',g.mode,'location',g.location,'enrollment_open',g.enrollment_open,'public_visible',g.public_visible,'status',g.status,
   'absence_deduct_hours',g.absence_deduct_hours,'recording_on_absence',g.recording_on_absence,'recording_visibility',g.recording_visibility,'allow_promotions',g.allow_promotions,'waitlist_enabled',g.waitlist_enabled,'seat_hold_minutes',g.seat_hold_minutes,'sort_order',g.sort_order,
   'seats_taken',public.group_class_used_seats(g.id),'remaining_seats',public.group_class_remaining_seats(g.id),
   'schedules',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'weekday',s.weekday,'start_time',to_char(s.start_time,'HH24:MI'),'end_time',to_char(s.end_time,'HH24:MI')) order by s.weekday,s.start_time) from public.os_student_group_schedules s where s.group_id=g.id and s.active=true),'[]'::jsonb)
 ) order by g.is_active desc,g.sort_order,g.created_at desc),'[]'::jsonb)
 into v_classes from public.os_student_groups g left join public.courses c on c.id=g.course_id left join public.tutors t on t.id=g.tutor_id where g.is_active=true;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'tutor_id',c.tutor_id) order by c.name),'[]'::jsonb) into v_courses from public.courses c where coalesce(c.active,true)=true;
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'name',t.display_name) order by t.sort_order,t.display_name),'[]'::jsonb) into v_tutors from public.tutors t where coalesce(t.active,true)=true;
 select jsonb_build_object(
   'open_classes',(select count(*) from public.os_student_groups g where g.is_active=true and g.status='open' and g.enrollment_open=true),
   'full_classes',(select count(*) from public.os_student_groups g where g.is_active=true and (g.status='full' or public.group_class_remaining_seats(g.id)<=0)),
   'total_members',(select count(*) from public.os_student_group_members m where m.active=true),
   'remaining_seats',(select coalesce(sum(public.group_class_remaining_seats(g.id)),0) from public.os_student_groups g where g.is_active=true and g.status in ('open','full'))
 ) into v_summary;
 return jsonb_build_object('classes',v_classes,'courses',v_courses,'tutors',v_tutors,'summary',v_summary);
end $$;
grant execute on function public.manager_group_class_bootstrap() to authenticated;

create or replace function public.manager_group_class_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_course uuid;v_tutor uuid;v_row jsonb;v_code text;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 v_id:=nullif(p_payload->>'id','')::uuid;v_course:=nullif(p_payload->>'course_id','')::uuid;v_tutor:=nullif(p_payload->>'tutor_id','')::uuid;
 if v_course is null or not exists(select 1 from public.courses where id=v_course) then raise exception 'Course not found'; end if;
 if v_tutor is null or not exists(select 1 from public.tutors where id=v_tutor) then raise exception 'Tutor not found'; end if;
 if trim(coalesce(p_payload->>'name',''))='' then raise exception 'กรุณากรอกชื่อคลาส'; end if;
 v_code:=nullif(trim(coalesce(p_payload->>'group_code','')),'');if v_code is null then v_code:='GC-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,7));end if;
 if v_id is null then
  insert into public.os_student_groups(tutor_id,course_id,group_code,name,is_active,image_url,description,capacity,price_amount,included_hours,included_sessions,start_date,end_date,mode,location,enrollment_open,public_visible,status,absence_deduct_hours,recording_on_absence,recording_visibility,allow_promotions,waitlist_enabled,seat_hold_minutes,sort_order,created_by)
  values(v_tutor,v_course,v_code,p_payload->>'name',true,nullif(p_payload->>'image_url',''),nullif(p_payload->>'description',''),greatest(1,coalesce((p_payload->>'capacity')::int,12)),greatest(0,coalesce((p_payload->>'price_amount')::numeric,0)),nullif(p_payload->>'included_hours','')::numeric,nullif(p_payload->>'included_sessions','')::int,nullif(p_payload->>'start_date','')::date,nullif(p_payload->>'end_date','')::date,coalesce(nullif(p_payload->>'mode',''),'onsite'),nullif(p_payload->>'location',''),coalesce((p_payload->>'enrollment_open')::boolean,false),coalesce((p_payload->>'public_visible')::boolean,false),coalesce(nullif(p_payload->>'status',''),'draft'),coalesce((p_payload->>'absence_deduct_hours')::boolean,true),coalesce((p_payload->>'recording_on_absence')::boolean,true),coalesce(nullif(p_payload->>'recording_visibility',''),'absent_only'),coalesce((p_payload->>'allow_promotions')::boolean,false),coalesce((p_payload->>'waitlist_enabled')::boolean,true),greatest(15,coalesce((p_payload->>'seat_hold_minutes')::int,1440)),coalesce((p_payload->>'sort_order')::int,100),auth.uid()) returning id into v_id;
 else
  update public.os_student_groups set tutor_id=v_tutor,course_id=v_course,group_code=v_code,name=p_payload->>'name',image_url=nullif(p_payload->>'image_url',''),description=nullif(p_payload->>'description',''),capacity=greatest(1,coalesce((p_payload->>'capacity')::int,capacity)),price_amount=greatest(0,coalesce((p_payload->>'price_amount')::numeric,price_amount)),included_hours=nullif(p_payload->>'included_hours','')::numeric,included_sessions=nullif(p_payload->>'included_sessions','')::int,start_date=nullif(p_payload->>'start_date','')::date,end_date=nullif(p_payload->>'end_date','')::date,mode=coalesce(nullif(p_payload->>'mode',''),'onsite'),location=nullif(p_payload->>'location',''),enrollment_open=coalesce((p_payload->>'enrollment_open')::boolean,false),public_visible=coalesce((p_payload->>'public_visible')::boolean,false),status=coalesce(nullif(p_payload->>'status',''),status),absence_deduct_hours=coalesce((p_payload->>'absence_deduct_hours')::boolean,true),recording_on_absence=coalesce((p_payload->>'recording_on_absence')::boolean,true),recording_visibility=coalesce(nullif(p_payload->>'recording_visibility',''),'absent_only'),allow_promotions=coalesce((p_payload->>'allow_promotions')::boolean,false),waitlist_enabled=coalesce((p_payload->>'waitlist_enabled')::boolean,true),seat_hold_minutes=greatest(15,coalesce((p_payload->>'seat_hold_minutes')::int,seat_hold_minutes)),sort_order=coalesce((p_payload->>'sort_order')::int,sort_order),updated_at=now() where id=v_id;
  if not found then raise exception 'Group class not found'; end if;
 end if;
 delete from public.os_student_group_schedules where group_id=v_id;
 for v_row in select * from jsonb_array_elements(coalesce(p_payload->'schedules','[]'::jsonb)) loop
   if coalesce(v_row->>'start_time','')<>'' and coalesce(v_row->>'end_time','')<>'' then
    insert into public.os_student_group_schedules(group_id,weekday,start_time,end_time,active) values(v_id,greatest(1,least(7,(v_row->>'weekday')::int)),(v_row->>'start_time')::time,(v_row->>'end_time')::time,true);
   end if;
 end loop;
 perform public.group_class_refresh_status(v_id);
 return jsonb_build_object('ok',true,'group_id',v_id,'group_code',v_code);
end $$;
grant execute on function public.manager_group_class_save(jsonb) to authenticated;

create or replace function public.manager_group_class_duplicate(p_group_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare g public.os_student_groups%rowtype;v_new uuid;v_code text;
begin
 if not public.is_manager() then raise exception 'Manager permission required';end if;
 select * into g from public.os_student_groups where id=p_group_id;if not found then raise exception 'Group class not found';end if;
 v_code:=coalesce(g.group_code,'GC')||'-COPY-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,4));
 insert into public.os_student_groups(tutor_id,course_id,group_code,name,is_active,image_url,description,capacity,price_amount,included_hours,included_sessions,start_date,end_date,mode,location,enrollment_open,public_visible,status,absence_deduct_hours,recording_on_absence,recording_visibility,allow_promotions,waitlist_enabled,seat_hold_minutes,sort_order,created_by)
 values(g.tutor_id,g.course_id,v_code,g.name||' · Copy',true,g.image_url,g.description,g.capacity,g.price_amount,g.included_hours,g.included_sessions,g.start_date,g.end_date,g.mode,g.location,false,false,'draft',g.absence_deduct_hours,g.recording_on_absence,g.recording_visibility,g.allow_promotions,g.waitlist_enabled,g.seat_hold_minutes,g.sort_order,auth.uid()) returning id into v_new;
 insert into public.os_student_group_schedules(group_id,weekday,start_time,end_time,active,sort_order) select v_new,weekday,start_time,end_time,active,sort_order from public.os_student_group_schedules where group_id=p_group_id;
 return jsonb_build_object('ok',true,'group_id',v_new);
end $$;
grant execute on function public.manager_group_class_duplicate(uuid) to authenticated;

create or replace function public.manager_group_class_students(p_group_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_members jsonb;v_res jsonb;
begin
 if not public.is_manager() then raise exception 'Manager permission required';end if;
 select coalesce(jsonb_agg(jsonb_build_object('student_id',s.id,'student_code',s.student_code,'display_name',s.display_name,'fullname',trim(concat_ws(' ',s.first_name,s.last_name)),'nickname',s.nickname,'phone',s.phone,'school',s.school,'grade',s.grade,'student_course_enrollment_id',m.student_course_enrollment_id) order by coalesce(s.nickname,s.display_name)),'[]'::jsonb) into v_members from public.os_student_group_members m join public.os_students s on s.id=m.student_id where m.group_id=p_group_id and m.active=true;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'enrollment_id',r.enrollment_id,'student_id',r.student_id,'phone_key',r.phone_key,'fullname',r.fullname,'seats',r.seats,'status',r.status,'expires_at',r.expires_at,'created_at',r.created_at) order by r.created_at desc),'[]'::jsonb) into v_res from public.os_student_group_reservations r where r.group_id=p_group_id and r.status not in ('cancelled','expired');
 return jsonb_build_object('members',v_members,'reservations',v_res);
end $$;
grant execute on function public.manager_group_class_students(uuid) to authenticated;

create or replace function public.manager_group_class_search_students(p_group_id uuid,p_query text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_course uuid;v_q text:='%'||lower(trim(coalesce(p_query,'')))||'%';v_rows jsonb;
begin
 if not public.is_manager() then raise exception 'Manager permission required';end if;
 select course_id into v_course from public.os_student_groups where id=p_group_id;if v_course is null then raise exception 'Group class not found';end if;
 select coalesce(jsonb_agg(x.obj),'[]'::jsonb) into v_rows from (
  select jsonb_build_object('id',s.id,'student_code',s.student_code,'display_name',s.display_name,'fullname',trim(concat_ws(' ',s.first_name,s.last_name)),'nickname',s.nickname,'phone',s.phone,'school',s.school,'grade',s.grade,'student_course_enrollment_id',ce.id) obj
  from public.os_students s left join lateral(select e.id from public.os_student_course_enrollments e where e.student_id=s.id and e.course_id=v_course and e.status='active' order by (e.hour_pool_id is not null) desc,e.updated_at desc limit 1) ce on true
  where coalesce(s.archived,false)=false and (lower(coalesce(s.student_code,'')) like v_q or lower(coalesce(s.display_name,'')) like v_q or lower(coalesce(s.nickname,'')) like v_q or lower(coalesce(s.phone,'')) like v_q or lower(coalesce(s.school,'')) like v_q or lower(trim(concat_ws(' ',s.first_name,s.last_name))) like v_q)
  order by coalesce(s.nickname,s.display_name) limit 30
 )x;
 return v_rows;
end $$;
grant execute on function public.manager_group_class_search_students(uuid,text) to authenticated;

create or replace function public.manager_group_class_add_student(p_group_id uuid,p_student_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare g public.os_student_groups%rowtype;v_sce uuid;v_used integer;v_warning text;
begin
 if not public.is_manager() then raise exception 'Manager permission required';end if;
 select * into g from public.os_student_groups where id=p_group_id for update;if not found then raise exception 'Group class not found';end if;
 if exists(select 1 from public.os_student_group_members where group_id=p_group_id and student_id=p_student_id and active=true) then return jsonb_build_object('ok',true,'already_member',true);end if;
 v_used:=public.group_class_used_seats(p_group_id);if v_used>=g.capacity then raise exception 'คลาสเต็มแล้ว';end if;
 select id into v_sce from public.os_student_course_enrollments where student_id=p_student_id and course_id=g.course_id and status='active' order by (hour_pool_id is not null) desc,updated_at desc limit 1;
 insert into public.os_student_group_members(group_id,student_id,student_course_enrollment_id,active) values(p_group_id,p_student_id,v_sce,true) on conflict(group_id,student_id) do update set student_course_enrollment_id=coalesce(excluded.student_course_enrollment_id,os_student_group_members.student_course_enrollment_id),active=true;
 if v_sce is null then v_warning:='เพิ่มเข้าคลาสแล้ว แต่ยังไม่มี Course Wallet ของคอร์สนี้ จึงยังตัดชั่วโมงอัตโนมัติไม่ได้';end if;
 perform public.group_class_refresh_status(p_group_id);return jsonb_build_object('ok',true,'student_course_enrollment_id',v_sce,'warning',v_warning);
end $$;
grant execute on function public.manager_group_class_add_student(uuid,uuid) to authenticated;

create or replace function public.manager_group_class_remove_student(p_group_id uuid,p_student_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin if not public.is_manager() then raise exception 'Manager permission required';end if;update public.os_student_group_members set active=false where group_id=p_group_id and student_id=p_student_id;perform public.group_class_refresh_status(p_group_id);return jsonb_build_object('ok',true);end $$;
grant execute on function public.manager_group_class_remove_student(uuid,uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 6) Atomic seat hold. Service-role only; public browser cannot bypass price/capacity.
-- ---------------------------------------------------------------------------
create or replace function public.group_class_create_hold(p_group_id uuid,p_phone text,p_fullname text default null,p_seats integer default 1)
returns jsonb language plpgsql security definer set search_path=public as $$
declare g public.os_student_groups%rowtype;v_used integer;v_id uuid;v_phone text:=regexp_replace(coalesce(p_phone,''),'\D','','g');v_seats integer:=greatest(1,least(20,coalesce(p_seats,1)));v_exp timestamptz;
begin
 select * into g from public.os_student_groups where id=p_group_id for update;if not found then raise exception 'ไม่พบคลาสกลุ่ม';end if;
 update public.os_student_group_reservations set status='expired',updated_at=now() where group_id=p_group_id and status in ('held','pending_payment') and expires_at is not null and expires_at<=now();
 if not g.is_active or not g.enrollment_open or not g.public_visible or g.status not in ('open','full') then raise exception 'คลาสนี้ยังไม่เปิดรับสมัคร';end if;
 if g.end_date is not null and g.end_date<current_date then raise exception 'คลาสนี้สิ้นสุดแล้ว';end if;
 if exists(select 1 from public.os_student_group_reservations r where r.group_id=p_group_id and r.phone_key=v_phone and r.status in ('held','pending_payment','confirmed') and (r.status='confirmed' or r.expires_at is null or r.expires_at>now())) then raise exception 'เบอร์นี้มีการจองคลาสนี้อยู่แล้ว';end if;
 v_used:=public.group_class_used_seats(p_group_id);if v_used+v_seats>g.capacity then raise exception 'คลาสเต็มแล้วหรือที่นั่งไม่เพียงพอ';end if;
 v_exp:=now()+make_interval(mins=>greatest(15,g.seat_hold_minutes));
 insert into public.os_student_group_reservations(group_id,phone_key,fullname,seats,status,expires_at) values(p_group_id,v_phone,nullif(trim(coalesce(p_fullname,'')),''),v_seats,'held',v_exp) returning id into v_id;
 perform public.group_class_refresh_status(p_group_id);
 return jsonb_build_object('ok',true,'reservation_id',v_id,'expires_at',v_exp,'price_amount',g.price_amount,'allow_promotions',g.allow_promotions,'course_id',g.course_id,'tutor_id',g.tutor_id,'included_hours',g.included_hours,'included_sessions',g.included_sessions);
end $$;
revoke all on function public.group_class_create_hold(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.group_class_create_hold(uuid,text,text,integer) to service_role;

create or replace function public.group_class_attach_hold(p_reservation_id uuid,p_enrollment_id uuid)
returns void language plpgsql security definer set search_path=public as $$
begin update public.os_student_group_reservations set enrollment_id=p_enrollment_id,status='pending_payment',expires_at=null,updated_at=now() where id=p_reservation_id and status='held';if not found then raise exception 'Seat reservation is no longer active';end if;end $$;
revoke all on function public.group_class_attach_hold(uuid,uuid) from public,anon,authenticated;grant execute on function public.group_class_attach_hold(uuid,uuid) to service_role;

create or replace function public.group_class_cancel_hold(p_reservation_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_group uuid;begin update public.os_student_group_reservations set status='cancelled',updated_at=now() where id=p_reservation_id returning group_id into v_group;if v_group is not null then perform public.group_class_refresh_status(v_group);end if;end $$;
revoke all on function public.group_class_cancel_hold(uuid) from public,anon,authenticated;grant execute on function public.group_class_cancel_hold(uuid) to service_role;

-- ---------------------------------------------------------------------------
-- 7) Confirmed enrollment -> group member. Cancel/reject -> release seat.
-- ---------------------------------------------------------------------------
create or replace function public.group_class_enrollment_status_sync()
returns trigger language plpgsql security definer set search_path=public as $$
declare r public.os_student_group_reservations%rowtype;g public.os_student_groups%rowtype;v_student uuid;v_sce uuid;
begin
 if new.status is not distinct from old.status then return new;end if;
 select * into r from public.os_student_group_reservations where enrollment_id=new.id limit 1;if not found then return new;end if;
 select * into g from public.os_student_groups where id=r.group_id;
 if new.status='confirmed' then
   if to_regprocedure('public.tutor_os_sync_core_enrollment(uuid)') is not null then begin execute 'select public.tutor_os_sync_core_enrollment($1)' using new.id;exception when others then null;end;end if;
   select id into v_student from public.os_students where source_enrollment_id=new.id or phone_key=regexp_replace(coalesce(new.phone,''),'\D','','g') order by (source_enrollment_id=new.id) desc,created_at desc limit 1;
   if v_student is not null then select id into v_sce from public.os_student_course_enrollments where student_id=v_student and course_id=g.course_id and (source_enrollment_id=new.id or status='active') order by (source_enrollment_id=new.id) desc,updated_at desc limit 1;end if;
   update public.os_student_group_reservations set status='confirmed',expires_at=null,student_id=v_student,updated_at=now() where id=r.id;
   if v_student is not null then insert into public.os_student_group_members(group_id,student_id,student_course_enrollment_id,active) values(g.id,v_student,v_sce,true) on conflict(group_id,student_id) do update set student_course_enrollment_id=coalesce(excluded.student_course_enrollment_id,os_student_group_members.student_course_enrollment_id),active=true;end if;
 elsif new.status in ('cancelled','rejected') then
   update public.os_student_group_reservations set status='cancelled',updated_at=now() where id=r.id;
   if r.student_id is not null then update public.os_student_group_members set active=false where group_id=r.group_id and student_id=r.student_id;end if;
 end if;
 perform public.group_class_refresh_status(r.group_id);return new;
end $$;
drop trigger if exists trg_group_class_enrollment_status_sync on public.enrollments;
create trigger trg_group_class_enrollment_status_sync after update of status on public.enrollments for each row execute function public.group_class_enrollment_status_sync();

-- ---------------------------------------------------------------------------
-- 8) Recording publish helper (Manager/Tutor)
-- ---------------------------------------------------------------------------
create or replace function public.group_class_save_recording(p_group_id uuid,p_session_id uuid,p_video_url text,p_title text default null,p_note text default null,p_visibility text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare g public.os_student_groups%rowtype;v_tutor uuid;v_id uuid;
begin
 select * into g from public.os_student_groups where id=p_group_id;if not found then raise exception 'Group class not found';end if;
 if not public.is_manager() then
   if to_regprocedure('public.tutor_os_current_tutor_id()') is null then raise exception 'Tutor permission required';end if;
   execute 'select public.tutor_os_current_tutor_id()' into v_tutor;if v_tutor is distinct from g.tutor_id then raise exception 'Tutor permission required';end if;
 end if;
 if trim(coalesce(p_video_url,''))='' then raise exception 'กรุณาใส่ URL วิดีโอ';end if;
 insert into public.os_student_group_recordings(group_id,session_id,title,video_url,visibility,note,created_by) values(p_group_id,p_session_id,nullif(trim(coalesce(p_title,'')),''),trim(p_video_url),coalesce(nullif(p_visibility,''),g.recording_visibility),nullif(trim(coalesce(p_note,'')),''),auth.uid()) returning id into v_id;
 return jsonb_build_object('ok',true,'recording_id',v_id);
end $$;
grant execute on function public.group_class_save_recording(uuid,uuid,text,text,text,text) to authenticated;


-- ---------------------------------------------------------------------------
-- 9) Tutor Group Class teaching: attendance + hour deduction + recording
-- ---------------------------------------------------------------------------
create or replace function public.tutor_group_class_detail(p_group_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  g public.os_student_groups%rowtype;
  v_tutor uuid;
  v_course_tutor uuid;
  v_members jsonb;
  v_sessions jsonb;
  v_recordings jsonb;
  v_schedules jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select * into g from public.os_student_groups where id=p_group_id;
  if not found then raise exception 'Group class not found'; end if;

  if not public.is_manager() then
    if to_regprocedure('public.tutor_os_current_tutor_id()') is null then raise exception 'Tutor permission required'; end if;
    execute 'select public.tutor_os_current_tutor_id()' into v_tutor;
    select tutor_id into v_course_tutor from public.courses where id=g.course_id;
    if v_tutor is null or (v_tutor is distinct from g.tutor_id and v_tutor is distinct from v_course_tutor) then
      raise exception 'Tutor permission required';
    end if;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'student_id',s.id,'student_code',s.student_code,'display_name',s.display_name,
    'fullname',trim(concat_ws(' ',s.first_name,s.last_name)),'nickname',s.nickname,
    'phone',s.phone,'school',s.school,'grade',s.grade,
    'student_course_enrollment_id',m.student_course_enrollment_id,
    'hour_pool_id',ce.hour_pool_id,
    'hours_total',ce.hours_total,'hours_used',ce.hours_used,
    'hours_unlimited',coalesce(ce.hours_unlimited,false),
    'remaining_hours',case when coalesce(ce.hours_unlimited,false) then null else greatest(coalesce(ce.hours_total,0)-coalesce(ce.hours_used,0),0) end
  ) order by coalesce(s.nickname,s.display_name,s.first_name)),'[]'::jsonb)
  into v_members
  from public.os_student_group_members m
  join public.os_students s on s.id=m.student_id
  left join public.os_student_course_enrollments ce on ce.id=m.student_course_enrollment_id
  where m.group_id=p_group_id and m.active=true;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'session_date',x.session_date,'start_time',x.start_time,'end_time',x.end_time,
    'title',x.title,'note',x.note,'actual_start_at',x.actual_start_at,'actual_end_at',x.actual_end_at,
    'duration_minutes',x.duration_minutes,'billable_hours',x.billable_hours,'status',x.status
  ) order by x.session_date desc,x.actual_start_at desc nulls last),'[]'::jsonb)
  into v_sessions
  from (select * from public.os_attendance_sessions where group_id=p_group_id order by session_date desc,created_at desc limit 30) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'session_id',x.session_id,'title',x.title,'video_url',x.video_url,
    'visibility',x.visibility,'note',x.note,'published_at',x.published_at,'active',x.active
  ) order by x.published_at desc),'[]'::jsonb)
  into v_recordings
  from (select * from public.os_student_group_recordings where group_id=p_group_id and active=true order by published_at desc limit 30) x;

  select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'weekday',s.weekday,'start_time',to_char(s.start_time,'HH24:MI'),'end_time',to_char(s.end_time,'HH24:MI')) order by s.weekday,s.start_time),'[]'::jsonb)
  into v_schedules from public.os_student_group_schedules s where s.group_id=p_group_id and s.active=true;

  return jsonb_build_object('group',to_jsonb(g),'members',v_members,'sessions',v_sessions,'recordings',v_recordings,'schedules',v_schedules);
end $$;
revoke all on function public.tutor_group_class_detail(uuid) from public;
grant execute on function public.tutor_group_class_detail(uuid) to authenticated;

create or replace function public.tutor_group_class_complete_lesson(
  p_group_id uuid,
  p_start_at timestamptz,
  p_end_at timestamptz,
  p_title text default null,
  p_note text default null,
  p_attendance jsonb default '[]'::jsonb,
  p_video_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  g public.os_student_groups%rowtype;
  v_tutor uuid;
  v_course_tutor uuid;
  v_session uuid;
  v_minutes integer;
  v_hours numeric(10,2);
  v_any_deduct boolean:=false;
  v_deducted_count integer:=0;
  v_absent_count integer:=0;
  v_warning_count integer:=0;
  v_warnings jsonb:='[]'::jsonb;
  m record;
  ce public.os_student_course_enrollments%rowtype;
  pool public.os_hour_pools%rowtype;
  v_status text;
  v_should_deduct boolean;
  v_deduct numeric(10,2);
  v_recording uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_start_at is null or p_end_at is null or p_end_at<=p_start_at then raise exception 'End time must be after start time'; end if;

  select * into g from public.os_student_groups where id=p_group_id and is_active=true;
  if not found then raise exception 'Group class not found'; end if;

  if not public.is_manager() then
    if to_regprocedure('public.tutor_os_current_tutor_id()') is null then raise exception 'Tutor permission required'; end if;
    execute 'select public.tutor_os_current_tutor_id()' into v_tutor;
    select tutor_id into v_course_tutor from public.courses where id=g.course_id;
    if v_tutor is null or (v_tutor is distinct from g.tutor_id and v_tutor is distinct from v_course_tutor) then raise exception 'Tutor permission required'; end if;
  end if;

  v_minutes:=greatest(0,floor(extract(epoch from (p_end_at-p_start_at))/60)::integer);
  v_hours:=greatest(0.25,round((v_minutes::numeric/60.0)*4.0)/4.0);

  insert into public.os_attendance_sessions(
    course_id,tutor_id,session_date,start_time,end_time,title,mode,location,status,note,created_by,
    actual_start_at,actual_end_at,duration_minutes,billable_hours,duration_source,
    deduction_status,deducted_at,deducted_by,deduction_note,group_id
  ) values(
    g.course_id,g.tutor_id,(p_start_at at time zone 'Asia/Bangkok')::date,
    (p_start_at at time zone 'Asia/Bangkok')::time,(p_end_at at time zone 'Asia/Bangkok')::time,
    coalesce(nullif(trim(p_title),''),g.name,'คลาสกลุ่ม'),g.mode,g.location,'completed',nullif(trim(p_note),''),auth.uid(),
    p_start_at,p_end_at,v_minutes,v_hours,'manual','not_deducted',null,null,'Group Class V24',g.id
  ) returning id into v_session;

  for m in
    select gm.student_id,gm.student_course_enrollment_id,s.display_name,s.nickname
    from public.os_student_group_members gm
    join public.os_students s on s.id=gm.student_id
    where gm.group_id=g.id and gm.active=true
    order by coalesce(s.nickname,s.display_name)
  loop
    select lower(coalesce(nullif(x->>'status',''),'present')) into v_status
    from jsonb_array_elements(coalesce(p_attendance,'[]'::jsonb)) x
    where x->>'student_id'=m.student_id::text limit 1;
    v_status:=coalesce(v_status,'present');
    if v_status not in ('present','late','absent','leave') then v_status:='present'; end if;
    if v_status='absent' then v_absent_count:=v_absent_count+1; end if;

    v_should_deduct:=v_status in ('present','late') or (v_status='absent' and g.absence_deduct_hours);
    v_deduct:=case when v_should_deduct then v_hours else 0 end;
    ce:=null; pool:=null;

    if v_should_deduct then
      if m.student_course_enrollment_id is not null then
        select * into ce from public.os_student_course_enrollments where id=m.student_course_enrollment_id and student_id=m.student_id;
      end if;
      if ce.id is null then
        select * into ce from public.os_student_course_enrollments
        where student_id=m.student_id and course_id=g.course_id and status in ('active','paused')
        order by (hour_pool_id is not null) desc,updated_at desc limit 1;
        if ce.id is not null then update public.os_student_group_members set student_course_enrollment_id=ce.id where group_id=g.id and student_id=m.student_id; end if;
      end if;

      if ce.id is null then
        v_deduct:=0;v_warning_count:=v_warning_count+1;
        v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('student_id',m.student_id,'student',coalesce(m.nickname,m.display_name),'warning','ไม่พบ Course Wallet'));
      else
        if ce.hour_pool_id is not null then
          select * into pool from public.os_hour_pools where id=ce.hour_pool_id for update;
        else
          select p.* into pool from public.os_hour_pools p
          where p.student_id=ce.student_id
            and ((ce.source_enrollment_id is not null and p.source_enrollment_id=ce.source_enrollment_id) or p.pool_key='shared')
            and p.status in ('active','paused','pending')
          order by case when ce.source_enrollment_id is not null and p.source_enrollment_id=ce.source_enrollment_id then 0 else 1 end,p.created_at desc limit 1 for update;
          if pool.id is not null then update public.os_student_course_enrollments set hour_pool_id=pool.id where id=ce.id;ce.hour_pool_id:=pool.id;end if;
        end if;
        if pool.id is null then
          v_deduct:=0;v_warning_count:=v_warning_count+1;
          v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('student_id',m.student_id,'student',coalesce(m.nickname,m.display_name),'warning','ไม่พบ Hour Pool'));
        elsif not pool.unlimited and coalesce(pool.used_hours,0)+v_hours>coalesce(pool.total_hours,0) then
          v_deduct:=0;v_warning_count:=v_warning_count+1;
          v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('student_id',m.student_id,'student',coalesce(m.nickname,m.display_name),'warning','ชั่วโมงคงเหลือไม่พอ'));
        end if;
      end if;
    end if;

    insert into public.os_student_attendance(session_id,student_id,status,checked_in_at,source,note,billable,deducted_hours)
    values(v_session,m.student_id,v_status,case when v_status in ('present','late') then p_start_at else null end,'tutor',nullif(trim(p_note),''),(v_deduct>0),v_deduct)
    on conflict(session_id,student_id) do update set status=excluded.status,checked_in_at=excluded.checked_in_at,source='tutor',note=excluded.note,billable=excluded.billable,deducted_hours=excluded.deducted_hours,updated_at=now();

    if v_deduct>0 and ce.id is not null and pool.id is not null then
      insert into public.os_hour_ledger(pool_id,student_id,student_course_enrollment_id,course_id,session_id,entry_type,hours_delta,note,created_by)
      values(pool.id,m.student_id,ce.id,g.course_id,v_session,'usage',v_deduct,
        case when v_status='absent' then 'Group class absent · hour deducted by class policy' else coalesce(nullif(trim(p_note),''),'Group class lesson') end,auth.uid())
      on conflict do nothing;
      v_any_deduct:=true;v_deducted_count:=v_deducted_count+1;
    end if;
  end loop;

  update public.os_attendance_sessions set deduction_status=case when v_any_deduct then 'deducted' else 'not_deducted' end,
    deducted_at=case when v_any_deduct then now() else null end,deducted_by=case when v_any_deduct then auth.uid() else null end,
    deduction_note=case when v_any_deduct then 'Group Class V24 · per-student ledger' else 'Group Class V24 · no billable wallet' end
  where id=v_session;

  if g.recording_on_absence and v_absent_count>0 and nullif(trim(coalesce(p_video_url,'')),'') is not null then
    insert into public.os_student_group_recordings(group_id,session_id,title,video_url,visibility,note,created_by)
    values(g.id,v_session,coalesce(nullif(trim(p_title),''),g.name||' · Recording'),trim(p_video_url),g.recording_visibility,nullif(trim(p_note),''),auth.uid()) returning id into v_recording;
  end if;

  return jsonb_build_object('ok',true,'session_id',v_session,'duration_minutes',v_minutes,'duration_hours',v_hours,
    'deducted_students',v_deducted_count,'absent_students',v_absent_count,'warning_count',v_warning_count,'warnings',v_warnings,
    'recording_id',v_recording,'recording_required',(g.recording_on_absence and v_absent_count>0 and v_recording is null));
end $$;
revoke all on function public.tutor_group_class_complete_lesson(uuid,timestamptz,timestamptz,text,text,jsonb,text) from public;
grant execute on function public.tutor_group_class_complete_lesson(uuid,timestamptz,timestamptz,text,text,jsonb,text) to authenticated;

-- Student sees group recordings according to class visibility. absent_only requires absent/leave attendance for that session.
create or replace function public.student_group_class_recordings()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare v_student uuid;v_rows jsonb;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if to_regprocedure('public.aw_my_student_id()') is null then return '[]'::jsonb; end if;
  execute 'select public.aw_my_student_id()' into v_student;
  if v_student is null then return '[]'::jsonb; end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'group_id',g.id,'group_name',g.name,'group_code',g.group_code,
    'course_id',g.course_id,'course_name',coalesce(c.title,c.name),
    'session_id',r.session_id,'session_date',s.session_date,'title',coalesce(r.title,s.title,g.name),
    'video_url',r.video_url,'visibility',r.visibility,'note',r.note,'published_at',r.published_at
  ) order by r.published_at desc),'[]'::jsonb)
  into v_rows
  from public.os_student_group_recordings r
  join public.os_student_groups g on g.id=r.group_id
  join public.os_student_group_members m on m.group_id=g.id and m.student_id=v_student and m.active=true
  left join public.courses c on c.id=g.course_id
  left join public.os_attendance_sessions s on s.id=r.session_id
  where r.active=true and (r.expires_at is null or r.expires_at>now())
    and (r.visibility='all_members' or exists(select 1 from public.os_student_attendance a where a.session_id=r.session_id and a.student_id=v_student and a.status in ('absent','leave')));
  return v_rows;
end $$;
revoke all on function public.student_group_class_recordings() from public;
grant execute on function public.student_group_class_recordings() to authenticated;

notify pgrst,'reload schema';
commit;

select jsonb_build_object(
 'ok',true,
 'group_master',to_regclass('public.os_student_groups') is not null,
 'group_schedules',to_regclass('public.os_student_group_schedules') is not null,
 'group_reservations',to_regclass('public.os_student_group_reservations') is not null,
 'group_recordings',to_regclass('public.os_student_group_recordings') is not null,
 'public_rpc',to_regprocedure('public.public_group_classes_for_course(uuid)') is not null,
 'manager_rpc',to_regprocedure('public.manager_group_class_bootstrap()') is not null,
 'tutor_group_lesson_rpc',to_regprocedure('public.tutor_group_class_complete_lesson(uuid,timestamptz,timestamptz,text,text,jsonb,text)') is not null,
 'student_recording_rpc',to_regprocedure('public.student_group_class_recordings()') is not null
) as arewarin_v24_group_class_status;
