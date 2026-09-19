-- ============================================================================
-- AreWarin Library V1
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

-- Edge Function authorization. Does not expose the private path to ordinary SQL users.
create or replace function public.library_edge_authorize(p_user_id uuid,p_item_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r text; i public.library_items%rowtype; display text; code text; lp integer:=1;
begin
  r:=public.library_role_for_user(p_user_id); if r='none' then return jsonb_build_object('ok',false,'message','No library access'); end if;
  select * into i from public.library_items where id=p_item_id;
  if not found then return jsonb_build_object('ok',false,'message','Book not found'); end if;
  if r<>'admin' and i.status<>'published' then return jsonb_build_object('ok',false,'message','Book is not published'); end if;
  if r='student' and i.audience='staff' then return jsonb_build_object('ok',false,'message','Staff only'); end if;
  if r='student' then select coalesce(nickname,display_name,first_name,'Student'),student_code into display,code from public.os_students where auth_user_id=p_user_id order by created_at desc limit 1; else display:='AreWarin Staff'; end if;
  select coalesce(last_page,1) into lp from public.library_reading_progress where user_id=p_user_id and item_id=p_item_id;
  insert into public.library_access_log(user_id,item_id,role,action) values(p_user_id,p_item_id,r,'open');
  return jsonb_build_object('ok',true,'role',r,'file_path',i.file_path,'title',i.title,'last_page',coalesce(lp,1),'watermark',trim(concat_ws(' · ',display,code)));
end $$;
revoke all on function public.library_edge_authorize(uuid,uuid) from public;
grant execute on function public.library_edge_authorize(uuid,uuid) to service_role;

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

-- IMPORTANT: No student SELECT policy is created for library-books.
-- PDFs are opened only through the library-reader Edge Function (short signed URL).
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
 'edge_auth',to_regprocedure('public.library_edge_authorize(uuid,uuid)') is not null
)) as arewarin_library_v1_status;
