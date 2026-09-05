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
