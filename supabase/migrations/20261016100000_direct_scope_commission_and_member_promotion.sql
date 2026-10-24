-- V73: exact commission scope + member-to-Sub-Agent promotion link.
-- A member promoted to Sub-Agent receives a login linked to the original member record.
-- 10% goes to the assigned collector; 2% only to the immediate parent if qualified.
-- Grandparents/deeper ancestors receive no override from deeper-level collections.
alter table public.profiles add column if not exists source_member_id uuid references public.members(id) on delete set null;
create unique index if not exists profiles_source_member_id_uidx on public.profiles(source_member_id) where source_member_id is not null;
create index if not exists profiles_parent_agent_id_idx on public.profiles(parent_agent_id);
create index if not exists members_assigned_agent_id_idx on public.members(assigned_agent_id);

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

  -- Direct-parent-only override. Never pay a grandparent or higher ancestor.
  select parent_agent_id into parent_id from public.profiles where id=collector_id and role in ('agent','sub_agent');
  if parent_id is not null then
    select count(*)::integer into branch_count
    from public.profiles child
    where child.parent_agent_id=parent_id
      and child.role='sub_agent'
      and child.status='active'
      and exists(select 1 from public.members direct_member where direct_member.assigned_agent_id=child.id);
    if branch_count>=2 then
      ancestor_amount:=round(p.amount*0.02,2);
      insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
      values(parent_id,'sub_agent_override_commission',p.id,p.amount,0.02,ancestor_amount,'available') on conflict do nothing;
      override_count:=1;
    end if;
  end if;

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
