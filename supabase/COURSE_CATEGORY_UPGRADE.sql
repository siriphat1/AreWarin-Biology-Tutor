-- AreWarin Course Category Upgrade
-- รองรับ: 1 คอร์สอยู่ได้หลายหมวด / สร้างหมวดใหม่จาก Manager / หน้าเว็บแสดงตามหมวดของคอร์สจริง
-- Safe / idempotent migration สำหรับระบบเดิม

begin;

-- ---------------------------------------------------------
-- 1) Junction table: courses <-> subject_categories
-- ---------------------------------------------------------
create table if not exists public.course_categories (
    course_id uuid not null
        references public.courses(id)
        on delete cascade,

    category_id text not null
        references public.subject_categories(id)
        on delete cascade,

    created_at timestamptz not null default now(),

    primary key (course_id, category_id)
);

create index if not exists idx_course_categories_course
    on public.course_categories(course_id);

create index if not exists idx_course_categories_category
    on public.course_categories(category_id);

-- ---------------------------------------------------------
-- 2) RLS
-- ---------------------------------------------------------
alter table public.course_categories enable row level security;

drop policy if exists "public read course categories"
on public.course_categories;

create policy "public read course categories"
on public.course_categories
for select
to anon, authenticated
using (true);

drop policy if exists "manager manage course categories"
on public.course_categories;

create policy "manager manage course categories"
on public.course_categories
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

-- ---------------------------------------------------------
-- 3) RPC สำหรับบันทึกหลายหมวดในครั้งเดียว
-- ---------------------------------------------------------
create or replace function public.manager_set_course_categories(
    p_course_id uuid,
    p_category_ids text[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_manager() then
        raise exception 'Manager permission required';
    end if;

    delete from public.course_categories
    where course_id = p_course_id;

    insert into public.course_categories(course_id, category_id)
    select
        p_course_id,
        x.category_id
    from (
        select distinct unnest(
            coalesce(p_category_ids, '{}'::text[])
        ) as category_id
    ) x
    join public.subject_categories sc
        on sc.id = x.category_id;
end;
$$;

grant execute on function public.manager_set_course_categories(uuid, text[])
to authenticated;

-- ---------------------------------------------------------
-- 4) Backfill คอร์สเดิมจาก tutor.categories
-- เพื่อให้คอร์สเก่าไม่หายหลังติดตั้ง
-- หมายเหตุ: หลังติดตั้งสามารถเข้า Manager แล้วแก้หมวดรายคอร์สได้ทันที
-- ---------------------------------------------------------
insert into public.course_categories(course_id, category_id)
select distinct
    c.id,
    legacy.category_id
from public.courses c
join public.tutors t
    on t.id = c.tutor_id
cross join lateral (
    select unnest(coalesce(t.categories, '{}'::text[])) as category_id
) legacy
join public.subject_categories sc
    on sc.id = legacy.category_id
on conflict (course_id, category_id) do nothing;

commit;
