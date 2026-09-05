-- AreWarin Biology — Reviews feature upgrade
-- Run this once in Supabase SQL Editor if your project already uses the V2 schema.

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  student_name text not null,
  school text,
  course_name text,
  review_text text not null,
  image_url text,
  rating smallint not null default 5 check (rating between 1 and 5),
  featured boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists reviews_public_order_idx
  on public.reviews(active, featured desc, sort_order, created_at desc);

alter table public.reviews enable row level security;

drop policy if exists "public active reviews" on public.reviews;
create policy "public active reviews"
  on public.reviews for select to anon, authenticated
  using (active or public.is_manager());

drop policy if exists "manager reviews" on public.reviews;
create policy "manager reviews"
  on public.reviews for all to authenticated
  using (public.is_manager())
  with check (public.is_manager());

insert into storage.buckets(id,name,public)
values ('review-assets','review-assets',true)
on conflict(id) do update set public=excluded.public;

drop policy if exists "public review assets read" on storage.objects;
create policy "public review assets read"
  on storage.objects for select to anon, authenticated
  using (bucket_id='review-assets');

drop policy if exists "manager review assets" on storage.objects;
create policy "manager review assets"
  on storage.objects for all to authenticated
  using (bucket_id='review-assets' and public.is_manager())
  with check (bucket_id='review-assets' and public.is_manager());
