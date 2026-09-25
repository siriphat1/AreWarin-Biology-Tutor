-- ============================================================
-- Alumni structured fields + Royal Scholarship + Banner support
-- Run once in Supabase SQL Editor. Safe to run again.
-- ============================================================

alter table public.alumni add column if not exists naktham_level text not null default '';
alter table public.alumni add column if not exists pali_level text not null default '';
alter table public.alumni add column if not exists is_royal_scholarship boolean not null default false;
alter table public.alumni add column if not exists royal_scholarship_batch text not null default '';
alter table public.alumni add column if not exists royal_scholarship_phase text not null default '';

alter table public.alumni_submissions add column if not exists naktham_level text not null default '';
alter table public.alumni_submissions add column if not exists pali_level text not null default '';
alter table public.alumni_submissions add column if not exists is_royal_scholarship boolean not null default false;
alter table public.alumni_submissions add column if not exists royal_scholarship_batch text not null default '';
alter table public.alumni_submissions add column if not exists royal_scholarship_phase text not null default '';

create index if not exists alumni_royal_scholarship_idx on public.alumni (is_royal_scholarship, published);
create index if not exists alumni_submissions_royal_scholarship_idx on public.alumni_submissions (is_royal_scholarship, review_status);

-- Replace public submission RPC so the new fields are retained.
create or replace function public.create_alumni_submission(p_payload jsonb)
returns table(id uuid, submission_no bigint, upload_token uuid)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.alumni_submissions;
  v_is_scholar boolean := coalesce((p_payload->>'isRoyalScholarship')::boolean,false);
begin
  if coalesce((p_payload->>'consentAccepted')::boolean, false) is not true then
    raise exception 'กรุณายอมรับเงื่อนไขการส่งข้อมูลก่อน';
  end if;
  if coalesce(btrim(p_payload->>'fullName'),'') = '' then
    raise exception 'กรุณาระบุชื่อ-นามสกุล';
  end if;
  if coalesce(btrim(p_payload->>'batch'),'') = '' then
    raise exception 'กรุณาระบุรุ่นศิษย์เก่า';
  end if;
  if coalesce(btrim(p_payload->>'phone'),'') = '' and coalesce(btrim(p_payload->>'email'),'') = '' then
    raise exception 'กรุณาระบุเบอร์โทรศัพท์หรือ Email อย่างน้อย 1 ช่อง';
  end if;
  if v_is_scholar and (coalesce(btrim(p_payload->>'royalScholarshipBatch'),'') = '' or coalesce(btrim(p_payload->>'royalScholarshipPhase'),'') = '') then
    raise exception 'กรุณาระบุรุ่นและระยะของทุนเฉลิมราชกุมารี';
  end if;

  insert into public.alumni_submissions (
    submission_state, review_status,
    full_name, batch, graduation_year, graduation_level, naktham_level, pali_level,
    is_royal_scholarship, royal_scholarship_batch, royal_scholarship_phase,
    current_position, occupation, organization, education,
    phone, email, facebook_url, bio, show_contact,
    photo_url, consent_accepted, consent_accepted_at, upload_token
  ) values (
    'uploading', 'pending',
    btrim(p_payload->>'fullName'), btrim(p_payload->>'batch'),
    coalesce(btrim(p_payload->>'graduationYear'),''),
    coalesce(btrim(p_payload->>'graduationLevel'),''),
    coalesce(btrim(p_payload->>'nakthamLevel'),''),
    coalesce(btrim(p_payload->>'paliLevel'),''),
    v_is_scholar,
    case when v_is_scholar then coalesce(btrim(p_payload->>'royalScholarshipBatch'),'') else '' end,
    case when v_is_scholar then coalesce(btrim(p_payload->>'royalScholarshipPhase'),'') else '' end,
    coalesce(btrim(p_payload->>'currentPosition'),''),
    coalesce(btrim(p_payload->>'occupation'),''),
    coalesce(btrim(p_payload->>'organization'),''),
    coalesce(p_payload->>'education',''),
    coalesce(btrim(p_payload->>'phone'),''),
    coalesce(btrim(p_payload->>'email'),''),
    coalesce(btrim(p_payload->>'facebookUrl'),''),
    coalesce(p_payload->>'bio',''),
    coalesce((p_payload->>'showContact')::boolean,false),
    coalesce(btrim(p_payload->>'photoUrl'),''),
    true, now(), gen_random_uuid()
  ) returning * into v_row;

  return query select v_row.id, v_row.submission_no, v_row.upload_token;
end;
$$;

revoke all on function public.create_alumni_submission(jsonb) from public;
grant execute on function public.create_alumni_submission(jsonb) to anon, authenticated;
