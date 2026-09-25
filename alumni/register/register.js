const db = window.SCHOOL_SUPABASE;
const $ = (s) => document.querySelector(s);
let selectedPhoto = null;
let objectPreviewUrl = '';

const currentBuddhistYear = new Date().getFullYear()+543;
function fillStructuredSelects(root=document){
  root.querySelectorAll('.alumni-batch-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- เลือกรุ่น --</option>'+Array.from({length:50},(_,i)=>`<option value="รุ่น ${i+1}">รุ่น ${i+1}</option>`).join('');if(v)el.value=/^\d+$/.test(v)?`รุ่น ${v}`:v;});
  root.querySelectorAll('.graduation-year-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option>'+Array.from({length:currentBuddhistYear-2499},(_,i)=>currentBuddhistYear-i).map(y=>`<option value="${y}">${y}</option>`).join('');if(v)el.value=v;});
  root.querySelectorAll('.graduation-level-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option>'+Array.from({length:6},(_,i)=>`<option value="ม.${i+1}">มัธยมศึกษาปีที่ ${i+1} (ม.${i+1})</option>`).join('');if(v)el.value=v;});
  root.querySelectorAll('.naktham-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option><option value="ตรี">นักธรรมตรี</option><option value="โท">นักธรรมโท</option><option value="เอก">นักธรรมเอก</option>';if(v)el.value=v;});
  root.querySelectorAll('.pali-select').forEach(el=>{const v=el.value;el.innerHTML='<option value="">-- ไม่ระบุ --</option><option value="ประโยค 1-2">ประโยค 1-2</option>'+Array.from({length:7},(_,i)=>i+3).map(n=>`<option value="ป.ธ.${n}">เปรียญธรรม ${n} ประโยค (ป.ธ.${n})</option>`).join('');if(v)el.value=v;});
}
function bindScholarshipToggles(root=document){
  root.querySelectorAll('.royal-scholarship-toggle').forEach(cb=>{const box=cb.closest('.rounded-2xl')?.querySelector('.royal-scholarship-fields');const sync=()=>{if(!box)return;box.classList.toggle('hidden',!cb.checked);box.querySelectorAll('input').forEach(i=>i.required=cb.checked)};cb.addEventListener('change',sync);sync();});
}


function showStatus(message, ok=false){
  const el=$('#form-status');
  el.className=`rounded-2xl p-4 text-sm ${ok?'bg-green-50 text-green-700 border border-green-100':'bg-red-50 text-red-600 border border-red-100'}`;
  el.textContent=message; el.classList.remove('hidden');
}
function clearStatus(){ $('#form-status').classList.add('hidden'); }
function setPreview(url){
  const img=$('#photo-preview'), ph=$('#photo-placeholder');
  if(url){ img.src=url;img.classList.remove('hidden');ph.classList.add('hidden');img.onerror=()=>{img.classList.add('hidden');ph.classList.remove('hidden')}; }
  else {img.src='';img.classList.add('hidden');ph.classList.remove('hidden');}
}
$('#photo-file').addEventListener('change',e=>{
  selectedPhoto=e.target.files?.[0]||null;
  if(objectPreviewUrl) URL.revokeObjectURL(objectPreviewUrl);
  if(selectedPhoto){
    if(selectedPhoto.size>10*1024*1024){selectedPhoto=null;e.target.value='';showStatus('รูปภาพต้องมีขนาดไม่เกิน 10 MB');return}
    objectPreviewUrl=URL.createObjectURL(selectedPhoto);setPreview(objectPreviewUrl);$('#file-note').textContent=`${selectedPhoto.name} • ${(selectedPhoto.size/1024/1024).toFixed(2)} MB`;
  } else {setPreview($('#photo-url').value.trim());$('#file-note').textContent='สูงสุด 10 MB'}
});
$('#photo-url').addEventListener('input',e=>{if(!selectedPhoto)setPreview(e.target.value.trim())});

async function uploadPhoto(submissionId, uploadToken){
  if(!selectedPhoto) return '';
  const ext=(selectedPhoto.name.split('.').pop()||'jpg').toLowerCase();
  const safeExt=['jpg','jpeg','png','webp','heic','heif'].includes(ext)?ext:'jpg';
  const path=`${submissionId}/${uploadToken}/${crypto.randomUUID()}.${safeExt}`;
  const {error}=await db.storage.from('alumni-submission-files').upload(path,selectedPhoto,{upsert:false,contentType:selectedPhoto.type||undefined});
  if(error) throw error;
  return path;
}

$('#submission-form').addEventListener('submit',async e=>{
  e.preventDefault(); clearStatus();
  if(!db) return showStatus('ยังไม่ได้ตั้งค่า Supabase สำหรับเว็บไซต์');
  const f=e.currentTarget;
  if(!$('#consent').checked) return showStatus('กรุณายอมรับเงื่อนไขก่อนส่งข้อมูล');
  if(f.elements.is_royal_scholarship.checked && (!f.elements.royal_scholarship_batch.value.trim() || !f.elements.royal_scholarship_phase.value.trim())) return showStatus('กรุณาระบุรุ่นและระยะของทุนเฉลิมราชกุมารี');
  if(!f.elements.phone.value.trim() && !f.elements.email.value.trim()) return showStatus('กรุณาระบุเบอร์โทรศัพท์หรือ Email อย่างน้อย 1 ช่อง');
  const btn=$('#submit-btn');btn.disabled=true;btn.classList.add('opacity-60','cursor-wait');btn.innerHTML='<span class="animate-pulse">กำลังส่งข้อมูล...</span>';
  try{
    const payload={
      fullName:f.elements.full_name.value.trim(),batch:f.elements.batch.value.trim(),graduationYear:f.elements.graduation_year.value.trim(),graduationLevel:f.elements.graduation_level.value.trim(),nakthamLevel:f.elements.naktham_level.value.trim(),paliLevel:f.elements.pali_level.value.trim(),isRoyalScholarship:f.elements.is_royal_scholarship.checked,royalScholarshipBatch:f.elements.royal_scholarship_batch.value.trim(),royalScholarshipPhase:f.elements.royal_scholarship_phase.value.trim(),
      currentPosition:f.elements.current_position.value.trim(),occupation:f.elements.occupation.value.trim(),organization:f.elements.organization.value.trim(),education:f.elements.education.value.trim(),bio:f.elements.bio.value.trim(),
      phone:f.elements.phone.value.trim(),email:f.elements.email.value.trim(),facebookUrl:f.elements.facebook_url.value.trim(),showContact:f.elements.show_contact.checked,
      photoUrl:selectedPhoto?'':f.elements.photo_url.value.trim(),consentAccepted:true
    };
    const {data:createData,error:createError}=await db.rpc('create_alumni_submission',{p_payload:payload});
    if(createError) throw createError;
    const created=Array.isArray(createData)?createData[0]:createData;
    if(!created?.id||!created?.upload_token) throw new Error('ไม่สามารถสร้างรายการส่งข้อมูลได้');
    const photoPath=await uploadPhoto(created.id,created.upload_token);
    const {data:finalData,error:finalError}=await db.rpc('finalize_alumni_submission',{p_id:created.id,p_upload_token:created.upload_token,p_photo_path:photoPath});
    if(finalError) throw finalError;
    const final=Array.isArray(finalData)?finalData[0]:finalData;
    $('#submission-number').textContent=`ALM-${String(final?.submission_no||created.submission_no).padStart(6,'0')}`;
    $('#form-card').classList.add('hidden');$('#success-card').classList.remove('hidden');window.scrollTo({top:0,behavior:'smooth'});lucide.createIcons();
  }catch(err){ console.error(err); showStatus('ส่งข้อมูลไม่สำเร็จ: '+(err.message||err)); }
  finally{btn.disabled=false;btn.classList.remove('opacity-60','cursor-wait');btn.innerHTML='<i data-lucide="send" class="w-5 h-5"></i> ส่งข้อมูลให้โรงเรียนตรวจสอบ';lucide.createIcons()}
});
$('#submit-another').addEventListener('click',()=>{location.reload()});
fillStructuredSelects();
bindScholarshipToggles();
lucide.createIcons();
