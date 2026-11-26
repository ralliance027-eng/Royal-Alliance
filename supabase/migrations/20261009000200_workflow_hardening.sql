
-- Royal Alliance workflow hardening migration (apply after 202610090001_initial_schema.sql)
create table if not exists public.payout_allocations (
  id uuid primary key default gen_random_uuid(),
  payout_id uuid not null references public.payout_requests(id) on delete restrict,
  earning_id uuid not null references public.earnings_ledger(id) on delete restrict,
  amount numeric(12,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique(payout_id, earning_id)
);
alter table public.payout_allocations enable row level security;
create policy "payout allocations visible to payout owner and managers"
on public.payout_allocations for select to authenticated
using (
  exists(select 1 from public.payout_requests p where p.id=payout_id
    and (p.requested_by_profile_id=auth.uid() or public.current_app_role() in ('admin','super_admin')))
);
-- Allocations are only written by protected functions.
revoke insert, update, delete on public.payout_allocations from authenticated;

create or replace function public.request_payout(
  p_amount numeric,
  p_method text default 'bank_transfer',
  p_account_reference text default null
) returns jsonb
language plpgsql security definer set search_path=public,auth
as $$
declare role_name text; available_total numeric(12,2); payout_id uuid; remaining numeric(12,2); row_earning record; take_amount numeric(12,2); free_amount numeric(12,2);
begin
 role_name:=public.current_app_role();
 if coalesce(role_name, '') not in ('agent','admin','super_admin') then raise exception 'Not authorized to request payout'; end if;
 if p_amount is null or p_amount <= 0 then raise exception 'Payout amount must be greater than zero'; end if;
 if p_method not in ('bank_transfer','upi','cash','cheque') then raise exception 'Unsupported payout method'; end if;
 perform e.id from public.earnings_ledger e where e.beneficiary_profile_id=auth.uid() and e.status in ('available','reserved') order by e.created_at,e.id for update;
 select coalesce(sum(e.amount-coalesce(a.used_amount,0)),0) into available_total
 from public.earnings_ledger e
 left join lateral (
   select sum(pa.amount) used_amount from public.payout_allocations pa
   join public.payout_requests pr on pr.id=pa.payout_id
   where pa.earning_id=e.id and pr.status in ('requested','under_review','approved','paid')
 ) a on true
 where e.beneficiary_profile_id=auth.uid() and e.status<>'paid' and e.status<>'reversed';
 if available_total < p_amount then raise exception 'Insufficient available earnings balance'; end if;
 insert into public.payout_requests(requested_by_profile_id,amount,payout_method,account_reference,status)
 values(auth.uid(),p_amount,p_method,nullif(trim(p_account_reference),''),'requested') returning id into payout_id;
 remaining:=p_amount;
 for row_earning in
   select e.id,e.amount,coalesce(a.used_amount,0) used_amount
   from public.earnings_ledger e
   left join lateral (
     select sum(pa.amount) used_amount from public.payout_allocations pa
     join public.payout_requests pr on pr.id=pa.payout_id
     where pa.earning_id=e.id and pr.status in ('requested','under_review','approved','paid')
   ) a on true
   where e.beneficiary_profile_id=auth.uid() and e.status<>'paid' and e.status<>'reversed'
   order by e.created_at,e.id for update of e
 loop
   exit when remaining <= 0;
   free_amount:=row_earning.amount-coalesce(row_earning.used_amount,0);
   if free_amount <= 0 then continue; end if;
   take_amount:=least(free_amount,remaining);
   insert into public.payout_allocations(payout_id,earning_id,amount) values(payout_id,row_earning.id,take_amount);
   if take_amount=free_amount then
     update public.earnings_ledger set status='reserved' where id=row_earning.id and status='available';
   end if;
   remaining:=remaining-take_amount;
 end loop;
 if remaining > 0 then raise exception 'Could not reserve the requested amount'; end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'payout.requested','payout',payout_id::text,jsonb_build_object('amount',p_amount,'method',p_method));
 return jsonb_build_object('ok',true,'payout_id',payout_id,'amount',p_amount);
end $$;

create or replace function public.review_payout(
 p_payout_id uuid, p_decision text, p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare p public.payout_requests%rowtype;
begin
 if coalesce(public.current_app_role(), '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can review payouts'; end if;
 if p_decision not in ('approve','reject') then raise exception 'Decision must be approve or reject'; end if;
 select * into p from public.payout_requests where id=p_payout_id for update;
 if not found then raise exception 'Payout request not found'; end if;
 if p.status not in ('requested','under_review') then raise exception 'Payout is not reviewable in its current status'; end if;
 if p_decision='approve' then
   update public.payout_requests set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),notes=coalesce(p_notes,notes),updated_at=now() where id=p.id;
 else
   update public.earnings_ledger e set status='available'
   where e.id in (select a.earning_id from public.payout_allocations a where a.payout_id=p.id)
   and e.status='reserved'
   and not exists (
     select 1 from public.payout_allocations a2 join public.payout_requests p2 on p2.id=a2.payout_id
     where a2.earning_id=e.id and p2.id<>p.id and p2.status in ('requested','under_review','approved','paid')
   );
   update public.payout_requests set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),notes=coalesce(p_notes,notes),updated_at=now() where id=p.id;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'payout.'||p_decision,'payout',p.id::text,jsonb_build_object('notes',p_notes));
 return jsonb_build_object('ok',true,'payout_id',p.id,'status',case when p_decision='approve' then 'approved' else 'rejected' end);
end $$;

create or replace function public.mark_payout_paid(
 p_payout_id uuid, p_payment_reference text, p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare p public.payout_requests%rowtype;
begin
 if coalesce(public.current_app_role(), '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can settle payouts'; end if;
 if nullif(trim(p_payment_reference),'') is null then raise exception 'Actual payment reference is required'; end if;
 select * into p from public.payout_requests where id=p_payout_id for update;
 if not found then raise exception 'Payout request not found'; end if;
 if p.status<>'approved' then raise exception 'Only approved payouts can be marked paid'; end if;
 if exists(select 1 from public.payout_requests x where x.payment_reference=p_payment_reference and x.id<>p.id and x.status='paid') then
   raise exception 'This payment reference is already used by another paid payout';
 end if;
 update public.payout_requests set status='paid',paid_at=now(),payment_reference=trim(p_payment_reference),
   reviewed_by=coalesce(reviewed_by,auth.uid()),reviewed_at=coalesce(reviewed_at,now()),
   notes=coalesce(p_notes,notes),updated_at=now() where id=p.id;
 update public.earnings_ledger e set status='paid'
 where e.id in (select a.earning_id from public.payout_allocations a where a.payout_id=p.id)
 and e.status<>'paid'
 and (select coalesce(sum(a2.amount),0) from public.payout_allocations a2
      join public.payout_requests p2 on p2.id=a2.payout_id
      where a2.earning_id=e.id and p2.status='paid')
     >= e.amount;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'payout.paid','payout',p.id::text,jsonb_build_object('amount',p.amount,'payment_reference',trim(p_payment_reference)));
 return jsonb_build_object('ok',true,'payout_id',p.id,'status','paid');
end $$;

create or replace function public.reconcile_cash_deposit(
 p_agent_id uuid, p_payment_ids uuid[], p_receipt_number text, p_notes text default null
) returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare total_amount numeric(12,2); batch_id uuid; row_count integer;
begin
 if coalesce(public.current_app_role(), '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can reconcile office cash'; end if;
 if p_agent_id is null or coalesce(array_length(p_payment_ids,1),0)=0 then raise exception 'Select an agent and at least one payment'; end if;
 if nullif(trim(p_receipt_number),'') is null then raise exception 'Office receipt number is required'; end if;
 if exists(select 1 from public.cash_deposit_batches where receipt_number=trim(p_receipt_number)) then raise exception 'Receipt number already exists'; end if;
 perform 1 from public.payment_entries where id=any(p_payment_ids) for update;
 select count(*),coalesce(sum(amount),0) into row_count,total_amount
 from public.payment_entries
 where id=any(p_payment_ids) and agent_id=p_agent_id and status='pending' and payment_mode='cash' and not office_cash_received;
 if row_count <> array_length(p_payment_ids,1) then raise exception 'Every selected payment must be a pending cash payment, un-reconciled, and belong to the selected agent'; end if;
 insert into public.cash_deposit_batches(agent_id,received_by,amount,receipt_number,notes,status)
 values(p_agent_id,auth.uid(),total_amount,trim(p_receipt_number),p_notes,'reconciled') returning id into batch_id;
 update public.payment_entries set office_cash_received=true,office_received_by=auth.uid(),office_received_at=now(),
 office_receipt_number=trim(p_receipt_number),updated_at=now()
 where id=any(p_payment_ids);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'cash_deposit.reconciled','cash_deposit_batch',batch_id::text,
 jsonb_build_object('agent_id',p_agent_id,'payment_ids',p_payment_ids,'amount',total_amount,'receipt_number',trim(p_receipt_number)));
 return jsonb_build_object('ok',true,'batch_id',batch_id,'amount',total_amount,'payments_reconciled',row_count);
end $$;

create or replace function public.build_draw_eligibility_snapshot(p_draw_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare d public.draws%rowtype; n integer;
begin
 if coalesce(public.current_app_role(), '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can build eligibility'; end if;
 select * into d from public.draws where id=p_draw_id for update;
 if not found then raise exception 'Draw not found'; end if;
 if d.status='completed' or d.status='cancelled' then raise exception 'Cannot snapshot a completed or cancelled draw'; end if;
 delete from public.draw_eligible_members where draw_id=d.id;
 insert into public.draw_eligible_members(draw_id,member_id,eligibility_status,reason)
 select d.id,m.id,
   case when exists(select 1 from public.draws old where old.winner_member_id=m.id and old.status='completed') then 'excluded' else 'eligible' end,
   case when exists(select 1 from public.draws old where old.winner_member_id=m.id and old.status='completed') then 'Previous winner' else 'Active member with approved payment' end
 from public.members m
 where m.status='active' and exists(select 1 from public.payment_entries p where p.member_id=m.id and p.status='approved')
 on conflict(draw_id,member_id) do update set eligibility_status=excluded.eligibility_status,reason=excluded.reason,snapshotted_at=now();
 get diagnostics n = row_count;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'draw.eligibility_snapshotted','draw',d.id::text,jsonb_build_object('eligible_rows',n));
 return jsonb_build_object('ok',true,'draw_id',d.id,'snapshot_rows',n);
end $$;

create or replace function public.execute_draw_selection(p_draw_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare d public.draws%rowtype; chosen uuid; eligible_count integer;
begin
 if coalesce(public.current_app_role(), '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can execute draw selection'; end if;
 select * into d from public.draws where id=p_draw_id for update;
 if not found then raise exception 'Draw not found'; end if;
 if d.status='completed' or d.status='cancelled' then raise exception 'Draw is closed'; end if;
 if exists(select 1 from public.draw_eligible_members where draw_id=d.id and eligibility_status='eligible')=false then
   raise exception 'Build a non-empty eligibility snapshot before selecting a winner';
 end if;
 select count(*) into eligible_count from public.draw_eligible_members where draw_id=d.id and eligibility_status='eligible';
 select member_id into chosen from public.draw_eligible_members where draw_id=d.id and eligibility_status='eligible' order by gen_random_uuid() limit 1;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'draw.selection_executed','draw',d.id::text,jsonb_build_object('eligible_count',eligible_count,'selected_member_id',chosen,'method','PostgreSQL gen_random_uuid ordering; not independently certified'));
 return public.declare_draw_winner(d.id,chosen);
end $$;

revoke all on function public.request_payout(numeric,text,text) from public;
grant execute on function public.request_payout(numeric,text,text) to authenticated;
revoke all on function public.review_payout(uuid,text,text) from public;
grant execute on function public.review_payout(uuid,text,text) to authenticated;
revoke all on function public.mark_payout_paid(uuid,text,text) from public;
grant execute on function public.mark_payout_paid(uuid,text,text) to authenticated;
revoke all on function public.reconcile_cash_deposit(uuid,uuid[],text,text) from public;
grant execute on function public.reconcile_cash_deposit(uuid,uuid[],text,text) to authenticated;
revoke all on function public.build_draw_eligibility_snapshot(uuid) from public;
grant execute on function public.build_draw_eligibility_snapshot(uuid) to authenticated;
revoke all on function public.execute_draw_selection(uuid) from public;
grant execute on function public.execute_draw_selection(uuid) to authenticated;
