-- Royal Alliance V69: secure member edit + assignment workflow.
-- Assignment changes are blocked once payment history exists to protect financial attribution.
create or replace function public.update_member_record(
  p_member_id uuid,
  p_full_name text,
  p_mobile text,
  p_address text,
  p_nominee_name text,
  p_nominee_mobile text,
  p_joining_date date,
  p_installment_amount numeric,
  p_installment_frequency text,
  p_assigned_agent_id uuid
) returns public.members
language plpgsql security definer set search_path=public,auth as $$
declare
  v_role text;
  v_member public.members%rowtype;
  v_target_role text;
  v_target_admin uuid;
  v_old_agent uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_role := public.current_app_role();
  if coalesce(v_role,'') not in ('super_admin','admin','agent','sub_agent') then
    raise exception 'Not authorized to edit members';
  end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'Member name is required'; end if;
  if nullif(trim(p_mobile),'') is null then raise exception 'Mobile number is required'; end if;
  if coalesce(p_installment_amount,0) < 0 then raise exception 'Installment amount cannot be negative'; end if;
  if coalesce(p_installment_frequency,'monthly') not in ('monthly','yearly','one_time') then raise exception 'Invalid installment frequency'; end if;

  select * into v_member from public.members where id=p_member_id for update;
  if not found then raise exception 'Member not found'; end if;
  v_old_agent := v_member.assigned_agent_id;

  -- Caller must already be authorized for the member's current assignment.
  if v_role='admin' and not public.is_admin_of_agent(v_old_agent) then raise exception 'Member is outside your assigned team'; end if;
  if v_role='agent' and v_old_agent<>auth.uid() and not exists(select 1 from public.profiles s where s.id=v_old_agent and s.role='sub_agent' and s.parent_agent_id=auth.uid()) then raise exception 'Member is outside your Agent/Sub-Agent team'; end if;
  if v_role='sub_agent' and v_old_agent<>auth.uid() then raise exception 'Member is outside your Sub-Agent account'; end if;

  if p_assigned_agent_id is null then raise exception 'Select an Agent or Sub-Agent'; end if;
  select role, assigned_admin_id into v_target_role,v_target_admin from public.profiles where id=p_assigned_agent_id and status='active';
  if not found or v_target_role not in ('agent','sub_agent') then raise exception 'Selected Agent/Sub-Agent is not an active account'; end if;
  if v_role='admin' and not public.is_admin_of_agent(p_assigned_agent_id) then raise exception 'You can assign only to agents in your team'; end if;
  if v_role='agent' and p_assigned_agent_id<>auth.uid() and not exists(select 1 from public.profiles s where s.id=p_assigned_agent_id and s.role='sub_agent' and s.parent_agent_id=auth.uid() and s.status='active') then raise exception 'You can assign only to yourself or your own active Sub-Agents'; end if;
  if v_role='sub_agent' and p_assigned_agent_id<>auth.uid() then raise exception 'Sub-Agent can assign only to their own account'; end if;

  if p_assigned_agent_id<>v_old_agent and exists(select 1 from public.payment_entries where member_id=p_member_id) then
    raise exception 'This member has payment history. Reassignment is locked to preserve payment and commission audit history.';
  end if;

  update public.members set
    full_name=trim(p_full_name),
    mobile=regexp_replace(trim(p_mobile),'[^0-9]','','g'),
    address=nullif(trim(coalesce(p_address,'')),''),
    nominee_name=nullif(trim(coalesce(p_nominee_name,'')),''),
    nominee_mobile=nullif(trim(coalesce(p_nominee_mobile,'')),''),
    joining_date=coalesce(p_joining_date,joining_date),
    installment_amount=coalesce(p_installment_amount,0),
    installment_frequency=coalesce(p_installment_frequency,'monthly'),
    assigned_agent_id=p_assigned_agent_id,
    agent_code=(select a.agent_code from public.agents a where a.id=p_assigned_agent_id),
    parent_agent_id=case when v_target_role='sub_agent' then (select parent_agent_id from public.profiles where id=p_assigned_agent_id) else null end,
    updated_at=now()
  where id=p_member_id returning * into v_member;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),case when p_assigned_agent_id<>v_old_agent then 'member.assigned' else 'member.updated' end,'member',v_member.id::text,
    jsonb_build_object('member_code',v_member.member_code,'old_assigned_agent_id',v_old_agent,'new_assigned_agent_id',p_assigned_agent_id,'role',v_role));
  return v_member;
exception when unique_violation then
  raise exception using errcode='23505',message='This mobile number is already registered to another member';
end;
$$;

revoke all on function public.update_member_record(uuid,text,text,text,text,text,date,numeric,text,uuid) from public,anon;
grant execute on function public.update_member_record(uuid,text,text,text,text,text,date,numeric,text,uuid) to authenticated;
notify pgrst, 'reload schema';
