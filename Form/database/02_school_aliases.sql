-- BioAre · School name grouping / upgrade (non-destructive)
-- Run AFTER database/setup_all.sql. Can be run again safely.
-- Stores alias -> canonical name; DOES NOT change the original school field
-- in speaker_feedback, so old responses and student-entered text are preserved.
-- Admins alone may list, create, edit or remove mappings.

create table if not exists public.bioare_school_aliases (
  alias_key text primary key,
  alias_name text not null,
  canonical_name text not null,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint bioare_alias_key_length check (char_length(alias_key) between 1 and 200),
  constraint bioare_alias_name_length check (char_length(btrim(alias_name)) between 1 and 120),
  constraint bioare_canonical_name_length check (char_length(btrim(canonical_name)) between 1 and 120)
);

create index if not exists bioare_school_aliases_canonical_idx
  on public.bioare_school_aliases (canonical_name);

alter table public.bioare_school_aliases enable row level security;
revoke all on table public.bioare_school_aliases from anon, authenticated;
grant select, insert, update, delete on table public.bioare_school_aliases to authenticated;

drop policy if exists bioare_school_aliases_admin_only on public.bioare_school_aliases;
create policy bioare_school_aliases_admin_only
on public.bioare_school_aliases for all to authenticated
using (
  exists (
    select 1 from public.speaker_feedback_admins as a
    where a.user_id = (select auth.uid())
  )
)
with check (
  exists (
    select 1 from public.speaker_feedback_admins as a
    where a.user_id = (select auth.uid())
  )
);

-- Verify mappings from SQL Editor:
-- select alias_name, canonical_name, updated_at
-- from public.bioare_school_aliases order by canonical_name, alias_name;
-- To undo a mapping, use the "ยกเลิกการรวม" button in BioAre Manager.
-- No data is deleted from public.speaker_feedback by this feature.
