(() => {
  'use strict';
  const sb = window.AreWarinAPI?.sb;
  const cfg = window.AREWARIN_CONFIG || {};
  const $ = id => document.getElementById(id);
  const esc = v => String(v ?? '').replace(/[&<>'"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const cleanPhone = v => String(v||'').replace(/\D/g,'');
  const DRAFT_KEY='arewarin_tutor_application_draft_v1';
  let step=1, eduSeq=0, workSeq=0, tutorPolicyRevision=1;
  let currentLang=localStorage.getItem('arewarin_tutor_language')==='en'?'en':'th';
  let cachedTutorPolicy=null, subjectRows=[];

  const days=[
    {key:'mon',th:'จันทร์',en:'Monday'},{key:'tue',th:'อังคาร',en:'Tuesday'},{key:'wed',th:'พุธ',en:'Wednesday'},
    {key:'thu',th:'พฤหัสบดี',en:'Thursday'},{key:'fri',th:'ศุกร์',en:'Friday'},{key:'sat',th:'เสาร์',en:'Saturday'},{key:'sun',th:'อาทิตย์',en:'Sunday'}
  ];
  const fallbackSubjects=[
    {id:'bio',name_th:'ชีววิทยา',name_en:'Biology',icon_class:'fas fa-dna'},
    {id:'chem',name_th:'เคมี',name_en:'Chemistry',icon_class:'fas fa-flask'},
    {id:'sci',name_th:'วิทยาศาสตร์',name_en:'Science',icon_class:'fas fa-atom'},
    {id:'math',name_th:'คณิตศาสตร์',name_en:'Mathematics',icon_class:'fas fa-calculator'},
    {id:'other',name_th:'อื่นๆ',name_en:'Other',icon_class:'fas fa-book-open'}
  ];

  const STATIC_EN = {
    'เช็คสถานะใบสมัคร':'Check application status','กลับหน้าหลัก':'Back to home',
    'มาร่วมสร้างการเรียนรู้ที่ดีกับ':'Build better learning with',
    'เรามองหาผู้สอนที่รักการถ่ายทอดความรู้ รับผิดชอบต่อผู้เรียน และพร้อมทำงานร่วมกับทีมอย่างเป็นมืออาชีพ':'We welcome educators who love teaching, take responsibility for learners, and are ready to work professionally with our team.',
    'ดูนโยบายและเริ่มสมัคร':'View policies & apply','เช็คสถานะใบสมัครเดิม':'Check existing application',
    'แชร์ความรู้':'Share knowledge','จัดตารางร่วมกัน':'Flexible scheduling','เติบโตกับทีม':'Grow with the team',
    'พื้นที่สำหรับผู้สอนที่อยากสร้างผลลัพธ์กับผู้เรียน':'A place for educators who want to make a real impact',
    'ระบบหลังบ้านช่วยจัดการโปรไฟล์ คอร์ส ตารางสอน และการจับคู่ผู้เรียน โดยข้อมูลที่กรอกในใบสมัครจะถูกส่งให้ทีมงานตรวจสอบก่อนทุกครั้ง':'Our system helps manage profiles, courses, schedules, and student matching. Every application is reviewed by our team before any teaching assignment.',
    'สอนได้หลายระดับ':'Teach multiple levels','ระบุวิชา ระดับ และสไตล์การสอนของคุณได้':'Choose your subjects, learner levels, and teaching style.',
    'วันว่างยืดหยุ่น':'Flexible availability','แจ้งวันที่สะดวกเพื่อใช้จับคู่กับตารางผู้เรียน':'Share your availability so we can match you with suitable learners.',
    'กระบวนการชัดเจน':'Clear process','ติดตามสถานะใบสมัครได้ด้วยเลขใบสมัครและเบอร์โทร':'Track your application using your application number and phone.',
    'ขั้นตอนการร่วมทีม':'Application process','อ่านนโยบาย':'Read policies','ทำความเข้าใจกติกาและแนวทางการทำงาน':'Review our policies and working guidelines.',
    'ส่งใบสมัคร':'Submit application','กรอกประวัติ วิชาที่สอน และวันว่าง':'Complete your profile, subjects, and availability.',
    'ทีมตรวจสอบ':'Team review','ตรวจข้อมูล เอกสาร และความเหมาะสม':'We review your information, documents, and fit.',
    'พูดคุย / ทดลองสอน':'Interview / demo lesson','ยืนยันรายละเอียดก่อนเริ่มร่วมงานจริง':'Confirm details before joining the teaching team.',
    'นโยบายและกติกาสำหรับผู้สมัครติวเตอร์':'Policies & guidelines for tutor applicants',
    'กรุณาอ่านแนวทางการทำงานให้ครบก่อนเริ่มกรอกใบสมัคร':'Please review the working guidelines before starting your application.',
    'กำลังโหลดนโยบาย...':'Loading policies...','ฉันได้อ่านและยอมรับนโยบายสำหรับผู้สมัครติวเตอร์':'I have read and accept the tutor applicant policies.',
    'โปรดยืนยันก่อนเริ่มกรอกใบสมัคร':'Please confirm before starting your application.','กลับหน้าต้อนรับ':'Back to welcome','ยอมรับและเริ่มสมัคร':'Accept & start application',
    'สมัครร่วมทีมติวเตอร์':'Apply to join our tutor team',
    'เปิดรับผู้สอนที่รักการถ่ายทอดความรู้ มีความรับผิดชอบ และพร้อมเติบโตไปกับผู้เรียน กรอกข้อมูลครั้งเดียว ทีมงานจะตรวจสอบประวัติและติดต่อกลับตามลำดับ':'We welcome educators who care about teaching, learner progress, and professional growth. Complete one application and our team will review your profile and contact you.',
    'ขั้นตอน':'Steps','ข้อมูลปลอดภัย':'Secure data','แนบเอกสารได้':'Document upload',
    'ข้อมูลส่วนตัว':'Personal details','การศึกษา & งาน':'Education & work','การสอน & วันว่าง':'Teaching & availability','เอกสาร & ยืนยัน':'Documents & consent',
    'ระบบบันทึกร่างอัตโนมัติในอุปกรณ์นี้ โดยไม่บันทึกไฟล์แนบจนกว่าจะกดส่ง':'Your draft is saved locally on this device. Attachments are not uploaded until you submit.',
    'ข้อมูลส่วนตัวและช่องทางติดต่อ':'Personal information & contact','ใช้สำหรับตรวจสอบใบสมัครและติดต่อเพื่อนัดพูดคุยเท่านั้น':'Used to review your application and contact you about the next steps.',
    'ชื่อ':'First name','นามสกุล':'Last name','ชื่อเล่น':'Preferred name / nickname','เบอร์โทร':'Phone number','อีเมล':'Email',
    'สัญชาติ':'Nationality','ประเทศที่พำนัก':'Country of residence','จังหวัด / เมืองที่พักปัจจุบัน':'Current province / city',
    'อาชีพ / สถานะปัจจุบัน':'Current occupation / status','แนะนำตัวสั้นๆ':'Short introduction',
    'ประวัติการศึกษาและประสบการณ์ทำงาน':'Education & work experience','สามารถเพิ่มได้หลายรายการ เรียงจากข้อมูลล่าสุดก่อน':'You can add multiple entries. Please list the most recent first.',
    'ประวัติการศึกษา':'Education','มหาวิทยาลัย / ปริญญา / สาขา / ปี':'Institution / degree / major / year','เพิ่มการศึกษา':'Add education',
    'ประวัติการทำงาน / การสอน':'Work / teaching experience','ถ้ายังไม่มีประสบการณ์สามารถเว้นได้':'Optional if you do not have prior experience.','เพิ่มประสบการณ์':'Add experience',
    'รางวัล / ใบประกาศ / ผลงานที่เกี่ยวข้อง':'Awards / certificates / relevant achievements',
    'วิชาที่สอน ระดับผู้เรียน และวันที่สะดวก':'Subjects, learner levels & availability','เลือกได้หลายรายการ เพื่อให้ทีมงานจับคู่กับคอร์สและผู้เรียนได้เหมาะสม':'Select all that apply so we can match you with suitable courses and learners.',
    'วิชาที่สนใจสอน':'Subjects you can teach','ระดับผู้เรียนที่สอนได้':'Learner levels','ประถมศึกษา':'Primary','มัธยมต้น':'Lower secondary','มัธยมปลาย':'Upper secondary','มหาวิทยาลัย':'University',
    'รูปแบบการสอนที่สะดวก':'Preferred teaching mode','ประสบการณ์สอน (ปี)':'Teaching experience (years)','เรทที่คาดหวัง / ชม.':'Expected rate / hour',
    'พื้นที่ Onsite ที่สะดวก':'Preferred onsite area','วันที่และเวลาที่สะดวกประจำ':'Regular availability','เลือกวัน แล้วระบุช่วงเวลาที่โดยทั่วไปสะดวก':'Select days and your usual available time range.',
    'แก้ไขภายหลังได้':'Can be updated later','สไตล์การสอน':'Teaching style','เหตุผลที่อยากร่วมทีม AreWarin':'Why do you want to join AreWarin?',
    'เอกสารประกอบและการยืนยันข้อมูล':'Documents & confirmation','ไฟล์ทั้งหมดจะเก็บในพื้นที่ส่วนตัวของระบบ และเปิดดูได้เฉพาะ Manager/Admin':'All files are stored privately and can only be accessed by authorized Manager/Admin users.',
    'รูปโปรไฟล์ (ถ้ามี)':'Profile photo (optional)','JPG / PNG / WebP ไม่เกิน 5 MB':'JPG / PNG / WebP, max 5 MB','PDF หรือรูป ไม่เกิน 10 MB':'PDF or image, max 10 MB',
    'Portfolio / ผลงาน':'Portfolio / work samples','ถ้ามี — PDF หรือรูป ไม่เกิน 10 MB':'Optional — PDF or image, max 10 MB','Transcript / เอกสารการศึกษา':'Transcript / education document',
    'ข้อความเพิ่มเติม':'Additional notes','ข้าพเจ้ารับรองว่าข้อมูลที่กรอกเป็นความจริงและสามารถตรวจสอบได้':'I certify that the information provided is true and can be verified.',
    'ยินยอมให้ AreWarin Biology เก็บและใช้ข้อมูลนี้เพื่อพิจารณาการร่วมงาน การติดต่อ และการบริหารบุคลากรตามวัตถุประสงค์ที่เกี่ยวข้อง':'I consent to AreWarin Biology collecting and using this information for recruitment, contact, and relevant personnel administration purposes.',
    'การส่งใบสมัครไม่ได้ถือเป็นการรับเข้าทำงานหรือรับเป็นติวเตอร์ทันที ทีมงานอาจนัดสัมภาษณ์ ทดลองสอน หรือตรวจเอกสารเพิ่มเติมก่อนยืนยันผล':'Submitting an application does not guarantee employment or a teaching assignment. We may request an interview, demo lesson, or additional documents before making a decision.',
    'ย้อนกลับ':'Back','บันทึกร่างอัตโนมัติ':'Autosave draft','ถัดไป':'Next','หลังส่งใบสมัคร':'After you apply',
    'ระบบจะออกเลขใบสมัครให้ทันที จากนั้น Manager จะตรวจข้อมูลและเอกสาร คุณสามารถกลับมาเช็คสถานะด้วยเลขใบสมัครและเบอร์โทรได้ตลอดเวลา':'You will receive an application number immediately. Our Manager will review your information and documents, and you can check your status anytime using your application number and phone.',
    'ตรวจประวัติ':'Profile review','นัดพูดคุย':'Interview','ยืนยันร่วมทีม':'Join team'
  };
  const PLACEHOLDER_EN = {
    'ชื่อจริง':'First name','นามสกุล':'Last name','ชื่อที่อยากให้เรียก':'Preferred name',
    'ถ้ามี':'Optional','เช่น ไทย / British':'e.g. Thai / British','เช่น Thailand':'e.g. Thailand',
    'เช่น ขอนแก่น / Bangkok':'e.g. Khon Kaen / Bangkok','เช่น นักศึกษา ป.โท / ครู / นักวิจัย':'e.g. graduate student / teacher / researcher',
    'เล่าเกี่ยวกับตัวเอง ความสนใจ และสิ่งที่อยากให้ทีมงานรู้จัก':'Tell us about yourself, your interests, and anything you would like the team to know.',
    'เช่น สอวน., งานวิจัย, รางวัลการสอน, คะแนนสอบ, ผลงานวิชาการ':'e.g. Olympiad programs, research, teaching awards, test scores, academic work',
    'ระบุได้ถ้ามี':'Optional','เช่น ขอนแก่น / นครราชสีมา / ตามตกลง':'e.g. Khon Kaen / Nakhon Ratchasima / negotiable',
    'เช่น เน้นปูพื้นฐาน ใช้ภาพ เชื่อมโยงโจทย์ หรือเน้น active learning':'e.g. concept building, visual learning, exam connections, active learning',
    'สิ่งที่สนใจเกี่ยวกับการสอนหรือทีมของเรา':'What interests you about teaching or our team?',
    'เช่น วันที่สะดวกเริ่มงาน ข้อจำกัด หรือข้อมูลอื่นที่อยากแจ้ง':'e.g. available start date, constraints, or other information'
  };
  const staticTextNodes=new WeakMap(), staticPlaceholders=new WeakMap();
  function captureStaticLanguage(){
    const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode:n=>n.parentElement&& !['SCRIPT','STYLE'].includes(n.parentElement.tagName)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT});
    let n;while(n=walker.nextNode())staticTextNodes.set(n,n.nodeValue);
    document.querySelectorAll('input[placeholder],textarea[placeholder]').forEach(el=>staticPlaceholders.set(el,el.getAttribute('placeholder')));
  }
  function translateStatic(){
    staticTextNodes.forEach?.(()=>{});
    const walker=document.createTreeWalker(document.body,NodeFilter.SHOW_TEXT,{acceptNode:n=>staticTextNodes.has(n)?NodeFilter.FILTER_ACCEPT:NodeFilter.FILTER_REJECT});
    let n;while(n=walker.nextNode()){
      const original=staticTextNodes.get(n)||'';
      const trimmed=original.trim();
      const translated=currentLang==='en'?(STATIC_EN[trimmed]||trimmed):trimmed;
      n.nodeValue=original.replace(trimmed,translated);
    }
    document.querySelectorAll('input[placeholder],textarea[placeholder]').forEach(el=>{
      const original=staticPlaceholders.get(el);
      if(original!=null)el.setAttribute('placeholder',currentLang==='en'?(PLACEHOLDER_EN[original]||original):original);
    });
    document.documentElement.lang=currentLang;
    document.title=currentLang==='en'?'Tutor Application | AreWarin Biology':'สมัครเป็นติวเตอร์ | AreWarin Biology';
    if($('langTh')){$('langTh').classList.toggle('active',currentLang==='th');$('langTh').setAttribute('aria-pressed',String(currentLang==='th'));}
    if($('langEn')){$('langEn').classList.toggle('active',currentLang==='en');$('langEn').setAttribute('aria-pressed',String(currentLang==='en'));}
  }
  const L=(th,en)=>currentLang==='en'?en:th;

  function toast(icon,title,text=''){return Swal.fire({icon,title,text,confirmButtonColor:'#0f172a',customClass:{popup:'rounded-[1.5rem]'}})}
  function formatPhoneInput(){
    const el=$('phone');const raw=String(el.value||'').trim();const hasPlus=raw.startsWith('+');let v=cleanPhone(raw).slice(0,15);
    if(hasPlus){el.value='+'+v;return;}
    if(v.startsWith('0')&&v.length<=10){el.value=v.length>6?`${v.slice(0,3)}-${v.slice(3,6)}-${v.slice(6)}`:v.length>3?`${v.slice(0,3)}-${v.slice(3)}`:v;return;}
    el.value=v;
  }
  function setStep(n){step=Math.max(1,Math.min(4,n));document.querySelectorAll('.step-pane').forEach(p=>p.classList.toggle('active',Number(p.dataset.step)===step));document.querySelectorAll('[data-step-indicator]').forEach(x=>{const s=Number(x.dataset.stepIndicator);x.classList.toggle('active',s===step);x.classList.toggle('done',s<step);x.querySelector('.step-dot').innerHTML=s<step?'<i class="fas fa-check"></i>':String(s)});$('btnBack').classList.toggle('invisible',step===1);$('btnNext').classList.toggle('hidden',step===4);$('btnSubmit').classList.toggle('hidden',step!==4);window.scrollTo({top:80,behavior:'smooth'});}

  function showOnboardView(name){['welcome','policy','application'].forEach(v=>{const el=$(v+'View');if(el)el.classList.toggle('hidden',v!==name)});window.scrollTo({top:0,behavior:'smooth'});}
  function localizedField(row,base){return currentLang==='en'?(row?.[base+'_en']||row?.[base]||''):(row?.[base]||row?.[base+'_en']||'');}
  function renderTutorPolicySections(rows){
    const el=$('tutorPolicySections');if(!el)return;
    if(!rows?.length){el.innerHTML=`<div class="col-span-full py-10 text-center text-[10px] text-slate-400">${L('ยังไม่มีรายการนโยบาย','No policy items yet.')}</div>`;return;}
    el.innerHTML=rows.map(x=>{const content=localizedField(x,'content');const lines=String(content||'').split(/\n+/).map(v=>v.trim()).filter(Boolean);const title=localizedField(x,'title'),caption=localizedField(x,'caption');return `<article class="policy-card policy-theme-${esc(x.theme||'blue')}"><div class="policy-card-head"><div class="policy-card-icon"><i class="${esc(x.icon_class||'fas fa-circle-info')}"></i></div><div><h3>${esc(title||'')}</h3>${caption?`<small>${esc(caption)}</small>`:''}</div></div><div class="policy-list">${lines.map(line=>`<div class="policy-line"><i class="fas fa-circle"></i><span>${esc(line.replace(/^[-•]\s*/,''))}</span></div>`).join('')}</div></article>`}).join('');
  }
  function applyTutorPolicyLanguage(){
    const res=cachedTutorPolicy;if(!res?.page)return;const pg=res.page;
    tutorPolicyRevision=Number(pg.revision||1);$('tutorPolicyRevision').value=String(tutorPolicyRevision);$('tutorPolicyRevisionBadge').textContent='REV. '+tutorPolicyRevision;
    $('tutorWelcomeKicker').innerHTML='<span class="w-6 h-px bg-sky-300"></span> '+esc(localizedField(pg,'welcome_kicker')||'JOIN OUR TEACHING TEAM');
    $('tutorWelcomeTitle').textContent=localizedField(pg,'welcome_title')||L('มาร่วมสร้างการเรียนรู้ที่ดีกับ','Build better learning with');
    $('tutorWelcomeHighlight').textContent=localizedField(pg,'welcome_highlight')||'AreWarin Biology';
    $('tutorWelcomeDescription').textContent=localizedField(pg,'welcome_description')||L('เรามองหาผู้สอนที่รักการถ่ายทอดความรู้ รับผิดชอบต่อผู้เรียน และพร้อมทำงานร่วมกับทีมอย่างเป็นมืออาชีพ','We welcome educators who love teaching and are ready to work professionally with our team.');
    $('tutorPolicyTitle').textContent=localizedField(pg,'policy_title')||L('นโยบายและกติกาสำหรับผู้สมัครติวเตอร์','Policies & guidelines for tutor applicants');
    $('tutorPolicySubtitle').textContent=localizedField(pg,'policy_subtitle')||'';
    $('tutorPolicyConsentTitle').textContent=localizedField(pg,'consent_title')||L('ฉันได้อ่านและยอมรับนโยบายสำหรับผู้สมัครติวเตอร์','I have read and accept the tutor applicant policies.');
    $('tutorPolicyConsentDesc').textContent=localizedField(pg,'consent_description')||'';
    $('btnAcceptTutorPolicy').innerHTML=esc(localizedField(pg,'start_button_label')||L('ยอมรับและเริ่มสมัคร','Accept & start application'))+' <i class="fas fa-arrow-right"></i>';
    renderTutorPolicySections(res.sections||[]);
  }
  async function loadTutorPolicy(){try{const api=window.AreWarinAPI;if(!api?.getPolicyPage)throw new Error('Policy API unavailable');const res=await api.getPolicyPage('tutor_application');if(!res?.page)throw new Error('Policy page not found');cachedTutorPolicy=res;applyTutorPolicyLanguage();}catch(e){console.warn('Tutor policy fallback',e);cachedTutorPolicy={page:null,sections:[{title:'มาตรฐานการร่วมทีม',title_en:'Professional standards',caption:'Tutor policy',caption_en:'Tutor policy',icon_class:'fas fa-shield-heart',theme:'blue',content:'กรุณาให้ข้อมูลตามความเป็นจริง\nเคารพผู้เรียนและรักษาความลับ\nตารางและค่าตอบแทนจะยืนยันร่วมกันก่อนเริ่มงาน',content_en:'Provide accurate information\nRespect learners and protect confidential information\nSchedules and compensation will be confirmed before teaching begins'}]};renderTutorPolicySections(cachedTutorPolicy.sections);}}

  function educationRow(data={}){
    eduSeq++;const el=document.createElement('div');el.className='repeat-row';el.dataset.row='education';
    el.innerHTML=`<div class="flex justify-between items-center mb-2"><div class="text-[10px] font-semibold text-slate-600">${L('รายการการศึกษา','Education entry')}</div><button type="button" class="remove-btn" title="${L('ลบ','Remove')}"><i class="fas fa-xmark"></i></button></div><div class="grid md:grid-cols-2 gap-2"><input class="field edu-institution" placeholder="${L('สถาบัน / มหาวิทยาลัย *','Institution / university *')}" value="${esc(data.institution||'')}"><input class="field edu-degree" placeholder="${L('ระดับ / ปริญญา','Degree / level')}" value="${esc(data.degree||'')}"><input class="field edu-major" placeholder="${L('คณะ / สาขา','Faculty / major')}" value="${esc(data.major||'')}"><input class="field edu-year" placeholder="${L('ปีที่จบ / กำลังศึกษา','Graduation year / currently studying')}" value="${esc(data.year||'')}"></div><input class="field edu-detail mt-2" placeholder="${L('รายละเอียดเพิ่มเติม (ถ้ามี)','Additional details (optional)')}" value="${esc(data.detail||'')}">`;
    el.querySelector('.remove-btn').onclick=()=>{el.remove();saveDraftSoon()};el.querySelectorAll('input').forEach(i=>i.addEventListener('input',saveDraftSoon));$('educationList').appendChild(el);return el;
  }
  function workRow(data={}){
    workSeq++;const el=document.createElement('div');el.className='repeat-row';el.dataset.row='work';
    el.innerHTML=`<div class="flex justify-between items-center mb-2"><div class="text-[10px] font-semibold text-slate-600">${L('รายการประสบการณ์','Experience entry')}</div><button type="button" class="remove-btn" title="${L('ลบ','Remove')}"><i class="fas fa-xmark"></i></button></div><div class="grid md:grid-cols-2 gap-2"><input class="field work-org" placeholder="${L('สถานที่ทำงาน / สถาบัน','Organization / institution')}" value="${esc(data.organization||'')}"><input class="field work-role" placeholder="${L('ตำแหน่ง / บทบาท','Position / role')}" value="${esc(data.role||'')}"><input class="field work-period" placeholder="${L('ช่วงเวลา เช่น 2024–ปัจจุบัน','Period, e.g. 2024–present')}" value="${esc(data.period||'')}"><input class="field work-subject" placeholder="${L('วิชา / งานที่เกี่ยวข้อง','Subject / relevant work')}" value="${esc(data.subject||'')}"></div><textarea class="field work-detail mt-2" placeholder="${L('หน้าที่หรือผลงานโดยย่อ','Brief responsibilities or achievements')}">${esc(data.detail||'')}</textarea>`;
    el.querySelector('.remove-btn').onclick=()=>{el.remove();saveDraftSoon()};el.querySelectorAll('input,textarea').forEach(i=>i.addEventListener('input',saveDraftSoon));$('workList').appendChild(el);return el;
  }
  function renderAvailability(saved=[]){
    const map=Object.fromEntries((saved||[]).map(x=>[x.day,x]));
    $('availabilityGrid').innerHTML=days.map(d=>{const s=map[d.key]||{};return `<div class="day-card ${s.enabled?'on':''}" data-day="${d.key}"><div class="day-head"><label class="flex items-center gap-2 text-[10.5px] font-semibold text-slate-700"><input class="day-toggle" type="checkbox" ${s.enabled?'checked':''}> ${esc(d[currentLang])}</label><span class="text-[8px] text-slate-400">Weekly</span></div><div class="day-times"><input class="field day-start !min-h-[38px]" type="time" value="${esc(s.start||'09:00')}"><input class="field day-end !min-h-[38px]" type="time" value="${esc(s.end||'18:00')}"></div></div>`}).join('');
    document.querySelectorAll('.day-card').forEach(card=>{const tog=card.querySelector('.day-toggle');tog.addEventListener('change',()=>{card.classList.toggle('on',tog.checked);saveDraftSoon()});card.querySelectorAll('input').forEach(i=>i.addEventListener('input',saveDraftSoon));});
  }

  async function loadBrandAndSubjects(){
    if(!sb){subjectRows=fallbackSubjects;return renderSubjects(subjectRows);}
    try{const [b,c]=await Promise.all([sb.from('site_branding').select('*').eq('id',1).maybeSingle(),sb.from('subject_categories').select('id,name_th,name_en,icon_class,active,sort_order').eq('active',true).order('sort_order')]);if(b.data){if(b.data.logo_url)$('brandLogo').src=b.data.logo_url;$('brandName').textContent=b.data.brand_name_en||'AreWarin Biology';}subjectRows=c.data?.length?c.data:fallbackSubjects;renderSubjects(subjectRows);}catch(e){subjectRows=fallbackSubjects;renderSubjects(subjectRows)}
  }
  function renderSubjects(rows){
    const selected=new Set(checked('subjects'));
    $('subjectChoices').innerHTML=rows.map(x=>{const key=x.id??x[0],label=currentLang==='en'?(x.name_en||x.name_th||x[2]||x[1]):(x.name_th||x.name_en||x[1]),icon=x.icon_class||x[3];return `<label class="choice"><input type="checkbox" name="subjects" value="${esc(key)}" ${selected.has(String(key))?'checked':''}><i class="${esc(icon||'fas fa-book-open')} text-sky-400"></i><span>${esc(label)}</span></label>`}).join('');
    document.querySelectorAll('input[name="subjects"]').forEach(i=>i.addEventListener('change',saveDraftSoon));
  }

  function collectEducation(){return [...document.querySelectorAll('[data-row="education"]')].map(r=>({institution:r.querySelector('.edu-institution').value.trim(),degree:r.querySelector('.edu-degree').value.trim(),major:r.querySelector('.edu-major').value.trim(),year:r.querySelector('.edu-year').value.trim(),detail:r.querySelector('.edu-detail').value.trim()})).filter(x=>Object.values(x).some(Boolean));}
  function collectWork(){return [...document.querySelectorAll('[data-row="work"]')].map(r=>({organization:r.querySelector('.work-org').value.trim(),role:r.querySelector('.work-role').value.trim(),period:r.querySelector('.work-period').value.trim(),subject:r.querySelector('.work-subject').value.trim(),detail:r.querySelector('.work-detail').value.trim()})).filter(x=>Object.values(x).some(Boolean));}
  function collectAvailability(){return [...document.querySelectorAll('.day-card')].filter(c=>c.querySelector('.day-toggle').checked).map(c=>({day:c.dataset.day,enabled:true,start:c.querySelector('.day-start').value,end:c.querySelector('.day-end').value}));}
  function checked(name){return [...document.querySelectorAll(`input[name="${name}"]:checked`)].map(x=>x.value)}
  function payload(){return {first_name:$('firstName').value.trim(),last_name:$('lastName').value.trim(),nickname:$('nickname').value.trim(),phone:cleanPhone($('phone').value),email:$('email').value.trim().toLowerCase(),line_id:$('lineId').value.trim(),nationality:$('nationality')?.value.trim()||'',country_residence:$('countryResidence')?.value.trim()||'',province:$('province').value.trim(),current_occupation:$('currentOccupation').value.trim(),intro:$('intro').value.trim(),education:collectEducation(),work_experience:collectWork(),achievements:$('achievements').value.trim(),subjects:checked('subjects'),levels:checked('levels'),teaching_modes:checked('modes'),teaching_experience_years:Number($('experienceYears').value||0),expected_rate:$('expectedRate').value.trim(),preferred_location:$('preferredLocation').value.trim(),availability:collectAvailability(),teaching_style:$('teachingStyle').value.trim(),why_join:$('whyJoin').value.trim(),additional_note:$('additionalNote').value.trim(),consent_pdpa:$('pdpaCheck').checked,certified_accuracy:$('accuracyCheck').checked,policy_version:tutorPolicyRevision,preferred_language:currentLang};}

  function validateStep(n){
    if(n===1){
      for(const id of ['firstName','lastName','nickname','phone','email']){const el=$(id);if(!el.value.trim()){el.focus();toast('warning',L('กรอกข้อมูลให้ครบ','Please complete required fields'),L('กรุณากรอกช่องที่มีเครื่องหมาย *','Please fill in all fields marked *'));return false}}
      const phoneLen=cleanPhone($('phone').value).length;if(phoneLen<8||phoneLen>15){$('phone').focus();toast('warning',L('ตรวจสอบเบอร์โทร','Check phone number'),L('กรุณากรอกเบอร์โทรให้ถูกต้อง 8–15 หลัก','Please enter a valid 8–15 digit phone number, including country code if applicable.'));return false}
      if(!$('email').checkValidity()){$('email').focus();toast('warning',L('ตรวจสอบอีเมล','Check email'),L('รูปแบบอีเมลไม่ถูกต้อง','Please enter a valid email address.'));return false}
    }
    if(n===2){const ed=collectEducation();if(!ed.length||!ed[0].institution){toast('warning',L('เพิ่มประวัติการศึกษา','Add education'),L('กรุณาระบุสถาบันการศึกษาอย่างน้อย 1 รายการ','Please provide at least one education entry.'));return false}}
    if(n===3){
      if(!checked('subjects').length){toast('warning',L('เลือกวิชาที่สอน','Select subjects'),L('กรุณาเลือกอย่างน้อย 1 วิชา','Please select at least one subject.'));return false}
      if(!checked('levels').length){toast('warning',L('เลือกระดับผู้เรียน','Select learner levels'),L('กรุณาเลือกอย่างน้อย 1 ระดับ','Please select at least one learner level.'));return false}
      if(!checked('modes').length){toast('warning',L('เลือกรูปแบบการสอน','Select teaching mode'),L('กรุณาเลือก Online หรือ Onsite อย่างน้อย 1 แบบ','Please select Online or Onsite.'));return false}
      if(!collectAvailability().length){toast('warning',L('เลือกวันที่สะดวก','Select availability'),L('กรุณาเลือกอย่างน้อย 1 วัน','Please select at least one available day.'));return false}
    }
    if(n===4&&!($('accuracyCheck').checked&&$('pdpaCheck').checked)){toast('warning',L('กรุณายืนยันข้อมูล','Please confirm'),L('ต้องยืนยันความถูกต้องและการใช้ข้อมูลก่อนส่งใบสมัคร','Please certify accuracy and consent to data use before submitting.'));return false}
    return true;
  }

  let draftTimer;function saveDraftSoon(){clearTimeout(draftTimer);draftTimer=setTimeout(saveDraft,350)}
  function saveDraft(){try{localStorage.setItem(DRAFT_KEY,JSON.stringify(payload()));$('draftStatus').innerHTML=`<i class="fas fa-check text-emerald-500 mr-1"></i> ${L('บันทึกร่างแล้ว','Draft saved')}`;setTimeout(()=>{$('draftStatus').innerHTML=`<i class="far fa-floppy-disk mr-1"></i> ${L('บันทึกร่างอัตโนมัติ','Autosave draft')}`},1300)}catch{}}
  function restoreDraft(){try{const d=JSON.parse(localStorage.getItem(DRAFT_KEY)||'null');if(!d)return false;const map={firstName:d.first_name,lastName:d.last_name,nickname:d.nickname,phone:d.phone,email:d.email,lineId:d.line_id,nationality:d.nationality,countryResidence:d.country_residence,province:d.province,currentOccupation:d.current_occupation,intro:d.intro,achievements:d.achievements,experienceYears:d.teaching_experience_years,expectedRate:d.expected_rate,preferredLocation:d.preferred_location,teachingStyle:d.teaching_style,whyJoin:d.why_join,additionalNote:d.additional_note};Object.entries(map).forEach(([id,v])=>{if($(id)&&v!=null)$(id).value=v});$('educationList').innerHTML='';(d.education?.length?d.education:[{}]).forEach(educationRow);$('workList').innerHTML='';(d.work_experience||[]).forEach(workRow);renderAvailability(d.availability||[]);setTimeout(()=>{(d.subjects||[]).forEach(v=>{const el=document.querySelector(`input[name="subjects"][value="${CSS.escape(v)}"]`);if(el)el.checked=true});(d.levels||[]).forEach(v=>{const el=document.querySelector(`input[name="levels"][value="${CSS.escape(v)}"]`);if(el)el.checked=true});(d.teaching_modes||[]).forEach(v=>{const el=document.querySelector(`input[name="modes"][value="${CSS.escape(v)}"]`);if(el)el.checked=true})},300);return true}catch{return false}}

  function validateFiles(){const rules=[['profilePhoto',5],['resumeFile',10],['portfolioFile',10],['transcriptFile',10]];for(const [id,max] of rules){const f=$(id).files[0];if(f&&f.size>max*1024*1024){toast('warning',L('ไฟล์ใหญ่เกินไป','File too large'),L(`${f.name} ต้องไม่เกิน ${max} MB`,`${f.name} must be no larger than ${max} MB`));return false}}return true}
  async function submitApplication(){
    if(!sb||!cfg.SUPABASE_URL||!cfg.SUPABASE_ANON_KEY)return toast('error',L('ยังไม่ได้เชื่อมระบบ','System not connected'),L('ไม่พบการตั้งค่า Supabase','Supabase configuration was not found.'));
    if(!validateFiles())return;
    const fd=new FormData();fd.append('payload',JSON.stringify(payload()));
    [['profile_photo','profilePhoto'],['resume','resumeFile'],['portfolio','portfolioFile'],['transcript','transcriptFile']].forEach(([key,id])=>{const f=$(id).files[0];if(f)fd.append(key,f,f.name)});
    $('btnSubmit').disabled=true;$('btnSubmit').innerHTML=`<i class="fas fa-circle-notch fa-spin"></i> ${L('กำลังส่ง...','Submitting...')}`;
    try{
      const res=await fetch(`${cfg.SUPABASE_URL}/functions/v1/submit-tutor-application`,{method:'POST',headers:{apikey:cfg.SUPABASE_ANON_KEY,Authorization:`Bearer ${cfg.SUPABASE_ANON_KEY}`},body:fd});
      let data={};try{data=await res.json()}catch{}
      if(!res.ok||!data.success)throw new Error(data.message||`HTTP ${res.status}`);
      localStorage.removeItem(DRAFT_KEY);const no=data.application_no;
      await Swal.fire({icon:'success',title:L('ส่งใบสมัครเรียบร้อย','Application submitted'),html:`<div class="text-[11px] text-slate-500">${L('เลขใบสมัครของคุณ','Your application number')}</div><div class="mt-2 px-4 py-3 rounded-xl bg-slate-900 text-white font-mono text-lg tracking-wide">${esc(no)}</div><div class="mt-3 text-[10px] text-slate-400 leading-relaxed">${L('กรุณาบันทึกเลขนี้ไว้ ใช้ร่วมกับเบอร์โทรเพื่อเช็คสถานะใบสมัคร','Please save this number. Use it with your phone number to check your application status.')}</div>`,confirmButtonText:L('กลับหน้าหลัก','Back to home'),confirmButtonColor:'#0f172a',customClass:{popup:'rounded-[1.5rem]'}});
      location.href='../';
    }catch(e){toast('error',L('ส่งใบสมัครไม่สำเร็จ','Could not submit application'),e.message||L('กรุณาลองใหม่อีกครั้ง','Please try again.'))}
    finally{$('btnSubmit').disabled=false;$('btnSubmit').innerHTML=`${L('ส่งใบสมัคร','Submit application')} <i class="fas fa-paper-plane"></i>`}
  }

  const statusInfo={
    th:{new:['รับใบสมัครแล้ว','bg-sky-50 text-sky-700'],reviewing:['กำลังตรวจสอบ','bg-amber-50 text-amber-700'],interview:['นัดสัมภาษณ์ / ทดลองสอน','bg-violet-50 text-violet-700'],accepted:['ผ่านการพิจารณา','bg-emerald-50 text-emerald-700'],rejected:['ไม่ผ่านการพิจารณา','bg-rose-50 text-rose-700'],withdrawn:['ยกเลิกใบสมัคร','bg-slate-100 text-slate-600']},
    en:{new:['Application received','bg-sky-50 text-sky-700'],reviewing:['Under review','bg-amber-50 text-amber-700'],interview:['Interview / demo lesson','bg-violet-50 text-violet-700'],accepted:['Accepted','bg-emerald-50 text-emerald-700'],rejected:['Not selected','bg-rose-50 text-rose-700'],withdrawn:['Withdrawn','bg-slate-100 text-slate-600']}
  };
  async function checkStatus(){
    if(!sb)return toast('error',L('ยังไม่ได้เชื่อมระบบ','System not connected'));
    const {value}=await Swal.fire({
      title:L('เช็คสถานะใบสมัคร','Check application status'),
      html:`<div class="text-left space-y-3"><label class="label">${L('เลขใบสมัคร','Application number')}<input id="statusNo" class="field mt-1" placeholder="AWT-2026-000001"></label><label class="label">${L('เบอร์โทร','Phone number')}<input id="statusPhone" type="tel" class="field mt-1" placeholder="+66... / 08xxxxxxxx"></label></div>`,
      showCancelButton:true,confirmButtonText:L('ตรวจสอบ','Check'),cancelButtonText:L('ยกเลิก','Cancel'),confirmButtonColor:'#0f172a',customClass:{popup:'rounded-[1.5rem]'},
      preConfirm:()=>{const no=document.getElementById('statusNo').value.trim(),phone=cleanPhone(document.getElementById('statusPhone').value);if(!no||phone.length<8||phone.length>15){Swal.showValidationMessage(L('กรอกเลขใบสมัครและเบอร์โทรให้ถูกต้อง','Enter a valid application number and phone.'));return false}return{no,phone}}
    });
    if(!value)return;
    Swal.fire({title:L('กำลังตรวจสอบ...','Checking...'),didOpen:()=>Swal.showLoading(),showConfirmButton:false,allowOutsideClick:false});
    const {data,error}=await sb.rpc('check_tutor_application_status',{p_application_no:value.no,p_phone:value.phone});
    if(error)return toast('error',L('ตรวจสอบไม่ได้','Could not check status'),error.message);
    if(!data?.found)return toast('warning',L('ไม่พบใบสมัคร','Application not found'),L('กรุณาตรวจสอบเลขใบสมัครและเบอร์โทรอีกครั้ง','Please check your application number and phone.'));
    const [label,cls]=(statusInfo[currentLang]?.[data.status])||[data.status,'bg-slate-100 text-slate-600'];
    const dateLocale=currentLang==='en'?'en-GB':'th-TH';
    Swal.fire({title:L('สถานะใบสมัคร','Application status'),html:`<div class="text-left"><div class="status-modal-row"><span>${L('เลขใบสมัคร','Application number')}</span><b class="font-mono">${esc(data.application_no)}</b></div><div class="status-modal-row"><span>${L('ผู้สมัคร','Applicant')}</span><b>${esc(data.applicant_name)}</b></div><div class="status-modal-row"><span>${L('วันที่ส่ง','Submitted')}</span><span>${new Date(data.created_at).toLocaleDateString(dateLocale)}</span></div><div class="status-modal-row"><span>${L('สถานะ','Status')}</span><span><span class="status-pill ${cls}">${esc(label)}</span></span></div>${data.public_status_note?`<div class="mt-3 p-3 rounded-xl bg-slate-50 border border-slate-100 text-[10px] text-slate-600 leading-relaxed">${esc(data.public_status_note)}</div>`:''}</div>`,confirmButtonText:L('ปิด','Close'),confirmButtonColor:'#0f172a',customClass:{popup:'rounded-[1.5rem]'}});
  }

  function rerenderDynamicForLanguage(){
    const edu=collectEducation(),work=collectWork(),avail=collectAvailability();
    $('educationList').innerHTML='';(edu.length?edu:[{}]).forEach(educationRow);
    $('workList').innerHTML='';work.forEach(workRow);
    renderAvailability(avail);
    renderSubjects(subjectRows.length?subjectRows:fallbackSubjects);
    applyTutorPolicyLanguage();
  }
  function setLanguage(lang){
    currentLang=lang==='en'?'en':'th';localStorage.setItem('arewarin_tutor_language',currentLang);translateStatic();rerenderDynamicForLanguage();
  }

  captureStaticLanguage();
  $('year').textContent=new Date().getFullYear();
  $('phone').addEventListener('input',()=>{formatPhoneInput();saveDraftSoon()});
  $('addEducation').onclick=()=>educationRow();$('addWork').onclick=()=>workRow();
  $('btnNext').onclick=()=>{if(validateStep(step))setStep(step+1)};$('btnBack').onclick=()=>setStep(step-1);
  $('applicationForm').onsubmit=e=>{e.preventDefault();if(validateStep(4))submitApplication()};
  $('btnCheckStatus').onclick=checkStatus;$('btnCheckStatusMobile').onclick=checkStatus;$('btnWelcomeCheckStatus').onclick=checkStatus;
  $('langTh').onclick=()=>setLanguage('th');$('langEn').onclick=()=>setLanguage('en');
  $('btnStartTutorApply').onclick=()=>{showOnboardView('policy')};$('btnPolicyBack').onclick=()=>showOnboardView('welcome');
  $('btnAcceptTutorPolicy').onclick=()=>{if(!$('tutorPolicyConsent').checked)return toast('warning',L('กรุณายอมรับนโยบาย','Please accept the policies'),L('อ่านและยอมรับกติกาก่อนเริ่มกรอกใบสมัคร','Please read and accept the policies before starting.'));showOnboardView('application');setStep(1)};
  document.querySelectorAll('#applicationForm input,#applicationForm textarea,#applicationForm select').forEach(el=>{if(!['file','checkbox'].includes(el.type))el.addEventListener('input',saveDraftSoon);if(el.type==='checkbox')el.addEventListener('change',saveDraftSoon)});
  translateStatic();
  educationRow();renderAvailability([]);
  Promise.all([loadBrandAndSubjects(),loadTutorPolicy()]).then(()=>{restoreDraft();rerenderDynamicForLanguage()});
  showOnboardView('welcome');
})();
