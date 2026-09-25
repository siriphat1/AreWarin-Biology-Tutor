const db = window.SCHOOL_SUPABASE;
const bucket = window.SCHOOL_APP_CONFIG?.STORAGE_BUCKET || 'site-media';
let settings = {};
let achievements = [];
let news = [];
let newsTableReady = true;
let newsLoadError = null;
let personnelTableReady = true;
let personnelLoadError = null;
let currentStaffKind = 'teachers';

const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const clone = v => JSON.parse(JSON.stringify(v));
const esc = (value='') => String(value).replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const getPath = (obj,path) => path.split('.').reduce((o,k)=>o?.[k],obj);
function setPath(obj,path,value){const keys=path.split('.');let o=obj;keys.slice(0,-1).forEach((k,i)=>{if(o[k]==null)o[k]=/^\d+$/.test(keys[i+1])?[]:{};o=o[k]});o[keys.at(-1)]=value}
function toast(msg,bad=false){const el=$('#toast');el.textContent=msg;el.className=`fixed right-4 bottom-4 z-[120] max-w-sm px-5 py-3 rounded-2xl shadow-2xl text-sm ${bad?'bg-red-600':'bg-slate-900'} text-white`;el.classList.remove('hidden');setTimeout(()=>el.classList.add('hidden'),2800)}
function markDirty(){if($('#save-status'))$('#save-status').textContent='มีการแก้ไข — กด “บันทึกเว็บไซต์” เพื่อเผยแพร่'}
function formatBytes(bytes=0){if(!Number(bytes))return '';const units=['B','KB','MB','GB'];let n=Number(bytes),i=0;while(n>=1024&&i<units.length-1){n/=1024;i++}return `${n.toFixed(i?1:0)} ${units[i]}`}
function ensureImagePreview(fileInput){
  if(!fileInput)return null;if(fileInput._imagePreviewBox?.isConnected)return fileInput._imagePreviewBox;
  const row=fileInput.closest('.flex')||fileInput.parentElement;if(!row)return null;
  const box=document.createElement('div');box.className='mt-3 rounded-2xl border border-dashed border-slate-200 bg-slate-50/80 p-3';
  box.innerHTML=`<div class="flex items-center justify-between gap-3 mb-2"><span class="text-[11px] font-bold text-slate-600 flex items-center gap-1.5"><i data-lucide="image" class="w-3.5 h-3.5 text-orange-500"></i> ตัวอย่างภาพ</span><span data-preview-meta class="text-[10px] text-slate-400 truncate max-w-[65%]">ยังไม่ได้เลือกภาพ</span></div><div class="relative min-h-32 max-h-72 rounded-xl overflow-hidden bg-white border border-slate-100 flex items-center justify-center"><img data-preview-image alt="ตัวอย่างภาพก่อนบันทึก" class="hidden w-full max-h-72 object-contain"><div data-preview-empty class="text-xs text-slate-400 flex flex-col items-center gap-2 py-8"><i data-lucide="image-plus" class="w-7 h-7 text-slate-300"></i><span>เมื่อเลือกภาพ ตัวอย่างจะแสดงตรงนี้</span></div></div>`;
  row.insertAdjacentElement('afterend',box);fileInput._imagePreviewBox=box;lucide.createIcons();return box;
}
function setImagePreview(fileInput,url,meta='ภาพปัจจุบัน'){
  const box=ensureImagePreview(fileInput);if(!box)return;const img=box.querySelector('[data-preview-image]'),empty=box.querySelector('[data-preview-empty]'),txt=box.querySelector('[data-preview-meta]');
  if(!url){img.removeAttribute('src');img.classList.add('hidden');empty.classList.remove('hidden');txt.textContent='ยังไม่ได้เลือกภาพ';return}
  img.onload=()=>{img.classList.remove('hidden');empty.classList.add('hidden');if(!txt.textContent||txt.textContent==='กำลังโหลดตัวอย่าง...')txt.textContent=meta};
  img.onerror=()=>{img.classList.add('hidden');empty.classList.remove('hidden');txt.textContent='ไม่สามารถแสดงตัวอย่างจาก URL นี้ได้'};
  txt.textContent=meta||'กำลังโหลดตัวอย่าง...';img.src=url;
}
function previewSelectedImage(fileInput,file){
  if(!fileInput||!file?.type?.startsWith('image/'))return;
  if(fileInput._previewObjectUrl)URL.revokeObjectURL(fileInput._previewObjectUrl);
  const objectUrl=URL.createObjectURL(file);fileInput._previewObjectUrl=objectUrl;const box=ensureImagePreview(fileInput),img=box?.querySelector('[data-preview-image]'),empty=box?.querySelector('[data-preview-empty]'),txt=box?.querySelector('[data-preview-meta]');if(!img)return;
  txt.textContent=`${file.name} • ${formatBytes(file.size)}`;img.onload=()=>{img.classList.remove('hidden');empty.classList.add('hidden');txt.textContent=`${file.name} • ${img.naturalWidth}×${img.naturalHeight}px • ${formatBytes(file.size)}`};img.onerror=()=>{txt.textContent='ไฟล์นี้ไม่สามารถแสดงตัวอย่างได้'};img.src=objectUrl;
}
function findStaticUploader(path){return $$('[data-upload-target]').find(x=>x.dataset.uploadTarget===path)}
function refreshStaticImagePreviews(){
  $$('[data-upload-target]').forEach(fileInput=>{const input=$$('[data-path]').find(x=>x.dataset.path===fileInput.dataset.uploadTarget);setImagePreview(fileInput,input?.value||getPath(settings,fileInput.dataset.uploadTarget)||'',input?.value?'ภาพที่ใช้อยู่บนเว็บไซต์':'ยังไม่ได้เลือกภาพ')});
}
async function loadDefault(){const r=await fetch('../assets/default-data.json');return r.json()}
async function loadLoginBranding(){
  let data={};
  try{data=await loadDefault()}catch(_){}
  if(db){
    try{
      const {data:row}=await db.from('site_settings').select('data').eq('id',1).maybeSingle();
      if(row?.data)data=mergeDefaults(data,row.data);
    }catch(_){}
  }
  const logo=data?.branding?.logoUrl||'';
  const name=data?.info?.nameTh||'โรงเรียนวัดหนองแวงวิทยา';
  const nameEl=$('#login-school-name'),img=$('#login-school-logo'),fallback=$('#login-logo-fallback');
  if(nameEl)nameEl.textContent=name;
  if(img&&fallback&&logo){
    img.onload=()=>{img.classList.remove('hidden');fallback.classList.add('hidden')};
    img.onerror=()=>{img.classList.add('hidden');fallback.classList.remove('hidden')};
    img.src=logo;
  }
}

const iconOptions=[['users','ผู้คน'],['book-open','หนังสือ'],['calendar','ปฏิทิน'],['bell','ระฆัง'],['sun','ดวงอาทิตย์'],['moon','พระจันทร์'],['clock','นาฬิกา'],['graduation-cap','การศึกษา'],['monitor-play','สื่อการเรียน'],['book','ตำรา'],['scroll-text','คัมภีร์ / เอกสาร'],['file-text','ไฟล์เอกสาร'],['school','โรงเรียน'],['heart','หัวใจ'],['award','รางวัล'],['star','ดาว'],['link','ลิงก์'],['globe','เว็บไซต์'],['map','แผนที่'],['phone','โทรศัพท์'],['mail','อีเมล'],['languages','ภาษา']];
const colorOptions=[
  ['orange','ส้ม','bg-orange-100','text-orange-600'],['blue','น้ำเงิน','bg-blue-100','text-blue-600'],['green','เขียว','bg-green-100','text-green-600'],['red','แดง','bg-red-100','text-red-600'],['amber','เหลือง','bg-amber-100','text-amber-600'],['purple','ม่วง','bg-purple-100','text-purple-600']
];
const badgeColors={red:'bg-red-100 text-red-600',green:'bg-green-100 text-green-600',blue:'bg-blue-100 text-blue-600',orange:'bg-orange-100 text-orange-600',purple:'bg-purple-100 text-purple-600',amber:'bg-amber-100 text-amber-600'};
const newsSchema={
  defaults:{date_text:'',month_year:'',category:'ข่าวสาร',category_color:'bg-orange-100 text-orange-600',title:'',summary:'',image_url:'',url:'',published:true},
  fields:[
    {name:'image_url',label:'ภาพปกข่าว',type:'image',uploadPrefix:'news'},
    {name:'date_text',label:'วันที่',placeholder:'เช่น 5',required:true},
    {name:'month_year',label:'เดือน / ปี',placeholder:'เช่น มี.ค. 69',required:true},
    {name:'category',label:'หมวดข่าว',placeholder:'เช่น ข่าวสาร / ประกาศ / รับสมัคร',required:true},
    {name:'category_color',label:'สีป้ายหมวด',type:'badgeColor'},
    {name:'title',label:'หัวข้อข่าว',type:'textarea',required:true},
    {name:'summary',label:'คำโปรย / สรุปสั้น ๆ',type:'textarea',placeholder:'ข้อความสั้น ๆ ที่จะแสดงบนการ์ดข่าว'},
    {name:'url',label:'ลิงก์อ่านรายละเอียด (ถ้ามี)',placeholder:'https://...'},
    {name:'published',label:'เผยแพร่ข่าวนี้บนเว็บไซต์',type:'checkbox'}
  ]
};
const collectionSchemas={
  events:{title:'กิจกรรม',empty:'ยังไม่มีกิจกรรม',summary:x=>`${x.date||''} • ${x.title||''} • ${x.time||''}`,defaults:{date:'',title:'',time:'',url:'',published:true},fields:[{name:'date',label:'วันที่ / ช่วงวันที่',placeholder:'เช่น 15 มีนาคม',required:true},{name:'title',label:'ชื่อกิจกรรม',required:true},{name:'time',label:'เวลา',placeholder:'เช่น 08:00 - 12:00'},{name:'url',label:'ลิงก์รายละเอียด (ถ้ามี)'},{name:'published',label:'แสดงกิจกรรมนี้บนเว็บไซต์',type:'checkbox'}]},
  'examStats.naktham':{title:'สถิติแผนกธรรม',empty:'ยังไม่มีสถิติ',summary:x=>`${x.name||''} — ผ่าน ${x.passRate??0}%`,defaults:{name:'',passRate:0,published:true},fields:[{name:'name',label:'ชื่อระดับ',required:true},{name:'passRate',label:'อัตราสอบผ่าน (%)',type:'number',min:0,max:100,required:true},{name:'published',label:'แสดงบนเว็บไซต์',type:'checkbox'}]},
  'examStats.pali':{title:'สถิติแผนกบาลี',empty:'ยังไม่มีสถิติ',summary:x=>`${x.name||''} — ผ่าน ${x.passRate??0}%`,defaults:{name:'',passRate:0,published:true},fields:[{name:'name',label:'ชื่อระดับ',required:true},{name:'passRate',label:'อัตราสอบผ่าน (%)',type:'number',min:0,max:100,required:true},{name:'published',label:'แสดงบนเว็บไซต์',type:'checkbox'}]},
  routines:{title:'กิจวัตรประจำวัน',empty:'ยังไม่มีกิจวัตร',summary:x=>`${x.time||''} • ${x.task||''}`,defaults:{time:'',task:'',icon:'clock',published:true},fields:[{name:'time',label:'เวลา',placeholder:'เช่น 04:30 น.',required:true},{name:'task',label:'กิจวัตร',required:true},{name:'icon',label:'ไอคอน',type:'icon'},{name:'published',label:'แสดงบนเว็บไซต์',type:'checkbox'}]},
  curriculums:{title:'แผนการเรียน',empty:'ยังไม่มีแผนการเรียน',summary:x=>`${x.title||''} • ${x.subtitle||''}`,defaults:{title:'',subtitle:'',desc:'',icon:'book',color:'bg-orange-100 text-orange-600',published:true},fields:[{name:'title',label:'ชื่อแผนการเรียน',required:true},{name:'subtitle',label:'คำอธิบายสั้น'},{name:'desc',label:'รายละเอียด',type:'textarea'},{name:'icon',label:'ไอคอน',type:'icon'},{name:'color',label:'สีประจำกล่อง',type:'boxColor'},{name:'published',label:'แสดงบนเว็บไซต์',type:'checkbox'}]},
  quickLinks:{title:'E-Services / เมนูลัด',empty:'ยังไม่มีเมนูลัด',summary:x=>`${x.label||''} • ${x.url||'#'}`,defaults:{icon:'link',label:'',bg:'bg-orange-100',text:'text-orange-600',url:'#',published:true},fields:[{name:'label',label:'ชื่อเมนู',required:true},{name:'url',label:'ลิงก์ปลายทาง',placeholder:'https://... หรือ #'},{name:'icon',label:'ไอคอน',type:'icon'},{name:'colorPicker',label:'สีเมนู',type:'quickColor'},{name:'published',label:'แสดงบนเว็บไซต์',type:'checkbox'}]},
  documents:{title:'เอกสารดาวน์โหลด',empty:'ยังไม่มีเอกสาร',summary:x=>`${x.title||''} • ${x.type||''} ${x.size?`• ${x.size}`:''}`,defaults:{title:'',size:'',type:'PDF',url:'',published:true},fields:[{name:'title',label:'ชื่อเอกสาร',required:true},{name:'type',label:'ประเภทไฟล์',placeholder:'PDF / DOCX / XLSX'},{name:'size',label:'ขนาดไฟล์',placeholder:'เช่น 1.2 MB'},{name:'url',label:'ไฟล์ / ลิงก์ดาวน์โหลด',type:'fileUpload',placeholder:'https://...'},{name:'published',label:'แสดงบนเว็บไซต์',type:'checkbox'}]}
};

async function start(){
  await loadLoginBranding();
  lucide.createIcons();
  if(!db){$('#config-warning').classList.remove('hidden');$('#login-form button').disabled=true;$('#login-form button').classList.add('opacity-50');return}
  const {data:{session}}=await db.auth.getSession();
  if(session)await enterApp(session); else $('#login-screen').classList.remove('hidden');
}

$('#login-form').addEventListener('submit',async e=>{
  e.preventDefault();const err=$('#login-error');err.classList.add('hidden');
  const {data,error}=await db.auth.signInWithPassword({email:$('#login-email').value.trim(),password:$('#login-password').value});
  if(error){err.textContent=error.message;err.classList.remove('hidden');return}await enterApp(data.session);
});

async function enterApp(session){
  if(!session?.user||session.user.is_anonymous){await db.auth.signOut();showLoginError('กรุณาเข้าสู่ระบบด้วยบัญชีผู้ดูแลที่สร้างใน Supabase Authentication');return}
  const {data:allowed,error}=await db.rpc('is_site_admin');
  if(error||!allowed){await db.auth.signOut();showLoginError('Supabase ยังไม่ได้เปิดโหมด Authentication Admin กรุณารันไฟล์ supabase/authentication-admin-mode.sql');return}
  $('#login-screen').classList.add('hidden');$('#app').classList.remove('hidden');
  $('#manager-email').textContent=session.user.email||'-';$('#manager-user-id').textContent=session.user.id||'-';
  const ref=(window.SCHOOL_APP_CONFIG?.SUPABASE_URL||'').match(/^https:\/\/([^.]+)\.supabase\.co/i)?.[1];if(ref)$('#supabase-auth-link').href=`https://supabase.com/dashboard/project/${ref}/auth/users`;
  await loadAll();bindUI();renderAll();lucide.createIcons();
}
function showLoginError(msg){$('#login-error').textContent=msg;$('#login-error').classList.remove('hidden')}

async function loadAll(){
  const fallback=await loadDefault();settings=clone(fallback);
  const [s,a,n,p]=await Promise.all([
    db.from('site_settings').select('data,updated_at').eq('id',1).maybeSingle(),
    db.from('achievements').select('*').order('created_at',{ascending:false}),
    db.from('news').select('*').order('sort_order',{ascending:true}).order('created_at',{ascending:false}),
    db.from('personnel').select('*').order('staff_type',{ascending:true}).order('sort_order',{ascending:true}).order('created_at',{ascending:true})
  ]);
  if(s.data?.data)settings=mergeDefaults(fallback,s.data.data);
  // News and personnel now live in dedicated Supabase tables. Do not keep/save duplicate JSON copies.
  delete settings.news;
  if(settings.introPage?.subtitle)settings.introPage.subtitle=String(settings.introPage.subtitle).replace(/<br\s*\/?>/gi,'\n');
  achievements=a.data||[];
  newsTableReady=!n.error;
  newsLoadError=n.error||null;
  news=n.data||[];
  personnelTableReady=!p.error;
  personnelLoadError=p.error||null;
  if(personnelTableReady){
    settings.executives=[]; settings.teachers=[]; settings.specialTeachers=[];
    (p.data||[]).forEach(row=>{
      const kind=['executives','teachers','specialTeachers'].includes(row.staff_type)?row.staff_type:'teachers';
      settings[kind].push(personnelRowToStaff(row));
    });
  }
}
function mergeDefaults(base,incoming){
  if(Array.isArray(base))return Array.isArray(incoming)?clone(incoming):clone(base);
  if(base&&typeof base==='object'){const out=clone(base);if(incoming&&typeof incoming==='object')Object.keys(incoming).forEach(k=>{out[k]=(k in base)?mergeDefaults(base[k],incoming[k]):clone(incoming[k])});return out}
  return incoming===undefined?base:incoming;
}

function personnelRowToStaff(row={}){
  return {
    id:row.id||'', name:row.full_name||'', position:row.position||'', department:row.department||'',
    img:row.image_url||'', education:row.education||'', phone:row.phone||'', email:row.email||'',
    isAlumni:!!row.is_alumni, alumniBatch:row.alumni_batch||'',
    isRoyalScholarship:!!row.is_royal_scholarship, royalScholarshipBatch:row.royal_scholarship_batch||'', royalScholarshipPhase:row.royal_scholarship_phase||'',
    published:row.published!==false, sortOrder:Number(row.sort_order||0)
  };
}
function staffToPersonnelRow(item={},kind='teachers',sortOrder=0){
  return {
    staff_type:kind, full_name:String(item.name||'').trim(), position:String(item.position||'').trim(),
    department:String(item.department||'').trim(), image_url:String(item.img||'').trim(),
    education:String(item.education||'').trim(), phone:String(item.phone||'').trim(), email:String(item.email||'').trim(),
    is_alumni:!!item.isAlumni, alumni_batch:item.isAlumni?String(item.alumniBatch||'').trim():'',
    is_royal_scholarship:!!item.isRoyalScholarship,
    royal_scholarship_batch:item.isRoyalScholarship?String(item.royalScholarshipBatch||'').trim():'',
    royal_scholarship_phase:item.isRoyalScholarship?String(item.royalScholarshipPhase||'').trim():'',
    published:item.published!==false, sort_order:Number.isFinite(Number(sortOrder))?Number(sortOrder):0
  };
}
function nextPersonnelSortOrder(kind){
  const arr=settings[kind]||[];
  return arr.length?Math.max(...arr.map(x=>Number(x.sortOrder||0)))+10:0;
}

function bindUI(){
  if(document.body.dataset.bound)return;document.body.dataset.bound='1';
  $$('#sidebar-nav [data-view]').forEach(b=>b.addEventListener('click',()=>showView(b.dataset.view)));$$('[data-jump]').forEach(b=>b.addEventListener('click',()=>showView(b.dataset.jump)));
  $('#save-btn').addEventListener('click',saveSettings);$('#logout-btn').addEventListener('click',async()=>{await db.auth.signOut();location.reload()});
  bindPathInputs();
  $('#add-banner').addEventListener('click',()=>{settings.promoBanners=settings.promoBanners||[];settings.promoBanners.push('');renderBanners();markDirty()});
  $('#add-staff').addEventListener('click',()=>openStaffEditor());$$('.staff-tab').forEach(b=>b.addEventListener('click',()=>{currentStaffKind=b.dataset.staffKind;$$('.staff-tab').forEach(x=>{x.classList.remove('bg-orange-500','text-white');x.classList.add('bg-white/70','text-slate-600')});b.classList.add('bg-orange-500','text-white');b.classList.remove('bg-white/70','text-slate-600');renderStaff()}));
  $('#add-achievement').addEventListener('click',()=>openAchievementEditor());
  $('#add-news').addEventListener('click',()=>openNewsEditor());
  $$('[data-add-collection]').forEach(b=>b.addEventListener('click',()=>openCollectionEditor(b.dataset.addCollection)));
  $$('[data-close-modal]').forEach(x=>x.addEventListener('click',closeModal));
}
function bindPathInputs(){
  $$('[data-path]').forEach(el=>{const event=el.type==='checkbox'?'change':'input';el.addEventListener(event,()=>{let v=el.type==='checkbox'?el.checked:el.value;if(el.type==='number'&&v!=='')v=Number(v);setPath(settings,el.dataset.path,v);const uploader=findStaticUploader(el.dataset.path);if(uploader&&el.type!=='checkbox')setImagePreview(uploader,el.value,el.value?'ตัวอย่างจาก URL':'ยังไม่ได้เลือกภาพ');refreshDerived();markDirty()})});
  $$('[data-upload-target]').forEach(el=>el.addEventListener('change',async()=>{if(!el.files?.[0])return;const file=el.files[0];previewSelectedImage(el,file);const path=el.dataset.uploadTarget,url=await uploadFile(file,path.replaceAll('.','-'));if(url){setPath(settings,path,url);const input=$$('[data-path]').find(x=>x.dataset.path===path);if(input)input.value=url;setImagePreview(el,url,'อัปโหลดแล้ว • พร้อมบันทึกเว็บไซต์');markDirty()}}));
}

function showView(name){
  $$('.panel').forEach(p=>p.classList.toggle('hidden',p.dataset.panel!==name));$$('.sidebar-btn').forEach(b=>b.classList.toggle('active',b.dataset.view===name));
  const titles={dashboard:'ภาพรวม',general:'ข้อมูลโรงเรียน',visual:'หน้าแรก / แบนเนอร์',staff:'บุคลากร',news:'ข่าวสาร',events:'กิจกรรม / ปฏิทิน',academic:'ข้อมูลวิชาการ',services:'บริการ / ลิงก์ / เอกสาร',achievements:'ผลงานแห่งความภาคภูมิใจ',admins:'บัญชีผู้ดูแลระบบ'};$('#page-title').textContent=titles[name]||'Website Manager';
}

function renderAll(){
  $$('[data-path]').forEach(el=>{let v=getPath(settings,el.dataset.path);if(el.type==='checkbox')el.checked=!!v;else if(el.type==='datetime-local')el.value=String(v||'').slice(0,16);else el.value=v??''});
  refreshStaticImagePreviews();renderBanners();renderStaff();renderNewsManager();Object.keys(collectionSchemas).forEach(renderCollection);renderAchievements();refreshDerived(false);
}
function refreshDerived(dirty=true){
  $('#dash-students').textContent=getPath(settings,'info.stats.0.value')||'-';$('#dash-staff').textContent=getPath(settings,'info.stats.1.value')||'-';$('#dash-teachers').textContent=(settings.teachers?.length||0)+(settings.executives?.length||0)+(settings.specialTeachers?.length||0);if($('#dash-news'))$('#dash-news').textContent=news.length;$('#dash-achievements').textContent=achievements.length;if(dirty)markDirty();
}

async function saveSettings(){
  const btn=$('#save-btn');try{btn.disabled=true;$('#save-status').textContent='กำลังบันทึก...';const payload=clone(settings);delete payload.news;if(personnelTableReady){delete payload.executives;delete payload.teachers;delete payload.specialTeachers;}const {error}=await db.from('site_settings').upsert({id:1,data:payload,updated_at:new Date().toISOString()},{onConflict:'id'});if(error)throw error;$('#save-status').textContent='บันทึกแล้ว '+new Date().toLocaleTimeString('th-TH',{hour:'2-digit',minute:'2-digit'});toast('บันทึกและเผยแพร่ข้อมูลเรียบร้อย')}
  catch(e){$('#save-status').textContent='บันทึกไม่สำเร็จ';toast(e.message,true)}finally{btn.disabled=false}
}

function renderBanners(){
  const list=$('#banner-list'),arr=settings.promoBanners||[];
  list.innerHTML=arr.map((url,i)=>`<div class="flex flex-col sm:flex-row sm:items-center gap-3 p-3 rounded-2xl bg-white/60 border border-white"><div class="w-full sm:w-28 aspect-video bg-slate-100 rounded-xl overflow-hidden shrink-0">${url?`<img src="${esc(url)}" class="w-full h-full object-cover">`:''}</div><input class="field flex-1" value="${esc(url)}" data-banner-index="${i}" placeholder="URL รูป หรือกดอัปโหลด"><label class="cursor-pointer px-3 py-3 rounded-xl bg-slate-100 text-xs font-bold text-center"><input type="file" accept="image/*" class="hidden" data-banner-upload="${i}">อัปโหลด</label><div class="flex gap-2"><button class="btn-secondary" data-banner-up="${i}" ${i===0?'disabled':''}>↑</button><button class="btn-secondary" data-banner-down="${i}" ${i===arr.length-1?'disabled':''}>↓</button><button class="px-3 py-2 rounded-xl bg-red-50 text-red-500" data-banner-delete="${i}"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div></div>`).join('')||'<div class="rounded-2xl bg-slate-50 p-6 text-center text-sm text-slate-400">ยังไม่มีแบนเนอร์</div>';
  $$('[data-banner-index]').forEach(el=>el.addEventListener('input',()=>{settings.promoBanners[+el.dataset.bannerIndex]=el.value;markDirty()}));$$('[data-banner-delete]').forEach(b=>b.addEventListener('click',()=>{if(confirm('ลบแบนเนอร์นี้?')){settings.promoBanners.splice(+b.dataset.bannerDelete,1);renderBanners();markDirty()}}));
  $$('[data-banner-up]').forEach(b=>b.addEventListener('click',()=>moveArrayItem(settings.promoBanners,+b.dataset.bannerUp,-1,renderBanners)));$$('[data-banner-down]').forEach(b=>b.addEventListener('click',()=>moveArrayItem(settings.promoBanners,+b.dataset.bannerDown,1,renderBanners)));
  $$('[data-banner-upload]').forEach(el=>el.addEventListener('change',async()=>{if(!el.files?.[0])return;const i=+el.dataset.bannerUpload,file=el.files[0],card=el.closest('.flex.flex-col');if(card){const frame=card.querySelector('.aspect-video');if(frame){const objectUrl=URL.createObjectURL(file);frame.innerHTML=`<img src="${objectUrl}" class="w-full h-full object-cover"><span class="absolute"></span>`}}const url=await uploadFile(file,'banner');if(url){settings.promoBanners[i]=url;renderBanners();markDirty()}}));lucide.createIcons();
}
function moveArrayItem(arr,index,dir,rerender){const to=index+dir;if(to<0||to>=arr.length)return;[arr[index],arr[to]]=[arr[to],arr[index]];rerender();markDirty()}

function renderStaff(){
  const list=$('#staff-list'),arr=settings[currentStaffKind]||[],isExec=currentStaffKind==='executives',status=$('#personnel-db-status'),addBtn=$('#add-staff');
  if(!personnelTableReady){
    if(status){status.className='rounded-2xl bg-red-50 text-red-700 px-4 py-3 text-xs font-bold';status.textContent='ยังไม่พบตาราง personnel ใน Supabase — กรุณารันไฟล์ supabase/personnel-system.sql ก่อน';}
    if(addBtn)addBtn.disabled=true;
    list.innerHTML='<div class="md:col-span-2 xl:col-span-3 rounded-3xl bg-red-50 p-8 text-center text-sm text-red-500">ระบบบุคลากรยังเชื่อมฐานข้อมูลไม่ได้</div>';
    lucide.createIcons(); return;
  }
  if(status){status.className='rounded-2xl bg-green-50 text-green-700 px-4 py-3 text-xs font-bold';status.textContent=`เชื่อมต่อ Supabase personnel แล้ว • บุคลากรทั้งหมด ${(settings.executives?.length||0)+(settings.teachers?.length||0)+(settings.specialTeachers?.length||0)} รายการ • บันทึกอัตโนมัติ`; }
  if(addBtn)addBtn.disabled=false;
  list.innerHTML=arr.map((p,i)=>`<article class="glass rounded-3xl p-5 flex gap-4 items-center"><img src="${esc(p.img||'')}" class="w-20 h-20 rounded-2xl object-cover bg-slate-100"><div class="min-w-0 flex-1"><div class="flex items-center gap-2 flex-wrap"><h4 class="font-bold truncate">${esc(p.name||'-')}</h4>${p.isAlumni?`<span class="text-[10px] font-bold bg-amber-50 text-amber-700 border border-amber-200 px-2 py-0.5 rounded-full">ศิษย์เก่า${p.alumniBatch?' • '+esc(p.alumniBatch):''}</span>`:''}${p.isRoyalScholarship?`<span class="text-[10px] font-bold bg-fuchsia-50 text-fuchsia-700 border border-fuchsia-200 px-2 py-0.5 rounded-full">ทุนเฉลิมราชกุมารี</span>`:''}</div><p class="text-xs text-slate-500 mt-1 line-clamp-2">${esc(isExec?(p.position||''):(p.position||p.department||''))}</p><p class="text-[10px] text-slate-400 mt-1">${p.phone?'☎ '+esc(p.phone):''}${p.phone&&p.email?' • ':''}${p.email?'✉ '+esc(p.email):''}</p></div><div class="flex flex-col gap-2"><button class="p-2.5 rounded-xl bg-orange-50 text-orange-600" data-edit-staff="${i}"><i data-lucide="pencil" class="w-4 h-4"></i></button><button class="p-2.5 rounded-xl bg-red-50 text-red-500" data-delete-staff="${i}"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div></article>`).join('')||'<div class="md:col-span-2 xl:col-span-3 glass rounded-3xl p-10 text-center text-slate-400">ยังไม่มีบุคลากรในหมวดนี้</div>';
  $$('[data-edit-staff]').forEach(b=>b.addEventListener('click',()=>openStaffEditor(+b.dataset.editStaff)));
  $$('[data-delete-staff]').forEach(b=>b.addEventListener('click',async()=>{
    const i=+b.dataset.deleteStaff,item=(settings[currentStaffKind]||[])[i]; if(!item||!confirm('ลบบุคลากรรายการนี้?'))return;
    if(!item.id){toast('ไม่พบรหัสบุคลากร กรุณารีเฟรชหน้า Manager',true);return;}
    const {error}=await db.from('personnel').delete().eq('id',item.id);
    if(error){toast(error.message,true);return;}
    settings[currentStaffKind].splice(i,1);renderStaff();refreshDerived(false);toast('ลบบุคลากรแล้ว');
  }));lucide.createIcons();
}

function openStaffEditor(index=null){
  const editing=index!==null,item=editing?clone(settings[currentStaffKind][index]):{name:'',department:'',position:'',img:'',education:'',phone:'',email:'',isAlumni:false,alumniBatch:'',isRoyalScholarship:false,royalScholarshipBatch:'',royalScholarshipPhase:''};$('#modal-title').textContent=editing?'แก้ไขบุคลากร':'เพิ่มบุคลากร';$('#modal-help').textContent='ข้อมูลนี้จะแสดงในทำเนียบบุคลากรทันทีหลังบันทึก สามารถระบุสถานะศิษย์เก่าและนักเรียนทุนเฉลิมราชกุมารีได้';
  $('#editor-form').innerHTML=`
    <div><label class="label">ชื่อ-นามสกุล</label><input name="name" class="field" value="${esc(item.name)}" required></div>
    <div><label class="label">ตำแหน่ง</label><input name="position" class="field" value="${esc(item.position||'')}"></div>
    <div><label class="label">กลุ่มสาระ / หน้าที่</label><input name="department" class="field" value="${esc(item.department||'')}"></div>
    <div class="rounded-2xl border border-orange-100 bg-orange-50/40 p-4 space-y-4">
      <div><p class="text-sm font-bold text-slate-800">ข้อมูลเพิ่มเติมของบุคลากร</p><p class="text-[10px] text-slate-500 mt-0.5">ข้อมูลส่วนนี้จะแสดงเมื่อเปิดดูรายละเอียดบุคลากร</p></div>
      <div><label class="label">ประวัติการศึกษา</label><textarea name="education" class="field min-h-28" placeholder="เช่น ปริญญาตรี ...&#10;ปริญญาโท ...">${esc(item.education||'')}</textarea><p class="text-[10px] text-slate-400 mt-1">กด Enter เพื่อแยกแต่ละวุฒิ/สถาบันได้</p></div>
      <div class="grid sm:grid-cols-2 gap-3"><div><label class="label">เบอร์โทรศัพท์</label><input name="phone" type="tel" class="field" value="${esc(item.phone||'')}" placeholder="เช่น 08x-xxx-xxxx"></div><div><label class="label">Email</label><input name="email" type="email" class="field" value="${esc(item.email||'')}" placeholder="name@school.ac.th"></div></div>
      <label class="flex items-center gap-3 p-4 rounded-2xl bg-white border border-orange-200 cursor-pointer"><input id="staff-is-alumni" name="isAlumni" type="checkbox" class="w-5 h-5 accent-orange-500" ${item.isAlumni?'checked':''}><div><span class="text-sm font-bold text-slate-800">เคยเป็นศิษย์เก่าโรงเรียน</span><p class="text-[10px] text-slate-500 mt-0.5">ติ๊กเพื่อให้แสดงในทำเนียบศิษย์เก่าและแสดงป้ายศิษย์เก่า</p></div></label>
      <div id="staff-alumni-batch-wrap" class="${item.isAlumni?'':'hidden'}"><label class="label">ศิษย์เก่ารุ่นที่ <span class="text-red-500">*</span></label><input name="alumniBatch" class="field" value="${esc(item.alumniBatch||'')}" placeholder="เช่น รุ่น 25 / รุ่นปีการศึกษา 2560"><p id="staff-alumni-batch-help" class="text-[10px] text-orange-600 mt-1">จำเป็นต้องกรอกเมื่อเลือก “เคยเป็นศิษย์เก่าโรงเรียน”</p></div>
      <div class="rounded-2xl border border-fuchsia-100 bg-fuchsia-50/70 p-4">
        <label class="flex items-center gap-3 cursor-pointer"><input id="staff-is-royal-scholarship" name="isRoyalScholarship" type="checkbox" class="w-5 h-5 accent-fuchsia-600" ${item.isRoyalScholarship?'checked':''}><div><span class="text-sm font-bold text-fuchsia-900">เป็นนักเรียนทุนเฉลิมราชกุมารี</span><p class="text-[10px] text-fuchsia-700 mt-0.5">หากเลือก กรุณาระบุรุ่นและระยะของทุน</p></div></label>
        <div id="staff-royal-scholarship-wrap" class="${item.isRoyalScholarship?'':'hidden'} grid sm:grid-cols-2 gap-3 mt-4">
          <div><label class="label">ทุนรุ่นที่ <span class="text-red-500">*</span></label><input name="royalScholarshipBatch" class="field" value="${esc(item.royalScholarshipBatch||'')}" placeholder="เช่น รุ่น 5"></div>
          <div><label class="label">ระยะ <span class="text-red-500">*</span></label><input name="royalScholarshipPhase" class="field" value="${esc(item.royalScholarshipPhase||'')}" placeholder="เช่น ระยะที่ 2"></div>
        </div>
      </div>
    </div>
    <div><label class="label">รูปภาพ</label><div class="flex gap-2"><input name="img" class="field" value="${esc(item.img||'')}" placeholder="URL รูป หรือกดอัปโหลด"><label class="cursor-pointer px-4 py-3 rounded-2xl bg-slate-100 text-xs font-bold"><input id="modal-staff-upload" type="file" accept="image/*" class="hidden">อัปโหลด</label></div></div>
    <button class="w-full bg-orange-500 text-white rounded-2xl py-3 font-bold">บันทึกรายการ</button>`;
  const staffFile=$('#modal-staff-upload'),staffUrl=$('#editor-form [name="img"]'),alumniCheck=$('#staff-is-alumni'),alumniWrap=$('#staff-alumni-batch-wrap'),alumniInput=$('#editor-form [name="alumniBatch"]'),scholarCheck=$('#staff-is-royal-scholarship'),scholarWrap=$('#staff-royal-scholarship-wrap'),scholarBatch=$('#editor-form [name="royalScholarshipBatch"]'),scholarPhase=$('#editor-form [name="royalScholarshipPhase"]');
  const toggleAlumni=()=>{
    alumniWrap.classList.toggle('hidden',!alumniCheck.checked);
    alumniInput.required=alumniCheck.checked;
    if(!alumniCheck.checked){alumniInput.value='';alumniInput.setCustomValidity('');}
    else if(!alumniInput.value.trim()){alumniInput.setCustomValidity('กรุณาระบุศิษย์เก่ารุ่นที่');}
  };
  alumniCheck.addEventListener('change',toggleAlumni);
  alumniInput.addEventListener('input',()=>alumniInput.setCustomValidity(alumniCheck.checked&&!alumniInput.value.trim()?'กรุณาระบุศิษย์เก่ารุ่นที่':''));
  toggleAlumni();
  const toggleScholarship=()=>{
    scholarWrap.classList.toggle('hidden',!scholarCheck.checked);
    [scholarBatch,scholarPhase].forEach(input=>input.required=scholarCheck.checked);
    if(!scholarCheck.checked){scholarBatch.value='';scholarPhase.value='';scholarBatch.setCustomValidity('');scholarPhase.setCustomValidity('');}
    else{
      scholarBatch.setCustomValidity(scholarBatch.value.trim()?'':'กรุณาระบุรุ่นของทุนเฉลิมราชกุมารี');
      scholarPhase.setCustomValidity(scholarPhase.value.trim()?'':'กรุณาระบุระยะของทุนเฉลิมราชกุมารี');
    }
  };
  scholarCheck.addEventListener('change',toggleScholarship);
  scholarBatch.addEventListener('input',()=>scholarBatch.setCustomValidity(scholarCheck.checked&&!scholarBatch.value.trim()?'กรุณาระบุรุ่นของทุนเฉลิมราชกุมารี':''));
  scholarPhase.addEventListener('input',()=>scholarPhase.setCustomValidity(scholarCheck.checked&&!scholarPhase.value.trim()?'กรุณาระบุระยะของทุนเฉลิมราชกุมารี':''));
  toggleScholarship();
  setImagePreview(staffFile,staffUrl.value,staffUrl.value?'ภาพปัจจุบัน':'ยังไม่ได้เลือกภาพ');staffUrl.addEventListener('input',()=>setImagePreview(staffFile,staffUrl.value,staffUrl.value?'ตัวอย่างจาก URL':'ยังไม่ได้เลือกภาพ'));
  $('#editor-form').onsubmit=async e=>{
    e.preventDefault();
    const f=new FormData(e.currentTarget),isAlumni=f.get('isAlumni')==='on',isRoyalScholarship=f.get('isRoyalScholarship')==='on';
    if(isAlumni&&!String(f.get('alumniBatch')||'').trim()){
      alumniInput.setCustomValidity('กรุณาระบุศิษย์เก่ารุ่นที่');
      alumniInput.reportValidity();
      alumniInput.focus();
      return;
    }
    alumniInput.setCustomValidity('');
    if(isRoyalScholarship && (!String(f.get('royalScholarshipBatch')||'').trim() || !String(f.get('royalScholarshipPhase')||'').trim())){
      if(!String(f.get('royalScholarshipBatch')||'').trim()){scholarBatch.setCustomValidity('กรุณาระบุรุ่นของทุนเฉลิมราชกุมารี');scholarBatch.reportValidity();scholarBatch.focus();}
      else{scholarPhase.setCustomValidity('กรุณาระบุระยะของทุนเฉลิมราชกุมารี');scholarPhase.reportValidity();scholarPhase.focus();}
      return;
    }
    scholarBatch.setCustomValidity('');scholarPhase.setCustomValidity('');
    const value={name:f.get('name'),position:f.get('position'),department:f.get('department'),education:f.get('education'),phone:f.get('phone'),email:f.get('email'),isAlumni,alumniBatch:isAlumni?String(f.get('alumniBatch')||'').trim():'',isRoyalScholarship,royalScholarshipBatch:isRoyalScholarship?String(f.get('royalScholarshipBatch')||'').trim():'',royalScholarshipPhase:isRoyalScholarship?String(f.get('royalScholarshipPhase')||'').trim():'',img:f.get('img'),published:true};
    if(!personnelTableReady){toast('ยังไม่พบตาราง personnel ใน Supabase',true);return;}
    settings[currentStaffKind]=settings[currentStaffKind]||[];
    try{
      if(editing){
        const old=settings[currentStaffKind][index];
        if(!old?.id)throw new Error('ไม่พบรหัสบุคลากร กรุณารีเฟรชหน้า Manager');
        const row=staffToPersonnelRow(value,currentStaffKind,old.sortOrder??index*10);
        const {data,error}=await db.from('personnel').update(row).eq('id',old.id).select().single();
        if(error)throw error; settings[currentStaffKind][index]=personnelRowToStaff(data);
      }else{
        const row=staffToPersonnelRow(value,currentStaffKind,nextPersonnelSortOrder(currentStaffKind));
        const {data,error}=await db.from('personnel').insert(row).select().single();
        if(error)throw error; settings[currentStaffKind].push(personnelRowToStaff(data));
      }
      closeModal();renderStaff();refreshDerived(false);toast(editing?'แก้ไขข้อมูลบุคลากรแล้ว':'เพิ่มบุคลากรแล้ว');
    }catch(err){toast(err.message||'บันทึกบุคลากรไม่สำเร็จ',true);}
  };
  staffFile.onchange=async e=>{if(!e.target.files?.[0])return;const file=e.target.files[0];previewSelectedImage(staffFile,file);const url=await uploadFile(file,'staff');if(url){staffUrl.value=url;setImagePreview(staffFile,url,'อัปโหลดแล้ว • พร้อมบันทึกรายการ')}};openModal();
}

function renderNewsManager(){
  const list=$('#news-list'),status=$('#news-db-status'),addBtn=$('#add-news');
  if(!list)return;
  if(!newsTableReady){
    if(status){status.className='mb-4 rounded-2xl bg-red-50 text-red-700 px-4 py-3 text-xs font-bold';status.textContent='ยังไม่พบตาราง news ใน Supabase — กรุณารันไฟล์ supabase/news-section-upgrade.sql ก่อน';}
    if(addBtn)addBtn.disabled=true;
    list.innerHTML='<div class="rounded-2xl bg-red-50 p-6 text-center text-sm text-red-500">ระบบข่าวยังเชื่อมฐานข้อมูลไม่ได้</div>';
    return;
  }
  if(status){status.className='mb-4 rounded-2xl bg-green-50 text-green-700 px-4 py-3 text-xs font-bold';status.textContent=`เชื่อมต่อ Supabase แล้ว • ข่าวทั้งหมด ${news.length} รายการ • บันทึกอัตโนมัติ`;}
  if(addBtn)addBtn.disabled=false;
  list.innerHTML=news.map((item,i)=>`<div class="flex flex-col sm:flex-row sm:items-center gap-3 rounded-2xl border border-white bg-white/60 p-4">
    <div class="w-full sm:w-28 aspect-video rounded-xl overflow-hidden bg-slate-100 shrink-0">${item.image_url?`<img src="${esc(item.image_url)}" class="w-full h-full object-cover">`:'<div class="w-full h-full flex items-center justify-center text-slate-300"><i data-lucide="newspaper" class="w-7 h-7"></i></div>'}</div>
    <div class="min-w-0 flex-1"><div class="flex flex-wrap items-center gap-2 mb-1"><span class="text-[10px] font-bold px-2 py-0.5 rounded-full ${item.category_color||'bg-orange-100 text-orange-600'}">${esc(item.category||'ข่าวสาร')}</span><span class="text-[10px] text-slate-400">${esc(item.date_text||'')} ${esc(item.month_year||'')}</span></div><p class="text-sm font-bold text-slate-800 line-clamp-2">${esc(item.title||'')}</p><p class="text-[10px] mt-1 ${item.published?'text-green-600':'text-slate-400'}">${item.published?'เผยแพร่บนเว็บไซต์':'ซ่อนจากเว็บไซต์'}</p></div>
    <div class="flex gap-1 shrink-0"><button class="btn-secondary !px-2" data-news-up="${i}" ${i===0?'disabled':''} title="เลื่อนขึ้น">↑</button><button class="btn-secondary !px-2" data-news-down="${i}" ${i===news.length-1?'disabled':''} title="เลื่อนลง">↓</button><button class="p-2.5 rounded-xl bg-orange-50 text-orange-600" data-news-edit="${i}"><i data-lucide="pencil" class="w-4 h-4"></i></button><button class="p-2.5 rounded-xl bg-red-50 text-red-500" data-news-delete="${i}"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div>
  </div>`).join('')||'<div class="rounded-2xl bg-slate-50 p-6 text-center text-sm text-slate-400">ยังไม่มีข่าวสารใน Supabase</div>';
  $$('[data-news-edit]').forEach(b=>b.addEventListener('click',()=>openNewsEditor(+b.dataset.newsEdit)));
  $$('[data-news-delete]').forEach(b=>b.addEventListener('click',()=>deleteNews(+b.dataset.newsDelete)));
  $$('[data-news-up]').forEach(b=>b.addEventListener('click',()=>moveNews(+b.dataset.newsUp,-1)));
  $$('[data-news-down]').forEach(b=>b.addEventListener('click',()=>moveNews(+b.dataset.newsDown,1)));
  if($('#dash-news'))$('#dash-news').textContent=news.length;
  lucide.createIcons();
}

function openNewsEditor(index=null){
  if(!newsTableReady)return toast('กรุณารัน news-section-upgrade.sql ก่อน',true);
  const editing=index!==null,item=editing?clone(news[index]):clone(newsSchema.defaults);
  $('#modal-title').textContent=editing?'แก้ไขข่าวสาร':'เพิ่มข่าวสาร';
  $('#modal-help').textContent='เมื่อกดบันทึก ข่าวจะถูกบันทึกลง Supabase โดยตรง';
  $('#editor-form').innerHTML=newsSchema.fields.map(f=>fieldHtml(f,item,'news')).join('')+`<button class="w-full bg-orange-500 hover:bg-orange-600 text-white rounded-2xl py-3 font-bold">${editing?'บันทึกการแก้ไข':'เผยแพร่ / บันทึกข่าว'}</button>`;
  const imgFile=$('#editor-form [data-modal-file-upload]'),imgUrl=$('#editor-form [name="image_url"]');
  if(imgFile&&imgUrl){
    setImagePreview(imgFile,imgUrl.value,imgUrl.value?'ภาพปัจจุบัน':'ยังไม่ได้เลือกภาพ');
    imgUrl.addEventListener('input',()=>setImagePreview(imgFile,imgUrl.value,imgUrl.value?'ตัวอย่างจาก URL':'ยังไม่ได้เลือกภาพ'));
    imgFile.addEventListener('change',async()=>{if(!imgFile.files?.[0])return;const file=imgFile.files[0];previewSelectedImage(imgFile,file);const url=await uploadFile(file,'news');if(url){imgUrl.value=url;setImagePreview(imgFile,url,'อัปโหลดแล้ว • พร้อมบันทึกข่าว')}});
  }
  $('#editor-form').onsubmit=async e=>{
    e.preventDefault();
    const form=e.currentTarget;
    const row={
      date_text:form.elements.date_text.value.trim(),month_year:form.elements.month_year.value.trim(),
      category:form.elements.category.value.trim()||'ข่าวสาร',category_color:form.elements.category_color.value,
      title:form.elements.title.value.trim(),summary:form.elements.summary.value.trim(),image_url:form.elements.image_url.value.trim(),
      url:form.elements.url.value.trim(),published:form.elements.published.checked
    };
    try{
      let r;
      if(editing){
        r=await db.from('news').update(row).eq('id',item.id).select().single();
      }else{
        const minOrder=news.length?Math.min(...news.map(x=>Number(x.sort_order)||0)):10;
        row.sort_order=minOrder-10;
        r=await db.from('news').insert(row).select().single();
      }
      if(r.error)throw r.error;
      if(editing)news[index]=r.data;else news.unshift(r.data);
      closeModal();renderNewsManager();refreshDerived(false);toast('บันทึกข่าวสารลง Supabase แล้ว');
    }catch(err){toast('บันทึกข่าวไม่สำเร็จ: '+err.message,true)}
  };
  openModal();
}

async function deleteNews(index){
  if(!confirm('ลบข่าวนี้ออกจาก Supabase ถาวร?'))return;
  const item=news[index];
  const {error}=await db.from('news').delete().eq('id',item.id);
  if(error)return toast(error.message,true);
  news.splice(index,1);renderNewsManager();refreshDerived(false);toast('ลบข่าวแล้ว');
}

async function moveNews(index,dir){
  const to=index+dir;if(to<0||to>=news.length)return;
  const a=news[index],b=news[to];
  let aOrder=Number(a.sort_order),bOrder=Number(b.sort_order);
  if(!Number.isFinite(aOrder))aOrder=index*10;
  if(!Number.isFinite(bOrder))bOrder=to*10;
  if(aOrder===bOrder){aOrder=index*10;bOrder=to*10;}
  const [ra,rb]=await Promise.all([db.from('news').update({sort_order:bOrder}).eq('id',a.id),db.from('news').update({sort_order:aOrder}).eq('id',b.id)]);
  if(ra.error||rb.error)return toast((ra.error||rb.error).message,true);
  a.sort_order=bOrder;b.sort_order=aOrder;[news[index],news[to]]=[news[to],news[index]];renderNewsManager();toast('อัปเดตลำดับข่าวแล้ว');
}

function collectionContainerId(path){return 'collection-'+path.replaceAll('.','-')}
function renderCollection(path){
  const schema=collectionSchemas[path],container=$('#'+collectionContainerId(path));if(!schema||!container)return;const arr=getPath(settings,path)||[];
  container.innerHTML=arr.map((item,i)=>`<div class="flex items-center gap-3 rounded-2xl border border-white bg-white/60 p-4"><div class="w-9 h-9 rounded-xl ${item.published===false?'bg-slate-100 text-slate-400':'bg-orange-50 text-orange-600'} flex items-center justify-center shrink-0"><i data-lucide="${item.published===false?'eye-off':'check-circle-2'}" class="w-4 h-4"></i></div><div class="min-w-0 flex-1"><p class="text-sm font-bold text-slate-800 line-clamp-2">${esc(schema.summary(item))}</p><p class="text-[10px] mt-1 ${item.published===false?'text-slate-400':'text-green-600'}">${item.published===false?'ซ่อนจากเว็บไซต์':'แสดงบนเว็บไซต์'}</p></div><div class="flex gap-1 shrink-0"><button class="btn-secondary !px-2" data-col-up="${path}|${i}" title="เลื่อนขึ้น">↑</button><button class="btn-secondary !px-2" data-col-down="${path}|${i}" title="เลื่อนลง">↓</button><button class="p-2.5 rounded-xl bg-orange-50 text-orange-600" data-col-edit="${path}|${i}"><i data-lucide="pencil" class="w-4 h-4"></i></button><button class="p-2.5 rounded-xl bg-red-50 text-red-500" data-col-delete="${path}|${i}"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div></div>`).join('')||`<div class="rounded-2xl bg-slate-50 p-6 text-center text-sm text-slate-400">${esc(schema.empty)}</div>`;
  $$(`[data-col-edit^="${path}|"]`).forEach(b=>b.addEventListener('click',()=>openCollectionEditor(path,Number(b.dataset.colEdit.split('|')[1]))));
  $$(`[data-col-delete^="${path}|"]`).forEach(b=>b.addEventListener('click',()=>{const i=Number(b.dataset.colDelete.split('|')[1]);if(confirm('ลบรายการนี้?')){arr.splice(i,1);renderCollection(path);markDirty()}}));
  $$(`[data-col-up^="${path}|"]`).forEach(b=>b.addEventListener('click',()=>moveCollection(path,Number(b.dataset.colUp.split('|')[1]),-1)));$$(`[data-col-down^="${path}|"]`).forEach(b=>b.addEventListener('click',()=>moveCollection(path,Number(b.dataset.colDown.split('|')[1]),1)));lucide.createIcons();
}
function moveCollection(path,index,dir){const arr=getPath(settings,path)||[],to=index+dir;if(to<0||to>=arr.length)return;[arr[index],arr[to]]=[arr[to],arr[index]];renderCollection(path);markDirty()}
function openCollectionEditor(path,index=null){
  const schema=collectionSchemas[path];if(!schema)return;const arr=getPath(settings,path)||[];const editing=index!==null,item=editing?clone(arr[index]):clone(schema.defaults);$('#modal-title').textContent=(editing?'แก้ไข':'เพิ่ม')+schema.title;$('#modal-help').textContent='กรอกข้อมูลตามช่อง ไม่ต้องแก้โค้ดหรือ JSON';
  $('#editor-form').innerHTML=schema.fields.map(f=>fieldHtml(f,item,path)).join('')+`<button class="w-full bg-orange-500 hover:bg-orange-600 text-white rounded-2xl py-3 font-bold">${editing?'บันทึกการแก้ไข':'เพิ่มรายการ'}</button>`;
  hydrateSpecialFields(item);
  $$('[data-modal-file-upload]').forEach(inp=>{
    const target=$('#editor-form').elements[inp.dataset.targetName];
    if(inp.accept?.includes('image')){
      setImagePreview(inp,target?.value||'',target?.value?'ภาพปัจจุบัน':'ยังไม่ได้เลือกภาพ');
      target?.addEventListener('input',()=>setImagePreview(inp,target.value,target.value?'ตัวอย่างจาก URL':'ยังไม่ได้เลือกภาพ'));
    }
    inp.addEventListener('change',async()=>{
      if(!inp.files?.[0])return;
      const file=inp.files[0];
      if(inp.accept?.includes('image')) previewSelectedImage(inp,file);
      const url=await uploadFile(file,inp.dataset.modalFileUpload||'document');
      if(url&&target){target.value=url;if(inp.accept?.includes('image'))setImagePreview(inp,url,'อัปโหลดแล้ว • พร้อมบันทึกรายการ')}
    });
  });
  $('#editor-form').onsubmit=e=>{e.preventDefault();const form=e.currentTarget,next=clone(item);schema.fields.forEach(f=>{if(f.type==='quickColor')return;const el=form.elements[f.name];if(!el)return;let v=f.type==='checkbox'?el.checked:el.value;if(f.type==='number'&&v!=='')v=Number(v);next[f.name]=v});if(path==='quickLinks'){const color=form.elements.colorPicker.value;const found=colorOptions.find(x=>x[0]===color)||colorOptions[0];next.bg=found[2];next.text=found[3]};if(!getPath(settings,path))setPath(settings,path,[]);const target=getPath(settings,path);if(editing)target[index]=next;else target.push(next);closeModal();renderCollection(path);markDirty()};openModal();
}
function fieldHtml(f,item,path){
  const val=item[f.name]??'';if(f.type==='textarea')return `<div><label class="label">${f.label}</label><textarea name="${f.name}" class="field min-h-24" ${f.required?'required':''}>${esc(val)}</textarea></div>`;
  if(f.type==='checkbox')return `<label class="flex items-center gap-3 p-4 rounded-2xl bg-slate-50 border border-slate-100"><input name="${f.name}" type="checkbox" class="w-5 h-5 accent-orange-500" ${val!==false?'checked':''}><span class="text-sm font-bold">${f.label}</span></label>`;
  if(f.type==='icon')return `<div><label class="label">${f.label}</label><select name="${f.name}" class="field">${iconOptions.map(([value,label])=>`<option value="${value}" ${val===value?'selected':''}>${label}</option>`).join('')}</select></div>`;
  if(f.type==='badgeColor'){const key=Object.entries(badgeColors).find(([,cls])=>cls===val)?.[0]||'orange';return `<div><label class="label">${f.label}</label><select name="${f.name}" class="field">${Object.entries({orange:'ส้ม',red:'แดง',green:'เขียว',blue:'น้ำเงิน',purple:'ม่วง',amber:'เหลือง'}).map(([k,n])=>`<option value="${badgeColors[k]}" ${key===k?'selected':''}>${n}</option>`).join('')}</select></div>`}
  if(f.type==='boxColor'){return `<div><label class="label">${f.label}</label><select name="${f.name}" class="field">${colorOptions.map(x=>`<option value="${x[2]} ${x[3]}" ${val===`${x[2]} ${x[3]}`?'selected':''}>${x[1]}</option>`).join('')}</select></div>`}
  if(f.type==='quickColor'){const current=colorOptions.find(x=>x[2]===item.bg&&x[3]===item.text)?.[0]||'orange';return `<div><label class="label">${f.label}</label><select name="colorPicker" class="field">${colorOptions.map(x=>`<option value="${x[0]}" ${current===x[0]?'selected':''}>${x[1]}</option>`).join('')}</select></div>`}
  if(f.type==='image')return `<div><label class="label">${f.label}</label><div class="flex gap-2"><input name="${f.name}" class="field" value="${esc(val)}" placeholder="URL รูป หรือกดอัปโหลด"><label class="cursor-pointer px-4 py-3 rounded-2xl bg-slate-100 text-xs font-bold shrink-0"><input type="file" accept="image/*" class="hidden" data-modal-file-upload="${esc(f.uploadPrefix||'image')}" data-target-name="${f.name}">อัปโหลดภาพ</label></div></div>`;
  return `<div><label class="label">${f.label}</label><input name="${f.name}" type="${f.type||'text'}" class="field" value="${esc(val)}" placeholder="${esc(f.placeholder||'')}" ${f.required?'required':''} ${f.min!==undefined?`min="${f.min}"`:''} ${f.max!==undefined?`max="${f.max}"`:''}></div>`;
}
function hydrateSpecialFields(){lucide.createIcons()}

function renderAchievements(){
  const list=$('#achievement-list');list.innerHTML=achievements.map((x,i)=>`<article class="glass rounded-[2rem] overflow-hidden"><div class="aspect-video bg-slate-100">${x.image_url?`<img src="${esc(x.image_url)}" class="w-full h-full object-cover">`:''}</div><div class="p-5"><div class="flex gap-2 items-start justify-between"><div><span class="text-[10px] font-bold text-orange-600">ปี ${esc(x.year||'-')}</span><h4 class="font-bold mt-1 leading-relaxed">${esc(x.title||'')}</h4></div><span class="text-[10px] ${x.published?'bg-green-50 text-green-600':'bg-slate-100 text-slate-500'} px-2 py-1 rounded-full">${x.published?'เผยแพร่':'ซ่อน'}</span></div><div class="flex gap-2 mt-4"><button class="flex-1 py-2 rounded-xl bg-orange-50 text-orange-600 text-xs font-bold" data-edit-ach="${i}">แก้ไข</button><button class="px-3 py-2 rounded-xl bg-red-50 text-red-500" data-delete-ach="${i}"><i data-lucide="trash-2" class="w-4 h-4"></i></button></div></div></article>`).join('')||'<div class="sm:col-span-2 xl:col-span-3 glass rounded-3xl p-10 text-center text-slate-400">ยังไม่มีผลงาน</div>';
  $$('[data-edit-ach]').forEach(b=>b.addEventListener('click',()=>openAchievementEditor(+b.dataset.editAch)));$$('[data-delete-ach]').forEach(b=>b.addEventListener('click',()=>deleteAchievement(+b.dataset.deleteAch)));$('#dash-achievements').textContent=achievements.length;lucide.createIcons();
}
function openAchievementEditor(index=null){
  const editing=index!==null,item=editing?clone(achievements[index]):{title:'',year:String(new Date().getFullYear()+543),image_url:'',description:'',published:true};$('#modal-title').textContent=editing?'แก้ไขผลงาน':'เพิ่มผลงาน';$('#modal-help').textContent='ผลงานที่เผยแพร่ล่าสุดจะถูกนำไปแสดงหน้าแรก 3 รายการ';
  $('#editor-form').innerHTML=`<div><label class="label">ชื่อผลงาน</label><input name="title" class="field" value="${esc(item.title)}" required></div><div><label class="label">ปี</label><input name="year" class="field" value="${esc(item.year||'')}"></div><div><label class="label">รายละเอียด</label><textarea name="description" class="field min-h-24">${esc(item.description||'')}</textarea></div><div><label class="label">รูปภาพ</label><div class="flex gap-2"><input name="image_url" class="field" value="${esc(item.image_url||'')}" placeholder="URL รูป หรือกดอัปโหลด"><label class="cursor-pointer px-4 py-3 rounded-2xl bg-slate-100 text-xs font-bold"><input id="modal-ach-upload" type="file" accept="image/*" class="hidden">อัปโหลด</label></div></div><label class="flex items-center gap-3 p-4 rounded-2xl bg-slate-50"><input name="published" type="checkbox" class="w-5 h-5 accent-orange-500" ${item.published!==false?'checked':''}><span class="text-sm font-bold">เผยแพร่บนเว็บไซต์</span></label><button class="w-full bg-orange-500 text-white rounded-2xl py-3 font-bold">บันทึกผลงาน</button>`;
  const achFile=$('#modal-ach-upload'),achUrl=$('#editor-form [name="image_url"]');setImagePreview(achFile,achUrl.value,achUrl.value?'ภาพปัจจุบัน':'ยังไม่ได้เลือกภาพ');achUrl.addEventListener('input',()=>setImagePreview(achFile,achUrl.value,achUrl.value?'ตัวอย่างจาก URL':'ยังไม่ได้เลือกภาพ'));
  $('#editor-form').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.currentTarget),row={title:f.get('title'),year:f.get('year'),description:f.get('description'),image_url:f.get('image_url'),published:f.get('published')==='on'};try{let r;if(editing)r=await db.from('achievements').update(row).eq('id',item.id).select().single();else r=await db.from('achievements').insert(row).select().single();if(r.error)throw r.error;if(editing)achievements[index]=r.data;else achievements.unshift(r.data);closeModal();renderAchievements();toast('บันทึกผลงานแล้ว')}catch(err){toast(err.message,true)}};
  achFile.onchange=async e=>{if(!e.target.files?.[0])return;const file=e.target.files[0];previewSelectedImage(achFile,file);const url=await uploadFile(file,'achievement');if(url){achUrl.value=url;setImagePreview(achFile,url,'อัปโหลดแล้ว • พร้อมบันทึกผลงาน')}};openModal();
}
async function deleteAchievement(index){if(!confirm('ลบผลงานรายการนี้ถาวร?'))return;const item=achievements[index],{error}=await db.from('achievements').delete().eq('id',item.id);if(error)return toast(error.message,true);achievements.splice(index,1);renderAchievements();toast('ลบผลงานแล้ว')}

function openModal(){const m=$('#editor-modal');m.classList.remove('hidden');m.classList.add('flex');lucide.createIcons()}
function closeModal(){const m=$('#editor-modal');m.classList.add('hidden');m.classList.remove('flex');$('#editor-form').onsubmit=null}
async function uploadFile(file,prefix='media'){
  try{const ext=(file.name.split('.').pop()||'bin').toLowerCase(),name=`${prefix}/${Date.now()}-${crypto.randomUUID()}.${ext}`;toast('กำลังอัปโหลดไฟล์...');const {error}=await db.storage.from(bucket).upload(name,file,{cacheControl:'3600',upsert:false});if(error)throw error;const {data}=db.storage.from(bucket).getPublicUrl(name);toast('อัปโหลดเรียบร้อย');return data.publicUrl}catch(e){toast('อัปโหลดไม่สำเร็จ: '+e.message,true);return null}
}

start();
