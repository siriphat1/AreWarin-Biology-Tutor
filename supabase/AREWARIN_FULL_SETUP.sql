-- ============================================================
-- AREWARIN BIOLOGY — COMPLETE SUPABASE SETUP (FRESH PROJECT)
-- ============================================================
-- Includes:
--   • Manager/Admin roles + RLS
--   • Tutors / Courses / Prices / Promotions
--   • Dynamic weekly schedule + capacity + reservations
--   • Enrollments / Payments / Receipt settings + numbering
--   • Speaker requests
--   • Student reviews + review image storage
--   • Website logo / branding / rotating banners
--   • Subject categories with Manager open/close control
--   • Storage buckets for slips, receipts, tutors, courses, reviews, site assets
--   • Seed data matching the current AreWarin website
--
-- Run in: Supabase Dashboard > SQL Editor > New query > Run
-- IMPORTANT: Edge Functions are deployed separately; SQL cannot create them.
-- ============================================================

begin;
create extension if not exists pgcrypto;

-- ---------- Roles / Manager auth ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  role text not null default 'manager' check (role in ('manager','admin')),
  created_at timestamptz not null default now()
);

create or replace function public.is_manager()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles p where p.id = auth.uid() and p.role in ('manager','admin'));
$$;

-- ---------- Catalog ----------
create table if not exists public.tutors (
  id uuid primary key default gen_random_uuid(),
  display_name text not null unique,
  full_name text,
  role_text text,
  image_url text,
  video_id text,
  education text[] not null default '{}',
  awards text[] not null default '{}',
  levels text[] not null default '{}',
  categories text[] not null default '{}',
  border_color text default 'border-sky-100 hover:border-sky-500',
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.courses (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutors(id) on delete cascade,
  name text not null,
  course_type text not null default 'content' check (course_type in ('content','exam')),
  short_detail text,
  image_url text,
  full_description text,
  target_text text,
  outcomes text[] not null default '{}',
  syllabus text[] not null default '{}',
  badge text,
  is_university boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tutor_id,name)
);

create table if not exists public.course_prices (
  id uuid primary key default gen_random_uuid(),
  tier text not null check (tier in ('standard','university')),
  package_code text not null check (package_code in ('yearly','monthly','pack20','pack10','hourly')),
  label text not null,
  amount numeric(12,2) not null check (amount >= 0),
  active boolean not null default true,
  updated_at timestamptz not null default now(),
  unique(tier,package_code)
);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text,
  discount_type text not null default 'fixed' check(discount_type in ('fixed','percent')),
  discount_value numeric(12,2) not null check(discount_value >= 0),
  starts_at timestamptz,
  ends_at timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null default 'null'::jsonb,
  description text,
  updated_at timestamptz not null default now()
);

-- ---------- Enrollment / Payment / Receipt ----------
create table if not exists public.enrollments (
  id uuid primary key default gen_random_uuid(),
  receipt_no text unique,
  receipt_token uuid not null default gen_random_uuid() unique,
  student_type text not null default 'new' check(student_type in ('new','old')),
  fullname text not null,
  nickname text,
  phone text,
  line_id text,
  email text,
  grade text,
  school text,
  faculty text,
  province text,
  parent_name text,
  parent_relation text,
  parent_phone text,
  study_type text,
  group_size integer not null default 1,
  additional_students jsonb not null default '[]'::jsonb,
  tutor_text text,
  course_text text,
  mode_text text,
  hours_text text,
  time_text text,
  amount_quoted numeric(12,2) not null default 0,
  promotion_code text,
  status text not null default 'pending_payment_verification' check(status in ('pending_payment_verification','confirmed','cancelled','rejected')),
  raw_payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  enrollment_id uuid not null unique references public.enrollments(id) on delete cascade,
  payment_method text not null check(payment_method in ('transfer','cash')),
  amount_submitted numeric(12,2) not null default 0,
  verified_amount numeric(12,2),
  slip_path text,
  status text not null default 'pending' check(status in ('pending','paid','rejected','cancelled')),
  rejection_reason text,
  verified_at timestamptz,
  verified_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.receipt_settings (
  id integer primary key default 1 check(id=1),
  business_name text not null default 'กวดวิชาชีววิทยา อาวริน',
  business_name_en text default 'AreWarin Biology',
  tax_id text,
  address text,
  phone text,
  receipt_prefix text not null default 'AR',
  logo_path text,
  signature_path text,
  signer_name text,
  signer_position text default 'ผู้รับเงิน',
  show_logo boolean not null default true,
  show_signature boolean not null default true,
  footer_text text default 'ขอบคุณที่ไว้วางใจ AreWarin Biology',
  updated_at timestamptz not null default now()
);

create table if not exists public.receipt_sequences (
  receipt_year integer primary key,
  last_no bigint not null default 0
);

create or replace function public.next_receipt_no()
returns text language plpgsql security definer set search_path=public as $$
declare
  y integer := extract(year from now())::integer;
  n bigint;
  p text;
begin
  insert into public.receipt_sequences(receipt_year,last_no) values(y,1)
  on conflict(receipt_year) do update set last_no = receipt_sequences.last_no + 1
  returning last_no into n;
  select coalesce(receipt_prefix,'AR') into p from public.receipt_settings where id=1;
  return p || '-' || y::text || '-' || lpad(n::text,6,'0');
end $$;

-- ---------- Dynamic weekly schedule ----------
-- Manager can add/remove arbitrary time ranges. Students only see slots that are
-- explicitly opened for every tutor in their cart.
create table if not exists public.schedule_templates (
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

create table if not exists public.tutor_schedules (
  id uuid primary key default gen_random_uuid(),
  tutor_id uuid not null references public.tutors(id) on delete cascade,
  weekday smallint not null check(weekday between 1 and 7), -- 1=Mon ... 7=Sun
  time_template_id uuid not null references public.schedule_templates(id) on delete cascade,
  status text not null default 'available' check(status in ('available','blocked')),
  capacity integer not null default 1 check(capacity between 1 and 100),
  note text,
  updated_at timestamptz not null default now(),
  unique(tutor_id,weekday,time_template_id)
);

create table if not exists public.schedule_reservations (
  id uuid primary key default gen_random_uuid(),
  tutor_schedule_id uuid not null references public.tutor_schedules(id) on delete cascade,
  enrollment_id uuid not null references public.enrollments(id) on delete cascade,
  seats integer not null default 1 check(seats between 1 and 100),
  status text not null default 'reserved' check(status in ('reserved','confirmed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(tutor_schedule_id,enrollment_id)
);

-- Public-safe availability. Reservation/student details never leave this function.
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
language sql
stable
security definer
set search_path=public
as $$
  select
    s.id,
    s.tutor_id,
    s.weekday,
    st.id,
    coalesce(nullif(st.label,''), to_char(st.start_time,'HH24:MI') || '-' || to_char(st.end_time,'HH24:MI')),
    to_char(st.start_time,'HH24:MI'),
    to_char(st.end_time,'HH24:MI'),
    s.status,
    s.capacity,
    coalesce(sum(r.seats) filter (where r.status in ('reserved','confirmed')),0)::bigint,
    greatest(
      s.capacity - coalesce(sum(r.seats) filter (where r.status in ('reserved','confirmed')),0),
      0
    )::bigint
  from public.tutor_schedules s
  join public.schedule_templates st on st.id=s.time_template_id and st.active=true
  left join public.schedule_reservations r on r.tutor_schedule_id=s.id
  where s.tutor_id = any(p_tutor_ids)
  group by s.id,s.tutor_id,s.weekday,st.id,st.label,st.start_time,st.end_time,s.status,s.capacity
  order by s.weekday,st.sort_order,st.start_time;
$$;

grant execute on function public.get_public_schedule(uuid[]) to anon, authenticated;

-- Atomic capacity check used only by the trusted create-enrollment Edge Function.
create or replace function public.reserve_enrollment_schedule(
  p_enrollment_id uuid,
  p_tutor_ids uuid[],
  p_selections jsonb,
  p_seats integer default 1
)
returns void
language plpgsql
security definer
set search_path=public
as $$
declare
  sel jsonb;
  v_tutor uuid;
  v_weekday smallint;
  v_template uuid;
  v_schedule public.tutor_schedules%rowtype;
  v_used integer;
  v_seats integer := greatest(1,coalesce(p_seats,1));
begin
  if p_selections is null or jsonb_array_length(p_selections)=0 then
    raise exception 'กรุณาเลือกเวลาเรียน';
  end if;

  for sel in select * from jsonb_array_elements(p_selections)
  loop
    v_weekday := (sel->>'weekday')::smallint;
    v_template := (sel->>'templateId')::uuid;

    foreach v_tutor in array p_tutor_ids
    loop
      select * into v_schedule
      from public.tutor_schedules
      where tutor_id=v_tutor
        and weekday=v_weekday
        and time_template_id=v_template
      for update;

      if not found or v_schedule.status <> 'available' then
        raise exception 'ช่วงเวลาที่เลือกมีการเปลี่ยนแปลง กรุณาเลือกเวลาใหม่';
      end if;

      select coalesce(sum(seats),0)::integer into v_used
      from public.schedule_reservations
      where tutor_schedule_id=v_schedule.id
        and status in ('reserved','confirmed');

      if (v_schedule.capacity - v_used) < v_seats then
        raise exception 'ช่วงเวลาที่เลือกเต็มแล้ว กรุณาเลือกเวลาใหม่';
      end if;

      insert into public.schedule_reservations(
        tutor_schedule_id,enrollment_id,seats,status,updated_at
      )
      values(v_schedule.id,p_enrollment_id,v_seats,'reserved',now())
      on conflict(tutor_schedule_id,enrollment_id)
      do update set seats=excluded.seats,status='reserved',updated_at=now();
    end loop;
  end loop;
end $$;

revoke all on function public.reserve_enrollment_schedule(uuid,uuid[],jsonb,integer) from public;
grant execute on function public.reserve_enrollment_schedule(uuid,uuid[],jsonb,integer) to service_role;

-- ---------- Speaker requests ----------
create table if not exists public.speaker_requests (
  id uuid primary key default gen_random_uuid(),
  organization text not null,
  coordinator_name text not null,
  phone text not null,
  email text,
  subject text not null,
  tutor_name text,
  topic text not null,
  event_datetime_text text not null,
  location_text text not null,
  audience_text text not null,
  budget_text text,
  wants_quotation boolean not null default true,
  details text,
  status text not null default 'pending' check(status in ('pending','contacted','quoted','confirmed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Minimal public phone status lookup (exact normalized phone only).
create or replace function public.check_application_status(p_phone text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r record; q text := regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  if length(q) < 9 then return jsonb_build_object('found',false); end if;
  select e.*, p.status as payment_status
  into r
  from public.enrollments e left join public.payments p on p.enrollment_id=e.id
  where regexp_replace(coalesce(e.phone,''),'\D','','g') = q
  order by e.created_at desc limit 1;
  if not found then return jsonb_build_object('found',false); end if;
  return jsonb_build_object(
    'found',true,
    'name',r.fullname,
    'course',r.course_text,
    'tutor',r.tutor_text,
    'time',r.time_text,
    'price',r.amount_quoted,
    'date',to_char(r.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),
    'paymentStatus',coalesce(r.payment_status,'pending'),
    'receiptNo',r.receipt_no,
    'receiptToken',r.receipt_token
  );
end $$;

grant execute on function public.check_application_status(text) to anon, authenticated;

-- ---------- RLS ----------
alter table public.profiles enable row level security;
alter table public.tutors enable row level security;
alter table public.courses enable row level security;
alter table public.course_prices enable row level security;
alter table public.promotions enable row level security;
alter table public.app_settings enable row level security;
alter table public.enrollments enable row level security;
alter table public.payments enable row level security;
alter table public.receipt_settings enable row level security;
alter table public.schedule_templates enable row level security;
alter table public.tutor_schedules enable row level security;
alter table public.schedule_reservations enable row level security;
alter table public.speaker_requests enable row level security;

drop policy if exists "profile self read" on public.profiles;
create policy "profile self read" on public.profiles for select to authenticated using (id=auth.uid() or public.is_manager());
drop policy if exists "manager profiles" on public.profiles;
create policy "manager profiles" on public.profiles for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public active tutors" on public.tutors;
create policy "public active tutors" on public.tutors for select to anon,authenticated using(active or public.is_manager());
drop policy if exists "manager tutors" on public.tutors;
create policy "manager tutors" on public.tutors for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public active courses" on public.courses;
create policy "public active courses" on public.courses for select to anon,authenticated using(active or public.is_manager());
drop policy if exists "manager courses" on public.courses;
create policy "manager courses" on public.courses for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public active prices" on public.course_prices;
create policy "public active prices" on public.course_prices for select to anon,authenticated using(active or public.is_manager());
drop policy if exists "manager prices" on public.course_prices;
create policy "manager prices" on public.course_prices for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public valid promotions" on public.promotions;
create policy "public valid promotions" on public.promotions for select to anon,authenticated
using(public.is_manager() or (active and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at >= now())));
drop policy if exists "manager promotions" on public.promotions;
create policy "manager promotions" on public.promotions for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public settings read" on public.app_settings;
create policy "public settings read" on public.app_settings for select to anon,authenticated using(true);
drop policy if exists "manager settings" on public.app_settings;
create policy "manager settings" on public.app_settings for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "manager enrollments" on public.enrollments;
create policy "manager enrollments" on public.enrollments for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager payments" on public.payments;
create policy "manager payments" on public.payments for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager receipt settings" on public.receipt_settings;
create policy "manager receipt settings" on public.receipt_settings for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public schedule templates" on public.schedule_templates;
create policy "public schedule templates" on public.schedule_templates for select to anon,authenticated using(active or public.is_manager());
drop policy if exists "manager schedule templates" on public.schedule_templates;
create policy "manager schedule templates" on public.schedule_templates for all to authenticated using(public.is_manager()) with check(public.is_manager());

-- Direct schedule rows/reservations are private to Manager. Public reads use get_public_schedule().
drop policy if exists "manager schedules" on public.tutor_schedules;
create policy "manager schedules" on public.tutor_schedules for all to authenticated using(public.is_manager()) with check(public.is_manager());
drop policy if exists "manager schedule reservations" on public.schedule_reservations;
create policy "manager schedule reservations" on public.schedule_reservations for all to authenticated using(public.is_manager()) with check(public.is_manager());

drop policy if exists "public speaker submit" on public.speaker_requests;
create policy "public speaker submit" on public.speaker_requests for insert to anon,authenticated with check(true);
drop policy if exists "manager speaker requests" on public.speaker_requests;
create policy "manager speaker requests" on public.speaker_requests for all to authenticated using(public.is_manager()) with check(public.is_manager());

-- ---------- Storage ----------
insert into storage.buckets(id,name,public) values
  ('payment-slips','payment-slips',false),
  ('receipt-assets','receipt-assets',false),
  ('tutor-assets','tutor-assets',true),
  ('course-assets','course-assets',true)
on conflict(id) do update set public=excluded.public;

-- Public media read; manager controls writes.
drop policy if exists "public tutor assets read" on storage.objects;
create policy "public tutor assets read" on storage.objects for select to anon,authenticated using(bucket_id='tutor-assets');
drop policy if exists "public course assets read" on storage.objects;
create policy "public course assets read" on storage.objects for select to anon,authenticated using(bucket_id='course-assets');
drop policy if exists "manager tutor assets" on storage.objects;
create policy "manager tutor assets" on storage.objects for all to authenticated using(bucket_id='tutor-assets' and public.is_manager()) with check(bucket_id='tutor-assets' and public.is_manager());
drop policy if exists "manager course assets" on storage.objects;
create policy "manager course assets" on storage.objects for all to authenticated using(bucket_id='course-assets' and public.is_manager()) with check(bucket_id='course-assets' and public.is_manager());
drop policy if exists "manager payment slips" on storage.objects;
create policy "manager payment slips" on storage.objects for select to authenticated using(bucket_id='payment-slips' and public.is_manager());
drop policy if exists "manager receipt assets" on storage.objects;
create policy "manager receipt assets" on storage.objects for all to authenticated using(bucket_id='receipt-assets' and public.is_manager()) with check(bucket_id='receipt-assets' and public.is_manager());

-- ---------- Initial settings / prices ----------
insert into public.receipt_settings(id,business_name,business_name_en,tax_id,address,phone,receipt_prefix,signer_position,footer_text)
values(1,'กวดวิชาชีววิทยา อาวริน','AreWarin Biology','1901001151577','122/7 ม.2 ต.มิตรภาพ อ.สีคิ้ว จ.นครราชสีมา 30140','080-508-5157','AR','ผู้รับเงิน','ขอบคุณที่ไว้วางใจ AreWarin Biology')
on conflict(id) do nothing;

insert into public.course_prices(tier,package_code,label,amount) values
('standard','yearly','รายปี',19900),('standard','monthly','30 ชั่วโมง',4900),('standard','pack20','20 ชั่วโมง',3200),('standard','pack10','10 ชั่วโมง',1650),('standard','hourly','รายชั่วโมง',170),
('university','yearly','รายปี',25900),('university','monthly','30 ชั่วโมง',6500),('university','pack20','20 ชั่วโมง',4500),('university','pack10','10 ชั่วโมง',2500),('university','hourly','รายชั่วโมง',250)
on conflict(tier,package_code) do nothing;

insert into public.app_settings(key,value,description) values
('COURSE_YEARLY','"OPEN"'::jsonb,'คอร์สรายปี'),('COURSE_30H','"OPEN"'::jsonb,'คอร์ส 30 ชั่วโมง'),('COURSE_20H','"OPEN"'::jsonb,'คอร์ส 20 ชั่วโมง'),('COURSE_10H','"OPEN"'::jsonb,'คอร์ส 10 ชั่วโมง'),('COURSE_HOURLY','"OPEN"'::jsonb,'รายชั่วโมง'),('ONSITE_OPTION','"OPEN"'::jsonb,'Onsite'),('ANNOUNCEMENT_STATUS','"CLOSE"'::jsonb,'Popup'),('ANNOUNCEMENT_IMG','""'::jsonb,'รูปประกาศ'),('ANNOUNCEMENT_MSG','""'::jsonb,'ข้อความประกาศ'),('MAINTENANCE_START','""'::jsonb,'เริ่มปิดระบบ'),('MAINTENANCE_END','""'::jsonb,'เปิดระบบ')
on conflict(key) do nothing;

insert into public.promotions(code,name,discount_type,discount_value,active)
values('SALE100','ส่วนลด 100 บาท','fixed',100,true)
on conflict(code) do nothing;

-- ---------- Seed default time ranges ----------
insert into public.schedule_templates(label,start_time,end_time,sort_order) values
('09:00-11:00','09:00','11:00',10),
('11:00-13:00','11:00','13:00',20),
('13:00-15:00','13:00','15:00',30),
('15:00-16:30','15:00','16:30',40),
('16:30-18:00','16:30','18:00',50),
('17:00-18:00','17:00','18:00',60),
('18:00-19:30','18:00','19:30',70),
('19:30-21:00','19:30','21:00',80),
('20:00-21:30','20:00','21:30',90),
('20:00-21:00','20:00','21:00',100),
('21:00-21:30','21:00','21:30',110),
('21:30-23:00','21:30','23:00',120)
on conflict(start_time,end_time) do nothing;

-- ---------- Seed original tutors ----------
insert into public.tutors(display_name,full_name,role_text,image_url,video_id,education,awards,levels,categories,border_color,sort_order)
values
('พี่อาร์','สุธาวริน ศิริภัทราณิชา','ชีววิทยา ม.ปลาย','https://img2.pic.in.th/pic/531691933_1782062845771076_6500762805646335341_n.jpg','n7OmFntD-Ss',array['กำลังศึกษา ป.โท ชีวเคมีทางการแพทย์ฯ มข.','วท.บ. ชีววิทยา (เกียรตินิยมอันดับ 1)'],array['เหรียญทอง ทักษะวิทยาศาสตร์ระดับประเทศ'],array['senior','university'],array['bio'],'border-sky-100 hover:border-sky-500',10),
('พี่เอ็มมี่','กีรติยาพร โหจันทึก','วิทย์ ม.ต้น','https://img5.pic.in.th/file/secure-sv1/10000149872150ba1db90bab6b.jpg','',array['กำลังศึกษา ป.โท สาขาพยาธิวิทยา มข.','วท.บ. ชีววิทยา (เกียรตินิยมอันดับ 2)'],array[]::text[],array['junior'],array['sci'],'border-pink-100 hover:border-pink-500',20),
('พี่ฟิล์ม','อาทิตยา ใหม่ห้อง','วิทย์-คณิต ประถม','https://img5.pic.in.th/file/secure-sv1/1000014988bae43c3a84d9756a.jpg','',array['กำลังศึกษา ป.โท สาขากายวิภาคศาสตร์ มข.','วท.บ. สาขาวิทยาศาสตร์การแพทย์'],array[]::text[],array['primary'],array['sci','math'],'border-amber-100 hover:border-amber-500',30),
('พี่ต้อง','ปราการ บุญใส','เคมี ม.ต้น - ม.ปลาย','https://img5.pic.in.th/file/secure-sv1/597388940_877671237995405_756803582194104517_n.jpg','',array['คณะเภสัชศาสตร์ ม.อุบลราชธานี','สอวน. เคมี ค่าย 2'],array[]::text[],array['junior','senior','university'],array['chem'],'border-green-100 hover:border-green-500',40)
on conflict(display_name) do nothing;

-- Open the default weekly grid to match the legacy system (Manager can edit it anytime).
insert into public.tutor_schedules(tutor_id,weekday,time_template_id,status,capacity)
select t.id,d.weekday,st.id,'available',1
from public.tutors t
cross join (values(1),(2),(3),(4),(5),(6),(7)) as d(weekday)
cross join public.schedule_templates st
where t.active=true and st.active=true
on conflict(tutor_id,weekday,time_template_id) do nothing;

-- ---------- Seed original courses ----------
insert into public.courses(tutor_id,name,course_type,short_detail,image_url,full_description,target_text,badge,is_university,sort_order)
select t.id,v.name,v.course_type,v.short_detail,v.image_url,v.full_description,v.target_text,v.badge,v.is_university,v.sort_order
from public.tutors t join (values
('พี่อาร์','เตรียมสอบ สอวน. ชีววิทยา','content','ปูพื้นฐานและเจาะลึกเนื้อหา','https://www.posn.or.th/wp-content/uploads/2024/06/posn-favicon.png','ปูพื้นฐานและเจาะลึกเนื้อหาชีววิทยา','ม.3 - ม.5','star',false,10),
('พี่อาร์','เตรียมสอบ NetSat ชีววิทยา','content','เจาะลึกข้อสอบ มข.','https://netsat.kku.ac.th/home/wp-content/uploads/2021/07/LOGO_NETSAT.png','สรุปเนื้อหาชีววิทยา ม.ปลาย เฉพาะจุด','ม.4 - ม.6','recommend',false,20),
('พี่อาร์','เตรียมสอบ A-Level ชีววิทยา','content','เนื้อหา ม.ปลาย ครบตาม Blueprint','https://images.unsplash.com/photo-1559757175-5700dde675bc?q=80&w=2070&auto=format&fit=crop','สรุปคอนเซปต์ชีววิทยา ม.4 - ม.6','ม.5 - ม.6','new',false,30),
('พี่อาร์','ชีวเคมี (Biochemistry)','content','เจาะลึกหัวข้อปราบเซียน','https://images.unsplash.com/photo-1579154204601-01588f351e67?q=80&w=2070&auto=format&fit=crop','เจาะลึกเรื่อง สารชีวโมเลกุล','ม.ปลาย / มหาวิทยาลัย','',true,40),
('พี่อาร์','ตะลุยโจทย์ สอวน. ชีววิทยา','exam','ทำข้อสอบเก่า 100%','https://www.posn.or.th/wp-content/uploads/2024/06/posn-favicon.png','ตะลุยข้อสอบค่าย 1','คนที่แม่นเนื้อหาแล้ว','',false,50),
('พี่อาร์','ตะลุยโจทย์ NetSat ชีววิทยา','exam','เน้นทำข้อสอบเก่า Speed Test','https://netsat.kku.ac.th/home/wp-content/uploads/2021/07/LOGO_NETSAT.png','เน้นทำข้อสอบเก่า NetSat','ม.6 ดึงคะแนนเข้า มข.','',false,60),
('พี่อาร์','ตะลุยโจทย์ A-Level ชีววิทยา','exam','โฟกัสโจทย์ประยุกต์ ทปอ.','https://images.unsplash.com/photo-1434030216411-0b793f4b4173?q=80&w=2070&auto=format&fit=crop','ตะลุยแนวข้อสอบจริง A-Level','เด็ก ม.6 โค้งสุดท้าย','',false,70),
('พี่เอ็มมี่','วิทยาศาสตร์ ม.ต้น','content','ปูพื้นฐาน ม.1-3','https://images.unsplash.com/photo-1532094349884-543bc11b234d?q=80&w=2070&auto=format&fit=crop','ปูพื้นฐานวิทยาศาสตร์...','น้อง ม.1-3...','recommend',false,10),
('พี่เอ็มมี่','ติวสอบเข้า ม.4','content','โรงเรียนแข่งขันสูง','https://images.unsplash.com/photo-1581093458791-9f3c3900df4b?q=80&w=2070&auto=format&fit=crop','สรุปเข้มวิทย์...','น้อง ม.3...','',false,20),
('พี่เอ็มมี่','IJSO วิทย์','exam','ติวสอบโอลิมปิกต้น','https://images.unsplash.com/photo-1507413245164-6160d8298b31?q=80&w=2070&auto=format&fit=crop','ติวเข้มเนื้อหา...','น้อง ม.1-2...','',false,30),
('พี่ฟิล์ม','วิทยาศาสตร์ ประถม','content','ป.1 - ป.6','https://images.unsplash.com/photo-1564325724739-bae0bd08762c?q=80&w=2070&auto=format&fit=crop','เรียนรู้ผ่านการทดลอง...','น้อง ป.1-6...','recommend',false,10),
('พี่ฟิล์ม','คณิตศาสตร์ ประถม','content','คิดเลขเร็ว แก้โจทย์','https://images.unsplash.com/photo-1635070041078-e363dbe005cb?q=80&w=2070&auto=format&fit=crop','ฝึกทักษะการคำนวณ...','น้อง ป.1-6...','',false,20),
('พี่ฟิล์ม','สอบเข้า ม.1','exam','ติวเข้มโค้งสุดท้าย','https://images.unsplash.com/photo-1454165804606-c3d57bc86b40?q=80&w=2070&auto=format&fit=crop','ติวเข้มวิทย์-คณิต...','น้อง ป.6...','',false,30),
('พี่ต้อง','เคมี ม.ต้น','content','ปูพื้นฐานเคมี','https://images.unsplash.com/photo-1628863353691-0071c8c1874c?q=80&w=2070&auto=format&fit=crop','ปูพื้นฐานเคมี...','น้อง ม.1-3...','',false,10),
('พี่ต้อง','เคมี ม.ปลาย','content','เนื้อหาครบ ตะลุยโจทย์','https://images.unsplash.com/photo-1603126857599-f6e157fa2fe6?q=80&w=2070&auto=format&fit=crop','เจาะลึกเนื้อหา...','น้อง ม.4-6...','',false,20),
('พี่ต้อง','สอวน. เคมี','exam','ติวเข้มโอลิมปิก','https://images.unsplash.com/photo-1532187863486-abf9dbad1b69?q=80&w=2070&auto=format&fit=crop','ติวเข้มเนื้อหา...','น้อง ม.3-5...','',false,30),
('พี่ต้อง','เคมี มหาวิทยาลัย','content','General Chemistry','https://images.unsplash.com/photo-1554475901-4538ddfbccc2?q=80&w=2072&auto=format&fit=crop','ติวเคมีทั่วไป...','นิสิต/นักศึกษา...','',true,40)
) as v(tutor_name,name,course_type,short_detail,image_url,full_description,target_text,badge,is_university,sort_order)
on t.display_name=v.tutor_name
on conflict(tutor_id,name) do nothing;

-- ============================================================
-- STUDENT REVIEWS
-- ============================================================
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  student_name text not null,
  school text,
  course_name text,
  review_text text not null,
  image_url text,
  rating smallint not null default 5 check (rating between 1 and 5),
  featured boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reviews_public_order_idx
  on public.reviews(active, featured desc, sort_order, created_at desc);

alter table public.reviews enable row level security;

drop policy if exists "public active reviews" on public.reviews;
create policy "public active reviews"
  on public.reviews for select to anon, authenticated
  using (active or public.is_manager());

drop policy if exists "manager reviews" on public.reviews;
create policy "manager reviews"
  on public.reviews for all to authenticated
  using (public.is_manager())
  with check (public.is_manager());

insert into storage.buckets(id,name,public)
values ('review-assets','review-assets',true)
on conflict(id) do update set public=excluded.public;

drop policy if exists "public review assets read" on storage.objects;
create policy "public review assets read"
  on storage.objects for select to anon, authenticated
  using (bucket_id='review-assets');

drop policy if exists "manager review assets" on storage.objects;
create policy "manager review assets"
  on storage.objects for all to authenticated
  using (bucket_id='review-assets' and public.is_manager())
  with check (bucket_id='review-assets' and public.is_manager());

-- ============================================================
-- SITE BRANDING / HOME BANNERS / SUBJECT CATEGORIES
-- ============================================================
create table if not exists public.site_branding (
  id smallint primary key default 1 check (id = 1),
  logo_url text,
  site_name_th text not null default 'กวดวิชาชีววิทยา อาวริน',
  site_name_en text not null default 'AreWarin Biology',
  tagline text not null default 'เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย',
  location_badge text default 'Onsite @ขอนแก่น',
  registration_badge text default '🚀 เปิดรับสมัครแล้ว!',
  updated_at timestamptz not null default now()
);

create table if not exists public.home_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  highlight_text text,
  description text,
  badge_text text,
  location_text text,
  image_url text,
  link_url text,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subject_categories (
  id text primary key check (id ~ '^[a-z0-9_-]+$'),
  name_th text not null,
  name_en text,
  icon_class text not null default 'fas fa-book-open',
  theme text not null default 'sky' check(theme in ('rose','teal','indigo','amber','sky','violet','emerald','slate')),
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.site_branding enable row level security;
alter table public.home_banners enable row level security;
alter table public.subject_categories enable row level security;

-- Idempotent policy creation.
do $$ begin
  create policy "public site branding read" on public.site_branding
    for select to anon, authenticated using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager site branding" on public.site_branding
    for all to authenticated using (public.is_manager()) with check (public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public active banners read" on public.home_banners
    for select to anon, authenticated using (active or public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager banners" on public.home_banners
    for all to authenticated using (public.is_manager()) with check (public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public active categories read" on public.subject_categories
    for select to anon, authenticated using (active or public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager categories" on public.subject_categories
    for all to authenticated using (public.is_manager()) with check (public.is_manager());
exception when duplicate_object then null; end $$;

-- Public media bucket for logo/banner assets.
insert into storage.buckets(id,name,public)
values ('site-assets','site-assets',true)
on conflict(id) do update set public=excluded.public;

do $$ begin
  create policy "public site assets read" on storage.objects
    for select to anon, authenticated using(bucket_id='site-assets');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager site assets" on storage.objects
    for all to authenticated
    using(bucket_id='site-assets' and public.is_manager())
    with check(bucket_id='site-assets' and public.is_manager());
exception when duplicate_object then null; end $$;

-- Seed current branding once.
insert into public.site_branding(
  id,logo_url,site_name_th,site_name_en,tagline,location_badge,registration_badge
) values (
  1,
  'https://img2.pic.in.th/pic/531691933_1782062845771076_6500762805646335341_n.jpg',
  'กวดวิชาชีววิทยา อาวริน',
  'AreWarin Biology',
  'เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย',
  'Onsite @ขอนแก่น',
  '🚀 เปิดรับสมัครแล้ว!'
)
on conflict(id) do nothing;

-- Seed banners only if the table is empty.
insert into public.home_banners(title,highlight_text,description,badge_text,location_text,image_url,active,sort_order)
select * from (values
  ('กวดวิชาชีววิทยา','อาวริน','เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย','🚀 เปิดรับสมัครแล้ว!','Onsite @ขอนแก่น','https://images.unsplash.com/photo-1532094349884-543bc11b234d?q=80&w=2070&auto=format&fit=crop',true,10),
  ('ติวเข้ม','มัธยมปลาย','ชีวะ - เคมี A-Level / NETSAT / สอวน.','เตรียมสอบอย่างเป็นระบบ','Online & Onsite','https://images.unsplash.com/photo-1576086213369-97a306d36557?q=80&w=2080&auto=format&fit=crop',true,20),
  ('ปูพื้นฐาน','ประถม - ม.ต้น','วิทย์ - คณิต สอนสนุก เข้าใจง่าย','พื้นฐานแน่น เรียนรู้สนุก','Online & Onsite','https://images.unsplash.com/photo-1503676260728-1c00da094a0b?q=80&w=2022&auto=format&fit=crop',true,30)
) as seed(title,highlight_text,description,badge_text,location_text,image_url,active,sort_order)
where not exists (select 1 from public.home_banners);

-- Seed current subject categories.
insert into public.subject_categories(id,name_th,name_en,icon_class,theme,active,sort_order) values
('bio','ชีววิทยา','Biology','fas fa-dna','rose',true,10),
('chem','เคมี','Chemistry','fas fa-flask','teal',true,20),
('sci','วิทยาศาสตร์','Science','fas fa-atom','indigo',true,30),
('math','คณิตศาสตร์','Mathematics','fas fa-calculator','amber',true,40)
on conflict(id) do nothing;

-- ============================================================
-- APPLICATION STATUS LOOKUP (LATEST + RECENT HISTORY)
-- ============================================================
create or replace function public.check_application_status(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  q text := regexp_replace(coalesce(p_phone,''),'\D','','g');
  latest jsonb;
  history jsonb;
begin
  if length(q) < 9 then
    return jsonb_build_object('found', false);
  end if;

  select jsonb_build_object(
      'found', true,
      'name', e.fullname,
      'course', e.course_text,
      'tutor', e.tutor_text,
      'time', e.time_text,
      'price', e.amount_quoted,
      'date', to_char(e.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),
      'createdAt', e.created_at,
      'paymentStatus', coalesce(p.status,'pending'),
      'enrollmentStatus', e.status,
      'paymentMethod', p.payment_method,
      'verifiedAt', p.verified_at,
      'rejectionReason', p.rejection_reason,
      'receiptNo', e.receipt_no,
      'receiptToken', e.receipt_token
    )
  into latest
  from public.enrollments e
  left join public.payments p on p.enrollment_id = e.id
  where regexp_replace(coalesce(e.phone,''),'\D','','g') = q
  order by e.created_at desc
  limit 1;

  if latest is null then
    return jsonb_build_object('found', false);
  end if;

  select coalesce(jsonb_agg(x.item order by x.created_at desc), '[]'::jsonb)
  into history
  from (
    select e.created_at,
      jsonb_build_object(
        'found', true,
        'name', e.fullname,
        'course', e.course_text,
        'tutor', e.tutor_text,
        'time', e.time_text,
        'price', e.amount_quoted,
        'date', to_char(e.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY'),
        'createdAt', e.created_at,
        'paymentStatus', coalesce(p.status,'pending'),
        'enrollmentStatus', e.status,
        'paymentMethod', p.payment_method,
        'verifiedAt', p.verified_at,
        'rejectionReason', p.rejection_reason,
        'receiptNo', e.receipt_no,
        'receiptToken', e.receipt_token
      ) as item
    from public.enrollments e
    left join public.payments p on p.enrollment_id = e.id
    where regexp_replace(coalesce(e.phone,''),'\D','','g') = q
    order by e.created_at desc
    limit 5
  ) x;

  return latest || jsonb_build_object('items', history);
end;
$$;

grant execute on function public.check_application_status(text) to anon, authenticated;

-- ============================================================
-- HARDENING / INDEXES / AUTO updated_at / PRIVILEGES
-- ============================================================

-- Receipt sequence is backend-only.
alter table public.receipt_sequences enable row level security;

-- Automatic updated_at maintenance.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare
  t text;
begin
  foreach t in array array[
    'tutors','courses','course_prices','promotions','app_settings',
    'enrollments','payments','receipt_settings','schedule_templates',
    'tutor_schedules','schedule_reservations','speaker_requests','reviews',
    'site_branding','home_banners','subject_categories'
  ]
  loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I', t, t);
    execute format(
      'create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      t, t
    );
  end loop;
end $$;

-- Useful indexes.
create index if not exists tutors_active_sort_idx
  on public.tutors(active, sort_order);
create index if not exists courses_tutor_active_sort_idx
  on public.courses(tutor_id, active, sort_order);
create index if not exists promotions_active_dates_idx
  on public.promotions(active, starts_at, ends_at);
create index if not exists enrollments_created_idx
  on public.enrollments(created_at desc);
create index if not exists enrollments_phone_idx
  on public.enrollments(phone);
create index if not exists payments_status_created_idx
  on public.payments(status, created_at desc);
create index if not exists tutor_schedules_lookup_idx
  on public.tutor_schedules(tutor_id, weekday, time_template_id);
create index if not exists schedule_reservations_lookup_idx
  on public.schedule_reservations(tutor_schedule_id, status);
create index if not exists speaker_requests_status_created_idx
  on public.speaker_requests(status, created_at desc);
create index if not exists home_banners_active_sort_idx
  on public.home_banners(active, sort_order);
create index if not exists subject_categories_active_sort_idx
  on public.subject_categories(active, sort_order);

-- Trusted backend/service-role functions.
revoke all on function public.next_receipt_no() from public;
grant execute on function public.next_receipt_no() to service_role;

revoke all on function public.reserve_enrollment_schedule(uuid,uuid[],jsonb,integer) from public;
grant execute on function public.reserve_enrollment_schedule(uuid,uuid[],jsonb,integer) to service_role;

-- Public-safe RPCs.
grant execute on function public.get_public_schedule(uuid[]) to anon, authenticated;
grant execute on function public.check_application_status(text) to anon, authenticated;

-- API privileges. RLS is still the authorization layer.
grant usage on schema public to anon, authenticated;

grant select on
  public.tutors,
  public.courses,
  public.course_prices,
  public.promotions,
  public.app_settings,
  public.schedule_templates,
  public.reviews,
  public.site_branding,
  public.home_banners,
  public.subject_categories
  to anon, authenticated;

grant insert on public.speaker_requests to anon, authenticated;

grant select, insert, update, delete on
  public.profiles,
  public.tutors,
  public.courses,
  public.course_prices,
  public.promotions,
  public.app_settings,
  public.enrollments,
  public.payments,
  public.receipt_settings,
  public.schedule_templates,
  public.tutor_schedules,
  public.schedule_reservations,
  public.speaker_requests,
  public.reviews,
  public.site_branding,
  public.home_banners,
  public.subject_categories
  to authenticated;

-- Service role is used by trusted Edge Functions and bypasses RLS.
grant all privileges on all tables in schema public to service_role;



-- ============================================================
-- TUTOR APPLICATION / RECRUITMENT SYSTEM
-- ============================================================
-- ============================================================
-- AreWarin Biology — Tutor Application System Upgrade
-- Run once in Supabase SQL Editor for an existing project.
-- Safe to re-run.
-- ============================================================


create table if not exists public.tutor_application_sequences (
  application_year integer primary key,
  last_no bigint not null default 0,
  updated_at timestamptz not null default now()
);

create table if not exists public.tutor_applications (
  id uuid primary key default gen_random_uuid(),
  application_no text not null unique,
  first_name text not null,
  last_name text not null,
  nickname text not null,
  phone text not null,
  email text not null,
  line_id text,
  province text,
  current_occupation text,
  intro text,
  education jsonb not null default '[]'::jsonb,
  work_experience jsonb not null default '[]'::jsonb,
  achievements text,
  subjects text[] not null default '{}'::text[],
  levels text[] not null default '{}'::text[],
  teaching_modes text[] not null default '{}'::text[],
  teaching_experience_years numeric(5,1) not null default 0,
  expected_rate text,
  preferred_location text,
  availability jsonb not null default '[]'::jsonb,
  teaching_style text,
  why_join text,
  additional_note text,
  profile_photo_path text,
  resume_path text,
  portfolio_path text,
  transcript_path text,
  status text not null default 'new' check(status in ('new','reviewing','interview','accepted','rejected','withdrawn')),
  public_status_note text,
  manager_notes text,
  consent_pdpa boolean not null default false,
  certified_accuracy boolean not null default false,
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.next_tutor_application_no()
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  y integer := extract(year from timezone('Asia/Bangkok', now()))::integer;
  n bigint;
begin
  insert into public.tutor_application_sequences(application_year,last_no)
  values(y,1)
  on conflict(application_year) do update
    set last_no = tutor_application_sequences.last_no + 1,
        updated_at = now()
  returning last_no into n;
  return 'AWT-' || y::text || '-' || lpad(n::text,6,'0');
end $$;

create or replace function public.check_tutor_application_status(p_application_no text, p_phone text)
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  r public.tutor_applications%rowtype;
  normalized_phone text := regexp_replace(coalesce(p_phone,''),'\D','','g');
begin
  select * into r
  from public.tutor_applications
  where upper(application_no)=upper(trim(p_application_no))
    and regexp_replace(phone,'\D','','g')=normalized_phone
  order by created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found',false);
  end if;

  return jsonb_build_object(
    'found',true,
    'application_no',r.application_no,
    'applicant_name',trim(r.first_name || ' ' || r.last_name),
    'nickname',r.nickname,
    'status',r.status,
    'public_status_note',r.public_status_note,
    'created_at',r.created_at,
    'updated_at',r.updated_at
  );
end $$;

alter table public.tutor_application_sequences enable row level security;
alter table public.tutor_applications enable row level security;

drop policy if exists "manager tutor applications" on public.tutor_applications;
create policy "manager tutor applications"
on public.tutor_applications
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

drop policy if exists "manager tutor application sequences" on public.tutor_application_sequences;
create policy "manager tutor application sequences"
on public.tutor_application_sequences
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'tutor-application-assets',
  'tutor-application-assets',
  false,
  10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict(id) do update set
  public=false,
  file_size_limit=10485760,
  allowed_mime_types=array['image/jpeg','image/png','image/webp','application/pdf'];

drop policy if exists "manager read tutor application assets" on storage.objects;
create policy "manager read tutor application assets"
on storage.objects
for select
to authenticated
using (bucket_id='tutor-application-assets' and public.is_manager());

drop policy if exists "manager delete tutor application assets" on storage.objects;
create policy "manager delete tutor application assets"
on storage.objects
for delete
to authenticated
using (bucket_id='tutor-application-assets' and public.is_manager());

-- updated_at helper (safe to create/replace)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path=public
as $$
begin
  new.updated_at = now();
  return new;
end $$;

-- updated_at trigger
drop trigger if exists trg_tutor_applications_updated_at on public.tutor_applications;
create trigger trg_tutor_applications_updated_at
before update on public.tutor_applications
for each row execute function public.set_updated_at();

create index if not exists tutor_applications_status_created_idx
  on public.tutor_applications(status, created_at desc);
create index if not exists tutor_applications_phone_idx
  on public.tutor_applications(phone);
create index if not exists tutor_applications_email_idx
  on public.tutor_applications(lower(email));

revoke all on function public.next_tutor_application_no() from public;
grant execute on function public.next_tutor_application_no() to service_role;

grant execute on function public.check_tutor_application_status(text,text) to anon, authenticated;

grant select, update, delete on public.tutor_applications to authenticated;
grant select on public.tutor_application_sequences to authenticated;
grant all privileges on public.tutor_applications, public.tutor_application_sequences to service_role;

-- ============================================================
-- AreWarin Biology
-- Existing Student Renewal Upgrade
-- Run once in Supabase > SQL Editor for an existing project.
-- ============================================================

create or replace function public.lookup_existing_student(p_phone text)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  q text := regexp_replace(coalesce(p_phone,''),'\D','','g');
  r public.enrollments%rowtype;
  h jsonb := '[]'::jsonb;
begin
  if length(q) < 9 then
    return jsonb_build_object('found',false);
  end if;

  select e.*
  into r
  from public.enrollments e
  where regexp_replace(coalesce(e.phone,''),'\D','','g') = q
  order by e.created_at desc
  limit 1;

  if not found then
    return jsonb_build_object('found',false);
  end if;

  select coalesce(jsonb_agg(x.item order by x.created_at desc),'[]'::jsonb)
  into h
  from (
    select
      e.created_at,
      jsonb_build_object(
        'id',e.id,
        'course',e.course_text,
        'tutor',e.tutor_text,
        'mode',e.mode_text,
        'hours',e.hours_text,
        'time',e.time_text,
        'amount',e.amount_quoted,
        'status',e.status,
        'date',to_char(e.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY')
      ) as item
    from public.enrollments e
    where regexp_replace(coalesce(e.phone,''),'\D','','g') = q
    order by e.created_at desc
    limit 6
  ) x;

  return jsonb_build_object(
    'found',true,
    'student',jsonb_build_object(
      'fullname',r.fullname,
      'nickname',r.nickname,
      'phone',r.phone,
      'lineId',r.line_id,
      'email',r.email,
      'grade',r.grade,
      'school',r.school,
      'faculty',r.faculty,
      'province',r.province,
      'studyType',r.study_type,
      'groupSize',r.group_size
    ),
    'latest',jsonb_build_object(
      'id',r.id,
      'name',r.fullname,
      'course',r.course_text,
      'tutor',r.tutor_text,
      'mode',r.mode_text,
      'hours',r.hours_text,
      'time',r.time_text,
      'amount',r.amount_quoted,
      'status',r.status,
      'date',to_char(r.created_at at time zone 'Asia/Bangkok','DD/MM/YYYY')
    ),
    'history',h
  );
end $$;

grant execute on function public.lookup_existing_student(text) to anon, authenticated;

-- ============================================================
-- INITIAL ADMIN BOOTSTRAP
-- ============================================================
-- The script promotes this email only IF the Auth user already exists.
-- If your Manager login uses another email, change this one line.
do $$
declare
  v_admin_email text := 'arewarin.biology@gmail.com';
  v_user_id uuid;
begin
  select id into v_user_id
  from auth.users
  where lower(email) = lower(v_admin_email)
  order by created_at
  limit 1;

  if v_user_id is not null then
    insert into public.profiles(id, display_name, role)
    values(v_user_id, 'AreWarin Admin', 'admin')
    on conflict(id) do update
      set display_name = excluded.display_name,
          role = 'admin';
  else
    raise notice 'Admin Auth user % does not exist yet. Create it in Authentication > Users, then run the admin snippet supplied with this setup.', v_admin_email;
  end if;
end $$;


commit;
