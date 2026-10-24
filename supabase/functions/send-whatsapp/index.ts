import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  let logId: string | null = null;
  try {
    const url = Deno.env.get('SUPABASE_URL')!;
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const token = Deno.env.get('WHATSAPP_ACCESS_TOKEN');
    const phoneNumberId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
    if (!token || !phoneNumberId) throw new Error('WhatsApp secrets are not configured');
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) throw new Error('Authorization token required');
    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
    if (authError || !caller) throw new Error('Invalid session');
    const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const { data: profile } = await admin.from('profiles').select('id,role,status').eq('id', caller.id).single();
    if (!profile || profile.status !== 'active' || !['admin','super_admin','agent'].includes(profile.role)) throw new Error('Only active authorized staff can send business notifications');
    const body = await req.json();
    let member: any; let templateName: string; let params: string[] = []; let relatedPaymentId: string | null = null; let relatedDrawId: string | null = null; let manualMessage: string | null = null; let recipientType: string | null = null; let recipientRecordId: string | null = null;
    if (body.type === 'payment') {
      const { data: payment, error } = await admin.from('payment_entries').select('id,amount,payment_date,installment_month,status,member_id').eq('id', body.payment_id).single();
      if (error || !payment || payment.status !== 'approved') throw new Error('Payment must be approved before confirmation is sent');
      const { data: m } = await admin.from('members').select('id,full_name,mobile,member_code,assigned_agent_id').eq('id', payment.member_id).single();
      if (profile.role === 'admin') {
        const { data: teamAgent } = await admin.from('agents').select('id').eq('id', m?.assigned_agent_id).eq('admin_id', caller.id).maybeSingle();
        if (!teamAgent) throw new Error('Payment is outside your assigned team');
      }
      member = m; if (!member?.mobile) throw new Error('Member mobile number is missing');
      templateName = Deno.env.get('WHATSAPP_PAYMENT_TEMPLATE') || 'payment_confirmation';
      params = [member.full_name, member.member_code, String(payment.amount), payment.installment_month, payment.payment_date, payment.id.slice(0, 8)];
      relatedPaymentId = payment.id;
    } else if (body.type === 'winner') {
      const { data: draw, error } = await admin.from('draws').select('id,title,gift_id,status,winner_member_id').eq('id', body.draw_id).single();
      if (error || !draw || draw.status !== 'completed' || draw.winner_member_id !== body.member_id) throw new Error('Winner must be declared before notification');
      const { data: m } = await admin.from('members').select('id,full_name,mobile,member_code,assigned_agent_id').eq('id', body.member_id).single();
      if (profile.role === 'admin') {
        const { data: teamAgent } = await admin.from('agents').select('id').eq('id', m?.assigned_agent_id).eq('admin_id', caller.id).maybeSingle();
        if (!teamAgent) throw new Error('Winner is outside your assigned team');
      }
      member = m; if (!member?.mobile) throw new Error('Winner mobile number is missing');
      const { data: gift } = await admin.from('gifts').select('name').eq('id', draw.gift_id).maybeSingle();
      templateName = Deno.env.get('WHATSAPP_WINNER_TEMPLATE') || 'draw_winner_announcement';
      params = [member.full_name, member.member_code, draw.title, gift?.name || 'Prize gift'];
      relatedDrawId = draw.id;
    } else if (body.type === 'manual') {
      if (body.consent_confirmed !== true) throw new Error('Recipient consent confirmation is required');
      if (typeof body.message !== 'string' || !body.message.trim() || body.message.trim().length > 4096) throw new Error('Message must contain 1–4096 characters');
      recipientType = body.recipient_type;
      recipientRecordId = String(body.recipient_id || '');
      manualMessage = body.message.trim();
      if (!['member', 'agent'].includes(recipientType) || !recipientRecordId) throw new Error('Choose a valid saved Member or Agent');
      if (recipientType === 'member') {
        const { data: m, error } = await admin.from('members').select('id,full_name,mobile,member_code,assigned_agent_id').eq('id', recipientRecordId).single();
        if (error || !m) throw new Error('Member was not found');
        if (profile.role === 'admin') {
          const { data: teamAgent } = await admin.from('agents').select('id').eq('id', m.assigned_agent_id).eq('admin_id', caller.id).maybeSingle();
          if (!teamAgent) throw new Error('Member is outside your assigned team');
        } else if (profile.role === 'agent' && m.assigned_agent_id !== caller.id) {
          throw new Error('Member is outside your assigned members');
        }
        member = m;
      } else {
        const { data: a, error } = await admin.from('agents').select('id,full_name,mobile,agent_code,admin_id,status').eq('id', recipientRecordId).single();
        if (error || !a || a.status !== 'active') throw new Error('Active Agent was not found');
        if (profile.role === 'admin' && a.admin_id !== caller.id) throw new Error('Agent is outside your assigned team');
        member = a;
      }
      if (!member?.mobile) throw new Error('The selected record has no saved mobile number');
      templateName = 'manual_text';
    } else throw new Error('Unsupported notification type');
    const logPayload: Record<string, unknown> = { member_id: recipientType === 'member' ? member.id : (body.type === 'manual' ? null : member.id), recipient_phone: member.mobile, template_name: templateName, related_payment_id: relatedPaymentId, related_draw_id: relatedDrawId, status: 'queued', attempt_count: 1 };
    if (body.type === 'manual') Object.assign(logPayload, { recipient_type: recipientType, recipient_record_id: recipientRecordId, message_body: manualMessage, manual_consent_confirmed: true });
    const { data: log, error: logError } = await admin.from('notification_logs').insert(logPayload).select('id').single();
    if (logError) throw new Error(logError.message); logId = log.id;
    let phone = String(member.mobile).replace(/[^0-9]/g, '');
    if (phone.length === 10) phone = `${Deno.env.get('WHATSAPP_DEFAULT_COUNTRY_CODE') || '91'}${phone}`;
    if (phone.length < 10 || phone.length > 15) throw new Error('Saved mobile number is invalid; include country code if needed');
    const apiVersion = Deno.env.get('WHATSAPP_API_VERSION') || 'v21.0';
    const outboundPayload = body.type === 'manual'
      ? { messaging_product: 'whatsapp', to: phone, type: 'text', text: { preview_url: false, body: manualMessage } }
      : { messaging_product: 'whatsapp', to: phone, type: 'template', template: { name: templateName, language: { code: Deno.env.get('WHATSAPP_TEMPLATE_LANGUAGE') || 'en' }, components: [{ type: 'body', parameters: params.map(text => ({ type: 'text', text })) }] } };
    const response = await fetch(`https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`, {
      method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(outboundPayload)
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result?.error?.message || `WhatsApp API returned ${response.status}`);
    await admin.from('notification_logs').update({ status: 'sent', provider_message_id: result?.messages?.[0]?.id || null, updated_at: new Date().toISOString() }).eq('id', logId);
    return new Response(JSON.stringify({ ok: true, status: 'sent', message_id: result?.messages?.[0]?.id || null }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    const message = e instanceof Error ? e.message : 'Unexpected error';
    if (logId) { const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { autoRefreshToken: false, persistSession: false } }); await admin.from('notification_logs').update({ status: 'failed', error_message: message, updated_at: new Date().toISOString() }).eq('id', logId); }
    return new Response(JSON.stringify({ error: message }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
