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


-- =========================================================
-- Verification view/query helper
-- =========================================================
-- หลัง Run สามารถทดสอบด้วย:
-- select * from public.course_categories limit 20;


-- =========================================================
-- AreWarin v4 — per-course package availability + custom price
-- Safe / idempotent
-- =========================================================
begin;

create table if not exists public.course_package_rules (
  course_id uuid not null references public.courses(id) on delete cascade,
  package_code text not null check (package_code in ('yearly','monthly','pack20','pack10','hourly')),
  enabled boolean not null default true,
  custom_price numeric(12,2) null check (custom_price is null or custom_price >= 0),
  updated_at timestamptz not null default now(),
  primary key (course_id, package_code)
);

create index if not exists idx_course_package_rules_course
  on public.course_package_rules(course_id);

alter table public.course_package_rules enable row level security;

drop policy if exists "public read course package rules" on public.course_package_rules;
create policy "public read course package rules"
on public.course_package_rules
for select
to anon, authenticated
using (true);

drop policy if exists "manager manage course package rules" on public.course_package_rules;
create policy "manager manage course package rules"
on public.course_package_rules
for all
to authenticated
using (public.is_manager())
with check (public.is_manager());

commit;

-- ทดสอบหลัง Run:
-- select * from public.course_package_rules order by course_id, package_code;



-- =========================================================
-- AREWARIN v5 RECOVERY FLAGS + REPAIR
-- =========================================================

begin;

-- บอก frontend ว่าตารางราคาเฉพาะคอร์สพร้อมแล้ว
insert into public.app_settings(key,value,description)
values(
  'COURSE_RULES_READY',
  'true'::jsonb,
  'Per-course package availability/custom pricing is installed'
)
on conflict(key) do update
set value = excluded.value,
    description = excluded.description,
    updated_at = now();

-- บอก frontend ว่าระบบ category relation พร้อมแล้ว
insert into public.app_settings(key,value,description)
values(
  'COURSE_CATEGORY_RELATION_READY',
  'true'::jsonb,
  'Course-to-subject-category relation is installed'
)
on conflict(key) do update
set value = excluded.value,
    description = excluded.description,
    updated_at = now();

-- Repair/backfill อีกครั้ง:
-- คอร์สเดิมที่ยังไม่มีหมวด จะรับหมวดเดิมของติวเตอร์
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
where not exists (
  select 1
  from public.course_categories cc
  where cc.course_id = c.id
)
on conflict(course_id, category_id) do nothing;

commit;

-- ตรวจหลัง Run:
-- select key,value from public.app_settings
-- where key in ('COURSE_RULES_READY','COURSE_CATEGORY_RELATION_READY');
--
-- select count(*) as course_category_rows from public.course_categories;
-- select count(*) as package_rule_rows from public.course_package_rules;
