-- Admin-managed payouts for member referral earnings (members intentionally have no login).
-- Apply after migrations 001-007 in staging first.
create or replace function public.request_member_referral_payout(
  p_member_id uuid,
  p_amount numeric,
  p_method text default 'bank_transfer',
  p_account_reference text default null,
  p_notes text default null
) returns jsonb
language plpgsql security definer set search_path=public,auth
as $$
declare
  role_name text;
  m public.members%rowtype;
  payout_id uuid;
  available_total numeric(12,2);
  remaining numeric(12,2);
  row_earning record;
  take_amount numeric(12,2);
  free_amount numeric(12,2);
  referral_count integer;
begin
  role_name := public.current_app_role();
  if coalesce(role_name,'') not in ('admin','super_admin') then
    raise exception 'Only Admin or Super Admin can create a member referral payout';
  end if;
  if p_member_id is null or p_amount is null or p_amount <= 0 then
    raise exception 'Member and a positive payout amount are required';
  end if;
  if p_method not in ('bank_transfer','upi','cash','cheque') then
    raise exception 'Unsupported payout method';
  end if;
  select * into m from public.members where id=p_member_id for update;
  if not found then raise exception 'Member not found'; end if;
  if role_name='admin' and not public.is_admin_of_agent(m.assigned_agent_id) then
    raise exception 'Member is outside your assigned team';
  end if;
  select count(*) into referral_count from public.members r
    where r.referrer_member_id=m.id and r.status in ('active','winner')
      and exists(select 1 from public.payment_entries pe where pe.member_id=r.id and pe.status='approved');
  if referral_count < 2 then raise exception 'Member does not meet the minimum two valid referrals rule'; end if;

  perform e.id from public.earnings_ledger e
    where e.beneficiary_member_id=m.id and e.earning_type='member_referral'
      and e.status in ('available','reserved') order by e.created_at,e.id for update;
  select coalesce(sum(e.amount-coalesce(a.used_amount,0)),0) into available_total
  from public.earnings_ledger e
  left join lateral (
    select sum(pa.amount) used_amount from public.payout_allocations pa
    join public.payout_requests pr on pr.id=pa.payout_id
    where pa.earning_id=e.id and pr.status in ('requested','under_review','approved','paid')
  ) a on true
  where e.beneficiary_member_id=m.id and e.earning_type='member_referral'
    and e.status not in ('paid','reversed');
  if available_total < p_amount then raise exception 'Insufficient available member referral earnings balance'; end if;

  insert into public.payout_requests(requested_by_profile_id,beneficiary_member_id,amount,payout_method,account_reference,status,notes)
  values(auth.uid(),m.id,p_amount,p_method,nullif(trim(p_account_reference),''),'requested',p_notes)
  returning id into payout_id;
  remaining := p_amount;
  for row_earning in
    select e.id,e.amount,coalesce(a.used_amount,0) used_amount
    from public.earnings_ledger e
    left join lateral (
      select sum(pa.amount) used_amount from public.payout_allocations pa
      join public.payout_requests pr on pr.id=pa.payout_id
      where pa.earning_id=e.id and pr.status in ('requested','under_review','approved','paid')
    ) a on true
    where e.beneficiary_member_id=m.id and e.earning_type='member_referral'
      and e.status not in ('paid','reversed')
    order by e.created_at,e.id for update of e
  loop
    exit when remaining <= 0;
    free_amount := row_earning.amount-coalesce(row_earning.used_amount,0);
    if free_amount <= 0 then continue; end if;
    take_amount := least(free_amount,remaining);
    insert into public.payout_allocations(payout_id,earning_id,amount) values(payout_id,row_earning.id,take_amount);
    if take_amount=free_amount then update public.earnings_ledger set status='reserved' where id=row_earning.id and status='available'; end if;
    remaining := remaining-take_amount;
  end loop;
  if remaining > 0 then raise exception 'Could not reserve the requested member referral earnings'; end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'member_referral_payout.requested','payout',payout_id::text,
    jsonb_build_object('member_id',m.id,'amount',p_amount,'method',p_method));
  return jsonb_build_object('ok',true,'payout_id',payout_id,'member_id',m.id,'amount',p_amount,'status','requested');
end;
$$;
revoke all on function public.request_member_referral_payout(uuid,numeric,text,text,text) from public;
grant execute on function public.request_member_referral_payout(uuid,numeric,text,text,text) to authenticated;
