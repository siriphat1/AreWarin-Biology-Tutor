(() => {
  'use strict';
  console.info('[AreWarin Tutor OS V19.5] Admin + Tutor Identity Link loaded');

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
    scheduleView: localStorage.getItem('aw_tutor_schedule_view') || 'calendar',
    scheduleWeekStart: localStorage.getItem('aw_tutor_schedule_week_start') || '',
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
  function currentTutorId() { return state.data?.tutor?.id || state.data?.identity?.tutor_id || state.data?.profile?.tutor_id || null; }

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
    const admin = isAdmin();

    return `${sectionHeader(
      'STUDENTS',
      'นักเรียน & CRM',
      admin
        ? 'Admin เห็นนักเรียนทั้งหมด · สามารถลบนักเรียนออกจาก Student/Tutor OS ได้'
        : 'แสดงเฉพาะนักเรียนที่ผูกกับคุณผ่าน Enrollment / Course',
      admin
        ? `<div class="aw-tag"><i class="fa-solid fa-shield-halved"></i> ลบได้เฉพาะ Admin / Manager</div>`
        : ''
    )}
      <section class="aw-card content-card">
        ${rows.length ? `<div class="table-wrap">
          <table class="aw-table">
            <thead>
              <tr>
                <th>Student ID</th>
                <th>นักเรียน</th>
                <th>โรงเรียน</th>
                <th>คอร์สที่กำลังเรียน</th>
                <th>ชั่วโมงคงเหลือ</th>
                ${admin ? '<th style="text-align:right">จัดการ</th>' : ''}
              </tr>
            </thead>
            <tbody>${rows.map((s) => {
              const ens = arr(state.data?.enrollments).filter((e) =>
                String(e.student_id) === String(s.id) &&
                ['active', 'paused'].includes(e.status)
              );
              const remain = ens.reduce(
                (sum, e) => sum + (e.hours_unlimited ? 0 : Math.max(0, num(e.hours_total) - num(e.hours_used))),
                0
              );
              return `<tr>
                <td><span class="mono-small">${esc(s.student_code || s.id)}</span></td>
                <td><b>${esc(fullName(s))}</b><small>${esc(s.phone || '')}</small></td>
                <td>${esc(s.school || '—')}</td>
                <td>${ens.map((e) => `<span class="aw-tag">${esc(courseById(e.course_id)?.title || courseById(e.course_id)?.name || e.course_label || 'คอร์ส')}</span>`).join(' ') || '—'}</td>
                <td>${ens.some((e) => e.hours_unlimited) ? '∞' : `${remain.toFixed(1)} ชม.`}</td>
                ${admin ? `<td>
                  <div class="table-actions">
                    <button
                      class="icon-btn danger aw-student-delete-btn"
                      type="button"
                      data-delete-student="${esc(s.id)}"
                      title="ลบนักเรียนออกจาก Student OS"
                      aria-label="ลบนักเรียน ${esc(fullName(s))}">
                      <i class="fa-solid fa-trash-can"></i>
                    </button>
                  </div>
                </td>` : ''}
              </tr>`;
            }).join('')}</tbody>
          </table>
        </div>` : '<div class="empty-state">ยังไม่มีนักเรียนในสิทธิ์ของบัญชีนี้</div>'}
      </section>`;
  }

  async function deleteStudent(studentId) {
    if (!isAdmin()) {
      return alertToast('error','ไม่มีสิทธิ์ลบนักเรียน','ฟังก์ชันนี้ใช้ได้เฉพาะ Admin / Manager');
    }

    const student = studentById(studentId);
    if (!student) {
      return alertToast('warning','ไม่พบนักเรียน','กรุณารีเฟรชข้อมูลแล้วลองอีกครั้ง');
    }

    try {
      loading('กำลังตรวจสอบข้อมูลที่เกี่ยวข้อง...');

      const preview = await rpc('os_v194_admin_student_delete_preview', {
        p_student_id: studentId
      });

      Swal.close();

      if (!preview?.ok) {
        throw new Error(preview?.message || 'ไม่สามารถตรวจสอบข้อมูลก่อนลบได้');
      }

      const confirmText = String(preview.confirmation || student.student_code || 'DELETE');
      const counts = preview.counts || {};
      const displayName = preview.display_name || fullName(student);
      const activeEnrollments = Number(counts.active_enrollments || 0);
      const schedules = Number(counts.schedules || 0);
      const sessions = Number(counts.sessions || 0);
      const groupLinks = Number(counts.group_links || 0);
      const serviceRecords = Number(counts.service_records || 0);

      const result = await Swal.fire({
        icon:'warning',
        title:'ลบนักเรียนออกจากระบบ?',
        width:560,
        html:`
          <div class="text-left">
            <div style="padding:12px 14px;border:1px solid #fee2e2;background:#fff7f7;border-radius:14px;margin-bottom:12px">
              <div style="font-size:12px;font-weight:800;color:#9f1239">${esc(displayName)}</div>
              <div style="font-size:9px;color:#94a3b8;margin-top:4px">${esc(student.student_code || student.id)}</div>
            </div>

            <div class="aw-delete-preview-grid">
              <div><small>Enrollment ที่ใช้งาน</small><b>${activeEnrollments}</b></div>
              <div><small>ตารางสอน</small><b>${schedules}</b></div>
              <div><small>ประวัติการสอน</small><b>${sessions}</b></div>
              <div><small>กลุ่ม/Locker</small><b>${groupLinks}</b></div>
              <div><small>Student Services</small><b>${serviceRecords}</b></div>
            </div>

            <div style="margin-top:12px;padding:11px 12px;border-radius:12px;background:#fffbeb;border:1px solid #fde68a;color:#92400e;font-size:9px;line-height:1.65">
              <b>ข้อมูลที่จะถูกลบ:</b> Student Profile และข้อมูลใน Student/Tutor OS ที่อ้างถึงนักเรียนคนนี้ตาม Foreign Key ของระบบ<br>
              <b>ข้อมูลที่เก็บไว้:</b> ใบสมัครเรียน/การชำระเงิน/ใบเสร็จในระบบหลักยังคงอยู่เพื่อ Audit
            </div>

            <div style="margin-top:12px;font-size:9px;color:#64748b;line-height:1.6">
              เพื่อป้องกันการกดผิด กรุณาพิมพ์ <b style="color:#be123c">${esc(confirmText)}</b> ในช่องด้านล่าง
            </div>
          </div>`,
        input:'text',
        inputPlaceholder:confirmText,
        inputAttributes:{
          autocapitalize:'off',
          autocomplete:'off',
          spellcheck:'false'
        },
        showCancelButton:true,
        confirmButtonText:'ลบนักเรียนถาวร',
        cancelButtonText:'ยกเลิก',
        confirmButtonColor:'#e11d48',
        reverseButtons:true,
        focusCancel:true,
        preConfirm:(value)=>{
          if(String(value || '').trim() !== confirmText) {
            Swal.showValidationMessage(`กรุณาพิมพ์ ${confirmText} ให้ตรงกัน`);
            return false;
          }
          return String(value || '').trim();
        }
      });

      if (!result.isConfirmed) return;

      loading('กำลังลบนักเรียนและข้อมูลที่เกี่ยวข้อง...');

      const deleted = await rpc('os_v194_admin_delete_student', {
        p_student_id: studentId,
        p_confirm: result.value
      });

      Swal.close();

      if (!deleted?.ok) {
        throw new Error(deleted?.message || 'ลบนักเรียนไม่สำเร็จ');
      }

      await Swal.fire({
        icon:'success',
        title:'ลบนักเรียนเรียบร้อย',
        html:`
          <div style="font-size:10px;color:#64748b;line-height:1.7">
            ลบ <b>${esc(deleted.display_name || displayName)}</b> ออกจาก Student/Tutor OS แล้ว<br>
            ข้อมูลสมัครเรียนและการเงินในระบบหลักยังคงเก็บไว้
          </div>`,
        confirmButtonText:'ตกลง',
        confirmButtonColor:'#0f172a'
      });

      await loadData(false);

    } catch (e) {
      Swal.close();
      console.error('[AreWarin Tutor OS V19.4] delete student failed', e);
      alertToast('error','ลบนักเรียนไม่สำเร็จ',friendlyError(e));
    }
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

  const AW_CAL_START_HOUR = 7;
  const AW_CAL_END_HOUR = 22;
  const AW_CAL_HOUR_PX = 64;

  function awDateKeyAddDays(key, days) {
    const m = String(key || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (!m) return '';
    const d = new Date(Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]) + Number(days || 0)));
    return d.toISOString().slice(0, 10);
  }

  function awMondayKey(value = new Date()) {
    const key = /^\d{4}-\d{2}-\d{2}$/.test(String(value || '')) ? String(value) : bangkokDateKey(value);
    const [y,m,d] = key.split('-').map(Number);
    const utc = new Date(Date.UTC(y,m-1,d));
    const weekday = utc.getUTCDay(); // 0 Sun ... 6 Sat
    const back = weekday === 0 ? 6 : weekday - 1;
    return awDateKeyAddDays(key, -back);
  }

  function awScheduleWeekStart() {
    const candidate = String(state.scheduleWeekStart || '');
    if (/^\d{4}-\d{2}-\d{2}$/.test(candidate)) return awMondayKey(candidate);
    return awMondayKey(new Date());
  }

  function awSetScheduleWeek(key) {
    state.scheduleWeekStart = awMondayKey(key);
    localStorage.setItem('aw_tutor_schedule_week_start', state.scheduleWeekStart);
  }

  function awBangkokTimeParts(v) {
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return {hour:0,minute:0};
    const parts = new Intl.DateTimeFormat('en-GB', {
      timeZone:'Asia/Bangkok', hour:'2-digit', minute:'2-digit', hourCycle:'h23'
    }).formatToParts(d);
    const out = Object.fromEntries(parts.map(p => [p.type,p.value]));
    return { hour:Number(out.hour || 0), minute:Number(out.minute || 0) };
  }

  function awDateLabel(key, weekday = false) {
    if (!key) return '';
    const d = new Date(`${key}T12:00:00+07:00`);
    return new Intl.DateTimeFormat('th-TH', {
      timeZone:'Asia/Bangkok',
      ...(weekday ? {weekday:'short'} : {}),
      day:'numeric',
      month:'short'
    }).format(d);
  }

  function awWeekRangeLabel(startKey) {
    const endKey = awDateKeyAddDays(startKey, 6);
    const a = new Date(`${startKey}T12:00:00+07:00`);
    const b = new Date(`${endKey}T12:00:00+07:00`);
    const sameMonth = a.getMonth() === b.getMonth() && a.getFullYear() === b.getFullYear();
    if (sameMonth) {
      const dayA = new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric'}).format(a);
      const end = new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric',month:'short',year:'numeric'}).format(b);
      return `${dayA}–${end}`;
    }
    const left = new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric',month:'short'}).format(a);
    const right = new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric',month:'short',year:'numeric'}).format(b);
    return `${left} – ${right}`;
  }

  function awMinutesToHHMM(total) {
    const n = Math.max(0, Math.floor(Number(total || 0)));
    const h = Math.floor(n / 60) % 24;
    const m = n % 60;
    return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}`;
  }

  function awLocalDateTimeFromKeyMinutes(key, mins) {
    return `${key}T${awMinutesToHHMM(mins)}`;
  }

  function awDurationText(minutes) {
    const n = Math.max(0, Math.round(Number(minutes || 0)));
    const h = Math.floor(n / 60);
    const m = n % 60;
    if (h && m) return `${h} ชม. ${m} นาที`;
    if (h) return `${h} ชม.`;
    return `${m} นาที`;
  }

  function awAddMinutesLocalInput(value, minutes) {
    if (!value) return '';
    const d = new Date(value);
    if (Number.isNaN(d.getTime())) return '';
    d.setMinutes(d.getMinutes() + Number(minutes || 0));
    const local = new Date(d.getTime() - d.getTimezoneOffset() * 60000);
    return local.toISOString().slice(0,16);
  }

  function awScheduleEventMeta(x) {
    const e = enrollmentById(x.student_course_enrollment_id);
    const st = studentById(x.student_id || e?.student_id);
    const c = courseById(x.course_id || e?.course_id);
    return { e, st, c };
  }

  function awCalendarDayLayout(dayRows) {
    const dayStart = AW_CAL_START_HOUR * 60;
    const dayEnd = AW_CAL_END_HOUR * 60;
    const normalized = dayRows.map(x => {
      const s = awBangkokTimeParts(x.start_at);
      const e = awBangkokTimeParts(x.end_at);
      let start = s.hour * 60 + s.minute;
      let end = e.hour * 60 + e.minute;
      if (bangkokDateKey(x.end_at) !== bangkokDateKey(x.start_at)) end = dayEnd;
      start = Math.max(dayStart, Math.min(dayEnd, start));
      end = Math.max(start + 15, Math.min(dayEnd, end));
      return {x,start,end,col:0,cols:1};
    }).filter(v => v.end > dayStart && v.start < dayEnd)
      .sort((a,b) => a.start-b.start || a.end-b.end);

    const groups = [];
    let current = [];
    let maxEnd = -1;
    normalized.forEach(item => {
      if (current.length && item.start >= maxEnd) {
        groups.push(current);
        current = [];
        maxEnd = -1;
      }
      current.push(item);
      maxEnd = Math.max(maxEnd, item.end);
    });
    if (current.length) groups.push(current);

    groups.forEach(group => {
      const colEnds = [];
      group.forEach(item => {
        let col = colEnds.findIndex(end => end <= item.start);
        if (col < 0) {
          col = colEnds.length;
          colEnds.push(item.end);
        } else {
          colEnds[col] = item.end;
        }
        item.col = col;
      });
      const cols = Math.max(1, colEnds.length);
      group.forEach(item => item.cols = cols);
    });

    return normalized;
  }

  function scheduleRowsHtml(rows, compact = false) {
    if (!rows.length) return '<div class="empty-state compact">ยังไม่มีตารางสอน</div>';
    return `<div class="schedule-list-v19">${rows.map((x) => {
      const {e,st,c} = awScheduleEventMeta(x);
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

  function awCalendarHtml(rows) {
    const startKey = awScheduleWeekStart();
    const todayKey = bangkokDateKey(new Date());
    const dayKeys = Array.from({length:7},(_,i)=>awDateKeyAddDays(startKey,i));
    const height = (AW_CAL_END_HOUR - AW_CAL_START_HOUR) * AW_CAL_HOUR_PX;
    const hours = Array.from({length:AW_CAL_END_HOUR-AW_CAL_START_HOUR+1},(_,i)=>AW_CAL_START_HOUR+i);

    const dayHeaders = dayKeys.map(key => {
      const d = new Date(`${key}T12:00:00+07:00`);
      const week = new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',weekday:'short'}).format(d);
      const day = new Intl.DateTimeFormat('th-TH',{timeZone:'Asia/Bangkok',day:'numeric'}).format(d);
      return `<div class="aw-cal-day-head ${key===todayKey?'today':''}"><span>${esc(week)}</span><b>${esc(day)}</b></div>`;
    }).join('');

    const dayColumns = dayKeys.map(key => {
      const dayRows = rows.filter(x => bangkokDateKey(x.start_at)===key && x.status!=='cancelled');
      const layout = awCalendarDayLayout(dayRows);
      const events = layout.map(({x,start,end,col,cols}) => {
        const {st,c} = awScheduleEventMeta(x);
        const top = ((start - AW_CAL_START_HOUR*60)/60) * AW_CAL_HOUR_PX;
        const h = Math.max(28, ((end-start)/60) * AW_CAL_HOUR_PX);
        const width = 100/cols;
        const left = col*width;
        const status = String(x.status || 'scheduled');
        const title = x.title || c?.title || c?.name || 'คาบเรียน';
        return `<button type="button" class="aw-cal-event ${esc(status)}" data-calendar-event="${esc(x.id)}" style="top:${top}px;height:${h}px;left:calc(${left}% + 2px);width:calc(${width}% - 4px)" title="${esc(fullName(st))} · ${esc(title)}">
          <b>${esc(fmtClock(x.start_at))}–${esc(fmtClock(x.end_at))}</b>
          <span>${esc(fullName(st))}</span>
          <small>${esc(title)}</small>
        </button>`;
      }).join('');

      return `<div class="aw-cal-day ${key===todayKey?'today':''}" data-calendar-day="${esc(key)}" style="height:${height}px">${events}</div>`;
    }).join('');

    const hourLabels = hours.map((h,i) => {
      const top = i * AW_CAL_HOUR_PX;
      return `<span style="top:${top}px">${String(h).padStart(2,'0')}:00</span>`;
    }).join('');

    return `<section class="aw-card aw-calendar-card">
      <div class="aw-calendar-toolbar">
        <div>
          <div class="page-kicker">WEEK CALENDAR</div>
          <h2>${esc(awWeekRangeLabel(startKey))}</h2>
          <p>คลิกช่องว่างในตารางเพื่อสร้างนัดใหม่ · คลิกคาบเพื่อแก้ไข</p>
        </div>
        <div class="aw-calendar-nav">
          <button class="aw-btn small" type="button" data-cal-prev title="สัปดาห์ก่อน"><i class="fa-solid fa-chevron-left"></i></button>
          <button class="aw-btn small" type="button" data-cal-today>วันนี้</button>
          <button class="aw-btn small" type="button" data-cal-next title="สัปดาห์ถัดไป"><i class="fa-solid fa-chevron-right"></i></button>
        </div>
      </div>
      <div class="aw-calendar-scroll">
        <div class="aw-calendar-week" style="--aw-hour-px:${AW_CAL_HOUR_PX}px">
          <div class="aw-cal-corner">GMT+7</div>
          ${dayHeaders}
          <div class="aw-cal-time-axis" style="height:${height}px">${hourLabels}</div>
          <div class="aw-cal-days">${dayColumns}</div>
        </div>
      </div>
      <div class="aw-calendar-legend">
        <span><i class="scheduled"></i> นัดสอน</span>
        <span><i class="in_progress"></i> กำลังสอน</span>
        <span><i class="completed"></i> สอนแล้ว</span>
        <span class="muted"><i class="fa-regular fa-hand-pointer"></i> กดช่องเวลาเพื่อเพิ่มนัด</span>
      </div>
    </section>`;
  }

  function scheduleHtml() {
    const rows = arr(state.data?.schedules).slice().sort((a,b) => new Date(a.start_at) - new Date(b.start_at));
    const now = new Date();
    const todayKey = bangkokDateKey(now);
    const today = rows.filter((x) => bangkokDateKey(x.start_at) === todayKey && x.status !== 'cancelled');
    const upcoming = rows.filter((x) => ['scheduled','rescheduled','in_progress'].includes(x.status) && new Date(x.end_at) >= now);
    const completed = rows.filter((x) => x.status === 'completed');
    const calendarActive = state.scheduleView !== 'list';

    return `${sectionHeader('TEACHING SCHEDULE', 'ตารางสอน', 'มุมมองปฏิทินรายสัปดาห์แบบ Google Calendar พร้อม Quick Duration เพื่อจัดตารางได้เร็วขึ้น', `<div class="toolbar"><button class="aw-btn sky" id="manualLessonBtn"><i class="fa-regular fa-clock"></i> ลงเวลา Manual</button><button class="aw-btn primary" id="newScheduleBtn"><i class="fa-solid fa-calendar-plus"></i> เพิ่มตารางสอน</button></div>`)}
      <div class="schedule-hero"><section class="aw-card schedule-summary"><h3>ตารางที่ควบคุมโดย Tutor OS</h3><p>เมื่อจัดตารางตรงนี้ Student Portal จะใช้เวลาจาก Tutor OS เป็นข้อมูลหลัก</p><div class="schedule-stat-grid"><div class="schedule-stat"><small>วันนี้</small><b>${today.length}</b></div><div class="schedule-stat"><small>กำลังจะถึง</small><b>${upcoming.length}</b></div><div class="schedule-stat"><small>สอนแล้ว</small><b>${completed.length}</b></div></div></section><section class="aw-card schedule-summary"><h3>กรอกเวลาได้เร็วขึ้น</h3><p>เลือกเวลาเริ่ม แล้วกด <b>1 ชม.</b> / <b>1.5 ชม.</b> / <b>2 ชม.</b> ระบบจะคำนวณเวลาจบให้อัตโนมัติ</p><div class="section-note" style="margin-top:12px">คลิกพื้นที่ว่างในปฏิทินเพื่อเปิดฟอร์มพร้อมวันและเวลาเริ่มที่เลือกไว้ทันที</div></section></div>

      <div class="aw-schedule-view-tabs">
        <button type="button" class="${calendarActive?'active':''}" data-schedule-view="calendar"><i class="fa-regular fa-calendar"></i> ปฏิทินสัปดาห์</button>
        <button type="button" class="${!calendarActive?'active':''}" data-schedule-view="list"><i class="fa-solid fa-list"></i> รายการ</button>
      </div>

      ${calendarActive
        ? awCalendarHtml(rows)
        : `<section class="aw-card content-card"><div class="card-head"><div><h2>รายการตารางสอน</h2><p>${rows.length} รายการ</p></div></div>${scheduleRowsHtml(rows)}</section>`
      }`;
  }

  function awBindCalendarControls() {
    $$('[data-schedule-view]').forEach(btn => {
      btn.onclick = () => {
        state.scheduleView = btn.dataset.scheduleView === 'list' ? 'list' : 'calendar';
        localStorage.setItem('aw_tutor_schedule_view', state.scheduleView);
        render();
      };
    });

    $('[data-cal-prev]')?.addEventListener('click', () => {
      awSetScheduleWeek(awDateKeyAddDays(awScheduleWeekStart(), -7));
      render();
    });
    $('[data-cal-next]')?.addEventListener('click', () => {
      awSetScheduleWeek(awDateKeyAddDays(awScheduleWeekStart(), 7));
      render();
    });
    $('[data-cal-today]')?.addEventListener('click', () => {
      awSetScheduleWeek(awMondayKey(new Date()));
      render();
    });

    $$('[data-calendar-event]').forEach(btn => {
      btn.onclick = (ev) => {
        ev.stopPropagation();
        openScheduleModal(btn.dataset.calendarEvent);
      };
    });

    $$('[data-calendar-day]').forEach(day => {
      day.onclick = (ev) => {
        if (ev.target.closest('[data-calendar-event]')) return;
        const rect = day.getBoundingClientRect();
        const y = Math.max(0, Math.min(rect.height, ev.clientY - rect.top));
        const minutesFromStart = Math.round(((y / rect.height) * ((AW_CAL_END_HOUR-AW_CAL_START_HOUR)*60)) / 15) * 15;
        const totalMinutes = Math.min((AW_CAL_END_HOUR-AW_CAL_START_HOUR)*60 - 15, Math.max(0, minutesFromStart));
        const startMinutes = AW_CAL_START_HOUR*60 + totalMinutes;
        openScheduleModal(null, { start: awLocalDateTimeFromKeyMinutes(day.dataset.calendarDay, startMinutes) });
      };
    });
  }

  function awBindQuickDuration(form, isEdit = false) {
    if (!form) return;
    const startInput = form.elements.start;
    const endInput = form.elements.end;
    const summary = $('awScheduleDurationSummary');
    const buttons = $$('[data-duration-hours]', form);
    if (!startInput || !endInput) return;

    let activeMinutes = null;

    function actualDuration() {
      if (!startInput.value || !endInput.value) return 0;
      const a = new Date(startInput.value);
      const b = new Date(endInput.value);
      if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime())) return 0;
      return Math.max(0, Math.round((b-a)/60000));
    }

    function refresh() {
      const mins = actualDuration();
      buttons.forEach(btn => {
        const target = Number(btn.dataset.durationHours) * 60;
        btn.classList.toggle('active', Math.abs(target-mins) <= 1);
      });
      activeMinutes = buttons.some(btn => btn.classList.contains('active')) ? mins : activeMinutes;
      if (summary) {
        if (startInput.value && endInput.value && mins > 0) {
          summary.innerHTML = `<b>${esc(startInput.value.slice(11,16))} → ${esc(endInput.value.slice(11,16))}</b><span>${esc(awDurationText(mins))}</span>`;
        } else {
          summary.innerHTML = '<b>เลือกเวลาเริ่ม</b><span>จากนั้นเลือกระยะเวลาคาบ</span>';
        }
      }
    }

    function applyMinutes(mins) {
      if (!startInput.value) {
        startInput.focus();
        return alertToast('warning','กรุณาเลือกเวลาเริ่มก่อน');
      }
      endInput.value = awAddMinutesLocalInput(startInput.value, mins);
      activeMinutes = mins;
      localStorage.setItem('aw_tutor_default_duration_minutes', String(mins));
      refresh();
    }

    buttons.forEach(btn => {
      btn.onclick = () => applyMinutes(Math.round(Number(btn.dataset.durationHours)*60));
    });

    startInput.addEventListener('input', () => {
      const mins = activeMinutes || Number(localStorage.getItem('aw_tutor_default_duration_minutes') || 60);
      if (mins > 0) applyMinutes(mins);
      else refresh();
    });
    startInput.addEventListener('change', refresh);
    endInput.addEventListener('input', () => {
      activeMinutes = actualDuration();
      refresh();
    });
    endInput.addEventListener('change', refresh);

    const initial = actualDuration();
    if (initial > 0) activeMinutes = initial;
    refresh();
  }

  function openScheduleModal(scheduleId = null, preset = null) {
    const s = scheduleId ? scheduleById(scheduleId) : null;
    const rows = arr(state.data?.enrollments).filter((e) => ['active','paused'].includes(e.status));
    if (!rows.length) return alertToast('warning','ยังไม่มี Enrollment ที่พร้อมจัดตาราง');

    const savedDuration = Math.max(30, Math.min(360, Number(localStorage.getItem('aw_tutor_default_duration_minutes') || 60)));
    const defaultStartInput = s?.start_at
      ? toLocalInput(s.start_at)
      : (preset?.start || toLocalInput(new Date(Date.now() + 3600000)));

    const defaultEndInput = s?.end_at
      ? toLocalInput(s.end_at)
      : awAddMinutesLocalInput(defaultStartInput, savedDuration);

    const durationChoices = [
      [0.5,'30 นาที'],
      [1,'1 ชม.'],
      [1.5,'1.5 ชม.'],
      [2,'2 ชม.'],
      [2.5,'2.5 ชม.'],
      [3,'3 ชม.']
    ];

    showModal(
      s ? 'แก้ไขตารางสอน' : 'เพิ่มตารางสอน',
      `<form id="scheduleForm">
        <div class="form-grid">
          <label class="aw-label wide">นักเรียน / คอร์ส
            <select class="aw-input" name="enrollment_id" required>${rows.map((e) => `<option value="${esc(e.id)}" ${String(s?.student_course_enrollment_id || '') === String(e.id) ? 'selected' : ''}>${esc(scopedEnrollmentLabel(e))}</option>`).join('')}</select>
          </label>

          <label class="aw-label">เริ่มเรียน
            <input class="aw-input" type="datetime-local" name="start" required value="${esc(defaultStartInput)}">
          </label>
          <label class="aw-label">เลิกเรียน
            <input class="aw-input" type="datetime-local" name="end" required value="${esc(defaultEndInput)}">
          </label>

          <div class="aw-label wide">
            <span>ระยะเวลาคาบ · Quick Duration</span>
            <div class="aw-duration-quick">${durationChoices.map(([h,label]) => `<button type="button" data-duration-hours="${h}">${esc(label)}</button>`).join('')}</div>
            <div id="awScheduleDurationSummary" class="aw-duration-summary"></div>
          </div>

          <label class="aw-label wide">ชื่อคาบ / หัวข้อ
            <input class="aw-input" name="title" value="${esc(s?.title || '')}" placeholder="เช่น Biochemistry · Enzyme kinetics">
          </label>

          <label class="aw-label">รูปแบบ
            <select class="aw-input" name="mode">
              <option value="online" ${s?.mode !== 'onsite' ? 'selected' : ''}>Online</option>
              <option value="onsite" ${s?.mode === 'onsite' ? 'selected' : ''}>On-site</option>
            </select>
          </label>

          <label class="aw-label">สถานที่ / ลิงก์ห้องเรียน
            <input class="aw-input" name="location" value="${esc(s?.location || '')}" placeholder="Zoom / ห้องเรียน / สถานที่">
          </label>

          ${!s ? `<label class="aw-label">ทำซ้ำรายสัปดาห์
            <select class="aw-input" name="repeat_weeks">${[1,2,4,6,8,10,12,16].map((n) => `<option value="${n}">${n === 1 ? 'ครั้งเดียว' : n + ' สัปดาห์'}</option>`).join('')}</select>
          </label>` : '<div></div>'}

          <label class="aw-label wide">หมายเหตุสำหรับผู้สอน
            <textarea class="aw-textarea" name="note" rows="3" placeholder="สิ่งที่ต้องเตรียม / หมายเหตุภายใน">${esc(s?.note || '')}</textarea>
          </label>
        </div>
      </form>`,
      `<button class="aw-btn" data-modal-close>ยกเลิก</button><button class="aw-btn primary" id="saveScheduleBtn"><i class="fa-solid fa-floppy-disk"></i> ${s ? 'บันทึกตาราง' : 'สร้างตาราง'}</button>`
    );

    const form = $('scheduleForm');
    awBindQuickDuration(form, !!s);

    $('saveScheduleBtn').onclick = async () => {
      const fd = new FormData(form);
      const start = fd.get('start') ? new Date(fd.get('start')).toISOString() : null;
      const end = fd.get('end') ? new Date(fd.get('end')).toISOString() : null;
      if (!start || !end || new Date(end) <= new Date(start)) return alertToast('warning','เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม');

      try {
        loading(s ? 'กำลังแก้ตาราง...' : 'กำลังสร้างตาราง...');
        if (s) {
          await rpc('os_v19_schedule_update', {
            p_schedule_id:s.id,
            p_student_course_enrollment_id:fd.get('enrollment_id'),
            p_start_at:start,
            p_end_at:end,
            p_title:String(fd.get('title') || '').trim() || null,
            p_mode:fd.get('mode'),
            p_location:String(fd.get('location') || '').trim() || null,
            p_note:String(fd.get('note') || '').trim() || null
          });
        } else {
          await rpc('os_v19_schedule_create', {
            p_student_course_enrollment_id:fd.get('enrollment_id'),
            p_start_at:start,
            p_end_at:end,
            p_title:String(fd.get('title') || '').trim() || null,
            p_mode:fd.get('mode'),
            p_location:String(fd.get('location') || '').trim() || null,
            p_note:String(fd.get('note') || '').trim() || null,
            p_repeat_weeks:num(fd.get('repeat_weeks') || 1)
          });
        }
        Swal.close();
        closeModal();
        alertToast('success', s ? 'อัปเดตตารางแล้ว' : 'เพิ่มตารางสอนแล้ว');
        await loadData(false);
      } catch (e) {
        Swal.close();
        alertToast('error','บันทึกตารางไม่สำเร็จ',friendlyError(e));
      }
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
    const myTutorId = currentTutorId();

    return `${sectionHeader(
      'TEAM',
      'ทีมติวเตอร์',
      myTutorId
        ? 'บัญชี Admin นี้เชื่อมกับตัวตนติวเตอร์แล้ว และยังคงสิทธิ์ Admin ครบ'
        : 'เลือกติวเตอร์ที่เป็นตัวคุณ แล้วกด “เชื่อมบัญชีนี้”'
    )}
      ${myTutorId ? `<div class="section-note" style="margin-bottom:12px">
        <b><i class="fa-solid fa-circle-check" style="color:#10b981"></i> บัญชีนี้เชื่อม Tutor Identity แล้ว</b><br>
        คุณยังคงเป็น Admin แต่ระบบงานสอนจะรู้ด้วยว่าคุณคือติวเตอร์คนใด
      </div>` : `<div class="section-note" style="margin-bottom:12px">
        <b>ทำไมต้องเชื่อม?</b><br>
        บัญชี Login คือ Supabase Auth ส่วน “พี่อาร์ / พี่เอ็มมี่ / พี่ต้อง” คือ Tutor Profile คนละชั้นกัน
        การเชื่อมจะทำให้ระบบรู้ว่า Admin คนนี้สอนในชื่อ Tutor คนใด โดยไม่ลดสิทธิ์ Admin
      </div>`}

      <div class="grid-3">${team.map((t) => {
        const linkedToMe = myTutorId && String(myTutorId) === String(t.id);
        const occupied = t.identity_status === 'active' && !linkedToMe;

        return `<article class="aw-card course-card aw-team-link-card ${linkedToMe ? 'linked-me' : ''}">
          <div class="course-card-icon"><i class="fa-solid fa-chalkboard-user"></i></div>
          <h3>${esc(t.display_name || 'Tutor')}</h3>
          <p>${esc(t.role_text || t.primary_subject || '')}</p>

          <div class="aw-team-link-status">
            ${linkedToMe
              ? '<span class="aw-tag aw-tag-linked"><i class="fa-solid fa-link"></i> บัญชีนี้</span>'
              : occupied
                ? '<span class="aw-tag"><i class="fa-solid fa-user-check"></i> เปิดบัญชีแล้ว</span>'
                : '<span class="aw-tag"><i class="fa-solid fa-link-slash"></i> ยังไม่เชื่อมบัญชี</span>'
            }
          </div>

          <div class="module-actions" style="margin-top:12px">
            ${linkedToMe
              ? `<button type="button" class="aw-btn small danger" data-unlink-my-tutor="${esc(t.id)}">
                   <i class="fa-solid fa-link-slash"></i> ยกเลิกการเชื่อม
                 </button>`
              : occupied
                ? `<button type="button" class="aw-btn small" disabled>
                     <i class="fa-solid fa-lock"></i> เชื่อมกับบัญชีอื่นแล้ว
                   </button>`
                : `<button type="button" class="aw-btn small primary" data-link-my-tutor="${esc(t.id)}">
                     <i class="fa-solid fa-link"></i> เชื่อมบัญชีนี้
                   </button>`
            }
          </div>
        </article>`;
      }).join('') || '<div class="aw-card empty-state">ยังไม่มีติวเตอร์</div>'}</div>`;
  }

  async function linkMyAdminAccountToTutor(tutorId) {
    if (!isAdmin()) return alertToast('error','ไม่มีสิทธิ์','ใช้ได้เฉพาะ Admin / Manager');

    const tutor = tutorById(tutorId) || arr(state.data?.team).find(x => String(x.id) === String(tutorId));
    if (!tutor) return alertToast('warning','ไม่พบติวเตอร์');

    const existingTutor = currentTutorId()
      ? (tutorById(currentTutorId()) || arr(state.data?.team).find(x => String(x.id) === String(currentTutorId())))
      : null;

    const confirm = await Swal.fire({
      icon:'question',
      title:'เชื่อมบัญชี Admin กับติวเตอร์?',
      html:`
        <div style="text-align:left;font-size:10px;line-height:1.8;color:#64748b">
          <div style="padding:12px 14px;border:1px solid #dbeafe;background:#f0f9ff;border-radius:14px;margin-bottom:12px">
            บัญชีที่กำลังใช้: <b>${esc(state.user?.email || state.data?.identity?.email || 'Admin account')}</b><br>
            เชื่อมเป็นติวเตอร์: <b style="color:#0369a1">${esc(tutor.display_name || 'Tutor')}</b>
          </div>
          ${existingTutor && String(existingTutor.id) !== String(tutorId)
            ? `<div style="padding:10px 12px;border-radius:12px;background:#fffbeb;border:1px solid #fde68a;color:#92400e;margin-bottom:10px">
                 ปัจจุบันบัญชีนี้เชื่อมกับ <b>${esc(existingTutor.display_name || 'Tutor')}</b> อยู่ ระบบจะย้ายการเชื่อมมายัง ${esc(tutor.display_name || 'Tutor')}
               </div>`
            : ''}
          <b>สิทธิ์ Admin จะไม่หาย</b> ระบบเพียงเพิ่ม Tutor Identity ให้บัญชีนี้ เพื่อให้รู้ว่าคุณสอนในชื่อใด
        </div>`,
      showCancelButton:true,
      confirmButtonText:`เชื่อมเป็น ${tutor.display_name || 'Tutor'}`,
      cancelButtonText:'ยกเลิก',
      confirmButtonColor:'#0f172a',
      reverseButtons:true
    });

    if (!confirm.isConfirmed) return;

    try {
      loading('กำลังเชื่อมบัญชี...');
      const result = await rpc('os_v195_admin_link_my_tutor', { p_tutor_id:tutorId });
      Swal.close();

      if (!result?.ok) throw new Error(result?.message || 'เชื่อมบัญชีไม่สำเร็จ');

      await Swal.fire({
        icon:'success',
        title:'เชื่อมบัญชีเรียบร้อย',
        html:`<div style="font-size:10px;line-height:1.8;color:#64748b">
          บัญชีนี้ยังเป็น <b>Admin</b> และตอนนี้เชื่อมกับติวเตอร์ <b>${esc(result.tutor_name || tutor.display_name || '')}</b> แล้ว
        </div>`,
        confirmButtonText:'ตกลง',
        confirmButtonColor:'#0f172a'
      });

      await loadData(false);

    } catch(e) {
      Swal.close();
      console.error('[AreWarin Tutor OS V19.5] link tutor failed', e);
      alertToast('error','เชื่อมบัญชีไม่สำเร็จ',friendlyError(e));
    }
  }

  async function unlinkMyAdminTutor(tutorId) {
    if (!isAdmin()) return alertToast('error','ไม่มีสิทธิ์');

    const tutor = tutorById(tutorId) || arr(state.data?.team).find(x => String(x.id) === String(tutorId));
    const confirm = await Swal.fire({
      icon:'warning',
      title:'ยกเลิกการเชื่อม Tutor Identity?',
      html:`<div style="font-size:10px;line-height:1.8;color:#64748b">
        บัญชีจะยังคงเป็น <b>Admin</b> ตามเดิม แต่จะไม่ถูกระบุว่าเป็น <b>${esc(tutor?.display_name || 'Tutor')}</b> อีก
      </div>`,
      showCancelButton:true,
      confirmButtonText:'ยกเลิกการเชื่อม',
      cancelButtonText:'กลับ',
      confirmButtonColor:'#e11d48',
      reverseButtons:true
    });

    if (!confirm.isConfirmed) return;

    try {
      loading('กำลังยกเลิกการเชื่อม...');
      const result = await rpc('os_v195_admin_unlink_my_tutor', {});
      Swal.close();

      if (!result?.ok) throw new Error(result?.message || 'ยกเลิกการเชื่อมไม่สำเร็จ');

      alertToast('success','ยกเลิกการเชื่อมแล้ว','บัญชียังคงสิทธิ์ Admin');
      await loadData(false);

    } catch(e) {
      Swal.close();
      console.error('[AreWarin Tutor OS V19.5] unlink tutor failed', e);
      alertToast('error','ยกเลิกการเชื่อมไม่สำเร็จ',friendlyError(e));
    }
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
    $$('[data-delete-student]').forEach((b) => b.onclick = () => deleteStudent(b.dataset.deleteStudent));
    $$('[data-link-my-tutor]').forEach((b) => b.onclick = () => linkMyAdminAccountToTutor(b.dataset.linkMyTutor));
    $$('[data-unlink-my-tutor]').forEach((b) => b.onclick = () => unlinkMyAdminTutor(b.dataset.unlinkMyTutor));
    if(state.section === 'schedule') awBindCalendarControls();
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
