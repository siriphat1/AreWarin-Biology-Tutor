-- BioAre | setup_all.sql — non-destructive setup + Manager access
-- Paste into Supabase Dashboard > SQL Editor for project ihmiqtwclnqrezsnswfz
-- Re-running is safe: create table if not exists and drop/recreate only access policies.
-- This does NOT create the login user; add in Authentication > Users, then run grant_manager.sql.

-- The AC Lab | Speaker feedback (Supabase)
-- Run once in: Supabase Dashboard > SQL Editor > New query > Run.
-- The supplied browser publishable key is safe for public use ONLY with these RLS rules.
-- Keep service_role and sb_secret_* keys private (never commit those keys to GitHub).

create extension if not exists pgcrypto;

create table if not exists public.speaker_feedback (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  school text not null,
  grade text not null,
  nickname text,
  full_name text,
  topic text,
  clarity smallint not null,
  content smallint not null,
  delivery smallint not null,
  interaction smallint not null,
  usefulness smallint not null,
  overall smallint not null,
  pace text,
  difficulty text,
  message_to_are text,

  constraint school_valid check (char_length(btrim(school)) between 1 and 120),
  constraint grade_valid check (char_length(btrim(grade)) between 1 and 30),
  constraint nickname_valid check (nickname is null or char_length(nickname) <= 60),
  constraint full_name_valid check (full_name is null or char_length(full_name) <= 120),
  constraint topic_valid check (topic is null or char_length(topic) <= 120),
  constraint message_valid check (message_to_are is null or char_length(message_to_are) <= 1500),
  constraint clarity_valid check (clarity between 1 and 5),
  constraint content_valid check (content between 1 and 5),
  constraint delivery_valid check (delivery between 1 and 5),
  constraint interaction_valid check (interaction between 1 and 5),
  constraint usefulness_valid check (usefulness between 1 and 5),
  constraint overall_valid check (overall between 1 and 5),
  constraint pace_valid check (pace is null or pace in ('too_slow','just_right','too_fast')),
  constraint difficulty_valid check (difficulty is null or difficulty in ('too_easy','just_right','too_hard'))
);

create index if not exists speaker_feedback_created_at_idx
  on public.speaker_feedback (created_at desc);
create index if not exists speaker_feedback_school_grade_idx
  on public.speaker_feedback (school, grade);

-- Protect students' responses: anonymous visitors may insert, but never read,
-- update, or delete submissions from the browser.
alter table public.speaker_feedback enable row level security;
revoke all on table public.speaker_feedback from anon, authenticated;

-- Column-specific INSERT grants ensure the browser cannot set id/created_at.
grant insert (
  school, grade, nickname, full_name, topic,
  clarity, content, delivery, interaction, usefulness, overall,
  pace, difficulty, message_to_are
) on public.speaker_feedback to anon;

-- The browser is intentionally unauthenticated. Do not add a public SELECT policy.
drop policy if exists speaker_feedback_public_insert on public.speaker_feedback;
create policy speaker_feedback_public_insert
on public.speaker_feedback for insert to anon
with check (true);

-- To review submissions: use Supabase > Table Editor while signed in as project owner.
-- Or execute this query in the SQL Editor (owner role only):
-- select created_at, school, grade, nickname, full_name, topic,
--        clarity, content, delivery, interaction, usefulness, overall,
--        pace, difficulty, message_to_are
-- from public.speaker_feedback
-- order by created_at desc;


-- THE AC LAB | FEEDBACK MANAGER
-- UPGRADE for an existing speaker_feedback table.
-- Run in Supabase > SQL Editor as the project owner, after speaker_feedback.sql.
-- Public visitors can INSERT feedback; only approved Supabase Auth users can SELECT it.

create table if not exists public.speaker_feedback_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);

alter table public.speaker_feedback_admins enable row level security;

-- No public membership listing or self-service enrollment.
revoke all on table public.speaker_feedback_admins from anon, authenticated;
grant select on table public.speaker_feedback_admins to authenticated;

drop policy if exists speaker_feedback_admins_read_self on public.speaker_feedback_admins;
create policy speaker_feedback_admins_read_self
on public.speaker_feedback_admins for select to authenticated
using (user_id = (select auth.uid()));

-- Allow signed-in people SELECT as a Postgres privilege, but restrict all rows
-- via RLS to people whose auth.users.id appears in the admin table.
-- Public (anon) has NO SELECT. Authenticated gets NO INSERT/UPDATE/DELETE.
revoke all on table public.speaker_feedback from authenticated;
grant select on table public.speaker_feedback to authenticated;

drop policy if exists speaker_feedback_admin_select on public.speaker_feedback;
create policy speaker_feedback_admin_select
on public.speaker_feedback for select to authenticated
using (
  exists (
    select 1
    from public.speaker_feedback_admins as a
    where a.user_id = (select auth.uid())
  )
);

-- Do not add an anonymous SELECT policy. Do not grant write to authenticated.
-- To enroll yourself, create a Supabase Auth user and then run grant_manager.sql.
