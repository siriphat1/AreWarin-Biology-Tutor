import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders={
  'Access-Control-Allow-Origin':'*',
  'Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods':'POST, OPTIONS'
};
const json=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{...corsHeaders,'Content-Type':'application/json; charset=utf-8'}});

Deno.serve(async req=>{
  if(req.method==='OPTIONS') return new Response('ok',{headers:corsHeaders});
  if(req.method!=='POST') return json({success:false,message:'Method not allowed'},405);
  const url=Deno.env.get('SUPABASE_URL');
  const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if(!url||!service) return json({success:false,message:'Supabase function environment is incomplete'},500);
  const sb=createClient(url,service,{auth:{persistSession:false}});
  try{
    const {receiptToken}=await req.json();
    if(!receiptToken) throw new Error('ไม่พบรหัสใบเสร็จ');
    const {data:enrollment,error:eErr}=await sb.from('enrollments').select('*').eq('receipt_token',receiptToken).single();
    if(eErr||!enrollment) throw new Error('ไม่พบใบเสร็จ');
    const [pRes,rRes]=await Promise.all([
      sb.from('payments').select('*').eq('enrollment_id',enrollment.id).maybeSingle(),
      sb.from('receipt_settings').select('*').eq('id',1).single()
    ]);
    if(pRes.error) throw pRes.error;
    if(rRes.error) throw rRes.error;
    const settings=rRes.data||{};
    let logoUrl:string|null=null, signatureUrl:string|null=null;
    if(settings.logo_path){const {data}=await sb.storage.from('receipt-assets').createSignedUrl(settings.logo_path,300);logoUrl=data?.signedUrl||null;}
    if(settings.signature_path){const {data}=await sb.storage.from('receipt-assets').createSignedUrl(settings.signature_path,300);signatureUrl=data?.signedUrl||null;}
    return json({success:true,enrollment,payment:pRes.data||null,settings,logoUrl,signatureUrl});
  }catch(err){
    console.error(err);
    return json({success:false,message:err instanceof Error?err.message:String(err)},404);
  }
});
