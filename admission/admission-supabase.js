/* ============================================================
   Admission subweb integration
   - Reads school branding/contact from the main website's site_settings
   - Stores applications in Supabase via secure RPC
   - Stores uploaded documents in private admission-files bucket
   - Public status check exposes only limited non-sensitive fields
   ============================================================ */
(() => {
  'use strict';

  const db = window.SCHOOL_SUPABASE;
  const cfg = window.SCHOOL_APP_CONFIG || {};
  const BUCKET = cfg.ADMISSION_STORAGE_BUCKET || 'admission-files';

  const $ = (id) => document.getElementById(id);
  const val = (id) => ($(id)?.value || '').trim();
  const checked = (selector) => document.querySelector(selector)?.value || '';
  const bool = (id) => Boolean($(id)?.checked);

  const STATUS_META = {
    pending: { label: 'รอตรวจสอบ', color: '#f59e0b' },
    under_review: { label: 'กำลังตรวจสอบ', color: '#0ea5e9' },
    approved: { label: 'อนุมัติแล้ว', color: '#10b981' },
    rejected: { label: 'ไม่ผ่านการอนุมัติ', color: '#ef4444' },
    waitlist: { label: 'สำรอง / รอเรียก', color: '#8b5cf6' }
  };

  function escapeText(v) {
    return String(v ?? '').replace(/[&<>"']/g, (ch) => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[ch]));
  }

  async function loadSchoolBranding() {
    if (!db) return;
    try {
      const { data, error } = await db.from('site_settings').select('data').eq('id', 1).maybeSingle();
      if (error) throw error;
      const site = data?.data || {};
      const info = site.info || {};
      const branding = site.branding || {};
      const social = site.social || {};

      if (info.nameTh && $('admissionSchoolName')) $('admissionSchoolName').textContent = info.nameTh;
      if (branding.logoUrl && $('admissionSchoolLogo')) $('admissionSchoolLogo').src = branding.logoUrl;
      if (site.welcomeImage && $('admissionHeroImage')) $('admissionHeroImage').src = site.welcomeImage;
      if (info.address && $('admissionSchoolAddress')) $('admissionSchoolAddress').textContent = info.address;
      if (info.phone && $('admissionSchoolPhone')) $('admissionSchoolPhone').textContent = `โทร: ${info.phone}`;
      if (social.facebook && $('admissionFacebookLink')) $('admissionFacebookLink').href = social.facebook;
      if (info.nameTh) document.title = `ระบบรับสมัครนักเรียน ${info.nameTh}`;
    } catch (err) {
      console.warn('Could not load school data from the main website:', err);
    }
  }

  function collectFullApplicationPayload() {
    const siblings = [];
    document.querySelectorAll('[id^="siblingName_"]').forEach(el => {
      const value = (el.value || '').trim();
      if (value) siblings.push(value);
    });

    const title = val('inpTitle') || val('stuTitle') || admissionData?.title || '';
    const fname = val('inpFname') || admissionData?.fname || '';
    const lname = val('inpLname') || admissionData?.lname || '';
    const ordinationChoice = checked('input[name="ordinationStatus"]');
    const studyPlanChoice = checked('input[name="studyPlan"]');
    const templeChoice = checked('input[name="templeResidence"]');
    const ordinationIntention = checked('input[name="ordinationIntention"]');
    const templeResidence = templeChoice === 'อื่นๆ' ? val('templeOtherInput') : (templeChoice || admissionData?.templeResidence || '');

    const payload = {
      academicYear: 2569,
      pdpaAccepted: bool('pdpaCheck'),
      levelId: admissionData?.levelId || checked('input[name="admissionLevel"]'),
      level: admissionData?.level || '',
      plan: admissionData?.plan || studyPlanChoice || '-',
      title,
      fname,
      lname,
      chaya: val('stuChaya') || admissionData?.chaya || '',
      idCard: val('stuIdCard') || admissionData?.idCard || '',
      dob: val('stuDob') || admissionData?.dob || '',
      age: val('stuAge') || admissionData?.age || '',
      phone: val('stuPhone') || admissionData?.phone || '',
      email: val('stuEmail') || admissionData?.email || '',
      address: val('stuAddress') || admissionData?.address || '',
      isNongwangAlumni: bool('isNongwangAlumni'),
      oldSchool: val('oldSchool') || admissionData?.oldSchool || '',
      oldProvince: val('oldProvince') || admissionData?.oldProvince || '',
      gpa: val('stuGpa') || admissionData?.gpa || '',
      ordinationStatus: ordinationChoice === 'ordained' ? 'บวชแล้ว' : (ordinationChoice === 'not_ordained' ? 'ยังไม่ได้บวช' : ''),
      isOrdained: ordinationChoice === 'ordained' || Boolean(admissionData?.isOrdained),
      templeResidence,
      ordinationIntention: ordinationIntention || admissionData?.ordinationIntention || '',
      fatherName: val('fatherName') || admissionData?.fatherName || '',
      fatherStatus: val('fatherStatus') || admissionData?.fatherStatus || '',
      fatherIdCard: val('fatherIdCard') || admissionData?.fatherIdCard || '',
      fatherOcc: val('fatherOcc') || admissionData?.fatherOcc || '',
      motherName: val('motherName') || admissionData?.motherName || '',
      motherStatus: val('motherStatus') || admissionData?.motherStatus || '',
      motherIdCard: val('motherIdCard') || admissionData?.motherIdCard || '',
      motherOcc: val('motherOcc') || admissionData?.motherOcc || '',
      parentsStatus: val('parentsStatus') || admissionData?.parentsStatus || '',
      siblingCount: Number(val('siblingCount') || admissionData?.siblingCount || 0),
      siblings: siblings.length ? siblings : (admissionData?.siblings || []),
      parentTitle: val('parentTitle'),
      parentFname: val('parentFname'),
      parentLname: val('parentLname'),
      parentFullName: `${val('parentTitle')}${val('parentFname')} ${val('parentLname')}`.trim() || admissionData?.parentFullName || '',
      parentRelation: val('parentRelation') || admissionData?.parentRelation || '',
      parentPhone: val('parentPhone') || admissionData?.parentPhone || '',
      hasDhamma: Boolean($('fileDhamma')?.files?.length),
      clientSubmittedAt: new Date().toISOString(),
      source: 'github-pages-admission-subweb'
    };

    // Keep any values already assembled by the original form so future fields are not lost.
    return Object.assign({}, admissionData || {}, payload);
  }

  function requiredFiles() {
    return [
      { key: 'photo', label: 'รูปถ่าย 1.5 นิ้ว', el: $('inputPhotoOnly'), required: true },
      { key: 'transcript', label: 'ปพ.1 / ปพ.7', el: $('fileTranscript'), required: true },
      { key: 'porpor2', label: 'ปพ.2', el: $('filePorPor2'), required: true },
      { key: 'house_registration', label: 'ทะเบียนบ้าน', el: $('fileHouseReg'), required: true },
      { key: 'identity', label: 'เอกสารยืนยันตัวตน / ใบสุทธิ', el: $('fileIdCard'), required: true },
      { key: 'dhamma', label: 'ใบนักธรรม', el: $('fileDhamma'), required: false }
    ];
  }

  function safeFileName(name) {
    const dot = name.lastIndexOf('.');
    const ext = dot >= 0 ? name.slice(dot).toLowerCase().replace(/[^.a-z0-9]/g, '') : '';
    const base = (dot >= 0 ? name.slice(0, dot) : name)
      .normalize('NFKD')
      .replace(/[^a-zA-Z0-9ก-๙_-]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 70) || 'file';
    return `${base}${ext}`;
  }

  async function uploadAdmissionFiles(applicationId, uploadToken) {
    const attachments = {};
    const files = requiredFiles();

    for (const item of files) {
      const file = item.el?.files?.[0];
      if (!file) {
        if (item.required) throw new Error(`ไม่พบไฟล์ ${item.label}`);
        continue;
      }
      if (file.size > 10 * 1024 * 1024) throw new Error(`${item.label} มีขนาดเกิน 10 MB`);

      const loading = $('loading-text');
      if (loading) loading.textContent = `กำลังอัปโหลด ${item.label}...`;

      const objectPath = `${applicationId}/${uploadToken}/${item.key}-${Date.now()}-${safeFileName(file.name)}`;
      const { error } = await db.storage.from(BUCKET).upload(objectPath, file, {
        cacheControl: '3600',
        upsert: false,
        contentType: file.type || undefined
      });
      if (error) throw new Error(`อัปโหลด ${item.label} ไม่สำเร็จ: ${error.message}`);

      attachments[item.key] = {
        path: objectPath,
        name: file.name,
        type: file.type || '',
        size: file.size,
        label: item.label
      };
    }
    return attachments;
  }

  function showSuccess(appNumber, submittedAt, payload) {
    document.getElementById('admissionForm').style.display = 'none';
    $('floatingAvatar')?.classList.add('hidden');
    $('successView')?.classList.remove('hidden');
    $('appNumber').textContent = appNumber || '-';

    let fullName = `${payload.title}${payload.fname} ${payload.lname}`;
    if (payload.isOrdained && payload.chaya) fullName = `${payload.title}${payload.fname} ${payload.chaya} ${payload.lname}`;
    $('finalName').textContent = fullName;

    let levelText = payload.level || '-';
    if (payload.plan && payload.plan !== '-') levelText += ` (${payload.plan})`;
    $('finalLevel').textContent = levelText;

    const dt = submittedAt ? new Date(submittedAt) : new Date();
    $('finalDate').textContent = `${dt.toLocaleDateString('th-TH')} ${dt.toLocaleTimeString('th-TH', {hour:'2-digit', minute:'2-digit'})}`;
    $('progressBar').style.width = '100%';
    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  window.submitApplication = async function submitApplicationSupabase() {
    const btn = $('btnSubmit');
    if (!db) {
      Swal.fire({ title: 'ยังไม่ได้เชื่อมต่อฐานข้อมูล', text: 'กรุณาตรวจสอบ Supabase configuration', icon: 'error', confirmButtonColor: '#f97316' });
      return;
    }

    const payload = collectFullApplicationPayload();
    if (!payload.pdpaAccepted) {
      Swal.fire({ title: 'กรุณายอมรับเงื่อนไข PDPA', icon: 'warning', confirmButtonColor: '#f97316' });
      return;
    }
    if (!payload.idCard || !payload.fname || !payload.lname || !payload.levelId) {
      Swal.fire({ title: 'ข้อมูลไม่ครบ', text: 'กรุณากลับไปตรวจสอบข้อมูลผู้สมัครก่อนส่งใบสมัคร', icon: 'warning', confirmButtonColor: '#f97316' });
      return;
    }

    try {
      btn.disabled = true;
      Swal.fire({
        title: 'กำลังส่งใบสมัคร...',
        html: '<div class="text-orange-600 mt-2 font-medium text-sm" id="loading-text">กำลังสร้างเลขที่ใบสมัคร...</div>',
        allowOutsideClick: false,
        showConfirmButton: false,
        didOpen: () => Swal.showLoading()
      });

      const { data: created, error: createError } = await db.rpc('create_admission_application', { p_payload: payload });
      if (createError) throw createError;
      const createdRow = Array.isArray(created) ? created[0] : created;
      if (!createdRow?.id || !createdRow?.upload_token) throw new Error('ระบบไม่สามารถสร้างใบสมัครได้');

      const attachments = await uploadAdmissionFiles(createdRow.id, createdRow.upload_token);
      const loading = $('loading-text');
      if (loading) loading.textContent = 'กำลังบันทึกข้อมูลและยืนยันการส่งใบสมัคร...';

      const { data: finalized, error: finalizeError } = await db.rpc('finalize_admission_application', {
        p_id: createdRow.id,
        p_upload_token: createdRow.upload_token,
        p_attachments: attachments
      });
      if (finalizeError) throw finalizeError;
      const finalRow = Array.isArray(finalized) ? finalized[0] : finalized;

      Swal.close();
      showSuccess(finalRow?.app_number || createdRow.app_number, finalRow?.submitted_at, payload);
    } catch (error) {
      console.error(error);
      Swal.close();
      Swal.fire({
        title: 'ส่งใบสมัครไม่สำเร็จ',
        text: error?.message || 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง',
        icon: 'error',
        confirmButtonColor: '#f97316',
        customClass: { popup: 'rounded-[2rem]' }
      });
      btn.disabled = false;
    }
  };

  window.checkStatus = async function checkStatusSupabase() {
    if (!db) {
      Swal.fire({ title: 'ยังไม่ได้เชื่อมต่อฐานข้อมูล', icon: 'error', confirmButtonColor: '#f97316' });
      return;
    }
    const result = await Swal.fire({
      title: 'ตรวจสอบสถานะการรับสมัคร',
      input: 'text',
      inputLabel: 'กรอกเลขประจำตัวประชาชน 13 หลัก',
      inputPlaceholder: 'xxxxxxxxxxxxx',
      inputAttributes: { maxlength: 13, inputmode: 'numeric' },
      showCancelButton: true,
      confirmButtonText: 'ตรวจสอบ',
      cancelButtonText: 'ปิด',
      confirmButtonColor: '#f97316',
      customClass: { popup: 'rounded-[2rem]' },
      inputValidator: (value) => (!/^\d{13}$/.test(value || '') ? 'กรุณากรอกเลขประจำตัวประชาชน 13 หลัก' : undefined)
    });
    if (!result.isConfirmed) return;

    Swal.fire({ title: 'กำลังค้นหาข้อมูล...', allowOutsideClick: false, showConfirmButton: false, didOpen: () => Swal.showLoading() });
    const { data, error } = await db.rpc('check_admission_status', { p_id_card: result.value });
    if (error) {
      Swal.fire({ title: 'ตรวจสอบไม่สำเร็จ', text: error.message, icon: 'error', confirmButtonColor: '#f97316' });
      return;
    }
    const row = Array.isArray(data) ? data[0] : data;
    if (!row) {
      Swal.fire({ title: 'ไม่พบใบสมัคร', text: 'ไม่พบข้อมูลที่ตรงกับเลขประจำตัวประชาชนนี้', icon: 'info', confirmButtonColor: '#f97316' });
      return;
    }
    const meta = STATUS_META[row.status] || STATUS_META.pending;
    const date = row.submitted_at ? new Date(row.submitted_at).toLocaleString('th-TH') : '-';
    Swal.fire({
      title: escapeText(meta.label),
      html: `
        <div class="text-left bg-slate-50 rounded-2xl p-4 text-sm space-y-2 border border-slate-200">
          <div><span class="text-slate-400">เลขที่ใบสมัคร:</span> <strong class="text-orange-600 ml-2">${escapeText(row.app_number)}</strong></div>
          <div><span class="text-slate-400">ผู้สมัคร:</span> <strong class="ml-2">${escapeText(row.full_name)}</strong></div>
          <div><span class="text-slate-400">ระดับชั้น:</span> <span class="ml-2">${escapeText(row.level)}</span></div>
          <div><span class="text-slate-400">แผนการเรียน:</span> <span class="ml-2">${escapeText(row.study_plan || '-')}</span></div>
          <div><span class="text-slate-400">ส่งเมื่อ:</span> <span class="ml-2">${escapeText(date)}</span></div>
          ${row.public_message ? `<div class="mt-3 bg-white p-3 rounded-xl border"><span class="text-slate-400 block text-xs mb-1">ข้อความจากโรงเรียน</span>${escapeText(row.public_message)}</div>` : ''}
        </div>`,
      icon: row.status === 'approved' ? 'success' : row.status === 'rejected' ? 'error' : 'info',
      confirmButtonColor: meta.color,
      confirmButtonText: 'ปิด',
      customClass: { popup: 'rounded-[2rem]' }
    });
  };

  // Disable the legacy embedded password-admin path completely.
  window.verifyAdmin = () => { window.location.href = './manager/'; };
  window.loadAdminData = () => { window.location.href = './manager/'; };

  document.addEventListener('DOMContentLoaded', loadSchoolBranding);
})();
