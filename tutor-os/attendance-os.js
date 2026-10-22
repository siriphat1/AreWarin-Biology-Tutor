/* AreWarin Tutor OS · Attendance Center 20.1
   Drop-in module for Tutor OS V19.7: shares the Supabase session but uses its own auditable ledger.
   Requires sql/01_attendance_migration.sql; intentionally DOES NOT alter legacy course wallets. */
(()=>{
'use strict';
const $=s=>document.querySelector(s);
const ROOT='#section-attendance';
const T={db:null,data:null,catalog:null,mode:'single',student:'',tutor:'',filter:'',saving:false,batch:[],lastRequest:null};
const esc=v=>String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const minuteText=v=>{let m=Number(v)||0;return `${(m/60).toLocaleString('th-TH',{maximumFractionDigits:2})} ชม.`};
const today=()=>{const parts=new Intl.DateTimeFormat('en-US',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date());const part=k=>parts.find(x=>x.type===k)?.value;return `${part('year')}-${part('month')}-${part('day')}`};
const showDate=v=>{if(!v)return '-';const d=new Date(`${String(v).slice(0,10)}T12:00:00+07:00`);return new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric',month:'short',year:'2-digit'}).format(d)};
const safeTime=v=>String(v||'').slice(0,5);
const alertUser=(m,bad=false)=>{const el=$('#awosNotice');if(el){el.textContent=m;el.className=`awos-notice ${bad?'error':'ok'}`;el.hidden=false;el.scrollIntoView({block:'nearest',behavior:'smooth'});} if(bad)console.warn('[Attendance Center]',m)};
const parseMinutes=(a,b)=>{
 if(!/^\d{2}:\d{2}$/.test(a)||!/^\d{2}:\d{2}$/.test(b))return 0;
 const [h1,m1]=a.split(':').map(Number),[h2,m2]=b.split(':').map(Number);
 if(h1>23||h2>23||m1>59||m2>59)return 0;
 const d=h2*60+m2-h1*60-m1;return d>0&&d<=600?d:0;
};
const genId=()=>crypto?.randomUUID?.()||'00000000-0000-4000-8000-'+Math.random().toString(16).slice(2).padEnd(12,'0');
function getDb(){
 if(T.db)return T.db;
 for(const db of [window.AreWarinAPI?.sb,window.awSupabase,window.supabaseClient,window.sb,window.__awTutorManagerClient]){
   if(db?.rpc&&db?.auth){T.db=db;return db;}
 }
 const cfg=window.AREWARIN_CONFIG||{};
 const url=cfg.SUPABASE_URL||cfg.supabaseUrl||'';
 const key=cfg.SUPABASE_ANON_KEY||cfg.SUPABASE_PUBLISHABLE_KEY||cfg.supabaseAnonKey||'';
 if(window.supabase?.createClient&&url&&key){T.db=window.supabase.createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});return T.db;}
 throw Error('ยังไม่พบการตั้งค่า Supabase — ตรวจสอบ ../config.js');
}
async function rpc(name,args={}){const db=getDb(),{data,error}=await db.rpc(name,args);if(error)throw error;return data}
function role(){return T.data?.actor?.role||'tutor'}
function mine(){return T.data?.roster||[]}
function currentRoster(){return mine().filter(r=>(!T.tutor||r.tutor_ref===T.tutor)&&r.active).sort((a,b)=>a.student_name.localeCompare(b.student_name,'th'))}
function findStudent(id){return mine().find(r=>r.student_ref===id&&r.tutor_ref===T.tutor)}
function currentRecords(){return(T.data?.records||[]).filter(r=>(!T.tutor||r.tutor_ref===T.tutor)&&(!T.filter||r.student_ref===T.filter))}
function options(rows,sel='',empty='— เลือก —',vf=r=>r.student_ref,lf=r=>r.student_name){return `<option value="">${empty}</option>`+rows.map(r=>`<option value="${esc(vf(r))}" ${String(vf(r))===String(sel)?'selected':''}>${esc(lf(r))}</option>`).join('')}
function tutorList(){return [...new Set((T.data?.roster||[]).map(x=>x.tutor_ref).concat((T.data?.access||[]).map(x=>x.tutor_ref).filter(Boolean)).concat((T.catalog?.tutors||[]).map(x=>String(x.id))))].sort()}
function tutorOptions(sel=T.tutor){return tutorList().map(id=>{const t=(T.catalog?.tutors||[]).find(x=>String(x.id)===id);return `<option value="${esc(id)}" ${sel===id?'selected':''}>${esc(t?.display_name||t?.name||id)}</option>`}).join('')}
function makeCss(){const css=`
#section-attendance .awos-head{display:flex;justify-content:space-between;gap:14px;align-items:center;flex-wrap:wrap;margin-bottom:17px}
#section-attendance h1{font-size:23px;margin:4px 0;color:#172033}#section-attendance h2{font-size:15px;margin:0 0 12px;color:#172033}#section-attendance .awos-sub{font-size:11px;color:#64748b;line-height:1.7}
#section-attendance .awos-card{background:#fff;border:1px solid #e5eaf1;border-radius:19px;padding:18px;box-shadow:0 14px 35px -30px #64748b;margin-bottom:15px}
#section-attendance .awos-hero{background:linear-gradient(110deg,#101e35,#1e3a58);color:#fff;border:0;padding:22px}#section-attendance .awos-hero h1{color:#fff}#section-attendance .awos-hero .awos-sub{color:#cbd5e1}
#section-attendance .awos-stats{display:grid;grid-template-columns:repeat(3,1fr);gap:10px;margin-bottom:15px}#section-attendance .awos-stats .awos-card{margin:0}#section-attendance .awos-num{font-size:25px;font-weight:700;color:#0f172a}#section-attendance .awos-muted{font-size:11px;color:#64748b}
#section-attendance .awos-modes{display:flex;flex-wrap:wrap;gap:7px;margin-bottom:13px}#section-attendance .awos-mode{border:1px solid #e2e8f0;padding:10px 15px;background:#fff;color:#64748b;border-radius:12px;font-size:12px;font-weight:600;cursor:pointer}#section-attendance .awos-mode.active{background:#0f172a;border-color:#0f172a;color:#fff}
#section-attendance .awos-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:13px}#section-attendance .awos-full{grid-column:1/-1}
#section-attendance label.awos-label{display:flex;flex-direction:column;gap:7px;font-size:11px;font-weight:600;color:#475569}
#section-attendance .awos-input{background:#fff;width:100%;min-height:43px;border:1px solid #dbe3ed;border-radius:11px;padding:9px 12px;font-family:inherit;font-size:13px;color:#172033;outline:none}#section-attendance .awos-input:focus{border-color:#0ea5e9;box-shadow:0 0 0 3px #e0f2fe}
#section-attendance .awos-btn{padding:10px 14px;border-radius:12px;border:1px solid #e2e8f0;background:#fff;color:#334155;font-family:inherit;font-size:12px;font-weight:600;cursor:pointer}#section-attendance .awos-btn.primary{color:#fff;background:#0f172a;border-color:#0f172a}#section-attendance .awos-btn.danger{color:#be123c;background:#fff1f2;border-color:#fecdd3}#section-attendance .awos-btn:disabled{opacity:.55;cursor:not-allowed}
#section-attendance .awos-actions{display:flex;gap:8px;flex-wrap:wrap;align-items:center}#section-attendance .awos-rows{display:flex;flex-direction:column;gap:8px}#section-attendance .awos-item{border:1px solid #e2e8f0;border-radius:12px;padding:12px;display:flex;justify-content:space-between;gap:10px;align-items:center}#section-attendance .awos-item b{font-size:12px}#section-attendance .awos-item small{font-size:10px;color:#64748b;display:block;line-height:1.7}
#section-attendance .awos-checkbox{display:flex;align-items:center;gap:10px;padding:9px 5px;cursor:pointer;font-size:12px;border-bottom:1px solid #f1f5f9}#section-attendance .awos-checkbox input{accent-color:#0ea5e9;width:17px;height:17px}
#section-attendance .awos-notice{padding:12px;border-radius:12px;font-size:12px;margin-bottom:12px}#section-attendance .awos-notice.ok{background:#ecfdf5;color:#047857}#section-attendance .awos-notice.error{background:#fff1f2;color:#be123c}
#section-attendance .awos-pill{background:#eff6ff;color:#1d4ed8;font-size:10px;border-radius:99px;padding:4px 10px;display:inline-block}#section-attendance .awos-pill.warn{background:#fff7ed;color:#c2410c}
#section-attendance .awos-divider{border:0;border-top:1px solid #edf1f6;margin:17px 0}
#section-attendance .awos-twocol{display:grid;grid-template-columns:1.2fr .8fr;gap:15px}#section-attendance .awos-dialog{position:fixed;inset:0;background:#0f172a91;z-index:99999;display:grid;place-items:center;padding:15px}#section-attendance .awos-dialog-body{width:min(540px,100%);background:#fff;border-radius:20px;padding:22px;max-height:85vh;overflow:auto}
#section-attendance .awos-batchrow{display:grid;grid-template-columns:1.2fr 1fr 1fr auto;gap:8px;margin-bottom:8px}
@media(max-width:700px){#section-attendance .awos-stats{grid-template-columns:repeat(2,1fr)}#section-attendance .awos-stats .awos-card:first-child{grid-column:1/-1}#section-attendance .awos-grid,#section-attendance .awos-twocol{grid-template-columns:1fr}#section-attendance .awos-batchrow{grid-template-columns:1fr 1fr}#section-attendance .awos-batchrow input:first-child{grid-column:1/-1}#section-attendance .awos-batchrow button{grid-column:1/-1}}
`;const st=document.createElement('style');st.textContent=css;document.head.appendChild(st)}
async function activate(){
 document.querySelectorAll('.section').forEach(s=>s.classList.remove('active'));
 document.querySelectorAll('.nav-btn').forEach(b=>b.classList.remove('active'));
 $('#awosAttendanceNav')?.classList.add('active');
 const root=$(ROOT);root.classList.add('active');root.innerHTML='<div class="awos-card">กำลังตรวจสอบสิทธิ์และโหลดข้อมูล...</div>';
 try{const db=getDb();const {data,error}=await db.auth.getUser();if(error||!data?.user)throw Error('กรุณาเข้าสู่ระบบ Tutor OS ก่อนใช้เมนูลงเวลา');await refresh()}
 catch(e){renderError(e.message||String(e))}
}
function renderError(msg){$(ROOT).innerHTML=`<div class="awos-card"><h2>ไม่สามารถเปิดระบบลงเวลาได้</h2><p class="awos-sub" style="color:#be123c">${esc(msg)}</p><p class="awos-sub">ตรวจสอบว่าได้รัน SQL Migration, ผูกสิทธิ์ awos_access และใช้บัญชี Supabase Auth แล้ว</p><button class="awos-btn" id="awosRetry">ลองอีกครั้ง</button></div>`;$('#awosRetry').onclick=activate}
async function refresh(){
 T.data=await rpc('awos_bootstrap');
 if(role()==='tutor')T.tutor=T.data.actor.tutor_ref;
 if(role()==='admin'&&!T.tutor){T.tutor=T.data?.roster?.[0]?.tutor_ref||''}
 if(T.student&&!findStudent(T.student))T.student='';
 render();
}
function buildStudentSelect(){return `<select id="awosStudent" class="awos-input">${options(currentRoster(),T.student,'เลือกนักเรียน')}</select>`}
function head(){const as=T.data?.actor||{};return `<div class="awos-card awos-hero"><div class="awos-head"><div><div class="awos-sub">AREWARIN BIOLOGY · TUTOR OS 20.1</div><h1>ลงเวลาเรียน</h1><div class="awos-sub">เลือกนักเรียน → ใส่วันที่และเวลา → ตรวจสอบก่อนบันทึก · ชั่วโมงคำนวณจากนาทีจริง</div></div><span class="awos-pill">${as.role==='admin'?'ADMIN':'TUTOR'} · ${esc(as.display_name||as.tutor_ref||'')}</span></div></div>`}
function stats(){const a=currentRoster(),m=a.reduce((s,r)=>s+Number(r.used_minutes||0),0),low=a.filter(r=>Number(r.target_minutes)>0 && Number(r.target_minutes)-Number(r.used_minutes)<300).length;return `<div class="awos-stats"><div class="awos-card"><div class="awos-muted">นักเรียนที่ลงเวลาได้</div><div class="awos-num">${a.length}</div></div><div class="awos-card"><div class="awos-muted">ชั่วโมงในระบบลงเวลา</div><div class="awos-num">${minuteText(m)}</div></div><div class="awos-card"><div class="awos-muted">ใกล้เป้าหมาย ≤ 5 ชม.</div><div class="awos-num">${low}</div></div></div>`}
function studentBadge(){const s=findStudent(T.student);if(!s)return `<div class="awos-muted">เลือกนักเรียนเพื่อดูสถิติ</div>`;const used=+s.used_minutes||0,target=+s.target_minutes||0;return `<div class="awos-card" style="background:#f8fafc"><b>${esc(s.student_name)}</b><div class="awos-sub">เรียนแล้ว <b>${minuteText(used)}</b> · เป้าหมาย ${minuteText(target)} · คงเหลือ ${target?minuteText(Math.max(0,target-used)):'ยังไม่ตั้งเป้าหมาย'}</div><div style="height:7px;border-radius:10px;background:#e2e8f0;margin-top:10px;overflow:hidden"><div style="height:7px;width:${target?Math.min(100,used/target*100):0}%;background:#0ea5e9"></div></div></div>`}
function filters(){return role()==='admin'?`<label class="awos-label">แสดงข้อมูลของติวเตอร์<select id="awosTutor" class="awos-input">${tutorOptions()}</select></label>`:''}
function form(){const day=today();let body='';
 if(T.mode==='single')body=`<div class="awos-grid"><label class="awos-label">นักเรียน ${buildStudentSelect()}</label><label class="awos-label">วันที่เรียน<input id="awosDate" class="awos-input" type="date" value="${day}"></label><label class="awos-label">สถานะ<select id="awosStatus" class="awos-input"><option value="present">มาเรียน</option><option value="leave">ลาหยุด (ไม่หักชั่วโมง)</option></select></label><label class="awos-label">หัวข้อ<input id="awosTopic" class="awos-input" placeholder="เช่น Cell Biology"></label><label class="awos-label awos-clock">เริ่ม<input id="awosIn" class="awos-input" type="time" value="17:00"></label><label class="awos-label awos-clock">สิ้นสุด<input id="awosOut" class="awos-input" type="time" value="19:00"></label><label class="awos-label awos-full">บันทึก / เหตุผลการลา<textarea id="awosNote" class="awos-input" rows="2" placeholder="หัวข้อย่อย การบ้าน หรือเหตุผลการลา"></textarea></label></div><div class="awos-actions" style="margin:12px 0"><span id="awosDuration" class="awos-pill">120 นาที (2 ชม.)</span><button class="awos-btn" data-quick="60">+1 ชม.</button><button class="awos-btn" data-quick="90">+1.5 ชม.</button><button class="awos-btn" data-quick="120">+2 ชม.</button></div><div id="awosStudentStats">${studentBadge()}</div><button id="awosSubmit" class="awos-btn primary">ตรวจสอบและบันทึกเวลา</button>`;
 if(T.mode==='group')body=`<div class="awos-grid"><label class="awos-label">วันที่สอน<input id="awosDate" class="awos-input" type="date" value="${day}"></label><label class="awos-label">ชื่อกลุ่ม / ห้องเรียน<input id="awosGroupLabel" class="awos-input" placeholder="เช่น ชีววิทยา ม.4"></label><label class="awos-label">เวลาเริ่ม<input id="awosIn" class="awos-input" type="time" value="17:00"></label><label class="awos-label">เวลาสิ้นสุด<input id="awosOut" class="awos-input" type="time" value="19:00"></label><label class="awos-label awos-full">หัวข้อ<input id="awosTopic" class="awos-input" placeholder="หัวข้อที่เรียนร่วมกัน"></label><label class="awos-label awos-full">หมายเหตุ<textarea id="awosNote" class="awos-input" rows="2"></textarea></label></div><hr class="awos-divider"><div class="awos-actions"><h2 style="margin:0">เลือกคนที่มาเรียน</h2><button class="awos-btn" id="awosAll">เลือกทั้งหมด</button><button class="awos-btn" id="awosNone">ล้าง</button></div><div class="awos-rows" style="max-height:230px;overflow:auto;margin:10px 0">${currentRoster().map(r=>`<label class="awos-checkbox"><input type="checkbox" class="awosMember" value="${esc(r.student_ref)}"><span>${esc(r.student_name)}</span><span class="awos-muted" style="margin-left:auto">${minuteText(r.used_minutes||0)}</span></label>`).join('')||'ยังไม่มีนักเรียน'}</div><p class="awos-sub" id="awosGroupPreview">เลือกนักเรียนเพื่อดูจำนวนรายการ</p><button id="awosSubmit" class="awos-btn primary">ตรวจสอบและบันทึกทั้งกลุ่ม</button>`;
 if(T.mode==='batch')body=`<div class="awos-grid"><label class="awos-label">นักเรียน ${buildStudentSelect()}</label><label class="awos-label">หัวข้อหลัก<input id="awosTopic" class="awos-input" placeholder="เช่น ชีววิทยา A-Level"></label></div><div class="awos-rows" id="awosBatchRows" style="margin-top:14px"></div><div class="awos-actions"><button id="awosAddBatch" class="awos-btn">+ เพิ่มวันที่</button><span id="awosBatchSum" class="awos-pill">0 นาที</span></div><hr class="awos-divider"><div id="awosStudentStats">${studentBadge()}</div><button id="awosSubmit" class="awos-btn primary">ตรวจสอบและบันทึกหลายวัน</button>`;
 return `<div class="awos-card"><div class="awos-head"><h2>บันทึกการเรียน</h2><small class="awos-sub">ไม่ให้บันทึกเวลาซ้อนกัน และไม่ใช้เวลาจากเครื่องเพื่อตัดยอดในฐานข้อมูล</small></div><div class="awos-modes">${[['single','คนเดียว'],['group','ทั้งกลุ่ม'],['batch','หลายวัน']].map(([k,l])=>`<button class="awos-mode ${T.mode===k?'active':''}" data-mode="${k}">${l}</button>`).join('')}</div>${body}</div>`;
}
function history(){const all=currentRecords(),a=mine();return `<div class="awos-card"><div class="awos-head"><div><h2>ประวัติลงเวลา</h2><div class="awos-sub">แสดง 500 รายการล่าสุด (ยอดชั่วโมงรวมคำนวณจากข้อมูลทั้งหมด)</div></div><div class="awos-actions"><select id="awosHistoryFilter" class="awos-input" style="width:190px"><option value="">ทุกคน</option>${a.filter(r=>!T.tutor||r.tutor_ref===T.tutor).map(r=>`<option value="${esc(r.student_ref)}" ${T.filter===r.student_ref?'selected':''}>${esc(r.student_name)}</option>`).join('')}</select><button class="awos-btn" id="awosExport">ส่งออก CSV</button></div></div><div class="awos-rows">${all.slice(0,50).map(r=>{const s=mine().find(x=>x.student_ref===r.student_ref&&x.tutor_ref===r.tutor_ref);return `<div class="awos-item"><div><b>${esc(s?.student_name||r.student_ref)} · ${showDate(r.lesson_date)}</b><small>${r.status==='leave'?'ลาหยุด · ไม่หักชั่วโมง':`${esc(safeTime(r.start_time))}–${esc(safeTime(r.end_time))} · ${minuteText(r.duration_minutes)}`} ${esc(r.topic||'')}</small>${r.note?`<small>หมายเหตุ: ${esc(r.note)}</small>`:''}</div><div class="awos-actions"><button class="awos-btn" data-edit="${esc(r.id)}">แก้ไข</button><button class="awos-btn danger" data-delete="${esc(r.id)}">ลบ</button></div></div>`}).join('')||'<div class="awos-sub">ยังไม่มีประวัติลงเวลา</div>'}</div></div>`}
function adminView(){
 if(role()!=='admin')return '';
 const ac=T.data?.access||[];
 const tcat=T.catalog?.tutors||[], scat=T.catalog?.students||[];
 const tOpts=tcat.length?'<option value="">เลือกติวเตอร์</option>'+tcat.map(t=>`<option value="${esc(t.id)}">${esc(t.display_name||t.fullname||t.id)}</option>`).join(''):'<option value="">กดอ่านรายชื่อหรือกรอก Tutor ID ด้านล่าง</option>';
 const sOpts='<option value="">เลือกนักเรียน</option>'+scat.map(s=>{
   const nm=s.nickname||s.display_name||s.fullname||[s.first_name,s.last_name].filter(Boolean).join(' ')||s.student_code||s.id;
   return `<option value="${esc(s.id)}">${esc(nm)}</option>`;
 }).join('');
 const accessNames=ac.map(a=>esc(a.display_name||a.user_id)+' ('+esc(a.role)+')').join(', ')||'ยังไม่มี';
 return `<div class="awos-card">
 <div class="awos-head"><div><h2>เชื่อมข้อมูล Tutor OS · สำหรับ Admin</h2><p class="awos-sub">จับคู่นักเรียนเดิมกับติวเตอร์ก่อนลงเวลา ระบบจะไม่แก้หรือสร้างนักเรียนซ้ำใน CRM</p></div><button class="awos-btn" id="awosCatalogReload">อ่านรายชื่อจาก Tutor OS</button></div>
 <div class="awos-grid">
 <label class="awos-label">Tutor ID<select id="awosAdminTutor" class="awos-input">${tOpts}</select></label>
 <label class="awos-label">กรอก Tutor ID (หากไม่มีในรายการ)<input id="awosAdminTutorCustom" class="awos-input" placeholder="รหัสจากตาราง tutors"></label>
 <label class="awos-label">นักเรียนเดิม<select id="awosAdminStudent" class="awos-input">${sOpts}</select></label>
 <label class="awos-label">Student ID (กรอกเองได้)<input id="awosAdminStudentCustom" class="awos-input" placeholder="ID ในตาราง students"></label>
 <label class="awos-label">ชื่อนักเรียน<input id="awosAdminStudentName" class="awos-input" placeholder="ชื่อที่ใช้แสดงในหน้าลงเวลา"></label>
 <label class="awos-label">เป้าหมายคอร์ส (ชั่วโมง)<input id="awosAdminTarget" class="awos-input" type="number" min="0" step="0.25" value="0"></label>
 </div><div class="awos-actions" style="margin-top:12px"><button class="awos-btn primary" id="awosLink">ผูกนักเรียนเข้าติวเตอร์</button></div>
 <hr class="awos-divider"><h2>สิทธิ์เข้าระบบลงเวลา</h2><p class="awos-sub">บัญชีต้องมีอยู่ใน Supabase Auth แล้ว การเพิ่มชื่อในตารางนี้ไม่ใช่การสร้างรหัสผ่านหรือส่งอีเมลเชิญ</p>
 <div class="awos-grid">
 <label class="awos-label">Auth User UUID<input id="awosAccessId" class="awos-input" placeholder="UUID จาก Authentication → Users"></label>
 <label class="awos-label">ชื่อแสดง<input id="awosAccessName" class="awos-input" placeholder="ชื่อผู้สอน"></label>
 <label class="awos-label">บทบาท<select id="awosAccessRole" class="awos-input"><option value="tutor">Tutor</option><option value="admin">Admin</option></select></label>
 <label class="awos-label">Tutor ID<input id="awosAccessTutor" class="awos-input" placeholder="สำหรับ Tutor เท่านั้น"></label>
 <label class="awos-label">สถานะ<select id="awosAccessEnabled" class="awos-input"><option value="true">เปิดใช้งาน</option><option value="false">ระงับ</option></select></label>
 </div><div class="awos-actions" style="margin-top:12px"><button class="awos-btn" id="awosAccessSave">กำหนดสิทธิ์</button></div>
 <p class="awos-sub" style="margin-top:10px">บัญชีที่ผูกแล้ว ${ac.length} รายการ: ${accessNames}</p></div>`;
}
function render(){
 const root=$(ROOT);if(!root)return;
 root.innerHTML=`${head()}<div id="awosNotice" class="awos-notice" hidden></div>${stats()}${role()==='admin'?`<div class="awos-card">${filters()}</div>`:''}${form()}${history()}${adminView()}<p class="awos-sub" style="padding:5px 6px 25px">⚠️ ยอดชั่วโมงในหน้าลงเวลานี้เป็น Attendance Ledger ใหม่ ไม่ได้ตัด Course Wallet/Hourly Group Ledger เดิมอัตโนมัติ เพื่อป้องกันการตัดซ้ำจนกว่าจะเชื่อมคอร์สโดยตรง</p>`;
 bind();
}
function batchRender(){const host=$('#awosBatchRows');if(!host)return;host.innerHTML=T.batch.map((r,i)=>`<div class="awos-batchrow" data-idx="${i}"><input aria-label="วันที่" class="awos-input" type="date" data-field="date" value="${esc(r.date)}"><input aria-label="เข้า" class="awos-input" type="time" data-field="start" value="${esc(r.start)}"><input aria-label="ออก" class="awos-input" type="time" data-field="end" value="${esc(r.end)}"><button class="awos-btn danger" data-remove="${i}">ลบ</button></div>`).join('');batchStats()}
function batchStats(){const m=T.batch.reduce((t,r)=>t+parseMinutes(r.start,r.end),0);if($('#awosBatchSum'))$('#awosBatchSum').textContent=`${T.batch.length} รายการ · ${minuteText(m)}`}
function groupStats(){const count=document.querySelectorAll('.awosMember:checked').length;const m=parseMinutes($('#awosIn')?.value||'', $('#awosOut')?.value||'');if($('#awosGroupPreview'))$('#awosGroupPreview').textContent=`เลือก ${count} คน · ${minuteText(m)} ต่อคน · รวม ${(count*m/60).toFixed(2)} ชั่วโมง-นักเรียน`}
function timeStats(){const leave=$('#awosStatus')?.value==='leave';document.querySelectorAll('.awos-clock').forEach(e=>e.style.display=leave?'none':'');if($('#awosDuration'))$('#awosDuration').textContent=leave?'ลาหยุด · 0 นาที':`${parseMinutes($('#awosIn')?.value||'',$('#awosOut')?.value||'')} นาที`}
function bind(){
 $(ROOT).querySelectorAll('[data-mode]').forEach(el=>el.onclick=()=>{T.mode=el.dataset.mode;if(T.mode==='batch'&&!T.batch.length)T.batch=[{date:today(),start:'17:00',end:'19:00'}];render()});
 $('#awosTutor')?.addEventListener('change',e=>{T.tutor=e.target.value;T.student='';T.filter='';render()});
 $('#awosStudent')?.addEventListener('change',e=>{T.student=e.target.value;renderStudentOnly()});
 $('#awosStatus')?.addEventListener('change',timeStats);
 for(const selector of ['#awosIn','#awosOut'])$(selector)?.addEventListener('input',()=>{timeStats();groupStats()});
 $(ROOT).querySelectorAll('[data-quick]').forEach(b=>b.onclick=()=>{const start=$('#awosIn');const end=$('#awosOut');let t=start.value||'17:00';let m=t.split(':').map(Number);let total=m[0]*60+m[1]+Number(b.dataset.quick);if(total>=1440){alertUser('เวลาจบข้ามวัน กรุณาแบ่งเป็น 2 รายการ',true);return;}end.value=String(Math.floor(total/60)).padStart(2,'0')+':'+String(total%60).padStart(2,'0');timeStats()});
 $(ROOT).querySelectorAll('.awosMember').forEach(x=>x.onchange=groupStats);
 $('#awosAll')?.addEventListener('click',()=>{$(ROOT).querySelectorAll('.awosMember').forEach(x=>x.checked=true);groupStats()});
 $('#awosNone')?.addEventListener('click',()=>{$(ROOT).querySelectorAll('.awosMember').forEach(x=>x.checked=false);groupStats()});
 $('#awosAddBatch')?.addEventListener('click',()=>{if(T.batch.length>=50)return alertUser('สูงสุด 50 วันต่อชุด',true);T.batch.push({date:today(),start:'17:00',end:'19:00'});batchRender()});
 $('#awosBatchRows')?.addEventListener('change',e=>{const row=e.target.closest('[data-idx]');if(row){const item=T.batch[+row.dataset.idx];item[e.target.dataset.field]=e.target.value;batchStats()}});
 $('#awosBatchRows')?.addEventListener('click',e=>{const b=e.target.closest('[data-remove]');if(b){T.batch.splice(+b.dataset.remove,1);batchRender()}});
 $('#awosSubmit')?.addEventListener('click',submit);
 $('#awosHistoryFilter')?.addEventListener('change',e=>{T.filter=e.target.value;render()});
 $(ROOT).querySelectorAll('[data-edit]').forEach(b=>b.onclick=()=>editRecord(b.dataset.edit));
 $(ROOT).querySelectorAll('[data-delete]').forEach(b=>b.onclick=()=>deleteRecord(b.dataset.delete));
 $('#awosExport')?.addEventListener('click',exportCSV);
 $('#awosCatalogReload')?.addEventListener('click',catalogLoad);
 $('#awosAdminStudent')?.addEventListener('change',e=>{const s=(T.catalog?.students||[]).find(x=>String(x.id)===e.target.value);if(s)$('#awosAdminStudentName').value=s.nickname||s.display_name||s.fullname||[s.first_name,s.last_name].filter(Boolean).join(' ')||s.student_code||String(s.id)});
 $('#awosLink')?.addEventListener('click',adminLink);
 $('#awosAccessSave')?.addEventListener('click',accessSave);
 timeStats();groupStats();if(T.mode==='batch')batchRender();
}
function renderStudentOnly(){// keep entered form data intact instead of re-rendering whole form
 const p=$('#awosStudent')?.value||'';T.student=p;
 // stats panel is immediately after controls in single/batch mode
 const badge=$(ROOT).querySelector('#awosStudentStats');if(badge){badge.innerHTML=studentBadge()}
}
async function confirmAction(text){if(window.Swal?.fire){const r=await window.Swal.fire({title:'ยืนยันข้อมูล',text,icon:'question',showCancelButton:true,confirmButtonText:'ยืนยันบันทึก',cancelButtonText:'กลับไปแก้ไข'});return r.isConfirmed;}return window.confirm(text)}
async function submit(){
 if(T.saving)return;
 if(!T.tutor)return alertUser('ยังไม่ได้เลือกติวเตอร์ หรือ Admin ยังไม่ได้ผูกนักเรียน',true);
 const commonTopic=($('#awosTopic')?.value||'').trim(),commonNote=($('#awosNote')?.value||'').trim();
 let list=[];
 if(T.mode==='single'){
   if(!T.student)return alertUser('กรุณาเลือกนักเรียน',true);
   list=[{student_ref:T.student,lesson_date:$('#awosDate').value,status:$('#awosStatus').value,start_time:$('#awosIn').value,end_time:$('#awosOut').value,topic:commonTopic,note:commonNote}];
 }else if(T.mode==='group'){
   const ids=[...$(ROOT).querySelectorAll('.awosMember:checked')].map(x=>x.value);
   if(!ids.length)return alertUser('กรุณาเลือกนักเรียนอย่างน้อย 1 คน',true);
   list=ids.map(id=>({student_ref:id,lesson_date:$('#awosDate').value,status:'present',start_time:$('#awosIn').value,end_time:$('#awosOut').value,topic:commonTopic,note:commonNote,group_label:$('#awosGroupLabel').value}));
 }else{
   if(!T.student||!T.batch.length)return alertUser('กรุณาเลือกนักเรียนและเพิ่มวัน',true);
   if(T.batch.length>1&&new Set(T.batch.map(r=>r.date+':'+r.start+':'+r.end)).size!==T.batch.length)return alertUser('พบรายการวันและเวลาซ้ำในชุดเดียวกัน',true);
   list=T.batch.map(r=>({student_ref:T.student,lesson_date:r.date,status:'present',start_time:r.start,end_time:r.end,topic:commonTopic,note:'Batch entry'}));
 }
 if(list.some(x=>!x.lesson_date||!x.student_ref))return alertUser('ข้อมูลนักเรียนหรือวันที่ไม่ครบ',true);
 if(list.some(x=>x.status==='present'&&!parseMinutes(x.start_time,x.end_time)))return alertUser('เวลาเริ่ม/จบไม่ถูกต้อง (ต้องอยู่ในวันเดียวกันและไม่เกิน 10 ชม.)',true);
 const total=list.reduce((s,x)=>s+(x.status==='leave'?0:parseMinutes(x.start_time,x.end_time)),0);
 const ok=await confirmAction(`บันทึก ${list.length} รายการ · ${minuteText(total)} · ${showDate(list[0].lesson_date)} — หากมีเวลาเรียนซ้อน ระบบจะปฏิเสธทั้งชุด`);
 if(!ok)return;
 T.saving=true;$('#awosSubmit').disabled=true;
 try{
   const request=genId();const result=await rpc('awos_save_records',{p_tutor_ref:T.tutor,p_request_id:request,p_records:list});
   T.lastRequest=request;if(T.mode==='batch')T.batch=[];await refresh();alertUser(`บันทึกสำเร็จ ${result.inserted} รายการ · ${minuteText(result.minutes)} (บันทึกใน Supabase แล้ว)`);
 }catch(e){alertUser(`${e.message||e} — ไม่มีรายการใหม่ในชุดนี้ถูกบันทึกหากธุรกรรมล้มเหลว`,true)}
 finally{T.saving=false;if($('#awosSubmit'))$('#awosSubmit').disabled=false}
}
function popup(title,content,onSave){const panel=$(ROOT);const div=document.createElement('div');div.className='awos-dialog';div.innerHTML=`<div class="awos-dialog-body"><h2>${esc(title)}</h2>${content}<div class="awos-actions" style="margin-top:16px"><button class="awos-btn" id="awosCancelDialog">ยกเลิก</button><button class="awos-btn primary" id="awosSaveDialog">บันทึก</button></div><p id="awosDialogError" class="awos-sub" style="color:#be123c"></p></div>`;panel.appendChild(div);div.querySelector('#awosCancelDialog').onclick=()=>div.remove();div.querySelector('#awosSaveDialog').onclick=async()=>{const b=div.querySelector('#awosSaveDialog');b.disabled=true;try{await onSave(div);div.remove();await refresh();alertUser('บันทึกการแก้ไขสำเร็จ')}catch(e){div.querySelector('#awosDialogError').textContent=e.message||e}finally{b.disabled=false}};div.addEventListener('click',e=>{if(e.target===div)div.remove()})}
function editRecord(id){const r=(T.data.records||[]).find(x=>x.id===id);if(!r)return;popup('แก้ไขบันทึก',`<div class="awos-grid"><label class="awos-label">วันที่<input id="awosEDate" class="awos-input" type="date" value="${esc(r.lesson_date)}"></label><label class="awos-label">สถานะ<select id="awosEStatus" class="awos-input"><option value="present" ${r.status==='present'?'selected':''}>มาเรียน</option><option value="leave" ${r.status==='leave'?'selected':''}>ลา</option></select></label><label class="awos-label">เริ่ม<input id="awosEIn" class="awos-input" type="time" value="${esc(safeTime(r.start_time))}"></label><label class="awos-label">จบ<input id="awosEOut" class="awos-input" type="time" value="${esc(safeTime(r.end_time))}"></label><label class="awos-label awos-full">หัวข้อ<input id="awosETopic" class="awos-input" value="${esc(r.topic)}"></label><label class="awos-label awos-full">หมายเหตุ<textarea id="awosENote" class="awos-input" rows="3">${esc(r.note)}</textarea></label></div>`,async box=>{
 const q=id=>box.querySelector('#'+id).value,status=q('awosEStatus');if(status==='present'&&!parseMinutes(q('awosEIn'),q('awosEOut')))throw Error('เวลาเริ่ม/จบไม่ถูกต้อง');
 await rpc('awos_update_record',{p_id:id,p_record:{lesson_date:q('awosEDate'),status,start_time:q('awosEIn'),end_time:q('awosEOut'),topic:q('awosETopic'),note:q('awosENote')}})
})}
async function deleteRecord(id){if(!await confirmAction('ลบรายการลงเวลานี้? ระบบจะเก็บ Audit Log ไว้และคำนวณยอดชั่วโมงใหม่'))return;try{await rpc('awos_delete_record',{p_id:id});await refresh();alertUser('ลบรายการสำเร็จ พร้อมปรับยอดชั่วโมงที่คำนวณใหม่')}catch(e){alertUser(e.message||e,true)}}
function exportCSV(){const rows=currentRecords(),fields=['lesson_date','student_ref','tutor_ref','status','start_time','end_time','duration_minutes','topic','note','group_label'];const csv=['วันที่,รหัสนักเรียน,รหัสติวเตอร์,สถานะ,เวลาเริ่ม,เวลาจบ,นาที,หัวข้อ,หมายเหตุ,กลุ่ม',...rows.map(r=>fields.map(k=>'"'+String(r[k]??'').replaceAll('"','""')+'"').join(','))].join('\r\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob(['\ufeff'+csv],{type:'text/csv;charset=utf-8'}));a.download=`attendance_${today()}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}
async function catalogLoad(){try{T.catalog=await rpc('awos_catalog');render();alertUser(`โหลดรายชื่อจาก Tutor OS แล้ว: นักเรียน ${(T.catalog?.students||[]).length} คน / ติวเตอร์ ${(T.catalog?.tutors||[]).length} คน`)}catch(e){alertUser('โหลดรายชื่อไม่ได้: '+(e.message||e),true)}}
async function adminLink(){try{const tutor=$('#awosAdminTutorCustom').value.trim()||$('#awosAdminTutor').value.trim(),student=$('#awosAdminStudentCustom').value.trim()||$('#awosAdminStudent').value.trim(),name=$('#awosAdminStudentName').value.trim(),h=Number($('#awosAdminTarget').value);if(!tutor||!student||!name||!Number.isFinite(h)||h<0||h>10000)throw Error('กรุณาระบุ Tutor ID, Student ID, ชื่อ และเป้าหมายที่ถูกต้อง');await rpc('awos_roster_upsert',{p_tutor_ref:tutor,p_student_ref:student,p_student_name:name,p_target_minutes:Math.round(h*60),p_active:true});T.tutor=tutor;await refresh();alertUser('ผูกนักเรียนกับติวเตอร์เรียบร้อย (Attendance roster)')}catch(e){alertUser(e.message||e,true)}}
async function accessSave(){try{const id=$('#awosAccessId').value.trim(),name=$('#awosAccessName').value.trim(),role=$('#awosAccessRole').value,tutor=$('#awosAccessTutor').value.trim()||null,enabled=$('#awosAccessEnabled').value==='true';if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id))throw Error('Auth User UUID ไม่ถูกต้อง');await rpc('awos_access_upsert',{p_user_id:id,p_role:role,p_tutor_ref:tutor,p_display_name:name,p_enabled:enabled});await refresh();alertUser('กำหนดสิทธิ์ลงเวลาแล้ว')}catch(e){alertUser(e.message||e,true)}}
function init(){if(!$(ROOT)||!$('#awosAttendanceNav'))return;makeCss();
 // Capture-phase interception prevents older Tutor OS navigation from attempting to render an unknown section.
 $('#awosAttendanceNav').addEventListener('click',e=>{e.preventDefault();e.stopImmediatePropagation();activate()},true);
 $('#awosAttendanceNav').addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();e.stopImmediatePropagation();activate()}},true);
}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
window.AreWarinAttendance={open:activate,refresh,minutesBetween:parseMinutes};
})();
