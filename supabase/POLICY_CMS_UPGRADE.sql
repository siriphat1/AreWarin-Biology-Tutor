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
