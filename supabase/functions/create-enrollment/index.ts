import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status=200) => new Response(JSON.stringify(body), {status, headers:{...corsHeaders,'Content-Type':'application/json; charset=utf-8'}});
const num = (v: unknown, fallback=0) => Number.isFinite(Number(v)) ? Number(v) : fallback;
const clean = (v: unknown) => String(v ?? '').trim();

Deno.serve(async req => {
  if (req.method === 'OPTIONS') return new Response('ok',{headers:corsHeaders});
  if (req.method !== 'POST') return json({success:false,message:'Method not allowed'},405);

  const url=Deno.env.get('SUPABASE_URL');
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!service) return json({success:false,message:'Supabase function environment is incomplete'},500);
  const sb=createClient(url,service,{auth:{persistSession:false}});

  let enrollmentId:string|null=null;
  let slipPath:string|null=null;
  try {
    const d=await req.json();
    const studentType=clean(d.studentType)==='old'?'old':'new';
    const fullname=clean(d.fullname);
    if(!fullname) throw new Error('กรุณากรอกชื่อผู้สมัคร');

    const courseText=clean(d.course);
    const tutorText=clean(d.tutor);
    const phone=clean(d.phone);
    if(studentType==='new' && (!courseText || !tutorText)) throw new Error('ข้อมูลคอร์สหรือติวเตอร์ไม่ครบ');

    // Duplicate guard: same formatted phone + course during the last 5 minutes.
    if(studentType==='new' && phone){
      const since=new Date(Date.now()-5*60*1000).toISOString();
      const {data:dupe}=await sb.from('enrollments').select('id').eq('phone',phone).eq('course_text',courseText).gte('created_at',since).limit(1);
      if(dupe?.length) throw new Error('พบการส่งข้อมูลซ้ำ กรุณารอสักครู่');
    }

    let finalAmount=0;
    let promotionCode:string|null=clean(d.discountCode).toUpperCase()||null;

    if(studentType==='new'){
      const tier=d.hasUniversity?'university':'standard';
      const packageCode=['yearly','monthly','pack20','pack10','hourly'].includes(clean(d.selectedMode)) ? clean(d.selectedMode) : 'monthly';
      const {data:price,error:priceErr}=await sb.from('course_prices').select('amount').eq('tier',tier).eq('package_code',packageCode).eq('active',true).single();
      if(priceErr||!price) throw new Error('ไม่พบราคาสำหรับแพ็กเกจที่เลือก');

      let unit=num(price.amount);
      const isGroup=clean(d.studyType)==='group';
      const groupSize=Math.max(1,Math.min(100,Math.floor(num(d.groupSize,1))));
      const courseCount=Math.max(1,Math.floor(num(d.courseCount,1)));
      const multiplier=(courseCount>1 && clean(d.cartShareMode)==='separate')?courseCount:1;
      const groupDiscount:Record<string,number>={yearly:3000,monthly:700,pack20:500,pack10:200,hourly:20};
      if(isGroup) unit=Math.max(0,unit-groupDiscount[packageCode]);
      unit*=multiplier;
      if(packageCode==='hourly') finalAmount=unit*Math.max(1,Math.floor(num(d.hourlyCount,1)))*groupSize;
      else finalAmount=unit*groupSize;
      if(d.onsite) finalAmount+=150;

      if(promotionCode){
        const {data:promo}=await sb.from('promotions').select('*').eq('code',promotionCode).eq('active',true).maybeSingle();
        const now=Date.now();
        if(promo && (!promo.starts_at||now>=new Date(promo.starts_at).getTime()) && (!promo.ends_at||now<=new Date(promo.ends_at).getTime())){
          const value=num(promo.discount_value);
          const discount=promo.discount_type==='percent'?Math.round(finalAmount*value/100):value;
          finalAmount=Math.max(0,finalAmount-discount);
        }else{
          promotionCode=null;
        }
      }
    } else {
      // Renewal/custom legacy amount is intentionally manager-defined in the existing flow.
      finalAmount=Math.max(0,num(d.price,0));
    }

    const {data:receiptNo,error:receiptErr}=await sb.rpc('next_receipt_no');
    if(receiptErr) throw receiptErr;

    const enrollmentRow={
      receipt_no:receiptNo,
      student_type:studentType,
      fullname,
      nickname:clean(d.nickname)||null,
      phone:phone||null,
      line_id:clean(d.lineId)||null,
      email:clean(d.email)||null,
      grade:clean(d.grade)||null,
      school:clean(d.school)||null,
      faculty:clean(d.faculty)||null,
      province:clean(d.province)||null,
      parent_name:clean(d.parentName)||null,
      parent_relation:clean(d.parentRelation)||null,
      parent_phone:clean(d.parentPhone)||null,
      study_type:clean(d.studyType)||null,
      group_size:Math.max(1,Math.floor(num(d.groupSize,1))),
      additional_students:Array.isArray(d.additionalStudents)?d.additionalStudents:[],
      tutor_text:tutorText||null,
      course_text:courseText||null,
      mode_text:clean(d.modeLabel)||clean(d.mode)||clean(d.selectedMode)||null,
      hours_text:clean(d.hours)||null,
      time_text:clean(d.time)||null,
      amount_quoted:finalAmount,
      promotion_code:promotionCode,
      status:'pending_payment_verification',
      raw_payload:{...d,fileData:undefined}
    };
    const {data:enrollment,error:enrollErr}=await sb.from('enrollments').insert(enrollmentRow).select('id,receipt_no,receipt_token').single();
    if(enrollErr) throw enrollErr;
    enrollmentId=enrollment.id;

    // Reserve every selected slot for every tutor in the cart using the DB lock/capacity function.
    if(studentType==='new'){
      const tutorNames=tutorText.split(',').map((x:string)=>x.trim()).filter(Boolean);
      const {data:tutors,error:tutorErr}=await sb.from('tutors').select('id,display_name').in('display_name',tutorNames);
      if(tutorErr) throw tutorErr;
      const tutorIds=(tutors||[]).map((x:any)=>x.id);
      const selections=Array.isArray(d.scheduleSelections)?d.scheduleSelections:[];
      if(tutorIds.length && selections.length===0) throw new Error('กรุณาเลือกเวลาเรียน');
      if(tutorIds.length && selections.length){
        const {error:reserveErr}=await sb.rpc('reserve_enrollment_schedule',{p_enrollment_id:enrollment.id,p_tutor_ids:tutorIds,p_selections:selections,p_seats:Math.max(1,Math.floor(num(d.groupSize,1)))});
        if(reserveErr) throw reserveErr;
      }
    }

    const method=clean(d.paymentMethod)==='cash'?'cash':'transfer';
    if(method==='transfer'){
      if(!d.fileData) throw new Error('กรุณาแนบสลิปการชำระเงิน');
      const binary=Uint8Array.from(atob(String(d.fileData)),c=>c.charCodeAt(0));
      const rawName=clean(d.fileName)||'slip.jpg';
      const ext=(rawName.split('.').pop()||'jpg').replace(/[^a-zA-Z0-9]/g,'').toLowerCase()||'jpg';
      slipPath=`${new Date().toISOString().slice(0,7)}/${enrollment.id}.${ext}`;
      const {error:uploadErr}=await sb.storage.from('payment-slips').upload(slipPath,binary,{contentType:clean(d.mimeType)||'image/jpeg',upsert:false});
      if(uploadErr) throw uploadErr;
    }

    const {error:payErr}=await sb.from('payments').insert({
      enrollment_id:enrollment.id,
      payment_method:method,
      amount_submitted:finalAmount,
      slip_path:slipPath,
      status:'pending'
    });
    if(payErr) throw payErr;

    return json({success:true,enrollmentId:enrollment.id,receiptNo:enrollment.receipt_no,receiptToken:enrollment.receipt_token,amount:finalAmount,status:'pending'});
  } catch(err){
    console.error(err);
    // Enrollment is the parent row; deleting it rolls back reservations and payment rows.
    if(enrollmentId) await sb.from('enrollments').delete().eq('id',enrollmentId);
    if(slipPath) await sb.storage.from('payment-slips').remove([slipPath]);
    return json({success:false,message:err instanceof Error?err.message:String(err)},400);
  }
});
