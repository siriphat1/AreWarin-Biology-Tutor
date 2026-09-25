(() => {
  'use strict';

  const db = window.SCHOOL_SUPABASE;
  const BUCKET = window.SCHOOL_APP_CONFIG?.ADMISSION_STORAGE_BUCKET || 'admission-files';
  const $ = (id) => document.getElementById(id);

  let applications = [];
  let filteredApplications = [];
  let currentApplication = null;
  let currentSignedFiles = {};
  let currentSession = null;
  let schoolSettings = {};

  const statusMeta = {
    pending: { label: 'รอตรวจสอบ', cls: 'bg-amber-100 text-amber-700 border-amber-200' },
    under_review: { label: 'กำลังตรวจสอบ', cls: 'bg-sky-100 text-sky-700 border-sky-200' },
    approved: { label: 'อนุมัติแล้ว', cls: 'bg-emerald-100 text-emerald-700 border-emerald-200' },
    rejected: { label: 'ไม่อนุมัติ', cls: 'bg-red-100 text-red-700 border-red-200' },
    waitlist: { label: 'สำรอง / รอเรียก', cls: 'bg-violet-100 text-violet-700 border-violet-200' }
  };

  function esc(v) {
    return String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[c]));
  }
  function fmt(v, fallback='-') { return (v === null || v === undefined || v === '') ? fallback : String(v); }
  function thaiDate(v, withTime=true) {
    if (!v) return '-';
    const d = new Date(v);
    return withTime ? d.toLocaleString('th-TH', {dateStyle:'medium', timeStyle:'short'}) : d.toLocaleDateString('th-TH', {dateStyle:'medium'});
  }
  function fullName(a) {
    return [a.title ? `${a.title}${a.fname || ''}` : (a.fname || ''), a.chaya || '', a.lname || ''].filter(Boolean).join(' ');
  }
  function readableSize(bytes) {
    const n = Number(bytes || 0);
    if (!n) return '-';
    if (n < 1024) return `${n} B`;
    if (n < 1024*1024) return `${(n/1024).toFixed(1)} KB`;
    return `${(n/1024/1024).toFixed(1)} MB`;
  }
  function statusBadge(status) {
    const m = statusMeta[status] || statusMeta.pending;
    return `<span class="inline-flex items-center px-2.5 py-1 rounded-full border text-[10px] font-bold ${m.cls}">${m.label}</span>`;
  }

  async function loadBranding() {
    if (!db) return;
    try {
      const { data, error } = await db.from('site_settings').select('data').eq('id',1).maybeSingle();
      if (error) throw error;
      schoolSettings = data?.data || {};
      const info = schoolSettings.info || {};
      const logo = schoolSettings.branding?.logoUrl;
      ['loginSchoolName','headerSchoolName'].forEach(id => { if ($(id) && info.nameTh) $(id).textContent = info.nameTh; });
      if (info.nameTh) document.title = `Admission Manager | ${info.nameTh}`;
      [['loginLogo','loginLogoFallback'],['headerLogo','headerLogoFallback']].forEach(([imgId, fallbackId]) => {
        if (logo && $(imgId)) { $(imgId).src = logo; $(imgId).classList.remove('hidden'); $(fallbackId)?.classList.add('hidden'); }
      });
    } catch (e) { console.warn('Branding load failed', e); }
  }

  function showLogin(message='') {
    $('loginView').classList.remove('hidden');
    $('appView').classList.add('hidden');
    if (message) { $('loginError').textContent = message; $('loginError').classList.remove('hidden'); }
  }

  async function showDashboard(session) {
    currentSession = session;
    $('loginView').classList.add('hidden');
    $('appView').classList.remove('hidden');
    $('currentUserEmail').textContent = session?.user?.email || '-';
    await loadApplications();
  }

  async function loadApplications() {
    if (!db || !currentSession) return;
    const btn = $('refreshBtn');
    const old = btn?.textContent;
    if (btn) { btn.disabled = true; btn.textContent = 'กำลังโหลด...'; }
    try {
      const { data, error } = await db
        .from('admission_applications')
        .select('*')
        .eq('submission_state','submitted')
        .order('submitted_at', {ascending:false});
      if (error) throw error;
      applications = data || [];
      updateStats();
      applyFilters();
    } catch (e) {
      Swal.fire({title:'โหลดข้อมูลไม่สำเร็จ', text:e.message, icon:'error', confirmButtonColor:'#0f172a'});
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = old || 'รีเฟรช'; }
    }
  }

  function updateStats() {
    $('statAll').textContent = applications.length;
    $('statPending').textContent = applications.filter(a => a.status === 'pending').length;
    $('statReview').textContent = applications.filter(a => a.status === 'under_review').length;
    $('statApproved').textContent = applications.filter(a => a.status === 'approved').length;
    $('statRejected').textContent = applications.filter(a => a.status === 'rejected').length;
  }

  function applyFilters() {
    const q = ($('searchInput').value || '').trim().toLowerCase();
    const status = $('statusFilter').value;
    const level = $('levelFilter').value;
    filteredApplications = applications.filter(a => {
      const hay = [a.app_number, fullName(a), a.id_card, a.phone, a.level, a.old_school].join(' ').toLowerCase();
      return (!q || hay.includes(q)) && (status === 'all' || a.status === status) && (level === 'all' || a.level_id === level);
    });
    renderTable();
  }

  function renderTable() {
    const tbody = $('applicationTable');
    tbody.innerHTML = '';
    $('emptyState').classList.toggle('hidden', filteredApplications.length > 0);
    if (!filteredApplications.length) return;

    tbody.innerHTML = filteredApplications.map(a => `
      <tr class="hover:bg-orange-50/40 transition">
        <td class="p-4"><div class="font-mono font-bold text-orange-600">${esc(a.app_number)}</div><div class="text-[10px] text-slate-400 mt-1">${esc(a.id_card)}</div></td>
        <td class="p-4"><div class="font-bold text-slate-800">${esc(fullName(a))}</div><div class="text-[10px] text-slate-400 mt-1">${esc(a.phone || '-')}</div></td>
        <td class="p-4"><div class="font-semibold">${esc(a.level)}</div><div class="text-[10px] text-slate-400">${esc(a.study_plan || '-')}</div></td>
        <td class="p-4 text-xs text-slate-500">${esc(thaiDate(a.submitted_at))}</td>
        <td class="p-4">${statusBadge(a.status)}</td>
        <td class="p-4 text-center"><div class="flex justify-center gap-2"><button data-view="${a.id}" class="px-3 py-2 rounded-lg bg-slate-900 text-white text-xs font-bold hover:bg-slate-700">ดูใบสมัคร</button><button data-print="${a.id}" class="px-3 py-2 rounded-lg bg-orange-50 text-orange-700 text-xs font-bold hover:bg-orange-100">Print</button></div></td>
      </tr>`).join('');

    tbody.querySelectorAll('[data-view]').forEach(btn => btn.addEventListener('click', () => openApplication(btn.dataset.view)));
    tbody.querySelectorAll('[data-print]').forEach(btn => btn.addEventListener('click', async () => {
      const a = applications.find(x => x.id === btn.dataset.print); if (a) await printApplication(a);
    }));
  }

  async function getSignedFiles(a) {
    const entries = Object.entries(a.attachments || {});
    const out = {};
    await Promise.all(entries.map(async ([key, meta]) => {
      if (!meta?.path) return;
      const { data, error } = await db.storage.from(BUCKET).createSignedUrl(meta.path, 60 * 60);
      if (!error && data?.signedUrl) out[key] = {...meta, url:data.signedUrl};
    }));
    return out;
  }

  function field(label, value, wide=false) {
    return `<div class="${wide ? 'md:col-span-2' : ''} bg-white border border-slate-100 rounded-xl p-3"><div class="field-label">${esc(label)}</div><div class="field-value mt-1">${esc(fmt(value))}</div></div>`;
  }

  function section(title, content) {
    return `<section class="mb-5"><h4 class="text-sm font-bold text-slate-800 mb-3 flex items-center gap-2"><span class="w-1.5 h-5 bg-orange-500 rounded-full"></span>${esc(title)}</h4><div class="grid grid-cols-1 md:grid-cols-2 gap-2">${content}</div></section>`;
  }

  function documentsHtml(files) {
    const labels = {photo:'รูปถ่าย 1.5 นิ้ว', transcript:'ปพ.1 / ปพ.7', porpor2:'ปพ.2', house_registration:'ทะเบียนบ้าน', identity:'เอกสารยืนยันตัวตน / ใบสุทธิ', dhamma:'ใบนักธรรม'};
    const keys = Object.keys(files || {});
    if (!keys.length) return `<div class="text-sm text-slate-400 bg-white rounded-xl p-5 border">ไม่มีข้อมูลไฟล์แนบ</div>`;
    return `<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">${keys.map(key => {
      const f = files[key];
      const isImage = (f.type || '').startsWith('image/');
      return `<article class="bg-white border border-slate-200 rounded-2xl overflow-hidden">
        ${isImage ? `<a href="${esc(f.url)}" target="_blank" class="block h-40 bg-slate-100"><img src="${esc(f.url)}" class="w-full h-full object-contain" alt="${esc(labels[key] || f.label || key)}"></a>` : `<div class="h-32 bg-red-50 text-red-500 flex items-center justify-center text-4xl">PDF</div>`}
        <div class="p-3"><p class="font-bold text-sm">${esc(labels[key] || f.label || key)}</p><p class="text-[10px] text-slate-400 truncate mt-1">${esc(f.name || '')} · ${esc(readableSize(f.size))}</p><a href="${esc(f.url)}" target="_blank" class="mt-3 inline-flex w-full justify-center rounded-lg bg-slate-900 text-white px-3 py-2 text-xs font-bold">เปิดไฟล์</a></div>
      </article>`;
    }).join('')}</div>`;
  }

  async function openApplication(id) {
    const a = applications.find(x => x.id === id);
    if (!a) return;
    currentApplication = a;
    currentSignedFiles = {};
    $('detailModal').classList.remove('hidden');
    $('detailTitle').textContent = `${a.app_number} · ${fullName(a)}`;
    $('detailBody').innerHTML = `<div class="h-full min-h-[300px] flex items-center justify-center text-slate-400">กำลังโหลดข้อมูลและไฟล์แนบ...</div>`;

    currentSignedFiles = await getSignedFiles(a);
    const f = a.form_data || {};
    const siblings = Array.isArray(f.siblings) ? f.siblings.join(', ') : '';

    $('detailBody').innerHTML = `
      <div class="grid grid-cols-1 lg:grid-cols-[1fr_320px] gap-6">
        <div>
          <div class="flex flex-wrap items-center gap-2 mb-5">${statusBadge(a.status)}<span class="text-xs text-slate-400">ส่งใบสมัคร ${esc(thaiDate(a.submitted_at))}</span></div>
          ${section('ข้อมูลผู้สมัคร',
            field('เลขที่ใบสมัคร',a.app_number)+field('ปีการศึกษา',a.academic_year)+
            field('ชื่อ-นามสกุล',fullName(a))+field('เลขประจำตัวประชาชน',a.id_card)+
            field('วันเกิด', a.dob ? new Date(a.dob+'T00:00:00').toLocaleDateString('th-TH') : '-')+field('อายุ',a.age ? `${a.age} ปี` : '-')+
            field('โทรศัพท์',a.phone)+field('อีเมล',a.email)+field('ที่อยู่ตามทะเบียนบ้าน',a.address,true)
          )}
          ${section('ข้อมูลการสมัครและการศึกษา',
            field('ระดับชั้น',a.level)+field('แผนการเรียน',a.study_plan)+
            field('โรงเรียนเดิม',a.old_school)+field('จังหวัดโรงเรียนเดิม',a.old_province)+
            field('GPAX',a.gpa)+field('ศิษย์เก่าโรงเรียนวัดหนองแวง',a.is_nongwang_alumni ? 'ใช่' : 'ไม่ใช่')
          )}
          ${section('สถานภาพการบรรพชา',
            field('สถานภาพ',a.ordination_status)+field('วัดที่พำนัก',a.temple_residence)+field('ความประสงค์ในการบรรพชา',a.ordination_intention,true)
          )}
          ${section('ข้อมูลครอบครัว',
            field('บิดา',a.father_name)+field('สถานภาพบิดา',a.father_status)+field('เลขบัตรบิดา',a.father_id_card)+field('อาชีพบิดา',a.father_occupation)+
            field('มารดา',a.mother_name)+field('สถานภาพมารดา',a.mother_status)+field('เลขบัตรมารดา',a.mother_id_card)+field('อาชีพมารดา',a.mother_occupation)+
            field('สถานภาพบิดา-มารดา',a.parents_status)+field('จำนวนพี่น้อง',a.sibling_count)+field('รายชื่อพี่น้อง',siblings,true)
          )}
          ${section('ผู้ปกครอง / บุคคลติดต่อ', field('ชื่อ',a.guardian_name)+field('ความสัมพันธ์',a.guardian_relation)+field('โทรศัพท์',a.guardian_phone))}
          <section class="mb-5"><h4 class="text-sm font-bold text-slate-800 mb-3 flex items-center gap-2"><span class="w-1.5 h-5 bg-orange-500 rounded-full"></span>ภาพและเอกสารแนบ</h4>${documentsHtml(currentSignedFiles)}</section>
        </div>

        <aside class="lg:sticky lg:top-0 h-fit space-y-4 no-print">
          <div class="bg-white border border-slate-200 rounded-2xl p-4">
            <p class="text-xs font-bold text-slate-500 mb-3">จัดการสถานะใบสมัคร</p>
            <div class="grid grid-cols-2 gap-2">
              <button data-status-action="under_review" class="rounded-xl bg-sky-50 text-sky-700 px-3 py-3 text-xs font-bold hover:bg-sky-100">กำลังตรวจสอบ</button>
              <button data-status-action="waitlist" class="rounded-xl bg-violet-50 text-violet-700 px-3 py-3 text-xs font-bold hover:bg-violet-100">สำรอง / รอเรียก</button>
              <button data-status-action="approved" class="rounded-xl bg-emerald-600 text-white px-3 py-3 text-xs font-bold hover:bg-emerald-700">✓ อนุมัติ</button>
              <button data-status-action="rejected" class="rounded-xl bg-red-600 text-white px-3 py-3 text-xs font-bold hover:bg-red-700">✕ ไม่อนุมัติ</button>
            </div>
          </div>
          <div class="bg-white border border-slate-200 rounded-2xl p-4">
            <label class="text-xs font-bold text-slate-500">ข้อความแจ้งผู้สมัคร</label>
            <textarea id="publicMessageInput" rows="4" class="mt-2 w-full rounded-xl border border-slate-200 p-3 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="ข้อความนี้จะแสดงเมื่อผู้สมัครตรวจสอบสถานะ">${esc(a.public_message || '')}</textarea>
            <label class="text-xs font-bold text-slate-500 block mt-4">บันทึกภายในเจ้าหน้าที่</label>
            <textarea id="adminNoteInput" rows="5" class="mt-2 w-full rounded-xl border border-slate-200 p-3 text-sm focus:outline-none focus:ring-2 focus:ring-orange-400" placeholder="ผู้สมัครจะไม่เห็นข้อความนี้">${esc(a.admin_note || '')}</textarea>
            <button id="saveNotesBtn" class="mt-3 w-full rounded-xl bg-slate-900 text-white px-3 py-3 text-xs font-bold hover:bg-slate-800">บันทึกข้อความ</button>
          </div>
          <div class="bg-white border border-slate-200 rounded-2xl p-4 text-[11px] text-slate-500 space-y-1">
            <p><strong>ตรวจล่าสุด:</strong> ${esc(thaiDate(a.reviewed_at))}</p>
            <p><strong>ตัดสินผล:</strong> ${esc(thaiDate(a.decision_at))}</p>
          </div>
        </aside>
      </div>`;

    $('detailBody').querySelectorAll('[data-status-action]').forEach(btn => btn.addEventListener('click', () => changeStatus(btn.dataset.statusAction)));
    $('saveNotesBtn').addEventListener('click', saveNotes);
  }

  async function saveNotes() {
    if (!currentApplication) return;
    const updates = {
      public_message: $('publicMessageInput')?.value?.trim() || null,
      admin_note: $('adminNoteInput')?.value?.trim() || null,
      reviewed_by: currentSession?.user?.id || null,
      reviewed_at: new Date().toISOString()
    };
    const {error} = await db.from('admission_applications').update(updates).eq('id',currentApplication.id);
    if (error) return Swal.fire({title:'บันทึกไม่สำเร็จ',text:error.message,icon:'error'});
    Object.assign(currentApplication, updates);
    const listItem = applications.find(x => x.id === currentApplication.id); if (listItem) Object.assign(listItem, updates);
    Swal.fire({title:'บันทึกแล้ว',icon:'success',timer:1000,showConfirmButton:false});
  }

  async function changeStatus(status) {
    if (!currentApplication) return;
    const m = statusMeta[status];
    const decision = ['approved','rejected','waitlist'].includes(status);
    const confirm = await Swal.fire({
      title: m?.label || 'เปลี่ยนสถานะ',
      text: status === 'approved' ? 'ยืนยันอนุมัติใบสมัครนี้?' : status === 'rejected' ? 'ยืนยันไม่อนุมัติใบสมัครนี้?' : 'ยืนยันเปลี่ยนสถานะใบสมัคร?',
      icon: status === 'approved' ? 'question' : status === 'rejected' ? 'warning' : 'info',
      showCancelButton:true, confirmButtonText:'ยืนยัน', cancelButtonText:'ยกเลิก', confirmButtonColor: status === 'rejected' ? '#dc2626' : '#0f172a'
    });
    if (!confirm.isConfirmed) return;

    const now = new Date().toISOString();
    const updates = {
      status,
      public_message: $('publicMessageInput')?.value?.trim() || null,
      admin_note: $('adminNoteInput')?.value?.trim() || null,
      reviewed_by: currentSession?.user?.id || null,
      reviewed_at: now,
      decision_at: decision ? now : null
    };
    const {error} = await db.from('admission_applications').update(updates).eq('id',currentApplication.id);
    if (error) return Swal.fire({title:'อัปเดตไม่สำเร็จ',text:error.message,icon:'error'});
    Object.assign(currentApplication, updates);
    const listItem = applications.find(x => x.id === currentApplication.id); if (listItem) Object.assign(listItem, updates);
    updateStats(); applyFilters();
    await openApplication(currentApplication.id);
    Swal.fire({title:`สถานะ: ${m?.label || status}`,icon:'success',timer:1100,showConfirmButton:false});
  }

  async function printApplication(a) {
    let signed = currentApplication?.id === a.id ? currentSignedFiles : await getSignedFiles(a);
    const photo = signed.photo?.url || '';
    const f = a.form_data || {};
    const logo = schoolSettings.branding?.logoUrl || '';
    const info = schoolSettings.info || {};
    const docs = Object.values(signed).map(x => x.label || x.name).filter(Boolean).join(', ');
    const siblingText = Array.isArray(f.siblings) ? f.siblings.join(', ') : '-';
    const w = window.open('', '_blank', 'width=950,height=900');
    if (!w) return Swal.fire({title:'ไม่สามารถเปิดหน้าพิมพ์ได้',text:'กรุณาอนุญาต Pop-up สำหรับเว็บไซต์นี้',icon:'warning'});
    w.document.write(`<!doctype html><html lang="th"><head><meta charset="utf-8"><title>${esc(a.app_number)}</title><link href="https://fonts.googleapis.com/css2?family=Sarabun:wght@400;600;700&display=swap" rel="stylesheet"><style>
      body{font-family:Sarabun,sans-serif;color:#111827;margin:0;padding:28px;background:white}.page{max-width:820px;margin:auto}.head{display:flex;align-items:center;gap:18px;border-bottom:3px solid #f97316;padding-bottom:16px}.logo{width:74px;height:74px;object-fit:contain}.head h1{font-size:21px;margin:0}.meta{color:#64748b;font-size:12px}.top{display:grid;grid-template-columns:1fr 120px;gap:20px;margin-top:18px}.photo{width:110px;height:140px;object-fit:cover;border:1px solid #cbd5e1;border-radius:8px}.sec{margin-top:18px}.sec h2{font-size:14px;background:#fff7ed;color:#c2410c;padding:7px 10px;border-radius:6px;margin:0 0 8px}.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px 18px}.row{font-size:12px;border-bottom:1px solid #e5e7eb;padding:5px 0}.lbl{color:#64748b}.wide{grid-column:1/-1}.status{display:inline-block;padding:5px 10px;border-radius:999px;background:#f1f5f9;font-weight:700}@media print{button{display:none}body{padding:0}.page{max-width:none}}</style></head><body><div class="page">
      <div class="head">${logo?`<img class="logo" src="${esc(logo)}">`:''}<div><h1>${esc(info.nameTh || 'โรงเรียนวัดหนองแวงวิทยา')}</h1><div class="meta">ใบสมัครเรียน ปีการศึกษา ${esc(a.academic_year)} · ${esc(a.app_number)}</div></div></div>
      <div class="top"><div><div class="row"><span class="lbl">ชื่อผู้สมัคร:</span> <strong>${esc(fullName(a))}</strong></div><div class="row"><span class="lbl">ระดับชั้น:</span> ${esc(a.level)} ${a.study_plan?`(${esc(a.study_plan)})`:''}</div><div class="row"><span class="lbl">สถานะ:</span> <span class="status">${esc(statusMeta[a.status]?.label || a.status)}</span></div><div class="row"><span class="lbl">วันที่สมัคร:</span> ${esc(thaiDate(a.submitted_at))}</div></div>${photo?`<img class="photo" src="${esc(photo)}">`:''}</div>
      <div class="sec"><h2>ข้อมูลส่วนตัว</h2><div class="grid"><div class="row"><span class="lbl">เลขบัตรประชาชน:</span> ${esc(a.id_card)}</div><div class="row"><span class="lbl">วันเกิด/อายุ:</span> ${esc(fmt(a.dob))} / ${esc(fmt(a.age))} ปี</div><div class="row"><span class="lbl">โทรศัพท์:</span> ${esc(fmt(a.phone))}</div><div class="row"><span class="lbl">อีเมล:</span> ${esc(fmt(a.email))}</div><div class="row wide"><span class="lbl">ที่อยู่:</span> ${esc(fmt(a.address))}</div></div></div>
      <div class="sec"><h2>ข้อมูลการศึกษาและการบรรพชา</h2><div class="grid"><div class="row"><span class="lbl">โรงเรียนเดิม:</span> ${esc(fmt(a.old_school))}</div><div class="row"><span class="lbl">จังหวัด:</span> ${esc(fmt(a.old_province))}</div><div class="row"><span class="lbl">GPAX:</span> ${esc(fmt(a.gpa))}</div><div class="row"><span class="lbl">สถานภาพ:</span> ${esc(fmt(a.ordination_status))}</div><div class="row wide"><span class="lbl">วัดที่พำนัก/ความประสงค์:</span> ${esc(fmt(a.temple_residence))} ${esc(fmt(a.ordination_intention,''))}</div></div></div>
      <div class="sec"><h2>ข้อมูลครอบครัวและผู้ปกครอง</h2><div class="grid"><div class="row"><span class="lbl">บิดา:</span> ${esc(fmt(a.father_name))} (${esc(fmt(a.father_status))})</div><div class="row"><span class="lbl">อาชีพบิดา:</span> ${esc(fmt(a.father_occupation))}</div><div class="row"><span class="lbl">มารดา:</span> ${esc(fmt(a.mother_name))} (${esc(fmt(a.mother_status))})</div><div class="row"><span class="lbl">อาชีพมารดา:</span> ${esc(fmt(a.mother_occupation))}</div><div class="row wide"><span class="lbl">พี่น้อง:</span> ${esc(siblingText)}</div><div class="row"><span class="lbl">ผู้ปกครอง:</span> ${esc(fmt(a.guardian_name))}</div><div class="row"><span class="lbl">โทร:</span> ${esc(fmt(a.guardian_phone))}</div></div></div>
      <div class="sec"><h2>เอกสารแนบ</h2><div class="row">${esc(docs || 'ไม่มีข้อมูล')}</div></div>
      <div class="sec"><h2>บันทึกเจ้าหน้าที่</h2><div class="row"><span class="lbl">ข้อความถึงผู้สมัคร:</span> ${esc(fmt(a.public_message))}</div><div class="row"><span class="lbl">บันทึกภายใน:</span> ${esc(fmt(a.admin_note))}</div></div>
      <div style="margin-top:32px;display:grid;grid-template-columns:1fr 1fr;gap:80px;text-align:center;font-size:12px"><div>ลงชื่อ ___________________________<br>ผู้ตรวจเอกสาร</div><div>ลงชื่อ ___________________________<br>ผู้อนุมัติ</div></div>
      <div style="margin-top:20px;text-align:center"><button onclick="window.print()" style="padding:10px 24px;border:0;border-radius:8px;background:#111827;color:white;font-weight:700">พิมพ์ใบสมัคร</button></div>
    </div><script>window.onload=()=>setTimeout(()=>window.print(),500)<\/script></body></html>`);
    w.document.close();
  }

  function exportCSV() {
    const cols = ['app_number','status','academic_year','title','fname','chaya','lname','id_card','dob','age','phone','email','address','level','study_plan','ordination_status','temple_residence','ordination_intention','old_school','old_province','gpa','father_name','father_status','mother_name','mother_status','parents_status','sibling_count','guardian_name','guardian_relation','guardian_phone','submitted_at','public_message','admin_note'];
    const quote = v => `"${String(v ?? '').replace(/"/g,'""')}"`;
    const csv = '\uFEFF' + [cols.join(','), ...filteredApplications.map(a => cols.map(c => quote(a[c])).join(','))].join('\r\n');
    const blob = new Blob([csv], {type:'text/csv;charset=utf-8'});
    const url = URL.createObjectURL(blob); const link = document.createElement('a'); link.href=url; link.download=`admissions-${new Date().toISOString().slice(0,10)}.csv`; document.body.appendChild(link); link.click(); link.remove(); URL.revokeObjectURL(url);
  }

  async function init() {
    await loadBranding();
    if (!db) return showLogin('ไม่พบ Supabase configuration');
    const {data:{session}} = await db.auth.getSession();
    if (session) await showDashboard(session); else showLogin();

    db.auth.onAuthStateChange((_event, sessionNow) => {
      if (!sessionNow) showLogin();
    });
  }

  $('loginForm').addEventListener('submit', async (e) => {
    e.preventDefault(); $('loginError').classList.add('hidden');
    const {data,error} = await db.auth.signInWithPassword({email:$('loginEmail').value.trim(), password:$('loginPassword').value});
    if (error) return showLogin(error.message === 'Invalid login credentials' ? 'อีเมลหรือรหัสผ่านไม่ถูกต้อง' : error.message);
    await showDashboard(data.session);
  });
  $('logoutBtn').addEventListener('click', async () => { await db.auth.signOut(); currentSession=null; applications=[]; showLogin(); });
  $('refreshBtn').addEventListener('click', loadApplications);
  $('searchInput').addEventListener('input', applyFilters);
  $('statusFilter').addEventListener('change', applyFilters);
  $('levelFilter').addEventListener('change', applyFilters);
  $('exportBtn').addEventListener('click', exportCSV);
  $('closeDetailBtn').addEventListener('click', () => $('detailModal').classList.add('hidden'));
  $('detailBackdrop').addEventListener('click', () => $('detailModal').classList.add('hidden'));
  $('printBtn').addEventListener('click', () => currentApplication && printApplication(currentApplication));
  document.addEventListener('keydown', e => { if (e.key === 'Escape') $('detailModal').classList.add('hidden'); });

  init();
})();
