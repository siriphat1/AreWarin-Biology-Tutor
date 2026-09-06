import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, accept',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
});
const clean = (v: unknown) => String(v ?? '').trim();
const num = (v: unknown, fallback = 0) => Number.isFinite(Number(v)) ? Number(v) : fallback;
const errorText = (err: any) => {
  if (!err) return 'Unknown error';
  if (typeof err === 'string') return err;
  if (err instanceof Error) return err.message || String(err);
  const parts = [err.message, err.details, err.hint, err.code].filter(Boolean).map(String);
  if (parts.length) return parts.join(' | ');
  try { return JSON.stringify(err); } catch { return String(err); }
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders });
  if (req.method === 'GET') return json({
    ok: true,
    function: 'create-enrollment',
    version: 'v15.2.3-rescue',
    mode: 'minimal-core-first',
  });
  if (req.method !== 'POST') return json({ success: false, message: 'Method not allowed' }, 405);

  const url = Deno.env.get('SUPABASE_URL');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !service) return json({ success: false, message: 'Function environment is incomplete' }, 500);

  const sb = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const warnings: string[] = [];
  let enrollment: any = null;
  let slipPath: string | null = null;

  try {
    const raw = await req.text();
    let d: any;
    try { d = raw ? JSON.parse(raw) : {}; }
    catch { return json({ success:false, message:'ข้อมูลที่ส่งมาไม่ใช่ JSON ที่ถูกต้อง', version:'v15.2.3-rescue' }, 400); }

    const fullname = clean(d.fullname);
    if (!fullname) return json({ success:false, message:'กรุณากรอกชื่อผู้สมัคร', version:'v15.2.3-rescue' }, 400);

    const amount = Math.max(0, num(d.price, 0));
    const paymentMethod = clean(d.paymentMethod) === 'cash' ? 'cash' : 'transfer';
    const sanitizedPayload = { ...d, fileData: undefined };

    // First try the normal core row. If the production schema is older, retry with
    // the absolute minimum columns that have existed since the original AreWarin setup.
    const normalRow: any = {
      student_type: clean(d.studentType) === 'old' ? 'old' : 'new',
      fullname,
      nickname: clean(d.nickname) || null,
      phone: clean(d.phone) || null,
      line_id: clean(d.lineId) || null,
      email: clean(d.email) || null,
      grade: clean(d.grade) || null,
      school: clean(d.school) || null,
      faculty: clean(d.faculty) || null,
      province: clean(d.province) || null,
      parent_name: clean(d.parentName) || null,
      parent_relation: clean(d.parentRelation) || null,
      parent_phone: clean(d.parentPhone) || null,
      study_type: clean(d.studyType) || null,
      group_size: Math.max(1, Math.floor(num(d.groupSize, 1))),
      additional_students: Array.isArray(d.additionalStudents) ? d.additionalStudents : [],
      tutor_text: clean(d.tutor) || null,
      course_text: clean(d.course) || null,
      mode_text: clean(d.modeLabel) || clean(d.mode) || clean(d.selectedMode) || null,
      hours_text: clean(d.hours) || null,
      time_text: clean(d.time) || null,
      amount_quoted: amount,
      promotion_code: clean(d.discountCode).toUpperCase() || null,
      status: 'pending_payment_verification',
      raw_payload: sanitizedPayload,
    };

    let ins = await sb.from('enrollments').insert(normalRow).select('id,receipt_no,receipt_token').single();
    if (ins.error) {
      warnings.push(`NORMAL_INSERT_RETRY:${errorText(ins.error)}`);
      const minimalRow: any = {
        fullname,
        phone: clean(d.phone) || null,
        amount_quoted: amount,
        raw_payload: sanitizedPayload,
      };
      ins = await sb.from('enrollments').insert(minimalRow).select('id,receipt_no,receipt_token').single();
    }
    if (ins.error || !ins.data) {
      throw new Error(`บันทึกใบสมัครไม่ได้: ${errorText(ins.error)}`);
    }
    enrollment = ins.data;

    // Receipt number is best-effort. A missing sequence must never block enrollment.
    if (!enrollment.receipt_no) {
      const rec = await sb.rpc('next_receipt_no');
      if (!rec.error && rec.data) {
        const up = await sb.from('enrollments').update({ receipt_no: rec.data }).eq('id', enrollment.id).select('receipt_no').maybeSingle();
        if (!up.error && up.data?.receipt_no) enrollment.receipt_no = up.data.receipt_no;
        else warnings.push(`RECEIPT_UPDATE_SKIPPED:${errorText(up.error)}`);
      } else if (rec.error) warnings.push(`RECEIPT_RPC_SKIPPED:${errorText(rec.error)}`);
    }

    // Preserve the slip when possible, but do not discard a valid enrollment if Storage
    // configuration is temporarily unavailable. Manager will see the warning in raw payload/logs.
    if (paymentMethod === 'transfer') {
      if (!d.fileData) {
        warnings.push('SLIP_MISSING');
      } else {
        try {
          const binary = Uint8Array.from(atob(String(d.fileData)), c => c.charCodeAt(0));
          const rawName = clean(d.fileName) || 'slip.jpg';
          const ext = (rawName.split('.').pop() || 'jpg').replace(/[^a-zA-Z0-9]/g, '').toLowerCase() || 'jpg';
          slipPath = `${new Date().toISOString().slice(0,7)}/${enrollment.id}.${ext}`;
          const up = await sb.storage.from('payment-slips').upload(slipPath, binary, {
            contentType: clean(d.mimeType) || 'image/jpeg',
            upsert: true,
          });
          if (up.error) {
            warnings.push(`SLIP_UPLOAD_FAILED:${errorText(up.error)}`);
            slipPath = null;
          }
        } catch (e) {
          warnings.push(`SLIP_DECODE_FAILED:${errorText(e)}`);
          slipPath = null;
        }
      }
    }

    const pay = await sb.from('payments').insert({
      enrollment_id: enrollment.id,
      payment_method: paymentMethod,
      amount_submitted: amount,
      slip_path: slipPath,
      status: 'pending',
    });
    if (pay.error) warnings.push(`PAYMENT_ROW_FAILED:${errorText(pay.error)}`);

    // Write warnings back into raw_payload so Manager can audit emergency enrollments.
    if (warnings.length) {
      const payloadWithWarnings = { ...sanitizedPayload, rescueWarnings: warnings, rescueVersion: 'v15.2.3-rescue', slipPath };
      const upd = await sb.from('enrollments').update({ raw_payload: payloadWithWarnings }).eq('id', enrollment.id);
      if (upd.error) console.warn('Could not persist rescue warnings:', upd.error);
    }

    return json({
      success: true,
      enrollmentId: enrollment.id,
      receiptNo: enrollment.receipt_no || null,
      receiptToken: enrollment.receipt_token || null,
      amount,
      status: 'pending',
      version: 'v15.2.3-rescue',
      warnings,
      needsManagerReview: warnings.length > 0,
    });
  } catch (err) {
    const message = errorText(err);
    console.error('create-enrollment v15.2.3 rescue failed', { message, err, enrollmentId: enrollment?.id, slipPath, warnings });
    return json({ success:false, message, version:'v15.2.3-rescue', warnings }, 400);
  }
});
