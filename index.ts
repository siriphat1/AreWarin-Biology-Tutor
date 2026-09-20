const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, accept, x-supabase-api-version',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Max-Age': '86400',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json; charset=utf-8',
    },
  });

function errorText(err: unknown) {
  if (err instanceof Error) return err.message || String(err);
  if (typeof err === 'string') return err;
  try { return JSON.stringify(err); } catch { return String(err); }
}

Deno.serve(async (req) => {
  // Must run before any auth/body/business logic.
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      status: 200,
      headers: corsHeaders,
    });
  }

  if (req.method === 'GET') {
    return json({
      ok: true,
      function: 'create-group-class-enrollment-proxy',
      upstream: 'create-group-class-enrollment',
      version: 'v26.4.1',
    });
  }

  if (req.method !== 'POST') {
    return json({ success: false, message: 'Method not allowed' }, 405);
  }

  const url = Deno.env.get('SUPABASE_URL');
  const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');

  if (!url || !service) {
    return json({
      success: false,
      message: 'Supabase function environment is incomplete',
      version: 'v26.4.1',
    }, 500);
  }

  try {
    const raw = await req.text();

    let body: Record<string, unknown> = {};
    try {
      body = raw ? JSON.parse(raw) : {};
    } catch {
      return json({ success: false, message: 'Invalid JSON body' }, 400);
    }

    if (!String(body.groupClassId ?? '').trim()) {
      return json({
        success: false,
        message: 'Missing groupClassId',
        version: 'v26.4.1',
      }, 400);
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 30000);

    let upstream: Response;
    try {
      upstream = await fetch(`${url}/functions/v1/create-group-class-enrollment`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${service}`,
          'apikey': service,
        },
        body: JSON.stringify(body),
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }

    const responseText = await upstream.text();
    const contentType =
      upstream.headers.get('content-type') ||
      'application/json; charset=utf-8';

    // Keep upstream status/body but always add browser-safe CORS headers.
    return new Response(responseText, {
      status: upstream.status,
      headers: {
        ...corsHeaders,
        'Content-Type': contentType,
      },
    });
  } catch (err) {
    const message = errorText(err);
    const timeout = /abort|timeout/i.test(message);

    console.error('create-group-class-enrollment-proxy v26.4.1 failed', {
      message,
    });

    return json({
      success: false,
      message: timeout
        ? 'create-group-class-enrollment timeout'
        : `Proxy failed: ${message}`,
      version: 'v26.4.1',
    }, timeout ? 504 : 500);
  }
});
