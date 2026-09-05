-- AreWarin Dynamic Schedule upgrade
-- Use this ONLY if you already ran the older starter schema.
-- It resets the old hard-coded weekly tutor_schedules table.

begin;

drop table if exists public.schedule_reservations cascade;
drop table if exists public.tutor_schedules cascade;
drop table if exists public.schedule_templates cascade;

create table public.schedule_templates (
  id uuid primary key default gen_random_uuid(),
  label text,
  start_time time not null,
  end_time time not null,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(end_time > start_time),
  unique(start_time,end_time)
);

create table public.tutor_schedules (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutors(id) on delete cascade,
  weekday smallint not null check(weekday between 1 and 7),
  time_template_id uuid not null references public.schedule_templates(id) on delete cascade,
  status text not null default 'available' check(status in ('available','blocked')),
  capacity integer not null default 1 check(capacity between 1 and 100),
  note text,
  updated_at timestamptz not null default now(),
  unique(tutor_id,weekday,time_template_id)
);

create table public.schedule_reservations (
  id uuid primary key default gen_random_uuid(),
  tutor_schedule_id uuid not null references public.tutor_schedules(id) on delete cascade,
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  seats integer not null default 1 check(seats between 1 and 100),
  status text not null default 'reserved' check(status in ('reserved','confirmed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tutor_schedule_id,enrollment_id)
);

create or replace function public.get_public_schedule(p_tutor_ids uuid[])
returns table(
  schedule_id uuid,
  tutor_id uuid,
  weekday smallint,
  template_id uuid,
  label text,
  start_time text,
  end_time text,
  status text,
  capacity integer,
  reserved_seats bigint,
  remaining_seats bigint
)
language sql stable security definer set search_path=public as $$
  select s.id,s.tutor_id,s.weekday,st.id,
    coalesce(nullif(st.label,''),to_char(st.start_time,'HH24:MI')||'-'||to_char(st.end_time,'HH24:MI')),
    to_char(st.start_time,'HH24:MI'),to_char(st.end_time,'HH24:MI'),
    s.status,s.capacity,
    coalesce(sum(r.seats) filter(where r.status in('reserved','confirmed')),0)::bigint,
    greatest(s.capacity-coalesce(sum(r.seats) filter(where r.status in('reserved','confirmed')),0),0)::bigint
  from public.tutor_schedules s
  join public.schedule_templates st on st.id=s.time_template_id and st.active=true
  left join public.schedule_reservations r on r.tutor_schedule_id=s.id
  where s.tutor_id=any(p_tutor_ids)
  group by s.id,s.tutor_id,s.weekday,st.id,st.label,st.start_time,st.end_time,s.status,s.capacity
  order by s.weekday,st.sort_order,st.start_time;
$$;

grant execute on function public.get_public_schedule(uuid[]) to anon,authenticated;

create or replace function public.reserve_enrollment_schedule(
  p_enrollment_id uuid,
  p_tutor_ids uuid[],
  p_selections jsonb,
  p_seats integer default 1
)
returns void language plpgsql security definer set search_path=public as $$
declare
  sel jsonb;
  v_tutor uuid;
  v_weekday smallint;
  v_template uuid;
  v_schedule public.tutor_schedules%rowtype;
  v_used integer;
  v_seats integer:=greatest(1,coalesce(p_seats,1));
begin
  if p_selections is null or jsonb_array_length(p_selections)=0 then raise exception 'กรุณาเลือกเวลาเรียน'; end if;
  for sel in select * from jsonb_array_elements(p_selections) loop
    v_weekday:=(sel->>'weekday')::smallint;
    v_template:=(sel->>'templateId')::uuid;
    foreach v_tutor in array p_tutor_ids loop
      select * into v_schedule from public.tutor_schedules
      where tutor_id=v_tutor and weekday=v_weekday and time_template_id=v_template for update;
      if not found or v_schedule.status<>'available' then raise exception 'ช่วงเวลาที่เลือกมีการเปลี่ยนแปลง กรุณาเลือกเวลาใหม่'; end if;
      select coalesce(sum(seats),0)::integer into v_used from public.schedule_reservations
      where tutor_schedule_id=v_schedule.id and status in('reserved','confirmed');
      if (v_schedule.capacity-v_used)<v_seats then raise exception 'ช่วงเวลาที่เลือกเต็มแล้ว กรุณาเลือกเวลาใหม่'; end if;
      insert into public.schedule_reservations(tutor_schedule_id,enrollment_id,seats,status,updated_at)
      values(v_schedule.id,p_enrollment_id,v_seats,'reserved',now())
      on conflict(tutor_schedule_id,enrollment_id)
      do update set seats=excluded.seats,status='reserved',updated_at=now();
    end loop;
  end loop;
end $$;

revoke all on function public.reserve_enrollment_schedule(uuid,uuid[],jsonb,integer) from public;
grant execute on function public.reserve_enrollment_schedule(uuid,uuid[],jsonb,integer) to service_role;

alter table public.schedule_templates enable row level security;
alter table public.tutor_schedules enable row level security;
alter table public.schedule_reservations enable row level security;

create policy "public schedule templates" on public.schedule_templates for select to anon,authenticated using(active or public.is_manager());
create policy "manager schedule templates" on public.schedule_templates for all to authenticated using(public.is_manager()) with check(public.is_manager());
create policy "manager schedules" on public.tutor_schedules for all to authenticated using(public.is_manager()) with check(public.is_manager());
create policy "manager schedule reservations" on public.schedule_reservations for all to authenticated using(public.is_manager()) with check(public.is_manager());

insert into public.schedule_templates(label,start_time,end_time,sort_order) values
('09:00-11:00','09:00','11:00',10),('11:00-13:00','11:00','13:00',20),('13:00-15:00','13:00','15:00',30),
('15:00-16:30','15:00','16:30',40),('16:30-18:00','16:30','18:00',50),('17:00-18:00','17:00','18:00',60),
('18:00-19:30','18:00','19:30',70),('19:30-21:00','19:30','21:00',80),('20:00-21:30','20:00','21:30',90),
('20:00-21:00','20:00','21:00',100),('21:00-21:30','21:00','21:30',110),('21:30-23:00','21:30','23:00',120)
on conflict(start_time,end_time) do update set label=excluded.label,sort_order=excluded.sort_order,active=true;

insert into public.tutor_schedules(tutor_id,weekday,time_template_id,status,capacity)
select t.id,d.weekday,st.id,'available',1
from public.tutors t
cross join(values(1),(2),(3),(4),(5),(6),(7)) as d(weekday)
cross join public.schedule_templates st
where t.active=true and st.active=true
on conflict(tutor_id,weekday,time_template_id) do nothing;

commit;
