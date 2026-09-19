-- ============================================================================
-- AreWarin Library V1.1 NO-TS
-- Private digital library for students / tutors / managers.
-- ============================================================================
begin;
create extension if not exists pgcrypto;

do $$ begin
  if to_regclass('public.os_students') is null then raise exception 'Missing public.os_students'; end if;
end $$;

alter table public.os_students add column if not exists auth_user_id uuid references auth.users(id) on delete set null;

create table if not exists public.library_categories(
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  icon text,
  sort_order integer not null default 100,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.library_items(
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.library_categories(id) on delete set null,
  title text not null,
  subtitle text,
  author text,
  publisher text,
  publication_year integer,
  isbn text,
  description text,
  tags text[] not null default '{}'::text[],
  storage_provider text not null default 'supabase',
  file_path text not null,
  cover_path text,
  audience text not null default 'all' check(audience in ('all','students','staff')),
  status text not null default 'published' check(status in ('draft','published','archived')),
  is_new boolean not null default false,
  new_until date,
  page_count integer,
  sort_order integer not null default 100,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists library_items_category_idx on public.library_items(category_id,status,sort_order);
create index if not exists library_items_title_idx on public.library_items(lower(title));

create table if not exists public.library_favorites(
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.library_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id,item_id)
);
create table if not exists public.library_reading_progress(
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.library_items(id) on delete cascade,
  last_page integer not null default 1,
  total_pages integer,
  progress_pct numeric(6,2) not null default 0,
  last_opened_at timestamptz not null default now(),
  primary key(user_id,item_id)
);
create table if not exists public.library_access_log(
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  item_id uuid references public.library_items(id) on delete set null,
  role text,
  action text not null default 'open',
  created_at timestamptz not null default now()
);

insert into public.library_categories(code,name,icon,sort_order) values
('BIO_ALEVEL','A-Level Biology','🧬',10),
('BIO_OLYMPIAD','Biology Olympiad','🔬',20),
('CHEM','Chemistry','⚗️',30),
('MATH','Mathematics','∑',40),
('GENERAL','General Learning','📚',100)
on conflict(code) do nothing;

-- Detect role using existing AreWarin identities. Safe for browser and Edge Function.
create or replace function public.library_role_for_user(p_uid uuid)
returns text language plpgsql stable security definer set search_path=public as $$
declare v_role text; v_sql text;
begin
  if p_uid is null then return 'none'; end if;
  if to_regclass('public.profiles') is not null then
    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='role') then
      if exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='id') then
        execute 'select role::text from public.profiles where id=$1 limit 1' into v_role using p_uid;
      elsif exists(select 1 from information_schema.columns where table_schema='public' and table_name='profiles' and column_name='user_id') then
        execute 'select role::text from public.profiles where user_id=$1 limit 1' into v_role using p_uid;
      end if;
      if lower(coalesce(v_role,'')) in ('manager','admin') then return 'admin'; end if;
    end if;
  end if;
  if to_regclass('public.os_staff_profiles') is not null then
    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='os_staff_profiles' and column_name='user_id') then
      execute 'select role::text from public.os_staff_profiles where user_id=$1 and coalesce(active,true)=true limit 1' into v_role using p_uid;
      if v_role is not null then
        if lower(v_role) in ('manager','admin') then return 'admin'; else return 'staff'; end if;
      end if;
    end if;
  end if;
  if to_regclass('public.tutor_os_identities') is not null then
    if exists(select 1 from information_schema.columns where table_schema='public' and table_name='tutor_os_identities' and column_name='auth_user_id') then
      execute 'select case when count(*)>0 then ''staff'' else null end from public.tutor_os_identities where auth_user_id=$1 and coalesce(status,''active'')=''active''' into v_role using p_uid;
      if v_role='staff' then return 'staff'; end if;
    end if;
  end if;
  if exists(select 1 from public.os_students where auth_user_id=p_uid) then return 'student'; end if;
  -- Compatibility with older Student Portal deployments that still use public.students.
  if to_regclass('public.students') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='students' and column_name='auth_user_id') then
    execute 'select case when count(*)>0 then ''student'' else null end from public.students where auth_user_id=$1' into v_role using p_uid;
    if v_role='student' then return 'student'; end if;
  end if;
  return 'none';
end $$;

create or replace function public.library_whoami()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r text; n text; code text;
begin
  if auth.uid() is null then return jsonb_build_object('ok',false,'message','Not signed in'); end if;
  r:=public.library_role_for_user(auth.uid());
  if r='none' then return jsonb_build_object('ok',false,'message','บัญชีนี้ยังไม่เชื่อมกับ AreWarin Student/Tutor/Manager'); end if;
  if r='student' then
    select coalesce(nickname,display_name,first_name,'นักเรียน'),student_code into n,code from public.os_students where auth_user_id=auth.uid() order by created_at desc limit 1;
  else
    n:=coalesce(auth.jwt()->>'email','AreWarin Staff');
  end if;
  return jsonb_build_object('ok',true,'role',r,'display_name',n,'student_code',code,'user_id',auth.uid());
end $$;
grant execute on function public.library_whoami() to authenticated;

create or replace function public.library_catalog(p_search text default null,p_category_id uuid default null,p_new_only boolean default false)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r text; q text:=lower(trim(coalesce(p_search,''))); items jsonb; cats jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  r:=public.library_role_for_user(auth.uid()); if r='none' then raise exception 'No library access'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.is_new desc,x.sort_order,x.title),'[]'::jsonb) into items
  from (
    select i.id,i.title,i.subtitle,i.author,i.publisher,i.publication_year,i.isbn,i.description,i.tags,i.cover_path,i.audience,i.sort_order,
      c.id category_id,c.name category_name,c.icon category_icon,
      (i.is_new and (i.new_until is null or i.new_until>=current_date)) or i.created_at>=now()-interval '30 days' as is_new,
      coalesce(p.last_page,1) last_page,coalesce(p.progress_pct,0) progress_pct,(f.user_id is not null) favorite
    from public.library_items i
    left join public.library_categories c on c.id=i.category_id
    left join public.library_reading_progress p on p.item_id=i.id and p.user_id=auth.uid()
    left join public.library_favorites f on f.item_id=i.id and f.user_id=auth.uid()
    where i.status='published'
      and (r in ('admin','staff') or i.audience in ('all','students'))
      and (p_category_id is null or i.category_id=p_category_id)
      and (not p_new_only or ((i.is_new and (i.new_until is null or i.new_until>=current_date)) or i.created_at>=now()-interval '30 days'))
      and (q='' or lower(concat_ws(' ',i.title,i.subtitle,i.author,i.publisher,i.isbn,array_to_string(i.tags,' '))) like '%'||q||'%')
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb) into cats from (select id,code,name,icon,description,sort_order from public.library_categories where active=true) x;
  return jsonb_build_object('ok',true,'items',items,'categories',cats);
end $$;
grant execute on function public.library_catalog(text,uuid,boolean) to authenticated;

create or replace function public.library_toggle_favorite(p_item_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null or public.library_role_for_user(auth.uid())='none' then raise exception 'No access'; end if;
  if exists(select 1 from public.library_favorites where user_id=auth.uid() and item_id=p_item_id) then
    delete from public.library_favorites where user_id=auth.uid() and item_id=p_item_id;
    return jsonb_build_object('ok',true,'favorite',false);
  end if;
  insert into public.library_favorites(user_id,item_id) values(auth.uid(),p_item_id) on conflict do nothing;
  return jsonb_build_object('ok',true,'favorite',true);
end $$;
grant execute on function public.library_toggle_favorite(uuid) to authenticated;

create or replace function public.library_progress_save(p_item_id uuid,p_last_page integer,p_total_pages integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pct numeric;
begin
  if auth.uid() is null or public.library_role_for_user(auth.uid())='none' then raise exception 'No access'; end if;
  pct:=case when coalesce(p_total_pages,0)>0 then least(100,round((greatest(1,p_last_page)::numeric/p_total_pages)*100,2)) else 0 end;
  insert into public.library_reading_progress(user_id,item_id,last_page,total_pages,progress_pct,last_opened_at)
  values(auth.uid(),p_item_id,greatest(1,p_last_page),p_total_pages,pct,now())
  on conflict(user_id,item_id) do update set last_page=excluded.last_page,total_pages=excluded.total_pages,progress_pct=excluded.progress_pct,last_opened_at=now();
  update public.library_items set page_count=coalesce(page_count,p_total_pages) where id=p_item_id;
  return jsonb_build_object('ok',true,'progress_pct',pct);
end $$;
grant execute on function public.library_progress_save(uuid,integer,integer) to authenticated;

create or replace function public.library_admin_bootstrap()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare cats jsonb; items jsonb;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then raise exception 'Admin only'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb) into cats from (
    select c.*, (select count(*) from public.library_items i where i.category_id=c.id) item_count from public.library_categories c
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into items from (
    select i.*,c.name category_name,c.code category_code from public.library_items i left join public.library_categories c on c.id=i.category_id
  ) x;
  return jsonb_build_object('ok',true,'categories',cats,'items',items);
end $$;
grant execute on function public.library_admin_bootstrap() to authenticated;

create or replace function public.library_admin_save_category(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  begin v_id:=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
  if coalesce(trim(p_payload->>'code'),'')='' or coalesce(trim(p_payload->>'name'),'')='' then return jsonb_build_object('ok',false,'message','กรุณากรอกรหัสและชื่อหมวด'); end if;
  if v_id is null then
    insert into public.library_categories(code,name,description,icon,sort_order) values(upper(trim(p_payload->>'code')),trim(p_payload->>'name'),nullif(trim(coalesce(p_payload->>'description','')),''),nullif(trim(coalesce(p_payload->>'icon','')),''),coalesce((p_payload->>'sort_order')::int,100)) returning id into v_id;
  else
    update public.library_categories set code=upper(trim(p_payload->>'code')),name=trim(p_payload->>'name'),description=nullif(trim(coalesce(p_payload->>'description','')),''),icon=nullif(trim(coalesce(p_payload->>'icon','')),''),sort_order=coalesce((p_payload->>'sort_order')::int,sort_order),updated_at=now() where id=v_id;
  end if;
  return jsonb_build_object('ok',true,'id',v_id);
exception when unique_violation then return jsonb_build_object('ok',false,'message','category_code ซ้ำ');
end $$;
grant execute on function public.library_admin_save_category(jsonb) to authenticated;

create or replace function public.library_admin_save_item(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  begin v_id:=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
  if coalesce(trim(p_payload->>'title'),'')='' or coalesce(trim(p_payload->>'file_path'),'')='' then return jsonb_build_object('ok',false,'message','กรุณาระบุชื่อและไฟล์ PDF'); end if;
  if v_id is null then
    insert into public.library_items(category_id,title,subtitle,author,publisher,publication_year,isbn,description,tags,file_path,cover_path,audience,status,is_new,new_until,sort_order,created_by)
    values(nullif(p_payload->>'category_id','')::uuid,trim(p_payload->>'title'),nullif(trim(coalesce(p_payload->>'subtitle','')),''),nullif(trim(coalesce(p_payload->>'author','')),''),nullif(trim(coalesce(p_payload->>'publisher','')),''),nullif(p_payload->>'publication_year','')::int,nullif(trim(coalesce(p_payload->>'isbn','')),''),nullif(trim(coalesce(p_payload->>'description','')),''),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'tags','[]'::jsonb))),'{}'::text[]),p_payload->>'file_path',nullif(p_payload->>'cover_path',''),coalesce(nullif(p_payload->>'audience',''),'all'),coalesce(nullif(p_payload->>'status',''),'published'),coalesce((p_payload->>'is_new')::boolean,false),nullif(p_payload->>'new_until','')::date,coalesce((p_payload->>'sort_order')::int,100),auth.uid()) returning id into v_id;
  else
    update public.library_items set category_id=nullif(p_payload->>'category_id','')::uuid,title=trim(p_payload->>'title'),subtitle=nullif(trim(coalesce(p_payload->>'subtitle','')),''),author=nullif(trim(coalesce(p_payload->>'author','')),''),publisher=nullif(trim(coalesce(p_payload->>'publisher','')),''),publication_year=nullif(p_payload->>'publication_year','')::int,isbn=nullif(trim(coalesce(p_payload->>'isbn','')),''),description=nullif(trim(coalesce(p_payload->>'description','')),''),tags=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'tags','[]'::jsonb))),'{}'::text[]),file_path=p_payload->>'file_path',cover_path=nullif(p_payload->>'cover_path',''),audience=coalesce(nullif(p_payload->>'audience',''),'all'),status=coalesce(nullif(p_payload->>'status',''),'published'),is_new=coalesce((p_payload->>'is_new')::boolean,false),new_until=nullif(p_payload->>'new_until','')::date,sort_order=coalesce((p_payload->>'sort_order')::int,sort_order),updated_at=now() where id=v_id;
  end if;
  return jsonb_build_object('ok',true,'id',v_id);
exception when others then return jsonb_build_object('ok',false,'message',SQLERRM,'sqlstate',SQLSTATE);
end $$;
grant execute on function public.library_admin_save_item(jsonb) to authenticated;

create or replace function public.library_admin_bulk_upsert(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; cid uuid; n integer:=0;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    cid:=null;
    if trim(coalesce(r->>'category_code',''))<>'' then select id into cid from public.library_categories where upper(code)=upper(trim(r->>'category_code')) limit 1; end if;
    insert into public.library_items(category_id,title,subtitle,author,publisher,publication_year,isbn,description,tags,file_path,cover_path,audience,status,is_new,new_until,sort_order,created_by)
    values(cid,trim(r->>'title'),nullif(trim(coalesce(r->>'subtitle','')),''),nullif(trim(coalesce(r->>'author','')),''),nullif(trim(coalesce(r->>'publisher','')),''),nullif(r->>'publication_year','')::int,nullif(trim(coalesce(r->>'isbn','')),''),nullif(trim(coalesce(r->>'description','')),''),coalesce(array(select jsonb_array_elements_text(coalesce(r->'tags','[]'::jsonb))),'{}'::text[]),r->>'file_path',nullif(r->>'cover_path',''),coalesce(nullif(r->>'audience',''),'all'),coalesce(nullif(r->>'status',''),'published'),coalesce((r->>'is_new')::boolean,false),nullif(r->>'new_until','')::date,coalesce((r->>'sort_order')::int,100),auth.uid());
    n:=n+1;
  end loop;
  return jsonb_build_object('ok',true,'inserted',n);
exception when others then return jsonb_build_object('ok',false,'message',SQLERRM,'sqlstate',SQLSTATE);
end $$;
grant execute on function public.library_admin_bulk_upsert(jsonb) to authenticated;

-- Browser-safe open authorization for the no-TypeScript edition.
-- Returns the private storage path only after role/audience/status checks.
create or replace function public.library_open_item(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public
as $$
declare
  r text;
  i public.library_items%rowtype;
  display text;
  code text;
  lp integer:=1;
begin
  if auth.uid() is null then
    return jsonb_build_object('ok',false,'message','Sign in required');
  end if;

  r:=public.library_role_for_user(auth.uid());
  if r='none' then
    return jsonb_build_object('ok',false,'message','No library access');
  end if;

  select * into i from public.library_items where id=p_item_id;
  if not found then
    return jsonb_build_object('ok',false,'message','Book not found');
  end if;

  if r<>'admin' and i.status<>'published' then
    return jsonb_build_object('ok',false,'message','Book is not published');
  end if;

  if r='student' and i.audience='staff' then
    return jsonb_build_object('ok',false,'message','Staff only');
  end if;

  if r='student' then
    select coalesce(nickname,display_name,first_name,'Student'),student_code
    into display,code
    from public.os_students
    where auth_user_id=auth.uid()
    order by created_at desc
    limit 1;
  else
    display:=coalesce(auth.jwt()->>'email','AreWarin Staff');
  end if;

  select coalesce(last_page,1)
  into lp
  from public.library_reading_progress
  where user_id=auth.uid() and item_id=p_item_id;

  insert into public.library_access_log(user_id,item_id,role,action)
  values(auth.uid(),p_item_id,r,'open');

  return jsonb_build_object(
    'ok',true,
    'role',r,
    'file_path',i.file_path,
    'title',i.title,
    'last_page',coalesce(lp,1),
    'watermark',trim(concat_ws(' · ',display,code))
  );
end $$;

grant execute on function public.library_open_item(uuid) to authenticated;

-- Helper used by the Storage RLS SELECT policy.
create or replace function public.library_can_read_path(p_user_id uuid,p_name text)
returns boolean
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  r text;
begin
  r:=public.library_role_for_user(p_user_id);

  if r='none' then
    return false;
  end if;

  return exists(
    select 1
    from public.library_items i
    where i.file_path=p_name
      and (
        r='admin'
        or (
          i.status='published'
          and (
            r='staff'
            or (r='student' and i.audience in ('all','students'))
          )
        )
      )
  );
end $$;

revoke all on function public.library_can_read_path(uuid,text) from public;
grant execute on function public.library_can_read_path(uuid,text) to authenticated;

-- RLS: browser reads through RPCs; storage files are more tightly controlled.
alter table public.library_categories enable row level security;
alter table public.library_items enable row level security;
alter table public.library_favorites enable row level security;
alter table public.library_reading_progress enable row level security;
alter table public.library_access_log enable row level security;

-- Storage buckets
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('library-covers','library-covers',true,10485760,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=true;
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('library-books','library-books',false,314572800,array['application/pdf'])
on conflict(id) do update set public=false;

-- Cover viewing is public; writes are admin-only.
drop policy if exists "library covers public read" on storage.objects;
create policy "library covers public read" on storage.objects for select to anon,authenticated using(bucket_id='library-covers');
drop policy if exists "library covers admin insert" on storage.objects;
create policy "library covers admin insert" on storage.objects for insert to authenticated with check(bucket_id='library-covers' and public.library_role_for_user(auth.uid())='admin');
drop policy if exists "library covers admin update" on storage.objects;
create policy "library covers admin update" on storage.objects for update to authenticated using(bucket_id='library-covers' and public.library_role_for_user(auth.uid())='admin') with check(bucket_id='library-covers' and public.library_role_for_user(auth.uid())='admin');
drop policy if exists "library covers admin delete" on storage.objects;
create policy "library covers admin delete" on storage.objects for delete to authenticated using(bucket_id='library-covers' and public.library_role_for_user(auth.uid())='admin');

-- No-TypeScript edition:
-- eligible signed-in users may SELECT only storage objects linked to books they are allowed to read.
-- The browser then creates a short-lived signed URL (90 seconds).
drop policy if exists "library books permitted read" on storage.objects;
create policy "library books permitted read"
on storage.objects
for select
to authenticated
using(
  bucket_id='library-books'
  and public.library_can_read_path(auth.uid(),name)
);

drop policy if exists "library books admin insert" on storage.objects;
create policy "library books admin insert" on storage.objects for insert to authenticated with check(bucket_id='library-books' and public.library_role_for_user(auth.uid())='admin');
drop policy if exists "library books admin update" on storage.objects;
create policy "library books admin update" on storage.objects for update to authenticated using(bucket_id='library-books' and public.library_role_for_user(auth.uid())='admin') with check(bucket_id='library-books' and public.library_role_for_user(auth.uid())='admin');
drop policy if exists "library books admin delete" on storage.objects;
create policy "library books admin delete" on storage.objects for delete to authenticated using(bucket_id='library-books' and public.library_role_for_user(auth.uid())='admin');

notify pgrst,'reload schema';
commit;

select jsonb_pretty(jsonb_build_object(
 'ok',true,
 'categories',to_regclass('public.library_categories') is not null,
 'items',to_regclass('public.library_items') is not null,
 'whoami',to_regprocedure('public.library_whoami()') is not null,
 'catalog',to_regprocedure('public.library_catalog(text,uuid,boolean)') is not null,
 'open_item',to_regprocedure('public.library_open_item(uuid)') is not null,
 'path_policy_helper',to_regprocedure('public.library_can_read_path(uuid,text)') is not null
)) as arewarin_library_v1_status;


-- ============================================================================
-- V2 COMPLETE UPGRADE STARTS HERE
-- ============================================================================

begin;

create table if not exists public.library_settings(
  id smallint primary key default 1 check(id=1),
  library_name text not null default 'AreWarin Library',
  new_days integer not null default 30 check(new_days between 1 and 365),
  max_active_devices integer not null default 2 check(max_active_devices between 1 and 20),
  device_window_minutes integer not null default 45 check(device_window_minutes between 5 and 1440),
  signed_url_seconds integer not null default 90 check(signed_url_seconds between 30 and 3600),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.library_settings(id) values(1) on conflict(id) do nothing;

alter table public.library_categories add column if not exists parent_id uuid references public.library_categories(id) on delete set null;

alter table public.library_items
  add column if not exists edition text,
  add column if not exists language text not null default 'th',
  add column if not exists file_sha256 text,
  add column if not exists file_size bigint,
  add column if not exists featured boolean not null default false,
  add column if not exists recommended boolean not null default false,
  add column if not exists archived_at timestamptz,
  add column if not exists deleted_at timestamptz;

-- Expand legacy status constraint for hidden/soft archive workflows.
do $$
declare r record;
begin
  for r in
    select conname from pg_constraint
    where conrelid='public.library_items'::regclass and contype='c'
      and pg_get_constraintdef(oid) ilike '%status%'
  loop execute format('alter table public.library_items drop constraint if exists %I',r.conname); end loop;
  alter table public.library_items add constraint library_items_status_check
    check(status in ('draft','published','hidden','archived'));
exception when duplicate_object then null;
end $$;

create index if not exists library_items_isbn_idx on public.library_items(isbn) where isbn is not null;
create index if not exists library_items_sha_idx on public.library_items(file_sha256) where file_sha256 is not null;
create index if not exists library_items_featured_idx on public.library_items(featured,recommended,status) where deleted_at is null;

create table if not exists public.library_collections(
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text,
  cover_path text,
  featured boolean not null default false,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.library_collection_items(
  collection_id uuid not null references public.library_collections(id) on delete cascade,
  item_id uuid not null references public.library_items(id) on delete cascade,
  sort_order integer not null default 100,
  primary key(collection_id,item_id)
);
create table if not exists public.library_item_courses(
  item_id uuid not null references public.library_items(id) on delete cascade,
  course_id uuid not null references public.courses(id) on delete cascade,
  primary key(item_id,course_id)
);
create table if not exists public.library_pins(
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.library_items(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id,item_id)
);
alter table public.library_reading_progress add column if not exists completed boolean not null default false;

create table if not exists public.library_bookmarks(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.library_items(id) on delete cascade,
  page_no integer not null check(page_no>0),
  label text,
  created_at timestamptz not null default now(),
  unique(user_id,item_id,page_no)
);
create table if not exists public.library_notes(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_id uuid not null references public.library_items(id) on delete cascade,
  page_no integer not null check(page_no>0),
  note text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.library_book_requests(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  author text,
  reason text,
  status text not null default 'pending' check(status in ('pending','approved','declined','added')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.library_new_seen(
  user_id uuid primary key references auth.users(id) on delete cascade,
  seen_at timestamptz not null default now()
);
create table if not exists public.library_sessions(
  user_id uuid not null references auth.users(id) on delete cascade,
  session_key text not null,
  device_label text,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key(user_id,session_key)
);
alter table public.library_access_log add column if not exists metadata jsonb not null default '{}'::jsonb;
create table if not exists public.library_audit_log(
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists library_collection_items_item_idx on public.library_collection_items(item_id);
create index if not exists library_item_courses_course_idx on public.library_item_courses(course_id,item_id);
create index if not exists library_progress_recent_idx on public.library_reading_progress(user_id,last_opened_at desc);
create index if not exists library_access_recent_idx on public.library_access_log(item_id,created_at desc);
create index if not exists library_requests_status_idx on public.library_book_requests(status,created_at desc);
create index if not exists library_sessions_recent_idx on public.library_sessions(user_id,last_seen_at desc);

-- RLS: most access is through narrow SECURITY DEFINER RPCs.
do $$ declare t text; begin
  foreach t in array array['library_settings','library_collections','library_collection_items','library_item_courses','library_pins','library_bookmarks','library_notes','library_book_requests','library_new_seen','library_sessions','library_audit_log'] loop
    execute format('alter table public.%I enable row level security',t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- V2 identity / access helpers
-- ---------------------------------------------------------------------------
create or replace function public.library_student_id_for_user(p_uid uuid)
returns uuid language plpgsql stable security definer set search_path=public as $$
declare v uuid;
begin
  if p_uid is null then return null; end if;
  select id into v from public.os_students where auth_user_id=p_uid order by created_at desc limit 1;
  return v;
end $$;
grant execute on function public.library_student_id_for_user(uuid) to authenticated;

create or replace function public.library_user_has_course(p_uid uuid,p_course_id uuid)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare sid uuid; ok boolean:=false;
begin
  if public.library_role_for_user(p_uid) in ('admin','staff') then return true; end if;
  sid:=public.library_student_id_for_user(p_uid);
  if sid is null or p_course_id is null then return false; end if;
  if to_regclass('public.os_student_course_enrollments') is not null then
    execute 'select exists(select 1 from public.os_student_course_enrollments where student_id=$1 and course_id=$2)'
      into ok using sid,p_course_id;
  end if;
  return coalesce(ok,false);
end $$;
grant execute on function public.library_user_has_course(uuid,uuid) to authenticated;

create or replace function public.library_user_can_access_item(p_uid uuid,p_item_id uuid)
returns boolean language plpgsql stable security definer set search_path=public as $$
declare r text; i public.library_items%rowtype; gated boolean; eligible boolean;
begin
  r:=public.library_role_for_user(p_uid);
  if r='none' then return false; end if;
  select * into i from public.library_items where id=p_item_id and deleted_at is null;
  if not found then return false; end if;
  if r='admin' then return true; end if;
  if i.status<>'published' then return false; end if;
  if r='student' and i.audience='staff' then return false; end if;
  if r='staff' then return true; end if;
  select exists(select 1 from public.library_item_courses where item_id=i.id) into gated;
  if not gated then return true; end if;
  select exists(
    select 1 from public.library_item_courses ic
    where ic.item_id=i.id and public.library_user_has_course(p_uid,ic.course_id)
  ) into eligible;
  return coalesce(eligible,false);
end $$;
grant execute on function public.library_user_can_access_item(uuid,uuid) to authenticated;

create or replace function public.library_session_touch(p_session_key text,p_device_label text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r text; max_devices int; win int; active_count int;
begin
  if auth.uid() is null then return jsonb_build_object('ok',false,'message','Sign in required'); end if;
  r:=public.library_role_for_user(auth.uid());
  if r='none' then return jsonb_build_object('ok',false,'message','No library access'); end if;
  select max_active_devices,device_window_minutes into max_devices,win from public.library_settings where id=1;
  max_devices:=coalesce(max_devices,2); win:=coalesce(win,45);
  delete from public.library_sessions where last_seen_at < now()-make_interval(mins=>greatest(win,5)*4);
  insert into public.library_sessions(user_id,session_key,device_label)
  values(auth.uid(),left(coalesce(p_session_key,''),120),left(coalesce(p_device_label,''),200))
  on conflict(user_id,session_key) do update set device_label=excluded.device_label,last_seen_at=now();
  if r='student' then
    select count(*) into active_count from public.library_sessions
    where user_id=auth.uid() and last_seen_at>=now()-make_interval(mins=>greatest(win,5));
    if active_count>max_devices then
      delete from public.library_sessions where user_id=auth.uid() and session_key=left(coalesce(p_session_key,''),120);
      return jsonb_build_object('ok',false,'code','DEVICE_LIMIT','message','บัญชีนี้เปิดห้องสมุดพร้อมกันเกินจำนวนอุปกรณ์ที่กำหนด','active_devices',active_count-1,'limit',max_devices);
    end if;
  end if;
  return jsonb_build_object('ok',true,'role',r,'max_active_devices',max_devices,'device_window_minutes',win);
end $$;
grant execute on function public.library_session_touch(text,text) to authenticated;

create or replace function public.library_whoami()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare r text; n text; code text; sid uuid; sett jsonb;
begin
  if auth.uid() is null then return jsonb_build_object('ok',false,'message','Not signed in'); end if;
  r:=public.library_role_for_user(auth.uid());
  if r='none' then return jsonb_build_object('ok',false,'message','บัญชีนี้ยังไม่เชื่อมกับ AreWarin Student/Tutor/Manager'); end if;
  if r='student' then
    select id,coalesce(nickname,display_name,first_name,'นักเรียน'),student_code into sid,n,code
    from public.os_students where auth_user_id=auth.uid() order by created_at desc limit 1;
  else n:=coalesce(auth.jwt()->>'email','AreWarin Staff'); end if;
  select to_jsonb(s) into sett from public.library_settings s where id=1;
  return jsonb_build_object('ok',true,'role',r,'display_name',n,'student_code',code,'student_id',sid,'user_id',auth.uid(),'settings',coalesce(sett,'{}'::jsonb));
end $$;
grant execute on function public.library_whoami() to authenticated;

-- ---------------------------------------------------------------------------
-- Home/catalog payload
-- ---------------------------------------------------------------------------
create or replace function public.library_home()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare
  r text; v_items jsonb; v_cats jsonb; v_cols jsonb; v_seen_at timestamptz; v_unseen int:=0; nd int:=30;
begin
  if auth.uid() is null then raise exception 'Sign in required'; end if;
  r:=public.library_role_for_user(auth.uid()); if r='none' then raise exception 'No library access'; end if;
  select new_days into nd from public.library_settings where id=1; nd:=coalesce(nd,30);
  select seen_at into v_seen_at from public.library_new_seen where user_id=auth.uid();

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.title),'[]'::jsonb) into v_items
  from (
    select i.id,i.title,i.subtitle,i.author,i.publisher,i.publication_year,i.edition,i.language,i.isbn,i.description,i.tags,
      i.cover_path,i.audience,i.status,i.is_new,i.new_until,i.featured,i.recommended,i.page_count,i.sort_order,i.created_at,
      c.id category_id,c.name category_name,c.icon category_icon,c.parent_id category_parent_id,
      ((i.is_new and (i.new_until is null or i.new_until>=current_date)) or i.created_at>=now()-make_interval(days=>nd)) as computed_new,
      coalesce(p.last_page,1) last_page,coalesce(p.total_pages,i.page_count) total_pages,coalesce(p.progress_pct,0) progress_pct,
      coalesce(p.completed,false) completed,p.last_opened_at,
      (f.user_id is not null) favorite,(pn.user_id is not null) pinned,
      (select count(*) from public.library_access_log al where al.item_id=i.id and al.action='open') view_count,
      exists(select 1 from public.library_bookmarks bm where bm.user_id=auth.uid() and bm.item_id=i.id) has_bookmark,
      exists(select 1 from public.library_item_courses ic where ic.item_id=i.id and public.library_user_has_course(auth.uid(),ic.course_id)) for_my_course,
      coalesce((select jsonb_agg(jsonb_build_object('id',co.id,'code',co.code,'name',co.name) order by co.sort_order,co.name)
                from public.library_collection_items ci join public.library_collections co on co.id=ci.collection_id
                where ci.item_id=i.id and co.active=true),'[]'::jsonb) collections,
      coalesce((select jsonb_agg(jsonb_build_object('id',cr.id,'name',cr.name) order by cr.name)
                from public.library_item_courses ic join public.courses cr on cr.id=ic.course_id where ic.item_id=i.id),'[]'::jsonb) courses
    from public.library_items i
    left join public.library_categories c on c.id=i.category_id
    left join public.library_reading_progress p on p.item_id=i.id and p.user_id=auth.uid()
    left join public.library_favorites f on f.item_id=i.id and f.user_id=auth.uid()
    left join public.library_pins pn on pn.item_id=i.id and pn.user_id=auth.uid()
    where i.deleted_at is null and public.library_user_can_access_item(auth.uid(),i.id)
      and (r='admin' or i.status='published')
  ) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb) into v_cats
  from (select id,code,name,description,icon,parent_id,sort_order from public.library_categories where active=true) x;

  select coalesce(jsonb_agg(to_jsonb(x) order by x.featured desc,x.sort_order,x.name),'[]'::jsonb) into v_cols
  from (
    select co.id,co.code,co.name,co.description,co.cover_path,co.featured,co.sort_order,
      (select count(*) from public.library_collection_items ci join public.library_items i on i.id=ci.item_id
       where ci.collection_id=co.id and i.deleted_at is null and public.library_user_can_access_item(auth.uid(),i.id)) item_count
    from public.library_collections co where co.active=true
  ) x;

  select count(*) into v_unseen from public.library_items i
  where i.deleted_at is null and i.status='published' and public.library_user_can_access_item(auth.uid(),i.id)
    and ((i.is_new and (i.new_until is null or i.new_until>=current_date)) or i.created_at>=now()-make_interval(days=>nd))
    and (v_seen_at is null or i.created_at>v_seen_at);

  return jsonb_build_object('ok',true,'items',v_items,'categories',v_cats,'collections',v_cols,'unseen_new',v_unseen);
end $$;
grant execute on function public.library_home() to authenticated;

create or replace function public.library_mark_new_seen()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  insert into public.library_new_seen(user_id,seen_at) values(auth.uid(),now())
  on conflict(user_id) do update set seen_at=now();
  return jsonb_build_object('ok',true);
end $$;
grant execute on function public.library_mark_new_seen() to authenticated;

-- ---------------------------------------------------------------------------
-- Personal shelf / reader actions
-- ---------------------------------------------------------------------------
create or replace function public.library_toggle_favorite(p_item_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  if exists(select 1 from public.library_favorites where user_id=auth.uid() and item_id=p_item_id) then
    delete from public.library_favorites where user_id=auth.uid() and item_id=p_item_id;
    return jsonb_build_object('ok',true,'favorite',false);
  end if;
  insert into public.library_favorites(user_id,item_id) values(auth.uid(),p_item_id) on conflict do nothing;
  return jsonb_build_object('ok',true,'favorite',true);
end $$;
grant execute on function public.library_toggle_favorite(uuid) to authenticated;

create or replace function public.library_toggle_pin(p_item_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  if exists(select 1 from public.library_pins where user_id=auth.uid() and item_id=p_item_id) then
    delete from public.library_pins where user_id=auth.uid() and item_id=p_item_id;
    return jsonb_build_object('ok',true,'pinned',false);
  end if;
  insert into public.library_pins(user_id,item_id) values(auth.uid(),p_item_id) on conflict do nothing;
  return jsonb_build_object('ok',true,'pinned',true);
end $$;
grant execute on function public.library_toggle_pin(uuid) to authenticated;

create or replace function public.library_progress_save(p_item_id uuid,p_last_page integer,p_total_pages integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare pct numeric(6,2); done boolean;
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  pct:=case when coalesce(p_total_pages,0)>0 then least(100,round((greatest(p_last_page,1)::numeric/p_total_pages::numeric)*100,2)) else 0 end;
  done:=pct>=95;
  insert into public.library_reading_progress(user_id,item_id,last_page,total_pages,progress_pct,completed,last_opened_at)
  values(auth.uid(),p_item_id,greatest(p_last_page,1),p_total_pages,pct,done,now())
  on conflict(user_id,item_id) do update set last_page=excluded.last_page,total_pages=excluded.total_pages,progress_pct=excluded.progress_pct,completed=excluded.completed,last_opened_at=now();
  update public.library_items set page_count=coalesce(page_count,p_total_pages) where id=p_item_id;
  return jsonb_build_object('ok',true,'progress_pct',pct,'completed',done);
end $$;
grant execute on function public.library_progress_save(uuid,integer,integer) to authenticated;

create or replace function public.library_toggle_bookmark(p_item_id uuid,p_page integer,p_label text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  select id into v_id from public.library_bookmarks where user_id=auth.uid() and item_id=p_item_id and page_no=p_page;
  if v_id is not null then delete from public.library_bookmarks where id=v_id; return jsonb_build_object('ok',true,'bookmarked',false); end if;
  insert into public.library_bookmarks(user_id,item_id,page_no,label) values(auth.uid(),p_item_id,greatest(p_page,1),nullif(trim(coalesce(p_label,'')),''));
  return jsonb_build_object('ok',true,'bookmarked',true);
end $$;
grant execute on function public.library_toggle_bookmark(uuid,integer,text) to authenticated;

create or replace function public.library_note_save(p_item_id uuid,p_page integer,p_note text,p_note_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid:=p_note_id;
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  if trim(coalesce(p_note,''))='' then return jsonb_build_object('ok',false,'message','Note is empty'); end if;
  if v_id is null then
    insert into public.library_notes(user_id,item_id,page_no,note) values(auth.uid(),p_item_id,greatest(p_page,1),left(trim(p_note),5000)) returning id into v_id;
  else
    update public.library_notes set note=left(trim(p_note),5000),page_no=greatest(p_page,1),updated_at=now() where id=v_id and user_id=auth.uid() and item_id=p_item_id;
  end if;
  return jsonb_build_object('ok',true,'id',v_id);
end $$;
grant execute on function public.library_note_save(uuid,integer,text,uuid) to authenticated;

create or replace function public.library_note_delete(p_note_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  delete from public.library_notes where id=p_note_id and user_id=auth.uid();
  return jsonb_build_object('ok',true);
end $$;
grant execute on function public.library_note_delete(uuid) to authenticated;

create or replace function public.library_reader_state(p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare b jsonb;n jsonb;
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.page_no),'[]'::jsonb) into b from (select id,page_no,label,created_at from public.library_bookmarks where user_id=auth.uid() and item_id=p_item_id) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.page_no,x.created_at),'[]'::jsonb) into n from (select id,page_no,note,created_at,updated_at from public.library_notes where user_id=auth.uid() and item_id=p_item_id) x;
  return jsonb_build_object('ok',true,'bookmarks',b,'notes',n);
end $$;
grant execute on function public.library_reader_state(uuid) to authenticated;

create or replace function public.library_request_book(p_title text,p_author text default null,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v uuid;
begin
  if public.library_role_for_user(auth.uid())='none' then return jsonb_build_object('ok',false,'message','No access'); end if;
  if trim(coalesce(p_title,''))='' then return jsonb_build_object('ok',false,'message','กรุณาระบุชื่อหนังสือ'); end if;
  insert into public.library_book_requests(user_id,title,author,reason) values(auth.uid(),left(trim(p_title),300),left(trim(coalesce(p_author,'')),200),left(trim(coalesce(p_reason,'')),1000)) returning id into v;
  return jsonb_build_object('ok',true,'id',v);
end $$;
grant execute on function public.library_request_book(text,text,text) to authenticated;

create or replace function public.library_item_detail(p_item_id uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare v_item jsonb; v_related jsonb; v_courses jsonb; v_cols jsonb;
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  select to_jsonb(x) into v_item from (
    select i.*,c.name category_name,c.icon category_icon,
      coalesce(p.progress_pct,0) progress_pct,coalesce(p.last_page,1) last_page,(f.user_id is not null) favorite,(pn.user_id is not null) pinned,
      (select count(*) from public.library_access_log al where al.item_id=i.id and al.action='open') view_count
    from public.library_items i left join public.library_categories c on c.id=i.category_id
    left join public.library_reading_progress p on p.item_id=i.id and p.user_id=auth.uid()
    left join public.library_favorites f on f.item_id=i.id and f.user_id=auth.uid()
    left join public.library_pins pn on pn.item_id=i.id and pn.user_id=auth.uid()
    where i.id=p_item_id
  ) x;
  select coalesce(jsonb_agg(to_jsonb(q)),'[]'::jsonb) into v_related from (
    select i.id,i.title,i.subtitle,i.author,i.cover_path,c.name category_name,
      (select count(*) from public.library_access_log al where al.item_id=i.id and al.action='open') view_count
    from public.library_items i join public.library_items base on base.id=p_item_id
    left join public.library_categories c on c.id=i.category_id
    where i.id<>p_item_id and i.deleted_at is null and public.library_user_can_access_item(auth.uid(),i.id)
      and (i.category_id=base.category_id or i.tags && base.tags)
    order by (i.category_id=base.category_id) desc, view_count desc,i.created_at desc limit 8
  ) q;
  select coalesce(jsonb_agg(jsonb_build_object('id',cr.id,'name',cr.name) order by cr.name),'[]'::jsonb) into v_courses
  from public.library_item_courses ic join public.courses cr on cr.id=ic.course_id where ic.item_id=p_item_id;
  select coalesce(jsonb_agg(jsonb_build_object('id',co.id,'name',co.name,'code',co.code) order by co.sort_order,co.name),'[]'::jsonb) into v_cols
  from public.library_collection_items ci join public.library_collections co on co.id=ci.collection_id where ci.item_id=p_item_id;
  return jsonb_build_object('ok',true,'item',v_item,'related',v_related,'courses',v_courses,'collections',v_cols);
end $$;
grant execute on function public.library_item_detail(uuid) to authenticated;

create or replace function public.library_open_item(p_item_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare i public.library_items%rowtype; display text; code text; lp integer:=1; sec int:=90;
begin
  if not public.library_user_can_access_item(auth.uid(),p_item_id) then return jsonb_build_object('ok',false,'message','No access'); end if;
  select * into i from public.library_items where id=p_item_id;
  if public.library_role_for_user(auth.uid())='student' then
    select coalesce(nickname,display_name,first_name,'Student'),student_code into display,code from public.os_students where auth_user_id=auth.uid() order by created_at desc limit 1;
  else display:=coalesce(auth.jwt()->>'email','AreWarin Staff'); end if;
  select coalesce(last_page,1) into lp from public.library_reading_progress where user_id=auth.uid() and item_id=p_item_id;
  select signed_url_seconds into sec from public.library_settings where id=1;
  insert into public.library_access_log(user_id,item_id,role,action,metadata) values(auth.uid(),p_item_id,public.library_role_for_user(auth.uid()),'open',jsonb_build_object('source','library_v2'));
  return jsonb_build_object('ok',true,'file_path',i.file_path,'title',i.title,'last_page',coalesce(lp,1),'watermark',trim(concat_ws(' · ',display,code)),'signed_url_seconds',coalesce(sec,90));
end $$;
grant execute on function public.library_open_item(uuid) to authenticated;

create or replace function public.library_can_read_path(p_user_id uuid,p_name text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.library_items i where i.file_path=p_name and public.library_user_can_access_item(p_user_id,i.id))
$$;
grant execute on function public.library_can_read_path(uuid,text) to authenticated;

-- ---------------------------------------------------------------------------
-- Admin Studio
-- ---------------------------------------------------------------------------
create or replace function public.library_admin_bootstrap_v2()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare cats jsonb; items jsonb; cols jsonb; crs jsonb; reqs jsonb; aud jsonb; stats jsonb; sett jsonb;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then raise exception 'Admin only'; end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb) into cats from (
    select c.*,(select count(*) from public.library_items i where i.category_id=c.id and i.deleted_at is null) item_count,
      p.name parent_name from public.library_categories c left join public.library_categories p on p.id=c.parent_id
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.deleted_at nulls first,x.updated_at desc),'[]'::jsonb) into items from (
    select i.*,c.name category_name,c.code category_code,
      coalesce((select jsonb_agg(ic.course_id order by ic.course_id) from public.library_item_courses ic where ic.item_id=i.id),'[]'::jsonb) course_ids,
      coalesce((select jsonb_agg(ci.collection_id order by ci.collection_id) from public.library_collection_items ci where ci.item_id=i.id),'[]'::jsonb) collection_ids,
      (select count(*) from public.library_access_log al where al.item_id=i.id and al.action='open') view_count
    from public.library_items i left join public.library_categories c on c.id=i.category_id
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb) into cols from (
    select co.*,(select count(*) from public.library_collection_items ci where ci.collection_id=co.id) item_count from public.library_collections co
  ) x;
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'active',c.active) order by c.active desc,c.name),'[]'::jsonb) into crs from public.courses c;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into reqs from (
    select r.*,coalesce(s.nickname,s.display_name,s.first_name,u.email) requester
    from public.library_book_requests r left join public.os_students s on s.auth_user_id=r.user_id left join auth.users u on u.id=r.user_id
    limit 300
  ) x;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into aud from (
    select id,actor_id,action,entity_type,entity_id,payload,created_at from public.library_audit_log order by created_at desc limit 300
  ) x;
  select jsonb_build_object(
    'total',count(*) filter(where deleted_at is null),
    'published',count(*) filter(where deleted_at is null and status='published'),
    'draft',count(*) filter(where deleted_at is null and status='draft'),
    'archived',count(*) filter(where deleted_at is null and status='archived'),
    'deleted',count(*) filter(where deleted_at is not null),
    'no_cover',count(*) filter(where deleted_at is null and nullif(cover_path,'') is null),
    'featured',count(*) filter(where deleted_at is null and featured=true),
    'new_count',count(*) filter(where deleted_at is null and ((is_new and (new_until is null or new_until>=current_date)) or created_at>=now()-interval '30 days')),
    'requests_pending',(select count(*) from public.library_book_requests where status='pending'),
    'reads_30d',(select count(*) from public.library_access_log where action='open' and created_at>=now()-interval '30 days')
  ) into stats from public.library_items;
  select to_jsonb(s) into sett from public.library_settings s where id=1;
  return jsonb_build_object('ok',true,'categories',cats,'items',items,'collections',cols,'courses',crs,'requests',reqs,'audit',aud,'stats',stats,'settings',sett);
end $$;
grant execute on function public.library_admin_bootstrap_v2() to authenticated;

create or replace function public.library_admin_duplicate_check(p_title text,p_isbn text default null,p_sha256 text default null,p_exclude_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare d jsonb;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'title',title,'isbn',isbn,'same_title',lower(trim(title))=lower(trim(coalesce(p_title,''))),'same_isbn',nullif(trim(coalesce(p_isbn,'')),'') is not null and isbn=p_isbn,'same_file',nullif(trim(coalesce(p_sha256,'')),'') is not null and file_sha256=p_sha256)),'[]'::jsonb)
  into d from public.library_items
  where (p_exclude_id is null or id<>p_exclude_id) and deleted_at is null and (
    lower(trim(title))=lower(trim(coalesce(p_title,''))) or
    (nullif(trim(coalesce(p_isbn,'')),'') is not null and isbn=trim(p_isbn)) or
    (nullif(trim(coalesce(p_sha256,'')),'') is not null and file_sha256=trim(p_sha256))
  );
  return jsonb_build_object('ok',true,'duplicates',d);
end $$;
grant execute on function public.library_admin_duplicate_check(text,text,text,uuid) to authenticated;

create or replace function public.library_admin_save_category(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_parent uuid;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  begin v_id:=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
  begin v_parent:=nullif(p_payload->>'parent_id','')::uuid; exception when others then v_parent:=null; end;
  if trim(coalesce(p_payload->>'code',''))='' or trim(coalesce(p_payload->>'name',''))='' then return jsonb_build_object('ok',false,'message','กรุณากรอกรหัสและชื่อหมวด'); end if;
  if v_id is null then
    insert into public.library_categories(code,name,description,icon,parent_id,sort_order,active) values(upper(trim(p_payload->>'code')),trim(p_payload->>'name'),nullif(trim(coalesce(p_payload->>'description','')),''),nullif(trim(coalesce(p_payload->>'icon','')),''),v_parent,coalesce((p_payload->>'sort_order')::int,100),coalesce((p_payload->>'active')::boolean,true)) returning id into v_id;
  else
    if v_parent=v_id then v_parent:=null; end if;
    update public.library_categories set code=upper(trim(p_payload->>'code')),name=trim(p_payload->>'name'),description=nullif(trim(coalesce(p_payload->>'description','')),''),icon=nullif(trim(coalesce(p_payload->>'icon','')),''),parent_id=v_parent,sort_order=coalesce((p_payload->>'sort_order')::int,sort_order),active=coalesce((p_payload->>'active')::boolean,active),updated_at=now() where id=v_id;
  end if;
  insert into public.library_audit_log(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'save_category','category',v_id::text,p_payload);
  return jsonb_build_object('ok',true,'id',v_id);
exception when unique_violation then return jsonb_build_object('ok',false,'message','category_code ซ้ำ');
end $$;
grant execute on function public.library_admin_save_category(jsonb) to authenticated;

create or replace function public.library_admin_save_collection(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  begin v_id:=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
  if trim(coalesce(p_payload->>'code',''))='' or trim(coalesce(p_payload->>'name',''))='' then return jsonb_build_object('ok',false,'message','กรุณากรอกรหัสและชื่อ Collection'); end if;
  if v_id is null then
    insert into public.library_collections(code,name,description,cover_path,featured,active,sort_order,created_by)
    values(upper(trim(p_payload->>'code')),trim(p_payload->>'name'),nullif(trim(coalesce(p_payload->>'description','')),''),nullif(trim(coalesce(p_payload->>'cover_path','')),''),coalesce((p_payload->>'featured')::boolean,false),coalesce((p_payload->>'active')::boolean,true),coalesce((p_payload->>'sort_order')::int,100),auth.uid()) returning id into v_id;
  else
    update public.library_collections set code=upper(trim(p_payload->>'code')),name=trim(p_payload->>'name'),description=nullif(trim(coalesce(p_payload->>'description','')),''),cover_path=nullif(trim(coalesce(p_payload->>'cover_path','')),''),featured=coalesce((p_payload->>'featured')::boolean,featured),active=coalesce((p_payload->>'active')::boolean,active),sort_order=coalesce((p_payload->>'sort_order')::int,sort_order),updated_at=now() where id=v_id;
  end if;
  insert into public.library_audit_log(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'save_collection','collection',v_id::text,p_payload);
  return jsonb_build_object('ok',true,'id',v_id);
exception when unique_violation then return jsonb_build_object('ok',false,'message','collection_code ซ้ำ');
end $$;
grant execute on function public.library_admin_save_collection(jsonb) to authenticated;

create or replace function public.library_admin_save_item(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_category uuid; v_course text; v_col text;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  begin v_id:=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
  begin v_category:=nullif(p_payload->>'category_id','')::uuid; exception when others then v_category:=null; end;
  if trim(coalesce(p_payload->>'title',''))='' or trim(coalesce(p_payload->>'file_path',''))='' then return jsonb_build_object('ok',false,'message','กรุณาระบุชื่อและไฟล์ PDF'); end if;
  if v_id is null then
    insert into public.library_items(category_id,title,subtitle,author,publisher,publication_year,edition,language,isbn,description,tags,file_path,cover_path,file_sha256,file_size,audience,status,is_new,new_until,featured,recommended,sort_order,created_by)
    values(v_category,trim(p_payload->>'title'),nullif(trim(coalesce(p_payload->>'subtitle','')),''),nullif(trim(coalesce(p_payload->>'author','')),''),nullif(trim(coalesce(p_payload->>'publisher','')),''),nullif(p_payload->>'publication_year','')::int,nullif(trim(coalesce(p_payload->>'edition','')),''),coalesce(nullif(p_payload->>'language',''),'th'),nullif(trim(coalesce(p_payload->>'isbn','')),''),nullif(trim(coalesce(p_payload->>'description','')),''),coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'tags','[]'::jsonb))),'{}'::text[]),p_payload->>'file_path',nullif(p_payload->>'cover_path',''),nullif(p_payload->>'file_sha256',''),nullif(p_payload->>'file_size','')::bigint,coalesce(nullif(p_payload->>'audience',''),'all'),coalesce(nullif(p_payload->>'status',''),'draft'),coalesce((p_payload->>'is_new')::boolean,false),nullif(p_payload->>'new_until','')::date,coalesce((p_payload->>'featured')::boolean,false),coalesce((p_payload->>'recommended')::boolean,false),coalesce((p_payload->>'sort_order')::int,100),auth.uid()) returning id into v_id;
  else
    update public.library_items set category_id=v_category,title=trim(p_payload->>'title'),subtitle=nullif(trim(coalesce(p_payload->>'subtitle','')),''),author=nullif(trim(coalesce(p_payload->>'author','')),''),publisher=nullif(trim(coalesce(p_payload->>'publisher','')),''),publication_year=nullif(p_payload->>'publication_year','')::int,edition=nullif(trim(coalesce(p_payload->>'edition','')),''),language=coalesce(nullif(p_payload->>'language',''),'th'),isbn=nullif(trim(coalesce(p_payload->>'isbn','')),''),description=nullif(trim(coalesce(p_payload->>'description','')),''),tags=coalesce(array(select jsonb_array_elements_text(coalesce(p_payload->'tags','[]'::jsonb))),'{}'::text[]),file_path=p_payload->>'file_path',cover_path=nullif(p_payload->>'cover_path',''),file_sha256=nullif(p_payload->>'file_sha256',''),file_size=nullif(p_payload->>'file_size','')::bigint,audience=coalesce(nullif(p_payload->>'audience',''),'all'),status=coalesce(nullif(p_payload->>'status',''),'draft'),is_new=coalesce((p_payload->>'is_new')::boolean,false),new_until=nullif(p_payload->>'new_until','')::date,featured=coalesce((p_payload->>'featured')::boolean,false),recommended=coalesce((p_payload->>'recommended')::boolean,false),sort_order=coalesce((p_payload->>'sort_order')::int,sort_order),archived_at=case when p_payload->>'status'='archived' then coalesce(archived_at,now()) else null end,deleted_at=null,updated_at=now() where id=v_id;
  end if;
  delete from public.library_item_courses where item_id=v_id;
  for v_course in select value#>>'{}' from jsonb_array_elements(coalesce(p_payload->'course_ids','[]'::jsonb)) loop
    begin insert into public.library_item_courses(item_id,course_id) values(v_id,v_course::uuid) on conflict do nothing; exception when others then null; end;
  end loop;
  delete from public.library_collection_items where item_id=v_id;
  for v_col in select value#>>'{}' from jsonb_array_elements(coalesce(p_payload->'collection_ids','[]'::jsonb)) loop
    begin insert into public.library_collection_items(collection_id,item_id) values(v_col::uuid,v_id) on conflict do nothing; exception when others then null; end;
  end loop;
  insert into public.library_audit_log(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'save_item','item',v_id::text,p_payload-'file_sha256');
  return jsonb_build_object('ok',true,'id',v_id);
exception when others then return jsonb_build_object('ok',false,'message',SQLERRM,'sqlstate',SQLSTATE);
end $$;
grant execute on function public.library_admin_save_item(jsonb) to authenticated;

create or replace function public.library_admin_bulk_action(p_item_ids jsonb,p_action text,p_value text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
declare ids uuid[]; n integer:=0;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  select coalesce(array_agg((value#>>'{}')::uuid),'{}'::uuid[]) into ids from jsonb_array_elements(coalesce(p_item_ids,'[]'::jsonb));
  if cardinality(ids)=0 then return jsonb_build_object('ok',false,'message','No items selected'); end if;
  case p_action
    when 'publish' then update public.library_items set status='published',deleted_at=null,updated_at=now() where id=any(ids);
    when 'draft' then update public.library_items set status='draft',updated_at=now() where id=any(ids);
    when 'archive' then update public.library_items set status='archived',archived_at=now(),updated_at=now() where id=any(ids);
    when 'feature_on' then update public.library_items set featured=true,updated_at=now() where id=any(ids);
    when 'feature_off' then update public.library_items set featured=false,updated_at=now() where id=any(ids);
    when 'new_on' then update public.library_items set is_new=true,new_until=coalesce(new_until,current_date+30),updated_at=now() where id=any(ids);
    when 'new_off' then update public.library_items set is_new=false,new_until=null,updated_at=now() where id=any(ids);
    when 'move_category' then update public.library_items set category_id=nullif(p_value,'')::uuid,updated_at=now() where id=any(ids);
    when 'soft_delete' then update public.library_items set deleted_at=now(),updated_at=now() where id=any(ids);
    when 'restore' then update public.library_items set deleted_at=null,status=case when status='archived' then 'draft' else status end,updated_at=now() where id=any(ids);
    else return jsonb_build_object('ok',false,'message','Unknown bulk action');
  end case;
  get diagnostics n=row_count;
  insert into public.library_audit_log(actor_id,action,entity_type,payload) values(auth.uid(),'bulk_'||p_action,'item',jsonb_build_object('ids',p_item_ids,'value',p_value,'affected',n));
  return jsonb_build_object('ok',true,'affected',n);
exception when others then return jsonb_build_object('ok',false,'message',SQLERRM,'sqlstate',SQLSTATE);
end $$;
grant execute on function public.library_admin_bulk_action(jsonb,text,text) to authenticated;

create or replace function public.library_admin_request_update(p_request_id uuid,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  if p_status not in ('pending','approved','declined','added') then return jsonb_build_object('ok',false,'message','Invalid status'); end if;
  update public.library_book_requests set status=p_status,admin_note=nullif(trim(coalesce(p_note,'')),''),updated_at=now() where id=p_request_id;
  insert into public.library_audit_log(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'request_'||p_status,'book_request',p_request_id::text,jsonb_build_object('note',p_note));
  return jsonb_build_object('ok',true);
end $$;
grant execute on function public.library_admin_request_update(uuid,text,text) to authenticated;

create or replace function public.library_admin_settings_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  update public.library_settings set library_name=coalesce(nullif(trim(p_payload->>'library_name'),''),library_name),new_days=greatest(1,least(365,coalesce((p_payload->>'new_days')::int,new_days))),max_active_devices=greatest(1,least(20,coalesce((p_payload->>'max_active_devices')::int,max_active_devices))),device_window_minutes=greatest(5,least(1440,coalesce((p_payload->>'device_window_minutes')::int,device_window_minutes))),signed_url_seconds=greatest(30,least(3600,coalesce((p_payload->>'signed_url_seconds')::int,signed_url_seconds))),updated_at=now() where id=1;
  insert into public.library_audit_log(actor_id,action,entity_type,entity_id,payload) values(auth.uid(),'save_settings','settings','1',p_payload);
  return jsonb_build_object('ok',true);
end $$;
grant execute on function public.library_admin_settings_save(jsonb) to authenticated;

create or replace function public.library_admin_bulk_upsert_v2(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb; cid uuid; v_id uuid; v_collection_code text; v_course_name text; results jsonb:='[]'::jsonb; idx int:=0; okn int:=0; errn int:=0;
begin
  if public.library_role_for_user(auth.uid())<>'admin' then return jsonb_build_object('ok',false,'message','Admin only'); end if;
  for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
    idx:=idx+1;
    begin
      if trim(coalesce(r->>'title',''))='' or trim(coalesce(r->>'file_path',''))='' then raise exception 'title/pdf required'; end if;
      cid:=null;
      if trim(coalesce(r->>'category_code',''))<>'' then select id into cid from public.library_categories where upper(code)=upper(trim(r->>'category_code')) limit 1; end if;
      insert into public.library_items(category_id,title,subtitle,author,publisher,publication_year,edition,language,isbn,description,tags,file_path,cover_path,file_sha256,file_size,audience,status,is_new,new_until,featured,recommended,sort_order,created_by)
      values(cid,trim(r->>'title'),nullif(trim(coalesce(r->>'subtitle','')),''),nullif(trim(coalesce(r->>'author','')),''),nullif(trim(coalesce(r->>'publisher','')),''),nullif(r->>'publication_year','')::int,nullif(trim(coalesce(r->>'edition','')),''),coalesce(nullif(r->>'language',''),'th'),nullif(trim(coalesce(r->>'isbn','')),''),nullif(trim(coalesce(r->>'description','')),''),coalesce(array(select jsonb_array_elements_text(coalesce(r->'tags','[]'::jsonb))),'{}'::text[]),r->>'file_path',nullif(r->>'cover_path',''),nullif(r->>'file_sha256',''),nullif(r->>'file_size','')::bigint,coalesce(nullif(r->>'audience',''),'all'),coalesce(nullif(r->>'status',''),'draft'),coalesce((r->>'is_new')::boolean,false),nullif(r->>'new_until','')::date,coalesce((r->>'featured')::boolean,false),coalesce((r->>'recommended')::boolean,false),coalesce((r->>'sort_order')::int,100),auth.uid()) returning id into v_id;
      for v_collection_code in select trim(value#>>'{}') from jsonb_array_elements(coalesce(r->'collection_codes','[]'::jsonb)) loop
        insert into public.library_collection_items(collection_id,item_id)
        select id,v_id from public.library_collections where upper(code)=upper(v_collection_code) on conflict do nothing;
      end loop;
      for v_course_name in select trim(value#>>'{}') from jsonb_array_elements(coalesce(r->'course_names','[]'::jsonb)) loop
        insert into public.library_item_courses(item_id,course_id)
        select v_id,c.id from public.courses c where lower(c.name)=lower(v_course_name) limit 1 on conflict do nothing;
      end loop;
      okn:=okn+1; results:=results||jsonb_build_array(jsonb_build_object('row',idx,'ok',true,'title',r->>'title','id',v_id));
    exception when others then
      errn:=errn+1; results:=results||jsonb_build_array(jsonb_build_object('row',idx,'ok',false,'title',r->>'title','message',SQLERRM));
    end;
  end loop;
  insert into public.library_audit_log(actor_id,action,entity_type,payload) values(auth.uid(),'excel_import','import',jsonb_build_object('success',okn,'errors',errn));
  return jsonb_build_object('ok',true,'success',okn,'errors',errn,'results',results);
end $$;
grant execute on function public.library_admin_bulk_upsert_v2(jsonb) to authenticated;

-- Storage read policy is explicitly rebuilt for V2 course-gated access.
drop policy if exists "library books permitted read" on storage.objects;
create policy "library books permitted read" on storage.objects for select to authenticated
using(bucket_id='library-books' and public.library_can_read_path(auth.uid(),name));

notify pgrst,'reload schema';
commit;

select jsonb_pretty(jsonb_build_object(
  'ok',true,
  'version','2.0-complete-no-ts',
  'home_rpc',to_regprocedure('public.library_home()') is not null,
  'reader_rpc',to_regprocedure('public.library_open_item(uuid)') is not null,
  'admin_rpc',to_regprocedure('public.library_admin_bootstrap_v2()') is not null,
  'collections',to_regclass('public.library_collections') is not null,
  'bookmarks',to_regclass('public.library_bookmarks') is not null,
  'notes',to_regclass('public.library_notes') is not null,
  'requests',to_regclass('public.library_book_requests') is not null
)) as arewarin_library_v2_status;
