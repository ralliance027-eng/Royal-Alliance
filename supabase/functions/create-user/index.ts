import { createClient } from 'npm:@supabase/supabase-js@2';
import { corsHeaders } from '../_shared/cors.ts';
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return new Response(JSON.stringify({ error: 'Method not allowed' }), { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  try {
    const url = Deno.env.get('SUPABASE_URL');
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !anonKey || !serviceKey) {
      throw new Error('Server configuration missing. Check Supabase function secrets; never place service-role keys in the browser.');
    }
    const authHeader = req.headers.get('Authorization') || '';
    if (!authHeader.startsWith('Bearer ')) throw new Error('Authorization token required');
    const callerClient = createClient(url, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: { user: caller }, error: authError } = await callerClient.auth.getUser();
    if (authError || !caller) throw new Error('Invalid session');
    const adminClient = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
    const { data: callerProfile, error: roleError } = await adminClient.from('profiles').select('id,role,status').eq('id', caller.id).single();
    if (roleError || callerProfile?.status !== 'active') throw new Error('Active staff profile required');
    const body = await req.json();
    const role = body.role;
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
    // Create the Auth account directly. This deliberately does not use inviteUserByEmail,
    // so Supabase sends no invitation email. The account is immediately confirmed.
    const { data: createdData, error: createError } = await adminClient.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name, mobile },
    });
    if (createError || !createdData.user) throw new Error(createError?.message || 'Could not create account');
    const userId = createdData.user.id;
    let parent_agent_id: string | null = null;
    let assigned_admin_id: string | null = null;
    if (role === 'sub_agent') {
      parent_agent_id = String(body.parent_agent_id || (['agent', 'sub_agent'].includes(callerProfile.role) ? caller.id : '')).trim() || null;
      if (!parent_agent_id) throw new Error('Select the parent Main Agent before creating a Sub-Agent');
      const { data: parent, error: parentError } = await adminClient.from('profiles').select('id,role,status,assigned_admin_id,parent_agent_id').eq('id', parent_agent_id).single();
      if (parentError || !parent || !['agent', 'sub_agent'].includes(parent.role) || parent.status !== 'active') throw new Error('Selected parent must be an active Agent or Sub-Agent');
      if (['agent', 'sub_agent'].includes(callerProfile.role) && parent.id !== caller.id) throw new Error('Agents can create Sub-Agents only under themselves');
      if (callerProfile.role === 'admin' && parent.assigned_admin_id !== caller.id) throw new Error('Main Agent is outside your assigned admin team');
      assigned_admin_id = parent.assigned_admin_id || null;
      const sourceMemberId = String(body.source_member_id || '').trim();
      if (sourceMemberId) {
        const { data: sourceMember, error: sourceMemberError } = await adminClient.from('members').select('id,assigned_agent_id').eq('id', sourceMemberId).single();
        if (sourceMemberError || !sourceMember) throw new Error('Selected source member was not found');
        if (sourceMember.assigned_agent_id !== parent_agent_id) throw new Error('To promote this member, select their currently assigned Agent/Sub-Agent as the parent');
        const { data: alreadyPromoted } = await adminClient.from('profiles').select('id').eq('source_member_id', sourceMemberId).maybeSingle();
        if (alreadyPromoted) throw new Error('This member already has a linked Sub-Agent login');
        if (callerProfile.role === 'admin' && parent.assigned_admin_id !== caller.id) throw new Error('Source member is outside your assigned admin team');
        if (['agent', 'sub_agent'].includes(callerProfile.role) && parent.id !== caller.id) throw new Error('You can only promote a member assigned to your own account');
      }
    } else if (role === 'agent' && callerProfile.role === 'admin') { assigned_admin_id = caller.id; }
    const sourceMemberId = role === 'sub_agent' && body.source_member_id ? String(body.source_member_id) : null;
    if (sourceMemberId) {
      const { data: sourceMember, error: sourceMemberError } = await adminClient.from('members').select('id,assigned_agent_id,full_name,mobile').eq('id', sourceMemberId).single();
      if (sourceMemberError || !sourceMember || sourceMember.assigned_agent_id !== parent_agent_id) {
        await adminClient.auth.admin.deleteUser(userId);
        throw new Error('Selected member must belong directly to the chosen parent Agent/Sub-Agent before promotion.');
      }
    }
    const profileUpdate: Record<string, unknown> = { full_name, email, mobile, role, status: 'active', assigned_admin_id, parent_agent_id, source_member_id: role === 'sub_agent' ? (String(body.source_member_id || '').trim() || null) : null, source_member_id: sourceMemberId };
    const { error: updateError } = await adminClient.from('profiles').update(profileUpdate).eq('id', userId);
    if (updateError) {
      await adminClient.auth.admin.deleteUser(userId);
      throw new Error(`Account setup failed; newly created account was rolled back: ${updateError.message}`);
    }
    await adminClient.from('audit_logs').insert({ actor_id: caller.id, action: `${role}.created`, entity_type: 'profile', entity_id: userId, details: { email, email_invitation_sent: false, parent_agent_id, source_member_id: sourceMemberId } });
    return new Response(JSON.stringify({ ok: true, user_id: userId, role, message: 'Account created.' }), { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  } catch (e) {
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : 'Unexpected error' }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });
  }
});
