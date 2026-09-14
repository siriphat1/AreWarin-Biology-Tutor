-- ============================================================
-- AreWarin V17.1 · Realtime Teaching Clock + Payment Cleanup
-- Run AFTER V17. Idempotent where practical.
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- Staff can optionally be linked to a Tutor master record.
alter table public.os_staff_profiles
  add column if not exists tutor_id uuid references public.tutors(id) on delete set null;

-- Extra linkage for private lesson clock.
alter table public.os_attendance_sessions
  add column if not exists private_student_id uuid references public.os_students(id) on delete set null,
  add column if not exists student_course_enrollment_id uuid references public.os_student_course_enrollments(id) on delete set null,
  add column if not exists session_kind text not null default 'class';

alter table public.os_teaching_logs
  add column if not exists session_id uuid references public.os_attendance_sessions(id) on delete set null;

create unique index if not exists os_teaching_logs_session_unique
on public.os_teaching_logs(session_id)
where session_id is not null;

create index if not exists os_attendance_private_student_idx
on public.os_attendance_sessions(private_student_id, session_date desc)
where private_student_id is not null;

-- ------------------------------------------------------------
-- Payment cleanup:
-- Active / paused / completed course is authoritative.
-- ------------------------------------------------------------
create or replace function public.aw_v171_reconcile_active_course_payment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.status not in ('active','paused','completed') then return new; end if;

  if new.source_enrollment_id is not null then
    update public.enrollments
       set status='confirmed', updated_at=now()
     where id=new.source_enrollment_id
       and status<>'confirmed';

    update public.payments
       set status='paid',
           verified_amount=coalesce(verified_amount,amount_submitted),
           verified_at=coalesce(verified_at,now()),
           updated_at=now()
     where enrollment_id=new.source_enrollment_id
       and status<>'paid';

    update public.portal_payment_requests
       set status='paid',
           updated_at=now()
     where enrollment_id=new.source_enrollment_id
       and status not in ('paid','cancelled');

    update public.portal_payment_submissions ps
       set status='approved',
           reviewed_at=coalesce(reviewed_at,now())
     where ps.payment_request_id in (
       select pr.id
       from public.portal_payment_requests pr
       where pr.enrollment_id=new.source_enrollment_id
     )
       and ps.status='pending';
  end if;

  return new;
end $$;

drop trigger if exists trg_aw_v171_active_course_payment on public.os_student_course_enrollments;
create trigger trg_aw_v171_active_course_payment
after insert or update of status on public.os_student_course_enrollments
for each row execute function public.aw_v171_reconcile_active_course_payment();

-- Backfill rows already Active before this migration.
update public.enrollments e
set status='confirmed', updated_at=now()
where exists(
  select 1
  from public.os_student_course_enrollments sce
  where sce.source_enrollment_id=e.id
    and sce.status in ('active','paused','completed')
)
and e.status<>'confirmed';

update public.payments p
set status='paid',
    verified_amount=coalesce(p.verified_amount,p.amount_submitted),
    verified_at=coalesce(p.verified_at,now()),
    updated_at=now()
where exists(
  select 1
  from public.os_student_course_enrollments sce
  where sce.source_enrollment_id=p.enrollment_id
    and sce.status in ('active','paused','completed')
)
and p.status<>'paid';

update public.portal_payment_requests pr
set status='paid', updated_at=now()
where exists(
  select 1
  from public.os_student_course_enrollments sce
  where sce.source_enrollment_id=pr.enrollment_id
    and sce.status in ('active','paused','completed')
)
and pr.status not in ('paid','cancelled');

-- ------------------------------------------------------------
-- Helper: check course wallet before logging a private lesson.
-- ------------------------------------------------------------
create or replace function public.os_v171_private_lesson_balance(
  p_student_id uuid,
  p_student_course_enrollment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  sce public.os_student_course_enrollments;
  hp public.os_hour_pools;
  rem numeric(10,2);
begin
  if not public.os_is_staff() then
    raise exception 'Staff permission required';
  end if;

  select * into sce
  from public.os_student_course_enrollments
  where id=p_student_course_enrollment_id
    and student_id=p_student_id
    and status in ('active','paused')
  limit 1;

  if sce.id is null then raise exception 'Active student course not found'; end if;

  select * into hp from public.os_hour_pools where id=sce.hour_pool_id;
  if hp.id is null then raise exception 'Hour pool not found'; end if;

  rem := case when hp.unlimited then null else greatest(0,coalesce(hp.total_hours,0)-coalesce(hp.used_hours,0)) end;

  return jsonb_build_object(
    'student_id',p_student_id,
    'student_course_enrollment_id',sce.id,
    'course_id',sce.course_id,
    'hour_pool_id',hp.id,
    'unlimited',hp.unlimited,
    'total_hours',hp.total_hours,
    'used_hours',hp.used_hours,
    'remaining_hours',rem
  );
end $$;

-- ------------------------------------------------------------
-- Manual/private lesson: choose date, start, end, auto hours,
-- mark present and deduct hours atomically.
-- ------------------------------------------------------------
create or replace function public.os_v171_log_private_lesson(
  p_student_id uuid,
  p_student_course_enrollment_id uuid,
  p_tutor_id uuid default null,
  p_session_date date default current_date,
  p_start_time time default null,
  p_end_time time default null,
  p_hours numeric default null,
  p_title text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  sce public.os_student_course_enrollments;
  hp public.os_hour_pools;
  sid uuid;
  start_ts timestamptz;
  end_ts timestamptz;
  hrs numeric(10,2);
  rem numeric(10,2);
  result jsonb;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;

  select * into sce
  from public.os_student_course_enrollments
  where id=p_student_course_enrollment_id
    and student_id=p_student_id
    and status in ('active','paused')
  for update;

  if sce.id is null then raise exception 'Active student course not found'; end if;
  if sce.hour_pool_id is null then raise exception 'Hour pool not found'; end if;

  select * into hp from public.os_hour_pools where id=sce.hour_pool_id for update;
  if hp.id is null then raise exception 'Hour pool not found'; end if;

  if p_start_time is null or p_end_time is null then
    raise exception 'Start and end time are required';
  end if;

  start_ts := ((p_session_date + p_start_time)::timestamp at time zone 'Asia/Bangkok');
  end_ts := ((p_session_date + p_end_time)::timestamp at time zone 'Asia/Bangkok');
  if end_ts <= start_ts then end_ts := end_ts + interval '1 day'; end if;

  hrs := round(coalesce(p_hours,extract(epoch from (end_ts-start_ts))/3600.0)::numeric,2);
  if hrs <= 0 then raise exception 'Lesson hours must be greater than 0'; end if;

  rem := case when hp.unlimited then null else greatest(0,coalesce(hp.total_hours,0)-coalesce(hp.used_hours,0)) end;
  if not hp.unlimited and hrs > rem + 0.001 then
    raise exception 'Remaining hours are insufficient. Remaining: % hour(s)',trim(to_char(rem,'FM999990.00'));
  end if;

  insert into public.os_attendance_sessions(
    course_id,tutor_id,session_date,start_time,end_time,title,mode,status,note,created_by,
    actual_start_at,actual_end_at,duration_minutes,billable_hours,duration_source,deduction_status,
    private_student_id,student_course_enrollment_id,session_kind
  ) values(
    sce.course_id,p_tutor_id,p_session_date,p_start_time,p_end_time,
    coalesce(nullif(trim(p_title),''),'Private Lesson'),'onsite','open',p_note,auth.uid(),
    start_ts,end_ts,round(extract(epoch from (end_ts-start_ts))/60.0)::int,hrs,'manual','not_deducted',
    p_student_id,sce.id,'private'
  ) returning id into sid;

  insert into public.os_student_attendance(session_id,student_id,status,checked_in_at,source,billable,note)
  values(sid,p_student_id,'present',start_ts,'tutor-os-private',true,p_note)
  on conflict(session_id,student_id) do update
    set status='present',checked_in_at=excluded.checked_in_at,billable=true,note=excluded.note,updated_at=now();

  select public.os_deduct_session_hours_v2(
    sid,
    jsonb_build_array(jsonb_build_object('student_id',p_student_id,'hours',hrs)),
    coalesce(p_note,'Tutor OS · Private Lesson')
  ) into result;

  insert into public.os_teaching_logs(
    session_id,student_id,course_id,tutor_id,lesson_date,topic,hours,notes,created_by
  ) values(
    sid,p_student_id,sce.course_id,p_tutor_id,p_session_date,
    coalesce(nullif(trim(p_title),''),'Private Lesson'),hrs,p_note,auth.uid()
  )
  on conflict(session_id) where session_id is not null do update
    set hours=excluded.hours,notes=excluded.notes,updated_at=now();

  select * into hp from public.os_hour_pools where id=sce.hour_pool_id;

  return jsonb_build_object(
    'ok',true,
    'session_id',sid,
    'hours',hrs,
    'unlimited',hp.unlimited,
    'remaining_hours',case when hp.unlimited then null else greatest(0,coalesce(hp.total_hours,0)-coalesce(hp.used_hours,0)) end,
    'deduction',result
  );
end $$;

-- ------------------------------------------------------------
-- Live clock: start now, then finish later.
-- ------------------------------------------------------------
create or replace function public.os_v171_start_private_lesson(
  p_student_id uuid,
  p_student_course_enrollment_id uuid,
  p_tutor_id uuid default null,
  p_title text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  sce public.os_student_course_enrollments;
  sid uuid;
  now_bkk timestamp;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;

  select * into sce
  from public.os_student_course_enrollments
  where id=p_student_course_enrollment_id
    and student_id=p_student_id
    and status in ('active','paused')
  limit 1;

  if sce.id is null then raise exception 'Active student course not found'; end if;
  if sce.hour_pool_id is null then raise exception 'Hour pool not found'; end if;

  if exists(
    select 1 from public.os_attendance_sessions
    where private_student_id=p_student_id
      and actual_start_at is not null
      and actual_end_at is null
      and status='open'
  ) then
    raise exception 'This student already has a running lesson clock';
  end if;

  now_bkk := now() at time zone 'Asia/Bangkok';

  insert into public.os_attendance_sessions(
    course_id,tutor_id,session_date,start_time,title,mode,status,note,created_by,
    actual_start_at,duration_source,deduction_status,
    private_student_id,student_course_enrollment_id,session_kind
  ) values(
    sce.course_id,p_tutor_id,now_bkk::date,now_bkk::time,
    coalesce(nullif(trim(p_title),''),'Private Lesson'),'onsite','open',p_note,auth.uid(),
    now(),'actual','not_deducted',
    p_student_id,sce.id,'private'
  ) returning id into sid;

  insert into public.os_student_attendance(session_id,student_id,status,checked_in_at,source,billable,note)
  values(sid,p_student_id,'present',now(),'tutor-os-live-clock',true,p_note)
  on conflict(session_id,student_id) do update
    set status='present',checked_in_at=excluded.checked_in_at,billable=true,note=excluded.note,updated_at=now();

  return jsonb_build_object('ok',true,'session_id',sid,'started_at',now());
end $$;

create or replace function public.os_v171_finish_private_lesson(
  p_session_id uuid,
  p_hours numeric default null,
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
  hp public.os_hour_pools;
  hrs numeric(10,2);
  rem numeric(10,2);
  result jsonb;
begin
  if not public.os_is_staff() then raise exception 'Staff permission required'; end if;

  select * into s
  from public.os_attendance_sessions
  where id=p_session_id
    and session_kind='private'
    and private_student_id is not null
  for update;

  if s.id is null then raise exception 'Private lesson session not found'; end if;
  if s.actual_start_at is null then raise exception 'Lesson clock has not started'; end if;

  select * into sce
  from public.os_student_course_enrollments
  where id=s.student_course_enrollment_id
    and student_id=s.private_student_id
    and status in ('active','paused')
  for update;

  if sce.id is null then raise exception 'Active student course not found'; end if;

  select * into hp from public.os_hour_pools where id=sce.hour_pool_id for update;
  if hp.id is null then raise exception 'Hour pool not found'; end if;

  hrs := round(coalesce(
    p_hours,
    extract(epoch from (coalesce(s.actual_end_at,now())-s.actual_start_at))/3600.0
  )::numeric,2);

  if hrs <= 0 then raise exception 'Lesson hours must be greater than 0'; end if;

  rem := case when hp.unlimited then null else greatest(0,coalesce(hp.total_hours,0)-coalesce(hp.used_hours,0)) end;
  if not hp.unlimited and hrs > rem + 0.001 then
    raise exception 'Remaining hours are insufficient. Remaining: % hour(s)',trim(to_char(rem,'FM999990.00'));
  end if;

  update public.os_attendance_sessions
     set actual_end_at=coalesce(actual_end_at,now()),
         end_time=(coalesce(actual_end_at,now()) at time zone 'Asia/Bangkok')::time,
         duration_minutes=greatest(1,round(extract(epoch from (coalesce(actual_end_at,now())-actual_start_at))/60.0)::int),
         billable_hours=hrs,
         duration_source=case when p_hours is null then 'actual' else 'manual' end,
         note=coalesce(p_note,note),
         updated_at=now()
   where id=p_session_id
   returning * into s;

  select public.os_deduct_session_hours_v2(
    p_session_id,
    jsonb_build_array(jsonb_build_object('student_id',s.private_student_id,'hours',hrs)),
    coalesce(p_note,'Tutor OS · Live Clock')
  ) into result;

  insert into public.os_teaching_logs(
    session_id,student_id,course_id,tutor_id,lesson_date,topic,hours,notes,created_by
  ) values(
    p_session_id,s.private_student_id,s.course_id,s.tutor_id,s.session_date,
    coalesce(nullif(trim(s.title),''),'Private Lesson'),hrs,coalesce(p_note,s.note),auth.uid()
  )
  on conflict(session_id) where session_id is not null do update
    set hours=excluded.hours,notes=excluded.notes,updated_at=now();

  select * into hp from public.os_hour_pools where id=sce.hour_pool_id;

  return jsonb_build_object(
    'ok',true,
    'session_id',p_session_id,
    'hours',hrs,
    'unlimited',hp.unlimited,
    'remaining_hours',case when hp.unlimited then null else greatest(0,coalesce(hp.total_hours,0)-coalesce(hp.used_hours,0)) end,
    'deduction',result
  );
end $$;

grant execute on function public.os_v171_private_lesson_balance(uuid,uuid) to authenticated;
grant execute on function public.os_v171_log_private_lesson(uuid,uuid,uuid,date,time,time,numeric,text,text) to authenticated;
grant execute on function public.os_v171_start_private_lesson(uuid,uuid,uuid,text,text) to authenticated;
grant execute on function public.os_v171_finish_private_lesson(uuid,numeric,text) to authenticated;

-- ------------------------------------------------------------
-- Student bootstrap: recent lessons including actual start/end,
-- tutor and deducted hours.
-- ------------------------------------------------------------
create or replace function public.student_v171_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  sid uuid:=public.aw_my_student_id();
  base jsonb;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;

  begin
    base:=public.student_v17_bootstrap();
  exception when undefined_function then
    base:=public.student_v16_bootstrap();
  end;

  return base || jsonb_build_object(
    'v171_recent_lessons',
    coalesce((
      select jsonb_agg(to_jsonb(x) order by x.session_date desc,x.actual_start_at desc nulls last)
      from (
        select
          ses.id,
          ses.course_id,
          ses.tutor_id,
          ses.session_date,
          ses.start_time,
          ses.end_time,
          ses.actual_start_at,
          ses.actual_end_at,
          ses.duration_minutes,
          ses.billable_hours,
          ses.title,
          ses.note,
          ses.status as session_status,
          a.status as attendance_status,
          coalesce(a.deducted_hours,0) as deducted_hours,
          c.name as course_name,
          t.display_name as tutor_name
        from public.os_student_attendance a
        join public.os_attendance_sessions ses on ses.id=a.session_id
        left join public.courses c on c.id=ses.course_id
        left join public.tutors t on t.id=ses.tutor_id
        where a.student_id=sid
        order by ses.session_date desc,ses.actual_start_at desc nulls last,ses.created_at desc
        limit 60
      ) x
    ),'[]'::jsonb)
  );
end $$;

grant execute on function public.student_v171_bootstrap() to authenticated;

-- ------------------------------------------------------------
-- Realtime: make sure operational tables are in publication.
-- ------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array[
      'os_hour_ledger',
      'os_hour_pools',
      'os_student_attendance',
      'os_attendance_sessions',
      'os_student_course_enrollments',
      'portal_notifications'
    ] loop
      if not exists(
        select 1 from pg_publication_tables
        where pubname='supabase_realtime'
          and schemaname='public'
          and tablename=t
      ) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end $$;

commit;

-- Diagnostic: latest private lesson / balances
select
  s.display_name,
  s.student_code,
  sce.course_label,
  hp.total_hours,
  hp.used_hours,
  case when hp.unlimited then null else greatest(0,coalesce(hp.total_hours,0)-coalesce(hp.used_hours,0)) end as remaining_hours,
  ses.session_date,
  ses.actual_start_at,
  ses.actual_end_at,
  ses.billable_hours
from public.os_student_course_enrollments sce
join public.os_students s on s.id=sce.student_id
left join public.os_hour_pools hp on hp.id=sce.hour_pool_id
left join lateral(
  select x.*
  from public.os_attendance_sessions x
  where x.student_course_enrollment_id=sce.id
  order by x.created_at desc
  limit 1
) ses on true
where sce.status in ('active','paused')
order by sce.updated_at desc
limit 50;
