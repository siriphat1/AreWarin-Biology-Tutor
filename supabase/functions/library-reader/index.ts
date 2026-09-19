import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type"};
Deno.serve(async(req)=>{
  if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
  try{
    const url=Deno.env.get("SUPABASE_URL")!, anon=Deno.env.get("SUPABASE_ANON_KEY")!, service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth=req.headers.get("Authorization")||"";
    if(!auth.startsWith("Bearer "))return new Response(JSON.stringify({ok:false,message:"Sign in required"}),{status:401,headers:{...cors,"Content-Type":"application/json"}});
    const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}}});
    const {data:{user},error:uerr}=await userClient.auth.getUser();
    if(uerr||!user)return new Response(JSON.stringify({ok:false,message:"Invalid session"}),{status:401,headers:{...cors,"Content-Type":"application/json"}});
    const body=await req.json(); const itemId=String(body?.item_id||"");
    if(!itemId)return new Response(JSON.stringify({ok:false,message:"Missing item_id"}),{status:400,headers:{...cors,"Content-Type":"application/json"}});
    const admin=createClient(url,service,{auth:{persistSession:false}});
    const {data:allowed,error:aerr}=await admin.rpc("library_edge_authorize",{p_user_id:user.id,p_item_id:itemId});
    if(aerr||!allowed?.ok)return new Response(JSON.stringify({ok:false,message:aerr?.message||allowed?.message||"Access denied"}),{status:403,headers:{...cors,"Content-Type":"application/json"}});
    const {data:signed,error:serr}=await admin.storage.from("library-books").createSignedUrl(allowed.file_path,600,{download:false});
    if(serr||!signed?.signedUrl)throw serr||new Error("Could not create reader URL");
    return new Response(JSON.stringify({ok:true,signed_url:signed.signedUrl,title:allowed.title,watermark:allowed.watermark,last_page:allowed.last_page||1,expires_in:600}),{headers:{...cors,"Content-Type":"application/json","Cache-Control":"no-store"}});
  }catch(e){return new Response(JSON.stringify({ok:false,message:e?.message||String(e)}),{status:500,headers:{...cors,"Content-Type":"application/json"}})}
});
