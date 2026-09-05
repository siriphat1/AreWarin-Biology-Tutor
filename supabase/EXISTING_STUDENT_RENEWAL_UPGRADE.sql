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
