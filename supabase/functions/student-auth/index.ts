import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status=200) => new Response(JSON.stringify(body), {
  status, headers:{...corsHeaders,'Content-Type':'application/json; charset=utf-8'}
});
const clean = (v: unknown) => String(v ?? '').trim();
const phoneKey = (v: unknown) => clean(v).replace(/\D/g,'');

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:corsHeaders});
  if (req.method !== 'POST') return json({ok:false,message:'Method not allowed'},405);

  const url=Deno.env.get('SUPABASE_URL');
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!service) return json({ok:false,message:'Supabase function environment is incomplete'},500);
  const sb=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});

  try {
    const body=await req.json();
    const action=clean(body.action);

    if(action==='register'){
      const phone=phoneKey(body.phone);
      const email=clean(body.email).toLowerCase();
      const password=clean(body.password);
      const pin=clean(body.pin);
      if(phone.length<9) return json({ok:false,code:'invalid_phone',message:'เบอร์โทรไม่ถูกต้อง'},400);
      if(!/^\S+@\S+\.\S+$/.test(email)) return json({ok:false,code:'invalid_email',message:'อีเมลไม่ถูกต้อง'},400);
      if(password.length<8) return json({ok:false,code:'weak_password',message:'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร'},400);
      if(!/^\d{4}$/.test(pin)) return json({ok:false,code:'invalid_pin',message:'PIN ต้องเป็นเลข 4 หลัก'},400);

      const {data:lookup,error:lookupErr}=await sb.rpc('lookup_student_by_phone',{p_phone:phone});
      if(lookupErr) throw lookupErr;
      if(!lookup?.found||!lookup?.student_id) return json({ok:false,code:'student_not_found',message:lookup?.message||'ไม่พบข้อมูลนักเรียน'},404);

      const {data:student,error:studentErr}=await sb.from('os_students').select('id,student_code,display_name,email').eq('id',lookup.student_id).single();
      if(studentErr) throw studentErr;
      if(student.email && clean(student.email).toLowerCase()!==email) {
        return json({ok:false,code:'email_mismatch',message:'อีเมลไม่ตรงกับข้อมูลที่ใช้สมัครเรียน'},400);
      }
      const {data:existing}=await sb.from('os_student_accounts').select('user_id').eq('student_id',student.id).maybeSingle();
      if(existing?.user_id) return json({ok:false,code:'account_exists',message:'บัญชีนี้สมัคร Student Portal แล้ว'},409);

      const {data:created,error:createErr}=await sb.auth.admin.createUser({
        email,password,email_confirm:true,
        user_metadata:{app:'student_portal',student_id:student.id,student_code:student.student_code}
      });
      if(createErr) {
        const msg=String(createErr.message||'');
        if(/already|registered|exists/i.test(msg)) return json({ok:false,code:'account_exists',message:'อีเมลนี้มีบัญชีแล้ว กรุณาเข้าสู่ระบบ'},409);
        throw createErr;
      }
      if(!created.user) throw new Error('Create user returned no user');

      const {error:linkErr}=await sb.from('os_student_accounts').upsert({
        user_id:created.user.id,student_id:student.id,is_active:true,updated_at:new Date().toISOString()
      },{onConflict:'user_id'});
      if(linkErr){ await sb.auth.admin.deleteUser(created.user.id); throw linkErr; }
      const {error:pinErr}=await sb.rpc('portal_set_pin',{p_user_id:created.user.id,p_pin:pin});
      if(pinErr) throw pinErr;

      return json({ok:true,user_id:created.user.id,student_id:student.id,student_code:student.student_code,display_name:student.display_name,email});
    }

    if(action==='reset_password'){
      const phone=phoneKey(body.phone),email=clean(body.email).toLowerCase(),pin=clean(body.pin),password=clean(body.new_password);
      if(password.length<8) return json({ok:false,code:'weak_password',message:'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร'},400);
      const {data:verified,error:verifyErr}=await sb.rpc('portal_verify_pin',{p_phone:phone,p_email:email,p_pin:pin});
      if(verifyErr) throw verifyErr;
      if(!verified?.ok||!verified?.user_id) return json({ok:false,code:'invalid_pin',message:'เบอร์ อีเมล หรือ PIN ไม่ถูกต้อง'},400);
      const {error:updateErr}=await sb.auth.admin.updateUserById(verified.user_id,{password});
      if(updateErr) throw updateErr;
      return json({ok:true});
    }

    if(action==='health') return json({ok:true,function:'student-auth',version:'v15'});
    return json({ok:false,message:'Unknown action'},400);
  } catch(e) {
    console.error(e);
    return json({ok:false,message:e instanceof Error?e.message:String(e)},500);
  }
});
