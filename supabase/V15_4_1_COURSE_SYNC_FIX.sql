-- AreWarin Unified System V15.4.1
-- Fix: public enrollment -> enrollment_items -> Student Portal/Tutor OS course links
-- Safe to run on the existing V15 project. Idempotent where practical.

begin;

-- Ensure the canonical line-item table exists.
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

-- V15 supports more than one course per enrollment.
alter table public.os_student_course_enrollments drop constraint if exists os_student_course_enrollments_source_enrollment_id_key;
alter table public.os_student_course_enrollments add column if not exists enrollment_item_id uuid references public.enrollment_items(id) on delete set null;
alter table public.os_student_course_enrollments add column if not exists offering_id uuid references public.course_offerings(id) on delete set null;
alter table public.os_student_course_enrollments add column if not exists hour_pool_id uuid;
create unique index if not exists os_sce_enrollment_item_unique on public.os_student_course_enrollments(enrollment_item_id) where enrollment_item_id is not null;
create index if not exists os_sce_source_enrollment_idx on public.os_student_course_enrollments(source_enrollment_id);

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
-- The public form already saved canonical UUIDs under raw_payload.courseItems.
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

-- Re-fire item sync for all current canonical items.
update public.enrollment_items set updated_at=now();

commit;

-- Diagnostic result: rows here should now match the Student Portal course cards.
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
