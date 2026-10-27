-- V80: Royal Alliance commission rule agreed with business owner.
-- 10% direct commission always goes to the Agent/Sub-Agent assigned to the member/payment.
-- 2% hierarchy override goes only to that collector's immediate parent (Agent or Sub-Agent),
-- and only when that parent has at least TWO active direct Sub-Agent children.
-- No 2% goes to grandparents or deeper ancestors. Member-referral 2% is a separate rule.
create or replace function public.approve_payment(p_payment_id uuid,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare
 p public.payment_entries%rowtype;
 m public.members%rowtype;
 role_name text;
 collector_id uuid;
 parent_id uuid;
 commission_amount numeric(12,2);
 parent_override_amount numeric(12,2);
 referral_amount numeric(12,2);
 referred_count integer:=0;
 override_count integer:=0;
 active_subagent_count integer:=0;
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
 select parent_agent_id into parent_id from public.profiles where id=collector_id and role in ('agent','sub_agent');
 -- Direct 10% belongs to the actual collector; never pass this 10% to the parent.
 commission_amount:=round(p.amount*0.10,2);
 insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
 values(collector_id,'agent_commission',p.id,p.amount,0.10,commission_amount,'available') on conflict do nothing;
 -- Only immediate parent receives the 2% override, if it has >=2 active direct Sub-Agent children.
 if parent_id is not null then
   select count(*)::integer into active_subagent_count
   from public.profiles child
   where child.parent_agent_id=parent_id and child.role='sub_agent' and lower(coalesce(child.status,''))='active';
   if active_subagent_count>=2 then
     parent_override_amount:=round(p.amount*0.02,2);
     insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
     values(parent_id,'sub_agent_override_commission',p.id,p.amount,0.02,parent_override_amount,'available') on conflict do nothing;
     override_count:=1;
   end if;
 end if;
 -- Existing member referral rule remains independent from hierarchy commission.
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
 values(auth.uid(),'payment.approved','payment_entry',p.id::text,jsonb_build_object(
   'amount',p.amount,'member_id',p.member_id,'agent_id',p.agent_id,
   'direct_commission_beneficiary',collector_id,'direct_commission',commission_amount,
   'parent_override_beneficiary',case when override_count=1 then parent_id else null end,
   'parent_override_count',override_count,'active_direct_subagents_for_parent',active_subagent_count,
   'member_referral_commission',coalesce(referral_amount,0)));
 return jsonb_build_object('ok',true,'payment_id',p.id,'status','approved',
   'commission_amount',commission_amount,'commission_beneficiary_id',collector_id,
   'parent_override_count',override_count,'parent_override_amount',coalesce(parent_override_amount,0),
   'parent_override_beneficiary',case when override_count=1 then parent_id else null end,
   'active_direct_subagents_for_parent',active_subagent_count,'override_requires_active_subagents',2,
   'referral_eligible',referred_count>=2,
   'message','Payment approved: 10% to collector; 2% only to immediate parent when it has at least two active direct Sub-Agents.');
end;
$$;
revoke all on function public.approve_payment(uuid,text) from public,anon;
grant execute on function public.approve_payment(uuid,text) to authenticated;
notify pgrst,'reload schema';
