(() => {
'use strict';
const cfg = window.BIOARE_CONFIG;
const $ = id => document.getElementById(id);
const $a = (sel,root=document) => [...root.querySelectorAll(sel)];
const headers = {'apikey':cfg.publishableKey,'Content-Type':'application/json'};
const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
let step=0, session=null, questions=[], version='2026-11-15-v1', busy=false;
const criteria=[['clarity','ความชัดเจนของการอธิบาย'],['content','เนื้อหามีประโยชน์'],['delivery','รูปแบบการบรรยาย'],['interaction','การมีส่วนร่วม'],['usefulness','นำความรู้ไปใช้ได้'],['overall','ความพึงพอใจโดยรวม']];
const request=async(path,opts={})=>{
 const res=await fetch(cfg.url+'/rest/v1/'+path,{...opts,headers:{...headers,...opts.headers}});
 if(!res.ok)throw new Error('HTTP '+res.status); if(res.status===204 || opts.headers?.Prefer==='return=minimal') return null;return res.json();
};
const clean=x=>String(x||'').replace(/\s+/g,' ').trim();
const makeUUID=()=>{if(globalThis.crypto?.randomUUID)return crypto.randomUUID();const b=new Uint8Array(16);crypto.getRandomValues(b);b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const h=Array.from(b,x=>x.toString(16).padStart(2,'0')).join('');return `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}`;};
const err=msg=>{const e=$('form-alert');e.textContent=msg;e.hidden=false;};
const noerr=()=>{$('form-alert').hidden=true;};
function renderRatings(){
 $('ratings').innerHTML='';criteria.forEach(([key,label],i)=>{
  const box=document.createElement('div');box.className='question';
  const title=document.createElement('b');title.textContent=`${i+1}. ${label} *`;box.append(title);
  const scale=document.createElement('div');scale.className='scale';
  for(let n=1;n<=5;n++){const lab=document.createElement('label'),radio=document.createElement('input'),v=document.createElement('span');radio.type='radio';radio.name=key;radio.value=n;radio.setAttribute('aria-label',`${n} จาก 5`);v.textContent=n;lab.append(radio,v);scale.append(lab);}
  box.append(scale);$('ratings').append(box);
 });
}
function renderQuestions(){
 $('extra-questions').replaceChildren();if(!questions.length)return;
 const heading=document.createElement('h3');heading.textContent='คำถามเพิ่มเติมจากพี่อาร์';heading.style.marginTop='29px';$('extra-questions').append(heading);
 questions.forEach(q=>{
  const div=document.createElement('div');div.className='field';div.style.marginTop='14px';const lab=document.createElement('label');lab.className='label';lab.textContent=q.label+(q.required?' *':' (ไม่บังคับ)');lab.htmlFor='extra-'+q.id;div.append(lab);
  let input;if(q.kind==='long'){input=document.createElement('textarea');input.maxLength=1200;}
  else if(['choice','scale'].includes(q.kind)){
   input=document.createElement('select');const options=q.kind==='scale'?[1,2,3,4,5]:(Array.isArray(q.options)?q.options:[]);
   const none=document.createElement('option');none.value='';none.textContent='เลือกคำตอบ';input.append(none);
   options.slice(0,20).forEach(op=>{const item=document.createElement('option');item.value=String(op);item.textContent=String(op);input.append(item);});
  }else{input=document.createElement('input');input.type='text';input.maxLength=250;}
  input.id='extra-'+q.id;input.className='input';input.required=!!q.required;input.dataset.question=q.id;div.append(input);$('extra-questions').append(div);
 });
}
function showStep(n){step=n;[0,1,2].forEach(i=>{$('step-'+i).hidden=i!==n;});$('step-count').textContent=`${n+1} / 3`;$('step-eyebrow').textContent=['STEP 01 / ABOUT YOU','STEP 02 / RATINGS','STEP 03 / YOUR VOICE'][n];$('progress-fill').style.width=(n+1)/3*100+'%';$a('.step-line').forEach((e,i)=>e.classList.toggle('active',i===n));$('next-btn').textContent=n===2?'ส่งแบบประเมิน ✓':'ต่อไป →';$('back-btn').textContent=n===0?'← หน้าต้อนรับ':'← ย้อนกลับ';noerr();window.scrollTo({top:0,behavior:'smooth'});}
function checkStep(n){if(n===0){if(!clean($('school').value)||!$('grade').value){err('กรุณากรอกโรงเรียนและเลือกระดับชั้น');return false;}}
 if(n===1){for(const [key] of criteria){if(!document.querySelector(`input[name="${key}"]:checked`)){err('กรุณาให้คะแนนครบทั้ง 6 ข้อ');return false;}}}
 if(n===2){for(const q of questions){const el=$('extra-'+q.id);if(q.required&&!clean(el.value)){err('กรุณาตอบคำถามเพิ่มเติม: '+q.label);el.focus();return false;}}}
 return true;}
function payload(){const result={school:clean($('school').value),grade:$('grade').value,nickname:clean($('nickname').value)||null,full_name:clean($('full_name').value)||null,topic:clean($('topic').value)||null,pace:document.querySelector('input[name="pace"]:checked')?.value||null,difficulty:document.querySelector('input[name="difficulty"]:checked')?.value||null,message_to_are:$('message_to_are').value.trim()||null,custom_answers:{},session_id:session?.id||null,consented_at:new Date().toISOString(),privacy_version:version,submission_ref:makeUUID()};criteria.forEach(([k])=>result[k]=Number(document.querySelector(`input[name="${k}"]:checked`).value));questions.forEach(q=>{const v=$('extra-'+q.id).value.trim();if(v)result.custom_answers[q.id]=v;});return result;}
async function submit(){if(busy||!checkStep(2)||!checkStep(0)||!checkStep(1))return;const p=payload();busy=true;$('next-btn').disabled=true;$('next-btn').textContent='กำลังส่ง…';noerr();try{
 await request('speaker_feedback',{method:'POST',headers:{Prefer:'return=minimal'},body:JSON.stringify(p)});$('feedback-form').hidden=true;$('success').hidden=false;$('receipt').textContent=p.submission_ref;window.scrollTo({top:0,behavior:'smooth'});
 }catch(e){console.error('Feedback submit failed',e);err('ส่งข้อมูลไม่สำเร็จ กรุณาตรวจสอบการติดตั้ง Supabase และสถานะรอบบรรยาย แล้วลองอีกครั้ง');}
 finally{busy=false;$('next-btn').disabled=false;$('next-btn').textContent='ส่งแบบประเมิน ✓';}}
async function loadPublic(){try{
 const [settings,schools]=await Promise.all([request('bioare_settings?select=key,value&key=in.(privacy_notice,privacy_version,wall_enabled)'),request('bioare_schools?select=canonical_name&active=eq.true&order=canonical_name.asc&limit=1000')]);
 for(const item of settings||[]){if(item.key==='privacy_notice')$('privacy-text').textContent=String(item.value);if(item.key==='privacy_version'){version=String(item.value);$('privacy-ver').textContent=version;}if(item.key==='wall_enabled'&&item.value===true)loadWall().catch(()=>{});}
 $('schools-list').replaceChildren();(schools||[]).forEach(s=>{const o=document.createElement('option');o.value=s.canonical_name;$('schools-list').append(o);});
 const sessionId=new URLSearchParams(location.search).get('session');if(sessionId){if(!UUID_RE.test(sessionId)){throw new Error('Invalid session link');}const list=await request('bioare_sessions?select=id,title,school_name,grade,topic,starts_at,status&id=eq.'+encodeURIComponent(sessionId)+'&status=eq.open&limit=1');
   if(!list?.length){$('welcome-status').textContent='รอบบรรยายนี้ปิดรับคำตอบหรือไม่พบแล้ว';$('start-btn').disabled=true;$('privacy-consent').disabled=true;return;}
   session=list[0];$('session-banner').hidden=false;$('session-banner').textContent=session.title;$('session-info').hidden=false;$('session-info').textContent=session.title+' · '+session.school_name;
   $('school').value=session.school_name;$('school').readOnly=true;$('school-hint').textContent='กำหนดจากรอบบรรยาย (แก้ไขไม่ได้)';if(session.grade){$('grade').value=session.grade;$('grade').disabled=true;}if(session.topic){$('topic').value=session.topic;$('topic').readOnly=true;}
 }
 const qurl='bioare_form_questions?select=id,label,kind,options,required,session_id,sort_order&active=eq.true&order=sort_order.asc&limit=100';
 const q=await request(qurl);questions=(q||[]).filter(x=>!x.session_id||x.session_id===session?.id);renderQuestions();
 }catch(e){console.warn('BioAre public config unavailable',e);$('privacy-text').textContent='ไม่สามารถโหลดประกาศความเป็นส่วนตัวได้ กรุณาแจ้งผู้ดูแลติดตั้งฐานข้อมูล BioAre ให้ครบก่อนเริ่มทำแบบประเมิน';$('start-btn').disabled=true;$('privacy-consent').disabled=true;$('welcome-status').textContent='ระบบยังไม่พร้อมให้บริการ';}
}
async function loadWall(){const data=await request('bioare_wall_items?select=excerpt,created_at&is_public=eq.true&order=created_at.desc&limit=12');if(!data?.length)return;$('wall-section').hidden=false;const el=$('public-wall');el.replaceChildren();data.forEach(r=>{let card=document.createElement('div');card.className='wall-quote';card.textContent='“'+r.excerpt+'”';el.append(card);});}
$('privacy-consent').addEventListener('change',()=>{$('start-btn').disabled=!$('privacy-consent').checked;});$('start-btn').onclick=()=>{if(!$('privacy-consent').checked)return;$('welcome').hidden=true;$('survey').hidden=false;showStep(0);};$('next-btn').onclick=()=>{if(busy)return;noerr();if(!checkStep(step))return;if(step<2)showStep(step+1);else submit();};$('back-btn').onclick=()=>{if(step>0)showStep(step-1);else{$('survey').hidden=true;$('welcome').hidden=false;window.scrollTo({top:0});}};
$('again-btn').onclick=()=>{location.href='./';};$('copy-receipt').onclick=async()=>{try{await navigator.clipboard.writeText($('receipt').textContent);$('copy-receipt').textContent='คัดลอกแล้ว ✓';}catch(e){$('copy-receipt').textContent='เลือกคัดลอกรหัสด้านบน';}};
$('feedback-form').onsubmit=e=>e.preventDefault();
$('open-rights').onclick=()=>{$('rights-modal').hidden=false;};$('rights-close').onclick=()=>{$('rights-modal').hidden=true;};$('rights-modal').onclick=e=>{if(e.target===$('rights-modal'))$('rights-modal').hidden=true;};
$('rights-form').onsubmit=async e=>{e.preventDefault();const f=new FormData(e.target);const submission_ref=clean(f.get('submission_ref'));const box=$('rights-result');box.hidden=false;if(!UUID_RE.test(submission_ref)){box.textContent='กรุณากรอกรหัสอ้างอิงให้ถูกต้อง';return;}
 const data={submission_ref,request_type:f.get('request_type'),contact_email:clean(f.get('contact_email'))||null,details:clean(f.get('details'))||null};try{await request('bioare_privacy_requests',{method:'POST',headers:{Prefer:'return=minimal'},body:JSON.stringify(data)});box.textContent='รับคำขอแล้ว ผู้ดูแลจะตรวจสอบความถูกต้องก่อนดำเนินการ';e.target.reset();}catch(err){box.textContent='ไม่สามารถส่งคำขอได้ กรุณาลองใหม่หรือติดต่ออีเมลผู้ดูแล';}};
renderRatings();loadPublic();
})();
