-- Royal Alliance: final defensive fixes for nullable roles, concurrent receipts,
-- and partial earning allocations. Apply after migrations 001 through 008 in staging.

-- Prevent receipt-number duplicates even when two admins reconcile concurrently.
create unique index if not exists cash_deposit_receipt_unique_idx
  on public.cash_deposit_batches (receipt_number)
  where receipt_number is not null and trim(receipt_number) <> '';

-- Harden member creation when current_app_role() returns NULL.
create or replace function public.prepare_member_insert()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare ref_id uuid; role_name text;
begin
  role_name := public.current_app_role();
  if coalesce(role_name,'') not in ('agent','admin','super_admin') then
    raise exception 'Not authorized to create members';
  end if;
  if role_name='agent' then
    new.assigned_agent_id := auth.uid();
  elsif role_name='admin' then
    if new.assigned_agent_id is null or not public.is_admin_of_agent(new.assigned_agent_id) then
      raise exception 'Admin can only assign members to agents in their own team';
    end if;
  elsif new.assigned_agent_id is null then
    raise exception 'An assigned agent is required';
  end if;
  if new.member_code is null or trim(new.member_code)='' then
    new.member_code := 'RA-MB-'||lpad(nextval('public.member_code_seq')::text,6,'0');
  end if;
  if new.referral_code is null or trim(new.referral_code)='' then
    new.referral_code := 'RA-REF-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8));
  end if;
  select a.agent_code into new.agent_code from public.agents a
    where a.id=new.assigned_agent_id and a.status='active';
  if new.agent_code is null then raise exception 'Assigned Agent is not an active Agent account'; end if;
  if new.created_by is null then new.created_by:=auth.uid(); end if;
  if nullif(trim(new.referred_by_code),'') is not null then
    select m.id into ref_id from public.members m
      where m.referral_code=trim(new.referred_by_code) and m.status in ('active','winner') limit 1;
    if ref_id is null then raise exception 'Referral code is invalid or inactive'; end if;
    if new.id is not null and ref_id=new.id then raise exception 'Self referral is not allowed'; end if;
    new.referrer_member_id:=ref_id;
  else
    new.referrer_member_id:=null;
  end if;
  return new;
end;
$$;

create or replace function public.prepare_payment_insert()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare m public.members%rowtype; role_name text;
begin
  role_name:=public.current_app_role();
  if coalesce(role_name,'') not in ('agent','admin','super_admin') then
    raise exception 'Not authorized to record payments';
  end if;
  select * into m from public.members where id=new.member_id for share;
  if not found then raise exception 'Member not found'; end if;
  if m.status='winner' then raise exception 'Future payment collection is disabled for winners'; end if;
  if role_name='agent' then
    if m.assigned_agent_id is distinct from auth.uid() then raise exception 'You can only record payments for your own members'; end if;
    new.agent_id:=auth.uid();
  elsif role_name='admin' then
    if not public.is_admin_of_agent(m.assigned_agent_id) then raise exception 'Member is outside your assigned team'; end if;
    new.agent_id:=m.assigned_agent_id;
  else
    new.agent_id:=m.assigned_agent_id;
  end if;
  new.status:='pending'; new.reviewed_by:=null; new.reviewed_at:=null;
  new.office_cash_received:=false; new.office_received_by:=null; new.office_received_at:=null; new.office_receipt_number:=null;
  return new;
end;
$$;

-- Settlement supports partial allocations but never permits reserved/paid allocations
-- to exceed an earning. An earning is marked paid only when fully disbursed.
create or replace function public.mark_payout_paid(
  p_payout_id uuid, p_payment_reference text, p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare p public.payout_requests%rowtype; allocated_total numeric(12,2); allocation_count integer;
begin
  if coalesce(public.current_app_role(),'') not in ('admin','super_admin') then
    raise exception 'Only Admin or Super Admin can settle payouts';
  end if;
  if nullif(trim(p_payment_reference),'') is null then raise exception 'Actual payment reference is required'; end if;
  select * into p from public.payout_requests where id=p_payout_id for update;
  if not found then raise exception 'Payout request not found'; end if;
  if p.status<>'approved' then raise exception 'Only approved payouts can be settled'; end if;
  select count(*),coalesce(sum(a.amount),0) into allocation_count,allocated_total
    from public.payout_allocations a where a.payout_id=p.id;
  if allocation_count=0 or allocated_total<>p.amount then
    raise exception 'Payout allocations do not match the approved payout amount';
  end if;
  if exists (
    select 1 from public.payout_allocations a
    join public.earnings_ledger e on e.id=a.earning_id
    where a.payout_id=p.id and (
      a.amount<=0 or a.amount>e.amount or
      (select coalesce(sum(a2.amount),0)
       from public.payout_allocations a2 join public.payout_requests p2 on p2.id=a2.payout_id
       where a2.earning_id=e.id and p2.status in ('requested','under_review','approved','paid')) > e.amount
    )
  ) then raise exception 'Earning allocation exceeds available earning amount'; end if;
  if exists(select 1 from public.payout_requests x where x.payment_reference=trim(p_payment_reference)
            and x.id<>p.id and x.status='paid') then
    raise exception 'This payment reference is already used by another paid payout';
  end if;
  update public.payout_requests set status='paid',paid_at=now(),payment_reference=trim(p_payment_reference),
    reviewed_by=coalesce(reviewed_by,auth.uid()),reviewed_at=coalesce(reviewed_at,now()),
    notes=coalesce(p_notes,notes),updated_at=now() where id=p.id;
  update public.earnings_ledger e set status='paid'
  where e.id in (select a.earning_id from public.payout_allocations a where a.payout_id=p.id)
    and (select coalesce(sum(a2.amount),0)
         from public.payout_allocations a2 join public.payout_requests p2 on p2.id=a2.payout_id
         where a2.earning_id=e.id and p2.status='paid') >= e.amount;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'payout.paid','payout',p.id::text,
    jsonb_build_object('amount',p.amount,'payment_reference',trim(p_payment_reference)));
  return jsonb_build_object('ok',true,'payout_id',p.id,'status','paid');
end;
$$;

-- Unique index above is the concurrency-safe duplicate receipt guard.
create or replace function public.reconcile_cash_deposit(
  p_agent_id uuid,p_payment_ids uuid[],p_receipt_number text,p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare total_amount numeric(12,2); batch_id uuid; matched_count integer; requested_count integer;
begin
  if coalesce(public.current_app_role(),'') not in ('admin','super_admin') then
    raise exception 'Only Admin or Super Admin can reconcile office cash';
  end if;
  if p_agent_id is null or coalesce(cardinality(p_payment_ids),0)=0 then raise exception 'Select an agent and at least one payment'; end if;
  if nullif(trim(p_receipt_number),'') is null then raise exception 'Office receipt number is required'; end if;
  if array_position(p_payment_ids,null) is not null then raise exception 'Payment IDs cannot contain null values'; end if;
  if public.current_app_role()='admin' and not public.is_admin_of_agent(p_agent_id) then raise exception 'Agent is outside your assigned team'; end if;
  select count(distinct x) into requested_count from unnest(p_payment_ids) as t(x);
  if requested_count<>cardinality(p_payment_ids) then raise exception 'Duplicate payment IDs are not allowed'; end if;
  perform 1 from public.payment_entries where id=any(p_payment_ids) order by id for update;
  select count(*),coalesce(sum(amount),0) into matched_count,total_amount
    from public.payment_entries where id=any(p_payment_ids) and agent_id=p_agent_id
      and status='pending' and payment_mode='cash' and office_cash_received=false;
  if matched_count<>cardinality(p_payment_ids) then raise exception 'Every selected payment must be pending, unreconciled cash for the selected agent'; end if;
  if total_amount<=0 then raise exception 'Deposit total must be greater than zero'; end if;
  insert into public.cash_deposit_batches(agent_id,received_by,amount,receipt_number,notes,status)
    values(p_agent_id,auth.uid(),total_amount,trim(p_receipt_number),p_notes,'reconciled') returning id into batch_id;
  update public.payment_entries set office_cash_received=true,office_received_by=auth.uid(),office_received_at=now(),
    office_receipt_number=trim(p_receipt_number),updated_at=now() where id=any(p_payment_ids);
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'cash_deposit.reconciled','cash_deposit_batch',batch_id::text,
      jsonb_build_object('agent_id',p_agent_id,'payment_ids',p_payment_ids,'amount',total_amount,'receipt_number',trim(p_receipt_number)));
  return jsonb_build_object('ok',true,'batch_id',batch_id,'amount',total_amount,'payments_reconciled',matched_count);
end;
$$;

revoke all on function public.reconcile_cash_deposit(uuid,uuid[],text,text) from public;
grant execute on function public.reconcile_cash_deposit(uuid,uuid[],text,text) to authenticated;
revoke all on function public.mark_payout_paid(uuid,text,text) from public;
grant execute on function public.mark_payout_paid(uuid,text,text) to authenticated;
