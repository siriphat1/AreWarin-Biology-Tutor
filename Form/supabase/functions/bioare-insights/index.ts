// BioAre AI Insights Edge Function (optional feature).
// Deploy using Supabase CLI; set OPENAI_API_KEY as Supabase secret.
// Authentication: valid Supabase Auth JWT + bioare manager membership.
// Privacy: only whitelisted aggregate metrics, NEVER raw feedback, names, or contact details.
import { createClient } from 'npm:@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const reply = (obj: unknown, status = 200) => new Response(JSON.stringify(obj), {
  status, headers: { ...cors, 'Content-Type': 'application/json; charset=utf-8' },
});
const numeric = (value: unknown, max = 100000): number => {
  const n = Number(value);
  return Number.isFinite(n) && n >= 0 && n <= max ? n : 0;
};

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return reply({ error: 'Method not allowed' }, 405);
  const authorization = req.headers.get('authorization') || '';
  const token = authorization.startsWith('Bearer ') ? authorization.slice(7) : '';
  if (!token) return reply({ error: 'Authentication required' }, 401);

  const projectUrl = Deno.env.get('SUPABASE_URL') || '';
  const publishableKey = Deno.env.get('SUPABASE_PUBLISHABLE_KEY') || Deno.env.get('SUPABASE_ANON_KEY') || '';
  const openaiKey = Deno.env.get('OPENAI_API_KEY') || '';
  if (!projectUrl || !publishableKey) return reply({ error: 'Supabase env missing' }, 503);
  if (!openaiKey) return reply({ error: 'OPENAI_API_KEY is not configured' }, 503);

  const supabase = createClient(projectUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: userResult, error: userError } = await supabase.auth.getUser(token);
  if (userError || !userResult.user) return reply({ error: 'Invalid session' }, 401);
  const { data: membership, error: memberError } = await supabase
    .from('speaker_feedback_admins').select('user_id')
    .eq('user_id', userResult.user.id).maybeSingle();
  if (memberError || !membership) return reply({ error: 'Manager permission required' }, 403);

  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return reply({ error: 'Invalid JSON' }, 400); }
  const criteriaKeys = ['clarity', 'content', 'delivery', 'interaction', 'usefulness', 'overall'];
  const paceKeys = ['too_slow', 'just_right', 'too_fast'];
  const diffKeys = ['too_easy', 'just_right', 'too_hard'];
  const themeKeys = ['เร็วไป', 'เนื้อหายาก', 'สนุก/มีส่วนร่วม', 'อยากได้ตัวอย่าง', 'ชื่นชมการสอน', 'ช้าไป'];
  const obj = (x: unknown) => x && typeof x === 'object' && !Array.isArray(x) ? x as Record<string, unknown> : {};
  const criteria = obj(body.criteria), pace = obj(body.pace), difficulty = obj(body.difficulty), themes = obj(body.theme_counts);
  const count = Math.round(numeric(body.number_of_responses));
  if (count < 1) return reply({ error: 'There are no responses to summarize' }, 400);
  const sanitized = {
    count,
    average_score: numeric(body.average_score, 5),
    criteria: Object.fromEntries(criteriaKeys.map(k => [k, numeric(criteria[k], 5)])),
    pace: Object.fromEntries(paceKeys.map(k => [k, Math.round(numeric(pace[k]))])),
    difficulty: Object.fromEntries(diffKeys.map(k => [k, Math.round(numeric(difficulty[k]))])),
    theme_counts: Object.fromEntries(themeKeys.map(k => [k, Math.round(numeric(themes[k]))])),
  };
  try {
    const response = await fetch('https://api.openai.com/v1/responses', {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${openaiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: Deno.env.get('OPENAI_MODEL') || 'gpt-4.1-mini',
        max_output_tokens: 600,
        instructions: 'คุณเป็นผู้ช่วยสรุปสถิติการประเมินการบรรยายภาษาไทย เขียนสั้น กระชับ ตรงประเด็น แบ่งเป็นจุดเด่น จุดที่ควรพัฒนา และข้อเสนอแนะที่ทำได้จริง ห้ามคาดเดาผู้ตอบหรือแสดงว่าสถิติคำสำคัญคือผลการวิเคราะห์ความหมายโดยสมบูรณ์ ระบุข้อจำกัดของข้อมูลเมื่อมีผู้ตอบน้อย',
        input: 'ข้อมูลรวมที่ไม่ระบุตัวตนจากระบบ BioAre: ' + JSON.stringify(sanitized),
      }),
    });
    if (!response.ok) return reply({ error: 'AI provider unavailable' }, 502);
    const data = await response.json();
    const summary = (data.output || [])
      .flatMap((item: { content?: { type?: string; text?: string }[] }) => item.content || [])
      .filter((piece: { type?: string; text?: string }) => piece.type === 'output_text')
      .map((piece: { text?: string }) => piece.text || '').join('\n').trim();
    return summary ? reply({ summary }) : reply({ error: 'No summary returned' }, 502);
  } catch (err) {
    console.error('BioAre insights request error', err instanceof Error ? err.message : 'unknown');
    return reply({ error: 'Analysis failed' }, 502);
  }
});
