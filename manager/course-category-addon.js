/* =========================================================
   AreWarin Manager - Course Category Add-on
   Drop-in add-on: ไม่ต้องแก้ manager/app.js เดิม
========================================================= */
(() => {
  'use strict';

  const STATE = {
    categories: [],
    selected: new Set(),
    loadedCourseId: '',
    syncing: false,
    initialized: false
  };

  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));

  function db() {
    try {
      if (typeof sb !== 'undefined' && sb && typeof sb.from === 'function') return sb;
    } catch (_) {}
    if (window.AreWarinAPI?.sb?.from) return window.AreWarinAPI.sb;
    if (window.awSupabase?.from) return window.awSupabase;
    if (window.supabaseClient?.from) return window.supabaseClient;
    if (window.sb?.from) return window.sb;

    const cfg = window.AREWARIN_CONFIG || {};
    if (window.supabase?.createClient && cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY) {
      if (!window.__awCourseCategoryClient) {
        window.__awCourseCategoryClient = window.supabase.createClient(
          cfg.SUPABASE_URL,
          cfg.SUPABASE_ANON_KEY,
          { auth: { persistSession: true, autoRefreshToken: true } }
        );
      }
      return window.__awCourseCategoryClient;
    }
    return null;
  }

  function toast(message, type='success') {
    if (window.AWAlert?.toast) {
      window.AWAlert.toast(message, type);
      return;
    }
    if (window.Swal?.fire) {
      Swal.fire({
        toast:true, position:'top-end', timer:2200, showConfirmButton:false,
        icon:type === 'error' ? 'error' : type === 'warning' ? 'warning' : 'success',
        title:message
      });
      return;
    }
    console[type === 'error' ? 'error' : 'log']('[Course Category]', message);
  }

  function injectStyles() {
    if ($('awCourseCategoryStyles')) return;
    const style = document.createElement('style');
    style.id = 'awCourseCategoryStyles';
    style.textContent = `
      .awcc-panel{border:1px solid #e2e8f0;background:linear-gradient(180deg,#f8fafc,#fff);border-radius:16px;padding:14px}
      .awcc-head{display:flex;justify-content:space-between;gap:10px;align-items:flex-start;margin-bottom:10px}
      .awcc-title{font-size:11px;font-weight:700;color:#334155}
      .awcc-note{font-size:9px;color:#94a3b8;margin-top:3px;line-height:1.45}
      .awcc-create{border:1px solid #bae6fd;background:#fff;color:#0284c7;border-radius:10px;padding:7px 10px;font-size:9px;font-weight:700;white-space:nowrap}
      .awcc-create:hover{background:#f0f9ff}
      .awcc-search{width:100%;border:1px solid #e2e8f0;background:#fff;border-radius:11px;padding:9px 10px;font-size:10px;outline:none;margin-bottom:9px}
      .awcc-search:focus{border-color:#7dd3fc;box-shadow:0 0 0 3px rgba(14,165,233,.08)}
      .awcc-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:7px;max-height:230px;overflow:auto}
      .awcc-item{display:flex;align-items:center;gap:8px;border:1px solid #e2e8f0;border-radius:12px;background:#fff;padding:9px;cursor:pointer;transition:.15s}
      .awcc-item:hover{border-color:#bae6fd}
      .awcc-item.is-selected{border-color:#7dd3fc;background:#f0f9ff}
      .awcc-icon{width:28px;height:28px;border-radius:9px;display:grid;place-items:center;background:#f8fafc;color:#0ea5e9;flex:0 0 auto}
      .awcc-name{font-size:9.5px;font-weight:700;color:#334155;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .awcc-en{font-size:8px;color:#94a3b8;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
      .awcc-status{font-size:7px;padding:2px 5px;border-radius:999px;background:#f1f5f9;color:#64748b;margin-left:auto}
      .awcc-selected{display:flex;flex-wrap:wrap;gap:5px;margin-top:9px}
      .awcc-chip{font-size:8px;border:1px solid #bae6fd;color:#0369a1;background:#f0f9ff;border-radius:999px;padding:4px 7px;font-weight:700}
      .awcc-empty{font-size:9px;color:#f43f5e;background:#fff1f2;border:1px solid #ffe4e6;border-radius:999px;padding:4px 8px}
      .awcc-modal-backdrop{position:fixed;inset:0;background:rgba(15,23,42,.38);backdrop-filter:blur(3px);z-index:99999;display:grid;place-items:center;padding:18px}
      .awcc-modal{width:min(520px,100%);max-height:90vh;overflow:auto;background:#fff;border-radius:22px;box-shadow:0 24px 80px rgba(15,23,42,.22);padding:20px}
      .awcc-modal h3{margin:0;font-size:16px;color:#0f172a}
      .awcc-field{display:block;margin-top:12px}
      .awcc-field span{display:block;font-size:9px;font-weight:700;color:#64748b;margin-bottom:5px}
      .awcc-field input,.awcc-field select{width:100%;border:1px solid #e2e8f0;border-radius:11px;padding:10px;font-size:11px;outline:none;background:#fff}
      .awcc-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:18px}
      .awcc-btn{border:1px solid #e2e8f0;background:#fff;border-radius:11px;padding:9px 13px;font-size:10px;font-weight:700;color:#475569}
      .awcc-btn.primary{background:#0f172a;color:#fff;border-color:#0f172a}
      @media(max-width:640px){.awcc-grid{grid-template-columns:1fr}.awcc-head{flex-direction:column}.awcc-create{width:100%}}
    `;
    document.head.appendChild(style);
  }

  function injectUI() {
    const form = $('courseForm');
    if (!form || $('courseCategoryPanel')) return false;

    const panel = document.createElement('div');
    panel.id = 'courseCategoryPanel';
    panel.className = 'awcc-panel';
    panel.innerHTML = `
      <div class="awcc-head">
        <div>
          <div class="awcc-title"><i class="fas fa-folder-tree" style="color:#0ea5e9;margin-right:5px"></i>หมวดที่เปิดสอน <span style="color:#f43f5e">*</span></div>
          <div class="awcc-note">เลือกหมวดเดิมได้หลายหมวด หรือสร้างหมวดใหม่ได้จากตรงนี้ คอร์สที่เปิดใช้งานต้องมีอย่างน้อย 1 หมวด</div>
        </div>
        <button id="courseCategoryCreate" type="button" class="awcc-create"><i class="fas fa-plus" style="margin-right:4px"></i>สร้างหมวดใหม่</button>
      </div>
      <input id="courseCategorySearch" class="awcc-search" placeholder="ค้นหาหมวด เช่น ชีววิทยา / Chemistry">
      <div id="courseCategoryGrid" class="awcc-grid"><div class="awcc-note">กำลังโหลดหมวด...</div></div>
      <div id="courseCategorySelected" class="awcc-selected"></div>
    `;

    const tutorSelect = $('courseTutor');
    if (tutorSelect) tutorSelect.insertAdjacentElement('afterend', panel);
    else form.insertBefore(panel, form.children[1] || null);

    $('courseCategorySearch')?.addEventListener('input', render);
    $('courseCategoryCreate')?.addEventListener('click', openCreateModal);
    return true;
  }

  async function loadCategories() {
    const client = db();
    if (!client) {
      const grid = $('courseCategoryGrid');
      if (grid) grid.innerHTML = '<div class="awcc-note" style="color:#ef4444">ไม่พบ Supabase client</div>';
      return;
    }
    const {data,error} = await client
      .from('subject_categories')
      .select('id,name_th,name_en,icon_class,theme,sort_order,active')
      .order('sort_order')
      .order('name_th');
    if (error) {
      console.error(error);
      const grid = $('courseCategoryGrid');
      if (grid) grid.innerHTML = '<div class="awcc-note" style="color:#ef4444">โหลดหมวดไม่สำเร็จ: '+esc(error.message)+'</div>';
      return;
    }
    STATE.categories = data || [];
    render();
  }

  function render() {
    const grid = $('courseCategoryGrid');
    const selectedBox = $('courseCategorySelected');
    if (!grid || !selectedBox) return;

    const q = ($('courseCategorySearch')?.value || '').trim().toLowerCase();
    const rows = STATE.categories.filter(c => {
      if (!q) return true;
      return [c.id,c.name_th,c.name_en].filter(Boolean).join(' ').toLowerCase().includes(q);
    });

    if (!rows.length) {
      grid.innerHTML = '<div class="awcc-note">ไม่พบหมวดที่ค้นหา</div>';
    } else {
      grid.innerHTML = rows.map(c => {
        const id = String(c.id);
        const selected = STATE.selected.has(id);
        return `
          <label class="awcc-item ${selected ? 'is-selected':''}">
            <input type="checkbox" data-awcc-id="${esc(id)}" ${selected?'checked':''}>
            <span class="awcc-icon"><i class="${esc(c.icon_class || 'fas fa-book-open')}"></i></span>
            <span style="min-width:0">
              <span class="awcc-name">${esc(c.name_th || c.id)}</span>
              <span class="awcc-en">${esc(c.name_en || c.id)}</span>
            </span>
            ${c.active === false ? '<span class="awcc-status">ปิด</span>' : ''}
          </label>`;
      }).join('');

      grid.querySelectorAll('[data-awcc-id]').forEach(input => {
        input.addEventListener('change', () => {
          const id = String(input.dataset.awccId);
          input.checked ? STATE.selected.add(id) : STATE.selected.delete(id);
          render();
        });
      });
    }

    const selectedRows = STATE.categories.filter(c => STATE.selected.has(String(c.id)));
    selectedBox.innerHTML = selectedRows.length
      ? selectedRows.map(c => `<span class="awcc-chip"><i class="${esc(c.icon_class || 'fas fa-book-open')}" style="margin-right:4px"></i>${esc(c.name_th || c.id)}</span>`).join('')
      : '<span class="awcc-empty"><i class="fas fa-circle-exclamation" style="margin-right:4px"></i>ยังไม่ได้เลือกหมวด</span>';
  }

  function closeModal() {
    $('awCourseCategoryModal')?.remove();
  }

  function slugify(v) {
    return String(v || '')
      .toLowerCase()
      .trim()
      .replace(/[^a-z0-9]+/g,'-')
      .replace(/^-+|-+$/g,'')
      .slice(0,50);
  }

  function openCreateModal() {
    closeModal();
    const el = document.createElement('div');
    el.id = 'awCourseCategoryModal';
    el.className = 'awcc-modal-backdrop';
    el.innerHTML = `
      <div class="awcc-modal" role="dialog" aria-modal="true">
        <h3>สร้างหมวดใหม่</h3>
        <div class="awcc-note" style="margin-top:5px">หมวดใหม่จะถูกเพิ่มใน subject_categories และเลือกให้คอร์สนี้อัตโนมัติ</div>

        <label class="awcc-field"><span>ชื่อภาษาไทย *</span><input id="awccNewTh" placeholder="เช่น กายวิภาคศาสตร์"></label>
        <label class="awcc-field"><span>ชื่อภาษาอังกฤษ</span><input id="awccNewEn" placeholder="Anatomy"></label>
        <label class="awcc-field"><span>Slug / รหัสหมวด</span><input id="awccNewId" placeholder="anatomy"></label>
        <label class="awcc-field"><span>Font Awesome icon</span><input id="awccNewIcon" value="fas fa-book-open"></label>
        <label class="awcc-field"><span>Theme</span>
          <select id="awccNewTheme">
            <option value="sky">Sky</option><option value="indigo">Indigo</option><option value="violet">Violet</option>
            <option value="emerald">Emerald</option><option value="teal">Teal</option><option value="amber">Amber</option>
            <option value="rose">Rose</option><option value="slate">Slate</option>
          </select>
        </label>
        <label class="awcc-field"><span>ลำดับ</span><input id="awccNewSort" type="number" min="0" value="100"></label>

        <div class="awcc-actions">
          <button id="awccCancel" type="button" class="awcc-btn">ยกเลิก</button>
          <button id="awccSaveNew" type="button" class="awcc-btn primary"><i class="fas fa-plus" style="margin-right:5px"></i>สร้างและเลือก</button>
        </div>
      </div>`;
    document.body.appendChild(el);

    $('awccNewEn')?.addEventListener('input', e => {
      const id = $('awccNewId');
      if (id && !id.dataset.manual) id.value = slugify(e.target.value);
    });
    $('awccNewId')?.addEventListener('input', e => e.target.dataset.manual = '1');
    $('awccCancel')?.addEventListener('click', closeModal);
    el.addEventListener('click', e => { if (e.target === el) closeModal(); });
    $('awccSaveNew')?.addEventListener('click', createCategory);
    $('awccNewTh')?.focus();
  }

  async function createCategory() {
    const client = db();
    if (!client) return toast('ไม่พบ Supabase client','error');

    const nameTh = ($('awccNewTh')?.value || '').trim();
    const nameEn = ($('awccNewEn')?.value || '').trim();
    let id = slugify(($('awccNewId')?.value || '').trim());
    if (!id) id = slugify(nameEn);
    if (!id) id = 'subject-' + Date.now().toString(36);

    if (!nameTh) return toast('กรุณากรอกชื่อหมวดภาษาไทย','warning');
    if (!/^[a-z0-9_-]+$/.test(id)) return toast('Slug ใช้ได้เฉพาะ a-z, 0-9, _ และ -','warning');

    const btn = $('awccSaveNew');
    if (btn) { btn.disabled = true; btn.textContent = 'กำลังสร้าง...'; }

    const payload = {
      id,
      name_th: nameTh,
      name_en: nameEn || null,
      icon_class: ($('awccNewIcon')?.value || 'fas fa-book-open').trim(),
      theme: $('awccNewTheme')?.value || 'sky',
      sort_order: Number($('awccNewSort')?.value || 100),
      active: true
    };

    const {data,error} = await client
      .from('subject_categories')
      .insert(payload)
      .select()
      .single();

    if (error) {
      if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-plus" style="margin-right:5px"></i>สร้างและเลือก'; }
      return toast(error.code === '23505' ? 'Slug นี้มีอยู่แล้ว' : error.message,'error');
    }

    await loadCategories();
    STATE.selected.add(String(data.id));
    render();
    closeModal();
    toast('สร้างหมวดและเลือกให้คอร์สนี้แล้ว');
  }

  async function loadForCourse(courseId) {
    const client = db();
    if (!client || !courseId) return;
    const {data,error} = await client
      .from('course_categories')
      .select('category_id')
      .eq('course_id', courseId);

    if (error) {
      console.warn('[Course Category] load relation failed:', error);
      return;
    }

    STATE.selected = new Set((data || []).map(x => String(x.category_id)));
    STATE.loadedCourseId = String(courseId);
    render();
  }

  async function saveForCourse(courseId, ids) {
    const client = db();
    if (!client) throw new Error('ไม่พบ Supabase client');

    // Prefer RPC; fallback direct delete+insert
    const rpc = await client.rpc('manager_set_course_categories', {
      p_course_id: courseId,
      p_category_ids: ids
    });
    if (!rpc.error) return;

    const del = await client.from('course_categories').delete().eq('course_id', courseId);
    if (del.error) throw del.error;

    if (ids.length) {
      const ins = await client.from('course_categories').insert(
        ids.map(category_id => ({course_id: courseId, category_id}))
      );
      if (ins.error) throw ins.error;
    }
  }

  async function findSavedCourse(snapshot) {
    const client = db();
    if (!client) return null;
    if (snapshot.courseId) return snapshot.courseId;
    if (!snapshot.tutorId || !snapshot.name) return null;

    for (let i=0; i<40; i++) {
      const {data,error} = await client
        .from('courses')
        .select('id')
        .eq('tutor_id', snapshot.tutorId)
        .eq('name', snapshot.name)
        .limit(1)
        .maybeSingle();

      if (!error && data?.id) return data.id;
      await new Promise(r => setTimeout(r, 250));
    }
    return null;
  }

  async function syncAfterNativeSave(snapshot) {
    if (STATE.syncing) return;
    STATE.syncing = true;
    try {
      const courseId = await findSavedCourse(snapshot);
      if (!courseId) throw new Error('หา Course ID หลังบันทึกไม่พบ');
      await saveForCourse(courseId, snapshot.categoryIds);
      STATE.loadedCourseId = String(courseId);
      toast(`บันทึกหมวดคอร์สแล้ว ${snapshot.categoryIds.length} หมวด`);
    } catch (e) {
      console.error('[Course Category] sync failed:', e);
      toast('คอร์สบันทึกแล้ว แต่บันทึกหมวดไม่สำเร็จ: ' + (e?.message || e),'error');
    } finally {
      STATE.syncing = false;
    }
  }

  function bindForm() {
    // Capture-phase validation runs before manager/app.js bubble submit handler
    document.addEventListener('submit', (event) => {
      if (event.target?.id !== 'courseForm') return;

      const categoryIds = [...STATE.selected];
      const active = $('courseActive')?.checked !== false;

      if (active && !categoryIds.length) {
        event.preventDefault();
        event.stopImmediatePropagation();
        toast('กรุณาเลือกหมวดอย่างน้อย 1 หมวดก่อนเปิดใช้งานคอร์ส','warning');
        $('courseCategoryPanel')?.scrollIntoView({behavior:'smooth',block:'center'});
        return;
      }

      const snapshot = {
        courseId: ($('courseId')?.value || '').trim(),
        tutorId: ($('courseTutor')?.value || '').trim(),
        name: ($('courseName')?.value || '').trim(),
        categoryIds
      };
      setTimeout(() => syncAfterNativeSave(snapshot), 0);
    }, true);

    $('courseReset')?.addEventListener('click', () => {
      STATE.selected.clear();
      STATE.loadedCourseId = '';
      render();
    });

    // Detect edit mode even if existing app directly assigns input.value
    let lastId = '';
    setInterval(() => {
      const id = ($('courseId')?.value || '').trim();
      if (id === lastId) return;
      lastId = id;
      if (id) {
        loadForCourse(id);
      } else if (!STATE.syncing) {
        STATE.loadedCourseId = '';
        STATE.selected.clear();
        render();
      }
    }, 350);
  }

  async function init() {
    if (STATE.initialized) return;
    if (!$('courseForm')) return;

    STATE.initialized = true;
    injectStyles();
    injectUI();
    bindForm();
    await loadCategories();

    const currentId = ($('courseId')?.value || '').trim();
    if (currentId) await loadForCourse(currentId);
  }

  function boot() {
    let tries = 0;
    const timer = setInterval(() => {
      tries++;
      if ($('courseForm')) {
        clearInterval(timer);
        init();
      } else if (tries > 80) {
        clearInterval(timer);
      }
    }, 100);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  window.AWCourseCategoryManager = {
    reload: loadCategories,
    loadForCourse,
    getSelected: () => [...STATE.selected]
  };
})();
