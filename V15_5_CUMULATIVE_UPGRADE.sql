-- AreWarin Unified System V15.4.1 (CORRECTED)
-- Fix: public enrollment -> enrollment_items -> Student Portal/Tutor OS course links
-- Fixes PostgreSQL 42P10 caused by ON CONFLICT against a partial unique index.
-- Safe to rerun on the existing V15 project. Idempotent where practical.

begin;

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

alter table public.os_student_course_enrollments drop constraint if exists os_student_course_enrollments_source_enrollment_id_key;
alter table public.os_student_course_enrollments add column if not exists enrollment_item_id uuid references public.enrollment_items(id) on delete set null;
alter table public.os_student_course_enrollments add column if not exists offering_id uuid references public.course_offerings(id) on delete set null;
alter table public.os_student_course_enrollments add column if not exists hour_pool_id uuid;

-- A normal UNIQUE index already allows multiple NULL values in PostgreSQL.
-- Using a full unique index lets ON CONFLICT(enrollment_item_id) infer it directly.
drop index if exists public.os_sce_enrollment_item_unique;
create unique index os_sce_enrollment_item_unique
  on public.os_student_course_enrollments(enrollment_item_id);

create index if not exists os_sce_source_enrollment_idx
  on public.os_student_course_enrollments(source_enrollment_id);

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

create or replace function public.aw_sync_enrollment_item_to_os()
returns trigger language plpgsql security definer set search_path=public as $$
declare
  e public.enrollments;
  s public.os_students;
  p public.os_hour_pools;
  v_pool_key text;
  v_status text;
begin
  select * into e from public.enrollments where id=new.enrollment_id;
  if e.id is null then return new; end if;

  select * into s
  from public.os_students
  where phone_key=case
    when regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')=''
      then 'enrollment:'||e.id::text
    else regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')
  end
  limit 1;

  if s.id is null then return new; end if;

  v_pool_key:=case when new.share_mode='shared' then 'shared' else coalesce(new.course_id::text,new.id::text) end;
  v_status:=case when e.status='confirmed' then 'active' when e.status in ('cancelled','rejected') then 'cancelled' else 'pending' end;

  insert into public.os_hour_pools(student_id,source_enrollment_id,pool_key,package_code,total_hours,unlimited,status)
  values(s.id,e.id,v_pool_key,new.package_code,new.hours_allocated,new.hours_unlimited,v_status)
  on conflict(student_id,source_enrollment_id,pool_key) do update set
    package_code=excluded.package_code,
    total_hours=excluded.total_hours,
    unlimited=excluded.unlimited,
    status=excluded.status,
    updated_at=now()
  returning * into p;

  insert into public.os_student_course_enrollments(
    student_id,course_id,tutor_id,source_enrollment_id,enrollment_item_id,offering_id,hour_pool_id,
    course_label,tutor_label,status,enrolled_at,hours_total,hours_used,price,note
  )
  values(
    s.id,new.course_id,new.tutor_id,e.id,new.id,new.offering_id,p.id,
    new.course_name_snapshot,new.tutor_name_snapshot,v_status,e.created_at::date,
    coalesce(p.total_hours,0),coalesce(p.used_hours,0),new.amount_allocated,'Synced from enrollment item'
  )
  on conflict(enrollment_item_id) do update set
    course_id=excluded.course_id,
    tutor_id=excluded.tutor_id,
    offering_id=excluded.offering_id,
    hour_pool_id=excluded.hour_pool_id,
    course_label=excluded.course_label,
    tutor_label=excluded.tutor_label,
    status=excluded.status,
    hours_total=excluded.hours_total,
    hours_used=excluded.hours_used,
    price=excluded.price,
    updated_at=now();

  return new;
end $$;

drop trigger if exists trg_aw_enrollment_item_sync on public.enrollment_items;
create trigger trg_aw_enrollment_item_sync
after insert or update on public.enrollment_items
for each row execute function public.aw_sync_enrollment_item_to_os();

-- Backfill enrollments created by the rescue Edge Function.
do $$
declare
  e record;
  item jsonb;
  v_course uuid;
  v_tutor uuid;
  v_offering uuid;
  v_count integer;
  v_hours numeric(10,2);
  v_unlimited boolean;
  v_share text;
  v_status text;
begin
  for e in
    select id,status,amount_quoted,raw_payload,created_at
    from public.enrollments
    where jsonb_typeof(raw_payload->'courseItems')='array'
      and jsonb_array_length(raw_payload->'courseItems')>0
  loop
    v_count:=greatest(1,jsonb_array_length(e.raw_payload->'courseItems'));
    v_unlimited:=coalesce(e.raw_payload->>'selectedMode','')='yearly' or coalesce(e.raw_payload->>'hours','') ilike '%รายปี%';
    begin
      v_hours:=case when v_unlimited then null else nullif(regexp_replace(coalesce(e.raw_payload->>'hours',e.raw_payload->>'hourlyCount','0'),'[^0-9.]','','g'),'')::numeric end;
    exception when others then
      v_hours:=null;
    end;
    v_share:=case when coalesce(e.raw_payload->>'cartShareMode','shared')='separate' then 'separate' else 'shared' end;
    v_status:=case when e.status='confirmed' then 'active' when e.status in ('cancelled','rejected') then 'cancelled' else 'pending' end;

    for item in select value from jsonb_array_elements(e.raw_payload->'courseItems')
    loop
      v_course:=null; v_tutor:=null; v_offering:=null;
      if coalesce(item->>'courseId','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        v_course:=(item->>'courseId')::uuid;
      end if;
      if coalesce(item->>'tutorId','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        v_tutor:=(item->>'tutorId')::uuid;
      end if;
      if coalesce(item->>'offeringId','') ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
        v_offering:=(item->>'offeringId')::uuid;
      end if;

      if v_course is not null and exists(select 1 from public.courses c where c.id=v_course) then
        insert into public.enrollment_items(
          enrollment_id,course_id,tutor_id,offering_id,course_name_snapshot,tutor_name_snapshot,
          package_code,share_mode,hours_allocated,hours_unlimited,amount_allocated,status
        ) values(
          e.id,v_course,
          case when v_tutor is not null and exists(select 1 from public.tutors t where t.id=v_tutor) then v_tutor else null end,
          case when v_offering is not null and exists(select 1 from public.course_offerings o where o.id=v_offering) then v_offering else null end,
          nullif(item->>'courseName',''),nullif(item->>'tutorName',''),
          nullif(coalesce(e.raw_payload->>'selectedMode',e.raw_payload->>'mode'),'') ,
          v_share,v_hours,v_unlimited,coalesce(e.amount_quoted,0)/v_count,v_status
        )
        on conflict(enrollment_id,course_id) do update set
          tutor_id=coalesce(excluded.tutor_id,public.enrollment_items.tutor_id),
          offering_id=coalesce(excluded.offering_id,public.enrollment_items.offering_id),
          course_name_snapshot=coalesce(excluded.course_name_snapshot,public.enrollment_items.course_name_snapshot),
          tutor_name_snapshot=coalesce(excluded.tutor_name_snapshot,public.enrollment_items.tutor_name_snapshot),
          package_code=coalesce(excluded.package_code,public.enrollment_items.package_code),
          share_mode=excluded.share_mode,
          hours_allocated=excluded.hours_allocated,
          hours_unlimited=excluded.hours_unlimited,
          amount_allocated=excluded.amount_allocated,
          status=excluded.status,
          updated_at=now();
      end if;
    end loop;
  end loop;
end $$;

update public.enrollment_items set updated_at=now();

commit;

select
  s.student_code,
  s.display_name,
  sce.course_label,
  sce.status,
  sce.hours_total,
  sce.hours_used,
  e.status as enrollment_status,
  e.receipt_no
from public.os_student_course_enrollments sce
join public.os_students s on s.id=sce.student_id
left join public.enrollments e on e.id=sce.source_enrollment_id
order by sce.created_at desc
limit 50;
-- AreWarin Unified Student V15.5
-- Purpose:
-- 1) Manager payment/Active state -> Student Portal payment + course state sync
-- 2) Backfill real student/application data into Student Portal
-- 3) Fix student_v9_payment_bootstrap GROUP BY / ORDER BY error
-- 4) Keep current V15.4.1 course sync intact

begin;

-- ------------------------------------------------------------
-- A. Helpers for real name fields from the application fullname
-- ------------------------------------------------------------
create or replace function public.aw_name_without_title(p_name text)
returns text language sql immutable as $$
  select nullif(
    btrim(
      regexp_replace(
        coalesce(p_name,''),
        '^(เด็กชาย|เด็กหญิง|ด\.ช\.|ด\.ญ\.|นาย|นางสาว|นาง|คุณ)\s*',
        '',
        'i'
      )
    ),
    ''
  );
$$;

create or replace function public.aw_first_name(p_name text)
returns text language sql immutable as $$
  select nullif(split_part(coalesce(public.aw_name_without_title(p_name),''),' ',1),'');
$$;

create or replace function public.aw_last_name(p_name text)
returns text language sql immutable as $$
  select nullif(
    btrim(
      regexp_replace(
        coalesce(public.aw_name_without_title(p_name),''),
        '^\S+\s*',
        ''
      )
    ),
    ''
  );
$$;

-- ------------------------------------------------------------
-- B. Ensure application data is reflected in os_students
--    Run after the existing enrollment -> OS sync trigger.
-- ------------------------------------------------------------
create or replace function public.aw_sync_student_application_profile()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_phone_key text;
  v_first text;
  v_last text;
begin
  v_phone_key := regexp_replace(coalesce(new.phone,''),'[^0-9+]','','g');
  if v_phone_key='' then v_phone_key := 'enrollment:'||new.id::text; end if;

  v_first := coalesce(
    nullif(new.raw_payload->>'firstName',''),
    nullif(new.raw_payload->>'first_name',''),
    public.aw_first_name(new.fullname)
  );
  v_last := coalesce(
    nullif(new.raw_payload->>'lastName',''),
    nullif(new.raw_payload->>'last_name',''),
    public.aw_last_name(new.fullname)
  );

  update public.os_students s
  set
    source_enrollment_id = new.id,
    display_name = coalesce(nullif(new.fullname,''),s.display_name),
    first_name = coalesce(v_first,s.first_name),
    last_name = coalesce(v_last,s.last_name),
    nickname = coalesce(nullif(new.nickname,''),s.nickname),
    phone = coalesce(nullif(new.phone,''),s.phone),
    email = coalesce(nullif(new.email,''),s.email),
    line_id = coalesce(nullif(new.line_id,''),s.line_id),
    school = coalesce(nullif(new.school,''),s.school),
    grade = coalesce(nullif(new.grade,''),s.grade),
    faculty = coalesce(nullif(new.faculty,''),s.faculty),
    province = coalesce(nullif(new.province,''),s.province),
    parent_name = coalesce(nullif(new.parent_name,''),s.parent_name),
    parent_phone = coalesce(nullif(new.parent_phone,''),s.parent_phone),
    guardian_name = coalesce(nullif(new.parent_name,''),s.guardian_name),
    guardian_relationship = coalesce(nullif(new.parent_relation,''),s.guardian_relationship),
    guardian_phone = coalesce(nullif(new.parent_phone,''),s.guardian_phone),
    course_summary = coalesce(nullif(new.course_text,''),s.course_summary),
    study_type = coalesce(nullif(new.study_type,''),s.study_type),
    status = case
      when new.status='confirmed' then 'active'
      when new.status in ('cancelled','rejected') then 'inactive'
      else 'pending'
    end,
    updated_at = now()
  where s.phone_key=v_phone_key or s.source_enrollment_id=new.id;

  return new;
end $$;

drop trigger if exists zz_aw_student_profile_sync on public.enrollments;
create trigger zz_aw_student_profile_sync
after insert or update on public.enrollments
for each row execute function public.aw_sync_student_application_profile();

-- Backfill current students from their latest linked enrollment.
do $$
declare r record;
begin
  for r in select * from public.enrollments order by created_at asc loop
    perform 1;
    update public.os_students s
    set
      source_enrollment_id=r.id,
      display_name=coalesce(nullif(r.fullname,''),s.display_name),
      first_name=coalesce(nullif(r.raw_payload->>'firstName',''),nullif(r.raw_payload->>'first_name',''),public.aw_first_name(r.fullname),s.first_name),
      last_name=coalesce(nullif(r.raw_payload->>'lastName',''),nullif(r.raw_payload->>'last_name',''),public.aw_last_name(r.fullname),s.last_name),
      nickname=coalesce(nullif(r.nickname,''),s.nickname),
      phone=coalesce(nullif(r.phone,''),s.phone),
      email=coalesce(nullif(r.email,''),s.email),
      line_id=coalesce(nullif(r.line_id,''),s.line_id),
      school=coalesce(nullif(r.school,''),s.school),
      grade=coalesce(nullif(r.grade,''),s.grade),
      faculty=coalesce(nullif(r.faculty,''),s.faculty),
      province=coalesce(nullif(r.province,''),s.province),
      parent_name=coalesce(nullif(r.parent_name,''),s.parent_name),
      parent_phone=coalesce(nullif(r.parent_phone,''),s.parent_phone),
      guardian_name=coalesce(nullif(r.parent_name,''),s.guardian_name),
      guardian_relationship=coalesce(nullif(r.parent_relation,''),s.guardian_relationship),
      guardian_phone=coalesce(nullif(r.parent_phone,''),s.guardian_phone),
      course_summary=coalesce(nullif(r.course_text,''),s.course_summary),
      study_type=coalesce(nullif(r.study_type,''),s.study_type),
      status=case when r.status='confirmed' then 'active' when r.status in ('cancelled','rejected') then 'inactive' else s.status end,
      updated_at=now()
    where s.source_enrollment_id=r.id
       or s.phone_key=case when regexp_replace(coalesce(r.phone,''),'[^0-9+]','','g')='' then 'enrollment:'||r.id::text else regexp_replace(coalesce(r.phone,''),'[^0-9+]','','g') end;
  end loop;
end $$;

-- ------------------------------------------------------------
-- C. Core payment <-> Student Portal payment state bridge
-- ------------------------------------------------------------
create index if not exists portal_payment_requests_enrollment_idx
  on public.portal_payment_requests(enrollment_id);

create or replace function public.aw_sync_core_payment_to_student_portal()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  e public.enrollments;
  sid uuid;
  v_status text;
  v_amount numeric(12,2);
  v_title text;
  v_req_id uuid;
  v_plan_id uuid;
begin
  select * into e from public.enrollments where id=new.enrollment_id;
  if e.id is null then return new; end if;

  select s.id into sid
  from public.os_students s
  where s.source_enrollment_id=e.id
     or s.phone_key=case when regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')='' then 'enrollment:'||e.id::text else regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g') end
  order by (s.source_enrollment_id=e.id) desc, s.updated_at desc
  limit 1;

  if sid is null then return new; end if;

  v_status := case new.status
    when 'paid' then 'paid'
    when 'rejected' then 'rejected'
    when 'cancelled' then 'cancelled'
    else 'pending'
  end;
  v_amount := greatest(0,coalesce(new.verified_amount,new.amount_submitted,e.amount_quoted,0));
  v_title := coalesce(nullif(e.course_text,''),'ค่าคอร์ส AreWarin Biology');

  -- Keep one core payment request per enrollment. Existing installment requests are untouched.
  select id into v_req_id
  from public.portal_payment_requests
  where enrollment_id=e.id and payment_plan_id is null and installment_id is null
  order by created_at asc
  limit 1;

  if v_req_id is null then
    insert into public.portal_payment_requests(
      student_id,enrollment_id,title,amount,note,status,expires_at,created_at,updated_at
    ) values(
      sid,e.id,v_title,v_amount,'เชื่อมจากระบบสมัครเรียนหลัก',v_status,
      case when v_status='pending' then now()+interval '15 minutes' else now()+interval '3650 days' end,
      coalesce(new.created_at,now()),now()
    ) returning id into v_req_id;
  else
    update public.portal_payment_requests
    set student_id=sid,
        title=v_title,
        amount=v_amount,
        status=v_status,
        expires_at=case when v_status='pending' then greatest(expires_at,now()+interval '15 minutes') else now()+interval '3650 days' end,
        updated_at=now()
    where id=v_req_id;
  end if;

  if new.status='paid' then
    -- Manager marking payment paid activates the enrollment/course automatically.
    if e.status<>'confirmed' then
      update public.enrollments set status='confirmed',updated_at=now() where id=e.id;
    end if;

    -- If this enrollment already has a payment plan, close it as paid in Student Portal.
    select id into v_plan_id from public.portal_payment_plans
    where source_enrollment_id=e.id
    order by created_at desc limit 1;

    if v_plan_id is not null then
      update public.portal_payment_installments
      set amount_paid=amount_due,status='paid',updated_at=now()
      where payment_plan_id=v_plan_id and status<>'cancelled';

      update public.portal_payment_plans
      set amount_paid=total_amount,balance_amount=0,status='paid',updated_at=now()
      where id=v_plan_id;
    end if;

    if not exists(
      select 1 from public.portal_notifications n
      where n.student_id=sid and n.source_type='core_payment' and n.source_id=new.id::text and n.title='ยืนยันการชำระเงินแล้ว'
    ) then
      insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id)
      values(sid,'ยืนยันการชำระเงินแล้ว',v_title||' · ชำระแล้ว '||to_char(v_amount,'FM999G999G990D00')||' บาท','payment','core_payment',new.id::text);
    end if;
  end if;

  return new;
end $$;

drop trigger if exists trg_aw_core_payment_portal_sync on public.payments;
create trigger trg_aw_core_payment_portal_sync
after insert or update of status,amount_submitted,verified_amount on public.payments
for each row execute function public.aw_sync_core_payment_to_student_portal();

-- Manager may press Active/Confirmed on the enrollment instead of changing payment first.
create or replace function public.aw_confirmed_enrollment_marks_paid()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if tg_op='INSERT' then
    if new.status<>'confirmed' then return new; end if;
  else
    if new.status<>'confirmed' or old.status is not distinct from new.status then return new; end if;
  end if;

    update public.payments p
    set status='paid',
        verified_amount=coalesce(p.verified_amount,p.amount_submitted,new.amount_quoted),
        verified_at=coalesce(p.verified_at,now()),
        verified_by=coalesce(p.verified_by,auth.uid()),
        updated_at=now()
    where p.enrollment_id=new.id and p.status<>'paid';
  return new;
end $$;

drop trigger if exists zzz_aw_confirmed_enrollment_marks_paid on public.enrollments;
create trigger zzz_aw_confirmed_enrollment_marks_paid
after insert or update of status on public.enrollments
for each row execute function public.aw_confirmed_enrollment_marks_paid();


-- If the Manager's current UI activates the Student-course row directly,
-- promote the linked core enrollment too. This keeps old Manager buttons compatible.
create or replace function public.aw_active_student_course_confirms_enrollment()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
begin
  if new.status='active'
     and (tg_op='INSERT' or old.status is distinct from new.status)
     and new.source_enrollment_id is not null then
    update public.enrollments
    set status='confirmed',updated_at=now()
    where id=new.source_enrollment_id and status<>'confirmed';
  end if;
  return new;
end $$;

drop trigger if exists zzz_aw_active_student_course_confirms_enrollment on public.os_student_course_enrollments;
create trigger zzz_aw_active_student_course_confirms_enrollment
after insert or update of status on public.os_student_course_enrollments
for each row execute function public.aw_active_student_course_confirms_enrollment();

-- Backfill all current core payments into Student Portal state.
update public.payments set status=status;
update public.enrollments set status=status where status='confirmed';

-- ------------------------------------------------------------
-- D. Fix installment-plan bootstrap SQL error
--    Old form: aggregate outside ORDER BY l.lesson_date -> GROUP BY error
-- ------------------------------------------------------------
create or replace function public.student_v9_payment_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare sid uuid:=public.aw_my_student_id();
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  return jsonb_build_object(
    'plans',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.portal_payment_plans p where p.student_id=sid),'[]'::jsonb),
    'installments',coalesce((select jsonb_agg(to_jsonb(i) order by i.due_date,i.installment_no) from public.portal_payment_installments i where i.payment_plan_id in (select id from public.portal_payment_plans where student_id=sid)),'[]'::jsonb),
    'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from public.portal_payment_requests r where r.student_id=sid),'[]'::jsonb),
    'submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from public.portal_payment_submissions s where s.student_id=sid),'[]'::jsonb),
    'teaching_notes',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'id',l.id,
          'topic',l.topic,
          'lesson_date',l.lesson_date,
          'lesson_summary',coalesce(l.outcome,l.notes),
          'homework',''
        ) order by l.lesson_date desc,l.created_at desc
      )
      from public.os_teaching_logs l
      where l.student_id=sid
    ),'[]'::jsonb)
  );
end $$;

grant execute on function public.student_v9_payment_bootstrap() to authenticated;

-- ------------------------------------------------------------
-- E. Student profile update now supports the application fields
-- ------------------------------------------------------------
create or replace function public.update_my_student_profile(p_profile jsonb)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare sid uuid:=public.aw_my_student_id(); s public.os_students;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  update public.os_students set
    first_name=coalesce(nullif(p_profile->>'first_name',''),first_name),
    last_name=coalesce(nullif(p_profile->>'last_name',''),last_name),
    nickname=coalesce(nullif(p_profile->>'nickname',''),nickname),
    phone=coalesce(nullif(p_profile->>'phone',''),phone),
    email=coalesce(nullif(p_profile->>'email',''),email),
    line_id=coalesce(nullif(p_profile->>'line_id',''),line_id),
    school=coalesce(nullif(p_profile->>'school',''),school),
    grade=coalesce(nullif(p_profile->>'grade',''),grade),
    faculty=coalesce(nullif(p_profile->>'faculty',''),faculty),
    province=coalesce(nullif(p_profile->>'province',''),province),
    birth_date=coalesce(nullif(p_profile->>'birth_date','')::date,birth_date),
    address=coalesce(p_profile->>'address',address),
    guardian_name=coalesce(nullif(p_profile->>'guardian_name',''),guardian_name),
    guardian_relationship=coalesce(nullif(p_profile->>'guardian_relationship',''),guardian_relationship),
    guardian_phone=coalesce(nullif(p_profile->>'guardian_phone',''),guardian_phone),
    guardian_line=coalesce(p_profile->>'guardian_line',guardian_line),
    display_name=coalesce(
      nullif(btrim(concat_ws(' ',nullif(p_profile->>'first_name',''),nullif(p_profile->>'last_name',''))),''),
      display_name
    ),
    updated_at=now()
  where id=sid returning * into s;
  return to_jsonb(s);
end $$;

grant execute on function public.update_my_student_profile(jsonb) to authenticated;

-- ------------------------------------------------------------
-- F. Student bootstrap: application history + core payment history
-- ------------------------------------------------------------
create or replace function public.student_v11_bootstrap()
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare sid uuid:=public.aw_my_student_id(); result jsonb; v_phone text;
begin
  if sid is null then raise exception 'Student account is not linked'; end if;
  select regexp_replace(coalesce(phone,''),'[^0-9+]','','g') into v_phone from public.os_students where id=sid;

  select jsonb_build_object(
    'student',(select to_jsonb(s) from public.os_students s where s.id=sid),
    'application_profile',coalesce((
      select jsonb_build_object(
        'id',e.id,'fullname',e.fullname,'nickname',e.nickname,'phone',e.phone,'line_id',e.line_id,'email',e.email,
        'grade',e.grade,'school',e.school,'faculty',e.faculty,'province',e.province,
        'parent_name',e.parent_name,'parent_relation',e.parent_relation,'parent_phone',e.parent_phone,
        'study_type',e.study_type,'course_text',e.course_text,'tutor_text',e.tutor_text,'hours_text',e.hours_text,'time_text',e.time_text,
        'amount_quoted',e.amount_quoted,'status',e.status,'created_at',e.created_at,'receipt_no',e.receipt_no
      )
      from public.enrollments e
      where e.id=(select source_enrollment_id from public.os_students where id=sid)
         or regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')=v_phone
      order by (e.id=(select source_enrollment_id from public.os_students where id=sid)) desc,e.created_at desc
      limit 1
    ),'{}'::jsonb),
    'applications',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select e.id,e.fullname,e.nickname,e.phone,e.email,e.school,e.grade,e.faculty,e.province,e.course_text,e.tutor_text,e.hours_text,e.time_text,e.amount_quoted,e.status,e.receipt_no,e.created_at
        from public.enrollments e
        where regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')=v_phone
      ) x
    ),'[]'::jsonb),
    'core_payments',coalesce((
      select jsonb_agg(to_jsonb(x) order by x.created_at desc)
      from (
        select p.id,p.enrollment_id,p.payment_method,p.amount_submitted,p.verified_amount,p.status,p.verified_at,p.created_at,e.course_text,e.receipt_no
        from public.payments p join public.enrollments e on e.id=p.enrollment_id
        where regexp_replace(coalesce(e.phone,''),'[^0-9+]','','g')=v_phone
      ) x
    ),'[]'::jsonb),
    'courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'course_type',c.course_type,'cover_url',c.image_url,'description',c.full_description,'public_description',c.short_detail,'renewal_alert_hours',3)) from public.courses c where c.id in (select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=sid and sce.course_id is not null)),'[]'::jsonb),
    'open_courses',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'course_type',c.course_type,'cover_url',c.image_url,'description',c.full_description,'public_description',coalesce(o.public_note,c.short_detail),'hours',coalesce(o.default_hours,0),'price',coalesce(o.display_price,0))) from public.courses c join public.course_offerings o on o.course_id=c.id where c.active=true and o.status='open' and o.student_portal_open=true and o.enrollment_open=true and (o.starts_on is null or o.starts_on<=current_date) and (o.ends_on is null or o.ends_on>=current_date)),'[]'::jsonb),
    'enrollments',coalesce((select jsonb_agg(jsonb_build_object('id',sce.id,'course_id',sce.course_id,'status',sce.status,'hours_total',coalesce(p.total_hours,sce.hours_total),'hours_used',coalesce(p.used_hours,sce.hours_used),'hours_unlimited',coalesce(p.unlimited,false),'hour_pool_id',sce.hour_pool_id,'price',sce.price,'source_enrollment_id',sce.source_enrollment_id)) from public.os_student_course_enrollments sce left join public.os_hour_pools p on p.id=sce.hour_pool_id where sce.student_id=sid),'[]'::jsonb),
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
    'hour_ledger',coalesce((select jsonb_agg(to_jsonb(h) order by h.created_at desc) from public.os_hour_ledger h where h.student_id=sid),'[]'::jsonb)
  ) into result;
  return result;
end $$;

grant execute on function public.student_v11_bootstrap() to authenticated;

commit;

-- Diagnostics: latest student/payment/course state
select
  s.student_code,
  s.display_name,
  s.first_name,
  s.last_name,
  e.status as enrollment_status,
  p.status as payment_status,
  p.verified_amount,
  sce.course_label,
  sce.status as student_course_status
from public.os_students s
left join public.enrollments e on e.id=s.source_enrollment_id
left join public.payments p on p.enrollment_id=e.id
left join public.os_student_course_enrollments sce on sce.student_id=s.id and sce.source_enrollment_id=e.id
order by s.updated_at desc
limit 50;
