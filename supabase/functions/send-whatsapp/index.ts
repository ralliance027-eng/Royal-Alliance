import { createClient } from 'npm:@supabase/supabase-js@2.57.0';
import { corsHeadersFor, isOriginAllowed } from '../_shared/cors.ts';

type StaffProfile = { id: string; role: string; status: string };
type MemberRecord = {
  id: string;
  full_name: string;
  mobile: string | null;
  member_code?: string | null;
  assigned_agent_id?: string | null;
};

function jsonResponse(req: Request, body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeadersFor(req), 'Content-Type': 'application/json' },
  });
}

async function isInAgentTree(admin: any, rootId: string, candidateId: string): Promise<boolean> {
  if (rootId === candidateId) return true;
  const { data, error } = await admin.rpc('is_agent_in_tree', {
    p_root: rootId,
    p_candidate: candidateId,
  });
  if (error) throw new Error(`Could not verify Agent team scope: ${error.message}`);
  return data === true;
}

async function assertMemberScope(
  admin: any,
  profile: StaffProfile,
  callerId: string,
  assignedAgentId: string | null | undefined,
): Promise<void> {
  if (profile.role === 'super_admin') return;
  if (!assignedAgentId) throw new Error('Member has no assigned Agent');
  if (profile.role === 'admin') {
    const { data, error } = await admin.from('agents')
      .select('id').eq('id', assignedAgentId).eq('admin_id', callerId).maybeSingle();
    if (error) throw new Error(`Could not verify Admin team scope: ${error.message}`);
    if (!data) throw new Error('Member is outside your assigned team');
    return;
  }
  if (profile.role === 'agent' || profile.role === 'sub_agent') {
    if (!(await isInAgentTree(admin, callerId, assignedAgentId))) {
      throw new Error('Member is outside your assigned Agent/Sub-Agent tree');
    }
    return;
  }
  throw new Error('Your role cannot send WhatsApp notifications');
}

async function assertAgentScope(
  admin: any,
  profile: StaffProfile,
  callerId: string,
  targetAgentId: string,
  targetAdminId: string | null,
): Promise<void> {
  if (profile.role === 'super_admin') return;
  if (profile.role === 'admin') {
    if (targetAdminId !== callerId) throw new Error('Agent is outside your assigned team');
    return;
  }
  if (profile.role === 'agent' || profile.role === 'sub_agent') {
    if (!(await isInAgentTree(admin, callerId, targetAgentId))) {
      throw new Error('Agent is outside your assigned Agent/Sub-Agent tree');
    }
    return;
  }
  throw new Error('Your role cannot send WhatsApp notifications');
}

Deno.serve(async (req: Request) => {
  if (!isOriginAllowed(req)) return jsonResponse(req, { error: 'Origin is not allowed' }, 403);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeadersFor(req) });
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Method not allowed' }, 405);

  let logId: string | null = null;
  let admin: any = null;
  let providerAccepted = false;
  try {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const token = Deno.env.get('WHATSAPP_ACCESS_TOKEN');
    const phoneNumberId = Deno.env.get('WHATSAPP_PHONE_NUMBER_ID');
    if (!url || !anonKey || !serviceKey) throw new Error('Supabase function secrets are incomplete');
    if (!token || !phoneNumberId) throw new Error('WhatsApp provider secrets are not configured');

    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) throw new Error('Authorization token required');
    const callerClient = createClient(url, anonKey, {
      global: { headers: { Authorization: authHeader } },
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
    if (authError || !caller) throw new Error('Invalid session');

    admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const { data: profile, error: profileError } = await admin.from('profiles')
      .select('id,role,status').eq('id', caller.id).single();
    if (profileError || !profile || profile.status !== 'active' ||
      !['admin', 'super_admin', 'agent', 'sub_agent'].includes(profile.role)) {
      throw new Error('Only active authorized staff can send business notifications');
    }

    const body = await req.json();
    let recipient: MemberRecord | null = null;
    let templateName = '';
    let params: string[] = [];
    let relatedPaymentId: string | null = null;
    let relatedDrawId: string | null = null;
    let manualMessage: string | null = null;
    let recipientType: 'member' | 'agent' | null = null;
    let recipientRecordId: string | null = null;

    if (body.type === 'payment') {
      const { data: payment, error } = await admin.from('payment_entries')
        .select('id,amount,payment_date,installment_month,status,member_id')
        .eq('id', body.payment_id).single();
      if (error || !payment || payment.status !== 'approved') {
        throw new Error('Payment must be approved before confirmation is sent');
      }
      const { data: member, error: memberError } = await admin.from('members')
        .select('id,full_name,mobile,member_code,assigned_agent_id')
        .eq('id', payment.member_id).single();
      if (memberError || !member) throw new Error('Payment member was not found');
      await assertMemberScope(admin, profile, caller.id, member.assigned_agent_id);
      if (!member.mobile) throw new Error('Member mobile number is missing');
      recipient = member;
      templateName = Deno.env.get('WHATSAPP_PAYMENT_TEMPLATE') || 'payment_confirmation';
      params = [member.full_name, member.member_code || '', String(payment.amount),
        payment.installment_month || '', payment.payment_date || '', payment.id.slice(0, 8)];
      relatedPaymentId = payment.id;
      recipientType = 'member';
      recipientRecordId = member.id;
    } else if (body.type === 'winner') {
      const { data: draw, error } = await admin.from('draws')
        .select('id,title,gift_id,status,winner_member_id').eq('id', body.draw_id).single();
      if (error || !draw || draw.status !== 'completed' || draw.winner_member_id !== body.member_id) {
        throw new Error('Winner must be declared before notification');
      }
      const { data: member, error: memberError } = await admin.from('members')
        .select('id,full_name,mobile,member_code,assigned_agent_id')
        .eq('id', body.member_id).single();
      if (memberError || !member) throw new Error('Winner member was not found');
      await assertMemberScope(admin, profile, caller.id, member.assigned_agent_id);
      if (!member.mobile) throw new Error('Winner mobile number is missing');
      const { data: gift } = await admin.from('gifts').select('name').eq('id', draw.gift_id).maybeSingle();
      recipient = member;
      templateName = Deno.env.get('WHATSAPP_WINNER_TEMPLATE') || 'draw_winner_announcement';
      params = [member.full_name, member.member_code || '', draw.title, gift?.name || 'Prize gift'];
      relatedDrawId = draw.id;
      recipientType = 'member';
      recipientRecordId = member.id;
    } else if (body.type === 'manual') {
      if (body.consent_confirmed !== true) throw new Error('Recipient consent confirmation is required');
      if (typeof body.message !== 'string' || !body.message.trim() || body.message.trim().length > 4096) {
        throw new Error('Message must contain 1–4096 characters');
      }
      if (!['member', 'agent'].includes(body.recipient_type)) throw new Error('Choose a valid saved Member or Agent');
      recipientType = body.recipient_type;
      recipientRecordId = String(body.recipient_id || '').trim();
      if (!recipientRecordId) throw new Error('Choose a valid saved Member or Agent');
      manualMessage = body.message.trim();

      if (recipientType === 'member') {
        const { data: member, error } = await admin.from('members')
          .select('id,full_name,mobile,member_code,assigned_agent_id')
          .eq('id', recipientRecordId).single();
        if (error || !member) throw new Error('Member was not found');
        await assertMemberScope(admin, profile, caller.id, member.assigned_agent_id);
        recipient = member;
      } else {
        const { data: agent, error } = await admin.from('agents')
          .select('id,full_name,mobile,agent_code,admin_id,status')
          .eq('id', recipientRecordId).single();
        if (error || !agent || agent.status !== 'active') throw new Error('Active Agent was not found');
        await assertAgentScope(admin, profile, caller.id, agent.id, agent.admin_id);
        recipient = { id: agent.id, full_name: agent.full_name, mobile: agent.mobile, member_code: agent.agent_code };
      }
      templateName = 'manual_text';
    } else {
      throw new Error('Unsupported notification type');
    }

    if (!recipient?.mobile) throw new Error('The selected record has no saved mobile number');
    let phone = String(recipient.mobile).replace(/[^0-9]/g, '');
    if (phone.length === 10) phone = `${Deno.env.get('WHATSAPP_DEFAULT_COUNTRY_CODE') || '91'}${phone}`;
    if (phone.length < 10 || phone.length > 15) throw new Error('Saved mobile number is invalid; include country code if needed');

    const logPayload: Record<string, unknown> = {
      member_id: recipientType === 'member' ? recipient.id : null,
      recipient_phone: phone,
      template_name: templateName,
      related_payment_id: relatedPaymentId,
      related_draw_id: relatedDrawId,
      status: 'queued',
      attempt_count: 1,
      recipient_type: recipientType,
      recipient_record_id: recipientRecordId,
    };
    if (body.type === 'manual') {
      Object.assign(logPayload, { message_body: manualMessage, manual_consent_confirmed: true });
    }
    const { data: log, error: logError } = await admin.from('notification_logs')
      .insert(logPayload).select('id').single();
    if (logError || !log) throw new Error(`Could not create notification log: ${logError?.message || 'Unknown error'}`);
    logId = log.id;

    const apiVersion = Deno.env.get('WHATSAPP_API_VERSION') || 'v21.0';
    const outboundPayload = body.type === 'manual'
      ? { messaging_product: 'whatsapp', to: phone, type: 'text', text: { preview_url: false, body: manualMessage } }
      : { messaging_product: 'whatsapp', to: phone, type: 'template', template: {
          name: templateName,
          language: { code: Deno.env.get('WHATSAPP_TEMPLATE_LANGUAGE') || 'en' },
          components: [{ type: 'body', parameters: params.map((value) => ({ type: 'text', text: value })) }],
        } };

    const response = await fetch(`https://graph.facebook.com/${apiVersion}/${phoneNumberId}/messages`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(outboundPayload),
      signal: AbortSignal.timeout(15000),
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      const providerMessage = result?.error?.message || `WhatsApp API returned ${response.status}`;
      await admin.from('notification_logs').update({ status: 'failed', error_message: providerMessage, updated_at: new Date().toISOString() }).eq('id', logId);
      logId = null;
      return jsonResponse(req, { error: providerMessage }, 502);
    }

    providerAccepted = true;
    const providerMessageId = result?.messages?.[0]?.id || null;
    const { error: updateError } = await admin.from('notification_logs').update({
      status: 'sent', provider_message_id: providerMessageId, error_message: null,
      updated_at: new Date().toISOString(),
    }).eq('id', logId);
    if (updateError) {
      await admin.from('notification_logs').update({ status: 'sent_unconfirmed', error_message: updateError.message, updated_at: new Date().toISOString() }).eq('id', logId);
      logId = null;
      return jsonResponse(req, { ok: true, status: 'sent_unconfirmed', message: 'Provider accepted the message; delivery status is awaiting webhook reconciliation.' }, 202);
    }
    logId = null;
    return jsonResponse(req, { ok: true, status: 'sent', message_id: providerMessageId });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Unexpected error';
    if (logId && admin) {
      await admin.from('notification_logs').update({ status: providerAccepted ? 'sent_unconfirmed' : 'failed', error_message: message, updated_at: new Date().toISOString() }).eq('id', logId);
    }
    const status = /Invalid session|Authorization token required/.test(message) ? 401
      : /Only active|outside your|cannot send|not authorized|consent confirmation/.test(message) ? 403
      : 400;
    return jsonResponse(req, { error: message }, status);
  }
});
