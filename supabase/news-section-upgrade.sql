-- ============================================================
-- Supabase Upgrade: Dedicated News Section
-- Project: Wat Nongwang Wittaya School
-- Run ONCE in Supabase > SQL Editor. Safe to run again.
-- ============================================================

-- Keep Website Manager authorization aligned with the current Authentication-first mode.
-- Every non-anonymous account created in Supabase Authentication is a manager.
create or replace function public.is_site_admin()
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select auth.uid() is not null
     and coalesce((auth.jwt()->>'is_anonymous')::boolean, false) = false;
$$;

revoke all on function public.is_site_admin() from public;
grant execute on function public.is_site_admin() to authenticated;

create table if not exists public.news (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  summary text not null default '',
  image_url text not null default '',
  category text not null default 'ข่าวสาร',
  category_color text not null default 'bg-orange-100 text-orange-600',
  date_text text not null default '',
  month_year text not null default '',
  url text not null default '',
  published boolean not null default true,
  sort_order integer not null default 0,
  published_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

create index if not exists news_public_order_idx
  on public.news (published, sort_order, created_at desc);

alter table public.news enable row level security;

-- Public website can read only published news.
drop policy if exists "public read published news" on public.news;
create policy "public read published news" on public.news
for select using (published = true);

-- Website Manager can also read drafts and manage all news.
drop policy if exists "admin read all news" on public.news;
create policy "admin read all news" on public.news
for select to authenticated using (public.is_site_admin());

drop policy if exists "admin insert news" on public.news;
create policy "admin insert news" on public.news
for insert to authenticated with check (public.is_site_admin());

drop policy if exists "admin update news" on public.news;
create policy "admin update news" on public.news
for update to authenticated using (public.is_site_admin()) with check (public.is_site_admin());

drop policy if exists "admin delete news" on public.news;
create policy "admin delete news" on public.news
for delete to authenticated using (public.is_site_admin());

grant select on public.news to anon, authenticated;
grant insert, update, delete on public.news to authenticated;

-- Reuse/create updated_at trigger function.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists news_updated_at on public.news;
create trigger news_updated_at before update on public.news
for each row execute function public.set_updated_at();

-- Migrate the existing JSON news array from site_settings only when the news
-- table is still empty. This prevents duplicates if the SQL is run again.
do $$
begin
  if not exists (select 1 from public.news limit 1) then
    insert into public.news (
      title, summary, image_url, category, category_color,
      date_text, month_year, url, published, sort_order
    )
    select
      coalesce(nullif(item->>'title',''), 'ข่าวสาร'),
      coalesce(item->>'summary',''),
      coalesce(item->>'image',''),
      coalesce(nullif(item->>'type',''), 'ข่าวสาร'),
      coalesce(nullif(item->>'typeColor',''), 'bg-orange-100 text-orange-600'),
      coalesce(item->>'date',''),
      coalesce(item->>'monthYear',''),
      coalesce(item->>'url',''),
      coalesce((item->>'published')::boolean, true),
      (ord - 1) * 10
    from public.site_settings s
    cross join lateral jsonb_array_elements(coalesce(s.data->'news','[]'::jsonb)) with ordinality as n(item, ord)
    where s.id = 1;
  end if;
end $$;

comment on table public.news is
'Dedicated news content managed from Website Manager. Public can read published rows only.';
