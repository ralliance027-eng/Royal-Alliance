-- Royal Alliance migration 011: enforce team scope on payout status transitions.
-- Apply after migrations 001-010. Protects both RPC-driven and direct table updates.
create or replace function public.guard_payout_team_scope()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  role_name text;
  beneficiary_agent_id uuid;
  requester_role text;
begin
  role_name := public.current_app_role();
  if role_name is null or role_name not in ('admin','super_admin') then
    raise exception 'Only Admin or Super Admin can change payout status';
  end if;

  if role_name = 'admin' and new.status is distinct from old.status then
    if new.beneficiary_member_id is not null then
      select m.assigned_agent_id into beneficiary_agent_id
      from public.members m where m.id = new.beneficiary_member_id;
      if beneficiary_agent_id is null or not public.is_admin_of_agent(beneficiary_agent_id) then
        raise exception 'Member payout is outside your assigned team';
      end if;
    else
      select p.role into requester_role
      from public.profiles p where p.id = new.requested_by_profile_id;
      if requester_role is distinct from 'agent'
         or not public.is_admin_of_agent(new.requested_by_profile_id) then
        raise exception 'Payout request is outside your assigned team';
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists payout_team_scope_guard on public.payout_requests;
create trigger payout_team_scope_guard
before update of status on public.payout_requests
for each row execute function public.guard_payout_team_scope();

revoke all on function public.guard_payout_team_scope() from public;
