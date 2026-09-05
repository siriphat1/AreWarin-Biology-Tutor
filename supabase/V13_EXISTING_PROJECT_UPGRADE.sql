-- AreWarin Biology V13 — CUMULATIVE EXISTING PROJECT UPGRADE
-- Run this on the current project when you want all upgrades through V13.

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

-- Sanity check:
-- select public.lookup_existing_student('08xxxxxxxx');


-- ============================================================
-- AreWarin Biology — Tutor Application System Upgrade
-- Run once in Supabase SQL Editor for an existing project.
-- Safe to re-run.
-- ============================================================

begin;

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

commit;


-- ============================================================
-- AreWarin Biology V12 — Editable Policy & Rules CMS
-- For an EXISTING Supabase project already running V11.
-- Run once in Supabase > SQL Editor.
-- ============================================================

begin;

create table if not exists public.policy_pages (
  page_key text primary key,
  audience text not null check (audience in ('student','tutor')),
  welcome_kicker text,
  welcome_title text not null,
  welcome_highlight text,
  welcome_description text,
  policy_title text not null,
  policy_subtitle text,
  consent_title text not null,
  consent_description text,
  start_button_label text not null default 'เริ่มต้น',
  revision integer not null default 1 check (revision >= 1),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.policy_sections (
  id uuid primary key default gen_random_uuid(),
  page_key text not null references public.policy_pages(page_key) on delete cascade,
  title text not null,
  caption text,
  icon_class text not null default 'fas fa-circle-info',
  theme text not null default 'blue' check (theme in ('blue','sky','indigo','violet','emerald','amber','orange','rose','red','slate')),
  content text not null default '',
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.enrollments
  add column if not exists policy_version_acknowledged integer,
  add column if not exists policy_acknowledged_at timestamptz;

alter table public.tutor_applications
  add column if not exists policy_version_acknowledged integer,
  add column if not exists policy_acknowledged_at timestamptz;

alter table public.policy_pages enable row level security;
alter table public.policy_sections enable row level security;

drop policy if exists "public active policy pages" on public.policy_pages;
create policy "public active policy pages"
  on public.policy_pages for select to anon, authenticated
  using (active or public.is_manager());

drop policy if exists "manager policy pages" on public.policy_pages;
create policy "manager policy pages"
  on public.policy_pages for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

drop policy if exists "public active policy sections" on public.policy_sections;
create policy "public active policy sections"
  on public.policy_sections for select to anon, authenticated
  using (
    (active and exists (
      select 1 from public.policy_pages p
      where p.page_key = policy_sections.page_key and p.active
    )) or public.is_manager()
  );

drop policy if exists "manager policy sections" on public.policy_sections;
create policy "manager policy sections"
  on public.policy_sections for all to authenticated
  using (public.is_manager()) with check (public.is_manager());

grant select on public.policy_pages, public.policy_sections to anon, authenticated;
grant insert, update, delete on public.policy_pages, public.policy_sections to authenticated;

-- Reuse the global updated_at helper from the full setup.
do $$
begin
  if exists (select 1 from pg_proc where proname='set_updated_at' and pronamespace='public'::regnamespace) then
    execute 'drop trigger if exists trg_policy_pages_updated_at on public.policy_pages';
    execute 'create trigger trg_policy_pages_updated_at before update on public.policy_pages for each row execute function public.set_updated_at()';
    execute 'drop trigger if exists trg_policy_sections_updated_at on public.policy_sections';
    execute 'create trigger trg_policy_sections_updated_at before update on public.policy_sections for each row execute function public.set_updated_at()';
  end if;
end $$;

create index if not exists policy_sections_page_sort_idx
  on public.policy_sections(page_key, active, sort_order, created_at);

-- ---------- Page content ----------
insert into public.policy_pages (
  page_key,audience,welcome_kicker,welcome_title,welcome_highlight,welcome_description,
  policy_title,policy_subtitle,consent_title,consent_description,start_button_label,revision,active
) values
(
  'student_enrollment','student','BEFORE YOU ENROLL','เริ่มต้นการเรียนรู้กับ','AreWarin Biology',
  'ก่อนสมัครเรียน กรุณาอ่านข้อตกลงสำคัญเกี่ยวกับตารางเรียน การเข้าเรียน ค่าใช้จ่าย การคืนเงิน และการดูแลข้อมูลส่วนบุคคล',
  'ข้อตกลงและนโยบายการสมัครเรียน','เงื่อนไขเหล่านี้ใช้เป็นแนวทางร่วมกันระหว่างผู้เรียน ผู้ปกครอง ติวเตอร์ และสถาบัน และอาจได้รับการปรับปรุงผ่านระบบ Manager',
  'ฉันได้อ่านและยอมรับข้อตกลงและนโยบายทั้งหมด','ต้องยอมรับเงื่อนไขก่อนดำเนินการสมัครเรียนต่อ','ยอมรับและไปต่อ',1,true
),
(
  'tutor_application','tutor','JOIN OUR TEACHING TEAM','มาร่วมสร้างการเรียนรู้ที่ดีกับ','AreWarin Biology',
  'เรามองหาผู้สอนที่รักการถ่ายทอดความรู้ รับผิดชอบต่อผู้เรียน และพร้อมทำงานร่วมกับทีมอย่างเป็นมืออาชีพ',
  'นโยบายและกติกาสำหรับผู้สมัครติวเตอร์','กรุณาอ่านแนวทางการทำงาน การจัดตาราง การดูแลผู้เรียน และการใช้ข้อมูลให้ครบก่อนเริ่มกรอกใบสมัคร',
  'ฉันได้อ่านและยอมรับนโยบายสำหรับผู้สมัครติวเตอร์','การส่งใบสมัครถือเป็นการยืนยันว่าข้อมูลที่ให้เป็นความจริงและยินยอมให้สถาบันใช้ข้อมูลเพื่อการคัดเลือกและติดต่อ','ยอมรับและเริ่มสมัคร',1,true
)
on conflict (page_key) do nothing;

-- ---------- Student policy sections ----------
insert into public.policy_sections(page_key,title,caption,icon_class,theme,content,sort_order,active)
select * from (values
('student_enrollment','การนัดหยุด / เลื่อนเรียน','Reschedule policy','far fa-clock','blue',
'แจ้งล่วงหน้าเพื่อให้ทีมงานและติวเตอร์สามารถจัดตารางเรียนใหม่ได้อย่างเหมาะสม\nกรณีแจ้งกระทันหัน การชดเชยหรือบันทึกการสอนขึ้นอยู่กับความเหมาะสมของคาบและผู้สอน\nหากติวเตอร์จำเป็นต้องเลื่อน สถาบันจะพยายามแจ้งผู้เรียนล่วงหน้าโดยเร็วที่สุด',10,true),
('student_enrollment','กฎการเข้าเรียน','Attendance policy','fas fa-user-clock','red',
'ผู้เรียนควรเข้าเรียนตรงเวลาและแจ้งล่วงหน้าหากไม่สามารถเข้าเรียนได้\nการขาดหรือมาสายซ้ำโดยไม่แจ้ง อาจถูกนับชั่วโมงตามเงื่อนไขของคอร์ส\nหากขาดเรียนต่อเนื่องเป็นเวลานาน ทีมงานอาจติดต่อเพื่อทบทวนตารางหรือสถานะคอร์ส',20,true),
('student_enrollment','กติกาสำหรับ Onsite','Onsite class','fas fa-location-dot','orange',
'สถานที่เรียนและค่าเดินทางให้ยึดตามรายละเอียดที่ตกลงกับสถาบันหรือผู้สอนก่อนเริ่มคาบ\nผู้เรียนควรเผื่อเวลาเดินทางและแจ้งทันทีเมื่อคาดว่าจะมาสาย\nการเปลี่ยนสถานที่หรือรูปแบบการเรียนต้องได้รับการยืนยันจากทีมงาน',30,true),
('student_enrollment','การชำระเงิน / คืนเงิน','Payment & refund','fas fa-rotate-left','rose',
'ยอดที่ต้องชำระให้ยึดตามราคาที่ระบบแสดงและรายการที่ได้รับการยืนยันจากสถาบัน\nการยกเลิกก่อนเริ่มเรียนและการคืนเงินจะพิจารณาตามระยะเวลาที่แจ้งและค่าใช้จ่ายที่เกิดขึ้นจริง\nเมื่อเริ่มใช้สิทธิ์การเรียนแล้ว เงื่อนไขการคืนเงินหรือโอนสิทธิ์ให้ยึดตามข้อตกลงที่แสดงในวันที่สมัคร',40,true),
('student_enrollment','ข้อมูลส่วนบุคคล','Privacy / PDPA','fas fa-user-shield','indigo',
'ข้อมูลผู้เรียนและผู้ปกครองใช้เพื่อการสมัคร การจัดตาราง การชำระเงิน เอกสาร และการติดต่อที่เกี่ยวข้องกับการเรียน\nสถาบันจะจำกัดการเข้าถึงข้อมูลตามหน้าที่และมาตรการของระบบ\nผู้สมัครควรตรวจสอบความถูกต้องของข้อมูลก่อนส่งแบบฟอร์ม',50,true)
) as v(page_key,title,caption,icon_class,theme,content,sort_order,active)
where not exists (select 1 from public.policy_sections s where s.page_key=v.page_key and s.title=v.title);

-- ---------- Tutor applicant policy sections ----------
insert into public.policy_sections(page_key,title,caption,icon_class,theme,content,sort_order,active)
select * from (values
('tutor_application','คุณสมบัติและความถูกต้องของข้อมูล','Applicant integrity','fas fa-id-card','blue',
'ผู้สมัครควรให้ข้อมูลการศึกษา ประสบการณ์ และผลงานตามความเป็นจริง\nเอกสารที่แนบควรเป็นของผู้สมัครและสามารถใช้ประกอบการพิจารณาได้\nการส่งใบสมัครไม่ได้หมายถึงการรับเข้าทำงานหรือรับมอบหมายคอร์สโดยอัตโนมัติ',10,true),
('tutor_application','มาตรฐานการสอนและผู้เรียน','Teaching standard','fas fa-chalkboard-user','indigo',
'ผู้สอนต้องเตรียมบทเรียนให้เหมาะกับระดับและเป้าหมายของผู้เรียน\nให้ความสำคัญกับความปลอดภัย ความเคารพ และบรรยากาศการเรียนรู้ที่เหมาะสม\nห้ามใช้ถ้อยคำหรือพฤติกรรมที่คุกคาม เลือกปฏิบัติ หรือไม่เหมาะสมต่อผู้เรียน',20,true),
('tutor_application','ตารางสอนและความรับผิดชอบ','Schedule & responsibility','far fa-calendar-check','emerald',
'วันและเวลาที่แจ้งในใบสมัครใช้เป็นข้อมูลเบื้องต้นสำหรับการจับคู่ตาราง\nเมื่อรับคาบแล้วควรตรงต่อเวลา และแจ้งทีมงานโดยเร็วหากมีเหตุจำเป็นต้องเปลี่ยนแปลง\nตารางจริง จำนวนคาบ และรูปแบบ Online / Onsite จะยืนยันร่วมกันก่อนเริ่มสอน',30,true),
('tutor_application','เอกสาร เนื้อหา และทรัพย์สินทางปัญญา','Materials & IP','fas fa-file-shield','violet',
'ผู้สอนควรใช้สื่อที่ตนมีสิทธิ์ใช้งานและหลีกเลี่ยงการเผยแพร่เนื้อหาที่ละเมิดลิขสิทธิ์\nเอกสารภายในหรือข้อมูลผู้เรียนที่ได้รับจากสถาบันไม่ควรถูกนำไปเผยแพร่ภายนอกโดยไม่ได้รับอนุญาต\nรายละเอียดการใช้สื่อร่วมกันของสถาบันจะตกลงเพิ่มเติมตามคอร์สหรือโครงการ',40,true),
('tutor_application','ข้อมูลส่วนบุคคลและการรักษาความลับ','Privacy & confidentiality','fas fa-lock','amber',
'ข้อมูลในใบสมัครใช้เพื่อการคัดเลือก ติดต่อ ตรวจสอบคุณสมบัติ และจัดการผู้สมัครติวเตอร์\nข้อมูลผู้เรียน ผู้ปกครอง และข้อมูลภายในที่ผู้สอนได้รับจากการทำงานต้องได้รับการดูแลเป็นความลับ\nการเข้าถึงไฟล์ใบสมัครในระบบ Manager จำกัดเฉพาะผู้มีสิทธิ์',50,true),
('tutor_application','ค่าตอบแทนและการมอบหมายงาน','Compensation & assignment','fas fa-handshake','slate',
'เรทที่ผู้สมัครระบุเป็นข้อมูลประกอบการพิจารณา ไม่ใช่การยืนยันอัตราค่าตอบแทน\nอัตราค่าตอบแทน เงื่อนไขการจ่าย และขอบเขตงานจะตกลงเป็นรายคอร์สหรือรายโครงการ\nสถาบันสามารถพิจารณาความเหมาะสมของผู้สอนกับผู้เรียนและคอร์สก่อนมอบหมายงาน',60,true)
) as v(page_key,title,caption,icon_class,theme,content,sort_order,active)
where not exists (select 1 from public.policy_sections s where s.page_key=v.page_key and s.title=v.title);

commit;

-- Verification
select p.page_key,p.audience,p.revision,p.active,count(s.id) as sections
from public.policy_pages p
left join public.policy_sections s on s.page_key=p.page_key
group by p.page_key,p.audience,p.revision,p.active
order by p.page_key;


-- ============================================================
-- AreWarin Biology V13
-- International Tutor Application + Bilingual Policy CMS Upgrade
-- Safe for an existing project that already has Tutor Applications.
-- ============================================================

begin;

-- Tutor applications: international applicants + language preference
alter table public.tutor_applications
  add column if not exists preferred_language text not null default 'th',
  add column if not exists nationality text,
  add column if not exists country_residence text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname='tutor_applications_preferred_language_check'
      and conrelid='public.tutor_applications'::regclass
  ) then
    alter table public.tutor_applications
      add constraint tutor_applications_preferred_language_check
      check (preferred_language in ('th','en'));
  end if;
end $$;

-- Policy pages: existing columns are Thai/default, *_en stores English.
alter table public.policy_pages
  add column if not exists welcome_kicker_en text,
  add column if not exists welcome_title_en text,
  add column if not exists welcome_highlight_en text,
  add column if not exists welcome_description_en text,
  add column if not exists policy_title_en text,
  add column if not exists policy_subtitle_en text,
  add column if not exists consent_title_en text,
  add column if not exists consent_description_en text,
  add column if not exists start_button_label_en text;

alter table public.policy_sections
  add column if not exists title_en text,
  add column if not exists caption_en text,
  add column if not exists content_en text;

-- English page copy (Manager can edit all of this later).
update public.policy_pages set
  welcome_kicker_en='BEFORE YOU ENROLL',
  welcome_title_en='Start learning with',
  welcome_highlight_en='AreWarin Biology',
  welcome_description_en='Before enrolling, please review the important terms for scheduling, attendance, fees, refunds, and personal-data handling.',
  policy_title_en='Enrollment Terms & Policies',
  policy_subtitle_en='These terms provide a shared framework for learners, guardians, tutors, and the institute. They may be revised through the Manager system.',
  consent_title_en='I have read and accept all enrollment terms and policies.',
  consent_description_en='You must accept these terms before continuing with enrollment.',
  start_button_label_en='Accept & continue'
where page_key='student_enrollment';

update public.policy_pages set
  welcome_kicker_en='JOIN OUR TEACHING TEAM',
  welcome_title_en='Build better learning with',
  welcome_highlight_en='AreWarin Biology',
  welcome_description_en='We welcome educators who love teaching, take responsibility for learners, and are ready to work professionally with our team.',
  policy_title_en='Policies & Guidelines for Tutor Applicants',
  policy_subtitle_en='Please review our working standards, scheduling expectations, learner care, confidentiality, and data-use terms before applying.',
  consent_title_en='I have read and accept the tutor applicant policies.',
  consent_description_en='By submitting an application, you confirm that the information is accurate and consent to its use for recruitment and contact purposes.',
  start_button_label_en='Accept & start application'
where page_key='tutor_application';

-- English student policy sections
update public.policy_sections set
 title_en='Rescheduling & Cancellations', caption_en='Reschedule policy',
 content_en='Please notify the team in advance so schedules can be adjusted appropriately.
For last-minute changes, make-up lessons or charged hours may depend on the class circumstances and tutor availability.
If a tutor needs to reschedule, the institute will make reasonable efforts to notify the learner as early as possible.'
where page_key='student_enrollment' and title='การนัดหยุด / เลื่อนเรียน';

update public.policy_sections set
 title_en='Attendance', caption_en='Attendance policy',
 content_en='Learners should attend on time and notify the team in advance if they cannot attend.
Repeated absence or lateness without notice may be counted according to the applicable course terms.
If a learner is absent for an extended period, the team may contact them to review the schedule or course status.'
where page_key='student_enrollment' and title='กฎการเข้าเรียน';

update public.policy_sections set
 title_en='Onsite Classes', caption_en='Onsite class',
 content_en='The class location and travel fees follow the details confirmed with the institute or tutor before the lesson.
Learners should allow sufficient travel time and notify the tutor promptly if they expect to be late.
Changes to location or teaching mode must be confirmed by the team.'
where page_key='student_enrollment' and title='กติกาสำหรับ Onsite';

update public.policy_sections set
 title_en='Payment & Refunds', caption_en='Payment & refund',
 content_en='The amount due follows the current system price and the enrollment details confirmed by the institute.
Refunds before classes begin are considered according to the notice period and costs already incurred.
After learning benefits have been used, refund or transfer conditions follow the terms shown and accepted at the time of enrollment.'
where page_key='student_enrollment' and title='การชำระเงิน / คืนเงิน';

update public.policy_sections set
 title_en='Personal Data & Privacy', caption_en='Privacy / PDPA',
 content_en='Learner and guardian data is used for enrollment, scheduling, payment, documents, and learning-related contact.
Access is limited according to staff responsibilities and system safeguards.
Applicants should verify that their information is accurate before submission.'
where page_key='student_enrollment' and title='ข้อมูลส่วนบุคคล';

-- English tutor applicant policy sections
update public.policy_sections set
 title_en='Applicant Integrity & Accurate Information', caption_en='Applicant integrity',
 content_en='Applicants should provide truthful education, experience, and achievement information.
Uploaded documents should belong to the applicant and be appropriate for recruitment review.
Submitting an application does not automatically create an employment relationship or guarantee a teaching assignment.'
where page_key='tutor_application' and title='คุณสมบัติและความถูกต้องของข้อมูล';

update public.policy_sections set
 title_en='Teaching Standards & Learner Care', caption_en='Teaching standard',
 content_en='Tutors should prepare lessons appropriate to each learner’s level and goals.
Safety, respect, and an appropriate learning environment are essential.
Harassment, discrimination, intimidation, or inappropriate behavior toward learners is not permitted.'
where page_key='tutor_application' and title='มาตรฐานการสอนและผู้เรียน';

update public.policy_sections set
 title_en='Scheduling & Responsibility', caption_en='Schedule & responsibility',
 content_en='Availability submitted in the application is used as an initial reference for schedule matching.
Once a class is accepted, tutors should be punctual and notify the team promptly if a change is necessary.
Final schedules, teaching hours, and Online / Onsite arrangements are confirmed before teaching begins.'
where page_key='tutor_application' and title='ตารางสอนและความรับผิดชอบ';

update public.policy_sections set
 title_en='Teaching Materials & Intellectual Property', caption_en='Materials & IP',
 content_en='Tutors should use materials they are legally entitled to use and avoid copyright infringement.
Internal documents or learner information provided by the institute must not be shared externally without authorization.
Additional material-use terms may be agreed for specific courses or projects.'
where page_key='tutor_application' and title='เอกสาร เนื้อหา และทรัพย์สินทางปัญญา';

update public.policy_sections set
 title_en='Privacy & Confidentiality', caption_en='Privacy & confidentiality',
 content_en='Application data is used for recruitment, contact, qualification review, and applicant administration.
Learner, guardian, and internal institute information obtained through teaching must be kept confidential.
Application files in Manager are restricted to authorized users.'
where page_key='tutor_application' and title='ข้อมูลส่วนบุคคลและการรักษาความลับ';

update public.policy_sections set
 title_en='Compensation & Teaching Assignments', caption_en='Compensation & assignment',
 content_en='The expected rate entered in the application is for consideration only and is not a confirmed compensation rate.
Compensation, payment terms, and work scope are agreed for each course or project.
The institute may assess tutor-course and tutor-learner fit before assigning work.'
where page_key='tutor_application' and title='ค่าตอบแทนและการมอบหมายงาน';

commit;

-- Verification
select
  p.page_key,
  p.revision,
  p.active,
  (p.policy_title_en is not null) as has_english_page,
  count(s.id) as sections,
  count(s.id) filter (where s.title_en is not null) as english_sections
from public.policy_pages p
left join public.policy_sections s on s.page_key=p.page_key
group by p.page_key,p.revision,p.active,p.policy_title_en
order by p.page_key;

select
  column_name,data_type
from information_schema.columns
where table_schema='public'
  and table_name='tutor_applications'
  and column_name in ('preferred_language','nationality','country_residence')
order by column_name;
