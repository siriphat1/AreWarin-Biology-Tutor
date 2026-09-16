/* =========================================================
   AreWarin Public Catalog - Course Category Add-on
   ใช้ category ของ "คอร์ส" จริง แทนการเหมารวมจาก tutor.categories
========================================================= */
(() => {
  'use strict';

  let relationReady = false;
  let relationLoading = null;

  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
  const jsq = (v) => String(v ?? '').replace(/\\/g,'\\\\').replace(/'/g,"\\'").replace(/\r?\n/g,' ');

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
      if (!window.__awCourseCategoryPublicClient) {
        window.__awCourseCategoryPublicClient = window.supabase.createClient(
          cfg.SUPABASE_URL,
          cfg.SUPABASE_ANON_KEY
        );
      }
      return window.__awCourseCategoryPublicClient;
    }
    return null;
  }

  function courseMatchesCategory(c, categoryId) {
    if (!categoryId) return true;
    return Array.isArray(c?.categoryIds) &&
      c.categoryIds.map(String).includes(String(categoryId));
  }

  async function hydrateRelations() {
    if (relationLoading) return relationLoading;
    relationLoading = (async () => {
      const client = db();
      if (!client) return false;

      const {data,error} = await client
        .from('course_categories')
        .select('course_id,category_id');

      if (error) {
        console.warn('[Course Categories] fallback to legacy tutor categories:', error.message);
        relationReady = false;
        return false;
      }

      const map = new Map();
      (data || []).forEach(row => {
        const k = String(row.course_id);
        if (!map.has(k)) map.set(k, []);
        map.get(k).push(String(row.category_id));
      });

      try {
        Object.values(coursesByTutor || {}).forEach(list => {
          (list || []).forEach(c => {
            c.categoryIds = map.get(String(c.id)) || [];
          });
        });
        relationReady = true;
      } catch (e) {
        console.warn('[Course Categories] catalog not ready yet:', e);
        relationReady = false;
      }
      return relationReady;
    })();

    const ok = await relationLoading;
    relationLoading = null;
    return ok;
  }

  const legacyRenderCategories = window.renderCategories;
  const legacyRenderTutors = window.renderTutors;
  const legacyRenderCourseCartList = window.renderCourseCartList;

  window.renderCategories = function() {
    if (!relationReady) {
      if (typeof legacyRenderCategories === 'function') return legacyRenderCategories();
      return;
    }

    const container = document.getElementById('categoryGrid');
    if(!container) return;

    const filteredCategories = (categories || []).filter(cat => {
      if (cat.active === false) return false;
      return Object.values(coursesByTutor || {}).some(list =>
        (list || []).some(c => courseMatchesCategory(c, cat.id))
      );
    });

    if(!filteredCategories.length) {
      container.innerHTML = '<div class="onb3-empty"><i class="fas fa-box-open mr-1"></i> ยังไม่พบหมวดวิชาที่เปิดสอนในขณะนี้</div>';
      return;
    }

    container.innerHTML = filteredCategories.map(cat => {
      const tutorKeys = [];
      let courseCount = 0;

      Object.entries(coursesByTutor || {}).forEach(([key,list]) => {
        const matched = (list || []).filter(c => courseMatchesCategory(c, cat.id));
        if (matched.length) {
          courseCount += matched.length;
          const profile = tutorProfiles?.[key];
          if (profile && (typeof isTutorOpen !== 'function' || isTutorOpen(profile))) tutorKeys.push(key);
        }
      });

      return '<div onclick="selectCategory(\'' + jsq(cat.id) + '\')" class="onb3-cat-card theme-' + esc(cat.theme || cat.id) + ' ' + esc(cat.id) + '" role="button" tabindex="0">' +
        '<span class="onb3-cat-glow"></span>' +
        '<div class="onb3-cat-top">' +
          '<div class="onb3-cat-icon"><i class="' + esc(cat.icon || 'fas fa-book-open') + '"></i></div>' +
          '<span class="onb3-cat-count"><i class="fas fa-circle-check mr-1"></i> เปิดสอน</span>' +
        '</div>' +
        '<div class="onb3-cat-name">' + esc(cat.name || cat.id) + '</div>' +
        '<div class="onb3-cat-en">' + esc(cat.desc || '') + '</div>' +
        '<div class="onb3-cat-meta">' +
          '<span class="onb3-cat-pill"><i class="fas fa-user-graduate"></i> ' + new Set(tutorKeys).size + ' ติวเตอร์</span>' +
          '<span class="onb3-cat-pill"><i class="fas fa-book-open"></i> ' + courseCount + ' คอร์ส</span>' +
        '</div>' +
        '<span class="onb3-cat-arrow"><i class="fas fa-arrow-right"></i></span>' +
      '</div>';
    }).join('');
  };

  window.renderTutors = function() {
    if (!relationReady) {
      if (typeof legacyRenderTutors === 'function') return legacyRenderTutors();
      return;
    }

    const container = document.getElementById('tutorGridContainer');
    if(!container) return;

    const filteredTutors = Object.entries(tutorProfiles || {}).filter(([key, profile]) => {
      const hasCourse = (coursesByTutor?.[key] || []).some(c =>
        courseMatchesCategory(c, selectedCategory)
      );
      const levelMatch = selectedLevel === 'all' || (profile.levels || []).includes(selectedLevel);
      return hasCourse && levelMatch;
    });

    const countEl = document.getElementById('tutorResultCount');
    if (countEl) countEl.textContent = filteredTutors.length + ' คน';

    if (!filteredTutors.length) {
      container.innerHTML = '<div class="tv4-empty"><div class="tv4-empty-icon"><i class="fas fa-user-slash"></i></div><strong>ยังไม่พบติวเตอร์ในหมวด/ระดับนี้</strong><span>ลองเปลี่ยนระดับชั้น หรือกลับไปเลือกหมวดวิชาอื่น</span></div>';
      return;
    }

    container.innerHTML = filteredTutors.map(([key,t]) => {
      const levelLabels = typeof getTutorLevelLabels === 'function' ? getTutorLevelLabels(t) : [];
      const levelTags = levelLabels.slice(0,3).map(l =>
        '<span class="tv4-tag"><i class="' + esc(l.icon) + '"></i>' + esc(l.name) + '</span>'
      ).join('');

      const courseCount = (coursesByTutor?.[key] || []).filter(c =>
        courseMatchesCategory(c, selectedCategory)
      ).length;

      const open = typeof isTutorOpen === 'function' ? isTutorOpen(t) : t.active !== false;
      const status = open
        ? '<span class="tv4-status">เปิดรับสมัคร</span>'
        : '<span class="tv4-status closed">ปิดรับชั่วคราว</span>';

      const edu = t.edu && t.edu.length ? t.edu[0] : 'ดูรายละเอียดประวัติและความเชี่ยวชาญเพิ่มเติม';
      const selectButton = open
        ? '<button type="button" onclick="selectTutor(\'' + jsq(key) + '\')" class="tv4-select-btn"><i class="fas fa-arrow-right"></i> เลือกติวเตอร์</button>'
        : '<button type="button" class="tv4-select-btn" disabled><i class="fas fa-lock"></i> ยังไม่เปิดรับ</button>';

      return '<article class="tv4-card">' +
        '<div class="tv4-card-media">' + status +
          '<img src="' + esc(t.img || '') + '" alt="' + esc(t.name || key) + '" loading="lazy">' +
          '<span class="tv4-course-count"><i class="fas fa-book-open"></i>' + courseCount + ' คอร์ส</span>' +
        '</div>' +
        '<div class="tv4-card-body">' +
          '<div class="tv4-name-row"><div class="min-w-0"><h3 class="tv4-name">' + esc(t.name || key) + '</h3><p class="tv4-real-name">' + esc(t.realName || '') + '</p></div></div>' +
          '<p class="tv4-role">' + esc(t.role || 'ติวเตอร์') + '</p>' +
          '<div class="tv4-tags">' + levelTags + '</div>' +
          '<div class="tv4-edu-preview"><i class="fas fa-graduation-cap"></i><span>' + esc(edu) + '</span></div>' +
          '<div class="tv4-actions"><button type="button" onclick="showTutorProfile(\'' + jsq(key) + '\')" class="tv4-profile-btn"><i class="fas fa-user"></i> โปรไฟล์</button>' + selectButton + '</div>' +
        '</div></article>';
    }).join('');
  };

  window.renderCourseCartList = function() {
    if (!relationReady) {
      if (typeof legacyRenderCourseCartList === 'function') return legacyRenderCourseCartList();
      return;
    }

    const container = document.getElementById('cartCourseListContainer');
    if(!container) return;

    const allCourses = coursesByTutor?.[selectedTutor] || [];
    const filteredCourses = allCourses.filter(function(c) {
      if (!courseMatchesCategory(c, selectedCategory)) return false;
      const typeOk = courseCatalogFilter === 'all' || c.type === courseCatalogFilter;
      if (!typeOk) return false;
      if (!courseCatalogSearch) return true;
      const haystack = [c.name,c.detail,c.fullDesc,c.target,c.instructor,selectedTutor].join(' ').toLowerCase();
      return haystack.indexOf(courseCatalogSearch) !== -1;
    });

    const contentCourses = filteredCourses.filter(c => c.type !== 'exam');
    const examCourses = filteredCourses.filter(c => c.type === 'exam');

    const count = document.getElementById('courseResultCount');
    if (count) count.textContent = filteredCourses.length + ' คอร์ส';

    const renderCard = (c) => {
      const index = allCourses.indexOf(c);
      const isUni = c.isUni ? 'true' : 'false';
      const inCart = courseCart.some(item => item.course === c.name && item.tutor === selectedTutor);
      const checkedStr = inCart ? 'checked' : '';
      const inputId = 'course_cb_' + index;

      let badgeHtml = '';
      if(c.badge === 'new') badgeHtml = '<span class="cv3-badge new"><i class="fas fa-bolt"></i> NEW</span>';
      else if(c.badge === 'recommend') badgeHtml = '<span class="cv3-badge recommend"><i class="fas fa-thumbs-up"></i> แนะนำ</span>';
      else if(c.badge === 'star') badgeHtml = '<span class="cv3-badge star"><i class="fas fa-star"></i> แนะนำ</span>';

      const logoStyle = typeof isLogoStyleCourseImage === 'function' && isLogoStyleCourseImage(c.img);
      const imageStyle = logoStyle ? 'object-fit:contain;padding:14px;background:#fff;' : 'object-fit:cover;padding:0;';
      const target = c.target || (c.isUni ? 'มหาวิทยาลัย' : 'นักเรียนทั่วไป');
      const tutorText = c.instructor || selectedTutor;

      return '<label class="cv3-course-card cursor-pointer group">' +
        '<input id="' + inputId + '" type="checkbox" name="courseCartCheckbox" value="' + esc(c.name) + '" data-is-uni="' + isUni + '" class="sr-only" ' + checkedStr + ' onchange="toggleCourseInCart(\'' + jsq(c.name) + '\', ' + isUni + ', this)">' +
        '<div>' + badgeHtml + '<span class="cv3-check"><i class="fas fa-check text-[10px]"></i></span>' +
        '<div class="cv3-media"><img src="' + esc(c.img || '') + '" alt="' + esc(c.name) + '" loading="lazy" style="' + imageStyle + '"></div>' +
        '<div class="cv3-body"><div><h3 class="cv3-title">' + esc(c.name) + '</h3><p class="cv3-desc">' + esc(c.detail || '') + '</p></div>' +
        '<div class="cv3-meta"><span class="cv3-pill"><i class="fas fa-graduation-cap"></i>' + esc(target) + '</span><span class="cv3-pill"><i class="fas fa-user-tie"></i>' + esc(tutorText) + '</span></div>' +
        '<div class="cv3-actions"><button type="button" onclick="event.preventDefault();event.stopPropagation();showCourseDetails(\'' + jsq(selectedTutor) + '\',' + index + ')" class="cv3-detail-btn"><i class="fas fa-circle-info"></i> รายละเอียด</button>' +
        '<div class="cv3-select-visual"><i class="fas ' + (inCart ? 'fa-check' : 'fa-plus') + '"></i> ' + (inCart ? 'เลือกแล้ว' : 'เลือกคอร์ส') + '</div></div>' +
        '</div></div></label>';
    };

    let htmlContent = '';
    if (contentCourses.length) {
      htmlContent += '<div class="cv3-section-title"><strong><i class="fas fa-book-open text-sky-500 mr-1.5"></i>เนื้อหาเข้มข้น (INTENSIVE)</strong><span>' + contentCourses.length + ' คอร์ส</span></div>';
      htmlContent += contentCourses.map(renderCard).join('');
    }
    if (examCourses.length) {
      htmlContent += '<div class="cv3-section-title mt-2"><strong><i class="fas fa-pen-ruler text-orange-400 mr-1.5"></i>ตะลุยโจทย์ / ติวข้อสอบ</strong><span>' + examCourses.length + ' คอร์ส</span></div>';
      htmlContent += examCourses.map(renderCard).join('');
    }
    if (!filteredCourses.length) {
      htmlContent = '<div class="col-span-full py-10 text-center bg-white border border-dashed border-slate-200 rounded-[1.5rem]"><div class="w-12 h-12 rounded-2xl bg-slate-50 text-slate-300 grid place-items-center mx-auto mb-3 text-lg"><i class="fas fa-search"></i></div><p class="font-bold text-slate-600 text-sm">ไม่พบคอร์สในหมวดนี้</p><p class="text-[10px] text-slate-400 mt-1">ลองเปลี่ยนติวเตอร์ หมวด หรือประเภทคอร์ส</p></div>';
    }
    container.innerHTML = htmlContent;
  };

  async function bootRelations() {
    // รอ remote catalog โหลดเสร็จก่อน
    for (let i=0; i<40; i++) {
      try {
        if (typeof coursesByTutor !== 'undefined' && coursesByTutor && Object.keys(coursesByTutor).length) break;
      } catch (_) {}
      await new Promise(r => setTimeout(r, 150));
    }

    const ok = await hydrateRelations();
    if (ok) {
      try {
        // ถ้าอยู่หน้าเลือกหมวดอยู่แล้ว ให้ refresh ทันที
        if (document.getElementById('categoryGrid')) window.renderCategories();
      } catch (_) {}
    }
  }

  if (document.readyState === 'loading') {
    window.addEventListener('load', bootRelations);
  } else {
    bootRelations();
  }

  window.AWCourseCategoryPublic = {
    reload: async () => {
      relationReady = false;
      await hydrateRelations();
      window.renderCategories?.();
    },
    isReady: () => relationReady
  };
})();
