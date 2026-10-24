-- Royal Alliance: Sub-Agent hierarchy, logins and immutable 10% + 2% commission ledger.
-- Existing payment approval/cash reconciliation remains the gate for all commissions.

alter table public.profiles add column if not exists parent_agent_id uuid references public.profiles(id);
alter table public.agents add column if not exists parent_agent_id uuid references public.profiles(id);
alter table public.members add column if not exists parent_agent_id uuid references public.profiles(id);

-- Permit the new staff role while preserving the existing role allow-list.
do $$ declare c record; begin
  for c in select conname from pg_constraint where conrelid='public.profiles'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%role%' loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.profiles add constraint profiles_role_allowed_check check (role in ('super_admin','admin','agent','sub_agent'));

-- Existing UNIQUE(earning_type, source_payment_id) is retained: the override uses a distinct earning_type, so retries remain idempotent without breaking existing referral-ledger RPCs.

create or replace function public.sync_agent_profile()
returns trigger language plpgsql security definer set search_path=public,auth as $$
begin
  if new.role in ('agent','sub_agent') then
    insert into public.agents(id,agent_code,admin_id,full_name,email,mobile,status,role,parent_agent_id)
    values(new.id,'RA-AG-'||lpad(nextval('public.agent_code_seq')::text,4,'0'),coalesce(new.assigned_admin_id,(select assigned_admin_id from public.profiles where id=new.parent_agent_id)),new.full_name,new.email,new.mobile,new.status,new.role,new.parent_agent_id)
    on conflict (id) do update set admin_id=excluded.admin_id,full_name=excluded.full_name,email=excluded.email,mobile=excluded.mobile,status=excluded.status,role=excluded.role,parent_agent_id=excluded.parent_agent_id;
  else
    delete from public.agents where id=new.id;
  end if;
  return new;
end $$;

-- Re-sync current rows to materialize the hierarchy in agents as well as profiles.
insert into public.agents(id,agent_code,admin_id,full_name,email,mobile,status,role,parent_agent_id)
select p.id,'RA-AG-'||lpad(nextval('public.agent_code_seq')::text,4,'0'),coalesce(p.assigned_admin_id,(select parent.assigned_admin_id from public.profiles parent where parent.id=p.parent_agent_id)),p.full_name,p.email,p.mobile,p.status,p.role,p.parent_agent_id
from public.profiles p where p.role in ('agent','sub_agent')
on conflict (id) do update set admin_id=excluded.admin_id,full_name=excluded.full_name,email=excluded.email,mobile=excluded.mobile,status=excluded.status,role=excluded.role,parent_agent_id=excluded.parent_agent_id;

create or replace function public.prepare_member_insert()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare ref_id uuid; role_name text; assigned_parent uuid;
begin
  role_name:=public.current_app_role();
  if coalesce(role_name,'') not in ('agent','sub_agent','admin','super_admin') then raise exception 'Not authorized to create members'; end if;
  if role_name in ('agent','sub_agent') then
    if new.assigned_agent_id is null then new.assigned_agent_id:=auth.uid(); end if;
    if new.assigned_agent_id<>auth.uid() then
      if role_name<>'agent' or not exists(select 1 from public.profiles s where s.id=new.assigned_agent_id and s.role='sub_agent' and s.parent_agent_id=auth.uid() and s.status='active') then
        raise exception 'You can only register members for yourself or your own Sub-Agent';
      end if;
    end if;
  elsif role_name='admin' then
    if new.assigned_agent_id is null or not public.is_admin_of_agent(new.assigned_agent_id) then raise exception 'Admin can only assign members to agents in their own team'; end if;
  elsif new.assigned_agent_id is null then raise exception 'An assigned agent is required'; end if;
  select parent_agent_id into assigned_parent from public.profiles where id=new.assigned_agent_id;
  new.parent_agent_id:=case when (select role from public.profiles where id=new.assigned_agent_id)='sub_agent' then assigned_parent else null end;
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

-- Keep the current idempotent registration RPC signature used by the installed UI.
create or replace function public.register_member_idempotent(
  p_address text, p_assigned_agent_id uuid, p_full_name text, p_installment_amount numeric,
  p_installment_frequency text, p_joining_date date, p_mobile text, p_nominee_name text,
  p_referred_by_code text, p_request_id uuid
) returns public.members language plpgsql security definer set search_path=public,auth as $$
declare v_member public.members%rowtype; v_role text; v_assigned uuid;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if p_request_id is null then raise exception 'Registration request ID is required'; end if;
  v_role:=public.current_app_role();
  if coalesce(v_role,'') not in ('agent','sub_agent','admin','super_admin') then raise exception 'Not authorized to create members'; end if;
  if nullif(trim(p_full_name),'') is null or nullif(trim(p_mobile),'') is null then raise exception 'Member name and mobile are required'; end if;
  if coalesce(p_installment_amount,0)<0 then raise exception 'Installment amount cannot be negative'; end if;
  if coalesce(p_installment_frequency,'monthly') not in ('monthly','yearly','one_time') then raise exception 'Invalid installment frequency'; end if;
  v_assigned:=coalesce(p_assigned_agent_id,auth.uid());
  if v_role='sub_agent' and v_assigned<>auth.uid() then raise exception 'Sub-Agent can only register own members'; end if;
  if v_role='agent' and v_assigned<>auth.uid() and not exists(select 1 from public.profiles s where s.id=v_assigned and s.role='sub_agent' and s.parent_agent_id=auth.uid() and s.status='active') then raise exception 'You can only register members for yourself or your own Sub-Agent'; end if;
  if v_role='admin' and not public.is_admin_of_agent(v_assigned) then raise exception 'Agent is outside your assigned team'; end if;
  if exists(select 1 from public.members where registration_request_id=p_request_id) then
    select * into v_member from public.members where registration_request_id=p_request_id;
    if v_member.created_by<>auth.uid() and v_member.assigned_agent_id<>auth.uid() then raise exception 'Not authorized for this registration request'; end if;
    return v_member;
  end if;
  insert into public.members(registration_request_id,full_name,mobile,address,nominee_name,referred_by_code,assigned_agent_id,joining_date,installment_amount,installment_frequency,created_by)
  values(p_request_id,trim(p_full_name),regexp_replace(p_mobile,'[^0-9]','','g'),nullif(trim(p_address),''),nullif(trim(p_nominee_name),''),nullif(trim(p_referred_by_code),''),v_assigned,coalesce(p_joining_date,current_date),coalesce(p_installment_amount,0),coalesce(p_installment_frequency,'monthly'),auth.uid())
  returning * into v_member;
  return v_member;
exception when unique_violation then
  select * into v_member from public.members where registration_request_id=p_request_id;
  if found then return v_member; end if;
  raise exception using errcode='23505',message='This mobile number or member code is already registered';
end $$;

create or replace function public.approve_payment(p_payment_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare p public.payment_entries%rowtype; m public.members%rowtype; role_name text; parent_id uuid; commission_amount numeric(12,2); parent_amount numeric(12,2); referred_count integer:=0; referral_amount numeric(12,2);
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
 commission_amount:=round(p.amount*0.10,2);
 insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status) values(p.agent_id,'agent_commission',p.id,p.amount,0.10,commission_amount,'available') on conflict do nothing;
 select parent_agent_id into parent_id from public.profiles where id=p.agent_id and role='sub_agent';
 if parent_id is not null then
   parent_amount:=round(p.amount*0.02,2);
   insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status) values(parent_id,'sub_agent_override_commission',p.id,p.amount,0.02,parent_amount,'available') on conflict do nothing;
 end if;
 if m.referrer_member_id is not null then
   select count(*)::integer into referred_count from public.members r where r.referrer_member_id=m.referrer_member_id and r.status in ('active','winner') and exists(select 1 from public.payment_entries ep where ep.member_id=r.id and ep.status='approved');
   if referred_count>=2 then referral_amount:=round(p.amount*0.02,2); insert into public.earnings_ledger(beneficiary_member_id,earning_type,source_payment_id,basis_amount,rate,amount,status) values(m.referrer_member_id,'member_referral',p.id,p.amount,0.02,referral_amount,'available') on conflict do nothing; end if;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'payment.approved','payment_entry',p.id::text,jsonb_build_object('amount',p.amount,'member_id',p.member_id,'agent_id',p.agent_id,'sub_agent_parent_id',parent_id,'sub_agent_commission',commission_amount,'parent_override_commission',coalesce(parent_amount,0),'member_referral_commission',coalesce(referral_amount,0)));
 return jsonb_build_object('ok',true,'payment_id',p.id,'status','approved','commission_amount',commission_amount,'parent_override_commission',coalesce(parent_amount,0),'referral_eligible',referred_count>=2,'message','Payment approved; eligible earnings recorded.');
end $$;

-- Role/team scopes: sub-agents see own members; parent agent can see own direct members and direct sub-agent members.
drop policy if exists "members read by owner or managers" on public.members;
create policy "members read by owner or managers" on public.members for select to authenticated using (
 assigned_agent_id=auth.uid() or public.current_app_role()='super_admin' or
 (public.current_app_role()='admin' and public.is_admin_of_agent(assigned_agent_id)) or
 (public.current_app_role()='agent' and parent_agent_id=auth.uid())
);

drop policy if exists "agents read self and authorized team" on public.agents;
create policy "agents read self and authorized team" on public.agents for select to authenticated using (
 id=auth.uid() or public.current_app_role()='super_admin' or
 (public.current_app_role()='admin' and (admin_id=auth.uid() or public.is_admin_of_agent(id))) or
 (public.current_app_role()='agent' and (role='sub_agent' and parent_agent_id=auth.uid()))
);

revoke all on function public.register_member_idempotent(text,uuid,text,numeric,text,date,text,text,text,uuid) from public,anon;
grant execute on function public.register_member_idempotent(text,uuid,text,numeric,text,date,text,text,text,uuid) to authenticated;
revoke all on function public.approve_payment(uuid,text) from public,anon;
grant execute on function public.approve_payment(uuid,text) to authenticated;
notify pgrst,'reload schema';

drop policy if exists "agents create own members" on public.members;
create policy "agents create own members" on public.members for insert to authenticated with check (
 public.current_app_role() in ('agent','sub_agent','admin','super_admin') and
 (public.current_app_role()='super_admin' or
  (public.current_app_role()='admin' and public.is_admin_of_agent(assigned_agent_id)) or
  (public.current_app_role()='sub_agent' and assigned_agent_id=auth.uid()) or
  (public.current_app_role()='agent' and (assigned_agent_id=auth.uid() or (parent_agent_id=auth.uid() and exists(select 1 from public.profiles s where s.id=assigned_agent_id and s.role='sub_agent' and s.parent_agent_id=auth.uid()))))
 )
);

create or replace function public.prepare_payment_insert()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare m public.members%rowtype; role_name text;
begin
 role_name:=public.current_app_role();
 select * into m from public.members where id=new.member_id;
 if not found then raise exception 'Member record not found'; end if;
 if role_name in ('agent','sub_agent') then
   if m.assigned_agent_id<>auth.uid() then raise exception 'You can only record payments for your own assigned members'; end if;
   new.agent_id:=auth.uid();
 elsif role_name in ('admin','super_admin') then
   if role_name='admin' and not public.is_admin_of_agent(m.assigned_agent_id) then raise exception 'Member is outside your assigned team'; end if;
   new.agent_id:=m.assigned_agent_id;
 else raise exception 'Not authorized to record payments'; end if;
 new.status:='pending'; new.reviewed_by:=null; new.reviewed_at:=null;
 return new;
end $$;

drop policy if exists "agents insert payment entries" on public.payment_entries;
create policy "agents insert payment entries" on public.payment_entries for insert to authenticated with check (public.current_app_role() in ('agent','sub_agent','admin','super_admin'));
