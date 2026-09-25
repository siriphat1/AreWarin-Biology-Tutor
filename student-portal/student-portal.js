const db = window.SCHOOL_SUPABASE;
const FILE_BUCKET = 'student-portal-files';
const TOKEN_KEY = 'wnw_student_portal_token';
let portalData = null;
let currentToken = localStorage.getItem(TOKEN_KEY) || '';
let photoObjectUrl = null;
let universities = [];

const $ = id => document.getElementById(id);
const esc = s => String(s ?? '').replace(/[&<>'"]/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));

window.addEventListener('DOMContentLoaded', async () => {
  lucide.createIcons();
  await loadBranding();
  await loadUniversities();
  bindForms();
  if (currentToken) await restoreSession();
});

async function loadBranding(){
  try{
    const {data} = await db.from('site_settings').select('data').eq('id',1).maybeSingle();
    const root = data?.data || data || {};
    const info = root.info || {};
    const logo = root.branding?.logoUrl || root.branding?.logo_url || '';
    if(info.nameTh) $('schoolName').textContent = info.nameTh;
    if(logo){ $('schoolLogo').src=logo; $('schoolLogo').classList.remove('hidden'); $('schoolLogoIcon').classList.add('hidden'); }
  }catch(_e){}
}

async function loadUniversities(){
  if(!db) return;
  try{
    const {data,error}=await db.from('university_admissions').select('*').eq('published',true).in('status',['open','upcoming']).order('featured',{ascending:false}).order('end_date',{ascending:true,nullsFirst:false}).limit(8);
    if(error) throw error;
    universities=data||[];
  }catch(_e){ universities=[]; }
  renderUniversityCards('publicUniversityCards', universities.slice(0,4));
  renderUniversityCards('portalUniversityCards', universities.slice(0,4));
}

function renderUniversityCards(targetId, rows){
  const el=$(targetId); if(!el) return;
  if(!rows.length){ el.innerHTML='<div class="col-span-full rounded-2xl border border-dashed border-slate-300 p-6 text-center text-sm text-slate-400">ยังไม่มีประกาศรับสมัครมหาวิทยาลัย</div>'; return; }
  el.innerHTML=rows.map(r=>{
    const end=r.end_date?new Date(r.end_date+'T23:59:59'):null;
    const days=end?Math.ceil((end-Date.now())/86400000):null;
    const status=r.status==='open'?'เปิดรับสมัคร':'เร็ว ๆ นี้';
    const badge=r.status==='open'?'bg-emerald-50 text-emerald-700 border-emerald-200':'bg-amber-50 text-amber-700 border-amber-200';
    return `<a href="${esc(r.apply_url||r.announcement_url||'../university-admission/')}" target="_blank" rel="noopener" class="group rounded-2xl bg-white border border-slate-200 p-4 hover:-translate-y-1 hover:shadow-xl transition block">
      <div class="flex items-center gap-3"><div class="w-12 h-12 rounded-xl border border-slate-100 bg-white overflow-hidden flex items-center justify-center">${r.logo_url?`<img src="${esc(r.logo_url)}" class="w-full h-full object-contain">`:'<span class="text-xl">🎓</span>'}</div><div class="min-w-0"><p class="font-extrabold text-sm line-clamp-2">${esc(r.university_name)}</p><p class="text-[11px] text-slate-500 truncate">${esc(r.faculty||r.program_name||r.admission_round||'รับสมัครนักศึกษา')}</p></div></div>
      <div class="mt-4 flex items-center justify-between gap-2"><span class="px-2.5 py-1 rounded-full border ${badge} text-[10px] font-bold">${status}</span><span class="text-[10px] font-semibold text-slate-400">${days!=null&&days>=0?`เหลือ ${days} วัน`:(r.admission_round||'')}</span></div>
    </a>`;
  }).join('');
}

function bindForms(){
  $('loginForm').addEventListener('submit', loginStudent);
  $('profileForm').addEventListener('submit', saveProfile);
  $('gradeForm').addEventListener('submit', uploadGrade);
  $('pinForm').addEventListener('submit', changePin);
  $('profilePhotoFile').addEventListener('change', previewProfilePhoto);
}

window.togglePin=()=>{const p=$('loginPin');p.type=p.type==='password'?'text':'password'};

async function loginStudent(e){
  e.preventDefault(); if(!db) return setMsg('loginMsg','ยังไม่ได้เชื่อม Supabase','text-red-600');
  const btn=$('loginSubmit'); btn.disabled=true; btn.textContent='กำลังตรวจสอบ...';
  const {data,error}=await db.rpc('student_portal_login',{p_student_code:$('loginStudentCode').value.trim(),p_pin:$('loginPin').value});
  btn.disabled=false; btn.textContent='เข้าสู่ Student Portal';
  if(error||!data?.ok){ setMsg('loginMsg',data?.message||error?.message||'เข้าสู่ระบบไม่สำเร็จ','text-red-600'); return; }
  currentToken=data.session_token; localStorage.setItem(TOKEN_KEY,currentToken); setMsg('loginMsg','เข้าสู่ระบบสำเร็จ','text-emerald-600');
  await fetchDashboard();
}

async function restoreSession(){
  const ok=await fetchDashboard(false); if(!ok) portalLogout(false);
}

async function fetchDashboard(showError=true){
  if(!currentToken||!db) return false;
  const {data,error}=await db.rpc('student_portal_dashboard',{p_token:currentToken});
  if(error||!data?.ok){ if(showError) alert(data?.message||error?.message||'เซสชันหมดอายุ'); return false; }
  portalData=data; showPortal(); await renderPortal(); return true;
}

function showPortal(){ $('publicView').classList.add('hide'); $('portalView').classList.remove('hide'); $('logoutBtn').classList.remove('hide'); $('logoutBtn').classList.add('flex'); }
window.portalLogout=(reload=true)=>{localStorage.removeItem(TOKEN_KEY);currentToken='';portalData=null;if(reload) location.reload();};

async function renderPortal(){
  const s=portalData.student; const full=[s.title,s.first_name,s.last_name].filter(Boolean).join(' ');
  $('heroName').textContent=full; $('heroClass').textContent=`${s.class_level}${s.room?' / '+s.room:''}`; $('heroCode').textContent=`รหัส ${s.student_code}`; $('heroSub').textContent=[s.phone,s.email].filter(Boolean).join(' • ')||'ยังไม่ได้เพิ่มข้อมูลติดต่อ';
  $('profileName').value=full; $('profileCode').value=s.student_code; $('profileClass').value=`${s.class_level}${s.room?' / '+s.room:''}`; $('profilePhone').value=s.phone||''; $('profileEmail').value=s.email||'';
  $('timetableSubtitle').textContent=`${s.class_level}${s.room?' ห้อง '+s.room:''}`; $('examSubtitle').textContent=`กำหนดการสอบสำหรับ ${s.class_level}`;
  const now=new Date(); $('todayDate').textContent=new Intl.DateTimeFormat('th-TH',{weekday:'long',day:'numeric',month:'short',year:'numeric',timeZone:'Asia/Bangkok'}).format(now);
  await loadStudentPhoto(s.photo_path);
  renderSchedules(); renderExams(); renderGrades();
  renderUniversityCards('portalUniversityCards',universities.slice(0,4));
  lucide.createIcons();
}

async function loadStudentPhoto(path){
  if(photoObjectUrl){URL.revokeObjectURL(photoObjectUrl);photoObjectUrl=null;}
  ['heroPhoto','profilePhotoPreview'].forEach(id=>$(id).classList.add('hidden'));
  $('heroPhotoIcon').classList.remove('hidden'); $('profilePhotoIcon').classList.remove('hidden');
  if(!path) return;
  try{const {data,error}=await db.storage.from(FILE_BUCKET).download(path);if(error)throw error;photoObjectUrl=URL.createObjectURL(data);['heroPhoto','profilePhotoPreview'].forEach(id=>{$(id).src=photoObjectUrl;$(id).classList.remove('hidden')});$('heroPhotoIcon').classList.add('hidden');$('profilePhotoIcon').classList.add('hidden');}catch(_e){}
}

function currentThaiDay(){ const en=new Intl.DateTimeFormat('en-US',{weekday:'long',timeZone:'Asia/Bangkok'}).format(new Date()); return ({Sunday:'อาทิตย์',Monday:'จันทร์',Tuesday:'อังคาร',Wednesday:'พุธ',Thursday:'พฤหัสบดี',Friday:'ศุกร์',Saturday:'เสาร์'})[en]; }

function renderSchedules(){
  const rows=portalData.timetable||[]; const day=currentThaiDay(); const today=rows.filter(x=>x.day_name===day);
  $('todayDayName').textContent=`วัน${day} • ${portalData.student.class_level}`; $('todayClassCount').textContent=today.length;
  $('todaySchedule').innerHTML=today.length?today.map(scheduleCard).join(''):'<div class="rounded-2xl bg-slate-50 border border-dashed border-slate-300 p-6 text-center text-slate-400 text-sm">วันนี้ยังไม่มีตารางเรียนที่เผยแพร่</div>';
  const days=['จันทร์','อังคาร','พุธ','พฤหัสบดี','ศุกร์','เสาร์','อาทิตย์'];
  $('timetableDays').innerHTML=days.map(d=>{const rr=rows.filter(x=>x.day_name===d);if(!rr.length)return'';return `<div class="rounded-2xl border border-slate-200 overflow-hidden"><div class="flex items-center gap-3 px-4 py-3 ${d===day?'bg-orange-50':'bg-slate-50'}"><span class="w-9 h-9 rounded-xl ${d===day?'bg-orange-500 text-white':'bg-white text-slate-600 border border-slate-200'} flex items-center justify-center font-black">${d.slice(0,1)}</span><div><h3 class="font-extrabold">วัน${d}</h3>${d===day?'<p class="text-xs text-orange-600 font-bold">วันนี้</p>':''}</div></div><div class="overflow-x-auto"><table class="w-full text-sm"><thead class="bg-white text-slate-500"><tr><th class="text-left p-3">คาบ</th><th class="text-left p-3">เวลา</th><th class="text-left p-3">รหัสวิชา</th><th class="text-left p-3">วิชา</th><th class="text-left p-3">ผู้สอน</th><th class="text-left p-3">ห้อง</th></tr></thead><tbody>${rr.map(x=>`<tr class="border-t border-slate-100"><td class="p-3 font-bold">${esc(x.period_no??'–')}</td><td class="p-3 font-mono whitespace-nowrap">${esc(x.start_time||'')} ${x.end_time?'– '+esc(x.end_time):''}</td><td class="p-3">${esc(x.subject_code||'–')}</td><td class="p-3 font-bold">${esc(x.subject_name)}</td><td class="p-3">${esc(x.teacher_name||'–')}</td><td class="p-3">${esc(x.room||'–')}</td></tr>`).join('')}</tbody></table></div></div>`}).join('')||'<p class="text-slate-400">ยังไม่มีตารางเรียน</p>';
}
function scheduleCard(x){return `<div class="rounded-2xl border border-slate-200 bg-white p-4 flex gap-4"><div class="min-w-[74px]"><p class="font-black text-orange-600">${esc(x.start_time||'')}</p><p class="text-[10px] text-slate-400">${esc(x.end_time||'')}</p></div><div><p class="font-extrabold">${esc(x.subject_name)}</p><p class="text-xs text-slate-500 mt-1">${esc(x.subject_code||'')} ${x.teacher_name?'• '+esc(x.teacher_name):''}</p><p class="text-[11px] text-slate-400 mt-1">${x.room?'ห้อง '+esc(x.room):''}</p></div></div>`}

function renderExams(){
  const rows=[...(portalData.exams||[])].sort((a,b)=>(a.exam_date+a.start_time).localeCompare(b.exam_date+b.start_time)); const today=new Date().toISOString().slice(0,10); const future=rows.filter(x=>x.exam_date>=today);
  $('nextExamList').innerHTML=future.slice(0,4).map(examMini).join('')||'<p class="text-sm text-slate-400">ยังไม่มีวันสอบที่กำลังจะมาถึง</p>';
  $('examList').innerHTML=rows.length?rows.map(x=>`<div class="rounded-2xl border ${x.exam_date>=today?'border-orange-200 bg-orange-50/30':'border-slate-200 bg-slate-50/50'} p-4 md:p-5 flex flex-col md:flex-row gap-4 md:items-center"><div class="md:w-36"><p class="text-xs text-slate-500">วันที่สอบ</p><p class="font-black text-lg">${formatThaiDate(x.exam_date)}</p><p class="text-xs text-orange-600 font-bold">${esc(x.exam_type||'')}</p></div><div class="flex-1"><p class="font-extrabold text-lg">${esc(x.subject_name)}</p><p class="text-sm text-slate-500">${esc(x.subject_code||'')} ${x.room?'• ห้อง '+esc(x.room):''}</p>${x.note?`<p class="text-xs text-slate-500 mt-2">${esc(x.note)}</p>`:''}</div><div class="md:text-right"><p class="font-black text-slate-700">${esc(x.start_time||'-')} ${x.end_time?'– '+esc(x.end_time):''}</p></div></div>`).join(''):'<p class="text-slate-400">ยังไม่มีกำหนดการสอบ</p>';
}
function examMini(x){return `<div class="rounded-xl bg-slate-50 p-3 border border-slate-100"><p class="text-[10px] font-bold text-orange-600">${formatThaiDate(x.exam_date)} • ${esc(x.start_time||'')}</p><p class="font-bold text-sm mt-1">${esc(x.subject_name)}</p></div>`}
function formatThaiDate(s){try{return new Intl.DateTimeFormat('th-TH',{day:'numeric',month:'short',year:'2-digit'}).format(new Date(s+'T12:00:00'))}catch{return s}}

function renderGrades(){
  const rows=portalData.grades||[]; $('gradeHistory').innerHTML=rows.length?rows.map(g=>`<div class="rounded-2xl border border-slate-200 p-4 flex items-center gap-3"><div class="w-11 h-11 rounded-xl bg-orange-50 text-orange-600 flex items-center justify-center shrink-0"><i data-lucide="file-text" class="w-5 h-5"></i></div><div class="flex-1 min-w-0"><p class="font-bold truncate">${esc(g.original_file_name||'ไฟล์ผลการเรียน')}</p><p class="text-xs text-slate-500">ปี ${esc(g.academic_year)} • ภาค ${esc(g.semester)} • ${new Date(g.uploaded_at).toLocaleDateString('th-TH')}</p></div><button onclick="openGrade('${g.id}')" class="p-2 rounded-lg hover:bg-slate-100" title="เปิดไฟล์"><i data-lucide="external-link" class="w-4 h-4"></i></button><button onclick="deleteGrade('${g.id}')" class="p-2 rounded-lg hover:bg-red-50 text-red-500" title="ลบ"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div>`).join(''):'<p class="text-sm text-slate-400">ยังไม่เคยอัปโหลดไฟล์ผลการเรียน</p>'; lucide.createIcons();
}

window.openGrade=async id=>{const g=(portalData.grades||[]).find(x=>x.id===id);if(!g)return;const {data,error}=await db.storage.from(FILE_BUCKET).download(g.file_path);if(error)return alert(error.message);const url=URL.createObjectURL(data);window.open(url,'_blank');setTimeout(()=>URL.revokeObjectURL(url),60000)};
window.deleteGrade=async id=>{if(!confirm('ลบไฟล์นี้หรือไม่?'))return;const g=(portalData.grades||[]).find(x=>x.id===id);if(!g)return;await db.storage.from(FILE_BUCKET).remove([g.file_path]);const {data,error}=await db.rpc('student_portal_delete_grade',{p_token:currentToken,p_grade_id:id});if(error||!data?.ok)return alert(data?.message||error?.message);await fetchDashboard(false);showTab('grades')};

function previewProfilePhoto(e){const f=e.target.files[0];if(!f)return;if(f.size>3*1024*1024){alert('รูปต้องไม่เกิน 3 MB');e.target.value='';return}const url=URL.createObjectURL(f);$('profilePhotoPreview').src=url;$('profilePhotoPreview').classList.remove('hidden');$('profilePhotoIcon').classList.add('hidden')}

async function saveProfile(e){
  e.preventDefault(); const s=portalData.student; let photoPath=s.photo_path||null; const f=$('profilePhotoFile').files[0];
  setMsg('profileMsg','กำลังบันทึก...','text-slate-500');
  if(f){const ext=(f.name.split('.').pop()||'jpg').toLowerCase();photoPath=`${s.storage_key}/profile/profile-${Date.now()}.${ext}`;const {error}=await db.storage.from(FILE_BUCKET).upload(photoPath,f,{upsert:true,contentType:f.type});if(error)return setMsg('profileMsg',error.message,'text-red-600')}
  const {data,error}=await db.rpc('student_portal_update_profile',{p_token:currentToken,p_phone:$('profilePhone').value,p_email:$('profileEmail').value,p_photo_path:photoPath});
  if(error||!data?.ok)return setMsg('profileMsg',data?.message||error?.message,'text-red-600');setMsg('profileMsg','บันทึกแล้ว','text-emerald-600');await fetchDashboard(false);showTab('profile');
}

async function uploadGrade(e){
  e.preventDefault(); const f=$('gradeFile').files[0]; if(!f)return; if(f.size>10*1024*1024)return setMsg('gradeMsg','ไฟล์ต้องไม่เกิน 10 MB','text-red-600');
  const btn=$('gradeSubmit');btn.disabled=true;btn.textContent='กำลังอัปโหลด...';const s=portalData.student;const safe=f.name.replace(/[^a-zA-Z0-9._-]+/g,'-');const path=`${s.storage_key}/grades/${crypto.randomUUID()}-${safe}`;
  const {error:upErr}=await db.storage.from(FILE_BUCKET).upload(path,f,{contentType:f.type||undefined});if(upErr){btn.disabled=false;btn.textContent='อัปโหลด';return setMsg('gradeMsg',upErr.message,'text-red-600')}
  const {data,error}=await db.rpc('student_portal_add_grade',{p_token:currentToken,p_academic_year:$('gradeYear').value.trim(),p_semester:$('gradeSemester').value,p_file_path:path,p_original_file_name:f.name,p_note:$('gradeNote').value});
  btn.disabled=false;btn.textContent='อัปโหลด';if(error||!data?.ok){await db.storage.from(FILE_BUCKET).remove([path]);return setMsg('gradeMsg',data?.message||error?.message,'text-red-600')}
  $('gradeForm').reset();setMsg('gradeMsg','อัปโหลดเรียบร้อย','text-emerald-600');await fetchDashboard(false);showTab('grades');
}

async function changePin(e){e.preventDefault();if($('newPin').value!==$('confirmPin').value)return setMsg('pinMsg','PIN ใหม่ไม่ตรงกัน','text-red-600');const {data,error}=await db.rpc('student_portal_change_pin',{p_token:currentToken,p_current_pin:$('currentPin').value,p_new_pin:$('newPin').value});if(error||!data?.ok)return setMsg('pinMsg',data?.message||error?.message,'text-red-600');$('pinForm').reset();setMsg('pinMsg','เปลี่ยน PIN แล้ว','text-emerald-600')}

window.showTab=tab=>{document.querySelectorAll('.portal-tab').forEach(x=>x.classList.add('hide'));$(`tab-${tab}`).classList.remove('hide');document.querySelectorAll('.tab-btn').forEach(x=>x.classList.toggle('active',x.dataset.tab===tab));window.scrollTo({top:0,behavior:'smooth'});lucide.createIcons()};
function setMsg(id,msg,cls){const el=$(id);el.textContent=msg;el.className=(id==='loginMsg'?'mt-4 text-sm text-center ':'')+cls}
