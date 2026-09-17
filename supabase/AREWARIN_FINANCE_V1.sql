-- ============================================================================
-- AreWarin Finance OS V1
-- Full finance workspace: documents, running numbers, ledger, parties, tax center,
-- templates, signatories, storage and manager-only RPCs.
-- ============================================================================

begin;
create extension if not exists pgcrypto;

do $$
begin
  if to_regprocedure('public.is_manager()') is null then
    raise exception 'Missing public.is_manager()';
  end if;
end $$;

create table if not exists public.finance_settings (
  id smallint primary key default 1 check(id=1),
  business_name text,
  business_name_en text,
  tax_id text,
  branch text default 'สำนักงานใหญ่',
  address text,
  phone text,
  email text,
  bank_name text,
  bank_account_no text,
  bank_account_name text,
  default_vat_rate numeric(6,3) not null default 0,
  accent_color text not null default '#172554',
  footer_text text,
  logo_path text,
  numbering_year_mode text not null default 'BE' check(numbering_year_mode in ('BE','CE')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into public.finance_settings(id,business_name,footer_text) values(1,'AreWarin','ขอบคุณที่ไว้วางใจ AreWarin') on conflict(id) do nothing;

create table if not exists public.finance_document_series (
  doc_type text primary key check(doc_type in ('quotation','speaker_quotation','invoice','receipt','tax_invoice','credit_note')),
  prefix text not null,
  last_number bigint not null default 0,
  reset_year integer,
  digits smallint not null default 6 check(digits between 3 and 10),
  updated_at timestamptz not null default now()
);
insert into public.finance_document_series(doc_type,prefix) values
 ('quotation','QT'),('speaker_quotation','SPQ'),('invoice','INV'),('receipt','RC'),('tax_invoice','TAX'),('credit_note','CN')
on conflict(doc_type) do nothing;

create table if not exists public.finance_parties (
  id uuid primary key default gen_random_uuid(),
  party_type text not null default 'customer' check(party_type in ('customer','organization','speaker','vendor','other')),
  name text not null,
  tax_id text,
  branch text,
  address text,
  phone text,
  email text,
  notes text,
  active boolean not null default true,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists finance_parties_name_idx on public.finance_parties(name);

create table if not exists public.finance_signatories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  position text,
  signature_path text,
  active boolean not null default true,
  sort_order integer not null default 100,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.finance_documents (
  id uuid primary key default gen_random_uuid(),
  doc_type text not null check(doc_type in ('quotation','speaker_quotation','invoice','receipt','tax_invoice','credit_note')),
  doc_no text unique,
  status text not null default 'draft' check(status in ('draft','issued','sent','paid','cancelled','overdue')),
  issue_date date not null default current_date,
  due_date date,
  party_id uuid references public.finance_parties(id) on delete set null,
  party_name text,
  party_tax_id text,
  party_address text,
  reference_no text,
  source_type text,
  source_id text,
  subtotal numeric(14,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  vat_rate numeric(6,3) not null default 0,
  vat_amount numeric(14,2) not null default 0,
  withholding_rate numeric(6,3) not null default 0,
  withholding_amount numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  currency text not null default 'THB',
  notes text,
  signatory_id uuid references public.finance_signatories(id) on delete set null,
  template_key text not null default 'arewarin_clean',
  issued_at timestamptz,
  paid_at timestamptz,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists finance_documents_issue_idx on public.finance_documents(issue_date desc);
create index if not exists finance_documents_type_idx on public.finance_documents(doc_type,status);

create table if not exists public.finance_document_items (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references public.finance_documents(id) on delete cascade,
  description text not null,
  qty numeric(12,3) not null default 1,
  unit text,
  unit_price numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,
  sort_order integer not null default 100,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists finance_document_items_doc_idx on public.finance_document_items(document_id,sort_order);

create table if not exists public.finance_transactions (
  id uuid primary key default gen_random_uuid(),
  kind text not null check(kind in ('income','expense')),
  transaction_date date not null default current_date,
  category text,
  description text,
  party_id uuid references public.finance_parties(id) on delete set null,
  party_name text,
  amount numeric(14,2) not null default 0,
  vat_amount numeric(14,2) not null default 0,
  withholding_tax numeric(14,2) not null default 0,
  payment_method text,
  document_id uuid references public.finance_documents(id) on delete set null,
  source_type text,
  source_id text,
  attachment_path text,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists finance_txn_date_idx on public.finance_transactions(transaction_date desc);

create table if not exists public.finance_tax_filings (
  id uuid primary key default gen_random_uuid(),
  form_type text not null check(form_type in ('PND90','PND91','PND94')),
  tax_year integer not null,
  period_key text,
  status text not null default 'draft' check(status in ('draft','ready','filed','paid','amended')),
  gross_income numeric(14,2) not null default 0,
  deductible_expenses numeric(14,2) not null default 0,
  allowances numeric(14,2) not null default 0,
  net_income numeric(14,2) not null default 0,
  estimated_tax numeric(14,2) not null default 0,
  withholding_credit numeric(14,2) not null default 0,
  prepaid_tax numeric(14,2) not null default 0,
  net_payable numeric(14,2) not null default 0,
  filed_at timestamptz,
  paid_at timestamptz,
  filing_reference text,
  notes text,
  attachment_path text,
  payload jsonb not null default '{}'::jsonb,
  created_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(form_type,tax_year,period_key)
);
create index if not exists finance_tax_status_idx on public.finance_tax_filings(tax_year desc,form_type,status);

create table if not exists public.finance_audit_log (
  id bigserial primary key,
  actor_id uuid default auth.uid(),
  action text not null,
  entity_type text not null,
  entity_id text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Storage bucket for logos/signatures/attachments.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('finance-assets','finance-assets',false,10485760,array['image/png','image/jpeg','image/webp','application/pdf'])
on conflict(id) do nothing;

-- RLS
alter table public.finance_settings enable row level security;
alter table public.finance_document_series enable row level security;
alter table public.finance_parties enable row level security;
alter table public.finance_signatories enable row level security;
alter table public.finance_documents enable row level security;
alter table public.finance_document_items enable row level security;
alter table public.finance_transactions enable row level security;
alter table public.finance_tax_filings enable row level security;
alter table public.finance_audit_log enable row level security;

do $$
declare t text;
begin
 foreach t in array array['finance_settings','finance_document_series','finance_parties','finance_signatories','finance_documents','finance_document_items','finance_transactions','finance_tax_filings','finance_audit_log']
 loop
   execute format('drop policy if exists %I on public.%I','finance manager all '||t,t);
   execute format('create policy %I on public.%I for all to authenticated using(public.is_manager()) with check(public.is_manager())','finance manager all '||t,t);
 end loop;
end $$;

drop policy if exists "finance assets manager select" on storage.objects;
create policy "finance assets manager select" on storage.objects for select to authenticated using(bucket_id='finance-assets' and public.is_manager());
drop policy if exists "finance assets manager insert" on storage.objects;
create policy "finance assets manager insert" on storage.objects for insert to authenticated with check(bucket_id='finance-assets' and public.is_manager());
drop policy if exists "finance assets manager update" on storage.objects;
create policy "finance assets manager update" on storage.objects for update to authenticated using(bucket_id='finance-assets' and public.is_manager()) with check(bucket_id='finance-assets' and public.is_manager());
drop policy if exists "finance assets manager delete" on storage.objects;
create policy "finance assets manager delete" on storage.objects for delete to authenticated using(bucket_id='finance-assets' and public.is_manager());

create or replace function public.finance_manager_me()
returns jsonb language sql stable security definer set search_path=public as $$
 select jsonb_build_object('allowed',public.is_manager(),'user_id',auth.uid())
$$;
grant execute on function public.finance_manager_me() to authenticated;

create or replace function public.finance_next_number(p_doc_type text,p_issue_date date default current_date)
returns text language plpgsql security definer set search_path=public as $$
declare v_prefix text;v_last bigint;v_digits int;v_reset int;v_year int;v_mode text;v_no text;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 select numbering_year_mode into v_mode from public.finance_settings where id=1;
 v_year:=extract(year from coalesce(p_issue_date,current_date))::int + case when coalesce(v_mode,'BE')='BE' then 543 else 0 end;
 select prefix,last_number,digits,reset_year into v_prefix,v_last,v_digits,v_reset
 from public.finance_document_series where doc_type=p_doc_type for update;
 if not found then raise exception 'Unknown document type %',p_doc_type; end if;
 if v_reset is distinct from v_year then v_last:=0; end if;
 v_last:=v_last+1;
 update public.finance_document_series set last_number=v_last,reset_year=v_year,updated_at=now() where doc_type=p_doc_type;
 v_no:=v_prefix||'-'||v_year::text||'-'||lpad(v_last::text,v_digits,'0');
 return v_no;
end $$;

create or replace function public.finance_bootstrap()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v jsonb;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 select jsonb_build_object(
  'settings',coalesce((select to_jsonb(s) from public.finance_settings s where id=1),'{}'::jsonb),
  'series',coalesce((select jsonb_agg(to_jsonb(x) order by x.doc_type) from public.finance_document_series x),'[]'::jsonb),
  'parties',coalesce((select jsonb_agg(to_jsonb(x) order by x.name) from public.finance_parties x where x.active=true),'[]'::jsonb),
  'signers',coalesce((select jsonb_agg(to_jsonb(x) order by x.sort_order,x.name) from public.finance_signatories x),'[]'::jsonb),
  'docs',coalesce((select jsonb_agg(to_jsonb(z) order by z.issue_date desc,z.created_at desc) from (
    select d.*,coalesce((select jsonb_agg(to_jsonb(i) order by i.sort_order,i.created_at) from public.finance_document_items i where i.document_id=d.id),'[]'::jsonb) items
    from public.finance_documents d
  ) z),'[]'::jsonb),
  'txns',coalesce((select jsonb_agg(to_jsonb(x) order by x.transaction_date desc,x.created_at desc) from public.finance_transactions x),'[]'::jsonb),
  'tax',coalesce((select jsonb_agg(to_jsonb(x) order by x.tax_year desc,x.form_type) from public.finance_tax_filings x),'[]'::jsonb),
  'enrollments',case when to_regclass('public.enrollments') is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(x)) from (select id,fullname,nickname,phone,course_text,tutor_text,amount_quoted,status,receipt_no,created_at from public.enrollments order by created_at desc limit 300) x),'[]'::jsonb) end,
  'payments',case when to_regclass('public.payments') is null then '[]'::jsonb else coalesce((select jsonb_agg(to_jsonb(x)) from (select id,enrollment_id,amount_submitted,verified_amount,status,created_at from public.payments order by created_at desc limit 300) x),'[]'::jsonb) end
 ) into v;
 return v;
end $$;
grant execute on function public.finance_bootstrap() to authenticated;

create or replace function public.finance_document_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_type text;v_status text;v_no text;v_sub numeric:=0;v_disc numeric:=0;v_vat_rate numeric:=0;v_wht_rate numeric:=0;v_vat numeric:=0;v_wht numeric:=0;v_total numeric:=0;v_item jsonb;v_issue date;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 begin v_id=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
 v_type:=p_payload->>'doc_type';v_status:=coalesce(nullif(p_payload->>'status',''),'draft');v_issue:=coalesce(nullif(p_payload->>'issue_date','')::date,current_date);
 v_disc:=greatest(0,coalesce((p_payload->>'discount_amount')::numeric,0));v_vat_rate:=greatest(0,coalesce((p_payload->>'vat_rate')::numeric,0));v_wht_rate:=greatest(0,coalesce((p_payload->>'withholding_rate')::numeric,0));
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'items','[]'::jsonb)) loop
   v_sub:=v_sub+greatest(0,coalesce((v_item->>'qty')::numeric,0))*greatest(0,coalesce((v_item->>'unit_price')::numeric,0));
 end loop;
 v_vat:=greatest(0,v_sub-v_disc)*v_vat_rate/100;v_wht:=greatest(0,v_sub-v_disc)*v_wht_rate/100;v_total:=greatest(0,v_sub-v_disc)+v_vat-v_wht;
 if v_id is null then
   if v_status<>'draft' then v_no:=public.finance_next_number(v_type,v_issue); end if;
   insert into public.finance_documents(doc_type,doc_no,status,issue_date,due_date,party_id,party_name,party_tax_id,party_address,reference_no,subtotal,discount_amount,vat_rate,vat_amount,withholding_rate,withholding_amount,grand_total,notes,signatory_id,issued_at)
   values(v_type,v_no,v_status,v_issue,nullif(p_payload->>'due_date','')::date,nullif(p_payload->>'party_id','')::uuid,nullif(p_payload->>'party_name',''),nullif(p_payload->>'party_tax_id',''),nullif(p_payload->>'party_address',''),nullif(p_payload->>'reference_no',''),v_sub,v_disc,v_vat_rate,v_vat,v_wht_rate,v_wht,v_total,nullif(p_payload->>'notes',''),nullif(p_payload->>'signatory_id','')::uuid,case when v_status='draft' then null else now() end)
   returning id into v_id;
 else
   select doc_no into v_no from public.finance_documents where id=v_id for update;
   if v_no is null and v_status<>'draft' then v_no:=public.finance_next_number(v_type,v_issue); end if;
   update public.finance_documents set doc_type=v_type,doc_no=v_no,status=v_status,issue_date=v_issue,due_date=nullif(p_payload->>'due_date','')::date,party_id=nullif(p_payload->>'party_id','')::uuid,party_name=nullif(p_payload->>'party_name',''),party_tax_id=nullif(p_payload->>'party_tax_id',''),party_address=nullif(p_payload->>'party_address',''),reference_no=nullif(p_payload->>'reference_no',''),subtotal=v_sub,discount_amount=v_disc,vat_rate=v_vat_rate,vat_amount=v_vat,withholding_rate=v_wht_rate,withholding_amount=v_wht,grand_total=v_total,notes=nullif(p_payload->>'notes',''),signatory_id=nullif(p_payload->>'signatory_id','')::uuid,issued_at=case when v_no is not null then coalesce(issued_at,now()) else null end,updated_at=now() where id=v_id;
   delete from public.finance_document_items where document_id=v_id;
 end if;
 for v_item in select value from jsonb_array_elements(coalesce(p_payload->'items','[]'::jsonb)) loop
   insert into public.finance_document_items(document_id,description,qty,unit_price,line_total,sort_order)
   values(v_id,v_item->>'description',coalesce((v_item->>'qty')::numeric,1),coalesce((v_item->>'unit_price')::numeric,0),coalesce((v_item->>'qty')::numeric,1)*coalesce((v_item->>'unit_price')::numeric,0),coalesce((v_item->>'sort_order')::int,100));
 end loop;
 insert into public.finance_audit_log(action,entity_type,entity_id,payload) values('save_document','finance_document',v_id::text,jsonb_build_object('type',v_type,'status',v_status,'doc_no',v_no));
 return jsonb_build_object('ok',true,'id',v_id,'doc_no',v_no);
exception when others then return jsonb_build_object('ok',false,'message',SQLERRM,'sqlstate',SQLSTATE);
end $$;
grant execute on function public.finance_document_save(jsonb) to authenticated;

create or replace function public.finance_transaction_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 begin v_id=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
 if v_id is null then
  insert into public.finance_transactions(kind,transaction_date,category,description,party_name,amount,vat_amount,withholding_tax,payment_method)
  values(p_payload->>'kind',coalesce(nullif(p_payload->>'transaction_date','')::date,current_date),nullif(p_payload->>'category',''),nullif(p_payload->>'description',''),nullif(p_payload->>'party_name',''),coalesce((p_payload->>'amount')::numeric,0),coalesce((p_payload->>'vat_amount')::numeric,0),coalesce((p_payload->>'withholding_tax')::numeric,0),nullif(p_payload->>'payment_method','')) returning id into v_id;
 else
  update public.finance_transactions set kind=p_payload->>'kind',transaction_date=coalesce(nullif(p_payload->>'transaction_date','')::date,current_date),category=nullif(p_payload->>'category',''),description=nullif(p_payload->>'description',''),party_name=nullif(p_payload->>'party_name',''),amount=coalesce((p_payload->>'amount')::numeric,0),vat_amount=coalesce((p_payload->>'vat_amount')::numeric,0),withholding_tax=coalesce((p_payload->>'withholding_tax')::numeric,0),payment_method=nullif(p_payload->>'payment_method',''),updated_at=now() where id=v_id;
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
grant execute on function public.finance_transaction_save(jsonb) to authenticated;

create or replace function public.finance_party_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 begin v_id=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
 if coalesce(trim(p_payload->>'name'),'')='' then return jsonb_build_object('ok',false,'message','กรุณากรอกชื่อ'); end if;
 if v_id is null then
  insert into public.finance_parties(party_type,name,tax_id,branch,address,phone,email,notes) values(coalesce(nullif(p_payload->>'party_type',''),'customer'),p_payload->>'name',nullif(p_payload->>'tax_id',''),nullif(p_payload->>'branch',''),nullif(p_payload->>'address',''),nullif(p_payload->>'phone',''),nullif(p_payload->>'email',''),nullif(p_payload->>'notes','')) returning id into v_id;
 else
  update public.finance_parties set party_type=coalesce(nullif(p_payload->>'party_type',''),'customer'),name=p_payload->>'name',tax_id=nullif(p_payload->>'tax_id',''),branch=nullif(p_payload->>'branch',''),address=nullif(p_payload->>'address',''),phone=nullif(p_payload->>'phone',''),email=nullif(p_payload->>'email',''),notes=nullif(p_payload->>'notes',''),updated_at=now() where id=v_id;
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
grant execute on function public.finance_party_save(jsonb) to authenticated;

create or replace function public.finance_signatory_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 begin v_id=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
 if v_id is null then insert into public.finance_signatories(name,position,signature_path,active) values(p_payload->>'name',nullif(p_payload->>'position',''),nullif(p_payload->>'signature_path',''),coalesce((p_payload->>'active')::boolean,true)) returning id into v_id;
 else update public.finance_signatories set name=p_payload->>'name',position=nullif(p_payload->>'position',''),signature_path=nullif(p_payload->>'signature_path',''),active=coalesce((p_payload->>'active')::boolean,true),updated_at=now() where id=v_id; end if;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
grant execute on function public.finance_signatory_save(jsonb) to authenticated;

create or replace function public.finance_series_save(p_rows jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 for r in select value from jsonb_array_elements(coalesce(p_rows,'[]'::jsonb)) loop
   update public.finance_document_series set prefix=upper(regexp_replace(coalesce(r->>'prefix',''),'[^A-Za-z0-9]','','g')),last_number=greatest(0,coalesce((r->>'last_number')::bigint,last_number)),updated_at=now() where doc_type=r->>'doc_type';
 end loop;
 return jsonb_build_object('ok',true);
end $$;
grant execute on function public.finance_series_save(jsonb) to authenticated;

create or replace function public.finance_settings_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 update public.finance_settings set business_name=nullif(p_payload->>'business_name',''),business_name_en=nullif(p_payload->>'business_name_en',''),tax_id=nullif(p_payload->>'tax_id',''),branch=nullif(p_payload->>'branch',''),address=nullif(p_payload->>'address',''),phone=nullif(p_payload->>'phone',''),email=nullif(p_payload->>'email',''),bank_name=nullif(p_payload->>'bank_name',''),bank_account_no=nullif(p_payload->>'bank_account_no',''),bank_account_name=nullif(p_payload->>'bank_account_name',''),default_vat_rate=coalesce((p_payload->>'default_vat_rate')::numeric,0),accent_color=coalesce(nullif(p_payload->>'accent_color',''),'#172554'),footer_text=nullif(p_payload->>'footer_text',''),logo_path=nullif(p_payload->>'logo_path',''),updated_at=now() where id=1;
 return jsonb_build_object('ok',true);
end $$;
grant execute on function public.finance_settings_save(jsonb) to authenticated;

create or replace function public.finance_tax_filing_save(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_id uuid;
begin
 if not public.is_manager() then raise exception 'Manager permission required'; end if;
 begin v_id=nullif(p_payload->>'id','')::uuid; exception when others then v_id:=null; end;
 if v_id is null then
  insert into public.finance_tax_filings(form_type,tax_year,period_key,status,gross_income,deductible_expenses,allowances,net_income,estimated_tax,withholding_credit,prepaid_tax,net_payable,filing_reference,notes,filed_at,paid_at)
  values(p_payload->>'form_type',(p_payload->>'tax_year')::int,coalesce(nullif(p_payload->>'period_key',''),'annual'),coalesce(nullif(p_payload->>'status',''),'draft'),coalesce((p_payload->>'gross_income')::numeric,0),coalesce((p_payload->>'deductible_expenses')::numeric,0),coalesce((p_payload->>'allowances')::numeric,0),coalesce((p_payload->>'net_income')::numeric,0),coalesce((p_payload->>'estimated_tax')::numeric,0),coalesce((p_payload->>'withholding_credit')::numeric,0),coalesce((p_payload->>'prepaid_tax')::numeric,0),coalesce((p_payload->>'net_payable')::numeric,0),nullif(p_payload->>'filing_reference',''),nullif(p_payload->>'notes',''),case when p_payload->>'status' in ('filed','paid') then now() else null end,case when p_payload->>'status'='paid' then now() else null end) returning id into v_id;
 else
  update public.finance_tax_filings set form_type=p_payload->>'form_type',tax_year=(p_payload->>'tax_year')::int,status=coalesce(nullif(p_payload->>'status',''),'draft'),gross_income=coalesce((p_payload->>'gross_income')::numeric,0),deductible_expenses=coalesce((p_payload->>'deductible_expenses')::numeric,0),allowances=coalesce((p_payload->>'allowances')::numeric,0),net_income=coalesce((p_payload->>'net_income')::numeric,0),estimated_tax=coalesce((p_payload->>'estimated_tax')::numeric,0),withholding_credit=coalesce((p_payload->>'withholding_credit')::numeric,0),prepaid_tax=coalesce((p_payload->>'prepaid_tax')::numeric,0),net_payable=coalesce((p_payload->>'net_payable')::numeric,0),filing_reference=nullif(p_payload->>'filing_reference',''),notes=nullif(p_payload->>'notes',''),filed_at=case when p_payload->>'status' in ('filed','paid') then coalesce(filed_at,now()) else filed_at end,paid_at=case when p_payload->>'status'='paid' then coalesce(paid_at,now()) else paid_at end,updated_at=now() where id=v_id;
 end if;
 return jsonb_build_object('ok',true,'id',v_id);
end $$;
grant execute on function public.finance_tax_filing_save(jsonb) to authenticated;

notify pgrst,'reload schema';
commit;

select jsonb_pretty(jsonb_build_object(
 'ok',true,
 'settings',to_regclass('public.finance_settings') is not null,
 'documents',to_regclass('public.finance_documents') is not null,
 'transactions',to_regclass('public.finance_transactions') is not null,
 'tax_filings',to_regclass('public.finance_tax_filings') is not null,
 'bootstrap_rpc',to_regprocedure('public.finance_bootstrap()') is not null,
 'next_number_rpc',to_regprocedure('public.finance_next_number(text,date)') is not null
)) as arewarin_finance_v1_status;
