import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  let adminClient: ReturnType<typeof createClient> | null = null;
  let createdUserId: string | null = null;
  try {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) throw new Error('Server configuration missing. Check Supabase function secrets.');
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) throw new Error('Authorization token required');
    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
    if (authError || !caller) throw new Error('Invalid session');
    adminClient = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const { data: callerProfile, error: roleError } = await adminClient.from('profiles').select('id,role,status,assigned_admin_id,parent_agent_id').eq('id', caller.id).single();
    if (roleError || callerProfile?.status !== 'active') throw new Error('Active staff profile required');
    const body = await req.json();
    const role = String(body.role || '');
    if (!['admin', 'agent', 'sub_agent'].includes(role)) throw new Error('Unsupported account role');
    if (role === 'admin' && callerProfile.role !== 'super_admin') throw new Error('Only Super Admin can create Admins');
    if (role === 'agent' && !['admin', 'super_admin'].includes(callerProfile.role)) throw new Error('Only Admin or Super Admin can create Agents');
    if (role === 'sub_agent' && !['agent', 'sub_agent', 'admin', 'super_admin'].includes(callerProfile.role)) throw new Error('Only authorized staff can create Sub-Agent logins');
    const email = String(body.email || '').trim().toLowerCase();
    const full_name = String(body.full_name || '').trim();
    const mobile = body.mobile ? String(body.mobile).trim() : null;
    const password = typeof body.password === 'string' ? body.password : '';
    if (!email || !full_name) throw new Error('Full name and email are required');
    if (password.length < 10) throw new Error('Password must be at least 10 characters long');

    let parent_agent_id: string | null = null;
    let assigned_admin_id: string | null = null;
    if (role === 'sub_agent') {
      parent_agent_id = String(body.parent_agent_id || (['agent', 'sub_agent'].includes(callerProfile.role) ? caller.id : '')).trim() || null;
      if (!parent_agent_id) throw new Error('Select the parent Main Agent before creating a Sub-Agent');
      const { data: parent, error: parentError } = await adminClient.from('profiles').select('id,role,status,assigned_admin_id').eq('id', parent_agent_id).single();
      if (parentError || !parent || !['agent', 'sub_agent'].includes(parent.role) || parent.status !== 'active') throw new Error('Selected parent must be an active Agent or Sub-Agent');
      if (['agent', 'sub_agent'].includes(callerProfile.role) && parent.id !== caller.id) throw new Error('Agents can create Sub-Agents only under themselves');
      if (callerProfile.role === 'admin' && parent.assigned_admin_id !== caller.id) throw new Error('Main Agent is outside your assigned admin team');
      assigned_admin_id = parent.assigned_admin_id || null;
      const sourceMemberId = String(body.source_member_id || '').trim();
      if (sourceMemberId) {
        const { data: sourceMember, error: sourceMemberError } = await adminClient
          .from('members').select('id,assigned_agent_id').eq('id', sourceMemberId).single();
        if (sourceMemberError || !sourceMember) throw new Error('Selected source member was not found');
        if (sourceMember.assigned_agent_id !== parent_agent_id) {
          throw new Error('The source member must be assigned to the selected parent Agent/Sub-Agent');
        }
        const { data: existingLinkedProfile, error: linkedProfileError } = await adminClient
          .from('profiles').select('id').eq('source_member_id', sourceMemberId).maybeSingle();
        if (linkedProfileError) throw new Error('Could not validate existing Sub-Agent linkage');
        if (existingLinkedProfile) throw new Error('This member already has a linked Sub-Agent login');
        if (callerProfile.role === 'admin' && parent.assigned_admin_id !== caller.id) {
          throw new Error('Source member is outside your assigned admin team');
        }
        if (['agent', 'sub_agent'].includes(callerProfile.role) && parent.id !== caller.id) {
          throw new Error('You can only promote a member assigned to your own account');
        }
      }
    } else if (role === 'agent' && callerProfile.role === 'admin') {
      assigned_admin_id = caller.id;
    }

    const { data: createdData, error: createError } = await adminClient.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name, mobile },
    });
    if (createError || !createdData.user) throw new Error(createError?.message || 'Could not create account');
    createdUserId = createdData.user.id;
    const profileUpdate: Record<string, unknown> = {
      full_name, email, mobile, role, status: 'active', assigned_admin_id, parent_agent_id, source_member_id: role === 'sub_agent' ? (String(body.source_member_id || '').trim() || null) : null,
    };
    const { error: updateError } = await adminClient.from('profiles').update(profileUpdate).eq('id', createdUserId);
    if (updateError) throw new Error('Account setup failed: ' + updateError.message);
    const { error: auditError } = await adminClient.from('audit_logs').insert({
      actor_id: caller.id, action: role + '.created', entity_type: 'profile',
      entity_id: createdUserId, details: { email, email_invitation_sent: false, parent_agent_id },
    });
    if (auditError) console.error('Audit log insert failed', auditError.message);
    return new Response(JSON.stringify({ ok: true, user_id: createdUserId, role, parent_agent_id, message: 'Account created. No invitation email was sent; provide credentials securely.' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    if (adminClient && createdUserId) {
      try { await adminClient.auth.admin.deleteUser(createdUserId); } catch { /* rollback best effort */ }
    }
    const message = e instanceof Error ? e.message : 'Unexpected error';
    return new Response(JSON.stringify({ error: message }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
