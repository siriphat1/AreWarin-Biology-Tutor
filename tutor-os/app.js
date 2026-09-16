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
    active: 'กำลังเรียน', paused: 'พักเรียน', completed: 'จบแล้ว', cancelled: 'ยกเลิก', scheduled: 'นัดสอน', rescheduled: 'เลื่อนนัด', in_progress: 'กำลังสอน',
    open: 'กำลังสอน', closed: 'จบคาบ', present: 'เข้าเรียน', late: 'สาย', absent: 'ขาด',
    leave: 'ลา', tutor: 'Tutor', teacher: 'Tutor', manager: 'Manager', admin: 'Admin'
  })[v] || v || '—';

  function friendlyError(error) {
    const m = String(error?.message || error || 'เกิดข้อผิดพลาด');
    if (/Invalid login credentials/i.test(m)) return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
    if (/Email not confirmed/i.test(m)) return 'กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ';
    if (/Tutor account is not linked/i.test(m)) return 'บัญชีนี้ยังไม่ได้เชื่อมกับใบสมัครติวเตอร์ กรุณาใช้เมนู “เปิดบัญชีด้วยเบอร์ที่ใช้สมัคร”';
    if (/Tutor profile link required/i.test(m)) return 'บัญชีผ่านการยืนยันแล้ว แต่ยังจับคู่กับ Tutor Profile ไม่ได้ กรุณาให้ Admin เชื่อมใบสมัครกับติวเตอร์ 1 ครั้ง';
    if (/not accepted/i.test(m)) return 'ใบสมัครติวเตอร์ยังไม่ได้รับการอนุมัติ';
    if (/Schedule conflict/i.test(m)) return 'เวลานี้ชนกับตารางสอนของนักเรียนหรือติวเตอร์ กรุณาเลือกเวลาใหม่';
    if (/End time must be after start time/i.test(m)) return 'เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม';
    if (/Insufficient remaining hours/i.test(m)) return 'ชั่วโมงคงเหลือไม่พอสำหรับเวลาที่จะตัด';
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
      ${state.data?.needs_tutor_link ? `<div class="aw-card content-card" style="margin-bottom:14px;border-color:#fbbf24;background:#fffbeb"><div class="section-note"><b>บัญชีติวเตอร์ยังรอเชื่อม Tutor Profile</b><br>ระบบยืนยันใบสมัคร tutor-apply และบัญชี Auth แล้ว แต่ยังจับคู่กับรายการในตาราง tutors ไม่ได้ กรุณาให้ Admin เชื่อม Tutor ID ก่อน จึงจะเห็นนักเรียนและเริ่มสอนได้</div></div>` : ''}
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
    const todaySchedules = arr(state.data?.schedules).filter((s) => bangkokDateKey(s.start_at) === today && s.status !== 'cancelled').sort((a,b) => new Date(a.start_at)-new Date(b.start_at));
    const startOptions = enrollments.map((e) => `<option value="${esc(e.id)}">${esc(scopedEnrollmentLabel(e))}</option>`).join('');
    return `${sectionHeader('TODAY TEACHING', 'การสอนวันนี้', 'ดูตาราง เริ่มจับเวลา ลงเวลา Manual และอัปเดตสิ่งที่สอนได้จากหน้าเดียว', `<div class="toolbar"><button class="aw-btn sky" id="manualLessonBtn"><i class="fa-regular fa-clock"></i> ลงเวลา Manual</button><button class="aw-btn" id="todayNewScheduleBtn"><i class="fa-solid fa-calendar-plus"></i> จัดตาราง</button><button class="aw-btn primary" id="newPrivateLessonBtn"><i class="fa-solid fa-play"></i> เริ่มสอนทันที</button></div>`)}
      <section class="aw-card content-card schedule-today-box"><div class="card-head"><div><h2>ตารางวันนี้</h2><p>${todaySchedules.length} นัด · ตารางนี้ซิงก์ไป Student Portal</p></div><button class="aw-btn small" data-open-schedule-page><i class="fa-regular fa-calendar-days"></i> ดูทั้งหมด</button></div>${scheduleRowsHtml(todaySchedules,true)}</section>
      ${running.length ? `<div class="grid-2">${running.map(sessionCard).join('')}</div>` : '<div class="aw-card empty-state"><i class="fa-regular fa-clock"></i><b>ยังไม่มีคาบที่กำลังจับเวลา</b><span>เริ่มจากตารางวันนี้ หรือใช้ “ลงเวลา Manual” สำหรับบันทึกย้อนหลัง</span></div>'}
      <section class="aw-card content-card" style="margin-top:14px"><div class="card-head"><div><h2>บันทึกการสอนวันนี้</h2><p>${sessions.length} รายการ</p></div></div>${sessionTable(sessions)}</section>
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


  const bangkokDateKey = (v) => {
    if (!v) return '';
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return '';
    return new Intl.DateTimeFormat('en-CA', { timeZone: 'Asia/Bangkok', year: 'numeric', month: '2-digit', day: '2-digit' }).format(d);
  };
  const fmtClock = (v) => v ? new Intl.DateTimeFormat('th-TH', { timeZone: 'Asia/Bangkok', hour: '2-digit', minute: '2-digit' }).format(new Date(v)) : '—';
  const scheduleStatusLabel = (v) => ({ scheduled:'นัดสอน', rescheduled:'เลื่อนนัด', in_progress:'กำลังสอน', completed:'สอนแล้ว', cancelled:'ยกเลิก' })[v] || v || '—';
  const scheduleById = (id) => arr(state.data?.schedules).find((x) => String(x.id) === String(id));
  const sessionById = (id) => arr(state.data?.sessions).find((x) => String(x.id) === String(id));

  function scheduleRowsHtml(rows, compact = false) {
    if (!rows.length) return '<div class="empty-state compact">ยังไม่มีตารางสอน</div>';
    return `<div class="schedule-list-v19">${rows.map((x) => {
      const e = enrollmentById(x.student_course_enrollment_id);
      const st = studentById(x.student_id || e?.student_id);
      const c = courseById(x.course_id || e?.course_id);
      const live = x.session_id ? sessionById(x.session_id) : null;
      const canStart = ['scheduled','rescheduled'].includes(x.status) && !x.session_id;
      const canManual = ['scheduled','rescheduled'].includes(x.status) && !x.session_id;
      const canEdit = ['scheduled','rescheduled'].includes(x.status) && !x.session_id;
      const canCancel = ['scheduled','rescheduled'].includes(x.status) && !x.session_id;
      const canDelete = x.status === 'cancelled' && !x.session_id;
      const day = new Intl.DateTimeFormat('th-TH', { timeZone:'Asia/Bangkok', day:'2-digit' }).format(new Date(x.start_at));
      const month = new Intl.DateTimeFormat('th-TH', { timeZone:'Asia/Bangkok', month:'short' }).format(new Date(x.start_at));
      return `<article class="schedule-item-v19"><div class="schedule-date-v19"><b>${esc(day)}</b><span>${esc(month)}</span></div><div class="schedule-copy-v19"><h3>${esc(x.title || c?.title || c?.name || 'คาบเรียน')}</h3><p><b>${esc(fullName(st))}</b> · ${esc(c?.title || c?.name || x.course_name || 'คอร์ส')}</p><small>${esc(fmtDate(x.start_at))} · ${esc(fmtClock(x.start_at))}–${esc(fmtClock(x.end_at))} · ${x.mode === 'online' ? 'Online' : esc(x.location || 'On-site')} ${x.note ? '· ' + esc(x.note) : ''}</small></div><div class="schedule-actions-v19"><span class="schedule-status ${esc(x.status)}">${esc(scheduleStatusLabel(x.status))}</span>${canStart ? `<button class="aw-btn small primary" data-start-schedule="${esc(x.id)}"><i class="fa-solid fa-play"></i> เริ่มคาบ</button>` : ''}${x.status === 'in_progress' && live ? `<button class="aw-btn small success" data-finish-session="${esc(live.id)}"><i class="fa-solid fa-stop"></i> จบคาบ</button>` : ''}${canManual ? `<button class="aw-btn small sky" data-manual-schedule="${esc(x.id)}"><i class="fa-regular fa-clock"></i> ลงเวลา</button>` : ''}${x.status === 'completed' && x.session_id ? `<button class="aw-btn small" data-edit-session="${esc(x.session_id)}"><i class="fa-solid fa-pen"></i> แก้บันทึก</button>` : ''}${canEdit ? `<button class="icon-btn" data-edit-schedule="${esc(x.id)}" title="แก้ตาราง"><i class="fa-solid fa-pen"></i></button>` : ''}${canCancel ? `<button class="icon-btn danger" data-cancel-schedule="${esc(x.id)}" title="ยกเลิกนัด"><i class="fa-solid fa-ban"></i></button>` : ''}${canDelete ? `<button class="icon-btn danger" data-delete-schedule="${esc(x.id)}" title="ลบ"><i class="fa-solid fa-trash"></i></button>` : ''}</div></article>`;
    }).join('')}</div>`;
  }

  function scheduleHtml() {
    const rows = arr(state.data?.schedules).slice().sort((a,b) => new Date(a.start_at) - new Date(b.start_at));
    const now = new Date();
    const todayKey = bangkokDateKey(now);
    const today = rows.filter((x) => bangkokDateKey(x.start_at) === todayKey && x.status !== 'cancelled');
    const upcoming = rows.filter((x) => ['scheduled','rescheduled','in_progress'].includes(x.status) && new Date(x.end_at) >= now);
    const completed = rows.filter((x) => x.status === 'completed');
    return `${sectionHeader('TEACHING SCHEDULE', 'ตารางสอน', 'กำหนดตารางจาก Tutor OS โดยตรง แก้เวลาเองได้ และตารางนี้จะเป็นตารางที่นักเรียนเห็น', `<div class="toolbar"><button class="aw-btn sky" id="manualLessonBtn"><i class="fa-regular fa-clock"></i> ลงเวลา Manual</button><button class="aw-btn primary" id="newScheduleBtn"><i class="fa-solid fa-calendar-plus"></i> เพิ่มตารางสอน</button></div>`)}
      <div class="schedule-hero"><section class="aw-card schedule-summary"><h3>ตารางที่ควบคุมโดย Tutor OS</h3><p>ไม่จำเป็นต้องยึดเวลาจากแบบสมัครเรียน เมื่อจัดตารางตรงนี้แล้ว Student Portal จะดึงเวลาจากตารางนี้อัตโนมัติ</p><div class="schedule-stat-grid"><div class="schedule-stat"><small>วันนี้</small><b>${today.length}</b></div><div class="schedule-stat"><small>กำลังจะถึง</small><b>${upcoming.length}</b></div><div class="schedule-stat"><small>สอนแล้ว</small><b>${completed.length}</b></div></div></section><section class="aw-card schedule-summary"><h3>การลงเวลา 2 แบบ</h3><p><b>Realtime</b> เริ่ม–จบคาบเพื่อจับเวลา หรือ <b>Manual</b> กรอกเวลาเข้า–ออกย้อนหลัง ระบบคำนวณชั่วโมงและตัด Hour Wallet ให้เหมือนกัน</p><div class="section-note" style="margin-top:12px">สถานะนักเรียนรองรับ เข้าเรียน / สาย / ลา / ขาด และสามารถบันทึกหัวข้อ “วันนี้สอนอะไร” พร้อมรายละเอียด/การบ้านได้</div></section></div>
      <section class="aw-card content-card"><div class="card-head"><div><h2>รายการตารางสอน</h2><p>${rows.length} รายการ</p></div></div>${scheduleRowsHtml(rows)}</section>`;
  }

  function openScheduleModal(scheduleId = null) {
    const s = scheduleId ? scheduleById(scheduleId) : null;
    const rows = arr(state.data?.enrollments).filter((e) => ['active','paused'].includes(e.status));
    if (!rows.length) return alertToast('warning','ยังไม่มี Enrollment ที่พร้อมจัดตาราง');
    const defaultStart = s?.start_at || new Date(Date.now() + 3600000).toISOString();
    const defaultEnd = s?.end_at || new Date(Date.now() + 2 * 3600000).toISOString();
    showModal(s ? 'แก้ไขตารางสอน' : 'เพิ่มตารางสอน', `<form id="scheduleForm"><div class="form-grid"><label class="aw-label wide">นักเรียน / คอร์ส<select class="aw-input" name="enrollment_id" required>${rows.map((e) => `<option value="${esc(e.id)}" ${String(s?.student_course_enrollment_id || '') === String(e.id) ? 'selected' : ''}>${esc(scopedEnrollmentLabel(e))}</option>`).join('')}</select></label><label class="aw-label">เริ่มเรียน<input class="aw-input" type="datetime-local" name="start" required value="${esc(toLocalInput(defaultStart))}"></label><label class="aw-label">เลิกเรียน<input class="aw-input" type="datetime-local" name="end" required value="${esc(toLocalInput(defaultEnd))}"></label><label class="aw-label wide">ชื่อคาบ / หัวข้อ<input class="aw-input" name="title" value="${esc(s?.title || '')}" placeholder="เช่น Biochemistry · Enzyme kinetics"></label><label class="aw-label">รูปแบบ<select class="aw-input" name="mode"><option value="online" ${s?.mode !== 'onsite' ? 'selected' : ''}>Online</option><option value="onsite" ${s?.mode === 'onsite' ? 'selected' : ''}>On-site</option></select></label><label class="aw-label">สถานที่ / ลิงก์ห้องเรียน<input class="aw-input" name="location" value="${esc(s?.location || '')}" placeholder="Zoom / ห้องเรียน / สถานที่"></label>${!s ? `<label class="aw-label">ทำซ้ำรายสัปดาห์<select class="aw-input" name="repeat_weeks">${[1,2,4,6,8,10,12,16].map((n) => `<option value="${n}">${n === 1 ? 'ครั้งเดียว' : n + ' สัปดาห์'}</option>`).join('')}</select></label>` : '<div></div>'}<label class="aw-label wide">หมายเหตุสำหรับผู้สอน<textarea class="aw-textarea" name="note" rows="3" placeholder="สิ่งที่ต้องเตรียม / หมายเหตุภายใน">${esc(s?.note || '')}</textarea></label></div></form>`, `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="saveScheduleBtn"><i class="fa-solid fa-floppy-disk"></i> ${s ? 'บันทึกตาราง' : 'สร้างตาราง'}</button>`);
    $('saveScheduleBtn').onclick = async () => {
      const fd = new FormData($('scheduleForm'));
      const start = fd.get('start') ? new Date(fd.get('start')).toISOString() : null;
      const end = fd.get('end') ? new Date(fd.get('end')).toISOString() : null;
      if (!start || !end || new Date(end) <= new Date(start)) return alertToast('warning','เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม');
      try {
        loading(s ? 'กำลังแก้ตาราง...' : 'กำลังสร้างตาราง...');
        if (s) {
          await rpc('os_v19_schedule_update', { p_schedule_id:s.id, p_student_course_enrollment_id:fd.get('enrollment_id'), p_start_at:start, p_end_at:end, p_title:String(fd.get('title') || '').trim() || null, p_mode:fd.get('mode'), p_location:String(fd.get('location') || '').trim() || null, p_note:String(fd.get('note') || '').trim() || null });
        } else {
          await rpc('os_v19_schedule_create', { p_student_course_enrollment_id:fd.get('enrollment_id'), p_start_at:start, p_end_at:end, p_title:String(fd.get('title') || '').trim() || null, p_mode:fd.get('mode'), p_location:String(fd.get('location') || '').trim() || null, p_note:String(fd.get('note') || '').trim() || null, p_repeat_weeks:num(fd.get('repeat_weeks') || 1) });
        }
        Swal.close(); closeModal(); alertToast('success', s ? 'อัปเดตตารางแล้ว' : 'เพิ่มตารางสอนแล้ว'); await loadData(false);
      } catch (e) { Swal.close(); alertToast('error','บันทึกตารางไม่สำเร็จ',friendlyError(e)); }
    };
  }

  async function cancelSchedule(id) {
    const r = await Swal.fire({ title:'ยกเลิกนัดเรียน?', text:'นักเรียนจะเห็นสถานะ “ยกเลิก” ในตารางเรียน', icon:'warning', showCancelButton:true, confirmButtonText:'ยกเลิกนัด', cancelButtonText:'กลับ', confirmButtonColor:'#e11d48' });
    if (!r.isConfirmed) return;
    try { loading('กำลังยกเลิก...'); await rpc('os_v19_schedule_cancel',{p_schedule_id:id}); Swal.close(); alertToast('success','ยกเลิกตารางแล้ว'); await loadData(false); } catch(e) { Swal.close(); alertToast('error','ยกเลิกไม่สำเร็จ',friendlyError(e)); }
  }

  async function deleteSchedule(id) {
    const r = await Swal.fire({ title:'ลบตารางนี้ถาวร?', text:'ใช้สำหรับรายการที่ยกเลิกและยังไม่มีบันทึกการสอนเท่านั้น', icon:'warning', showCancelButton:true, confirmButtonText:'ลบ', cancelButtonText:'ไม่ลบ', confirmButtonColor:'#e11d48' });
    if (!r.isConfirmed) return;
    try { loading('กำลังลบ...'); await rpc('os_v19_schedule_delete',{p_schedule_id:id}); Swal.close(); alertToast('success','ลบตารางแล้ว'); await loadData(false); } catch(e) { Swal.close(); alertToast('error','ลบไม่สำเร็จ',friendlyError(e)); }
  }

  async function startScheduledLesson(id) {
    try { loading('กำลังเริ่มคาบตามตาราง...'); await rpc('os_v19_start_scheduled_lesson',{p_schedule_id:id}); Swal.close(); alertToast('success','เริ่มจับเวลาแล้ว'); state.section='today'; await loadData(false); } catch(e) { Swal.close(); alertToast('error','เริ่มคาบไม่สำเร็จ',friendlyError(e)); }
  }

  function calculatedManualHours(startValue, endValue, status = 'present', deduct = true) {
    if (!deduct || ['leave','absent'].includes(status)) return 0;
    const a = new Date(startValue), b = new Date(endValue);
    if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime()) || b <= a) return 0;
    const minutes = (b - a) / 60000;
    return Math.max(0.25, Math.round((minutes / 60) * 4) / 4);
  }

  function openManualLesson(scheduleId = null) {
    const sch = scheduleId ? scheduleById(scheduleId) : null;
    const allRows = arr(state.data?.enrollments).filter((e) => ['active','paused'].includes(e.status));
    const rows = sch ? allRows.filter((e) => String(e.id) === String(sch.student_course_enrollment_id)) : allRows;
    if (!rows.length) return alertToast('warning','ยังไม่มี Enrollment ที่พร้อมบันทึก');
    const now = new Date();
    const startDefault = sch?.start_at || new Date(now.getTime() - 60 * 60000).toISOString();
    const endDefault = sch?.end_at || now.toISOString();
    showModal('ลงเวลาแบบ Manual', `<form id="manualLessonForm"><div class="form-grid"><label class="aw-label wide">นักเรียน / คอร์ส<select class="aw-input" name="enrollment_id" required>${rows.map((e) => `<option value="${esc(e.id)}">${esc(scopedEnrollmentLabel(e))}</option>`).join('')}</select></label><label class="aw-label">เวลาเข้า<input class="aw-input" type="datetime-local" name="start" required value="${esc(toLocalInput(startDefault))}"></label><label class="aw-label">เวลาออก<input class="aw-input" type="datetime-local" name="end" required value="${esc(toLocalInput(endDefault))}"></label><label class="aw-label">สถานะนักเรียน<select class="aw-input" name="attendance_status"><option value="present">เข้าเรียน</option><option value="late">มาสาย</option><option value="leave">ลา</option><option value="absent">ขาด</option></select></label><label class="aw-label">การตัดชั่วโมง<span class="form-check"><input type="checkbox" name="deduct" checked> ตัดชั่วโมงตามเวลาที่คำนวณ</span></label><label class="aw-label wide">วันนี้สอนอะไร<input class="aw-input" name="title" value="${esc(sch?.title || '')}" placeholder="เช่น Enzyme kinetics / Glycolysis / ตะลุยโจทย์บทที่ 3"></label><label class="aw-label wide">รายละเอียด / การบ้าน / หมายเหตุ<textarea class="aw-textarea" name="note" rows="4" placeholder="สรุปเนื้อหาที่สอน การบ้าน สิ่งที่ต้องทบทวน หรือเหตุผลการลา">${esc(sch?.note || '')}</textarea></label><div class="wide manual-preview"><div><small>ระบบคำนวณและปัดเป็นช่วงละ 15 นาที</small><div style="font-size:9px;color:#64748b;margin-top:4px">สถานะลา/ขาดจะไม่ตัดชั่วโมงโดยอัตโนมัติ</div></div><b id="manualHoursPreview">0.00 ชม.</b></div></div></form>`, `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="saveManualLesson"><i class="fa-solid fa-clock-rotate-left"></i> บันทึกและตัดชั่วโมง</button>`);
    const form = $('manualLessonForm');
    const updatePreview = () => {
      const fd = new FormData(form);
      const hours = calculatedManualHours(fd.get('start'),fd.get('end'),String(fd.get('attendance_status')),form.elements.deduct.checked);
      $('manualHoursPreview').textContent = `${hours.toFixed(2)} ชม.`;
    };
    ['start','end','attendance_status','deduct'].forEach((name) => form.elements[name]?.addEventListener('change', updatePreview));
    form.elements.start?.addEventListener('input',updatePreview); form.elements.end?.addEventListener('input',updatePreview); updatePreview();
    $('saveManualLesson').onclick = async () => {
      const fd = new FormData(form);
      const start = fd.get('start') ? new Date(fd.get('start')).toISOString() : null;
      const end = fd.get('end') ? new Date(fd.get('end')).toISOString() : null;
      if (!start || !end || new Date(end) <= new Date(start)) return alertToast('warning','เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม');
      try {
        loading('กำลังบันทึกเวลาและคำนวณชั่วโมง...');
        const r = await rpc('os_v19_manual_lesson',{ p_student_course_enrollment_id:fd.get('enrollment_id'), p_schedule_id:sch?.id || null, p_start_at:start, p_end_at:end, p_title:String(fd.get('title') || '').trim() || null, p_note:String(fd.get('note') || '').trim() || null, p_attendance_status:String(fd.get('attendance_status') || 'present'), p_deduct_hours:form.elements.deduct.checked });
        Swal.close(); closeModal(); alertToast('success','บันทึกการสอนแล้ว',`คำนวณ ${num(r?.duration_hours).toFixed(2)} ชม. · ตัด ${num(r?.deducted_hours).toFixed(2)} ชม.`); await loadData(false);
      } catch(e) { Swal.close(); alertToast('error','บันทึก Manual ไม่สำเร็จ',friendlyError(e)); }
    };
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
      overview: overviewHtml, today: todayHtml, schedule: scheduleHtml, students: studentsHtml, courses: coursesHtml,
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
    $('newScheduleBtn')?.addEventListener('click', () => openScheduleModal());
    $('todayNewScheduleBtn')?.addEventListener('click', () => openScheduleModal());
    $('manualLessonBtn')?.addEventListener('click', () => openManualLesson());
    $$('[data-open-schedule-page]').forEach((b) => b.onclick = () => { state.section='schedule'; render(); });
    $$('[data-start-schedule]').forEach((b) => b.onclick = () => startScheduledLesson(b.dataset.startSchedule));
    $$('[data-manual-schedule]').forEach((b) => b.onclick = () => openManualLesson(b.dataset.manualSchedule));
    $$('[data-edit-schedule]').forEach((b) => b.onclick = () => openScheduleModal(b.dataset.editSchedule));
    $$('[data-cancel-schedule]').forEach((b) => b.onclick = () => cancelSchedule(b.dataset.cancelSchedule));
    $$('[data-delete-schedule]').forEach((b) => b.onclick = () => deleteSchedule(b.dataset.deleteSchedule));
    $$('[data-finish-session]').forEach((b) => b.onclick = () => finishLesson(b.dataset.finishSession));
    $$('[data-edit-session]').forEach((b) => b.onclick = () => openEditLesson(b.dataset.editSession));
  }

  function openStartLesson() {
    const rows = arr(state.data?.enrollments).filter((e) => ['active', 'paused'].includes(e.status));
    if (!rows.length) return alertToast('warning', 'ยังไม่มี Enrollment ที่พร้อมสอน');
    showModal('เริ่มสอนรายบุคคล', `<form id="startLessonForm"><div class="form-grid"><label class="aw-label wide">นักเรียน / คอร์ส<select class="aw-input" name="enrollment_id" required>${rows.map((e) => `<option value="${esc(e.id)}">${esc(scopedEnrollmentLabel(e))}</option>`).join('')}</select></label><label class="aw-label wide">วันนี้สอนอะไร<input class="aw-input" name="title" placeholder="เช่น Cell biology · ครั้งที่ 1"></label><label class="aw-label wide">รายละเอียด / การบ้าน / หมายเหตุ<textarea class="aw-textarea" name="note" rows="3" placeholder="เป้าหมายหรือเนื้อหาที่จะสอน"></textarea></label></div></form>`, `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="confirmStartLesson"><i class="fa-solid fa-play"></i> เริ่มจับเวลา</button>`);
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
    showModal('แก้ไขบันทึกการสอน', `<form id="editLessonForm"><div class="form-grid"><label class="aw-label wide">วันนี้สอนอะไร<input class="aw-input" name="title" value="${esc(s.title || '')}"></label><label class="aw-label">เวลาเริ่ม<input class="aw-input" type="datetime-local" name="start" value="${esc(toLocalInput(s.actual_start_at))}"></label><label class="aw-label">เวลาสิ้นสุด<input class="aw-input" type="datetime-local" name="end" value="${esc(toLocalInput(s.actual_end_at))}"></label><label class="aw-label">สถานะเข้าเรียน<select class="aw-input" name="attendance_status">${[['present','เข้าเรียน'],['late','สาย'],['leave','ลา'],['absent','ขาด']].map(([v,l]) => `<option value="${v}" ${String(s.attendance_status || 'present') === v ? 'selected' : ''}>${l}</option>`).join('')}</select></label><label class="aw-label">ชั่วโมงที่ตัด<input class="aw-input" type="number" min="0" step="0.25" name="deducted_hours" value="${num(s.deducted_hours).toFixed(2)}"></label><label class="aw-label wide">รายละเอียด / การบ้าน / หมายเหตุ<textarea class="aw-textarea" name="note" rows="4">${esc(s.attendance_note || s.note || '')}</textarea></label></div></form>`, `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="saveLessonEdit"><i class="fa-solid fa-floppy-disk"></i> บันทึกการแก้ไข</button>`);
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
      try { state.data.schedules = await rpc('tutor_os_schedule_v19'); } catch (scheduleError) { console.warn('Schedule V19 unavailable:', scheduleError); state.data.schedules = []; }
      showApp();
      setConnection(true);
      if (state.data?.needs_tutor_link && !state.data?.is_admin) state.section = 'overview';
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
          try { state.data.schedules = await rpc('tutor_os_schedule_v19'); } catch (_) { state.data.schedules = []; }
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
    ['os_student_course_enrollments', 'os_attendance_sessions', 'os_student_attendance', 'os_hour_ledger', 'os_hour_pools', 'os_student_groups', 'os_teaching_schedule'].forEach((table) => {
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
