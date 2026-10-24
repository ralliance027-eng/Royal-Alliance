-- V72: Unlimited-depth Agent/Sub-Agent tree and qualified 2% override.
-- Apply after 20261013170000_sub_agent_hierarchy_commissions.sql.
-- Overrides are paid to every eligible ancestor in the payment collector's chain.
-- An ancestor is eligible only if it has >=2 active direct Sub-Agents, and each
-- of those direct branches contains at least one member (at any descendant depth).

create index if not exists profiles_parent_agent_id_idx on public.profiles(parent_agent_id);
create index if not exists members_assigned_agent_id_idx on public.members(assigned_agent_id);

-- Keep the ledger idempotent per beneficiary, type and payment; the old unique
-- (earning_type, source_payment_id) prevented paying multiple eligible ancestors.
do $$ declare c record; begin
  for c in
    select conname from pg_constraint
    where conrelid='public.earnings_ledger'::regclass and contype='u'
      and pg_get_constraintdef(oid) ilike '%earning_type%source_payment_id%'
  loop execute format('alter table public.earnings_ledger drop constraint %I',c.conname); end loop;
end $$;
alter table public.earnings_ledger drop constraint if exists earnings_ledger_earning_type_check;
alter table public.earnings_ledger add constraint earnings_ledger_earning_type_check
  check (earning_type in ('agent_commission','member_referral','sub_agent_override_commission'));
create unique index if not exists earnings_ledger_idempotency_uidx on public.earnings_ledger
  (earning_type,source_payment_id,(coalesce(beneficiary_profile_id,'00000000-0000-0000-0000-000000000000'::uuid)),(coalesce(beneficiary_member_id,'00000000-0000-0000-0000-000000000000'::uuid)));

create or replace function public.is_agent_in_tree(p_root uuid,p_candidate uuid)
returns boolean language sql stable security definer set search_path=public,auth as $$
  with recursive tree(id,parent_agent_id,path) as (
    select p.id,p.parent_agent_id,array[p.id] from public.profiles p where p.id=p_root
    union all
    select child.id,child.parent_agent_id,tree.path||child.id
    from public.profiles child join tree on child.parent_agent_id=tree.id
    where not child.id=any(tree.path) and cardinality(tree.path)<100
  ) select exists(select 1 from tree where id=p_candidate);
$$;
revoke all on function public.is_agent_in_tree(uuid,uuid) from public,anon;
grant execute on function public.is_agent_in_tree(uuid,uuid) to authenticated;

-- Profile -> agents mirror must track parent changes and support every depth.
create or replace function public.sync_agent_profile()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare v_admin uuid;
begin
  if new.role in ('agent','sub_agent') then
    v_admin:=coalesce(new.assigned_admin_id,(select p.assigned_admin_id from public.profiles p where p.id=new.parent_agent_id));
    insert into public.agents(id,agent_code,admin_id,full_name,email,mobile,status,role,parent_agent_id)
    values(new.id,'RA-AG-'||lpad(nextval('public.agent_code_seq')::text,4,'0'),v_admin,new.full_name,new.email,new.mobile,new.status,new.role,new.parent_agent_id)
    on conflict(id) do update set admin_id=excluded.admin_id,full_name=excluded.full_name,email=excluded.email,mobile=excluded.mobile,status=excluded.status,role=excluded.role,parent_agent_id=excluded.parent_agent_id;
  else delete from public.agents where id=new.id;
  end if;
  return new;
end $$;
drop trigger if exists profiles_sync_agent on public.profiles;
create trigger profiles_sync_agent after insert or update of role,assigned_admin_id,parent_agent_id,full_name,email,mobile,status on public.profiles for each row execute function public.sync_agent_profile();

-- Extend members visibility to all descendants (RLS remains the authority).
drop policy if exists "members read by owner or managers" on public.members;
create policy "members read by owner or managers" on public.members for select to authenticated using (
  assigned_agent_id=auth.uid() or public.current_app_role()='super_admin' or
  (public.current_app_role()='admin' and public.is_admin_of_agent(assigned_agent_id)) or
  (public.current_app_role() in ('agent','sub_agent') and public.is_agent_in_tree(auth.uid(),assigned_agent_id))
);

drop policy if exists "agents read self and authorized team" on public.agents;
create policy "agents read self and authorized team" on public.agents for select to authenticated using (
  id=auth.uid() or public.current_app_role()='super_admin' or
  (public.current_app_role()='admin' and (admin_id=auth.uid() or public.is_admin_of_agent(id))) or
  (public.current_app_role() in ('agent','sub_agent') and public.is_agent_in_tree(auth.uid(),id))
);

-- Replaces payment approval atomically. Existing cash reconciliation and team checks
-- are preserved; 10% goes to the collector; each eligible ancestor gets 2% once.
create or replace function public.approve_payment(p_payment_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
  p public.payment_entries%rowtype; m public.members%rowtype; role_name text;
  collector_id uuid; parent_id uuid; commission_amount numeric(12,2);
  referral_amount numeric(12,2); referred_count integer:=0; override_count integer:=0;
  ancestor record; branch_count integer; eligible boolean; ancestor_amount numeric(12,2);
begin
  role_name:=public.current_app_role();
  if coalesce(role_name,'') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can approve payments'; end if;
  select * into p from public.payment_entries where id=p_payment_id for update;
  if not found then raise exception 'Payment entry not found'; end if;
  if p.status<>'pending' then raise exception 'Only pending payments can be approved'; end if;
  if role_name='admin' and not public.is_admin_of_agent(p.agent_id) then raise exception 'Payment is outside your assigned team'; end if;
  select * into m from public.members where id=p.member_id for update;
  if not found or m.assigned_agent_id<>p.agent_id then raise exception 'Payment agent does not match the member assigned agent'; end if;
  if m.status='winner' then raise exception 'Winner members cannot submit new payments'; end if;
  if p.payment_mode='cash' and (not p.office_cash_received or p.office_received_by is null or p.office_received_at is null or nullif(trim(p.office_receipt_number),'') is null) then raise exception 'Cash must be reconciled at the office with a receipt before payment approval'; end if;
  if p.payment_mode<>'cash' and p.office_cash_received then raise exception 'Non-cash payments must not be marked as office cash deposits'; end if;
  update public.payment_entries set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now(),notes=case when nullif(trim(p_reason),'') is not null then concat_ws(E'\n',notes,'Approval note: '||trim(p_reason)) else notes end where id=p.id;

  collector_id:=p.agent_id;
  commission_amount:=round(p.amount*0.10,2);
  insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
  values(collector_id,'agent_commission',p.id,p.amount,0.10,commission_amount,'available') on conflict do nothing;

  -- Traverse parent chain, avoid cycles, max depth 100 for defensive safety.
  for ancestor in
    with recursive chain(id,parent_agent_id,path,depth) as (
      select pr.id,pr.parent_agent_id,array[pr.id],1 from public.profiles pr where pr.id=collector_id
      union all
      select par.id,par.parent_agent_id,chain.path||par.id,chain.depth+1
      from chain join public.profiles par on par.id=chain.parent_agent_id
      where not par.id=any(chain.path) and chain.depth<100
    ) select id from chain where id<>collector_id
  loop
    -- A branch qualifies only when >=2 direct active children each have >=1 member
    -- assigned anywhere under that child's descendant subtree.
    select count(*)::integer into branch_count
    from public.profiles child
    where child.parent_agent_id=ancestor.id and child.role='sub_agent' and child.status='active'
      and exists (
        with recursive branch(id,path,depth) as (
          select child.id,array[child.id],1
          union all
          select d.id,branch.path||d.id,branch.depth+1 from public.profiles d join branch on d.parent_agent_id=branch.id
          where not d.id=any(branch.path) and branch.depth<100
        ) select 1 from public.members mm join branch b on b.id=mm.assigned_agent_id
      );
    eligible:=branch_count>=2;
    if eligible then
      ancestor_amount:=round(p.amount*0.02,2);
      insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
      values(ancestor.id,'sub_agent_override_commission',p.id,p.amount,0.02,ancestor_amount,'available') on conflict do nothing;
      override_count:=override_count+1;
    end if;
  end loop;

  if m.referrer_member_id is not null then
    select count(*)::integer into referred_count from public.members r
    where r.referrer_member_id=m.referrer_member_id and r.status in ('active','winner')
      and exists(select 1 from public.payment_entries ep where ep.member_id=r.id and ep.status='approved');
    if referred_count>=2 then
      referral_amount:=round(p.amount*0.02,2);
      insert into public.earnings_ledger(beneficiary_member_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
      values(m.referrer_member_id,'member_referral',p.id,p.amount,0.02,referral_amount,'available') on conflict do nothing;
    end if;
  end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'payment.approved','payment_entry',p.id::text,jsonb_build_object('amount',p.amount,'member_id',p.member_id,'agent_id',p.agent_id,'own_commission',commission_amount,'eligible_ancestor_override_count',override_count,'member_referral_commission',coalesce(referral_amount,0)));
  return jsonb_build_object('ok',true,'payment_id',p.id,'status','approved','commission_amount',commission_amount,'eligible_ancestor_override_count',override_count,'referral_eligible',referred_count>=2,'message','Payment approved; eligible ancestor overrides and earnings recorded idempotently.');
end $$;
revoke all on function public.approve_payment(uuid,text) from public,anon;
grant execute on function public.approve_payment(uuid,text) to authenticated;
notify pgrst,'reload schema';


-- Member creation can target self or a direct child; this allows a Sub-Agent to
-- build a team while keeping assignment authority local to the parent-child edge.
create or replace function public.prepare_member_insert()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare ref_id uuid; role_name text; assigned_role text; assigned_parent uuid;
begin
  role_name:=public.current_app_role();
  if coalesce(role_name,'') not in ('agent','sub_agent','admin','super_admin') then raise exception 'Not authorized to create members'; end if;
  if new.assigned_agent_id is null then new.assigned_agent_id:=auth.uid(); end if;
  select role,parent_agent_id into assigned_role,assigned_parent from public.profiles where id=new.assigned_agent_id and status='active';
  if assigned_role is null then raise exception 'Assigned Agent/Sub-Agent is not an active account'; end if;
  if role_name in ('agent','sub_agent') and new.assigned_agent_id<>auth.uid() and assigned_parent<>auth.uid() then
    raise exception 'You can only register members for yourself or your direct Sub-Agent';
  elsif role_name='admin' and not public.is_admin_of_agent(new.assigned_agent_id) then
    raise exception 'Admin can only assign members to agents in their own team';
  elsif role_name='super_admin' then null;
  end if;
  new.parent_agent_id:=assigned_parent;
  if new.member_code is null or new.member_code='' then new.member_code:='RA-MB-'||lpad(nextval('public.member_code_seq')::text,6,'0'); end if;
  if new.referral_code is null or new.referral_code='' then new.referral_code:='RA-REF-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8)); end if;
  select agent_code into new.agent_code from public.agents where id=new.assigned_agent_id;
  if new.agent_code is null then raise exception 'Assigned Agent/Sub-Agent is not a valid account'; end if;
  if new.created_by is null then new.created_by:=auth.uid(); end if;
  if new.referred_by_code is not null and trim(new.referred_by_code)<>'' then
    select id into ref_id from public.members where referral_code=trim(new.referred_by_code) and status in ('active','winner') limit 1;
    if ref_id is null then raise exception 'Referral code is invalid or inactive'; end if;
    if ref_id=new.id then raise exception 'Self referral is not allowed'; end if;
    new.referrer_member_id:=ref_id;
  end if;
  return new;
end $$;

create or replace function public.register_member_idempotent(
  p_address text,p_assigned_agent_id uuid,p_full_name text,p_installment_amount numeric,
  p_installment_frequency text,p_joining_date date,p_mobile text,p_nominee_name text,
  p_referred_by_code text,p_request_id uuid
) returns public.members language plpgsql security definer set search_path=public,auth as $$
declare v_member public.members%rowtype; v_role text; v_assigned uuid; v_parent uuid; v_target_role text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_request_id is null then raise exception 'Registration request ID is required'; end if;
  v_role:=public.current_app_role();
  if coalesce(v_role,'') not in ('agent','sub_agent','admin','super_admin') then raise exception 'Not authorized to create members'; end if;
  if nullif(trim(p_full_name),'') is null or nullif(trim(p_mobile),'') is null then raise exception 'Member name and mobile are required'; end if;
  if coalesce(p_installment_amount,0)<0 then raise exception 'Installment amount cannot be negative'; end if;
  if coalesce(p_installment_frequency,'monthly') not in ('monthly','yearly','one_time') then raise exception 'Invalid installment frequency'; end if;
  v_assigned:=coalesce(p_assigned_agent_id,auth.uid());
  select role,parent_agent_id into v_target_role,v_parent from public.profiles where id=v_assigned and status='active';
  if v_target_role is null or v_target_role not in ('agent','sub_agent') then raise exception 'Select an active Agent or Sub-Agent'; end if;
  if v_role in ('agent','sub_agent') and v_assigned<>auth.uid() and v_parent<>auth.uid() then raise exception 'You can only register members for yourself or your direct Sub-Agent'; end if;
  if v_role='admin' and not public.is_admin_of_agent(v_assigned) then raise exception 'Agent is outside your assigned team'; end if;
  if exists(select 1 from public.members where registration_request_id=p_request_id) then
    select * into v_member from public.members where registration_request_id=p_request_id;
    if v_member.created_by<>auth.uid() and v_member.assigned_agent_id<>auth.uid() then raise exception 'Not authorized for this registration request'; end if;
    return v_member;
  end if;
  insert into public.members(registration_request_id,full_name,mobile,address,nominee_name,referred_by_code,assigned_agent_id,joining_date,installment_amount,installment_frequency,created_by)
  values(p_request_id,trim(p_full_name),regexp_replace(p_mobile,'[^0-9]','','g'),nullif(trim(p_address),''),nullif(trim(p_nominee_name),''),nullif(trim(p_referred_by_code),''),v_assigned,coalesce(p_joining_date,current_date),coalesce(p_installment_amount,0),coalesce(p_installment_frequency,'monthly'),auth.uid()) returning * into v_member;
  return v_member;
exception when unique_violation then
  select * into v_member from public.members where registration_request_id=p_request_id;
  if found then return v_member; end if;
  raise exception using errcode='23505',message='This mobile number or member code is already registered';
end $$;
revoke all on function public.register_member_idempotent(text,uuid,text,numeric,text,date,text,text,text,uuid) from public,anon;
grant execute on function public.register_member_idempotent(text,uuid,text,numeric,text,date,text,text,text,uuid) to authenticated;
