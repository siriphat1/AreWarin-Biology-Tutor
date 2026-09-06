(() => {
  'use strict';

  const cfg = window.AREWARIN_CONFIG || {};
  const configured = cfg.SUPABASE_URL && cfg.SUPABASE_ANON_KEY && !String(cfg.SUPABASE_URL).includes('YOUR_PROJECT_REF');
  const sb = configured && window.supabase
    ? window.supabase.createClient(cfg.SUPABASE_URL, cfg.SUPABASE_ANON_KEY, {
        auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
      })
    : null;

  const needClient = () => {
    if (!sb) throw new Error('ยังไม่ได้ตั้งค่า Supabase ใน config.js');
    return sb;
  };
  const cleanPhone = v => String(v || '').replace(/\D/g, '');
  const unwrapSetting = value => value && typeof value === 'object' && Object.prototype.hasOwnProperty.call(value,'value') ? value.value : value;

  async function getPublicCatalog() {
    const db = needClient();
    const [tRes,cRes,pRes,oRes] = await Promise.all([
      db.from('tutors').select('*').eq('active',true).order('sort_order'),
      db.from('courses').select('*').eq('active',true).order('sort_order'),
      db.from('course_prices').select('*').eq('active',true),
      db.from('course_offerings').select('*').eq('enrollment_open',true).eq('status','open')
    ]);
    for (const x of [tRes,cRes,pRes]) if (x.error) throw x.error;
    // V15: course_offerings is the shared publish switch. If V15 SQL has not
    // been installed yet, keep V14 behavior as a safe fallback.
    const offeringRows = oRes.error ? null : (oRes.data || []);
    const openCourseIds = offeringRows ? new Set(offeringRows.map(x => x.course_id)) : null;
    const offeringByCourse = Object.fromEntries((offeringRows || []).map(x => [x.course_id,x]));

    const tutorProfiles = {};
    (tRes.data || []).forEach(t => {
      tutorProfiles[t.display_name] = {
        id: t.id,
        img: t.image_url || '',
        name: t.display_name || '',
        realName: t.full_name || '',
        edu: t.education || [],
        awards: t.awards || [],
        role: t.role_text || '',
        video: t.video_id || '',
        levels: t.levels || [],
        categories: t.categories || [],
        borderColor: t.border_color || 'border-sky-100 hover:border-sky-500',
        active: t.active !== false
      };
    });

    const tutorNameById = Object.fromEntries((tRes.data || []).map(t => [t.id,t.display_name]));
    const coursesByTutor = {};
    (cRes.data || []).forEach(c => {
      if (openCourseIds && !openCourseIds.has(c.id)) return;
      const tutor = tutorNameById[c.tutor_id];
      if (!tutor) return;
      const offering = offeringByCourse[c.id] || null;
      (coursesByTutor[tutor] ||= []).push({
        id: c.id,
        tutorId: c.tutor_id,
        offeringId: offering?.id || null,
        offering: offering,
        name: c.name,
        type: c.course_type || 'content',
        detail: c.short_detail || '',
        img: c.image_url || '',
        fullDesc: c.full_description || '',
        target: c.target_text || '',
        instructor: tutor,
        badge: c.badge || '',
        isUni: !!c.is_university,
        outcomes: c.outcomes || [],
        syllabus: c.syllabus || []
      });
    });

    const prices = { standard:{}, university:{} };
    (pRes.data || []).forEach(p => { prices[p.tier][p.package_code] = Number(p.amount || 0); });
    return { tutorProfiles, coursesByTutor, prices, courseOfferings:offeringRows || [] };
  }

  async function checkDiscountCode(code) {
    const db = needClient();
    const normalized = String(code || '').trim().toUpperCase();
    if (!normalized) return {valid:false,message:'กรุณากรอกโค้ดส่วนลด'};
    const { data, error } = await db.from('promotions').select('*').eq('code',normalized).maybeSingle();
    if (error) throw error;
    if (!data || !data.active) return {valid:false,message:'ไม่พบโค้ดส่วนลดนี้'};
    const now = Date.now();
    if (data.starts_at && now < new Date(data.starts_at).getTime()) return {valid:false,message:'โค้ดนี้ยังไม่ถึงเวลาใช้งาน'};
    if (data.ends_at && now > new Date(data.ends_at).getTime()) return {valid:false,message:'โค้ดนี้หมดอายุแล้ว'};
    return data.discount_type === 'percent'
      ? {valid:true,type:'percent',percent:Number(data.discount_value || 0)}
      : {valid:true,type:'fixed',amount:Number(data.discount_value || 0)};
  }

  async function processApplication(payload) {
    // Public enrollment uses a direct, CORS-simple POST instead of functions.invoke().
    // functions.invoke adds Authorization/apikey/x-client-info headers and therefore forces
    // a browser preflight. GitHub Pages was being blocked when the deployed Edge Function
    // had not yet been redeployed with verify_jwt=false. text/plain is CORS-safelisted and
    // keeps the public form independent from the visitor's Supabase Auth session.
    needClient();
    const endpoint = `${String(cfg.SUPABASE_URL || '').replace(/\/$/,'')}/functions/v1/create-enrollment`;
    let response;
    try {
      response = await fetch(endpoint, {
        method: 'POST',
        mode: 'cors',
        cache: 'no-store',
        headers: {
          'Content-Type': 'text/plain;charset=UTF-8',
          'Accept': 'application/json'
        },
        body: JSON.stringify(payload || {})
      });
    } catch (err) {
      console.error('create-enrollment network error:', err);
      throw new Error('เชื่อมต่อระบบสมัครเรียนไม่ได้ กรุณาตรวจว่า Edge Function create-enrollment ถูก Deploy แบบ --no-verify-jwt แล้ว');
    }

    const raw = await response.text();
    let data = null;
    try { data = raw ? JSON.parse(raw) : null; } catch (_) { data = null; }

    if (!response.ok) {
      if (response.status === 404) {
        throw new Error('ยังไม่พบ Edge Function create-enrollment ใน Supabase Project นี้ กรุณา Deploy ฟังก์ชัน create-enrollment ไปที่ project ref ihmiqtwclnqrezsnswfz ก่อน');
      }
      const rawDetail = data?.message ?? data?.error ?? data ?? raw ?? `HTTP ${response.status}`;
      let detail;
      if (typeof rawDetail === 'string') detail = rawDetail;
      else { try { detail = JSON.stringify(rawDetail); } catch (_) { detail = String(rawDetail); } }
      console.error('create-enrollment rejected request:', { status: response.status, data, raw });
      throw new Error(`ส่งใบสมัครไม่สำเร็จ: ${detail}`);
    }
    if (!data?.success) throw new Error(data?.message || 'ส่งใบสมัครไม่สำเร็จ');
    return data;
  }

  async function submitSpeakerRequest(d) {
    const db = needClient();
    const row = {
      organization: String(d.org || '').trim(),
      coordinator_name: String(d.name || '').trim(),
      phone: String(d.phone || '').trim(),
      email: String(d.email || '').trim() || null,
      subject: String(d.subject || '').trim(),
      tutor_name: String(d.tutor || '').trim() || null,
      topic: String(d.topic || '').trim(),
      event_datetime_text: String(d.datetime || '').trim(),
      location_text: String(d.location || '').trim(),
      audience_text: String(d.audience || '').trim(),
      budget_text: String(d.budget || '').trim() || null,
      wants_quotation: !!d.quotation,
      details: String(d.details || '').trim() || null,
      status: 'pending'
    };
    const { error } = await db.from('speaker_requests').insert(row);
    if (error) throw error;
    return {success:true};
  }

  async function checkApplicationStatus(phone) {
    const db = needClient();
    const { data, error } = await db.rpc('check_application_status',{p_phone:cleanPhone(phone)});
    if (error) throw error;
    return data || {found:false};
  }

  async function lookupExistingStudent(phone) {
    const db = needClient();
    const normalized = cleanPhone(phone);
    if (normalized.length < 9) return {found:false};
    const { data, error } = await db.rpc('lookup_existing_student',{p_phone:normalized});
    if (error) throw error;
    return data || {found:false};
  }

  async function getPolicyPage(pageKey) {
    const db = needClient();
    const key = String(pageKey || '').trim();
    const [pRes,sRes] = await Promise.all([
      db.from('policy_pages').select('*').eq('page_key',key).eq('active',true).maybeSingle(),
      db.from('policy_sections').select('*').eq('page_key',key).eq('active',true).order('sort_order').order('created_at')
    ]);
    if (pRes.error) throw pRes.error;
    if (sRes.error) throw sRes.error;
    return { page:pRes.data || null, sections:sRes.data || [] };
  }

  async function getAppConfig() {
    const db = needClient();
    const { data, error } = await db.from('app_settings').select('key,value');
    if (error) throw error;
    return Object.fromEntries((data || []).map(x => [x.key, unwrapSetting(x.value)]));
  }

  async function saveAppConfig(configData) {
    const db = needClient();
    const rows = Object.entries(configData || {}).map(([key,value]) => ({ key, value, updated_at:new Date().toISOString() }));
    if (!rows.length) return {success:true};
    const { error } = await db.from('app_settings').upsert(rows,{onConflict:'key'});
    if (error) throw error;
    return {success:true};
  }

  async function getScheduleMatrix(tutorNames) {
    const db = needClient();
    const names = [...new Set((tutorNames || []).filter(Boolean))];
    if (!names.length) return {tutors:[],templates:[],rows:[]};
    const { data:tutors, error:tErr } = await db.from('tutors').select('id,display_name').in('display_name',names);
    if (tErr) throw tErr;
    const ids = (tutors || []).map(t => t.id);
    if (!ids.length) return {tutors:[],templates:[],rows:[]};
    const { data:rows, error } = await db.rpc('get_public_schedule',{p_tutor_ids:ids});
    if (error) throw error;
    const templatesMap = new Map();
    (rows || []).forEach(r => templatesMap.set(r.template_id,{id:r.template_id,label:r.label,start_time:r.start_time,end_time:r.end_time}));
    return { tutors:tutors || [], templates:[...templatesMap.values()], rows:rows || [] };
  }

  // Legacy helper retained for any old UI calls. It returns a compact weekly map.
  async function getTutorAvailability(tutorName) {
    const matrix = await getScheduleMatrix([tutorName]);
    const map = {};
    matrix.rows.forEach(r => { map[`${r.weekday}_${r.template_id}`] = r.status === 'available' && Number(r.remaining_seats)>0 ? 'ว่าง' : 'ไม่ว่าง'; });
    return map;
  }

  async function exportCSV(type='all') {
    const db = needClient();
    const session = (await db.auth.getSession()).data.session;
    if (!session) throw new Error('กรุณาเข้าสู่ระบบ Manager');
    const rows = [];
    if (type === 'speaker') {
      const {data,error}=await db.from('speaker_requests').select('*').order('created_at',{ascending:false}); if(error)throw error;
      rows.push(['วันที่','หน่วยงาน','ผู้ประสานงาน','โทร','อีเมล','วิชา','วิทยากร','หัวข้อ','วันเวลา','สถานที่','กลุ่มเป้าหมาย','งบประมาณ','สถานะ']);
      (data||[]).forEach(x=>rows.push([x.created_at,x.organization,x.coordinator_name,x.phone,x.email,x.subject,x.tutor_name,x.topic,x.event_datetime_text,x.location_text,x.audience_text,x.budget_text,x.status]));
    } else {
      const {data,error}=await db.from('enrollments').select('*').order('created_at',{ascending:false}); if(error)throw error;
      rows.push(['วันที่','ประเภท','ชื่อ-นามสกุล','ชื่อเล่น','โทร','Line','Email','ติวเตอร์','คอร์ส','แพ็กเกจ','เวลา','ยอด','สถานะ','เลขใบเสร็จ']);
      (data||[]).filter(x=>type==='all'||(type==='new'&&x.student_type==='new')||(type==='old'&&x.student_type==='old')).forEach(x=>rows.push([x.created_at,x.student_type,x.fullname,x.nickname,x.phone,x.line_id,x.email,x.tutor_text,x.course_text,x.mode_text,x.time_text,x.amount_quoted,x.status,x.receipt_no]));
    }
    const quote = v => { const s=String(v ?? ''); return /[",\n]/.test(s) ? `"${s.replace(/"/g,'""')}"` : s; };
    return '\uFEFF' + rows.map(r=>r.map(quote).join(',')).join('\n');
  }

  function makeRunner(successCb,failureCb) {
    const runner = {
      withSuccessHandler(fn){ return makeRunner(fn,failureCb); },
      withFailureHandler(fn){ return makeRunner(successCb,fn); }
    };
    const methods = { checkDiscountCode, processApplication, submitSpeakerRequest, checkApplicationStatus, lookupExistingStudent, getTutorAvailability, getPolicyPage, getAppConfig, saveAppConfig, exportCSV };
    Object.entries(methods).forEach(([name,fn]) => {
      runner[name] = (...args) => { Promise.resolve().then(()=>fn(...args)).then(v=>successCb?.(v)).catch(err=>failureCb?.(err)); return runner; };
    });
    return runner;
  }

  window.AreWarinAPI = { sb, configured:!!sb, getPublicCatalog, getScheduleMatrix, checkDiscountCode, processApplication, submitSpeakerRequest, checkApplicationStatus, lookupExistingStudent, getPolicyPage, getAppConfig, saveAppConfig, exportCSV };
  if (sb) window.google = { script:{ run:makeRunner(null,null) } };
})();
