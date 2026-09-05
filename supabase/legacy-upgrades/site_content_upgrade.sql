-- ============================================================
-- AreWarin Biology: Site branding, home banners, categories
-- Run once in Supabase SQL Editor on top of the existing V2 schema.
-- ============================================================

create table if not exists public.site_branding (
  id smallint primary key default 1 check (id = 1),
  logo_url text,
  site_name_th text not null default 'กวดวิชาชีววิทยา อาวริน',
  site_name_en text not null default 'AreWarin Biology',
  tagline text not null default 'เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย',
  location_badge text default 'Onsite @ขอนแก่น',
  registration_badge text default '🚀 เปิดรับสมัครแล้ว!',
  updated_at timestamptz not null default now()
);

create table if not exists public.home_banners (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  highlight_text text,
  description text,
  badge_text text,
  location_text text,
  image_url text,
  link_url text,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subject_categories (
  id text primary key check (id ~ '^[a-z0-9_-]+$'),
  name_th text not null,
  name_en text,
  icon_class text not null default 'fas fa-book-open',
  theme text not null default 'sky' check(theme in ('rose','teal','indigo','amber','sky','violet','emerald','slate')),
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.site_branding enable row level security;
alter table public.home_banners enable row level security;
alter table public.subject_categories enable row level security;

-- Idempotent policy creation.
do $$ begin
  create policy "public site branding read" on public.site_branding
    for select to anon, authenticated using (true);
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager site branding" on public.site_branding
    for all to authenticated using (public.is_manager()) with check (public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public active banners read" on public.home_banners
    for select to anon, authenticated using (active or public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager banners" on public.home_banners
    for all to authenticated using (public.is_manager()) with check (public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "public active categories read" on public.subject_categories
    for select to anon, authenticated using (active or public.is_manager());
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager categories" on public.subject_categories
    for all to authenticated using (public.is_manager()) with check (public.is_manager());
exception when duplicate_object then null; end $$;

-- Public media bucket for logo/banner assets.
insert into storage.buckets(id,name,public)
values ('site-assets','site-assets',true)
on conflict(id) do update set public=excluded.public;

do $$ begin
  create policy "public site assets read" on storage.objects
    for select to anon, authenticated using(bucket_id='site-assets');
exception when duplicate_object then null; end $$;

do $$ begin
  create policy "manager site assets" on storage.objects
    for all to authenticated
    using(bucket_id='site-assets' and public.is_manager())
    with check(bucket_id='site-assets' and public.is_manager());
exception when duplicate_object then null; end $$;

-- Seed current branding once.
insert into public.site_branding(
  id,logo_url,site_name_th,site_name_en,tagline,location_badge,registration_badge
) values (
  1,
  'https://img2.pic.in.th/pic/531691933_1782062845771076_6500762805646335341_n.jpg',
  'กวดวิชาชีววิทยา อาวริน',
  'AreWarin Biology',
  'เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย',
  'Onsite @ขอนแก่น',
  '🚀 เปิดรับสมัครแล้ว!'
)
on conflict(id) do nothing;

-- Seed banners only if the table is empty.
insert into public.home_banners(title,highlight_text,description,badge_text,location_text,image_url,active,sort_order)
select * from (values
  ('กวดวิชาชีววิทยา','อาวริน','เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย','🚀 เปิดรับสมัครแล้ว!','Onsite @ขอนแก่น','https://images.unsplash.com/photo-1532094349884-543bc11b234d?q=80&w=2070&auto=format&fit=crop',true,10),
  ('ติวเข้ม','มัธยมปลาย','ชีวะ - เคมี A-Level / NETSAT / สอวน.','เตรียมสอบอย่างเป็นระบบ','Online & Onsite','https://images.unsplash.com/photo-1576086213369-97a306d36557?q=80&w=2080&auto=format&fit=crop',true,20),
  ('ปูพื้นฐาน','ประถม - ม.ต้น','วิทย์ - คณิต สอนสนุก เข้าใจง่าย','พื้นฐานแน่น เรียนรู้สนุก','Online & Onsite','https://images.unsplash.com/photo-1503676260728-1c00da094a0b?q=80&w=2022&auto=format&fit=crop',true,30)
) as seed(title,highlight_text,description,badge_text,location_text,image_url,active,sort_order)
where not exists (select 1 from public.home_banners);

-- Seed current subject categories.
insert into public.subject_categories(id,name_th,name_en,icon_class,theme,active,sort_order) values
('bio','ชีววิทยา','Biology','fas fa-dna','rose',true,10),
('chem','เคมี','Chemistry','fas fa-flask','teal',true,20),
('sci','วิทยาศาสตร์','Science','fas fa-atom','indigo',true,30),
('math','คณิตศาสตร์','Mathematics','fas fa-calculator','amber',true,40)
on conflict(id) do nothing;
