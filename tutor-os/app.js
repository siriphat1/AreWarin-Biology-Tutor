(() => {
  'use strict';

  const cfg = window.AREWARIN_CONFIG || {};
  const loginView = document.getElementById('loginView');
  const appView = document.getElementById('appView');
  const modalRoot = document.getElementById('modalRoot');
  const $ = (id) => document.getElementById(id);
  const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

  const state = {
    sb: null,
    data: null,
    section: new URLSearchParams(location.search).get('section') || 'today',
    signupPhone: '',
    signupLookup: null,
    realtime: null,
    reloadTimer: null,
  };

  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[c]));
  const num = (v) => Number(v || 0);
  const arr = (v) => Array.isArray(v) ? v : [];
  const fmtMoney = (v) => `฿${num(v).toLocaleString('th-TH', { maximumFractionDigits: 2 })}`;
  const fmtDate = (v) => v ? new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium' }).format(new Date(v)) : '—';
  const fmtDateTime = (v) => v ? new Intl.DateTimeFormat('th-TH', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(v)) : '—';
  const toLocalInput = (v) => {
    if (!v) return '';
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return '';
    const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0, 16);
  };
  const fullName = (s = {}) => [s.first_name, s.last_name].filter(Boolean).join(' ') || s.name || s.display_name || 'ไม่ระบุชื่อ';
  const statusLabel = (v) => ({
    active: 'กำลังเรียน', paused: 'พักเรียน', completed: 'จบแล้ว', cancelled: 'ยกเลิก',
    open: 'กำลังสอน', closed: 'จบคาบ', present: 'เข้าเรียน', late: 'สาย', absent: 'ขาด',
    leave: 'ลา', makeup: 'ชดเชย', tutor: 'Tutor', manager: 'Manager', admin: 'Admin'
  })[v] || v || '—';

  function friendlyError(error) {
    const m = String(error?.message || error || 'เกิดข้อผิดพลาด');
    if (/Invalid login credentials/i.test(m)) return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    if (/Email not confirmed/i.test(m)) return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
    if (/Tutor account is not linked/i.test(m)) return 'บัญชีนี้ยังไม่ได้เชื่อมกับติวเตอร์ กรุณาใช้เมนู “เปิดบัญชีด้วยเบอร์ที่ใช้สมัคร”';
    if (/not accepted/i.test(m)) return 'ใบสมัครติวเตอร์ยังไม่ได้รับการอนุมัติ';
    return m;
  }

  function alertToast(icon, title, text = '') {
    if (window.Swal) {
      return Swal.fire({
        toast: true, position: 'top-end', timer: 3300, showConfirmButton: false,
        icon, title, text
      });
    }
    console.log(title, text);
  }

  function loading(title = 'กำลังดำเนินการ...') {
    if (!window.Swal) return;
    Swal.fire({ title, allowOutsideClick: false, showConfirmButton: false, didOpen: () => Swal.showLoading() });
  }

  async function rpc(name, args = {}) {
    const { data, error } = await state.sb.rpc(name, args);
    if (error) throw error;
    return data;
  }

  function setConnection(ok, text = ok ? 'Connected' : 'Disconnected') {
    const dot = $('connectionDot');
    const label = $('connectionText');
    if (dot) dot.style.background = ok ? '#22c55e' : '#ef4444';
    if (label) label.textContent = text;
  }

  function showLogin() {
    loginView.classList.remove('hidden');
    appView.classList.add('hidden');
  }

  function showApp() {
    loginView.classList.add('hidden');
    appView.classList.remove('hidden');
  }

  function currentRole() { return state.data?.role || 'tutor'; }
  function isAdmin() { return !!state.data?.is_admin; }
  function currentTutorId() { return state.data?.tutor?.id || state.data?.profile?.tutor_id || null; }

  function courseById(id) {
    return arr(state.data?.courses).find((x) => String(x.id) === String(id));
  }
  function studentById(id) {
    return arr(state.data?.students).find((x) => String(x.id) === String(id));
  }
  function enrollmentById(id) {
    return arr(state.data?.enrollments).find((x) => String(x.id) === String(id));
  }
  function tutorById(id) {
    const self = state.data?.tutor;
    if (self && String(self.id) === String(id)) return self;
    return arr(state.data?.team).find((x) => String(x.id) === String(id));
  }

  function scopedEnrollmentLabel(e) {
    const s = studentById(e.student_id);
    const c = courseById(e.course_id);
    return `${fullName(s)} · ${c?.title || c?.name || e.course_label || 'คอร์ส'}`;
  }

  function sectionHeader(kicker, title, subtitle, right = '') {
    return `<div class="page-head"><div><div class="page-kicker">${esc(kicker)}</div><h1 class="page-title">${esc(title)}</h1><p class="page-subtitle">${esc(subtitle)}</p></div>${right}</div>`;
  }

  function metric(icon, label, value, note = '') {
    return `<article class="aw-card metric-card"><div class="metric-icon"><i class="fa-solid ${icon}"></i></div><div class="metric-value">${esc(value)}</div><div class="metric-label">${esc(label)}</div><div class="metric-note">${esc(note)}</div></article>`;
  }

  function overviewHtml() {
    const students = arr(state.data?.students);
    const enrollments = arr(state.data?.enrollments).filter((e) => ['active', 'paused'].includes(e.status));
    const sessions = arr(state.data?.sessions);
    const running = sessions.filter((s) => s.status === 'open' && !s.actual_end_at);
    const used = arr(state.data?.hour_ledger).reduce((sum, x) => sum + Math.max(0, num(x.hours_delta)), 0);
    return `${sectionHeader('OVERVIEW', 'ภาพรวม Tutor OS', isAdmin() ? 'มุมมองผู้ดูแลระบบ · เห็นข้อมูลทุกติวเตอร์' : 'ข้อมูลถูกจำกัดเฉพาะนักเรียนและคอร์สที่คุณรับผิดชอบ')}
      <div class="metric-grid">
        ${metric('fa-user-graduate', 'นักเรียนในความดูแล', students.length, isAdmin() ? 'ทุกคนในระบบ' : 'เฉพาะที่ได้รับมอบหมาย')}
        ${metric('fa-book-open', 'Enrollment ที่ใช้งาน', enrollments.length, 'Active / Paused')}
        ${metric('fa-stopwatch', 'คาบที่กำลังสอน', running.length, 'กำลังจับเวลา')}
        ${metric('fa-clock-rotate-left', 'ชั่วโมงที่บันทึก', used.toFixed(1), 'รวมจาก Hour Ledger')}
      </div>
      <div class="grid-2" style="margin-top:14px">
        <section class="aw-card content-card"><div class="card-head"><div><h2>สิทธิ์ข้อมูล</h2><p>ระบบตรวจสิทธิ์จากบัญชีที่ล็อกอินและ Tutor ID ฝั่งฐานข้อมูล</p></div><span class="aw-tag">${esc(statusLabel(currentRole()))}</span></div>
          <div class="section-note"><b>${isAdmin() ? 'Admin access' : 'Tutor scoped access'}</b><br>${isAdmin() ? 'สามารถดูและจัดการข้อมูลทุกติวเตอร์ได้' : 'ไม่สามารถอ่านนักเรียนหรือคาบของติวเตอร์อื่นผ่าน RPC ของ Tutor OS ได้'}</div></section>
        <section class="aw-card content-card"><div class="card-head"><div><h2>บัญชีผู้สอน</h2><p>เชื่อมจากใบสมัคร tutor-apply ที่ผ่านการพิจารณา</p></div></div>
          <div class="detail-list"><div><span>ชื่อ</span><b>${esc(state.data?.profile?.display_name || state.data?.tutor?.display_name || '—')}</b></div><div><span>อีเมล</span><b>${esc(state.data?.identity?.email || '—')}</b></div><div><span>ติวเตอร์</span><b>${esc(state.data?.tutor?.display_name || (isAdmin() ? 'Admin' : '—'))}</b></div></div></section>
      </div>`;
  }

  function todayHtml() {
    const today = new Date().toLocaleDateString('sv-SE', { timeZone: 'Asia/Bangkok' });
    const sessions = arr(state.data?.sessions).filter((s) => String(s.session_date || '').slice(0, 10) === today);
    const enrollments = arr(state.data?.enrollments).filter((e) => ['active', 'paused'].includes(e.status));
    const running = sessions.filter((s) => s.status === 'open' && !s.actual_end_at);
    const startOptions = enrollments.map((e) => `<option value="${esc(e.id)}">${esc(scopedEnrollmentLabel(e))}</option>`).join('');
    return `${sectionHeader('TODAY TEACHING', 'การสอนวันนี้', 'เริ่มจับเวลา จบคาบ ตัดชั่วโมง และแก้ไขบันทึกจากหน้าเดียว', `<button class="aw-btn primary" id="newPrivateLessonBtn"><i class="fa-solid fa-play"></i> เริ่มสอนรายบุคคล</button>`)}
      ${running.length ? `<div class="grid-2">${running.map(sessionCard).join('')}</div>` : '<div class="aw-card empty-state"><i class="fa-regular fa-clock"></i><b>ยังไม่มีคาบที่กำลังจับเวลา</b><span>กด “เริ่มสอนรายบุคคล” เพื่อเริ่มบันทึกเวลา</span></div>'}
      <section class="aw-card content-card" style="margin-top:14px"><div class="card-head"><div><h2>คาบวันนี้</h2><p>${sessions.length} รายการ</p></div></div>${sessionTable(sessions)}</section>
      <template id="todayEnrollmentOptions">${startOptions}</template>`;
  }

  function sessionCard(s) {
    const st = studentById(s.student_id);
    const course = courseById(s.course_id);
    const tutor = tutorById(s.tutor_id);
    return `<article class="aw-card session-live"><div class="card-head"><div><span class="live-pill"><i></i> LIVE</span><h2>${esc(s.title || course?.title || course?.name || 'คาบเรียน')}</h2><p>${esc(fullName(st))} · ${esc(tutor?.display_name || state.data?.tutor?.display_name || 'Tutor')}</p></div><div class="timer-big">${esc(s.actual_start_at ? new Intl.DateTimeFormat('th-TH', { timeStyle: 'short' }).format(new Date(s.actual_start_at)) : String(s.start_time || '').slice(0, 5))}</div></div><div class="toolbar"><button class="aw-btn primary" data-finish-session="${esc(s.id)}"><i class="fa-solid fa-stop"></i> จบคาบ</button><button class="aw-btn" data-edit-session="${esc(s.id)}"><i class="fa-solid fa-pen"></i> แก้ไขบันทึก</button></div></article>`;
  }

  function sessionTable(rows) {
    if (!rows.length) return '<div class="empty-state compact">ยังไม่มีประวัติการสอน</div>';
    return `<div class="table-wrap"><table class="aw-table"><thead><tr><th>วันที่</th><th>นักเรียน / คอร์ส</th><th>เวลา</th><th>ผู้สอน</th><th>สถานะ</th><th>ตัดชม.</th><th></th></tr></thead><tbody>${rows.map((s) => {
      const st = studentById(s.student_id);
      const c = courseById(s.course_id);
      const t = tutorById(s.tutor_id);
      const start = s.actual_start_at ? new Intl.DateTimeFormat('th-TH', { timeStyle: 'short' }).format(new Date(s.actual_start_at)) : String(s.start_time || '').slice(0, 5);
      const end = s.actual_end_at ? new Intl.DateTimeFormat('th-TH', { timeStyle: 'short' }).format(new Date(s.actual_end_at)) : String(s.end_time || '').slice(0, 5);
      return `<tr><td>${esc(fmtDate(s.session_date))}</td><td><b>${esc(fullName(st))}</b><small>${esc(c?.title || c?.name || s.course_name || 'คอร์ส')} · ${esc(s.title || 'คาบเรียน')}</small></td><td>${esc(start || '—')}${end ? ` – ${esc(end)}` : ''}</td><td>${esc(t?.display_name || s.tutor_name || 'Tutor')}</td><td><span class="aw-tag">${esc(statusLabel(s.attendance_status || s.status))}</span></td><td><b>${num(s.deducted_hours).toFixed(2)}</b> ชม.</td><td><div class="table-actions">${s.status === 'open' && !s.actual_end_at ? `<button class="icon-btn success" data-finish-session="${esc(s.id)}" title="จบคาบ"><i class="fa-solid fa-stop"></i></button>` : ''}<button class="icon-btn" data-edit-session="${esc(s.id)}" title="แก้ไข"><i class="fa-solid fa-pen"></i></button></div></td></tr>`;
    }).join('')}</tbody></table></div>`;
  }

  function studentsHtml() {
    const rows = arr(state.data?.students);
    return `${sectionHeader('STUDENTS', 'นักเรียน & CRM', isAdmin() ? 'Admin เห็นนักเรียนทั้งหมด' : 'แสดงเฉพาะนักเรียนที่ผูกกับคุณผ่าน Enrollment / Course')}
      <section class="aw-card content-card">${rows.length ? `<div class="table-wrap"><table class="aw-table"><thead><tr><th>Student ID</th><th>นักเรียน</th><th>โรงเรียน</th><th>คอร์สที่กำลังเรียน</th><th>ชั่วโมงคงเหลือ</th></tr></thead><tbody>${rows.map((s) => {
        const ens = arr(state.data?.enrollments).filter((e) => String(e.student_id) === String(s.id) && ['active', 'paused'].includes(e.status));
        const remain = ens.reduce((sum, e) => sum + (e.hours_unlimited ? 0 : Math.max(0, num(e.hours_total) - num(e.hours_used))), 0);
        return `<tr><td><span class="mono-small">${esc(s.student_code || s.id)}</span></td><td><b>${esc(fullName(s))}</b><small>${esc(s.phone || '')}</small></td><td>${esc(s.school || '—')}</td><td>${ens.map((e) => `<span class="aw-tag">${esc(courseById(e.course_id)?.title || courseById(e.course_id)?.name || e.course_label || 'คอร์ส')}</span>`).join(' ') || '—'}</td><td>${ens.some((e) => e.hours_unlimited) ? '∞' : `${remain.toFixed(1)} ชม.`}</td></tr>`;
      }).join('')}</tbody></table></div>` : '<div class="empty-state">ยังไม่มีนักเรียนในสิทธิ์ของบัญชีนี้</div>'}</section>`;
  }

  function coursesHtml() {
    const courses = arr(state.data?.courses);
    return `${sectionHeader('COURSES', 'คอร์ส & สมัคร', isAdmin() ? 'คอร์สทั้งหมดในระบบ' : 'เฉพาะคอร์สที่คุณเป็นผู้สอนหรือมี Enrollment ที่ได้รับมอบหมาย')}
      <div class="grid-3">${courses.map((c) => {
        const es = arr(state.data?.enrollments).filter((e) => String(e.course_id) === String(c.id) && ['active', 'paused'].includes(e.status));
        return `<article class="aw-card course-card"><div class="course-card-icon"><i class="fa-solid fa-book-open"></i></div><h3>${esc(c.title || c.name || 'คอร์ส')}</h3><p>${esc(c.short_detail || c.description || '')}</p><div class="detail-list"><div><span>นักเรียน</span><b>${new Set(es.map((x) => String(x.student_id))).size} คน</b></div><div><span>สถานะ</span><b>${c.active === false || c.is_active === false ? 'ปิด' : 'เปิด'}</b></div></div></article>`;
      }).join('') || '<div class="aw-card empty-state">ยังไม่มีคอร์สในสิทธิ์ของบัญชีนี้</div>'}</div>`;
  }

  function groupsHtml() {
    const groups = arr(state.data?.groups);
    return `${sectionHeader('GROUP LOCKER', 'กลุ่มเรียน · Locker', 'กลุ่มที่เกี่ยวข้องกับติวเตอร์และนักเรียนในสิทธิ์ของคุณ')}
      <div class="locker-grid">${groups.map((g) => `<article class="aw-card locker-card"><div class="locker-icon"><i class="fa-solid fa-people-group"></i></div><h3>${esc(g.name || g.group_code || 'กลุ่มเรียน')}</h3><p>${esc(g.group_code || '')}</p><span class="aw-tag">${esc(courseById(g.course_id)?.title || courseById(g.course_id)?.name || 'คอร์ส')}</span></article>`).join('') || '<div class="aw-card empty-state">ยังไม่มีกลุ่มเรียนในสิทธิ์ของคุณ</div>'}</div>`;
  }

  function teachingHtml() {
    const sessions = arr(state.data?.sessions);
    return `${sectionHeader('TEACHING LOG', 'ประวัติการสอน', 'แก้ชื่อหัวข้อ หมายเหตุ เวลา สถานะเข้าเรียน และจำนวนชั่วโมงย้อนหลังได้')}
      <section class="aw-card content-card">${sessionTable(sessions)}</section>`;
  }

  function servicesHtml() {
    return `${sectionHeader('STUDENT SERVICES', 'Student Services', 'ข้อมูลบริการที่เกี่ยวข้องกับนักเรียนในสิทธิ์ของคุณ')}
      <div class="grid-3">${metric('fa-id-card', 'นักเรียนที่เชื่อม Portal', arr(state.data?.students).filter((s) => s.auth_user_id).length, 'เชื่อมบัญชีแล้ว')}${metric('fa-wallet', 'Course Wallet', arr(state.data?.enrollments).length, 'Enrollment ที่มองเห็นได้')}${metric('fa-people-group', 'กลุ่มเรียน', arr(state.data?.groups).length, 'เฉพาะกลุ่มที่เกี่ยวข้อง')}</div>`;
  }

  function financeHtml() {
    if (!isAdmin()) return '<div class="aw-card empty-state">เมนูนี้สำหรับ Admin เท่านั้น</div>';
    return `${sectionHeader('FINANCE', 'การเงิน', 'ข้อมูลการเงินยังจัดการจาก Manager หลักเพื่อรักษา source of truth เดียวกัน')}
      <div class="aw-card content-card"><div class="section-note">เปิด <b>AreWarin Manager → การชำระเงิน</b> เพื่อจัดการยอดและสลิป โดย Tutor OS V18 ไม่เปิดข้อมูลการเงินของนักเรียนให้ Tutor</div></div>`;
  }

  function teamHtml() {
    if (!isAdmin()) return '<div class="aw-card empty-state">เมนูนี้สำหรับ Admin เท่านั้น</div>';
    const team = arr(state.data?.team);
    return `${sectionHeader('TEAM', 'ทีมติวเตอร์', 'Admin เห็นบัญชีติวเตอร์ทั้งหมด')}
      <div class="grid-3">${team.map((t) => `<article class="aw-card course-card"><div class="course-card-icon"><i class="fa-solid fa-chalkboard-user"></i></div><h3>${esc(t.display_name || 'Tutor')}</h3><p>${esc(t.role_text || t.primary_subject || '')}</p><span class="aw-tag">${t.identity_status === 'active' ? 'เปิดบัญชีแล้ว' : 'ยังไม่เชื่อมบัญชี'}</span></article>`).join('') || '<div class="aw-card empty-state">ยังไม่มีติวเตอร์</div>'}</div>`;
  }

  function reportsHtml() {
    const sessions = arr(state.data?.sessions);
    const completed = sessions.filter((s) => s.actual_end_at || s.status === 'closed');
    const hours = completed.reduce((sum, s) => sum + num(s.deducted_hours), 0);
    return `${sectionHeader('REPORTS', 'รายงาน', isAdmin() ? 'รายงานรวมทุกติวเตอร์' : 'รายงานเฉพาะงานสอนของคุณ')}
      <div class="metric-grid">${metric('fa-chalkboard-user', 'คาบทั้งหมด', sessions.length, 'ในขอบเขตสิทธิ์')}${metric('fa-circle-check', 'คาบที่จบแล้ว', completed.length, 'บันทึกเรียบร้อย')}${metric('fa-hourglass-half', 'ชั่วโมงสอน', hours.toFixed(2), 'จากจำนวนชั่วโมงที่ตัด')}</div>`;
  }

  function settingsHtml() {
    return `${sectionHeader('SETTINGS', 'ตั้งค่า & เครื่องมือ', 'ข้อมูลบัญชีและสถานะการเชื่อมต่อ')}
      <div class="grid-2"><section class="aw-card content-card"><div class="card-head"><div><h2>Account</h2><p>Supabase Auth + Tutor identity</p></div></div><div class="detail-list"><div><span>Role</span><b>${esc(statusLabel(currentRole()))}</b></div><div><span>Tutor ID</span><b class="mono-small">${esc(currentTutorId() || 'Admin')}</b></div><div><span>Application</span><b>${esc(state.data?.identity?.application_ref || '—')}</b></div></div></section><section class="aw-card content-card"><div class="card-head"><div><h2>Security</h2><p>Data isolation enforced server-side</p></div></div><div class="section-note"><b>RLS + Security Definer RPC</b><br>Frontend ไม่ส่ง Tutor ID เพื่อกำหนดสิทธิ์เอง ฟังก์ชันฝั่งฐานข้อมูลอ่านผู้ใช้จาก <span class="mono-small">auth.uid()</span> ทุกครั้ง</div></section></div>`;
  }

  function render() {
    if (!state.data) return;
    const map = {
      overview: overviewHtml, today: todayHtml, students: studentsHtml, courses: coursesHtml,
      groups: groupsHtml, teaching: teachingHtml, services: servicesHtml, finance: financeHtml,
      team: teamHtml, reports: reportsHtml, settings: settingsHtml
    };
    if (!map[state.section]) state.section = 'today';

    $$('.section').forEach((s) => { s.classList.remove('active'); s.innerHTML = ''; });
    const target = $(`section-${state.section}`);
    if (target) {
      target.classList.add('active');
      target.innerHTML = map[state.section]();
    }

    $$('.nav-btn').forEach((b) => b.classList.toggle('active', b.dataset.section === state.section));
    $$('.admin-only').forEach((el) => el.classList.toggle('hidden', !isAdmin()));
    const mgr = $('managerTopLink');
    if (mgr) mgr.classList.toggle('hidden', !isAdmin());

    $('userLabel').textContent = `${state.data?.profile?.display_name || state.data?.tutor?.display_name || 'Tutor'} · ${statusLabel(currentRole())}`;
    bindRendered();
  }

  function bindRendered() {
    $('newPrivateLessonBtn')?.addEventListener('click', openStartLesson);
    $$('[data-finish-session]').forEach((b) => b.onclick = () => finishLesson(b.dataset.finishSession));
    $$('[data-edit-session]').forEach((b) => b.onclick = () => openEditLesson(b.dataset.editSession));
  }

  function openStartLesson() {
    const rows = arr(state.data?.enrollments).filter((e) => ['active', 'paused'].includes(e.status));
    if (!rows.length) return alertToast('warning', 'ยังไม่มี Enrollment ที่พร้อมสอน');
    showModal('เริ่มสอนรายบุคคล', `<form id="startLessonForm"><div class="form-grid"><label class="aw-label wide">นักเรียน / คอร์ส<select class="aw-input" name="enrollment_id" required>${rows.map((e) => `<option value="${esc(e.id)}">${esc(scopedEnrollmentLabel(e))}</option>`).join('')}</select></label><label class="aw-label wide">หัวข้อ<input class="aw-input" name="title" placeholder="เช่น Cell biology · ครั้งที่ 1"></label><label class="aw-label wide">หมายเหตุ<textarea class="aw-textarea" name="note" rows="3" placeholder="เป้าหมายหรือเนื้อหาที่จะสอน"></textarea></label></div></form>`, `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="confirmStartLesson"><i class="fa-solid fa-play"></i> เริ่มจับเวลา</button>`);
    $('confirmStartLesson').onclick = async () => {
      const fd = new FormData($('startLessonForm'));
      try {
        loading('กำลังเริ่มจับเวลา...');
        await rpc('os_v18_start_private_lesson', {
          p_student_course_enrollment_id: fd.get('enrollment_id'),
          p_title: String(fd.get('title') || '').trim() || null,
          p_note: String(fd.get('note') || '').trim() || null
        });
        Swal.close(); closeModal();
        alertToast('success', 'เริ่มจับเวลาแล้ว');
        await loadData(false);
      } catch (e) { Swal.close(); alertToast('error', 'เริ่มจับเวลาไม่สำเร็จ', friendlyError(e)); }
    };
  }

  async function finishLesson(sessionId) {
    const result = await Swal.fire({
      title: 'จบคาบและตัดชั่วโมง?',
      text: 'ระบบจะคำนวณเวลาจริง ปัดเป็นช่วงละ 15 นาที และอัปเดต Course Wallet',
      icon: 'question', showCancelButton: true, confirmButtonText: 'จบคาบ', cancelButtonText: 'ยกเลิก', confirmButtonColor: '#0f766e'
    });
    if (!result.isConfirmed) return;
    try {
      loading('กำลังบันทึกคาบ...');
      const r = await rpc('os_v18_finish_private_lesson', { p_session_id: sessionId, p_attendance_status: 'present', p_note: null });
      Swal.close();
      alertToast('success', 'บันทึกการสอนแล้ว', r?.deducted_hours != null ? `ตัด ${num(r.deducted_hours).toFixed(2)} ชั่วโมง` : '');
      await loadData(false);
    } catch (e) { Swal.close(); alertToast('error', 'จบคาบไม่สำเร็จ', friendlyError(e)); }
  }

  function openEditLesson(sessionId) {
    const s = arr(state.data?.sessions).find((x) => String(x.id) === String(sessionId));
    if (!s) return;
    showModal('แก้ไขบันทึกการสอน', `<form id="editLessonForm"><div class="form-grid"><label class="aw-label wide">หัวข้อ<input class="aw-input" name="title" value="${esc(s.title || '')}"></label><label class="aw-label">เวลาเริ่ม<input class="aw-input" type="datetime-local" name="start" value="${esc(toLocalInput(s.actual_start_at))}"></label><label class="aw-label">เวลาสิ้นสุด<input class="aw-input" type="datetime-local" name="end" value="${esc(toLocalInput(s.actual_end_at))}"></label><label class="aw-label">สถานะเข้าเรียน<select class="aw-input" name="attendance_status">${[['present','เข้าเรียน'],['late','สาย'],['leave','ลา'],['absent','ขาด'],['makeup','ชดเชย']].map(([v,l]) => `<option value="${v}" ${String(s.attendance_status || 'present') === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label><label class="aw-label">ชั่วโมงที่ตัด<input class="aw-input" type="number" min="0" step="0.25" name="deducted_hours" value="${num(s.deducted_hours).toFixed(2)}"></label><label class="aw-label wide">หมายเหตุ<textarea class="aw-textarea" name="note" rows="4">${esc(s.attendance_note || s.note || '')}</textarea></label></div></form>`, `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="saveLessonEdit"><i class="fa-solid fa-floppy-disk"></i> บันทึกการแก้ไข</button>`);
    $('saveLessonEdit').onclick = async () => {
      const fd = new FormData($('editLessonForm'));
      const start = fd.get('start') ? new Date(fd.get('start')).toISOString() : null;
      const end = fd.get('end') ? new Date(fd.get('end')).toISOString() : null;
      try {
        loading('กำลังปรับบันทึกและชั่วโมง...');
        await rpc('os_v18_update_lesson_record', {
          p_session_id: sessionId,
          p_title: String(fd.get('title') || '').trim() || null,
          p_note: String(fd.get('note') || '').trim() || null,
          p_actual_start_at: start,
          p_actual_end_at: end,
          p_attendance_status: fd.get('attendance_status'),
          p_deducted_hours: num(fd.get('deducted_hours'))
        });
        Swal.close(); closeModal();
        alertToast('success', 'แก้ไขบันทึกการสอนแล้ว');
        await loadData(false);
      } catch (e) { Swal.close(); alertToast('error', 'แก้ไขไม่สำเร็จ', friendlyError(e)); }
    };
  }

  function showModal(title, body, actions = '') {
    modalRoot.innerHTML = `<div class="modal-backdrop"><section class="modal-card"><header class="modal-head"><div><span class="page-kicker">TUTOR OS</span><h3>${esc(title)}</h3></div><button class="icon-btn" data-modal-close><i class="fa-solid fa-xmark"></i></button></header><div class="modal-body">${body}</div><footer class="modal-actions">${actions}</footer></section></div>`;
    $$('[data-modal-close]', modalRoot).forEach((b) => b.onclick = closeModal);
    modalRoot.querySelector('.modal-backdrop')?.addEventListener('click', (e) => { if (e.target.classList.contains('modal-backdrop')) closeModal(); });
  }
  function closeModal() { modalRoot.innerHTML = ''; }

  async function loadData(showLoader = true) {
    if (showLoader) {
      showApp();
      $('section-today').classList.add('active');
      $('section-today').innerHTML = '<div class="aw-card empty-state"><div class="spinner"></div><b>กำลังโหลดข้อมูลตามสิทธิ์...</b></div>';
    }
    try {
      state.data = await rpc('tutor_os_bootstrap_v18');
      showApp();
      setConnection(true);
      render();
      setupRealtime();
    } catch (e) {
      setConnection(false, 'Access denied');
      const pendingPhone = localStorage.getItem('arewarin_tutor_pending_phone');
      if (pendingPhone && /not linked|Tutor account/i.test(String(e.message || e))) {
        try {
          await rpc('tutor_os_claim_accepted_application', { p_phone: pendingPhone });
          localStorage.removeItem('arewarin_tutor_pending_phone');
          state.data = await rpc('tutor_os_bootstrap_v18');
          showApp(); render(); setupRealtime(); return;
        } catch (_) {}
      }
      await state.sb.auth.signOut({ scope: 'local' }).catch(() => {});
      showLogin();
      $('loginHint').innerHTML = `<b>เปิด Tutor OS ไม่สำเร็จ</b><br>${esc(friendlyError(e))}`;
    }
  }

  function setupRealtime() {
    if (state.realtime) return;
    let ch = state.sb.channel('tutor-os-v18');
    ['os_student_course_enrollments', 'os_attendance_sessions', 'os_student_attendance', 'os_hour_ledger', 'os_hour_pools', 'os_student_groups'].forEach((table) => {
      ch = ch.on('postgres_changes', { event: '*', schema: 'public', table }, () => {
        clearTimeout(state.reloadTimer);
        state.reloadTimer = setTimeout(() => loadData(false), 500);
      });
    });
    state.realtime = ch.subscribe();
  }

  async function login(e) {
    e.preventDefault();
    const email = $('loginEmail').value.trim().toLowerCase();
    const password = $('loginPassword').value;
    try {
      loading('กำลังเข้าสู่ระบบ...');
      const { data, error } = await state.sb.auth.signInWithPassword({ email, password });
      if (error) throw error;
      if (!data.session) throw new Error('ไม่พบ session');
      const pending = localStorage.getItem('arewarin_tutor_pending_phone');
      if (pending) {
        try {
          await rpc('tutor_os_claim_accepted_application', { p_phone: pending });
          localStorage.removeItem('arewarin_tutor_pending_phone');
        } catch (claimError) {
          console.warn('Tutor claim pending:', claimError);
        }
      }
      Swal.close();
      await loadData();
    } catch (e2) {
      Swal.close();
      alertToast('error', 'เข้าสู่ระบบไม่สำเร็จ', friendlyError(e2));
    }
  }

  async function lookupTutorPhone(e) {
    e.preventDefault();
    const phone = $('tutorSignupPhone').value.trim();
    if (!phone) return;
    try {
      loading('กำลังตรวจสอบใบสมัครติวเตอร์...');
      const result = await rpc('tutor_os_lookup_accepted_application', { p_phone: phone });
      Swal.close();
      state.signupPhone = phone;
      state.signupLookup = result;
      const box = $('tutorLookupResult');
      if (!result?.found) {
        box.innerHTML = '<div class="section-note danger-note"><b>ไม่พบใบสมัคร</b><br>กรุณาใช้เบอร์เดียวกับที่ส่งผ่าน tutor-apply</div>';
        $('tutorCreateAccountForm').classList.add('hidden');
        return;
      }
      if (!result?.eligible) {
        box.innerHTML = `<div class="section-note danger-note"><b>ยังเปิดบัญชีไม่ได้</b><br>สถานะใบสมัคร: ${esc(result.status || 'ยังไม่ผ่านการพิจารณา')}</div>`;
        $('tutorCreateAccountForm').classList.add('hidden');
        return;
      }
      box.innerHTML = `<div class="section-note"><b>${esc(result.display_name || 'Tutor')}</b><br>ใบสมัครผ่านการพิจารณาแล้ว · อีเมล ${esc(result.email_hint || 'ที่ใช้สมัคร')}</div>`;
      $('tutorSignupEmail').value = '';
      $('tutorCreateAccountForm').classList.remove('hidden');
    } catch (err) {
      Swal.close();
      alertToast('error', 'ตรวจสอบเบอร์ไม่สำเร็จ', friendlyError(err));
    }
  }

  async function createTutorAccount(e) {
    e.preventDefault();
    if (!state.signupLookup?.eligible || !state.signupPhone) return alertToast('warning', 'กรุณาตรวจสอบเบอร์ก่อน');
    const email = $('tutorSignupEmail').value.trim().toLowerCase();
    const password = $('tutorSignupPassword').value;
    const confirm = $('tutorSignupPasswordConfirm').value;
    if (password !== confirm) return alertToast('warning', 'รหัสผ่านไม่ตรงกัน');
    if (password.length < 8) return alertToast('warning', 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
    try {
      loading('กำลังสร้างบัญชีติวเตอร์...');
      localStorage.setItem('arewarin_tutor_pending_phone', state.signupPhone);
      const { data, error } = await state.sb.auth.signUp({
        email, password,
        options: { data: { role: 'tutor', signup_source: 'tutor-apply' } }
      });
      if (error) throw error;
      if (data.session) {
        await rpc('tutor_os_claim_accepted_application', { p_phone: state.signupPhone });
        localStorage.removeItem('arewarin_tutor_pending_phone');
        Swal.close();
        await Swal.fire({ icon: 'success', title: 'เปิดบัญชีติวเตอร์แล้ว', text: 'ข้อมูลบัญชีเชื่อมกับใบสมัคร tutor-apply เรียบร้อย' });
        await loadData();
      } else {
        Swal.close();
        await Swal.fire({ icon: 'success', title: 'สร้างบัญชีแล้ว', text: 'กรุณายืนยันอีเมล จากนั้นกลับมาเข้าสู่ระบบ ระบบจะเชื่อม Tutor ID ให้อัตโนมัติ' });
        showSignup(false);
        $('loginEmail').value = email;
      }
    } catch (err) {
      Swal.close();
      alertToast('error', 'สร้างบัญชีไม่สำเร็จ', friendlyError(err));
    }
  }

  function showSignup(show) {
    $('loginForm').classList.toggle('hidden', show);
    $('openTutorSignup').classList.toggle('hidden', show);
    $('tutorSignupPanel').classList.toggle('hidden', !show);
    $('loginHint').classList.toggle('hidden', show);
    if (!show) {
      state.signupLookup = null;
      state.signupPhone = '';
      $('tutorCreateAccountForm').classList.add('hidden');
      $('tutorLookupResult').innerHTML = '';
    }
  }

  async function logout() {
    if (state.realtime) { try { await state.sb.removeChannel(state.realtime); } catch (_) {} state.realtime = null; }
    await state.sb.auth.signOut({ scope: 'local' });
    state.data = null;
    showLogin();
  }

  function bindStatic() {
    $('loginForm').addEventListener('submit', login);
    $('openTutorSignup').addEventListener('click', () => showSignup(true));
    $('backTutorLogin').addEventListener('click', () => showSignup(false));
    $('tutorPhoneForm').addEventListener('submit', lookupTutorPhone);
    $('tutorCreateAccountForm').addEventListener('submit', createTutorAccount);
    $('logoutBtn').addEventListener('click', logout);
    $$('.nav-btn').forEach((b) => b.addEventListener('click', () => {
      if ((b.dataset.section === 'finance' || b.dataset.section === 'team') && !isAdmin()) return;
      state.section = b.dataset.section;
      history.replaceState({}, '', `${location.pathname}?section=${encodeURIComponent(state.section)}`);
      render();
    }));
  }

  async function boot() {
    if (!window.supabase?.createClient || !cfg.SUPABASE_URL || !cfg.SUPABASE_ANON_KEY) {
      $('loginHint').innerHTML = '<b>ยังไม่ได้ตั้งค่า Supabase</b><br>ตรวจสอบ ../config.js';
      return;
    }
    state.sb = window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    window.awTutorSupabase = state.sb;
    bindStatic();
    const { data } = await state.sb.auth.getSession();
    if (data.session) await loadData(); else showLogin();
    state.sb.auth.onAuthStateChange((event, session) => {
      if (event === 'SIGNED_OUT' || !session) showLogin();
    });
  }

  boot();
})();
