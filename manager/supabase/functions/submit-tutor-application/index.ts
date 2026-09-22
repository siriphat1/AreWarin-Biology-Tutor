import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'content-type, accept',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
});

const clean = (v: unknown) => String(v ?? '').trim();
const cleanPhone = (v: unknown) => clean(v).replace(/\D/g, '');
const isEmail = (v: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v);

const DEFAULT_AGREEMENT_VERSION = 'AW-TUTOR-AGREEMENT-2026-09-21-v1';

function rateForTier(tier: string, settings: any) {
  if (tier === 'bachelor_studying' || tier === 'bachelor_graduate') {
    const r = Number(settings?.bachelor_rate ?? 155);
    return { min: r, max: r, label: `${r} บาท/ชั่วโมง` };
  }
  if (tier === 'master') {
    const r = Number(settings?.master_rate ?? 180);
    return { min: r, max: r, label: `${r} บาท/ชั่วโมง` };
  }
  if (tier === 'doctorate') {
    const min = Number(settings?.doctorate_rate_min ?? 200);
    const max = Number(settings?.doctorate_rate_max ?? 250);
    return { min, max, label: `${min}–${max} บาท/ชั่วโมง` };
  }
  throw new Error('กรุณาเลือกระดับการศึกษาสำหรับกำหนดค่าตอบแทน');
}

function agreementText(rateText: string, payoutCycle: string) {
  return `การสมัครเป็นติวเตอร์ — สถาบันกวดวิชาชีววิทยา อาวริน

ผู้สมัครประสงค์สมัครเป็นติวเตอร์เพื่อให้บริการสอนผ่านระบบของสถาบัน กวดวิชาชีววิทยา อาวริน โดยข้อมูลและเอกสารที่ผู้สมัครให้แก่ระบบต้องเป็นข้อมูลที่ถูกต้องและเป็นปัจจุบัน

1. ข้อมูลผู้สมัคร
ผู้สมัครต้องให้ข้อมูลตามที่ระบบกำหนด ซึ่งรวมถึงชื่อ–นามสกุล วันเดือนปีเกิด เลขประจำตัวประชาชน หรือเลขหนังสือเดินทางสำหรับชาวต่างชาติ ที่อยู่ หมายเลขโทรศัพท์ อีเมล วุฒิการศึกษา/สถาบัน วิชาและระดับชั้นที่สามารถสอนได้ ประสบการณ์สอน อัตราค่าตอบแทน เลขบัญชีธนาคารสำหรับรับค่าตอบแทน และเอกสารยืนยันตัวตนหรือเอกสารประกอบคุณสมบัติเท่าที่จำเป็น

2. ค่าตอบแทน
ระบบจะแสดงค่าตอบแทนที่ติวเตอร์จะได้รับก่อนยืนยันรับงาน
อัตราค่าตอบแทนตามระดับการศึกษาของผู้สมัครรายนี้: ${rateText}
รอบการจ่ายเงิน: ${payoutCycle}
หากมีกฎหมายกำหนดให้ต้องหักภาษี ณ ที่จ่ายหรือรายการอื่นใด กิจการจะดำเนินการตามกฎหมายและแสดงรายละเอียดการหักดังกล่าวในรายการจ่ายเงิน
ค่าบริหารจัดการของระบบและภาษีหัก ณ ที่จ่ายเป็นคนละรายการกัน

3. การรับงานและการสอน
ติวเตอร์ต้องดำเนินการสอนตามวัน เวลา วิชา และเงื่อนไขของงานที่ยืนยันรับไว้ หากไม่สามารถเข้าสอนได้ ต้องแจ้งผ่านระบบตามระยะเวลาที่กำหนด
ติวเตอร์ต้องรักษามาตรฐานการสอน ความเหมาะสมในการสื่อสาร และข้อมูลส่วนบุคคลของนักเรียน

4. การติดต่อกับนักเรียนและการห้ามชักชวนนักเรียนออกนอกระบบ
ข้อมูลนักเรียนที่ติวเตอร์ได้รับเนื่องจากการรับงานผ่านกิจการ ให้ใช้เพื่อวัตถุประสงค์ในการจัดการเรียนการสอนตามงานที่ได้รับเท่านั้น
ติวเตอร์ตกลงว่าจะไม่ใช้ข้อมูลหรือความสัมพันธ์กับนักเรียนที่ได้รับหรือรู้จักผ่านกิจการเพื่อ
(1) ชักชวนให้นักเรียนยกเลิกหรือหลีกเลี่ยงการใช้บริการของกิจการเพื่อไปเรียนกับติวเตอร์โดยตรง
(2) รับชำระค่าเรียนจากนักเรียนดังกล่าวโดยตรงเพื่อหลีกเลี่ยงระบบ
(3) นัดหมายหรือจัดการเรียนการสอนนอกระบบเพื่อหลีกเลี่ยงค่าบริหารจัดการของกิจการ
(4) ส่งต่อหรือชักชวนนักเรียนดังกล่าวไปยังบุคคลหรือกิจการอื่นเพื่อหลีกเลี่ยงระบบ
(5) นำข้อมูลส่วนบุคคลหรือช่องทางติดต่อของนักเรียนไปใช้เพื่อประโยชน์ส่วนตัวโดยไม่ได้รับอนุญาต
ข้อกำหนดนี้ไม่มุ่งหมายห้ามติวเตอร์ประกอบอาชีพสอนพิเศษทั่วไปหรือรับนักเรียนที่ติวเตอร์หามาเองโดยอิสระและไม่ได้รู้จักนักเรียนดังกล่าวผ่านกิจการ
หากพบการฝ่าฝืน กิจการมีสิทธิระงับบัญชี ยกเลิกสิทธิการใช้งาน ยกเลิกข้อตกลง และใช้สิทธิตามกฎหมายเพื่อเรียกร้องความเสียหายที่เกิดขึ้นจริงตามที่กฎหมายอนุญาต

5. ข้อมูลและความลับ
ติวเตอร์ต้องเก็บรักษาข้อมูลส่วนบุคคลของนักเรียน ผู้ปกครอง เอกสารการเรียน ช่องทางติดต่อ และข้อมูลภายในของกิจการเป็นความลับ และต้องไม่นำข้อมูลดังกล่าวไปใช้เพื่อวัตถุประสงค์อื่นนอกเหนือจากงานที่ได้รับมอบหมาย
เมื่อสิ้นสุดการให้บริการ ติวเตอร์ต้องหยุดใช้ข้อมูลดังกล่าวและดำเนินการกับข้อมูลตามนโยบายและข้อกำหนดที่เกี่ยวข้อง

6. การลาออก/ยุติการให้บริการ
ติวเตอร์สามารถยื่นคำขอยุติการให้บริการได้ผ่านเมนู บัญชีของฉัน → ยุติการเป็นติวเตอร์
ก่อนวันที่การยุติมีผล ติวเตอร์ต้องดำเนินการเกี่ยวกับคลาสที่รับไว้ นักเรียนที่อยู่ระหว่างการเรียน เอกสาร และยอดค่าตอบแทนคงค้างตามเงื่อนไขของระบบ
การยุติการเป็นติวเตอร์ไม่ทำให้หน้าที่เกี่ยวกับการรักษาความลับ การคุ้มครองข้อมูลส่วนบุคคล และข้อกำหนดเกี่ยวกับการไม่ชักชวนนักเรียนที่กำหนดให้มีผลต่อเนื่องสิ้นสุดลงโดยอัตโนมัติ

PDPA / การยืนยันตัวตน
เลขประจำตัวประชาชนหรือเลขหนังสือเดินทางและเอกสารยืนยันตัวตนถูกขอเพื่อยืนยันตัวตน ป้องกันการสวมสิทธิ์ ดำเนินการก่อนเข้าทำข้อตกลงและบริหารข้อตกลง รวมทั้งดำเนินการด้านบัญชี ภาษี หรือหน้าที่ตามกฎหมายที่เกี่ยวข้องเท่าที่จำเป็น โดยยึดหลักการเก็บข้อมูลเท่าที่จำเป็นและแจ้งวัตถุประสงค์ก่อนเก็บตามพระราชบัญญัติคุ้มครองข้อมูลส่วนบุคคล พ.ศ. 2562 มาตรา 22–24`;
}

async function sha256(text: string) {
  const bytes = new TextEncoder().encode(text);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function safeExt(file: File) {
  const mime = String(file.type || '').toLowerCase();
  if (mime === 'application/pdf') return 'pdf';
  if (mime === 'image/jpeg') return 'jpg';
  if (mime === 'image/png') return 'png';
  if (mime === 'image/webp') return 'webp';
  throw new Error(`ไฟล์ ${file.name || ''} เป็นชนิดที่ไม่รองรับ`);
}

function validateFile(file: File | null, maxMb: number) {
  if (!file) return;
  if (file.size <= 0 || file.size > maxMb * 1024 * 1024) {
    throw new Error(`${file.name} ต้องมีขนาดไม่เกิน ${maxMb} MB`);
  }
  safeExt(file);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !service) {
    return json({ success: false, message: 'Function environment is incomplete' }, 500);
  }

  const sb = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const uploaded: string[] = [];
  let applicationId: string | null = null;
  let applicationInserted = false;

  try {
    const form = await req.formData();
    const raw = clean(form.get('payload'));
    if (!raw) throw new Error('Missing payload');

    let d: any;
    try {
      d = JSON.parse(raw);
    } catch {
      throw new Error('ข้อมูลที่ส่งมาไม่ใช่ JSON ที่ถูกต้อง');
    }

    const firstName = clean(d.first_name);
    const lastName = clean(d.last_name);
    const nickname = clean(d.nickname);
    const birthDate = clean(d.birth_date);
    const address = clean(d.address);
    const phone = cleanPhone(d.phone);
    const email = clean(d.email).toLowerCase();
    const nationality = clean(d.nationality);
    const countryResidence = clean(d.country_residence);
    const identityNumber = clean(d.identity_number);
    const isForeigner = !!d.is_foreigner;
    const identityType = isForeigner ? 'passport' : 'thai_national_id';
    const educationTier = clean(d.education_tier);

    if (!firstName || !lastName || !nickname || !birthDate || !address) {
      throw new Error('กรุณากรอกข้อมูลผู้สมัครให้ครบ');
    }
    if (phone.length < 8 || phone.length > 15) throw new Error('เบอร์โทรไม่ถูกต้อง');
    if (!isEmail(email)) throw new Error('อีเมลไม่ถูกต้อง');
    if (!nationality || !countryResidence) throw new Error('กรุณาระบุสัญชาติและประเทศที่พำนัก');
    if (!identityNumber) {
      throw new Error(isForeigner ? 'กรุณากรอกเลขหนังสือเดินทาง' : 'กรุณากรอกเลขประจำตัวประชาชน');
    }
    if (!isForeigner && !/^\d{13}$/.test(identityNumber)) {
      throw new Error('เลขประจำตัวประชาชนต้องมีตัวเลข 13 หลัก');
    }
    if (isForeigner && identityNumber.length < 5) throw new Error('เลขหนังสือเดินทางไม่ถูกต้อง');

    const bankName = clean(d.bank_name);
    const bankAccountName = clean(d.bank_account_name);
    const bankAccountNumber = clean(d.bank_account_number).replace(/\s+/g, '');
    if (!bankName || !bankAccountName || !bankAccountNumber) {
      throw new Error('กรุณากรอกข้อมูลบัญชีธนาคารสำหรับรับค่าตอบแทนให้ครบ');
    }

    const checks = Array.isArray(d.agreement_checks) ? d.agreement_checks.map(String) : [];
    const requiredChecks = [
      'read_all','rate','withholding','non_circumvention','remedies','termination','truth'
    ];
    if (!requiredChecks.every((k) => checks.includes(k))) {
      throw new Error('กรุณายืนยัน NOTICE ก่อนลงนามให้ครบทุกข้อ');
    }
    if (!d.agreement_accepted || !d.consent_pdpa || !d.certified_accuracy) {
      throw new Error('กรุณายืนยันข้อตกลง ความถูกต้องของข้อมูล และการประมวลผลข้อมูลให้ครบ');
    }

    const applicantSignature = clean(d.applicant_signature_data);
    if (!applicantSignature.startsWith('data:image/png;base64,')) {
      throw new Error('กรุณาลงลายมือชื่ออิเล็กทรอนิกส์');
    }
    if (applicantSignature.length > 800000) {
      throw new Error('ไฟล์ลายเซ็นผู้สมัครมีขนาดใหญ่เกินไป');
    }

    const [settingsRes, managerRes] = await Promise.all([
      sb.from('aw_tutor_contract_settings').select('*').eq('id', 1).maybeSingle(),
      sb.from('aw_manager_signatures')
        .select('*')
        .eq('active', true)
        .eq('is_default', true)
        .order('updated_at', { ascending: false })
        .limit(1)
        .maybeSingle(),
    ]);

    if (settingsRes.error) throw settingsRes.error;
    if (managerRes.error) throw managerRes.error;

    const settings = settingsRes.data || {};
    const managerSig = managerRes.data;
    if (!managerSig?.signature_data_url) {
      return json({
        success: false,
        message: 'Manager ยังไม่ได้ตั้งค่าลายเซ็นผู้แทนสถาบันใน Manager System',
      }, 409);
    }

    const rate = rateForTier(educationTier, settings);
    const payoutCycle = clean(settings.payout_cycle) || 'ตามรอบที่ระบบกำหนดและแจ้งก่อนการจ่าย';
    const agreementVersion = clean(settings.agreement_version) || DEFAULT_AGREEMENT_VERSION;

    const getFile = (key: string): File | null => {
      const value = form.get(key);
      return value instanceof File && value.size > 0 ? value : null;
    };

    const files: Record<string, File | null> = {
      identity_document: getFile('identity_document'),
      profile_photo: getFile('profile_photo'),
      resume: getFile('resume'),
      portfolio: getFile('portfolio'),
      transcript: getFile('transcript'),
      bankbook: getFile('bankbook'),
    };

    // Thai applicant: national ID copy is mandatory.
    // Foreigner: this requirement is waived; passport copy remains optional.
    if (!isForeigner && !files.identity_document) {
      throw new Error('ผู้สมัครชาวไทยต้องแนบสำเนาบัตรประชาชน');
    }

    validateFile(files.identity_document, 10);
    validateFile(files.profile_photo, 5);
    validateFile(files.resume, 10);
    validateFile(files.portfolio, 10);
    validateFile(files.transcript, 10);
    validateFile(files.bankbook, 10);

    applicationId = crypto.randomUUID();

    const noRes = await sb.rpc('aw_next_tutor_application_no');
    if (noRes.error || !noRes.data) {
      throw noRes.error || new Error('ไม่สามารถสร้างเลขใบสมัครได้');
    }
    const applicationNo = String(noRes.data);

    const paths: Record<string, string | null> = {
      identity_document: null,
      profile_photo: null,
      resume: null,
      portfolio: null,
      transcript: null,
      bankbook: null,
    };

    for (const [kind, file] of Object.entries(files)) {
      if (!file) continue;
      const ext = safeExt(file);
      const path = `${new Date().toISOString().slice(0, 4)}/${applicationId}/${kind}.${ext}`;
      const up = await sb.storage.from('tutor-applications').upload(path, file, {
        contentType: file.type || 'application/octet-stream',
        cacheControl: '3600',
        upsert: false,
      });
      if (up.error) throw up.error;
      uploaded.push(path);
      paths[kind] = path;
    }

    const appRow: any = {
      id: applicationId,
      application_no: applicationNo,
      first_name: firstName,
      last_name: lastName,
      nickname,
      phone,
      email,
      line_id: clean(d.line_id) || null,
      province: clean(d.province) || null,
      current_occupation: clean(d.current_occupation) || null,
      intro: clean(d.intro) || null,
      education: Array.isArray(d.education) ? d.education : [],
      work_experience: Array.isArray(d.work_experience) ? d.work_experience : [],
      achievements: clean(d.achievements) || null,
      subjects: Array.isArray(d.subjects) ? d.subjects.map(String) : [],
      levels: Array.isArray(d.levels) ? d.levels.map(String) : [],
      teaching_modes: Array.isArray(d.teaching_modes) ? d.teaching_modes.map(String) : [],
      teaching_experience_years: Number(d.teaching_experience_years || 0),
      expected_rate: rate.label,
      preferred_location: clean(d.preferred_location) || null,
      availability: Array.isArray(d.availability) ? d.availability : [],
      teaching_style: clean(d.teaching_style) || null,
      why_join: clean(d.why_join) || null,
      additional_note: clean(d.additional_note) || null,
      profile_photo_path: paths.profile_photo,
      resume_path: paths.resume,
      portfolio_path: paths.portfolio,
      transcript_path: paths.transcript,
      status: 'new',
      consent_pdpa: true,
      certified_accuracy: true,
      policy_version_acknowledged: Number(d.policy_version || 1),
      policy_acknowledged_at: new Date().toISOString(),
      preferred_language: clean(d.preferred_language) === 'en' ? 'en' : 'th',
      nationality,
      country_residence: countryResidence,
      birth_date: birthDate,
      address,
      is_foreigner: isForeigner,
      education_tier: educationTier,
      compensation_rate_min: rate.min,
      compensation_rate_max: rate.max,
      identity_document_path: paths.identity_document,
      bankbook_path: paths.bankbook,
      agreement_version: agreementVersion,
      agreement_signed_at: new Date().toISOString(),
    };

    const appIns = await sb
      .from('tutor_applications')
      .insert(appRow)
      .select('id,application_no')
      .single();
    if (appIns.error) throw appIns.error;
    applicationInserted = true;

    const clientIp = clean(
      req.headers.get('cf-connecting-ip')
      || req.headers.get('x-real-ip')
      || req.headers.get('x-forwarded-for')?.split(',')[0]
      || ''
    );
    const userAgent = clean(req.headers.get('user-agent'));
    const transactionMeta = {
      origin: clean(req.headers.get('origin')),
      referer: clean(req.headers.get('referer')),
      forwarded_for: clean(req.headers.get('x-forwarded-for')),
      edge_request_id: clean(req.headers.get('x-request-id')),
    };

    const privateIns = await sb.from('tutor_application_private').insert({
      application_id: applicationId,
      identity_type: identityType,
      identity_number: identityNumber,
      bank_name: bankName,
      bank_account_name: bankAccountName,
      bank_account_number: bankAccountNumber,
      identity_document_path: paths.identity_document,
      bankbook_path: paths.bankbook,
      client_ip: clientIp || null,
      user_agent: userAgent || null,
      transaction_meta: transactionMeta,
    });
    if (privateIns.error) throw privateIns.error;

    const agreement = agreementText(rate.label, payoutCycle);
    const signedAt = new Date().toISOString();
    const hash = await sha256([
      agreementVersion,
      applicationId,
      applicationNo,
      signedAt,
      identityType,
      identityNumber.slice(-4),
      applicantSignature,
      managerSig.signature_data_url,
      agreement,
    ].join('|'));

    const agreementIns = await sb.from('tutor_service_agreements').insert({
      application_id: applicationId,
      agreement_version: agreementVersion,
      agreement_text_snapshot: agreement,
      applicant_name: `${firstName} ${lastName}`.trim(),
      applicant_identity_type: identityType,
      applicant_identity_last4: identityNumber.slice(-4),
      applicant_signature_data: applicantSignature,
      manager_signature_id: managerSig.id,
      manager_signer_name: managerSig.signer_name,
      manager_signer_title: managerSig.signer_title,
      manager_signature_data: managerSig.signature_data_url,
      compensation_rate_min: rate.min,
      compensation_rate_max: rate.max,
      payout_cycle: payoutCycle,
      notice_checks: checks,
      signed_at: signedAt,
      client_signed_at: d.client_signed_at || null,
      client_ip: clientIp || null,
      user_agent: userAgent || null,
      transaction_meta: transactionMeta,
      agreement_sha256: hash,
    });
    if (agreementIns.error) throw agreementIns.error;

    return json({
      success: true,
      application_id: applicationId,
      application_no: applicationNo,
      agreement_version: agreementVersion,
      compensation_rate_min: rate.min,
      compensation_rate_max: rate.max,
      manager_signer_name: managerSig.signer_name,
      version: 'v2.0-agreement',
    });

  } catch (err: any) {
    console.error('[submit-tutor-application V2.0] failed', err);

    if (applicationInserted && applicationId) {
      await sb.from('tutor_applications').delete().eq('id', applicationId);
    }
    if (uploaded.length) {
      await sb.storage.from('tutor-applications').remove(uploaded);
    }

    return json({
      success: false,
      message: err?.message || String(err),
      version: 'v2.0-agreement',
    }, 400);
  }
});
