const db = window.SCHOOL_SUPABASE;
const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = (v='') => String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const collator = new Intl.Collator('th',{numeric:true,sensitivity:'base'});
let rows = [], settings = {}, staffAlumni = [], submissions = [];
let editingId = null, pendingFile = null, reviewingSubmissionId = null;

const currentBuddhistYear = new Date().getFullYear()+543;
function normalizeBatchSelectValue(v=''){v=String(v||'').trim();if(/^\d+$/.test(v))return `รุ่น ${v}`;if(/^รุ่น\s*\d+$/i.test(v))return `รุ่น ${v.replace(/\D/g,'')}`;return v;}
function fillStructuredSelects(root=document){
  root.querySelectorAll('.alumni-batch-select').forEach(el=>{const v=normalizeBatchSelectValue(el.value);el.innerHTML='<option value="">-- เลือกรุ่น --</option>'+Array.from({length:50},(_,i)=>`<option value="รุ่น ${i+1}">รุ่น ${i+1}</option>`).join('');if(v)el.value=v;});
  root.querySelectorAll('.graduation-year-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option>'+Array.from({length:currentBuddhistYear-2499},(_,i)=>currentBuddhistYear-i).map(y=>`<option value="${y}">${y}</option>`).join('');if(v)el.value=v;});
  root.querySelectorAll('.graduation-level-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option>'+Array.from({length:6},(_,i)=>`<option value="ม.${i+1}">มัธยมศึกษาปีที่ ${i+1} (ม.${i+1})</option>`).join('');if(v)el.value=v;});
  root.querySelectorAll('.naktham-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option><option value="ตรี">นักธรรมตรี</option><option value="โท">นักธรรมโท</option><option value="เอก">นักธรรมเอก</option>';if(v)el.value=v;});
  root.querySelectorAll('.pali-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option><option value="ประโยค 1-2">ประโยค 1-2</option>'+Array.from({length:7},(_,i)=>i+3).map(n=>`<option value="ป.ธ.${n}">เปรียญธรรม ${n} ประโยค (ป.ธ.${n})</option>`).join('');if(v)el.value=v;});
}
function syncScholarshipBlock(form){if(!form)return;const cb=form.elements.is_royal_scholarship;const box=cb?.closest('.rounded-2xl')?.querySelector('.royal-scholarship-fields');if(!cb||!box)return;box.classList.toggle('hidden',!cb.checked);box.querySelectorAll('input').forEach(i=>i.required=cb.checked);}
function bindScholarshipToggles(root=document){root.querySelectorAll('.royal-scholarship-toggle').forEach(cb=>{if(cb.dataset.bound)return;cb.dataset.bound='1';cb.addEventListener('change',()=>syncScholarshipBlock(cb.form));});}
function scholarshipValid(form){return !form.elements.is_royal_scholarship?.checked || (form.elements.royal_scholarship_batch.value.trim() && form.elements.royal_scholarship_phase.value.trim());}


function toast(msg,ok=true){const t=$('#toast');t.textContent=msg;t.className=`fixed bottom-5 right-5 z-[200] px-5 py-3 rounded-2xl shadow-2xl text-sm font-bold ${ok?'bg-slate-950 text-white':'bg-red-600 text-white'}`;t.classList.remove('hidden');setTimeout(()=>t.classList.add('hidden'),3000)}
function normalize(v=''){return String(v).trim().toLowerCase().replace(/\s+/g,' ')}
function photoFallback(){return 'data:image/svg+xml;charset=UTF-8,'+encodeURIComponent(`<svg xmlns="http://www.w3.org/2000/svg" width="400" height="400"><rect width="100%" height="100%" fill="#f1f5f9"/><circle cx="200" cy="150" r="70" fill="#cbd5e1"/><rect x="85" y="235" width="230" height="120" rx="60" fill="#94a3b8"/></svg>`)}
function fmtDate(v){if(!v)return '-';try{return new Intl.DateTimeFormat('th-TH',{dateStyle:'medium',timeStyle:'short'}).format(new Date(v))}catch{return v}}
function submissionCode(x){return `ALM-${String(x?.submission_no||0).padStart(6,'0')}`}
function statusMeta(status){return ({pending:['รอตรวจสอบ','bg-orange-50 text-orange-700'],approved:['อนุมัติแล้ว','bg-green-50 text-green-700'],rejected:['ไม่อนุมัติ','bg-red-50 text-red-600']})[status]||[status||'-','bg-slate-100 text-slate-500']}

async function init(){
  lucide.createIcons();
  if(!db){showLoginError('ยังไม่ได้ตั้งค่า Supabase');return}
  const {data:{session}}=await db.auth.getSession();
  if(session) await enterApp(session); else $('#login-screen').classList.remove('hidden');
  db.auth.onAuthStateChange(async (_e,s)=>{if(s && $('#app').classList.contains('hidden')) await enterApp(s)});
}
async function enterApp(){
  $('#login-screen').classList.add('hidden');$('#app').classList.remove('hidden');
  await Promise.all([loadSettings(),loadRows(),loadSubmissions(),loadStaffAlumni()]);
  renderAll();
}
function showLoginError(msg){const el=$('#login-error');el.textContent=msg;el.classList.toggle('hidden',!msg)}
$('#login-form').addEventListener('submit',async e=>{e.preventDefault();showLoginError('');const {error}=await db.auth.signInWithPassword({email:$('#login-email').value.trim(),password:$('#login-password').value});if(error)showLoginError(error.message)});
$('#logout-btn').addEventListener('click',async()=>{await db.auth.signOut();location.reload()});

async function loadSettings(){const {data,error}=await db.from('site_settings').select('data').eq('id',1).maybeSingle();if(error)console.warn(error);settings=data?.data||{}}
async function loadRows(){const {data,error}=await db.from('alumni').select('*').order('sort_order',{ascending:true}).order('full_name',{ascending:true});if(error){toast('ยังไม่พบตาราง alumni กรุณารัน SQL อัปเกรดก่อน',false);rows=[];return}rows=data||[]}
async function loadSubmissions(){
  const {data,error}=await db.from('alumni_submissions').select('*').eq('submission_state','submitted').order('submitted_at',{ascending:false});
  if(error){console.warn('alumni_submissions unavailable',error);submissions=[];return}
  submissions=data||[];
}
async function loadStaffAlumni(){
  const {data,error}=await db.from('personnel').select('*').eq('published',true).eq('is_alumni',true).order('sort_order',{ascending:true}).order('full_name',{ascending:true});
  if(!error){staffAlumni=(data||[]).map(x=>({name:x.full_name,img:x.image_url,position:x.position,department:x.department,alumniBatch:x.alumni_batch,_label:({executive:'คณะผู้บริหาร',teacher:'ครูและบุคลากร',special:'ครูพิเศษ'})[x.staff_type]||'บุคลากร'}));return}
  staffAlumni=extractStaff(settings);
}
function extractStaff(s){const out=[];[['executives','คณะผู้บริหาร'],['teachers','ครูและบุคลากร'],['specialTeachers','ครูพิเศษ']].forEach(([key,label])=>(s?.[key]||[]).forEach((p,i)=>{if(p?.isAlumni)out.push({...p,_key:key,_index:i,_label:label})}));return out}

function renderAll(){renderStats();renderFilters();renderRows();renderStaff();renderSubmissionStats();renderSubmissionFilters();renderSubmissions();fillStructuredSelects();bindScholarshipToggles();lucide.createIcons()}
function renderStats(){
  $('#stat-total').textContent=rows.length.toLocaleString('th-TH');
  $('#stat-published').textContent=rows.filter(x=>x.published).length.toLocaleString('th-TH');
  $('#stat-batches').textContent=new Set(rows.map(x=>String(x.batch||'').trim()).filter(Boolean)).size.toLocaleString('th-TH');
  $('#stat-featured').textContent=rows.filter(x=>x.featured).length.toLocaleString('th-TH');
}
function renderFilters(){const current=$('#batch-filter').value;const batches=[...new Set(rows.map(x=>x.batch).filter(Boolean))].sort((a,b)=>collator.compare(b,a));$('#batch-filter').innerHTML='<option value="">ทุกรุ่น</option>'+batches.map(b=>`<option value="${esc(b)}">${esc(b)}</option>`).join('');$('#batch-filter').value=batches.includes(current)?current:''}
function getFiltered(){const q=normalize($('#search').value),batch=$('#batch-filter').value,status=$('#status-filter').value;return rows.filter(x=>{const hay=normalize([x.full_name,x.batch,x.graduation_year,x.current_position,x.occupation,x.organization,x.education].join(' '));return(!q||hay.includes(q))&&(!batch||x.batch===batch)&&(!status||(status==='published'?x.published:!x.published))})}
function renderRows(){const arr=getFiltered(),box=$('#alumni-list');if(!arr.length){box.innerHTML='<div class="md:col-span-2 xl:col-span-3 glass rounded-[2rem] p-10 text-center text-slate-400">ยังไม่มีข้อมูลที่ตรงกับตัวกรอง</div>';return}box.innerHTML=arr.map(x=>`<article class="glass rounded-[2rem] p-5 flex gap-4 items-start">
  <img src="${esc(x.photo_url||photoFallback())}" onerror="this.src='${photoFallback()}'" class="w-24 h-24 rounded-2xl object-cover bg-slate-100 shrink-0" alt="">
  <div class="min-w-0 flex-1"><div class="flex flex-wrap gap-2 mb-1"><span class="text-[10px] font-bold bg-orange-50 text-orange-700 border border-orange-100 px-2 py-1 rounded-full">${esc(x.batch||'ไม่ระบุรุ่น')}</span>${x.featured?'<span class="text-[10px] font-bold bg-amber-50 text-amber-700 px-2 py-1 rounded-full">ศิษย์เก่าเด่น</span>':''}${x.is_royal_scholarship?'<span class="text-[10px] font-bold bg-fuchsia-50 text-fuchsia-700 px-2 py-1 rounded-full">ทุนเฉลิมราชกุมารี</span>':''}<span class="text-[10px] font-bold ${x.published?'bg-green-50 text-green-700':'bg-slate-100 text-slate-500'} px-2 py-1 rounded-full">${x.published?'เผยแพร่':'ซ่อน'}</span></div><h3 class="font-bold text-slate-900 line-clamp-2">${esc(x.full_name)}</h3><p class="text-xs text-orange-600 font-semibold mt-1 line-clamp-1">${esc(x.current_position||x.occupation||'')}</p><p class="text-[11px] text-slate-400 mt-1 line-clamp-1">${esc(x.organization||'')}</p></div>
  <div class="flex flex-col gap-2"><button data-edit="${x.id}" class="p-2.5 rounded-xl bg-orange-50 text-orange-600" title="แก้ไข"><i data-lucide="pencil" class="w-4 h-4"></i></button><button data-toggle="${x.id}" class="p-2.5 rounded-xl ${x.published?'bg-slate-100 text-slate-500':'bg-green-50 text-green-600'}" title="${x.published?'ซ่อน':'เผยแพร่'}"><i data-lucide="${x.published?'eye-off':'eye'}" class="w-4 h-4"></i></button><button data-delete="${x.id}" class="p-2.5 rounded-xl bg-red-50 text-red-500" title="ลบ"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div>
</article>`).join('');
  $$('[data-edit]').forEach(b=>b.onclick=()=>openEditor(b.dataset.edit));$$('[data-toggle]').forEach(b=>b.onclick=()=>togglePublish(b.dataset.toggle));$$('[data-delete]').forEach(b=>b.onclick=()=>deleteRow(b.dataset.delete));lucide.createIcons();
}
function renderStaff(){const box=$('#staff-alumni-list');box.innerHTML=staffAlumni.map(p=>`<article class="glass rounded-[2rem] p-5 flex gap-4 items-center"><img src="${esc(p.img||photoFallback())}" onerror="this.src='${photoFallback()}'" class="w-20 h-20 rounded-2xl object-cover bg-slate-100"><div class="min-w-0"><span class="text-[10px] font-bold bg-amber-50 text-amber-700 px-2 py-1 rounded-full">${esc(p.alumniBatch||'ไม่ระบุรุ่น')}</span><h3 class="font-bold mt-2">${esc(p.name||'-')}</h3><p class="text-xs text-slate-500 mt-1">${esc(p.position||p.department||p._label)}</p></div></article>`).join('')||'<div class="md:col-span-2 xl:col-span-3 glass rounded-[2rem] p-10 text-center text-slate-400">ยังไม่มีบุคลากรที่ถูกติ๊กว่าเป็นศิษย์เก่า</div>'}

// ---------------- Alumni editor ----------------
function openEditor(id=null){
  editingId=id;pendingFile=null;const x=id?rows.find(r=>r.id===id):null;$('#editor-title').textContent=x?'แก้ไขศิษย์เก่า':'เพิ่มศิษย์เก่า';const f=$('#editor-form');f.reset();
  fillStructuredSelects(f);bindScholarshipToggles(f);f.elements.id.value=x?.id||'';f.elements.full_name.value=x?.full_name||'';f.elements.photo_url.value=x?.photo_url||'';$('#photo-file').value='';f.elements.batch.value=normalizeBatchSelectValue(x?.batch||'');f.elements.graduation_year.value=x?.graduation_year||'';f.elements.graduation_level.value=x?.graduation_level||'';f.elements.naktham_level.value=x?.naktham_level||'';f.elements.pali_level.value=x?.pali_level||'';f.elements.is_royal_scholarship.checked=!!x?.is_royal_scholarship;f.elements.royal_scholarship_batch.value=x?.royal_scholarship_batch||'';f.elements.royal_scholarship_phase.value=x?.royal_scholarship_phase||'';syncScholarshipBlock(f);f.elements.current_position.value=x?.current_position||'';f.elements.occupation.value=x?.occupation||'';f.elements.organization.value=x?.organization||'';f.elements.education.value=x?.education||'';f.elements.bio.value=x?.bio||'';f.elements.phone.value=x?.phone||'';f.elements.email.value=x?.email||'';f.elements.facebook_url.value=x?.facebook_url||'';f.elements.show_contact.checked=!!x?.show_contact;f.elements.featured.checked=!!x?.featured;f.elements.published.checked=x?!!x.published:true;f.elements.sort_order.value=x?.sort_order??0;
  setPreview(x?.photo_url||'');$('#form-status').classList.add('hidden');const m=$('#editor-modal');m.classList.remove('hidden');m.classList.add('flex');lucide.createIcons();
}
function closeEditor(){const m=$('#editor-modal');m.classList.add('hidden');m.classList.remove('flex');pendingFile=null}
$$('[data-close]').forEach(b=>b.addEventListener('click',closeEditor));$('#add-btn').addEventListener('click',()=>openEditor());
function setPreview(url){const img=$('#photo-preview'),ph=$('#photo-placeholder'),note=$('#photo-source-note');if(url){img.src=url;img.classList.remove('hidden');ph.classList.add('hidden');img.onerror=()=>{img.classList.add('hidden');ph.classList.remove('hidden');if(note)note.textContent='ไม่สามารถโหลดตัวอย่างจากลิงก์นี้ได้ กรุณาตรวจสอบ URL'};img.onload=()=>{if(note&&!pendingFile)note.textContent='กำลังใช้รูปจากลิงก์ • แสดงตัวอย่างแล้ว'}}else{img.src='';img.classList.add('hidden');ph.classList.remove('hidden');if(note)note.textContent='รองรับทั้งอัปโหลดจากเครื่องและลิงก์รูปภาพ'}}
$('#photo-file').addEventListener('change',e=>{pendingFile=e.target.files?.[0]||null;if(pendingFile){setPreview(URL.createObjectURL(pendingFile));const note=$('#photo-source-note');if(note)note.textContent=`เลือกไฟล์แล้ว: ${pendingFile.name} • ไฟล์นี้จะถูกใช้เมื่อบันทึก`}});
$('#photo-url-input').addEventListener('input',e=>{const url=e.target.value.trim();if(url){pendingFile=null;$('#photo-file').value='';setPreview(url)}else setPreview('')});
$('#photo-url-open').addEventListener('click',()=>{const url=$('#photo-url-input').value.trim();if(!url)return toast('กรุณาวางลิงก์รูปภาพก่อน',false);try{const u=new URL(url);window.open(u.href,'_blank','noopener,noreferrer')}catch{toast('ลิงก์รูปภาพไม่ถูกต้อง',false)}});
async function uploadPhoto(file){if(!file)return $('#editor-form').elements.photo_url.value.trim()||'';const ext=(file.name.split('.').pop()||'jpg').toLowerCase();const path=`alumni/${new Date().toISOString().slice(0,10)}/${crypto.randomUUID()}.${ext}`;const bucket=window.SCHOOL_APP_CONFIG?.STORAGE_BUCKET||'site-media';const {error}=await db.storage.from(bucket).upload(path,file,{upsert:false,contentType:file.type||undefined});if(error)throw error;return db.storage.from(bucket).getPublicUrl(path).data.publicUrl}
$('#editor-form').addEventListener('submit',async e=>{e.preventDefault();const status=$('#form-status');status.className='text-xs rounded-xl p-3 bg-orange-50 text-orange-700';status.textContent='กำลังบันทึก...';status.classList.remove('hidden');try{const f=e.currentTarget;if(!scholarshipValid(f))throw new Error('กรุณาระบุรุ่นและระยะของทุนเฉลิมราชกุมารี');const photo=await uploadPhoto(pendingFile);const payload={full_name:f.elements.full_name.value.trim(),photo_url:photo,batch:f.elements.batch.value.trim(),graduation_year:f.elements.graduation_year.value.trim(),graduation_level:f.elements.graduation_level.value.trim(),naktham_level:f.elements.naktham_level.value.trim(),pali_level:f.elements.pali_level.value.trim(),is_royal_scholarship:f.elements.is_royal_scholarship.checked,royal_scholarship_batch:f.elements.royal_scholarship_batch.value.trim(),royal_scholarship_phase:f.elements.royal_scholarship_phase.value.trim(),current_position:f.elements.current_position.value.trim(),occupation:f.elements.occupation.value.trim(),organization:f.elements.organization.value.trim(),education:f.elements.education.value.trim(),phone:f.elements.phone.value.trim(),email:f.elements.email.value.trim(),facebook_url:f.elements.facebook_url.value.trim(),bio:f.elements.bio.value.trim(),show_contact:f.elements.show_contact.checked,featured:f.elements.featured.checked,published:f.elements.published.checked,sort_order:Number(f.elements.sort_order.value||0)};let error;if(editingId){({error}=await db.from('alumni').update(payload).eq('id',editingId))}else{({error}=await db.from('alumni').insert(payload))}if(error)throw error;await loadRows();renderAll();closeEditor();toast('บันทึกข้อมูลศิษย์เก่าแล้ว')}catch(err){console.error(err);status.className='text-xs rounded-xl p-3 bg-red-50 text-red-600';status.textContent='บันทึกไม่สำเร็จ: '+(err.message||err)}});
async function togglePublish(id){const x=rows.find(r=>r.id===id);if(!x)return;const {error}=await db.from('alumni').update({published:!x.published}).eq('id',id);if(error)return toast(error.message,false);await loadRows();renderAll();toast(x.published?'ซ่อนจากทำเนียบแล้ว':'เผยแพร่แล้ว')}
async function deleteRow(id){const x=rows.find(r=>r.id===id);if(!x||!confirm(`ลบ ${x.full_name} ออกจากฐานข้อมูลศิษย์เก่าหรือไม่?`))return;const {error}=await db.from('alumni').delete().eq('id',id);if(error)return toast(error.message,false);await loadRows();renderAll();toast('ลบข้อมูลแล้ว')}
$('#search').addEventListener('input',renderRows);$('#batch-filter').addEventListener('change',renderRows);$('#status-filter').addEventListener('change',renderRows);
$('#export-btn').addEventListener('click',()=>{const data=getFiltered();const cols=[['full_name','ชื่อ-นามสกุล'],['batch','รุ่น'],['graduation_year','ปีจบ'],['graduation_level','ระดับที่จบ'],['current_position','ตำแหน่ง'],['occupation','อาชีพ'],['organization','หน่วยงาน'],['phone','โทรศัพท์'],['email','อีเมล'],['published','เผยแพร่']];const q=v=>`"${String(v??'').replace(/"/g,'""')}"`;const csv='\ufeff'+cols.map(c=>q(c[1])).join(',')+'\n'+data.map(r=>cols.map(c=>q(r[c[0]])).join(',')).join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv;charset=utf-8'}));a.download=`alumni-${new Date().toISOString().slice(0,10)}.csv`;a.click();URL.revokeObjectURL(a.href)});

// ---------------- Public submission review queue ----------------
function renderSubmissionStats(){
  const pending=submissions.filter(x=>x.review_status==='pending').length;
  $('#sub-stat-pending').textContent=pending.toLocaleString('th-TH');$('#sub-stat-approved').textContent=submissions.filter(x=>x.review_status==='approved').length.toLocaleString('th-TH');$('#sub-stat-rejected').textContent=submissions.filter(x=>x.review_status==='rejected').length.toLocaleString('th-TH');$('#sub-stat-total').textContent=submissions.length.toLocaleString('th-TH');
  const badge=$('#pending-badge');badge.textContent=pending>99?'99+':pending;badge.classList.toggle('hidden',pending===0);badge.classList.toggle('flex',pending>0);
}
function renderSubmissionFilters(){const sel=$('#submission-batch-filter');const cur=sel.value;const batches=[...new Set(submissions.map(x=>x.batch).filter(Boolean))].sort((a,b)=>collator.compare(b,a));sel.innerHTML='<option value="">ทุกรุ่น</option>'+batches.map(b=>`<option value="${esc(b)}">${esc(b)}</option>`).join('');sel.value=batches.includes(cur)?cur:''}
function getFilteredSubmissions(){const q=normalize($('#submission-search').value),batch=$('#submission-batch-filter').value,status=$('#submission-status-filter').value;return submissions.filter(x=>{const hay=normalize([x.full_name,x.batch,x.phone,x.email,x.occupation,x.organization].join(' '));return(!q||hay.includes(q))&&(!batch||x.batch===batch)&&(!status||x.review_status===status)})}
function renderSubmissions(){
  const box=$('#submission-list'), arr=getFilteredSubmissions();
  if(!arr.length){box.innerHTML='<tr><td colspan="6" class="px-5 py-12 text-center text-slate-400">ยังไม่มีแบบฟอร์มที่ตรงกับตัวกรอง</td></tr>';return}
  box.innerHTML=arr.map(x=>{const [label,cls]=statusMeta(x.review_status);return `<tr class="hover:bg-slate-50/60"><td class="px-5 py-4 font-mono text-xs text-slate-500">${submissionCode(x)}</td><td class="px-4 py-4"><p class="font-bold text-slate-900">${esc(x.full_name)}</p><p class="text-[11px] text-slate-400 mt-1">${esc(x.phone||x.email||'')}</p></td><td class="px-4 py-4 text-sm">${esc(x.batch)}</td><td class="px-4 py-4 text-xs text-slate-500">${esc(fmtDate(x.submitted_at))}</td><td class="px-4 py-4"><span class="text-[10px] font-bold px-2.5 py-1 rounded-full ${cls}">${label}</span></td><td class="px-5 py-4 text-right"><button data-review="${x.id}" class="btn ${x.review_status==='pending'?'btn-primary':'btn-light'}"><i data-lucide="${x.review_status==='pending'?'clipboard-check':'eye'}" class="w-4 h-4"></i> ${x.review_status==='pending'?'ตรวจสอบ':'ดู/แก้ไข'}</button></td></tr>`}).join('');
  $$('[data-review]').forEach(b=>b.onclick=()=>openReview(b.dataset.review));lucide.createIcons();
}
$('#submission-search').addEventListener('input',renderSubmissions);$('#submission-batch-filter').addEventListener('change',renderSubmissions);$('#submission-status-filter').addEventListener('change',renderSubmissions);

async function submissionPhotoUrl(x){
  if(x.photo_url) return x.photo_url;
  if(!x.photo_path) return '';
  const {data,error}=await db.storage.from('alumni-submission-files').createSignedUrl(x.photo_path,3600);
  if(error){console.warn(error);return ''}
  return data?.signedUrl||'';
}
async function openReview(id){
  const x=submissions.find(s=>s.id===id);if(!x)return;
  reviewingSubmissionId=id;const f=$('#review-form');f.reset();
  fillStructuredSelects(f);bindScholarshipToggles(f);f.elements.submission_id.value=x.id;f.elements.full_name.value=x.full_name||'';f.elements.batch.value=normalizeBatchSelectValue(x.batch||'');f.elements.graduation_year.value=x.graduation_year||'';f.elements.graduation_level.value=x.graduation_level||'';f.elements.naktham_level.value=x.naktham_level||'';f.elements.pali_level.value=x.pali_level||'';f.elements.is_royal_scholarship.checked=!!x.is_royal_scholarship;f.elements.royal_scholarship_batch.value=x.royal_scholarship_batch||'';f.elements.royal_scholarship_phase.value=x.royal_scholarship_phase||'';syncScholarshipBlock(f);f.elements.current_position.value=x.current_position||'';f.elements.occupation.value=x.occupation||'';f.elements.organization.value=x.organization||'';f.elements.education.value=x.education||'';f.elements.bio.value=x.bio||'';f.elements.phone.value=x.phone||'';f.elements.email.value=x.email||'';f.elements.facebook_url.value=x.facebook_url||'';f.elements.show_contact.checked=!!x.show_contact;f.elements.featured.checked=!!x.featured;f.elements.admin_note.value=x.admin_note||'';
  $('#review-reference').textContent=`${submissionCode(x)} • ส่งเมื่อ ${fmtDate(x.submitted_at)}`;const [label,cls]=statusMeta(x.review_status);const pill=$('#review-status-pill');pill.className=`text-[10px] font-bold px-2.5 py-1 rounded-full ${cls}`;pill.textContent=label;
  const img=$('#review-photo'),ph=$('#review-photo-placeholder'),open=$('#review-photo-open');img.classList.add('hidden');ph.classList.remove('hidden');open.classList.add('hidden');
  const url=await submissionPhotoUrl(x);if(url){img.src=url;img.classList.remove('hidden');ph.classList.add('hidden');open.href=url;open.classList.remove('hidden')}
  // Editable direct photo URL for link-based submissions.
  let photoInput=$('#review-photo-url');if(photoInput)photoInput.value=x.photo_url||'';
  $('#review-form-status').classList.add('hidden');const m=$('#review-modal');m.classList.remove('hidden');m.classList.add('flex');lucide.createIcons();
}
function closeReview(){const m=$('#review-modal');m.classList.add('hidden');m.classList.remove('flex');reviewingSubmissionId=null}
$$('[data-close-review]').forEach(b=>b.addEventListener('click',closeReview));
function reviewPayload(){const f=$('#review-form');return {full_name:f.elements.full_name.value.trim(),batch:f.elements.batch.value.trim(),graduation_year:f.elements.graduation_year.value.trim(),graduation_level:f.elements.graduation_level.value.trim(),naktham_level:f.elements.naktham_level.value.trim(),pali_level:f.elements.pali_level.value.trim(),is_royal_scholarship:f.elements.is_royal_scholarship.checked,royal_scholarship_batch:f.elements.royal_scholarship_batch.value.trim(),royal_scholarship_phase:f.elements.royal_scholarship_phase.value.trim(),current_position:f.elements.current_position.value.trim(),occupation:f.elements.occupation.value.trim(),organization:f.elements.organization.value.trim(),education:f.elements.education.value.trim(),bio:f.elements.bio.value.trim(),phone:f.elements.phone.value.trim(),email:f.elements.email.value.trim(),facebook_url:f.elements.facebook_url.value.trim(),show_contact:f.elements.show_contact.checked,featured:f.elements.featured.checked,admin_note:f.elements.admin_note.value.trim(),photo_url:$('#review-photo-url')?.value.trim()||submissions.find(x=>x.id===reviewingSubmissionId)?.photo_url||''}}
function reviewStatus(message,ok=true){const el=$('#review-form-status');el.className=`text-xs rounded-xl p-3 ${ok?'bg-green-50 text-green-700':'bg-red-50 text-red-600'}`;el.textContent=message;el.classList.remove('hidden')}
async function saveSubmissionEdits(silent=false){if(!reviewingSubmissionId)return null;const f=$('#review-form');const payload=reviewPayload();if(!payload.full_name||!payload.batch){reviewStatus('กรุณาระบุชื่อ-นามสกุลและรุ่น',false);return null}if(!scholarshipValid(f)){reviewStatus('กรุณาระบุรุ่นและระยะของทุนเฉลิมราชกุมารี',false);return null}const {data,error}=await db.from('alumni_submissions').update(payload).eq('id',reviewingSubmissionId).select('*').single();if(error){reviewStatus('บันทึกไม่สำเร็จ: '+error.message,false);return null}const idx=submissions.findIndex(x=>x.id===reviewingSubmissionId);if(idx>=0)submissions[idx]=data;if(!silent){reviewStatus('บันทึกการแก้ไขแล้ว');renderSubmissionStats();renderSubmissionFilters();renderSubmissions()}return data}
$('#review-save-btn').addEventListener('click',()=>saveSubmissionEdits(false));

async function promotePrivatePhoto(x){
  if(x.photo_url) return x.photo_url;
  if(!x.photo_path) return '';
  const linked=rows.find(r=>r.id===x.approved_alumni_id);if(linked?.photo_url)return linked.photo_url;
  const {data:blob,error:downloadError}=await db.storage.from('alumni-submission-files').download(x.photo_path);if(downloadError)throw downloadError;
  const ext=(x.photo_path.split('.').pop()||'jpg').toLowerCase();const path=`alumni/approved/${new Date().toISOString().slice(0,10)}/${crypto.randomUUID()}.${ext}`;const bucket=window.SCHOOL_APP_CONFIG?.STORAGE_BUCKET||'site-media';
  const {error:uploadError}=await db.storage.from(bucket).upload(path,blob,{upsert:false,contentType:blob.type||undefined});if(uploadError)throw uploadError;
  return db.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}
$('#review-approve-btn').addEventListener('click',async()=>{
  const btn=$('#review-approve-btn');btn.disabled=true;btn.classList.add('opacity-60');reviewStatus('กำลังอนุมัติและนำข้อมูลเข้าทำเนียบ...',true);
  try{
    let x=await saveSubmissionEdits(true);if(!x)throw new Error('กรุณาตรวจสอบข้อมูลที่จำเป็น');
    const photo=await promotePrivatePhoto(x);const alumniPayload={full_name:x.full_name,photo_url:photo,batch:x.batch,graduation_year:x.graduation_year||'',graduation_level:x.graduation_level||'',naktham_level:x.naktham_level||'',pali_level:x.pali_level||'',is_royal_scholarship:!!x.is_royal_scholarship,royal_scholarship_batch:x.royal_scholarship_batch||'',royal_scholarship_phase:x.royal_scholarship_phase||'',current_position:x.current_position||'',occupation:x.occupation||'',organization:x.organization||'',education:x.education||'',phone:x.phone||'',email:x.email||'',facebook_url:x.facebook_url||'',bio:x.bio||'',show_contact:!!x.show_contact,featured:!!x.featured,published:true,sort_order:0};
    let alumniId=x.approved_alumni_id;
    if(alumniId){const {error}=await db.from('alumni').update(alumniPayload).eq('id',alumniId);if(error)throw error}
    else {const {data,error}=await db.from('alumni').insert(alumniPayload).select('id').single();if(error)throw error;alumniId=data.id}
    const {data:{user}}=await db.auth.getUser();const {error:updateError}=await db.from('alumni_submissions').update({review_status:'approved',approved_alumni_id:alumniId,reviewed_at:new Date().toISOString(),reviewed_by:user?.id||null}).eq('id',x.id);if(updateError)throw updateError;
    await Promise.all([loadRows(),loadSubmissions()]);renderAll();closeReview();toast('อนุมัติและเผยแพร่ในทำเนียบแล้ว');
  }catch(err){console.error(err);reviewStatus('อนุมัติไม่สำเร็จ: '+(err.message||err),false)}finally{btn.disabled=false;btn.classList.remove('opacity-60')}
});
$('#review-reject-btn').addEventListener('click',async()=>{
  if(!reviewingSubmissionId||!confirm('ยืนยันว่าไม่อนุมัติรายการนี้?'))return;
  try{let x=await saveSubmissionEdits(true);if(!x)return;const {data:{user}}=await db.auth.getUser();if(x.approved_alumni_id)await db.from('alumni').update({published:false}).eq('id',x.approved_alumni_id);const {error}=await db.from('alumni_submissions').update({review_status:'rejected',reviewed_at:new Date().toISOString(),reviewed_by:user?.id||null}).eq('id',x.id);if(error)throw error;await Promise.all([loadRows(),loadSubmissions()]);renderAll();closeReview();toast('เปลี่ยนสถานะเป็นไม่อนุมัติแล้ว')}catch(err){reviewStatus('ดำเนินการไม่สำเร็จ: '+(err.message||err),false)}
});


// ---------------- Alumni page settings ----------------
function renderAlumniSettings(){
  const url=settings?.alumniDirectory?.heroBackgroundUrl||'';
  const input=$('#hero-background-url'),img=$('#hero-background-preview');if(!input||!img)return;
  input.value=url;updateHeroSettingsPreview(url);
}
function updateHeroSettingsPreview(url){const img=$('#hero-background-preview');if(!img)return;if(url){img.src=url;img.classList.remove('hidden');img.onerror=()=>img.classList.add('hidden')}else{img.classList.add('hidden');img.removeAttribute('src')}}
$('#hero-background-url')?.addEventListener('input',e=>updateHeroSettingsPreview(e.target.value.trim()));
$('#alumni-settings-form')?.addEventListener('submit',async e=>{
  e.preventDefault();const status=$('#settings-status');status.className='text-xs rounded-xl p-3 bg-orange-50 text-orange-700';status.textContent='กำลังบันทึก...';status.classList.remove('hidden');
  try{const url=$('#hero-background-url').value.trim();const next=structuredClone(settings||{});next.alumniDirectory={...(next.alumniDirectory||{}),heroBackgroundUrl:url};const {error}=await db.from('site_settings').upsert({id:1,data:next,updated_at:new Date().toISOString()},{onConflict:'id'});if(error)throw error;settings=next;status.className='text-xs rounded-xl p-3 bg-green-50 text-green-700';status.textContent='บันทึกพื้นหลัง Banner แล้ว';toast('บันทึกพื้นหลังทำเนียบแล้ว');}catch(err){status.className='text-xs rounded-xl p-3 bg-red-50 text-red-600';status.textContent='บันทึกไม่สำเร็จ: '+(err.message||err)}
});

// ---------------- Navigation ----------------
const viewMeta={directory:['รายชื่อศิษย์เก่า','เพิ่ม แก้ไข ลบ และจัดการการเผยแพร่'],submissions:['แบบฟอร์มที่ส่งมา','ตรวจสอบ แก้ไข อนุมัติ หรือไม่อนุมัติก่อนเผยแพร่'], 'staff-alumni':['บุคลากรที่เป็นศิษย์เก่า','ข้อมูลนี้เชื่อมจาก Website Manager อัตโนมัติ'],settings:['ตั้งค่าหน้าทำเนียบ','จัดการภาพพื้นหลัง Banner และการแสดงผลหน้าสาธารณะ']};
$$('.nav-btn').forEach(btn=>btn.addEventListener('click',()=>{
  const view=btn.dataset.view;$$('.nav-btn').forEach(x=>{x.classList.remove('bg-orange-500','text-white');x.classList.add('hover:bg-white/5')});btn.classList.add('bg-orange-500','text-white');btn.classList.remove('hover:bg-white/5');
  $('#panel-directory').classList.toggle('hidden',view!=='directory');$('#panel-submissions').classList.toggle('hidden',view!=='submissions');$('#panel-staff-alumni').classList.toggle('hidden',view!=='staff-alumni');$('#panel-settings').classList.toggle('hidden',view!=='settings');$('#add-btn').classList.toggle('hidden',view!=='directory');if(view==='settings')renderAlumniSettings();$('#page-title').textContent=viewMeta[view][0];$('#page-subtitle').textContent=viewMeta[view][1];
}));

document.addEventListener('keydown',e=>{if(e.key==='Escape'){closeEditor();closeReview()}});
init();
