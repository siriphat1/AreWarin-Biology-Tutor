-- BioAre v3 · Add-on for the existing feedback and admin tables.
-- Non-destructive and repeatable. Run AFTER 01_existing_core.sql and 02_school_aliases.sql.
-- Existing feedback rows and original school names are kept.
create extension if not exists pgcrypto;

-- Keep canonical schools publicly searchable (no student information here).
create table if not exists public.bioare_schools (
 id uuid primary key default gen_random_uuid(),
 canonical_name text not null unique,
 active boolean not null default true,
 created_at timestamptz not null default now(),
 constraint bioare_school_name_len check (char_length(btrim(canonical_name)) between 2 and 120)
);
create index if not exists bioare_schools_active_name_idx on public.bioare_schools(active, canonical_name);

create table if not exists public.bioare_sessions (
 id uuid primary key default gen_random_uuid(),
 title text not null,
 school_id uuid references public.bioare_schools(id) on delete set null,
 school_name text not null,
 grade text,
 topic text,
 starts_at timestamptz not null default now(),
 status text not null default 'draft' check(status in ('draft','open','closed')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 constraint bioare_session_title_len check(char_length(btrim(title)) between 2 and 150),
 constraint bioare_session_school_len check(char_length(btrim(school_name)) between 1 and 120),
 constraint bioare_session_grade_len check(grade is null or char_length(grade) <= 30),
 constraint bioare_session_topic_len check(topic is null or char_length(topic) <= 120)
);
create index if not exists bioare_sessions_start_idx on public.bioare_sessions(starts_at desc);

create table if not exists public.bioare_form_questions (
 id uuid primary key default gen_random_uuid(),
 session_id uuid references public.bioare_sessions(id) on delete cascade,
 label text not null,
 kind text not null default 'short' check(kind in ('short','long','choice','scale')),
 options jsonb not null default '[]'::jsonb check(jsonb_typeof(options)='array' and pg_column_size(options) <= 3000),
 required boolean not null default false,
 active boolean not null default true,
 sort_order integer not null default 100,
 created_at timestamptz not null default now(),
 constraint bioare_question_label_len check(char_length(btrim(label)) between 2 and 180)
);
create index if not exists bioare_questions_sort_idx on public.bioare_form_questions(active, session_id, sort_order);

create table if not exists public.bioare_settings (
 key text primary key,
 value jsonb not null,
 updated_at timestamptz not null default now()
);
insert into public.bioare_settings(key,value) values
 ('privacy_notice',to_jsonb('แบบประเมินนี้จัดทำเพื่อพัฒนาคุณภาพการบรรยาย ข้อมูลโรงเรียน ระดับชั้น คะแนน และความคิดเห็นจะถูกใช้ในการวิเคราะห์ผล ชื่อเล่นและชื่อ–นามสกุลไม่บังคับ เจ้าของระบบเป็นผู้เข้าถึงคำตอบรายบุคคล สามารถติดต่อผู้ดูแลเพื่อขอใช้สิทธิเกี่ยวกับข้อมูลส่วนบุคคลได้ที่ arewarin.biology@gmail.com'::text)),
 ('privacy_version',to_jsonb('2026-11-15-v1'::text)),
 ('retention_days','365'::jsonb),
 ('wall_enabled','false'::jsonb)
on conflict(key) do nothing;

alter table public.speaker_feedback add column if not exists session_id uuid references public.bioare_sessions(id) on delete set null;
alter table public.speaker_feedback add column if not exists custom_answers jsonb not null default '{}'::jsonb;
alter table public.speaker_feedback add column if not exists privacy_version text;
alter table public.speaker_feedback add column if not exists consented_at timestamptz;
alter table public.speaker_feedback add column if not exists submission_ref uuid not null default gen_random_uuid();
create unique index if not exists bioare_submission_ref_uidx on public.speaker_feedback(submission_ref);
create index if not exists bioare_feedback_session_idx on public.speaker_feedback(session_id, created_at desc);
-- A max-size check is added only if one does not already exist.
do $$ begin
 if not exists (select 1 from pg_constraint where conname='bioare_answers_size') then
   alter table public.speaker_feedback add constraint bioare_answers_size check (jsonb_typeof(custom_answers)='object' and pg_column_size(custom_answers)<10000);
 end if;
end $$;

-- During session-linked submissions, validate session and freeze its official school/topic.
-- Students cannot force a closed session or change school by editing the browser request.
create or replace function public.bioare_validate_submission() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare sess public.bioare_sessions%rowtype;
begin
 if new.session_id is not null then
   select * into sess from public.bioare_sessions where id=new.session_id;
   if not found or sess.status <> 'open' then
      raise exception 'This feedback session is no longer accepting responses';
   end if;
   new.school := sess.school_name;
   if nullif(btrim(coalesce(sess.grade,'')),'') is not null then new.grade := sess.grade; end if;
   if nullif(btrim(coalesce(sess.topic,'')),'') is not null then new.topic := sess.topic; end if;
 end if;
 if new.consented_at is null then raise exception 'Privacy notice acknowledgement is required'; end if;
 if new.privacy_version is null or char_length(new.privacy_version) > 60 then raise exception 'Invalid privacy version'; end if;
 return new;
end $$;
drop trigger if exists bioare_validate_submission_trg on public.speaker_feedback;
create trigger bioare_validate_submission_trg before insert on public.speaker_feedback
for each row execute function public.bioare_validate_submission();
-- Previous website versions that don't send consent fields must be upgraded together.
grant insert (session_id, custom_answers, privacy_version, consented_at, submission_ref)
on public.speaker_feedback to anon;

create table if not exists public.bioare_wall_items (
 id uuid primary key default gen_random_uuid(),
 feedback_id uuid unique references public.speaker_feedback(id) on delete cascade,
 excerpt text not null,
 is_public boolean not null default false,
 created_at timestamptz not null default now(),
 constraint bioare_wall_excerpt_len check(char_length(btrim(excerpt)) between 2 and 450)
);

create table if not exists public.bioare_privacy_requests (
 id uuid primary key default gen_random_uuid(),
 created_at timestamptz not null default now(),
 submission_ref uuid not null,
 request_type text not null check(request_type in ('access','delete','correct')),
 contact_email text,
 details text,
 status text not null default 'pending' check(status in ('pending','reviewing','resolved','rejected')),
 resolution_note text,
 constraint bioare_privacy_req_email_len check(contact_email is null or char_length(contact_email)<=190),
 constraint bioare_privacy_req_details_len check(details is null or char_length(details)<=800)
);
create index if not exists bioare_privacy_pending_idx on public.bioare_privacy_requests(status, created_at desc);

-- Shared authorization predicate so all BioAre administrator features follow same membership table.
create or replace function public.bioare_is_admin() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
 select exists(select 1 from public.speaker_feedback_admins where user_id=(select auth.uid()));
$$;
revoke all on function public.bioare_is_admin() from public;
grant execute on function public.bioare_is_admin() to authenticated;

-- Public reads ONLY open sessions, active schools, active questions and published wall snippets.
-- Public never reads raw feedback, administrator details or privacy requests.
do $$ declare t text;
begin
 foreach t in array array['bioare_schools','bioare_sessions','bioare_form_questions','bioare_settings','bioare_wall_items','bioare_privacy_requests'] loop
  execute format('alter table public.%I enable row level security',t);
  execute format('revoke all on public.%I from anon, authenticated',t);
 end loop;
end $$;

grant select on public.bioare_schools, public.bioare_sessions, public.bioare_form_questions, public.bioare_settings, public.bioare_wall_items to anon;
grant select,insert,update,delete on public.bioare_schools, public.bioare_sessions, public.bioare_form_questions, public.bioare_settings, public.bioare_wall_items to authenticated;
grant insert (submission_ref,request_type,contact_email,details) on public.bioare_privacy_requests to anon;
grant select,update,delete on public.bioare_privacy_requests to authenticated;
-- Managers can erase feedback for verified privacy requests, other logged-in users cannot.
grant delete on public.speaker_feedback to authenticated;

-- Policies recreated idempotently.
drop policy if exists bioare_schools_public_read on public.bioare_schools;
create policy bioare_schools_public_read on public.bioare_schools for select to anon using(active);
drop policy if exists bioare_schools_admin on public.bioare_schools;
create policy bioare_schools_admin on public.bioare_schools for all to authenticated using ((select public.bioare_is_admin())) with check ((select public.bioare_is_admin()));

drop policy if exists bioare_sessions_public_read on public.bioare_sessions;
create policy bioare_sessions_public_read on public.bioare_sessions for select to anon using(status='open');
drop policy if exists bioare_sessions_admin on public.bioare_sessions;
create policy bioare_sessions_admin on public.bioare_sessions for all to authenticated using ((select public.bioare_is_admin())) with check ((select public.bioare_is_admin()));

drop policy if exists bioare_questions_public_read on public.bioare_form_questions;
create policy bioare_questions_public_read on public.bioare_form_questions for select to anon using(active and (session_id is null or exists (select 1 from public.bioare_sessions s where s.id=session_id and s.status='open')));
drop policy if exists bioare_questions_admin on public.bioare_form_questions;
create policy bioare_questions_admin on public.bioare_form_questions for all to authenticated using ((select public.bioare_is_admin())) with check ((select public.bioare_is_admin()));

drop policy if exists bioare_settings_public_read on public.bioare_settings;
create policy bioare_settings_public_read on public.bioare_settings for select to anon using(key in ('privacy_notice','privacy_version','wall_enabled'));
drop policy if exists bioare_settings_admin on public.bioare_settings;
create policy bioare_settings_admin on public.bioare_settings for all to authenticated using ((select public.bioare_is_admin())) with check ((select public.bioare_is_admin()));

drop policy if exists bioare_wall_public_read on public.bioare_wall_items;
create policy bioare_wall_public_read on public.bioare_wall_items for select to anon using(is_public and (select coalesce((select value::text='true' from public.bioare_settings where key='wall_enabled'),false)));
drop policy if exists bioare_wall_admin on public.bioare_wall_items;
create policy bioare_wall_admin on public.bioare_wall_items for all to authenticated using ((select public.bioare_is_admin())) with check ((select public.bioare_is_admin()));

drop policy if exists bioare_privacy_submit on public.bioare_privacy_requests;
create policy bioare_privacy_submit on public.bioare_privacy_requests for insert to anon with check(status='pending' and resolution_note is null);
drop policy if exists bioare_privacy_admin on public.bioare_privacy_requests;
create policy bioare_privacy_admin on public.bioare_privacy_requests for all to authenticated using ((select public.bioare_is_admin())) with check ((select public.bioare_is_admin()));

drop policy if exists bioare_feedback_admin_delete on public.speaker_feedback;
create policy bioare_feedback_admin_delete on public.speaker_feedback for delete to authenticated using ((select public.bioare_is_admin()));

-- Optional safe purge: ADMIN ONLY; call manually after reviewing retention policy.
-- Runs using caller's RLS; no security definer bypass. Wall rows cascade.
-- Purging is irreversible: export a backup first if legally appropriate.
-- Existing old responses with NULL consented_at are still considered by created_at.
create or replace function public.bioare_purge_expired() returns integer
language plpgsql security invoker set search_path=public,pg_temp as $$
declare days_to_keep integer; deleted integer;
begin
 if not (select public.bioare_is_admin()) then raise exception 'Forbidden'; end if;
 select greatest(30,least(3650,coalesce(nullif(trim(both '"' from value::text),'')::integer,365)))
 into days_to_keep from public.bioare_settings where key='retention_days';
 days_to_keep := coalesce(days_to_keep,365);
 delete from public.speaker_feedback where created_at < now() - make_interval(days=>days_to_keep);
 get diagnostics deleted = row_count;
 return deleted;
end $$;
revoke all on function public.bioare_purge_expired() from public, anon;
grant execute on function public.bioare_purge_expired() to authenticated;

-- Optional enable of realtime needs Supabase replication setting. The manager polls even if realtime is OFF.
-- alter publication supabase_realtime add table public.speaker_feedback;
