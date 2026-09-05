import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  // Public application form. No cookies/credentials are used, so wildcard CORS is safe here.
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
  'Vary': 'Origin',
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, 'Content-Type': 'application/json; charset=utf-8' },
})

const cleanPhone = (v: unknown) => String(v ?? '').replace(/\D/g, '')
const text = (v: unknown, max = 5000) => String(v ?? '').trim().slice(0, max)
const arr = (v: unknown) => Array.isArray(v) ? v : []

const fileRules: Record<string, { max: number; types: string[]; prefix: string }> = {
  profile_photo: { max: 5 * 1024 * 1024, types: ['image/jpeg','image/png','image/webp'], prefix: 'profile' },
  resume: { max: 10 * 1024 * 1024, types: ['application/pdf','image/jpeg','image/png','image/webp'], prefix: 'resume' },
  portfolio: { max: 10 * 1024 * 1024, types: ['application/pdf','image/jpeg','image/png','image/webp'], prefix: 'portfolio' },
  transcript: { max: 10 * 1024 * 1024, types: ['application/pdf','image/jpeg','image/png','image/webp'], prefix: 'transcript' },
}

Deno.serve(async (req) => {
  // IMPORTANT: deploy this function with verify_jwt = false / --no-verify-jwt.
  // Otherwise Supabase's gateway can reject OPTIONS before this code gets a chance to answer CORS.
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders })
  if (req.method === 'GET') return json({ ok:true, function:'submit-tutor-application', version:'v13-cors-fix' })
  if (req.method !== 'POST') return json({ success:false, message:'Method not allowed' }, 405)

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const admin = createClient(supabaseUrl, serviceKey, { auth:{ persistSession:false } })
    const form = await req.formData()
    const rawPayload = form.get('payload')
    if (typeof rawPayload !== 'string') return json({ success:false, message:'ไม่พบข้อมูลใบสมัคร' }, 400)

    let p: any
    try { p = JSON.parse(rawPayload) } catch { return json({ success:false, message:'รูปแบบข้อมูลไม่ถูกต้อง' }, 400) }

    const lang = p.preferred_language === 'en' ? 'en' : 'th'
    const msg = (th:string,en:string) => lang === 'en' ? en : th
    const required = ['first_name','last_name','nickname','phone','email']
    for (const k of required) if (!text(p[k],300)) return json({ success:false, message:msg(`กรุณากรอก ${k}`,`Please complete ${k}.`) }, 400)
    const phone = cleanPhone(p.phone)
    if (phone.length < 8 || phone.length > 15) return json({ success:false, message:msg('เบอร์โทรไม่ถูกต้อง','Invalid phone number. Please include the country code when applicable.') }, 400)
    const email = text(p.email,320).toLowerCase()
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ success:false, message:msg('อีเมลไม่ถูกต้อง','Invalid email address.') }, 400)
    if (!arr(p.subjects).length) return json({ success:false, message:msg('กรุณาเลือกวิชาที่สอน','Please select at least one subject.') }, 400)
    if (!arr(p.levels).length) return json({ success:false, message:msg('กรุณาเลือกระดับผู้เรียน','Please select at least one learner level.') }, 400)
    if (!arr(p.teaching_modes).length) return json({ success:false, message:msg('กรุณาเลือกรูปแบบการสอน','Please select a teaching mode.') }, 400)
    if (!arr(p.availability).length) return json({ success:false, message:msg('กรุณาเลือกวันที่สะดวก','Please select at least one available day.') }, 400)
    if (p.consent_pdpa !== true || p.certified_accuracy !== true) return json({ success:false, message:msg('กรุณายืนยันข้อมูลและการใช้ข้อมูลส่วนบุคคล','Please confirm data accuracy and consent to data use.') }, 400)

    for (const [key,rule] of Object.entries(fileRules)) {
      const f = form.get(key)
      if (f instanceof File && f.size > 0) {
        if (f.size > rule.max) return json({ success:false, message:`ไฟล์ ${key} ใหญ่เกินกำหนด` }, 400)
        if (!rule.types.includes(f.type)) return json({ success:false, message:`ชนิดไฟล์ ${key} ไม่รองรับ` }, 400)
      }
    }

    const { data:no, error:noErr } = await admin.rpc('next_tutor_application_no')
    if (noErr || !no) throw noErr || new Error('สร้างเลขใบสมัครไม่สำเร็จ')
    const id = crypto.randomUUID()

    const row:any = {
      id,
      application_no:no,
      first_name:text(p.first_name,120),
      last_name:text(p.last_name,120),
      nickname:text(p.nickname,120),
      phone,
      email,
      line_id:text(p.line_id,200) || null,
      preferred_language:lang,
      nationality:text(p.nationality,200) || null,
      country_residence:text(p.country_residence,200) || null,
      province:text(p.province,200) || null,
      current_occupation:text(p.current_occupation,300) || null,
      intro:text(p.intro,6000) || null,
      education:arr(p.education).slice(0,20),
      work_experience:arr(p.work_experience).slice(0,30),
      achievements:text(p.achievements,8000) || null,
      subjects:arr(p.subjects).map((x:any)=>text(x,80)).filter(Boolean).slice(0,30),
      levels:arr(p.levels).map((x:any)=>text(x,80)).filter(Boolean).slice(0,20),
      teaching_modes:arr(p.teaching_modes).map((x:any)=>text(x,80)).filter(Boolean).slice(0,10),
      teaching_experience_years:Math.max(0,Math.min(50,Number(p.teaching_experience_years)||0)),
      expected_rate:text(p.expected_rate,200) || null,
      preferred_location:text(p.preferred_location,500) || null,
      availability:arr(p.availability).slice(0,21),
      teaching_style:text(p.teaching_style,8000) || null,
      why_join:text(p.why_join,8000) || null,
      additional_note:text(p.additional_note,8000) || null,
      status:'new',
      consent_pdpa:true,
      certified_accuracy:true,
      policy_version_acknowledged:Math.max(1,Math.floor(Number(p.policy_version)||1)),
      policy_acknowledged_at:new Date().toISOString(),
    }

    const { error:insertErr } = await admin.from('tutor_applications').insert(row)
    if (insertErr) throw insertErr

    const uploaded: Record<string,string> = {}
    try {
      for (const [key,rule] of Object.entries(fileRules)) {
        const f = form.get(key)
        if (!(f instanceof File) || f.size === 0) continue
        const safeExt = f.type === 'application/pdf' ? 'pdf' : (f.type.split('/')[1] || 'bin').replace('jpeg','jpg')
        const path = `${id}/${rule.prefix}-${crypto.randomUUID()}.${safeExt}`
        const bytes = new Uint8Array(await f.arrayBuffer())
        const { error:uploadErr } = await admin.storage.from('tutor-application-assets').upload(path, bytes, { contentType:f.type, upsert:false })
        if (uploadErr) throw uploadErr
        uploaded[key] = path
      }
      const patch:any = {}
      if (uploaded.profile_photo) patch.profile_photo_path = uploaded.profile_photo
      if (uploaded.resume) patch.resume_path = uploaded.resume
      if (uploaded.portfolio) patch.portfolio_path = uploaded.portfolio
      if (uploaded.transcript) patch.transcript_path = uploaded.transcript
      if (Object.keys(patch).length) {
        const { error:updateErr } = await admin.from('tutor_applications').update(patch).eq('id',id)
        if (updateErr) throw updateErr
      }
    } catch (fileErr) {
      await admin.from('tutor_applications').delete().eq('id',id)
      for (const path of Object.values(uploaded)) await admin.storage.from('tutor-application-assets').remove([path])
      throw fileErr
    }

    return json({ success:true, application_no:no })
  } catch (e) {
    console.error('submit-tutor-application', e)
    return json({ success:false, message:e instanceof Error ? e.message : 'ส่งใบสมัครไม่สำเร็จ' }, 500)
  }
})
