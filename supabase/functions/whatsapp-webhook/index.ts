import { createClient } from 'npm:@supabase/supabase-js@2.57.0';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

async function verifySignature(rawBody: string, signature: string, appSecret: string): Promise<boolean> {
  if (!signature.startsWith('sha256=')) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(appSecret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const digest = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(rawBody));
  const expected = 'sha256=' + Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('');
  return constantTimeEqual(signature.toLowerCase(), expected);
}

Deno.serve(async (req: Request) => {
  const verifyToken = Deno.env.get('WHATSAPP_WEBHOOK_VERIFY_TOKEN');
  if (req.method === 'GET') {
    const url = new URL(req.url);
    const mode = url.searchParams.get('hub.mode');
    const token = url.searchParams.get('hub.verify_token');
    const challenge = url.searchParams.get('hub.challenge');
    if (mode === 'subscribe' && verifyToken && token && constantTimeEqual(token, verifyToken) && challenge) {
      return new Response(challenge, { status: 200, headers: { 'Content-Type': 'text/plain' } });
    }
    return new Response('Webhook verification failed', { status: 403 });
  }
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405);

  const appSecret = Deno.env.get('WHATSAPP_APP_SECRET');
  const serviceUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!appSecret || !serviceUrl || !serviceKey) return json({ error: 'Webhook secrets are not configured' }, 503);

  const rawBody = await req.text();
  const signature = req.headers.get('X-Hub-Signature-256') || '';
  if (!(await verifySignature(rawBody, signature, appSecret))) return json({ error: 'Invalid webhook signature' }, 401);

  let payload: any;
  try { payload = JSON.parse(rawBody); } catch { return json({ error: 'Invalid JSON payload' }, 400); }
  const admin = createClient(serviceUrl, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const allowedStatuses = new Set(['sent', 'delivered', 'read', 'failed']);
  let processed = 0;

  for (const entry of payload?.entry || []) {
    for (const change of entry?.changes || []) {
      for (const item of change?.value?.statuses || []) {
        const messageId = typeof item?.id === 'string' ? item.id : '';
        const providerStatus = typeof item?.status === 'string' ? item.status : '';
        if (!messageId || !allowedStatuses.has(providerStatus)) continue;
        const errorText = providerStatus === 'failed'
          ? (item?.errors || []).map((e: any) => e?.error_data?.details || e?.title || e?.message || 'Provider delivery failed').join('; ').slice(0, 1000)
          : null;
        const { error } = await admin.from('notification_logs').update({
          status: providerStatus,
          error_message: errorText,
          updated_at: new Date().toISOString(),
        }).eq('provider_message_id', messageId);
        if (error) return json({ error: 'Could not update delivery status' }, 500);
        processed++;
      }
    }
  }
  return json({ ok: true, processed });
});
