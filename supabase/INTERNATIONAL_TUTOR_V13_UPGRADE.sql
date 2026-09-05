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
