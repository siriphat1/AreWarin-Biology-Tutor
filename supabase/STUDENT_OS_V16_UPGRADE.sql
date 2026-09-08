-- ============================================================
-- AREWARIN UNIFIED STUDENT OS V16 — EXISTING PROJECT UPGRADE
-- Schedule / Homework / Parent View / Receipts / Support / Certificates
-- Security / Activity / Recommendations / Notification rules
-- ============================================================
begin;
create extension if not exists pgcrypto;

-- ---------- Schedule & reschedule ----------
create table if not exists public.student_schedule_events (
  id uuid primary key default gen_random_uuid(),
  student_id uuid references public.os_students(id) on delete cascade,
  group_id uuid references public.os_student_groups(id) on delete cascade,
  course_id uuid references public.courses(id) on delete set null,
  tutor_id uuid references public.tutors(id) on delete set null,
  title text not null default 'คาบเรียน',
  start_at timestamptz not null,
  end_at timestamptz not null,
  mode text not null default 'online' check(mode in ('online','onsite','hybrid')),
  location text,
  meeting_url text,
  status text not null default 'scheduled' check(status in ('scheduled','rescheduled','completed','cancelled')),
  notes text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(end_at>start_at),
  check(student_id is not null or group_id is not null)
);
create index if not exists student_schedule_student_idx on public.student_schedule_events(student_id,start_at);
create index if not exists student_schedule_group_idx on public.student_schedule_events(group_id,start_at);

create table if not exists public.student_reschedule_requests (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  schedule_event_id uuid not null references public.student_schedule_events(id) on delete cascade,
  requested_start_at timestamptz not null,
  reason text,
  status text not null default 'pending' check(status in ('pending','approved','rejected','cancelled')),
  staff_note text,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------- Homework ----------
create table if not exists public.student_assignments (
  id uuid primary key default gen_random_uuid(),
  course_id uuid references public.courses(id) on delete cascade,
  group_id uuid references public.os_student_groups(id) on delete cascade,
  student_id uuid references public.os_students(id) on delete cascade,
  tutor_id uuid references public.tutors(id) on delete set null,
  title text not null,
  description text,
  due_at timestamptz,
  max_score numeric(10,2) not null default 100,
  status text not null default 'published' check(status in ('draft','published','closed','archived')),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(course_id is not null or group_id is not null or student_id is not null)
);
create table if not exists public.student_assignment_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.student_assignments(id) on delete cascade,
  student_id uuid not null references public.os_students(id) on delete cascade,
  submission_text text,
  file_paths text[] not null default '{}',
  status text not null default 'submitted' check(status in ('draft','submitted','graded','returned')),
  score numeric(10,2),
  feedback text,
  submitted_at timestamptz not null default now(),
  graded_at timestamptz,
  graded_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  unique(assignment_id,student_id)
);

-- ---------- Parent View ----------
create table if not exists public.student_parent_links (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  parent_name text not null,
  relationship text,
  token_hash text not null unique,
  active boolean not null default true,
  expires_at timestamptz,
  last_used_at timestamptz,
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);

-- ---------- Support ----------
create table if not exists public.student_support_tickets (
  id uuid primary key default gen_random_uuid(),
  ticket_no text unique,
  student_id uuid not null references public.os_students(id) on delete cascade,
  category text not null default 'other' check(category in ('hours','schedule','payment','course','account','other')),
  subject text not null,
  description text,
  priority text not null default 'normal' check(priority in ('low','normal','high','urgent')),
  status text not null default 'open' check(status in ('open','in_progress','waiting_student','resolved','closed')),
  assigned_to uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create table if not exists public.student_support_messages (
  id uuid primary key default gen_random_uuid(),
  ticket_id uuid not null references public.student_support_tickets(id) on delete cascade,
  student_id uuid references public.os_students(id) on delete cascade,
  sender_user_id uuid references auth.users(id) on delete set null,
  sender_type text not null check(sender_type in ('student','staff','system')),
  message text not null,
  created_at timestamptz not null default now()
);

-- ---------- Certificates ----------
create table if not exists public.student_certificates (
  id uuid primary key default gen_random_uuid(),
  certificate_no text not null unique,
  student_id uuid not null references public.os_students(id) on delete cascade,
  student_course_id uuid references public.os_student_course_enrollments(id) on delete set null,
  course_id uuid references public.courses(id) on delete set null,
  course_label text,
  title text not null default 'Certificate of Completion',
  issued_at timestamptz not null default now(),
  issued_by uuid references auth.users(id) on delete set null,
  status text not null default 'issued' check(status in ('issued','revoked')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- ---------- Device registry / security ----------
create table if not exists public.student_devices (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.os_students(id) on delete cascade,
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  device_key text not null,
  device_name text,
  user_agent text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  revoked_at timestamptz,
  unique(student_id,device_key)
);

-- ---------- Configurable notification rules ----------
create table if not exists public.student_notification_rules (
  rule_key text primary key,
  label text not null,
  enabled boolean not null default true,
  threshold_value numeric(12,2),
  threshold_unit text,
  message_template text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
insert into public.student_notification_rules(rule_key,label,enabled,threshold_value,threshold_unit,message_template) values
('schedule_reminder','แจ้งเตือนก่อนเรียน',true,6,'hours','มีคาบเรียนในอีก {value} ชั่วโมง'),
('assignment_due','เตือนการบ้านใกล้กำหนด',true,24,'hours','การบ้านใกล้ถึงกำหนดส่ง'),
('renewal_hours','เตือนต่อคอร์ส',true,3,'hours_remaining','คอร์สเหลือ {value} ชั่วโมง'),
('payment_overdue','ติดตามรายการชำระหมดเวลา',true,0,'hours','มีรายการชำระที่ต้องดำเนินการ')
on conflict(rule_key) do nothing;

-- ---------- Generic updated_at helper ----------
create or replace function public.v16_set_updated_at() returns trigger language plpgsql as $$begin new.updated_at=now();return new;end$$;

do $$declare t text;begin
  foreach t in array array['student_schedule_events','student_reschedule_requests','student_assignments','student_assignment_submissions','student_support_tickets'] loop
    execute format('drop trigger if exists trg_v16_updated_at on public.%I',t);
    execute format('create trigger trg_v16_updated_at before update on public.%I for each row execute function public.v16_set_updated_at()',t);
  end loop;
end$$;

-- ---------- Ticket numbering ----------
create or replace function public.v16_ticket_number() returns trigger language plpgsql security definer set search_path=public as $$begin
  if new.ticket_no is null then new.ticket_no='AWT-'||to_char(now() at time zone 'Asia/Bangkok','YYYY')||'-'||upper(substr(replace(new.id::text,'-',''),1,8));end if;return new;end$$;
drop trigger if exists trg_v16_ticket_no on public.student_support_tickets;
create trigger trg_v16_ticket_no before insert on public.student_support_tickets for each row execute function public.v16_ticket_number();

-- ---------- Auto certificate when course is completed ----------
create or replace function public.v16_issue_certificate_on_complete() returns trigger language plpgsql security definer set search_path=public as $$begin
  if new.status='completed' and (tg_op='INSERT' or old.status is distinct from new.status) then
    insert into public.student_certificates(certificate_no,student_id,student_course_id,course_id,course_label)
    values('AWC-'||to_char(now() at time zone 'Asia/Bangkok','YYYY')||'-'||upper(substr(replace(new.id::text,'-',''),1,8)),new.student_id,new.id,new.course_id,coalesce(new.course_label,'AreWarin Biology'))
    on conflict(certificate_no) do nothing;
  end if;return new;end$$;
drop trigger if exists trg_v16_certificate on public.os_student_course_enrollments;
create trigger trg_v16_certificate after insert or update of status on public.os_student_course_enrollments for each row execute function public.v16_issue_certificate_on_complete();

insert into public.student_certificates(certificate_no,student_id,student_course_id,course_id,course_label,issued_at)
select 'AWC-'||to_char(coalesce(sce.updated_at,sce.created_at,now()) at time zone 'Asia/Bangkok','YYYY')||'-'||upper(substr(replace(sce.id::text,'-',''),1,8)),sce.student_id,sce.id,sce.course_id,coalesce(sce.course_label,'AreWarin Biology'),coalesce(sce.updated_at,sce.created_at,now())
from public.os_student_course_enrollments sce
where sce.status='completed'
on conflict(certificate_no) do nothing;

-- ---------- RLS ----------
alter table public.student_schedule_events enable row level security;
alter table public.student_reschedule_requests enable row level security;
alter table public.student_assignments enable row level security;
alter table public.student_assignment_submissions enable row level security;
alter table public.student_parent_links enable row level security;
alter table public.student_support_tickets enable row level security;
alter table public.student_support_messages enable row level security;
alter table public.student_certificates enable row level security;
alter table public.student_devices enable row level security;
alter table public.student_notification_rules enable row level security;

do $$declare t text;begin
  foreach t in array array['student_schedule_events','student_reschedule_requests','student_assignments','student_assignment_submissions','student_parent_links','student_support_tickets','student_support_messages','student_certificates','student_devices','student_notification_rules'] loop
    execute format('drop policy if exists v16_staff_all on public.%I',t);
    execute format('create policy v16_staff_all on public.%I for all to authenticated using (public.os_is_staff() or public.is_manager()) with check (public.os_is_staff() or public.is_manager())',t);
  end loop;
end$$;

-- Student own policies (reads/writes that do not use RPC still remain safe)
drop policy if exists v16_student_schedule_read on public.student_schedule_events;
drop policy if exists v16_student_reschedule_read on public.student_reschedule_requests;
drop policy if exists v16_student_assignment_read on public.student_assignments;
drop policy if exists v16_student_submission_read on public.student_assignment_submissions;
drop policy if exists v16_student_parent_read on public.student_parent_links;
drop policy if exists v16_student_ticket_read on public.student_support_tickets;
drop policy if exists v16_student_message_read on public.student_support_messages;
drop policy if exists v16_student_certificate_read on public.student_certificates;
drop policy if exists v16_student_device_read on public.student_devices;
create policy v16_student_schedule_read on public.student_schedule_events for select to authenticated using (
  student_id=public.aw_my_student_id() or group_id in(select gm.group_id from public.os_student_group_members gm where gm.student_id=public.aw_my_student_id() and gm.is_active=true)
);
create policy v16_student_reschedule_read on public.student_reschedule_requests for select to authenticated using(student_id=public.aw_my_student_id());
create policy v16_student_assignment_read on public.student_assignments for select to authenticated using(
 status='published' and (student_id=public.aw_my_student_id() or course_id in(select sce.course_id from public.os_student_course_enrollments sce where sce.student_id=public.aw_my_student_id()) or group_id in(select gm.group_id from public.os_student_group_members gm where gm.student_id=public.aw_my_student_id() and gm.is_active=true))
);
create policy v16_student_submission_read on public.student_assignment_submissions for select to authenticated using(student_id=public.aw_my_student_id());
create policy v16_student_parent_read on public.student_parent_links for select to authenticated using(student_id=public.aw_my_student_id());
create policy v16_student_ticket_read on public.student_support_tickets for select to authenticated using(student_id=public.aw_my_student_id());
create policy v16_student_message_read on public.student_support_messages for select to authenticated using(ticket_id in(select id from public.student_support_tickets where student_id=public.aw_my_student_id()));
create policy v16_student_certificate_read on public.student_certificates for select to authenticated using(student_id=public.aw_my_student_id());
create policy v16_student_device_read on public.student_devices for select to authenticated using(student_id=public.aw_my_student_id());

-- ---------- Storage for homework files ----------
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('student-assignment-files','student-assignment-files',false,15728640,array['image/jpeg','image/png','image/webp','application/pdf','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-powerpoint','application/vnd.openxmlformats-officedocument.presentationml.presentation']) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists v16_assignment_file_student_insert on storage.objects;
create policy v16_assignment_file_student_insert on storage.objects for insert to authenticated with check(bucket_id='student-assignment-files' and (storage.foldername(name))[1]=auth.uid()::text);
drop policy if exists v16_assignment_file_student_read on storage.objects;
create policy v16_assignment_file_student_read on storage.objects for select to authenticated using(bucket_id='student-assignment-files' and ((storage.foldername(name))[1]=auth.uid()::text or public.os_is_staff() or public.is_manager()));
drop policy if exists v16_assignment_file_staff_all on storage.objects;
create policy v16_assignment_file_staff_all on storage.objects for all to authenticated using(bucket_id='student-assignment-files' and (public.os_is_staff() or public.is_manager())) with check(bucket_id='student-assignment-files' and (public.os_is_staff() or public.is_manager()));

-- ---------- Student RPCs ----------
create or replace function public.student_v16_request_reschedule(p_event_id uuid,p_requested_start_at timestamptz,p_reason text default null) returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();ev public.student_schedule_events;r public.student_reschedule_requests;begin if sid is null then raise exception 'Student account is not linked';end if;select * into ev from public.student_schedule_events where id=p_event_id and (student_id=sid or group_id in(select group_id from public.os_student_group_members where student_id=sid and is_active=true));if ev.id is null then raise exception 'Schedule event not found';end if;if ev.start_at<=now() then raise exception 'Cannot reschedule a past class';end if;insert into public.student_reschedule_requests(student_id,schedule_event_id,requested_start_at,reason) values(sid,p_event_id,p_requested_start_at,p_reason) returning * into r;insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id) values(sid,'ส่งคำขอเลื่อนเรียนแล้ว','ทีมงานจะตรวจสอบและอัปเดตตารางให้','schedule','reschedule',r.id::text);return to_jsonb(r);end$$;

create or replace function public.student_v16_submit_assignment(p_assignment_id uuid,p_submission_text text default null,p_file_paths text[] default '{}') returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();a public.student_assignments;s public.student_assignment_submissions;begin if sid is null then raise exception 'Student account is not linked';end if;select * into a from public.student_assignments where id=p_assignment_id and status='published' and (student_id=sid or course_id in(select course_id from public.os_student_course_enrollments where student_id=sid) or group_id in(select group_id from public.os_student_group_members where student_id=sid and is_active=true));if a.id is null then raise exception 'Assignment not found';end if;insert into public.student_assignment_submissions(assignment_id,student_id,submission_text,file_paths,status,submitted_at) values(a.id,sid,p_submission_text,coalesce(p_file_paths,'{}'), 'submitted',now()) on conflict(assignment_id,student_id) do update set submission_text=excluded.submission_text,file_paths=excluded.file_paths,status='submitted',submitted_at=now(),updated_at=now() returning * into s;return to_jsonb(s);end$$;

create or replace function public.student_v16_create_ticket(p_category text,p_subject text,p_description text) returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();t public.student_support_tickets;begin if sid is null then raise exception 'Student account is not linked';end if;insert into public.student_support_tickets(student_id,category,subject,description) values(sid,p_category,p_subject,p_description) returning * into t;insert into public.student_support_messages(ticket_id,student_id,sender_type,message) values(t.id,sid,'student',coalesce(p_description,''));return to_jsonb(t);end$$;
create or replace function public.student_v16_reply_ticket(p_ticket_id uuid,p_message text) returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();m public.student_support_messages;begin if not exists(select 1 from public.student_support_tickets where id=p_ticket_id and student_id=sid and status<>'closed') then raise exception 'Ticket not found';end if;insert into public.student_support_messages(ticket_id,student_id,sender_type,message) values(p_ticket_id,sid,'student',p_message) returning * into m;update public.student_support_tickets set status=case when status='waiting_student' then 'in_progress' else status end,updated_at=now() where id=p_ticket_id;return to_jsonb(m);end$$;

create or replace function public.student_v16_create_parent_link(p_parent_name text,p_relationship text default 'ผู้ปกครอง') returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();tok text;h text;r public.student_parent_links;begin if sid is null then raise exception 'Student account is not linked';end if;tok='AWP-'||upper(substr(encode(gen_random_bytes(8),'hex'),1,12));h=encode(digest(upper(tok),'sha256'),'hex');insert into public.student_parent_links(student_id,parent_name,relationship,token_hash) values(sid,p_parent_name,p_relationship,h) returning * into r;return jsonb_build_object('id',r.id,'token',tok,'parent_name',r.parent_name,'relationship',r.relationship);end$$;
create or replace function public.student_v16_revoke_parent_link(p_link_id uuid) returns boolean language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();begin update public.student_parent_links set active=false,revoked_at=now() where id=p_link_id and student_id=sid;return found;end$$;

create or replace function public.student_v16_register_device(p_device_key text,p_device_name text,p_user_agent text default null) returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();d public.student_devices;begin if sid is null then return '{}'::jsonb;end if;insert into public.student_devices(student_id,auth_user_id,device_key,device_name,user_agent,last_seen_at,revoked_at) values(sid,auth.uid(),p_device_key,p_device_name,left(p_user_agent,500),now(),null) on conflict(student_id,device_key) do update set auth_user_id=auth.uid(),device_name=excluded.device_name,user_agent=excluded.user_agent,last_seen_at=now(),revoked_at=null returning * into d;return to_jsonb(d);end$$;
create or replace function public.student_v16_revoke_other_devices(p_current_device_key text) returns integer language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();cnt integer;begin update public.student_devices set revoked_at=now() where student_id=sid and device_key<>p_current_device_key and revoked_at is null;get diagnostics cnt=row_count;return cnt;end$$;

-- ---------- Public Parent RPC: intentionally limited data ----------
create or replace function public.parent_v16_view(p_token text) returns jsonb language plpgsql security definer set search_path=public as $$declare h text;lnk public.student_parent_links;sid uuid;s public.os_students;begin h=encode(digest(upper(trim(p_token)),'sha256'),'hex');select * into lnk from public.student_parent_links where token_hash=h and active=true and (expires_at is null or expires_at>now()) limit 1;if lnk.id is null then return jsonb_build_object('found',false);end if;update public.student_parent_links set last_used_at=now() where id=lnk.id;sid=lnk.student_id;select * into s from public.os_students where id=sid;return jsonb_build_object('found',true,'student_name',s.display_name,'school',s.school,'generated_at',now(),'courses',coalesce((select jsonb_agg(jsonb_build_object('course_label',sce.course_label,'status',sce.status,'hours_total',coalesce(hp.total_hours,sce.hours_total),'hours_used',coalesce(hp.used_hours,sce.hours_used),'unlimited',coalesce(hp.unlimited,false))) from public.os_student_course_enrollments sce left join public.os_hour_pools hp on hp.id=sce.hour_pool_id where sce.student_id=sid and sce.status in('active','paused','completed')),'[]'::jsonb),'schedule',coalesce((select jsonb_agg(jsonb_build_object('title',se.title,'start_at',se.start_at,'end_at',se.end_at,'mode',se.mode,'location',se.location) order by se.start_at) from public.student_schedule_events se where se.status in('scheduled','rescheduled') and se.start_at>=now() and (se.student_id=sid or se.group_id in(select group_id from public.os_student_group_members where student_id=sid and is_active=true)) limit 10),'[]'::jsonb),'attendance',coalesce((select jsonb_agg(jsonb_build_object('status',a.status,'title',ses.title,'session_at',ses.session_date::text||'T00:00:00') order by a.created_at desc) from public.os_student_attendance a left join public.os_attendance_sessions ses on ses.id=a.session_id where a.student_id=sid limit 20),'[]'::jsonb),'assignments',coalesce((select jsonb_agg(jsonb_build_object('title',a.title,'due_at',a.due_at,'submitted',exists(select 1 from public.student_assignment_submissions sub where sub.assignment_id=a.id and sub.student_id=sid and sub.status in('submitted','graded')))) from public.student_assignments a where a.status='published' and (a.student_id=sid or a.course_id in(select course_id from public.os_student_course_enrollments where student_id=sid) or a.group_id in(select group_id from public.os_student_group_members where student_id=sid and is_active=true))),'[]'::jsonb),'payment_due_count',(select count(*) from public.portal_payment_requests pr where pr.student_id=sid and pr.status in('pending','slip_submitted','rejected')));end$$;
revoke all on function public.parent_v16_view(text) from public;grant execute on function public.parent_v16_view(text) to anon,authenticated;

-- ---------- Certificate read RPC ----------
create or replace function public.student_v16_certificate(p_certificate_id uuid) returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();c public.student_certificates;s public.os_students;begin select * into c from public.student_certificates where id=p_certificate_id and student_id=sid and status='issued';if c.id is null then return jsonb_build_object('found',false);end if;select * into s from public.os_students where id=sid;return jsonb_build_object('found',true,'certificate_no',c.certificate_no,'student_name',s.display_name,'course_label',c.course_label,'issued_at',c.issued_at);end$$;

-- ---------- Notification sweep ----------
create or replace function public.student_v16_notification_sweep_worker() returns jsonb language plpgsql security definer set search_path=public as $$declare hrs numeric;duehrs numeric;cnt integer:=0;r record;begin select threshold_value into hrs from public.student_notification_rules where rule_key='schedule_reminder' and enabled=true;if hrs is not null then for r in select distinct s.id student_id,e.id event_id,e.title,e.start_at from public.student_schedule_events e join lateral (select os.id from public.os_students os where os.id=e.student_id union select gm.student_id from public.os_student_group_members gm where gm.group_id=e.group_id and gm.is_active=true) s on true where e.status in('scheduled','rescheduled') and e.start_at between now() and now()+make_interval(hours=>hrs::int) loop if not exists(select 1 from public.portal_notifications where student_id=r.student_id and source_type='v16_schedule_reminder' and source_id=r.event_id::text) then insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id) values(r.student_id,'ใกล้ถึงเวลาเรียน',r.title||' · '||to_char(r.start_at at time zone 'Asia/Bangkok','DD/MM HH24:MI'),'schedule','v16_schedule_reminder',r.event_id::text);cnt=cnt+1;end if;end loop;end if;select threshold_value into duehrs from public.student_notification_rules where rule_key='assignment_due' and enabled=true;if duehrs is not null then for r in select a.id assignment_id,a.title,a.due_at,s.id student_id from public.student_assignments a join lateral (select os.id from public.os_students os where os.id=a.student_id union select sce.student_id from public.os_student_course_enrollments sce where sce.course_id=a.course_id union select gm.student_id from public.os_student_group_members gm where gm.group_id=a.group_id and gm.is_active=true) s on true where a.status='published' and a.due_at between now() and now()+make_interval(hours=>duehrs::int) and not exists(select 1 from public.student_assignment_submissions sub where sub.assignment_id=a.id and sub.student_id=s.id and sub.status in('submitted','graded')) loop if not exists(select 1 from public.portal_notifications where student_id=r.student_id and source_type='v16_assignment_due' and source_id=r.assignment_id::text) then insert into public.portal_notifications(student_id,title,body,notification_type,source_type,source_id) values(r.student_id,'การบ้านใกล้ถึงกำหนด',r.title||' · กำหนด '||to_char(r.due_at at time zone 'Asia/Bangkok','DD/MM HH24:MI'),'assignment','v16_assignment_due',r.assignment_id::text);cnt=cnt+1;end if;end loop;end if;return jsonb_build_object('success',true,'notifications_created',cnt,'ran_at',now());end$$;
revoke all on function public.student_v16_notification_sweep_worker() from public,anon,authenticated;

create or replace function public.student_v16_run_notification_sweep() returns jsonb language plpgsql security definer set search_path=public as $$begin if not(public.os_is_staff() or public.is_manager()) then raise exception 'Not authorized';end if;return public.student_v16_notification_sweep_worker();end$$;
revoke all on function public.student_v16_run_notification_sweep() from public,anon;grant execute on function public.student_v16_run_notification_sweep() to authenticated;

-- ---------- Rich V16 bootstrap ----------
create or replace function public.student_v16_bootstrap() returns jsonb language plpgsql security definer set search_path=public as $$declare sid uuid:=public.aw_my_student_id();base jsonb;begin if sid is null then raise exception 'Student account is not linked';end if;begin base=public.student_v12_bootstrap();exception when undefined_function then base=public.student_v11_bootstrap();end;return base||jsonb_build_object('v16_schedule',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'student_id',e.student_id,'group_id',e.group_id,'course_id',e.course_id,'tutor_id',e.tutor_id,'tutor_name',t.display_name,'title',e.title,'start_at',e.start_at,'end_at',e.end_at,'mode',e.mode,'location',e.location,'meeting_url',e.meeting_url,'status',e.status,'notes',e.notes) order by e.start_at) from public.student_schedule_events e left join public.tutors t on t.id=e.tutor_id where e.start_at>=now()-interval '30 days' and (e.student_id=sid or e.group_id in(select group_id from public.os_student_group_members where student_id=sid and is_active=true))),'[]'::jsonb),'v16_reschedule_requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.created_at desc) from public.student_reschedule_requests r where r.student_id=sid),'[]'::jsonb),'v16_assignments',coalesce((select jsonb_agg(to_jsonb(a) order by coalesce(a.due_at,'2999-01-01'::timestamptz),a.created_at desc) from public.student_assignments a where a.status='published' and (a.student_id=sid or a.course_id in(select course_id from public.os_student_course_enrollments where student_id=sid) or a.group_id in(select group_id from public.os_student_group_members where student_id=sid and is_active=true))),'[]'::jsonb),'v16_assignment_submissions',coalesce((select jsonb_agg(to_jsonb(s) order by s.submitted_at desc) from public.student_assignment_submissions s where s.student_id=sid),'[]'::jsonb),'v16_parent_links',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'parent_name',p.parent_name,'relationship',p.relationship,'active',p.active,'expires_at',p.expires_at,'last_used_at',p.last_used_at,'created_at',p.created_at) order by p.created_at desc) from public.student_parent_links p where p.student_id=sid),'[]'::jsonb),'v16_support_tickets',coalesce((select jsonb_agg(to_jsonb(t) order by t.updated_at desc) from public.student_support_tickets t where t.student_id=sid),'[]'::jsonb),'v16_support_messages',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at) from public.student_support_messages m where m.ticket_id in(select id from public.student_support_tickets where student_id=sid)),'[]'::jsonb),'v16_certificates',coalesce((select jsonb_agg(to_jsonb(c) order by c.issued_at desc) from public.student_certificates c where c.student_id=sid and c.status='issued'),'[]'::jsonb),'v16_devices',coalesce((select jsonb_agg(to_jsonb(d) order by d.last_seen_at desc) from public.student_devices d where d.student_id=sid),'[]'::jsonb),'v16_receipts',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'receipt_no',e.receipt_no,'receipt_token',e.receipt_token,'course_text',e.course_text,'amount',coalesce(p.verified_amount,p.amount_submitted,e.amount_quoted),'created_at',e.created_at) order by e.created_at desc) from public.enrollments e left join lateral(select * from public.payments p where p.enrollment_id=e.id order by p.created_at desc limit 1)p on true where e.id in(select source_enrollment_id from public.os_student_course_enrollments where student_id=sid and status in('active','paused','completed')) and e.receipt_no is not null),'[]'::jsonb),'v16_recommendations',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'title',c.name,'cover_url',c.image_url,'tutor_name',t.display_name,'description',coalesce(o.public_note,c.short_detail),'hours',coalesce(o.default_hours,0),'price',coalesce(o.display_price,0),'score',(case when coalesce(c.target_text,'') ilike '%'||(select coalesce(grade,'') from public.os_students where id=sid)||'%' then 50 else 0 end)+(case when c.course_type in(select cc.course_type from public.courses cc join public.os_student_course_enrollments sce on sce.course_id=cc.id where sce.student_id=sid limit 1) then 20 else 0 end)+(100-least(100,c.sort_order))) order by ((case when coalesce(c.target_text,'') ilike '%'||(select coalesce(grade,'') from public.os_students where id=sid)||'%' then 50 else 0 end)+(case when c.course_type in(select cc.course_type from public.courses cc join public.os_student_course_enrollments sce on sce.course_id=cc.id where sce.student_id=sid limit 1) then 20 else 0 end)+(100-least(100,c.sort_order))) desc) from public.courses c join public.tutors t on t.id=c.tutor_id join public.course_offerings o on o.course_id=c.id where c.active=true and t.active=true and o.status='open' and o.student_portal_open=true and o.enrollment_open=true and c.id not in(select coalesce(course_id,'00000000-0000-0000-0000-000000000000'::uuid) from public.os_student_course_enrollments where student_id=sid) limit 6),'[]'::jsonb),'v16_notification_rules',coalesce((select jsonb_agg(to_jsonb(nr)) from public.student_notification_rules nr where nr.enabled=true),'[]'::jsonb));end$$;
grant execute on function public.student_v16_bootstrap() to authenticated;

-- Grants for RPCs
revoke all on function public.student_v16_request_reschedule(uuid,timestamptz,text) from public,anon;grant execute on function public.student_v16_request_reschedule(uuid,timestamptz,text) to authenticated;
revoke all on function public.student_v16_submit_assignment(uuid,text,text[]) from public,anon;grant execute on function public.student_v16_submit_assignment(uuid,text,text[]) to authenticated;
revoke all on function public.student_v16_create_ticket(text,text,text) from public,anon;grant execute on function public.student_v16_create_ticket(text,text,text) to authenticated;
revoke all on function public.student_v16_reply_ticket(uuid,text) from public,anon;grant execute on function public.student_v16_reply_ticket(uuid,text) to authenticated;
revoke all on function public.student_v16_create_parent_link(text,text) from public,anon;grant execute on function public.student_v16_create_parent_link(text,text) to authenticated;
revoke all on function public.student_v16_revoke_parent_link(uuid) from public,anon;grant execute on function public.student_v16_revoke_parent_link(uuid) to authenticated;
revoke all on function public.student_v16_register_device(text,text,text) from public,anon;grant execute on function public.student_v16_register_device(text,text,text) to authenticated;
revoke all on function public.student_v16_revoke_other_devices(text) from public,anon;grant execute on function public.student_v16_revoke_other_devices(text) to authenticated;
revoke all on function public.student_v16_certificate(uuid) from public,anon;grant execute on function public.student_v16_certificate(uuid) to authenticated;

commit;

-- Diagnostics
select 'student_schedule_events' module,count(*) rows from public.student_schedule_events union all
select 'student_assignments',count(*) from public.student_assignments union all
select 'student_support_tickets',count(*) from public.student_support_tickets union all
select 'student_certificates',count(*) from public.student_certificates;
