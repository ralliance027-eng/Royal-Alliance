-- Royal Alliance: final payment approval guardrails.
-- Apply after migrations 001 through 004 in a staging Supabase project first.
-- Cash approval requires office reconciliation metadata; approval and earnings ledger
-- writes run in the same PostgreSQL transaction, so any error rolls back the entire action.

create or replace function public.approve_payment(
  p_payment_id uuid,
  p_reason text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  p public.payment_entries%rowtype;
  m public.members%rowtype;
  role_name text;
  referred_count integer := 0;
  commission_amount numeric(12,2);
  referral_amount numeric(12,2);
begin
  role_name := public.current_app_role();
  if coalesce(role_name, '') not in ('admin', 'super_admin') then
    raise exception 'Only Admin or Super Admin can approve payments';
  end if;

  select * into p
    from public.payment_entries
   where id = p_payment_id
   for update;
  if not found then
    raise exception 'Payment entry not found';
  end if;
  if p.status <> 'pending' then
    raise exception 'Only pending payments can be approved';
  end if;
  if role_name = 'admin' and not public.is_admin_of_agent(p.agent_id) then
    raise exception 'Payment is outside your assigned team';
  end if;

  select * into m
    from public.members
   where id = p.member_id
   for update;
  if not found then
    raise exception 'Member record not found';
  end if;
  if m.assigned_agent_id <> p.agent_id then
    raise exception 'Payment agent does not match the member assigned agent';
  end if;
  if m.status = 'winner' then
    raise exception 'Winner members cannot submit new payments';
  end if;

  if p.payment_mode = 'cash' and (
       not p.office_cash_received
       or p.office_received_by is null
       or p.office_received_at is null
       or nullif(trim(p.office_receipt_number), '') is null
     ) then
    raise exception 'Cash must be reconciled at the office with a receipt before payment approval';
  end if;

  -- Prevent a malformed/stale office-reconciliation flag from bypassing the cash workflow.
  if p.payment_mode <> 'cash' and p.office_cash_received then
    raise exception 'Non-cash payments must not be marked as office cash deposits';
  end if;

  update public.payment_entries
     set status = 'approved',
         reviewed_by = auth.uid(),
         reviewed_at = now(),
         updated_at = now(),
         notes = case
           when p_reason is not null and trim(p_reason) <> ''
             then concat_ws(E'\n', notes, 'Approval note: ' || trim(p_reason))
           else notes
         end
   where id = p_payment_id;

  commission_amount := round(p.amount * 0.10, 2);
  insert into public.earnings_ledger(
    beneficiary_profile_id, earning_type, source_payment_id,
    basis_amount, rate, amount, status
  ) values (
    p.agent_id, 'agent_commission', p.id,
    p.amount, 0.10, commission_amount, 'available'
  )
  on conflict (earning_type, source_payment_id) do nothing;

  -- A referral qualifies only after at least two active/winner referred members
  -- have at least one approved payment. This avoids counting unverified signups.
  if m.referrer_member_id is not null then
    select count(*)::integer
      into referred_count
      from public.members referred
     where referred.referrer_member_id = m.referrer_member_id
       and referred.status in ('active', 'winner')
       and exists (
         select 1
           from public.payment_entries verified_payment
          where verified_payment.member_id = referred.id
            and verified_payment.status = 'approved'
       );

    if referred_count >= 2 then
      referral_amount := round(p.amount * 0.02, 2);
      insert into public.earnings_ledger(
        beneficiary_member_id, earning_type, source_payment_id,
        basis_amount, rate, amount, status
      ) values (
        m.referrer_member_id, 'member_referral', p.id,
        p.amount, 0.02, referral_amount, 'available'
      )
      on conflict (earning_type, source_payment_id) do nothing;
    end if;
  end if;

  insert into public.audit_logs(actor_id, action, entity_type, entity_id, details)
  values (
    auth.uid(), 'payment.approved', 'payment_entry', p.id::text,
    jsonb_build_object(
      'amount', p.amount,
      'member_id', p.member_id,
      'agent_id', p.agent_id,
      'payment_mode', p.payment_mode,
      'office_receipt_number', p.office_receipt_number,
      'commission_amount', commission_amount,
      'qualifying_referred_members', referred_count
    )
  );

  return jsonb_build_object(
    'ok', true,
    'payment_id', p.id,
    'status', 'approved',
    'commission_amount', commission_amount,
    'referral_eligible', (referred_count >= 2),
    'message', 'Payment approved; eligible earnings recorded.'
  );
end;
$$;

revoke all on function public.approve_payment(uuid, text) from public;
grant execute on function public.approve_payment(uuid, text) to authenticated;
