const sb = window.AreWarinAPI.sb;
let state = { tutors: [], courses: [], reviews: [], prices: [], promotions: [], enrollments: [], payments: [], speakers: [], tutorApplications: [], receipt: null, settings: {}, scheduleTemplates: [], schedules: [], scheduleReservations: [], branding: null, banners: [], categories: [] };
let activeScheduleTutorId = null;
const $ = id => document.getElementById(id);
const esc = v => String(v ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const lines = v => String(v || '').split('\n').map(x=>x.trim()).filter(Boolean);
const csv = v => String(v || '').split(',').map(x=>x.trim()).filter(Boolean);
const notify = (icon,title,text='') => Swal.fire({icon,title,text,confirmButtonColor:'#0ea5e9',customClass:{popup:'rounded-[1.5rem]'}});

let lastManagerAccessError = '';
async function ensureManager(session) {
  lastManagerAccessError = '';
  if (!session?.user) {
    lastManagerAccessError = 'ไม่พบ Supabase session';
    return false;
  }
  if (!sb) {
    lastManagerAccessError = 'ยังไม่ได้เชื่อมต่อ Supabase โปรดตรวจสอบ config.js';
    return false;
  }
  const { data, error } = await sb.from('profiles').select('display_name,role').eq('id',session.user.id).maybeSingle();
  if (error) {
    lastManagerAccessError = `อ่าน public.profiles ไม่ได้: ${error.message}`;
    await sb.auth.signOut();
    return false;
  }
  if (!data) {
    lastManagerAccessError = `ล็อกอิน Auth สำเร็จ แต่ไม่พบ profile ของ ${session.user.email} (user id: ${session.user.id})`;
    await sb.auth.signOut();
    return false;
  }
  if (!['manager','admin'].includes(data.role)) {
    lastManagerAccessError = `บัญชี ${session.user.email} มี role = ${data.role || '(ว่าง)'} ต้องเป็น manager หรือ admin`;
    await sb.auth.signOut();
    return false;
  }
  $('userLabel').textContent = `${data.display_name || session.user.email} • ${data.role}`;
  return true;
}

async function boot() {
  const { data:{session} } = await sb.auth.getSession();
  if (await ensureManager(session)) { $('login').classList.add('hidden'); $('app').classList.remove('hidden'); await loadAll(); }
  sb.auth.onAuthStateChange(async (_e,s) => { if(!s){$('app').classList.add('hidden');$('login').classList.remove('hidden');} });
}

$('btnLogin').onclick = async () => {
  const { data, error } = await sb.auth.signInWithPassword({ email:$('loginEmail').value.trim(), password:$('loginPassword').value });
  if (error) return notify('error','เข้าสู่ระบบไม่สำเร็จ',error.message);
  if (!(await ensureManager(data.session))) return notify('error','ไม่มีสิทธิ์ Manager',lastManagerAccessError || 'บัญชีนี้ยังไม่มี role manager/admin');
  $('login').classList.add('hidden'); $('app').classList.remove('hidden'); await loadAll();
};
$('btnLogout').onclick = () => sb.auth.signOut();

document.querySelectorAll('.nav').forEach(b => b.onclick = () => {
  document.querySelectorAll('.nav').forEach(x=>x.classList.remove('active')); b.classList.add('active');
  document.querySelectorAll('.section').forEach(x=>x.classList.remove('active')); $('section-'+b.dataset.section).classList.add('active');
});

async function loadAll() {
  const [t,c,rv,p,pr,en,pay,sp,ta,rs,as,st,sch,sr,brand,bn,cat] = await Promise.all([
    sb.from('tutors').select('*').order('sort_order'),
    sb.from('courses').select('*').order('sort_order'),
    sb.from('reviews').select('*').order('featured',{ascending:false}).order('sort_order').order('created_at',{ascending:false}),
    sb.from('course_prices').select('*').order('tier').order('package_code'),
    sb.from('promotions').select('*').order('created_at',{ascending:false}),
    sb.from('enrollments').select('*').order('created_at',{ascending:false}),
    sb.from('payments').select('*,enrollments(*)').order('created_at',{ascending:false}),
    sb.from('speaker_requests').select('*').order('created_at',{ascending:false}),
    sb.from('tutor_applications').select('*').order('created_at',{ascending:false}),
    sb.from('receipt_settings').select('*').eq('id',1).single(),
    sb.from('app_settings').select('*'),
    sb.from('schedule_templates').select('*').order('sort_order').order('start_time'),
    sb.from('tutor_schedules').select('*'),
    sb.from('schedule_reservations').select('id,tutor_schedule_id,enrollment_id,seats,status,created_at'),
    sb.from('site_branding').select('*').eq('id',1).maybeSingle(),
    sb.from('home_banners').select('*').order('sort_order').order('created_at'),
    sb.from('subject_categories').select('*').order('sort_order').order('name_th')
  ]);
  for (const x of [t,c,rv,p,pr,en,pay,sp,ta,rs,as,st,sch,sr,brand,bn,cat]) if(x.error) console.error(x.error);
  state.tutors=t.data||[];
  state.courses=c.data||[];
  state.reviews=rv.data||[];
  state.prices=p.data||[];
  state.promotions=pr.data||[];
  state.enrollments=en.data||[];
  state.payments=pay.data||[];
  state.speakers=sp.data||[];
  state.tutorApplications=ta.data||[];
  state.receipt=rs.data||{};
  state.settings=Object.fromEntries((as.data||[]).map(x=>[x.key,typeof x.value==='object'&&x.value?.value!==undefined?x.value.value:x.value]));
  state.scheduleTemplates=st.data||[];
  state.schedules=sch.data||[];
  state.scheduleReservations=sr.data||[];
  state.branding=brand.data||null;
  state.banners=bn.data||[];
  state.categories=cat.data||[];
  if(!activeScheduleTutorId || !state.tutors.some(t=>t.id===activeScheduleTutorId)) activeScheduleTutorId=state.tutors[0]?.id||null;
  $('statTutors').textContent=state.tutors.filter(x=>x.active).length;
  $('statCourses').textContent=state.courses.filter(x=>x.active).length;
  $('statPending').textContent=state.payments.filter(x=>x.status==='pending').length;
  $('statEnrollments').textContent=state.enrollments.length;
  if($('statReviews')) $('statReviews').textContent=state.reviews.filter(x=>x.active).length;
  renderHomepage(); renderTutors(); renderTutorApplications(); renderCourses(); renderReviews(); renderEnrollments(); renderSpeakers(); renderPrices(); renderPromos(); renderPayments(); renderReceipt(); renderSystem(); fillTutorSelect(); renderScheduleManager();
}

async function uploadPublic(bucket,file,prefix) {
  if(!file) return null; const ext=file.name.split('.').pop()||'jpg'; const path=`${prefix}/${crypto.randomUUID()}.${ext}`;
  const {error}=await sb.storage.from(bucket).upload(path,file,{contentType:file.type,upsert:false}); if(error) throw error;
  return sb.storage.from(bucket).getPublicUrl(path).data.publicUrl;
}
async function uploadPrivate(bucket,file,prefix) {
  if(!file) return null; const ext=file.name.split('.').pop()||'png'; const path=`${prefix}/${crypto.randomUUID()}.${ext}`;
  const {error}=await sb.storage.from(bucket).upload(path,file,{contentType:file.type,upsert:false}); if(error) throw error; return path;
}


// ---------- Homepage / Branding / Banner / Subject Category CMS ----------
const DEFAULT_BRAND_LOGO='https://img2.pic.in.th/pic/531691933_1782062845771076_6500762805646335341_n.jpg';
function previewPublicImage(url,imgId,fallbackId){
  const img=$(imgId), fallback=$(fallbackId); if(!img) return;
  if(url){ img.src=url; img.classList.remove('hidden'); if(fallback) fallback.classList.add('hidden'); }
  else { img.src=''; img.classList.add('hidden'); if(fallback) fallback.classList.remove('hidden'); }
}
function renderHomepage(){
  if(!$('brandForm')) return;
  const b=state.branding||{};
  $('brandLogoUrl').value=b.logo_url||'';
  $('brandNameTh').value=b.site_name_th||'กวดวิชาชีววิทยา อาวริน';
  $('brandNameEn').value=b.site_name_en||'AreWarin Biology';
  $('brandTagline').value=b.tagline||'เปลี่ยนเรื่องยาก ให้เป็นเรื่องง่าย';
  $('brandLocation').value=b.location_badge||'Onsite @ขอนแก่น';
  $('brandRegistration').value=b.registration_badge||'🚀 เปิดรับสมัครแล้ว!';
  previewPublicImage(b.logo_url||DEFAULT_BRAND_LOGO,'brandLogoPreview','brandLogoFallback');
  previewPublicImage(b.logo_url||DEFAULT_BRAND_LOGO,'managerBrandLogo','managerBrandFallback');
  renderBanners(); renderCategoriesManager();
}
if($('brandLogoUrl')) $('brandLogoUrl').addEventListener('input',e=>previewPublicImage(e.target.value.trim(),'brandLogoPreview','brandLogoFallback'));
if($('brandLogoFile')) $('brandLogoFile').addEventListener('change',e=>{const f=e.target.files?.[0]; if(f) previewPublicImage(URL.createObjectURL(f),'brandLogoPreview','brandLogoFallback');});
if($('brandForm')) $('brandForm').onsubmit=async e=>{e.preventDefault();try{
  let logo=$('brandLogoUrl').value.trim()||state.branding?.logo_url||null;
  if($('brandLogoFile').files[0]) logo=await uploadPublic('site-assets',$('brandLogoFile').files[0],'branding');
  const row={id:1,logo_url:logo,site_name_th:$('brandNameTh').value.trim()||'กวดวิชาชีววิทยา อาวริน',site_name_en:$('brandNameEn').value.trim()||'AreWarin Biology',tagline:$('brandTagline').value.trim(),location_badge:$('brandLocation').value.trim(),registration_badge:$('brandRegistration').value.trim(),updated_at:new Date().toISOString()};
  const{error}=await sb.from('site_branding').upsert(row); if(error) throw error; await loadAll(); notify('success','บันทึกแบรนด์แล้ว','หน้าเว็บหลักจะใช้ข้อมูลใหม่ทันที');
}catch(err){notify('error','บันทึกแบรนด์ไม่สำเร็จ',err.message)}};

function setBannerPreview(url){previewPublicImage(url,'bannerImagePreview','bannerImageFallback');}
function resetBannerForm(){
  if(!$('bannerForm')) return; $('bannerForm').reset(); $('bannerId').value=''; $('bannerSort').value='100'; $('bannerActive').checked=true; $('bannerImageUrl').value=''; setBannerPreview('');
}
if($('bannerReset')) $('bannerReset').onclick=resetBannerForm;
if($('bannerImageUrl')) $('bannerImageUrl').addEventListener('input',e=>setBannerPreview(e.target.value.trim()));
if($('bannerImageFile')) $('bannerImageFile').addEventListener('change',e=>{const f=e.target.files?.[0];if(f)setBannerPreview(URL.createObjectURL(f));});
function renderBanners(){
  if(!$('bannerList')) return; if($('bannerCount')) $('bannerCount').textContent=`${state.banners.length} รายการ`;
  $('bannerList').innerHTML=state.banners.map(x=>`<article class="overflow-hidden rounded-2xl border border-slate-200 bg-white hover:border-sky-200 transition">
    <div class="aspect-[16/8] bg-slate-100 relative overflow-hidden">${x.image_url?`<img src="${esc(x.image_url)}" class="w-full h-full object-cover">`:'<div class="absolute inset-0 grid place-items-center text-slate-300"><i class="far fa-image text-2xl"></i></div>'}<div class="absolute top-2 left-2 flex gap-1"><span class="tag !bg-white/90">#${Number(x.sort_order||100)}</span><span class="tag ${x.active?'!bg-emerald-50 !text-emerald-600':'!bg-slate-100 !text-slate-500'}">${x.active?'แสดง':'ซ่อน'}</span></div></div>
    <div class="p-3.5"><div class="text-[12px] font-semibold text-slate-800">${esc(x.title)} ${x.highlight_text?`<span class="text-sky-600">${esc(x.highlight_text)}</span>`:''}</div><div class="text-[9.5px] text-slate-400 mt-1 line-clamp-2">${esc(x.description||'ไม่มีคำอธิบาย')}</div><div class="flex gap-2 mt-3"><button onclick="editBanner('${x.id}')" class="flex-1 py-2 rounded-lg bg-sky-50 text-sky-600 text-[10px] font-semibold">แก้ไข</button><button onclick="deleteBanner('${x.id}')" class="px-3 py-2 rounded-lg bg-rose-50 text-rose-600 text-[10px] font-semibold">ลบ</button></div></div>
  </article>`).join('')||'<div class="md:col-span-2 py-8 text-center text-[10px] text-slate-400">ยังไม่มีแบนเนอร์</div>';
}
window.editBanner=id=>{const x=state.banners.find(v=>v.id===id);if(!x)return;$('bannerId').value=x.id;$('bannerTitle').value=x.title||'';$('bannerHighlight').value=x.highlight_text||'';$('bannerDesc').value=x.description||'';$('bannerBadge').value=x.badge_text||'';$('bannerLocation').value=x.location_text||'';$('bannerLink').value=x.link_url||'';$('bannerSort').value=x.sort_order??100;$('bannerActive').checked=x.active!==false;$('bannerImageUrl').value=x.image_url||'';setBannerPreview(x.image_url||'');$('bannerForm').scrollIntoView({behavior:'smooth',block:'center'});};
window.deleteBanner=async id=>{const r=await Swal.fire({icon:'warning',title:'ลบแบนเนอร์นี้?',text:'การลบไม่สามารถย้อนกลับได้',showCancelButton:true,confirmButtonText:'ลบ',cancelButtonText:'ยกเลิก',confirmButtonColor:'#e11d48'});if(!r.isConfirmed)return;const{error}=await sb.from('home_banners').delete().eq('id',id);if(error)return notify('error','ลบไม่สำเร็จ',error.message);if($('bannerId').value===id)resetBannerForm();await loadAll();notify('success','ลบแบนเนอร์แล้ว');};
if($('bannerForm')) $('bannerForm').onsubmit=async e=>{e.preventDefault();try{
  const current=state.banners.find(x=>x.id===$('bannerId').value); let image=$('bannerImageUrl').value.trim()||current?.image_url||null; if($('bannerImageFile').files[0])image=await uploadPublic('site-assets',$('bannerImageFile').files[0],'banners');
  const row={title:$('bannerTitle').value.trim(),highlight_text:$('bannerHighlight').value.trim()||null,description:$('bannerDesc').value.trim()||null,badge_text:$('bannerBadge').value.trim()||null,location_text:$('bannerLocation').value.trim()||null,image_url:image,link_url:$('bannerLink').value.trim()||null,active:$('bannerActive').checked,sort_order:Number($('bannerSort').value||100),updated_at:new Date().toISOString()};
  let q=$('bannerId').value?sb.from('home_banners').update(row).eq('id',$('bannerId').value):sb.from('home_banners').insert(row);const{error}=await q;if(error)throw error;resetBannerForm();await loadAll();notify('success','บันทึกแบนเนอร์แล้ว');
}catch(err){notify('error','บันทึกแบนเนอร์ไม่สำเร็จ',err.message)}};

const CATEGORY_THEME_DOT={rose:'bg-rose-400',teal:'bg-teal-400',indigo:'bg-indigo-400',amber:'bg-amber-400',sky:'bg-sky-400',violet:'bg-violet-400',emerald:'bg-emerald-400',slate:'bg-slate-400'};
function resetCategoryForm(){if(!$('categoryForm'))return;$('categoryForm').reset();$('categoryOriginalId').value='';$('categoryKey').disabled=false;$('categoryTheme').value='rose';$('categorySort').value='100';$('categoryActive').checked=true;}
if($('categoryReset')) $('categoryReset').onclick=resetCategoryForm;
function renderCategoriesManager(){
  if(!$('categoryList')) return; if($('categoryCount')) $('categoryCount').textContent=`${state.categories.filter(x=>x.active).length}/${state.categories.length} เปิด`;
  $('categoryList').innerHTML=state.categories.map(x=>`<div class="flex items-center gap-3 p-3.5 rounded-2xl border border-slate-200 bg-white hover:border-indigo-200 transition"><div class="w-10 h-10 rounded-xl bg-slate-50 border border-slate-100 grid place-items-center text-slate-600"><i class="${esc(x.icon_class||'fas fa-book-open')}"></i></div><div class="min-w-0 flex-1"><div class="flex items-center gap-2"><span class="w-2 h-2 rounded-full ${CATEGORY_THEME_DOT[x.theme]||'bg-sky-400'}"></span><div class="text-[11px] font-semibold text-slate-800 truncate">${esc(x.name_th)}</div><span class="tag">${esc(x.id)}</span></div><div class="text-[9px] text-slate-400 mt-1">${esc(x.name_en||'')} · ลำดับ ${Number(x.sort_order||100)}</div></div><label class="flex items-center gap-1.5 text-[9px] text-slate-500"><input type="checkbox" ${x.active?'checked':''} onchange="toggleCategory('${x.id}',this.checked)"> เปิด</label><button onclick="editCategory('${x.id}')" class="px-2.5 py-2 rounded-lg bg-indigo-50 text-indigo-600 text-[9.5px] font-semibold">แก้ไข</button><button onclick="deleteCategory('${x.id}')" class="px-2.5 py-2 rounded-lg bg-rose-50 text-rose-600 text-[9.5px] font-semibold">ลบ</button></div>`).join('')||'<div class="py-8 text-center text-[10px] text-slate-400">ยังไม่มีหมวดวิชา</div>';
}
window.editCategory=id=>{const x=state.categories.find(v=>v.id===id);if(!x)return;$('categoryOriginalId').value=x.id;$('categoryKey').value=x.id;$('categoryKey').disabled=true;$('categoryNameTh').value=x.name_th||'';$('categoryNameEn').value=x.name_en||'';$('categoryIcon').value=x.icon_class||'';$('categoryTheme').value=x.theme||'sky';$('categorySort').value=x.sort_order??100;$('categoryActive').checked=x.active!==false;$('categoryForm').scrollIntoView({behavior:'smooth',block:'center'});};
window.toggleCategory=async(id,active)=>{const{error}=await sb.from('subject_categories').update({active,updated_at:new Date().toISOString()}).eq('id',id);if(error)return notify('error','เปลี่ยนสถานะไม่สำเร็จ',error.message);await loadAll();};
window.deleteCategory=async id=>{const r=await Swal.fire({icon:'warning',title:'ลบหมวดวิชานี้?',html:'แนะนำให้ <b>ปิดการแสดงผล</b> แทน หากหมวดนี้ยังถูกผูกกับติวเตอร์',showCancelButton:true,confirmButtonText:'ลบถาวร',cancelButtonText:'ยกเลิก',confirmButtonColor:'#e11d48'});if(!r.isConfirmed)return;const{error}=await sb.from('subject_categories').delete().eq('id',id);if(error)return notify('error','ลบไม่สำเร็จ',error.message);if($('categoryOriginalId').value===id)resetCategoryForm();await loadAll();notify('success','ลบหมวดแล้ว');};
if($('categoryForm')) $('categoryForm').onsubmit=async e=>{e.preventDefault();try{
  const original=$('categoryOriginalId').value;const id=$('categoryKey').value.trim().toLowerCase();if(!/^[a-z0-9_-]+$/.test(id))throw new Error('รหัสหมวดใช้ได้เฉพาะ a-z, 0-9, _ และ -');
  const row={id,name_th:$('categoryNameTh').value.trim(),name_en:$('categoryNameEn').value.trim()||null,icon_class:$('categoryIcon').value.trim()||'fas fa-book-open',theme:$('categoryTheme').value,active:$('categoryActive').checked,sort_order:Number($('categorySort').value||100),updated_at:new Date().toISOString()};
  let q; if(original){const {id:_,...upd}=row;q=sb.from('subject_categories').update(upd).eq('id',original);} else {q=sb.from('subject_categories').insert(row);} const{error}=await q;if(error)throw error;resetCategoryForm();await loadAll();notify('success','บันทึกหมวดวิชาแล้ว');
}catch(err){notify('error','บันทึกหมวดไม่สำเร็จ',err.message)}};

function renderTutors(){
  if(!$('tutorList'))return;
  $('tutorList').innerHTML=state.tutors.map(t=>{
    const courseCount=state.courses.filter(c=>c.tutor_id===t.id).length;
    const scheduleCount=state.schedules.filter(s=>s.tutor_id===t.id).length;
    return `<article class="border rounded-2xl p-4 hover:border-sky-200 transition bg-white">
      <div class="flex gap-3">
        <img src="${esc(t.image_url||'')}" onerror="this.style.visibility='hidden'" class="w-14 h-14 rounded-xl object-cover bg-slate-100 border border-slate-100">
        <div class="min-w-0 flex-1">
          <div class="flex items-start justify-between gap-2">
            <div class="min-w-0">
              <div class="font-bold text-slate-800 truncate">${esc(t.display_name)}</div>
              <div class="text-xs text-slate-500 truncate">${esc(t.full_name||'')}</div>
            </div>
            <span class="tag shrink-0">${t.active?'เปิด':'ปิด'}</span>
          </div>
          <div class="mt-2 flex flex-wrap gap-1.5 text-[9px] text-slate-400">
            <span class="px-2 py-1 rounded-lg bg-slate-50 border border-slate-100"><i class="fas fa-book-open mr-1"></i>${courseCount} คอร์ส</span>
            <span class="px-2 py-1 rounded-lg bg-slate-50 border border-slate-100"><i class="far fa-calendar mr-1"></i>${scheduleCount} ช่องเวลา</span>
          </div>
        </div>
      </div>
      <div class="grid grid-cols-[1fr_auto] gap-2 mt-3 pt-3 border-t border-slate-100">
        <button type="button" onclick="editTutor('${t.id}')" class="py-2 rounded-xl bg-sky-50 text-sky-600 hover:bg-sky-100 text-[10.5px] font-semibold"><i class="fas fa-pen mr-1"></i> แก้ไข</button>
        <button type="button" onclick="deleteTutor('${t.id}')" class="w-10 h-9 rounded-xl bg-rose-50 text-rose-500 hover:bg-rose-100" title="ลบติวเตอร์"><i class="far fa-trash-can"></i></button>
      </div>
    </article>`;
  }).join('')||'<p class="text-slate-400">ยังไม่มีติวเตอร์</p>';
}
window.editTutor=id=>{const t=state.tutors.find(x=>x.id===id); if(!t)return; $('tutorId').value=t.id;$('tutorDisplay').value=t.display_name||'';$('tutorFull').value=t.full_name||'';$('tutorRole').value=t.role_text||'';$('tutorImageUrl').value=t.image_url||'';$('tutorEdu').value=(t.education||[]).join('\n');$('tutorAwards').value=(t.awards||[]).join('\n');$('tutorLevels').value=(t.levels||[]).join(',');$('tutorCategories').value=(t.categories||[]).join(',');$('tutorVideo').value=t.video_id||'';$('tutorActive').checked=t.active;window.scrollTo({top:0,behavior:'smooth'});};

window.deleteTutor=async id=>{
  const t=state.tutors.find(x=>x.id===id);if(!t)return;
  const courseCount=state.courses.filter(c=>c.tutor_id===id).length;
  const tutorScheduleIds=new Set(state.schedules.filter(s=>s.tutor_id===id).map(s=>s.id));
  const reservationCount=state.scheduleReservations.filter(r=>tutorScheduleIds.has(r.tutor_schedule_id)&&['reserved','confirmed'].includes(r.status)).length;
  const scheduleCount=tutorScheduleIds.size;

  if(reservationCount>0){
    const result=await Swal.fire({
      icon:'warning',
      title:'ยังลบถาวรไม่ได้',
      html:`<div class="text-left text-sm leading-relaxed text-slate-600">
        <p><b>${esc(t.display_name)}</b> ยังมีรายการจอง/ตารางเรียนที่ใช้งานอยู่ <b>${reservationCount}</b> รายการ</p>
        <p class="mt-2">เพื่อไม่ให้ประวัตินักเรียนและตารางจองสูญหาย ระบบจะให้ <b>ปิดการใช้งานติวเตอร์</b> แทน</p>
      </div>`,
      showCancelButton:true,confirmButtonText:'ปิดการใช้งาน',cancelButtonText:'ยกเลิก',confirmButtonColor:'#0f172a'
    });
    if(!result.isConfirmed)return;
    const{error}=await sb.from('tutors').update({active:false,updated_at:new Date().toISOString()}).eq('id',id);
    if(error)return notify('error','ปิดติวเตอร์ไม่สำเร็จ',error.message);
    await loadAll();notify('success','ปิดการใช้งานติวเตอร์แล้ว','ข้อมูลคอร์สและการจองเดิมยังคงอยู่');
    return;
  }

  const first=await Swal.fire({
    icon:'warning',
    title:`ลบ ${t.display_name}?`,
    html:`<div class="text-left text-sm text-slate-600 space-y-2">
      <p>การลบถาวรจะลบข้อมูลที่ผูกกับติวเตอร์นี้ตามฐานข้อมูลด้วย</p>
      <div class="grid grid-cols-2 gap-2">
        <div class="rounded-xl bg-slate-50 p-3"><div class="text-[9px] text-slate-400">คอร์สที่ผูก</div><div class="font-bold text-slate-700">${courseCount}</div></div>
        <div class="rounded-xl bg-slate-50 p-3"><div class="text-[9px] text-slate-400">ช่องตาราง</div><div class="font-bold text-slate-700">${scheduleCount}</div></div>
      </div>
      <p class="text-[10px] text-amber-600">แนะนำให้เลือก “ปิดใช้งาน” หากต้องการเก็บข้อมูลไว้</p>
    </div>`,
    showDenyButton:true,showCancelButton:true,
    confirmButtonText:'ลบถาวร',denyButtonText:'ปิดใช้งานแทน',cancelButtonText:'ยกเลิก',
    confirmButtonColor:'#e11d48',denyButtonColor:'#0f172a'
  });
  if(first.isDenied){
    const{error}=await sb.from('tutors').update({active:false,updated_at:new Date().toISOString()}).eq('id',id);
    if(error)return notify('error','ปิดติวเตอร์ไม่สำเร็จ',error.message);
    await loadAll();notify('success','ปิดการใช้งานติวเตอร์แล้ว');return;
  }
  if(!first.isConfirmed)return;

  const confirm=await Swal.fire({
    title:'ยืนยันการลบถาวร',
    text:'พิมพ์ DELETE เพื่อยืนยัน',
    input:'text',inputPlaceholder:'DELETE',showCancelButton:true,
    confirmButtonText:'ยืนยันลบ',cancelButtonText:'ยกเลิก',confirmButtonColor:'#e11d48',
    inputValidator:v=>String(v||'').trim().toUpperCase()==='DELETE'?undefined:'กรุณาพิมพ์ DELETE'
  });
  if(!confirm.isConfirmed)return;

  const{error}=await sb.from('tutors').delete().eq('id',id);
  if(error)return notify('error','ลบติวเตอร์ไม่สำเร็จ',error.message);
  if($('tutorId').value===id){$('tutorForm').reset();$('tutorId').value='';}
  await loadAll();notify('success','ลบติวเตอร์แล้ว');
};
$('tutorReset').onclick=()=>{$('tutorForm').reset();$('tutorId').value='';$('tutorActive').checked=true;};
$('tutorForm').onsubmit=async e=>{e.preventDefault();try{let image=$('tutorImageUrl').value.trim()||null;if($('tutorImage').files[0]) image=await uploadPublic('tutor-assets',$('tutorImage').files[0],'tutors');const row={display_name:$('tutorDisplay').value.trim(),full_name:$('tutorFull').value.trim(),role_text:$('tutorRole').value.trim(),image_url:image,education:lines($('tutorEdu').value),awards:lines($('tutorAwards').value),levels:csv($('tutorLevels').value),categories:csv($('tutorCategories').value),video_id:$('tutorVideo').value.trim(),active:$('tutorActive').checked,updated_at:new Date().toISOString()};let q=$('tutorId').value?sb.from('tutors').update(row).eq('id',$('tutorId').value):sb.from('tutors').insert(row);const{error}=await q;if(error)throw error;$('tutorForm').reset();$('tutorId').value='';await loadAll();notify('success','บันทึกติวเตอร์แล้ว');}catch(err){notify('error','บันทึกไม่สำเร็จ',err.message)}};

function fillTutorSelect(){ $('courseTutor').innerHTML='<option value="">เลือกติวเตอร์</option>'+state.tutors.map(t=>`<option value="${t.id}">${esc(t.display_name)}</option>`).join(''); if($('scheduleTutorFilter')){$('scheduleTutorFilter').innerHTML=state.tutors.map(t=>`<option value="${t.id}">${esc(t.display_name)}</option>`).join(''); if(activeScheduleTutorId)$('scheduleTutorFilter').value=activeScheduleTutorId;} }
function renderCourses(){const names=Object.fromEntries(state.tutors.map(t=>[t.id,t.display_name]));$('courseList').innerHTML=state.courses.map(c=>`<button onclick="editCourse('${c.id}')" class="w-full text-left border rounded-2xl p-4 hover:border-purple-300 flex gap-3"><img src="${esc(c.image_url||'')}" class="w-16 h-16 rounded-xl object-cover bg-slate-100"><div class="flex-1"><div class="font-bold">${esc(c.name)}</div><div class="text-xs text-slate-500">${esc(names[c.tutor_id]||'-')} • ${esc(c.short_detail||'')}</div><div class="mt-2 flex gap-2"><span class="tag">${c.course_type}</span>${c.is_university?'<span class="tag">มหาวิทยาลัย</span>':''}<span class="tag">${c.active?'เปิด':'ปิด'}</span></div></div></button>`).join('')||'<p class="text-slate-400">ยังไม่มีคอร์ส</p>';}
window.editCourse=id=>{const c=state.courses.find(x=>x.id===id);if(!c)return;$('courseId').value=c.id;$('courseTutor').value=c.tutor_id;$('courseName').value=c.name||'';$('courseType').value=c.course_type||'content';$('courseShort').value=c.short_detail||'';$('courseFull').value=c.full_description||'';$('courseTarget').value=c.target_text||'';$('courseOutcomes').value=(c.outcomes||[]).join('\n');$('courseSyllabus').value=(c.syllabus||[]).join('\n');$('courseBadge').value=c.badge||'';$('courseImageUrl').value=c.image_url||'';$('courseUni').checked=c.is_university;$('courseActive').checked=c.active;window.scrollTo({top:0,behavior:'smooth'});};
$('courseReset').onclick=()=>$('courseForm').reset();
$('courseForm').onsubmit=async e=>{e.preventDefault();try{let image=$('courseImageUrl').value.trim()||null;if($('courseImage').files[0])image=await uploadPublic('course-assets',$('courseImage').files[0],'courses');const row={tutor_id:$('courseTutor').value,name:$('courseName').value.trim(),course_type:$('courseType').value,short_detail:$('courseShort').value.trim(),full_description:$('courseFull').value.trim(),target_text:$('courseTarget').value.trim(),outcomes:lines($('courseOutcomes').value),syllabus:lines($('courseSyllabus').value),badge:$('courseBadge').value||null,image_url:image,is_university:$('courseUni').checked,active:$('courseActive').checked,updated_at:new Date().toISOString()};let q=$('courseId').value?sb.from('courses').update(row).eq('id',$('courseId').value):sb.from('courses').insert(row);const{error}=await q;if(error)throw error;$('courseForm').reset();$('courseId').value='';await loadAll();notify('success','บันทึกคอร์สแล้ว');}catch(err){notify('error','บันทึกไม่สำเร็จ',err.message)}};


// ---------- Student Reviews ----------
const reviewInitials = name => String(name || '?').trim().slice(0,2);
function reviewImageMarkup(r){
  return r.image_url
    ? `<img src="${esc(r.image_url)}" class="w-14 h-14 rounded-2xl object-cover bg-slate-100 border border-slate-200" onerror="this.outerHTML='<div class=&quot;w-14 h-14 rounded-2xl bg-indigo-50 text-indigo-500 flex items-center justify-center font-bold border border-indigo-100&quot;>${esc(reviewInitials(r.student_name))}</div>'">`
    : `<div class="w-14 h-14 rounded-2xl bg-indigo-50 text-indigo-500 flex items-center justify-center font-bold border border-indigo-100">${esc(reviewInitials(r.student_name))}</div>`;
}
function renderReviews(){
  if(!$('reviewList')) return;
  if($('reviewCourseOptions')) $('reviewCourseOptions').innerHTML=state.courses.filter(c=>c.active).map(c=>`<option value="${esc(c.name)}"></option>`).join('');
  const q=String($('reviewSearch')?.value||'').trim().toLowerCase();
  const rows=state.reviews.filter(r=>!q||[r.student_name,r.school,r.course_name,r.review_text].join(' ').toLowerCase().includes(q));
  if($('reviewCount')) $('reviewCount').textContent=`${rows.length} รายการ`;
  $('reviewList').innerHTML=rows.map(r=>`<div class="border border-slate-200 rounded-2xl p-4 bg-white hover:border-indigo-200 hover:shadow-sm transition">
    <div class="flex items-start gap-3">${reviewImageMarkup(r)}<div class="min-w-0 flex-1"><div class="flex items-start justify-between gap-2"><div><div class="font-bold text-sm truncate">${esc(r.student_name)}</div><div class="text-[10px] text-slate-400 truncate mt-0.5">${esc(r.school||'ไม่ระบุโรงเรียน')}</div></div><div class="flex gap-1">${r.featured?'<span class="tag !bg-amber-50 !text-amber-600">แนะนำ</span>':''}<span class="tag">${r.active?'แสดง':'ซ่อน'}</span></div></div><div class="mt-2 text-[10px] font-bold text-sky-600 truncate"><i class="fas fa-book-open mr-1"></i>${esc(r.course_name||'ไม่ระบุคอร์ส')}</div></div></div>
    <p class="mt-3 text-[10.5px] text-slate-500 leading-relaxed line-clamp-3">${esc(r.review_text)}</p>
    <div class="mt-3 pt-3 border-t border-slate-100 flex items-center justify-between"><span class="text-[10px] text-amber-500">${'★'.repeat(Math.max(1,Math.min(5,Number(r.rating||5))))}</span><div class="flex gap-1"><button onclick="editReview('${r.id}')" class="px-2.5 py-1.5 rounded-lg bg-indigo-50 text-indigo-600 text-[10px] font-bold">แก้ไข</button><button onclick="deleteReview('${r.id}')" class="px-2.5 py-1.5 rounded-lg bg-red-50 text-red-500 text-[10px] font-bold">ลบ</button></div></div>
  </div>`).join('')||'<div class="md:col-span-2 py-12 text-center text-slate-400 text-sm">ยังไม่มีรีวิว</div>';
}
function setReviewPreview(url){
  if(!$('reviewImagePreviewWrap')) return;
  if(url){$('reviewImagePreview').src=url;$('reviewImagePreviewWrap').classList.remove('hidden');}
  else{$('reviewImagePreview').src='';$('reviewImagePreviewWrap').classList.add('hidden');}
}
window.editReview=id=>{
  const r=state.reviews.find(x=>x.id===id);if(!r)return;
  $('reviewId').value=r.id;$('reviewName').value=r.student_name||'';$('reviewSchool').value=r.school||'';$('reviewCourse').value=r.course_name||'';$('reviewText').value=r.review_text||'';$('reviewRating').value=String(r.rating||5);$('reviewSort').value=r.sort_order??100;$('reviewImageUrl').value=r.image_url||'';$('reviewFeatured').checked=!!r.featured;$('reviewActive').checked=r.active!==false;setReviewPreview(r.image_url||'');window.scrollTo({top:0,behavior:'smooth'});
};
window.deleteReview=async id=>{
  const r=state.reviews.find(x=>x.id===id);if(!r)return;
  const ok=await Swal.fire({title:'ลบรีวิวนี้?',text:`${r.student_name} • ${r.course_name||''}`,icon:'warning',showCancelButton:true,confirmButtonText:'ลบ',cancelButtonText:'ยกเลิก',confirmButtonColor:'#ef4444'});if(!ok.isConfirmed)return;
  const{error}=await sb.from('reviews').delete().eq('id',id);if(error)return notify('error','ลบรีวิวไม่สำเร็จ',error.message);await loadAll();notify('success','ลบรีวิวแล้ว');
};
if($('reviewReset')) $('reviewReset').onclick=()=>{ $('reviewForm').reset();$('reviewId').value='';$('reviewRating').value='5';$('reviewSort').value='100';$('reviewActive').checked=true;setReviewPreview(''); };
if($('reviewImageUrl')) $('reviewImageUrl').addEventListener('input',e=>setReviewPreview(e.target.value.trim()));
if($('reviewImage')) $('reviewImage').addEventListener('change',e=>{const f=e.target.files?.[0];if(f)setReviewPreview(URL.createObjectURL(f));});
if($('reviewSearch')) $('reviewSearch').addEventListener('input',renderReviews);
if($('reviewForm')) $('reviewForm').onsubmit=async e=>{e.preventDefault();try{
  let image=$('reviewImageUrl').value.trim()||null;if($('reviewImage').files[0]) image=await uploadPublic('review-assets',$('reviewImage').files[0],'reviews');
  const row={student_name:$('reviewName').value.trim(),school:$('reviewSchool').value.trim()||null,course_name:$('reviewCourse').value.trim()||null,review_text:$('reviewText').value.trim(),image_url:image,rating:Number($('reviewRating').value||5),featured:$('reviewFeatured').checked,active:$('reviewActive').checked,sort_order:Number($('reviewSort').value||100),updated_at:new Date().toISOString()};
  let q=$('reviewId').value?sb.from('reviews').update(row).eq('id',$('reviewId').value):sb.from('reviews').insert(row);const{error}=await q;if(error)throw error;
  $('reviewForm').reset();$('reviewId').value='';$('reviewRating').value='5';$('reviewSort').value='100';$('reviewActive').checked=true;setReviewPreview('');await loadAll();notify('success','บันทึกรีวิวแล้ว');
}catch(err){notify('error','บันทึกรีวิวไม่สำเร็จ',err.message)}};

const pick=(obj,keys)=>{for(const k of keys){if(obj[k]!==undefined&&String(obj[k]).trim()!=='')return obj[k];}return''};
const truthy=v=>['1','true','yes','y','ใช่','แสดง','เปิด','active'].includes(String(v??'').trim().toLowerCase());
if($('reviewImportBtn')) $('reviewImportBtn').onclick=async()=>{
  const file=$('reviewImportFile').files?.[0];if(!file)return notify('warning','กรุณาเลือกไฟล์ Excel','ดาวน์โหลด Template แล้วกรอกข้อมูลก่อนนำเข้า');
  try{
    const wb=XLSX.read(await file.arrayBuffer(),{type:'array'});const ws=wb.Sheets[wb.SheetNames[0]];const raw=XLSX.utils.sheet_to_json(ws,{defval:''});
    if(!raw.length)throw new Error('ไฟล์ไม่มีข้อมูล');
    const rows=[],skipped=[];
    raw.forEach((x,i)=>{
      const name=String(pick(x,['student_name','ชื่อ','ชื่อน้อง','ชื่อผู้เรียน','Name'])).trim();
      const review=String(pick(x,['review_text','รีวิว','ข้อความรีวิว','Review'])).trim();
      if(!name||!review){skipped.push(i+2);return;}
      const rating=Math.max(1,Math.min(5,Number(pick(x,['rating','คะแนน','Rating']))||5));
      rows.push({student_name:name,school:String(pick(x,['school','โรงเรียน','School'])).trim()||null,course_name:String(pick(x,['course_name','คอร์ส','คอร์สที่ลง','Course'])).trim()||null,review_text:review,image_url:String(pick(x,['image_url','รูป','URL รูป','Image URL'])).trim()||null,rating,featured:truthy(pick(x,['featured','แนะนำ','Featured'])),active:String(pick(x,['active','แสดงผล','Active'])).trim()===''?true:truthy(pick(x,['active','แสดงผล','Active'])),sort_order:Number(pick(x,['sort_order','ลำดับ','Sort']))||100,updated_at:new Date().toISOString()});
    });
    if(!rows.length)throw new Error('ไม่พบแถวที่มีชื่อและข้อความรีวิวครบ');
    const sample=rows.slice(0,3).map(r=>`<div class="p-2 rounded-lg bg-slate-50 mb-1"><b>${esc(r.student_name)}</b><br><span class="text-xs text-slate-500">${esc(r.school||'-')} • ${esc(r.course_name||'-')}</span></div>`).join('');
    const confirm=await Swal.fire({title:`นำเข้า ${rows.length} รีวิว?`,html:`<div class="text-left text-sm">${sample}${rows.length>3?`<div class="text-xs text-slate-400 mt-2">และอีก ${rows.length-3} รายการ</div>`:''}${skipped.length?`<div class="mt-3 text-xs text-amber-600">ข้ามแถวที่ข้อมูลไม่ครบ: ${skipped.join(', ')}</div>`:''}</div>`,showCancelButton:true,confirmButtonText:'นำเข้า',cancelButtonText:'ยกเลิก',confirmButtonColor:'#4f46e5'});if(!confirm.isConfirmed)return;
    const{error}=await sb.from('reviews').insert(rows);if(error)throw error;$('reviewImportFile').value='';await loadAll();notify('success',`นำเข้า ${rows.length} รีวิวแล้ว`,skipped.length?`ข้าม ${skipped.length} แถวที่ข้อมูลไม่ครบ`:'' );
  }catch(err){notify('error','นำเข้า Excel ไม่สำเร็จ',err.message)}
};


const DAY_NAMES={1:'จันทร์',2:'อังคาร',3:'พุธ',4:'พฤหัสบดี',5:'ศุกร์',6:'เสาร์',7:'อาทิตย์'};
const timeShort=v=>String(v||'').slice(0,5);
const templateDisplay=t=>t?.label||`${timeShort(t?.start_time)}-${timeShort(t?.end_time)}`;
function scheduleUsed(scheduleId){return state.scheduleReservations.filter(r=>r.tutor_schedule_id===scheduleId&&['reserved','confirmed'].includes(r.status)).reduce((s,r)=>s+Number(r.seats||0),0);}
function activeTutor(){return state.tutors.find(t=>t.id===activeScheduleTutorId)||null;}
function selectedScheduleDays(){return [...document.querySelectorAll('.schedule-day-check:checked')].map(x=>Number(x.value));}
function selectedScheduleTimes(){return [...document.querySelectorAll('.schedule-time-check:checked')].map(x=>x.value);}
function setScheduleDayChecks(values=[]){const set=new Set(values.map(Number));document.querySelectorAll('.schedule-day-check').forEach(x=>x.checked=set.has(Number(x.value)));}
function setScheduleTimeChecks(values=[]){const set=new Set(values);document.querySelectorAll('.schedule-time-check').forEach(x=>x.checked=set.has(x.value));}

function renderTutorPresetPanel(){
  if(!$('scheduleBulkTimes')) return;
  const tutor=activeTutor();
  const activeTemplates=state.scheduleTemplates.filter(t=>t.active);
  $('scheduleBulkTimes').innerHTML=activeTemplates.map(t=>`<label class="cursor-pointer block"><input class="peer sr-only schedule-time-check" type="checkbox" value="${t.id}"><span class="flex items-center justify-between gap-2 px-3 py-2.5 rounded-xl border border-slate-200 bg-white text-[10px] text-slate-600 peer-checked:bg-sky-50 peer-checked:border-sky-300 peer-checked:text-sky-700"><span class="font-semibold truncate">${esc(templateDisplay(t))}</span><span class="text-[9px] opacity-70 whitespace-nowrap">${timeShort(t.start_time)}–${timeShort(t.end_time)}</span></span></label>`).join('')||'<div class="text-[10px] text-slate-400 p-3 bg-slate-50 rounded-xl">ยังไม่มีช่วงเวลาเรียน</div>';

  if($('scheduleCopySource')) $('scheduleCopySource').innerHTML='<option value="">เลือกต้นแบบ</option>'+state.tutors.filter(t=>t.id!==activeScheduleTutorId).map(t=>`<option value="${t.id}">${esc(t.display_name)}</option>`).join('');
  if(!tutor){
    if($('schedulePresetTutorName')) $('schedulePresetTutorName').textContent='เลือกติวเตอร์';
    if($('scheduleTutorSummary')) $('scheduleTutorSummary').textContent='กำหนดตารางประจำรายบุคคล';
    return;
  }
  if($('schedulePresetTutorName')) $('schedulePresetTutorName').textContent=tutor.display_name||'ติวเตอร์';
  const tutorRows=state.schedules.filter(s=>s.tutor_id===tutor.id&&s.status==='available');
  const days=[...new Set(tutorRows.map(s=>Number(s.weekday)))].sort((a,b)=>a-b);
  const booked=tutorRows.filter(s=>scheduleUsed(s.id)>0).length;
  if($('scheduleTutorSummary')) $('scheduleTutorSummary').textContent=days.length?`เปิดสอน ${days.length} วัน • ${tutorRows.length} ช่วง${booked?` • มีจอง ${booked} ช่อง`:''}`:'ยังไม่ได้เปิดตารางสอน';
  if($('scheduleTutorAvatar')){
    if(tutor.image_url) $('scheduleTutorAvatar').innerHTML=`<img src="${esc(tutor.image_url)}" class="w-full h-full object-cover" alt="${esc(tutor.display_name||'Tutor')}">`;
    else $('scheduleTutorAvatar').textContent=String(tutor.display_name||'AW').trim().slice(0,2);
  }
}

function renderScheduleManager(){
  if(!$('scheduleTemplateList'))return;
  $('scheduleTemplateCount').textContent=state.scheduleTemplates.length;
  $('scheduleTemplateList').innerHTML=state.scheduleTemplates.map(t=>`<button type="button" onclick="editScheduleTemplate('${t.id}')" class="w-full text-left border rounded-xl p-3 hover:border-sky-300 ${t.active?'bg-white':'bg-slate-50 opacity-60'}"><div class="flex justify-between items-center gap-2"><div><div class="font-bold text-xs text-slate-700">${esc(templateDisplay(t))}</div><div class="text-[10px] text-slate-400">${timeShort(t.start_time)} → ${timeShort(t.end_time)}</div></div><span class="tag">${t.active?'OPEN':'OFF'}</span></div></button>`).join('')||'<p class="text-xs text-slate-400">ยังไม่มีช่วงเวลา</p>';
  if($('scheduleTutorFilter')){$('scheduleTutorFilter').innerHTML=state.tutors.map(t=>`<option value="${t.id}">${esc(t.display_name)}</option>`).join('');if(activeScheduleTutorId)$('scheduleTutorFilter').value=activeScheduleTutorId;}
  renderTutorPresetPanel();
  renderScheduleCalendar();
}

window.editScheduleTemplate=id=>{const t=state.scheduleTemplates.find(x=>x.id===id);if(!t)return;$('scheduleTemplateId').value=t.id;$('scheduleStart').value=timeShort(t.start_time);$('scheduleEnd').value=timeShort(t.end_time);$('scheduleLabel').value=t.label||'';$('scheduleTemplateActive').checked=t.active;};
$('scheduleTemplateReset').onclick=()=>{$('scheduleTemplateForm').reset();$('scheduleTemplateId').value='';$('scheduleTemplateActive').checked=true;};
$('scheduleTemplateForm').onsubmit=async e=>{e.preventDefault();try{const start=$('scheduleStart').value,end=$('scheduleEnd').value;if(!start||!end||end<=start)return notify('warning','ตรวจสอบช่วงเวลา','เวลาสิ้นสุดต้องมากกว่าเวลาเริ่ม');const row={start_time:start,end_time:end,label:$('scheduleLabel').value.trim()||null,active:$('scheduleTemplateActive').checked,updated_at:new Date().toISOString()};let q=$('scheduleTemplateId').value?sb.from('schedule_templates').update(row).eq('id',$('scheduleTemplateId').value):sb.from('schedule_templates').insert(row);const{error}=await q;if(error)throw error;$('scheduleTemplateForm').reset();$('scheduleTemplateId').value='';$('scheduleTemplateActive').checked=true;await loadAll();notify('success','บันทึกช่วงเวลาแล้ว');}catch(err){notify('error','บันทึกช่วงเวลาไม่สำเร็จ',err.message)}};

if($('scheduleTutorFilter')) $('scheduleTutorFilter').onchange=e=>{
  activeScheduleTutorId=e.target.value;
  setScheduleDayChecks([]);setScheduleTimeChecks([]);
  renderTutorPresetPanel();renderScheduleCalendar();
};
if($('refreshSchedule')) $('refreshSchedule').onclick=loadAll;
if($('scheduleSelectWeekdays')) $('scheduleSelectWeekdays').onclick=()=>setScheduleDayChecks([1,2,3,4,5]);
if($('scheduleSelectWeekend')) $('scheduleSelectWeekend').onclick=()=>setScheduleDayChecks([6,7]);
if($('scheduleSelectAllDays')) $('scheduleSelectAllDays').onclick=()=>setScheduleDayChecks([1,2,3,4,5,6,7]);
if($('scheduleClearDays')) $('scheduleClearDays').onclick=()=>setScheduleDayChecks([]);
if($('scheduleSelectAllTimes')) $('scheduleSelectAllTimes').onclick=()=>setScheduleTimeChecks(state.scheduleTemplates.filter(t=>t.active).map(t=>t.id));
if($('scheduleClearTimes')) $('scheduleClearTimes').onclick=()=>setScheduleTimeChecks([]);

async function applyTutorWeeklyPreset(){
  try{
    if(!activeScheduleTutorId) throw new Error('กรุณาเลือกติวเตอร์');
    const days=selectedScheduleDays(), templates=selectedScheduleTimes();
    if(!days.length) throw new Error('กรุณาเลือกอย่างน้อย 1 วัน');
    if(!templates.length) throw new Error('กรุณาเลือกอย่างน้อย 1 ช่วงเวลา');
    const status=$('scheduleBulkStatus')?.value||'available';
    const capacity=Math.max(1,Number($('scheduleBulkCapacity')?.value||1));
    const note=$('scheduleBulkNote')?.value.trim()||null;
    const replace=$('scheduleReplaceMode')?.checked!==false;
    const tutor=activeTutor();

    for(const weekday of days){
      for(const templateId of templates){
        const existing=state.schedules.find(s=>s.tutor_id===activeScheduleTutorId&&Number(s.weekday)===weekday&&s.time_template_id===templateId);
        if(existing&&status==='available'&&capacity<scheduleUsed(existing.id)) throw new Error(`${DAY_NAMES[weekday]} ${templateDisplay(state.scheduleTemplates.find(t=>t.id===templateId))} มีผู้จองแล้ว ${scheduleUsed(existing.id)} คิว`);
      }
    }

    const confirm=await Swal.fire({
      title:`บันทึกตารางของ ${esc(tutor?.display_name||'ติวเตอร์')}?`,
      html:`<div class="text-left text-sm text-slate-600 space-y-2"><div class="p-3 rounded-xl bg-sky-50 border border-sky-100"><b>${days.map(d=>DAY_NAMES[d]).join(', ')}</b><br><span class="text-xs">${templates.length} ช่วงเวลา • ${status==='available'?'เปิดรับ':'บล็อก'} • รับ ${capacity} คน/ช่วง</span></div>${replace?'<div class="text-xs text-amber-600">โหมดตารางหลัก: ช่วงอื่นที่ไม่ได้เลือกจะถูกปิดรับ แต่การจองเดิมไม่ถูกลบ</div>':''}</div>`,
      showCancelButton:true,confirmButtonText:'บันทึกตาราง',cancelButtonText:'ยกเลิก',confirmButtonColor:'#0f172a'
    });
    if(!confirm.isConfirmed)return;

    const now=new Date().toISOString();
    if(replace){
      const {error}=await sb.from('tutor_schedules').update({status:'blocked',updated_at:now}).eq('tutor_id',activeScheduleTutorId);
      if(error) throw error;
    }
    const rows=[];
    for(const weekday of days) for(const time_template_id of templates) rows.push({tutor_id:activeScheduleTutorId,weekday,time_template_id,status,capacity,note,updated_at:now});
    const {error}=await sb.from('tutor_schedules').upsert(rows,{onConflict:'tutor_id,weekday,time_template_id'});
    if(error)throw error;
    await loadAll();
    notify('success','บันทึกตารางประจำติวเตอร์แล้ว',`${tutor?.display_name||''}: ${days.length} วัน × ${templates.length} ช่วงเวลา`);
  }catch(err){notify('error','บันทึกตารางไม่สำเร็จ',err.message)}
}
if($('scheduleApplyPreset')) $('scheduleApplyPreset').onclick=applyTutorWeeklyPreset;

async function copyTutorWeeklySchedule(){
  try{
    const sourceId=$('scheduleCopySource')?.value;
    if(!sourceId) throw new Error('กรุณาเลือกติวเตอร์ต้นแบบ');
    if(!activeScheduleTutorId||sourceId===activeScheduleTutorId) throw new Error('กรุณาเลือกติวเตอร์ปลายทาง');
    const source=state.tutors.find(t=>t.id===sourceId),target=activeTutor();
    const sourceRows=state.schedules.filter(s=>s.tutor_id===sourceId);
    if(!sourceRows.length) throw new Error('ติวเตอร์ต้นแบบยังไม่มีตาราง');
    const confirm=await Swal.fire({title:'คัดลอกตาราง?',html:`<div class="text-sm text-slate-600">คัดลอกจาก <b>${esc(source?.display_name||'')}</b> → <b>${esc(target?.display_name||'')}</b><br><span class="text-xs text-slate-400">ตารางเดิมของปลายทางจะถูกปิดก่อน แล้วเปิดตามต้นแบบ</span></div>`,showCancelButton:true,confirmButtonText:'คัดลอก',cancelButtonText:'ยกเลิก',confirmButtonColor:'#4f46e5'});
    if(!confirm.isConfirmed)return;
    const now=new Date().toISOString();
    let q=await sb.from('tutor_schedules').update({status:'blocked',updated_at:now}).eq('tutor_id',activeScheduleTutorId);if(q.error)throw q.error;
    const rows=sourceRows.map(src=>{
      const targetRow=state.schedules.find(s=>s.tutor_id===activeScheduleTutorId&&Number(s.weekday)===Number(src.weekday)&&s.time_template_id===src.time_template_id);
      const used=targetRow?scheduleUsed(targetRow.id):0;
      return {tutor_id:activeScheduleTutorId,weekday:Number(src.weekday),time_template_id:src.time_template_id,status:src.status,capacity:Math.max(Number(src.capacity||1),used),note:src.note||null,updated_at:now};
    });
    q=await sb.from('tutor_schedules').upsert(rows,{onConflict:'tutor_id,weekday,time_template_id'});if(q.error)throw q.error;
    await loadAll();notify('success','คัดลอกตารางแล้ว',`${source?.display_name||''} → ${target?.display_name||''}`);
  }catch(err){notify('error','คัดลอกตารางไม่สำเร็จ',err.message)}
}
if($('scheduleCopyBtn')) $('scheduleCopyBtn').onclick=copyTutorWeeklySchedule;

async function closeTutorWeek(){
  try{
    if(!activeScheduleTutorId)throw new Error('กรุณาเลือกติวเตอร์');
    const tutor=activeTutor();
    const confirm=await Swal.fire({icon:'warning',title:`ปิดรับทั้งสัปดาห์ของ ${esc(tutor?.display_name||'ติวเตอร์')}?`,text:'รายการจองเดิมจะยังอยู่ แต่จะไม่เปิดรับการจองใหม่ทุกช่วงเวลา',showCancelButton:true,confirmButtonText:'ปิดรับทั้งสัปดาห์',cancelButtonText:'ยกเลิก',confirmButtonColor:'#e11d48'});
    if(!confirm.isConfirmed)return;
    const {error}=await sb.from('tutor_schedules').update({status:'blocked',updated_at:new Date().toISOString()}).eq('tutor_id',activeScheduleTutorId);if(error)throw error;
    await loadAll();notify('success','ปิดรับทั้งสัปดาห์แล้ว');
  }catch(err){notify('error','ดำเนินการไม่สำเร็จ',err.message)}
}
if($('scheduleCloseWeekBtn')) $('scheduleCloseWeekBtn').onclick=closeTutorWeek;

function renderScheduleCalendar(){
  const el=$('scheduleCalendar');if(!el)return;
  const templates=state.scheduleTemplates.filter(t=>t.active);
  if(!activeScheduleTutorId||!templates.length){el.innerHTML='<div class="py-12 text-center text-slate-400 text-sm">เพิ่มติวเตอร์และช่วงเวลาก่อน</div>';return;}
  const days=[1,2,3,4,5,6,7];
  let open=0,booked=0,blocked=0;
  const header='<div class="grid grid-cols-[130px_repeat(7,minmax(100px,1fr))] gap-2 mb-2"><div class="p-2 text-xs font-bold text-slate-400">เวลา</div>'+days.map(d=>`<div class="p-2 text-center text-xs font-bold text-slate-600 bg-slate-50 rounded-xl">${DAY_NAMES[d]}</div>`).join('')+'</div>';
  const rows=templates.map(t=>`<div class="grid grid-cols-[130px_repeat(7,minmax(100px,1fr))] gap-2 mb-2"><div class="p-3 rounded-xl bg-slate-50 border border-slate-100"><div class="font-bold text-xs">${esc(templateDisplay(t))}</div><div class="text-[9px] text-slate-400">${timeShort(t.start_time)}-${timeShort(t.end_time)}</div></div>${days.map(d=>{const s=state.schedules.find(x=>x.tutor_id===activeScheduleTutorId&&Number(x.weekday)===d&&x.time_template_id===t.id);if(!s){blocked++;return `<button type="button" onclick="editScheduleCell(${d},'${t.id}')" class="schedule-cell rounded-xl border border-dashed border-slate-200 bg-slate-50 text-slate-400 p-2"><i class="fas fa-plus text-xs"></i><div class="text-[9px] mt-1">ยังไม่เปิด</div></button>`;}const used=scheduleUsed(s.id),remain=Math.max(0,Number(s.capacity||1)-used);if(s.status==='blocked'){blocked++;return `<button type="button" onclick="editScheduleCell(${d},'${t.id}')" class="schedule-cell rounded-xl border border-slate-200 bg-slate-100 text-slate-500 p-2"><i class="fas fa-ban text-xs"></i><div class="text-[9px] mt-1">บล็อก</div>${used?`<div class="text-[8px] text-amber-600 mt-1">มีจอง ${used}</div>`:''}</button>`;}open++;if(used>0)booked++;return `<button type="button" onclick="editScheduleCell(${d},'${t.id}')" class="schedule-cell rounded-xl border ${used>0?'border-amber-200 bg-amber-50':'border-emerald-200 bg-emerald-50'} p-2 text-left"><div class="flex justify-between"><i class="fas fa-circle ${used>0?'text-amber-400':'text-emerald-400'} text-[8px]"></i><span class="text-[9px] font-bold ${used>0?'text-amber-700':'text-emerald-700'}">${remain}/${s.capacity}</span></div><div class="text-[9px] mt-2 font-bold text-slate-600">${used>0?'มีการจอง':'เปิดรับ'}</div></button>`;}).join('')}</div>`).join('');
  el.innerHTML=header+rows;
  $('scheduleStatOpen').textContent=open;$('scheduleStatBooked').textContent=booked;$('scheduleStatBlocked').textContent=blocked;
}

window.editScheduleCell=async(weekday,templateId)=>{
  const t=state.scheduleTemplates.find(x=>x.id===templateId);
  let s=state.schedules.find(x=>x.tutor_id===activeScheduleTutorId&&Number(x.weekday)===Number(weekday)&&x.time_template_id===templateId);
  const used=s?scheduleUsed(s.id):0;
  const tutor=activeTutor();
  const result=await Swal.fire({title:`${esc(tutor?.display_name||'')} • ${DAY_NAMES[weekday]} • ${templateDisplay(t)}`,html:`<div class="text-left space-y-3"><label class="text-xs font-bold text-slate-600">สถานะ<select id="swalScheduleStatus" class="input mt-1"><option value="available" ${!s||s.status==='available'?'selected':''}>เปิดรับ</option><option value="blocked" ${s?.status==='blocked'?'selected':''}>บล็อก</option></select></label><label class="text-xs font-bold text-slate-600">จำนวนคิวที่รับพร้อมกัน<input id="swalScheduleCapacity" type="number" min="1" max="100" class="input mt-1" value="${s?.capacity||1}"></label><label class="text-xs font-bold text-slate-600">หมายเหตุ<input id="swalScheduleNote" class="input mt-1" value="${esc(s?.note||'')}"></label>${used?`<div class="bg-amber-50 border border-amber-100 rounded-xl p-3 text-xs text-amber-700">มีการจองแล้ว ${used} คิว การลดจำนวนคิวต่ำกว่านี้จะไม่สามารถบันทึกได้</div>`:''}</div>`,showCancelButton:true,confirmButtonText:'บันทึก',cancelButtonText:'ยกเลิก',confirmButtonColor:'#0ea5e9',preConfirm:()=>({status:document.getElementById('swalScheduleStatus').value,capacity:Number(document.getElementById('swalScheduleCapacity').value||1),note:document.getElementById('swalScheduleNote').value.trim()})});
  if(!result.isConfirmed)return;
  try{
    if(result.value.capacity<used)throw new Error(`มีผู้จองแล้ว ${used} คิว`);
    const row={tutor_id:activeScheduleTutorId,weekday:Number(weekday),time_template_id:templateId,status:result.value.status,capacity:result.value.capacity,note:result.value.note||null,updated_at:new Date().toISOString()};
    const q=s?sb.from('tutor_schedules').update(row).eq('id',s.id):sb.from('tutor_schedules').insert(row);const{error}=await q;if(error)throw error;await loadAll();
  }catch(err){notify('error','บันทึกตารางไม่สำเร็จ',err.message)}
};



// ---------- Tutor Recruitment ----------
const TA_STATUS_LABELS={new:'ใบสมัครใหม่',reviewing:'กำลังตรวจสอบ',interview:'สัมภาษณ์ / ทดลองสอน',accepted:'ผ่านการพิจารณา',rejected:'ไม่ผ่าน',withdrawn:'ยกเลิก'};
const TA_DAY_LABELS={mon:'จ.',tue:'อ.',wed:'พ.',thu:'พฤ.',fri:'ศ.',sat:'ส.',sun:'อา.'};
const taArr=v=>Array.isArray(v)?v:[];
const taStatusClass=s=>({new:'bg-sky-50 text-sky-700',reviewing:'bg-amber-50 text-amber-700',interview:'bg-violet-50 text-violet-700',accepted:'bg-emerald-50 text-emerald-700',rejected:'bg-rose-50 text-rose-700',withdrawn:'bg-slate-100 text-slate-600'}[s]||'bg-slate-100 text-slate-600');
function renderTutorApplications(){
  if(!$('tutorApplicationRows'))return;
  const all=state.tutorApplications||[];
  if($('taStatAll'))$('taStatAll').textContent=all.length;
  if($('taStatNew'))$('taStatNew').textContent=all.filter(x=>x.status==='new').length;
  if($('taStatReview'))$('taStatReview').textContent=all.filter(x=>x.status==='reviewing').length;
  if($('taStatInterview'))$('taStatInterview').textContent=all.filter(x=>x.status==='interview').length;
  if($('taStatAccepted'))$('taStatAccepted').textContent=all.filter(x=>x.status==='accepted').length;
  const q=String($('tutorApplicationSearch')?.value||'').trim().toLowerCase(), f=$('tutorApplicationStatusFilter')?.value||'all';
  const list=all.filter(x=>{const hay=[x.application_no,x.first_name,x.last_name,x.nickname,x.phone,x.email,...taArr(x.subjects)].join(' ').toLowerCase();return(f==='all'||x.status===f)&&(!q||hay.includes(q));});
  $('tutorApplicationRows').innerHTML=list.map(x=>{
    const days=taArr(x.availability).filter(a=>a?.day).map(a=>TA_DAY_LABELS[a.day]||a.day).join(' ');
    return `<tr><td class="text-[10px] text-slate-500">${new Date(x.created_at).toLocaleDateString('th-TH')}</td><td><span class="font-mono text-[10px] font-semibold text-slate-600">${esc(x.application_no)}</span></td><td><b>${esc(x.first_name)} ${esc(x.last_name)}</b><div class="text-[10px] text-slate-400">${esc(x.nickname||'-')} • ${esc(x.current_occupation||'-')}</div></td><td><div class="text-[10px]">${esc(x.phone)}</div><div class="text-[9px] text-slate-400">${esc(x.email)}</div></td><td><div class="flex flex-wrap gap-1">${taArr(x.subjects).slice(0,4).map(v=>`<span class="tag">${esc(v)}</span>`).join('')||'<span class="text-slate-300">-</span>'}</div></td><td class="text-[10px] text-slate-500">${esc(days||'-')}</td><td><span class="inline-flex px-2 py-1 rounded-full text-[9px] font-semibold ${taStatusClass(x.status)}">${esc(TA_STATUS_LABELS[x.status]||x.status)}</span></td><td class="text-right"><button onclick="viewTutorApplication('${x.id}')" class="px-2.5 py-1.5 rounded-lg bg-slate-900 text-white text-[10px] font-semibold">เปิดใบสมัคร</button></td></tr>`;
  }).join('')||'<tr><td colspan="8" class="py-10 text-center text-slate-400">ไม่พบใบสมัครติวเตอร์</td></tr>';
}
if($('tutorApplicationSearch'))$('tutorApplicationSearch').oninput=renderTutorApplications;
if($('tutorApplicationStatusFilter'))$('tutorApplicationStatusFilter').onchange=renderTutorApplications;
if($('refreshTutorApplications'))$('refreshTutorApplications').onclick=loadAll;

function taEducationHtml(items){return taArr(items).map((x,i)=>`<div class="p-3 rounded-xl border border-slate-100 bg-slate-50/70"><div class="text-[10px] font-semibold text-slate-700">${esc(x.institution||'-')}</div><div class="text-[9px] text-slate-500 mt-1">${esc([x.degree,x.major,x.year].filter(Boolean).join(' • ')||'-')}</div>${x.detail?`<div class="text-[9px] text-slate-400 mt-1">${esc(x.detail)}</div>`:''}</div>`).join('')||'<div class="text-[10px] text-slate-400">ไม่มีข้อมูล</div>';}
function taWorkHtml(items){return taArr(items).map(x=>`<div class="p-3 rounded-xl border border-slate-100 bg-slate-50/70"><div class="text-[10px] font-semibold text-slate-700">${esc(x.organization||x.role||'-')}</div><div class="text-[9px] text-slate-500 mt-1">${esc([x.role,x.period,x.subject].filter(Boolean).join(' • ')||'-')}</div>${x.detail?`<div class="text-[9px] text-slate-400 mt-1 leading-relaxed">${esc(x.detail)}</div>`:''}</div>`).join('')||'<div class="text-[10px] text-slate-400">ไม่มีข้อมูล</div>';}
function taAvailabilityHtml(items){return taArr(items).map(a=>`<span class="tag">${esc(TA_DAY_LABELS[a.day]||a.day)} ${esc(a.start||'')}–${esc(a.end||'')}</span>`).join(' ')||'<span class="text-slate-400">-</span>';}
window.openTutorApplicationFile=async(id,field)=>{const a=state.tutorApplications.find(x=>x.id===id),path=a?.[field];if(!path)return notify('warning','ไม่มีไฟล์แนบ');const{data,error}=await sb.storage.from('tutor-application-assets').createSignedUrl(path,300);if(error)return notify('error','เปิดไฟล์ไม่ได้',error.message);window.open(data.signedUrl,'_blank','noopener');};
window.prefillTutorFromApplication=async id=>{const a=state.tutorApplications.find(x=>x.id===id);if(!a)return;let photoUrl='';if(a.profile_photo_path){try{const d=await sb.storage.from('tutor-application-assets').download(a.profile_photo_path);if(!d.error&&d.data){const ext=(d.data.type?.split('/')[1]||'jpg').replace('jpeg','jpg');const path=`tutors/from-application-${a.id}.${ext}`;const up=await sb.storage.from('tutor-assets').upload(path,d.data,{contentType:d.data.type,upsert:true});if(!up.error)photoUrl=sb.storage.from('tutor-assets').getPublicUrl(path).data.publicUrl;}}catch(e){console.warn(e)}}$('tutorId').value='';$('tutorDisplay').value=a.nickname?`พี่${a.nickname}`:'';$('tutorFull').value=`${a.first_name||''} ${a.last_name||''}`.trim();$('tutorRole').value=taArr(a.subjects).join(' / ');$('tutorImageUrl').value=photoUrl;$('tutorEdu').value=taArr(a.education).map(x=>[x.degree,x.major,x.institution,x.year].filter(Boolean).join(' • ')).join('\n');$('tutorAwards').value=a.achievements||'';$('tutorLevels').value=taArr(a.levels).join(',');$('tutorCategories').value=taArr(a.subjects).join(',');$('tutorActive').checked=false;Swal.close();const nav=document.querySelector('.nav[data-section="tutors"]');if(nav)nav.click();setTimeout(()=>$('tutorForm')?.scrollIntoView({behavior:'smooth',block:'start'}),100);notify('success','นำข้อมูลมาใส่ฟอร์มติวเตอร์แล้ว','ตรวจสอบข้อมูลและกดบันทึกเมื่อพร้อม');};
window.viewTutorApplication=async id=>{const a=state.tutorApplications.find(x=>x.id===id);if(!a)return;const fileBtns=[['profile_photo_path','รูปโปรไฟล์','fa-image'],['resume_path','Resume / CV','fa-file-pdf'],['portfolio_path','Portfolio','fa-folder-open'],['transcript_path','Transcript','fa-file-lines']].filter(([f])=>a[f]).map(([f,l,ic])=>`<button type="button" onclick="openTutorApplicationFile('${a.id}','${f}')" class="px-3 py-2 rounded-xl bg-slate-100 text-slate-600 text-[10px] font-semibold"><i class="far ${ic} mr-1"></i>${l}</button>`).join('');const result=await Swal.fire({title:`${esc(a.nickname||a.first_name)} • ${esc(a.application_no)}`,width:820,html:`<div class="text-left max-h-[68vh] overflow-y-auto pr-1 space-y-4"><div class="grid md:grid-cols-2 gap-3"><div class="p-4 rounded-2xl bg-slate-50 border border-slate-100"><div class="text-[9px] uppercase tracking-wider text-slate-400 font-semibold">Personal</div><div class="text-[12px] font-semibold text-slate-800 mt-1">${esc(a.first_name)} ${esc(a.last_name)} (${esc(a.nickname)})</div><div class="text-[10px] text-slate-500 mt-2 leading-relaxed">${esc(a.phone)}<br>${esc(a.email)}${a.line_id?`<br>LINE: ${esc(a.line_id)}`:''}${a.province?`<br>${esc(a.province)}`:''}</div><div class="text-[10px] text-slate-500 mt-2">${esc(a.current_occupation||'-')}</div></div><div class="p-4 rounded-2xl bg-sky-50 border border-sky-100"><div class="text-[9px] uppercase tracking-wider text-sky-500 font-semibold">Teaching</div><div class="flex flex-wrap gap-1 mt-2">${taArr(a.subjects).map(v=>`<span class="tag">${esc(v)}</span>`).join('')}</div><div class="text-[10px] text-sky-800 mt-2">ระดับ: ${esc(taArr(a.levels).join(', ')||'-')}</div><div class="text-[10px] text-sky-800 mt-1">รูปแบบ: ${esc(taArr(a.teaching_modes).join(', ')||'-')} • ประสบการณ์ ${Number(a.teaching_experience_years||0)} ปี</div></div></div>${a.intro?`<div><div class="text-[10px] font-semibold text-slate-600 mb-1">แนะนำตัว</div><div class="text-[10px] leading-relaxed text-slate-500 whitespace-pre-line">${esc(a.intro)}</div></div>`:''}<div class="grid md:grid-cols-2 gap-3"><div><div class="text-[10px] font-semibold text-slate-600 mb-2">การศึกษา</div><div class="space-y-2">${taEducationHtml(a.education)}</div></div><div><div class="text-[10px] font-semibold text-slate-600 mb-2">ประสบการณ์</div><div class="space-y-2">${taWorkHtml(a.work_experience)}</div></div></div>${a.achievements?`<div><div class="text-[10px] font-semibold text-slate-600 mb-1">รางวัล / ผลงาน</div><div class="text-[10px] leading-relaxed text-slate-500 whitespace-pre-line">${esc(a.achievements)}</div></div>`:''}<div><div class="text-[10px] font-semibold text-slate-600 mb-2">วันที่สะดวก</div><div class="flex flex-wrap gap-1">${taAvailabilityHtml(a.availability)}</div></div><div class="grid md:grid-cols-2 gap-3">${a.teaching_style?`<div class="p-3 rounded-xl bg-slate-50"><div class="text-[9px] font-semibold text-slate-500">สไตล์การสอน</div><div class="text-[10px] text-slate-600 mt-1 leading-relaxed">${esc(a.teaching_style)}</div></div>`:''}${a.why_join?`<div class="p-3 rounded-xl bg-slate-50"><div class="text-[9px] font-semibold text-slate-500">เหตุผลที่อยากร่วมทีม</div><div class="text-[10px] text-slate-600 mt-1 leading-relaxed">${esc(a.why_join)}</div></div>`:''}</div>${fileBtns?`<div><div class="text-[10px] font-semibold text-slate-600 mb-2">ไฟล์แนบ</div><div class="flex flex-wrap gap-2">${fileBtns}</div></div>`:''}<div class="grid md:grid-cols-2 gap-3 pt-3 border-t border-slate-100"><label class="text-[10px] font-semibold text-slate-600">สถานะ<select id="taStatus" class="input mt-1"><option value="new" ${a.status==='new'?'selected':''}>ใบสมัครใหม่</option><option value="reviewing" ${a.status==='reviewing'?'selected':''}>กำลังตรวจสอบ</option><option value="interview" ${a.status==='interview'?'selected':''}>สัมภาษณ์ / ทดลองสอน</option><option value="accepted" ${a.status==='accepted'?'selected':''}>ผ่านการพิจารณา</option><option value="rejected" ${a.status==='rejected'?'selected':''}>ไม่ผ่าน</option><option value="withdrawn" ${a.status==='withdrawn'?'selected':''}>ยกเลิก</option></select></label><label class="text-[10px] font-semibold text-slate-600">ข้อความที่ผู้สมัครเห็น<textarea id="taPublicNote" class="input mt-1 h-20">${esc(a.public_status_note||'')}</textarea></label></div><label class="text-[10px] font-semibold text-slate-600">บันทึกภายใน Manager<textarea id="taManagerNote" class="input mt-1 h-24">${esc(a.manager_notes||'')}</textarea></label>${a.additional_note?`<div class="p-3 rounded-xl bg-amber-50 border border-amber-100 text-[10px] text-amber-800"><b>ข้อความเพิ่มเติม:</b> ${esc(a.additional_note)}</div>`:''}</div>`,showCancelButton:true,showDenyButton:true,confirmButtonText:'บันทึกสถานะ',denyButtonText:'สร้างเป็นติวเตอร์',cancelButtonText:'ปิด',confirmButtonColor:'#0ea5e9',denyButtonColor:'#0f172a',customClass:{popup:'rounded-[1.5rem]'},preConfirm:()=>({status:document.getElementById('taStatus').value,public_status_note:document.getElementById('taPublicNote').value.trim()||null,manager_notes:document.getElementById('taManagerNote').value.trim()||null})});if(result.isDenied)return prefillTutorFromApplication(id);if(!result.isConfirmed)return;try{const session=(await sb.auth.getSession()).data.session;const row={...result.value,reviewed_by:session?.user?.id||null,reviewed_at:new Date().toISOString(),updated_at:new Date().toISOString()};const{error}=await sb.from('tutor_applications').update(row).eq('id',id);if(error)throw error;await loadAll();notify('success','บันทึกใบสมัครติวเตอร์แล้ว');}catch(err){notify('error','บันทึกไม่สำเร็จ',err.message)}};

// ---------- Enrollments ----------
const statusLabel = s => ({pending_payment_verification:'รอตรวจสอบ',confirmed:'ยืนยันแล้ว',rejected:'ไม่ผ่าน',cancelled:'ยกเลิก'}[s]||s||'-');
const paymentLabel = s => ({pending:'รอตรวจ',paid:'ชำระแล้ว',rejected:'ไม่ผ่าน',cancelled:'ยกเลิก'}[s]||s||'-');
function enrollmentPayment(id){return state.payments.find(p=>p.enrollment_id===id)||null;}
function renderEnrollments(){
  if(!$('enrollmentRows')) return;
  const q=String($('enrollmentSearch')?.value||'').trim().toLowerCase();
  const f=$('enrollmentStatusFilter')?.value||'all';
  const list=state.enrollments.filter(e=>{
    if(f!=='all'&&e.status!==f)return false;
    if(!q)return true;
    return [e.receipt_no,e.fullname,e.nickname,e.phone,e.course_text,e.tutor_text,e.school].join(' ').toLowerCase().includes(q);
  });
  $('enrollmentStatAll').textContent=state.enrollments.length;
  $('enrollmentStatPending').textContent=state.enrollments.filter(x=>x.status==='pending_payment_verification').length;
  $('enrollmentStatConfirmed').textContent=state.enrollments.filter(x=>x.status==='confirmed').length;
  $('enrollmentStatClosed').textContent=state.enrollments.filter(x=>['rejected','cancelled'].includes(x.status)).length;
  $('enrollmentRows').innerHTML=list.map(e=>{const p=enrollmentPayment(e.id);return `<tr><td class="font-mono text-[10px]">${esc(e.receipt_no||'-')}</td><td><b>${esc(e.fullname)}</b><div class="text-[10px] text-slate-400">${esc(e.phone||'')} ${e.school?'• '+esc(e.school):''}</div></td><td><div class="font-medium text-xs">${esc(e.course_text||'-')}</div><div class="text-[10px] text-sky-600 mt-1">${esc(e.tutor_text||'-')}</div></td><td class="text-xs max-w-[190px]">${esc(e.time_text||'-')}</td><td class="font-semibold">${Number(e.amount_quoted||0).toLocaleString()} ฿</td><td><span class="tag">${esc(paymentLabel(p?.status))}</span></td><td><span class="tag">${esc(statusLabel(e.status))}</span></td><td class="text-right"><button onclick="viewEnrollment('${e.id}')" class="px-2.5 py-1.5 rounded-lg bg-sky-50 text-sky-600 text-[10px] font-semibold">ดูรายละเอียด</button></td></tr>`}).join('')||'<tr><td colspan="8" class="py-10 text-center text-slate-400">ไม่พบรายการ</td></tr>';
}
window.viewEnrollment=async id=>{const e=state.enrollments.find(x=>x.id===id);if(!e)return;const p=enrollmentPayment(id);const r=await Swal.fire({title:esc(e.fullname),width:680,html:`<div class="text-left grid sm:grid-cols-2 gap-2 text-xs"><div class="p-3 rounded-xl bg-slate-50"><b>เลขที่</b><br>${esc(e.receipt_no||'-')}</div><div class="p-3 rounded-xl bg-slate-50"><b>โทร</b><br>${esc(e.phone||'-')}</div><div class="p-3 rounded-xl bg-slate-50 sm:col-span-2"><b>คอร์ส</b><br>${esc(e.course_text||'-')}</div><div class="p-3 rounded-xl bg-slate-50"><b>ติวเตอร์</b><br>${esc(e.tutor_text||'-')}</div><div class="p-3 rounded-xl bg-slate-50"><b>เวลา</b><br>${esc(e.time_text||'-')}</div><div class="p-3 rounded-xl bg-slate-50"><b>ยอด</b><br>${Number(e.amount_quoted||0).toLocaleString()} บาท</div><div class="p-3 rounded-xl bg-slate-50"><b>การชำระเงิน</b><br>${esc(paymentLabel(p?.status))}</div></div><label class="block text-left text-xs font-bold text-slate-500 mt-4">สถานะใบสมัคร<select id="swalEnrollmentStatus" class="input mt-1"><option value="pending_payment_verification" ${e.status==='pending_payment_verification'?'selected':''}>รอตรวจสอบ</option><option value="confirmed" ${e.status==='confirmed'?'selected':''}>ยืนยันแล้ว</option><option value="rejected" ${e.status==='rejected'?'selected':''}>ไม่ผ่าน</option><option value="cancelled" ${e.status==='cancelled'?'selected':''}>ยกเลิก</option></select></label>`,showCancelButton:true,showDenyButton:!!e.receipt_token,confirmButtonText:'บันทึกสถานะ',denyButtonText:'ดาวน์โหลดใบเสร็จ',cancelButtonText:'ปิด',confirmButtonColor:'#0ea5e9',preConfirm:()=>document.getElementById('swalEnrollmentStatus').value});if(r.isDenied&&e.receipt_token)return window.AreWarinReceipt.download(e.receipt_token);if(!r.isConfirmed)return;await setEnrollmentStatus(id,r.value);};
async function setEnrollmentStatus(id,status){try{const {error}=await sb.from('enrollments').update({status,updated_at:new Date().toISOString()}).eq('id',id);if(error)throw error;if(['cancelled','rejected'].includes(status))await sb.from('schedule_reservations').update({status:'cancelled',updated_at:new Date().toISOString()}).eq('enrollment_id',id);if(status==='confirmed')await sb.from('schedule_reservations').update({status:'confirmed',updated_at:new Date().toISOString()}).eq('enrollment_id',id).neq('status','cancelled');await loadAll();notify('success','อัปเดตสถานะแล้ว');}catch(err){notify('error','อัปเดตไม่สำเร็จ',err.message)}}
if($('enrollmentSearch')) $('enrollmentSearch').oninput=renderEnrollments;
if($('enrollmentStatusFilter')) $('enrollmentStatusFilter').onchange=renderEnrollments;
if($('refreshEnrollments')) $('refreshEnrollments').onclick=loadAll;

// ---------- Speaker Requests ----------
const speakerStatusLabel=s=>({pending:'รอติดต่อ',contacted:'ติดต่อแล้ว',quoted:'เสนอราคาแล้ว',confirmed:'ยืนยันงาน',cancelled:'ยกเลิก'}[s]||s||'-');
function renderSpeakers(){if(!$('speakerRows'))return;const q=String($('speakerSearch')?.value||'').trim().toLowerCase(),f=$('speakerStatusFilter')?.value||'all';const list=state.speakers.filter(x=>(f==='all'||x.status===f)&&(!q||[x.organization,x.coordinator_name,x.phone,x.subject,x.topic,x.location_text].join(' ').toLowerCase().includes(q)));$('speakerRows').innerHTML=list.map(x=>`<tr><td class="text-[10px] text-slate-500">${new Date(x.created_at).toLocaleDateString('th-TH')}</td><td><b>${esc(x.organization)}</b><div class="text-[10px] text-slate-400">${esc(x.coordinator_name)} • ${esc(x.phone)}</div></td><td><div class="text-xs font-medium">${esc(x.subject)}</div><div class="text-[10px] text-slate-500 mt-1">${esc(x.topic)}</div></td><td><div class="text-xs">${esc(x.event_datetime_text)}</div><div class="text-[10px] text-slate-400 mt-1">${esc(x.location_text)}</div></td><td class="text-xs">${esc(x.budget_text||'-')}</td><td>${x.wants_quotation?'<span class="tag">ต้องการ</span>':'<span class="tag">ไม่ต้องการ</span>'}</td><td><span class="tag">${esc(speakerStatusLabel(x.status))}</span></td><td class="text-right"><button onclick="viewSpeaker('${x.id}')" class="px-2.5 py-1.5 rounded-lg bg-emerald-50 text-emerald-700 text-[10px] font-semibold">จัดการ</button></td></tr>`).join('')||'<tr><td colspan="8" class="py-10 text-center text-slate-400">ไม่มีคำขอ</td></tr>';}
window.viewSpeaker=async id=>{const x=state.speakers.find(v=>v.id===id);if(!x)return;const r=await Swal.fire({title:esc(x.organization),width:700,html:`<div class="text-left space-y-2 text-xs"><div class="grid sm:grid-cols-2 gap-2"><div class="p-3 bg-slate-50 rounded-xl"><b>ผู้ประสานงาน</b><br>${esc(x.coordinator_name)}<br>${esc(x.phone)}<br>${esc(x.email||'')}</div><div class="p-3 bg-slate-50 rounded-xl"><b>วิทยากร</b><br>${esc(x.tutor_name||'ไม่ระบุ')}</div><div class="p-3 bg-slate-50 rounded-xl sm:col-span-2"><b>หัวข้อ</b><br>${esc(x.subject)} • ${esc(x.topic)}</div><div class="p-3 bg-slate-50 rounded-xl"><b>วันเวลา</b><br>${esc(x.event_datetime_text)}</div><div class="p-3 bg-slate-50 rounded-xl"><b>สถานที่</b><br>${esc(x.location_text)}</div><div class="p-3 bg-slate-50 rounded-xl"><b>กลุ่มเป้าหมาย</b><br>${esc(x.audience_text)}</div><div class="p-3 bg-slate-50 rounded-xl"><b>งบประมาณ</b><br>${esc(x.budget_text||'-')}</div><div class="p-3 bg-slate-50 rounded-xl sm:col-span-2"><b>รายละเอียด</b><br>${esc(x.details||'-')}</div></div><label class="block font-bold text-slate-500 mt-3">สถานะ<select id="swalSpeakerStatus" class="input mt-1"><option value="pending" ${x.status==='pending'?'selected':''}>รอติดต่อ</option><option value="contacted" ${x.status==='contacted'?'selected':''}>ติดต่อแล้ว</option><option value="quoted" ${x.status==='quoted'?'selected':''}>เสนอราคาแล้ว</option><option value="confirmed" ${x.status==='confirmed'?'selected':''}>ยืนยันงาน</option><option value="cancelled" ${x.status==='cancelled'?'selected':''}>ยกเลิก</option></select></label></div>`,showCancelButton:true,confirmButtonText:'บันทึกสถานะ',cancelButtonText:'ปิด',confirmButtonColor:'#10b981',preConfirm:()=>document.getElementById('swalSpeakerStatus').value});if(!r.isConfirmed)return;const {error}=await sb.from('speaker_requests').update({status:r.value,updated_at:new Date().toISOString()}).eq('id',id);if(error)return notify('error','อัปเดตไม่สำเร็จ',error.message);await loadAll();notify('success','อัปเดตคำขอแล้ว');};
if($('speakerSearch')) $('speakerSearch').oninput=renderSpeakers;
if($('speakerStatusFilter')) $('speakerStatusFilter').onchange=renderSpeakers;
if($('refreshSpeakers')) $('refreshSpeakers').onclick=loadAll;

function renderPrices(){const order=['yearly','monthly','pack20','pack10','hourly'];const labels={yearly:'รายปี',monthly:'30 ชั่วโมง',pack20:'20 ชั่วโมง',pack10:'10 ชั่วโมง',hourly:'รายชั่วโมง'};$('priceGrid').innerHTML=['standard','university'].map(tier=>`<div class="border rounded-2xl p-4"><h3 class="font-bold mb-3">${tier==='standard'?'ประถม - มัธยม':'มหาวิทยาลัย'}</h3>${order.map(code=>{const p=state.prices.find(x=>x.tier===tier&&x.package_code===code);return `<label class="grid grid-cols-[1fr_140px] gap-3 items-center mb-2 text-sm"><span>${labels[code]}</span><input class="input price-input" data-id="${p?.id||''}" data-tier="${tier}" data-code="${code}" data-label="${labels[code]}" type="number" min="0" step="0.01" value="${p?Number(p.amount):0}"></label>`}).join('')}</div>`).join('');}
$('savePrices').onclick=async()=>{try{const rows=[...document.querySelectorAll('.price-input')].map(i=>({id:i.dataset.id||undefined,tier:i.dataset.tier,package_code:i.dataset.code,label:i.dataset.label,amount:Number(i.value),active:true,updated_at:new Date().toISOString()}));for(const r of rows){const {id,...body}=r;const q=id?sb.from('course_prices').update(body).eq('id',id):sb.from('course_prices').insert(body);const{error}=await q;if(error)throw error;}await loadAll();notify('success','อัปเดตราคาแล้ว');}catch(err){notify('error','บันทึกราคาไม่สำเร็จ',err.message)}};

function localDT(v){if(!v)return'';const d=new Date(v);const pad=n=>String(n).padStart(2,'0');return `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;}
function renderPromos(){$('promoList').innerHTML=state.promotions.map(p=>`<button onclick="editPromo('${p.id}')" class="w-full text-left border rounded-2xl p-4 hover:border-emerald-300"><div class="flex justify-between"><div><div class="font-bold text-emerald-700">${esc(p.code)}</div><div class="text-xs text-slate-500">${esc(p.name||'')} • ${p.discount_type==='percent'?p.discount_value+'%':Number(p.discount_value).toLocaleString()+' บาท'}</div></div><span class="tag">${p.active?'ACTIVE':'OFF'}</span></div></button>`).join('')||'<p class="text-slate-400">ยังไม่มีโปรโมชั่น</p>';}
window.editPromo=id=>{const p=state.promotions.find(x=>x.id===id);if(!p)return;$('promoId').value=p.id;$('promoCode').value=p.code;$('promoName').value=p.name||'';$('promoType').value=p.discount_type;$('promoValue').value=p.discount_value;$('promoStart').value=localDT(p.starts_at);$('promoEnd').value=localDT(p.ends_at);$('promoActive').checked=p.active;};
$('promoReset').onclick=()=>$('promoForm').reset();
$('promoForm').onsubmit=async e=>{e.preventDefault();try{const row={code:$('promoCode').value.trim().toUpperCase(),name:$('promoName').value.trim(),discount_type:$('promoType').value,discount_value:Number($('promoValue').value),starts_at:$('promoStart').value?new Date($('promoStart').value).toISOString():null,ends_at:$('promoEnd').value?new Date($('promoEnd').value).toISOString():null,active:$('promoActive').checked,updated_at:new Date().toISOString()};let q=$('promoId').value?sb.from('promotions').update(row).eq('id',$('promoId').value):sb.from('promotions').insert(row);const{error}=await q;if(error)throw error;$('promoForm').reset();$('promoId').value='';await loadAll();notify('success','บันทึก Promotion แล้ว');}catch(err){notify('error','บันทึก Promotion ไม่สำเร็จ',err.message)}};

function renderPayments(){$('paymentRows').innerHTML=state.payments.map(p=>{const e=p.enrollments||{};return `<tr class="border-b"><td class="py-3 font-mono text-xs">${esc(e.receipt_no||'-')}</td><td><b>${esc(e.fullname||'-')}</b><div class="text-[10px] text-slate-400">${esc(e.phone||'')}</div></td><td class="max-w-[260px] text-xs">${esc(e.course_text||'-')}</td><td class="font-bold">${Number(p.amount_submitted||0).toLocaleString()}</td><td>${p.payment_method==='cash'?'เงินสด':'โอนเงิน'}</td><td><span class="tag">${esc(p.status)}</span></td><td class="text-right"><div class="flex justify-end gap-1">${p.slip_path?`<button onclick="viewSlip('${p.id}')" class="px-2 py-1 bg-sky-50 text-sky-600 rounded-lg text-xs">สลิป</button>`:''}${p.status==='pending'?`<button onclick="verifyPayment('${p.id}',true)" class="px-2 py-1 bg-emerald-50 text-emerald-600 rounded-lg text-xs">ยืนยัน</button><button onclick="verifyPayment('${p.id}',false)" class="px-2 py-1 bg-red-50 text-red-600 rounded-lg text-xs">ไม่ผ่าน</button>`:''}<button onclick="receiptPdf('${e.receipt_token}')" class="px-2 py-1 bg-slate-100 rounded-lg text-xs">ใบเสร็จ</button></div></td></tr>`}).join('')||'<tr><td colspan="7" class="py-10 text-center text-slate-400">ไม่มีข้อมูล</td></tr>';}
window.viewSlip=async id=>{const p=state.payments.find(x=>x.id===id);if(!p?.slip_path)return;const{data,error}=await sb.storage.from('payment-slips').createSignedUrl(p.slip_path,300);if(error)return notify('error','เปิดสลิปไม่ได้',error.message);Swal.fire({imageUrl:data.signedUrl,imageAlt:'Slip',showConfirmButton:false,showCloseButton:true,customClass:{popup:'rounded-[1.5rem]'}});};
window.verifyPayment=async(id,ok)=>{const p=state.payments.find(x=>x.id===id);if(!p)return;let reason=null;if(!ok){const r=await Swal.fire({title:'เหตุผลที่ไม่ผ่าน',input:'text',showCancelButton:true});if(!r.isConfirmed)return;reason=r.value||'ไม่ผ่านการตรวจสอบ';}const session=(await sb.auth.getSession()).data.session;const body=ok?{status:'paid',verified_amount:Number(p.amount_submitted),verified_at:new Date().toISOString(),verified_by:session.user.id,rejection_reason:null,updated_at:new Date().toISOString()}:{status:'rejected',rejection_reason:reason,verified_at:new Date().toISOString(),verified_by:session.user.id,updated_at:new Date().toISOString()};const{error}=await sb.from('payments').update(body).eq('id',id);if(error)return notify('error','อัปเดตไม่ได้',error.message);await sb.from('enrollments').update({status:ok?'confirmed':'rejected',updated_at:new Date().toISOString()}).eq('id',p.enrollment_id);await sb.from('schedule_reservations').update({status:ok?'confirmed':'cancelled',updated_at:new Date().toISOString()}).eq('enrollment_id',p.enrollment_id);await loadAll();notify('success',ok?'ยืนยันการชำระเงินแล้ว':'บันทึกว่าไม่ผ่านแล้ว');};
window.receiptPdf=token=>window.AreWarinReceipt.download(token); $('refreshPayments').onclick=loadAll;

async function signedPreview(path,imgId){if(!path){$(imgId).classList.add('hidden');return;}const{data}=await sb.storage.from('receipt-assets').createSignedUrl(path,300);if(data?.signedUrl){$(imgId).src=data.signedUrl;$(imgId).classList.remove('hidden');}}
function renderReceipt(){const r=state.receipt||{};$('rBusiness').value=r.business_name||'';$('rBusinessEn').value=r.business_name_en||'';$('rTax').value=r.tax_id||'';$('rAddress').value=r.address||'';$('rPhone').value=r.phone||'';$('rPrefix').value=r.receipt_prefix||'AR';$('rSigner').value=r.signer_name||'';$('rPosition').value=r.signer_position||'';$('rFooter').value=r.footer_text||'';$('rShowLogo').checked=r.show_logo!==false;$('rShowSignature').checked=r.show_signature!==false;signedPreview(r.logo_path,'rLogoPreview');signedPreview(r.signature_path,'rSignaturePreview');}
$('receiptForm').onsubmit=async e=>{e.preventDefault();try{let logo=state.receipt?.logo_path||null,signature=state.receipt?.signature_path||null;if($('rLogo').files[0])logo=await uploadPrivate('receipt-assets',$('rLogo').files[0],'logo');if($('rSignature').files[0])signature=await uploadPrivate('receipt-assets',$('rSignature').files[0],'signature');const row={id:1,business_name:$('rBusiness').value.trim(),business_name_en:$('rBusinessEn').value.trim(),tax_id:$('rTax').value.trim(),address:$('rAddress').value.trim(),phone:$('rPhone').value.trim(),receipt_prefix:$('rPrefix').value.trim().toUpperCase()||'AR',logo_path:logo,signature_path:signature,signer_name:$('rSigner').value.trim(),signer_position:$('rPosition').value.trim(),footer_text:$('rFooter').value.trim(),show_logo:$('rShowLogo').checked,show_signature:$('rShowSignature').checked,updated_at:new Date().toISOString()};const{error}=await sb.from('receipt_settings').upsert(row);if(error)throw error;await loadAll();notify('success','บันทึกตั้งค่าใบเสร็จแล้ว');}catch(err){notify('error','บันทึกไม่สำเร็จ',err.message)}};

const systemKeys=['COURSE_YEARLY','COURSE_30H','COURSE_20H','COURSE_10H','COURSE_HOURLY','ONSITE_OPTION','ANNOUNCEMENT_STATUS','ANNOUNCEMENT_IMG','ANNOUNCEMENT_MSG','MAINTENANCE_START','MAINTENANCE_END'];
function renderSystem(){$('systemSettings').innerHTML=systemKeys.map(k=>{const v=state.settings[k]??'';if(['COURSE_YEARLY','COURSE_30H','COURSE_20H','COURSE_10H','COURSE_HOURLY','ONSITE_OPTION','ANNOUNCEMENT_STATUS'].includes(k))return `<label class="border rounded-xl p-3 flex justify-between text-sm"><span>${k}</span><input class="system-setting" data-key="${k}" type="checkbox" ${v==='OPEN'?'checked':''}></label>`;return `<label class="text-xs font-bold">${k}<input class="input system-setting mt-1" data-key="${k}" value="${esc(v)}"></label>`}).join('');}
$('saveSystem').onclick=async()=>{try{const rows=[...document.querySelectorAll('.system-setting')].map(i=>({key:i.dataset.key,value:i.type==='checkbox'?(i.checked?'OPEN':'CLOSE'):i.value,updated_at:new Date().toISOString()}));const{error}=await sb.from('app_settings').upsert(rows,{onConflict:'key'});if(error)throw error;await loadAll();notify('success','บันทึกตั้งค่าระบบแล้ว');}catch(err){notify('error','บันทึกไม่สำเร็จ',err.message)}};

boot();
