-- Secure code migration audit history and record future code changes automatically.
-- Code history is append-only from application clients; only trusted backend triggers write it.

alter table public.code_migration_history enable row level security;
revoke all on table public.code_migration_history from public, anon, authenticated;
grant select on table public.code_migration_history to authenticated;
grant all on table public.code_migration_history to service_role;

drop policy if exists "code migration history super admin read" on public.code_migration_history;
create policy "code migration history super admin read"
  on public.code_migration_history
  for select
  to authenticated
  using ((select public.current_app_role()) = 'super_admin');

create index if not exists code_migration_history_record_changed_idx
  on public.code_migration_history(entity_type, record_id, changed_at desc);

create or replace function public.log_code_migration_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_table_name = 'members' then
    if old.member_code is distinct from new.member_code
       and old.member_code is not null and new.member_code is not null then
      insert into public.code_migration_history(entity_type, record_id, old_code, new_code)
      values ('member', new.id, old.member_code, new.member_code);
    end if;
  elsif tg_table_name = 'agents' then
    if old.agent_code is distinct from new.agent_code
       and old.agent_code is not null and new.agent_code is not null then
      insert into public.code_migration_history(entity_type, record_id, old_code, new_code)
      values ('agent', new.id, old.agent_code, new.agent_code);
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.log_code_migration_change() from public, anon, authenticated;

drop trigger if exists members_log_code_migration on public.members;
create trigger members_log_code_migration
  after update of member_code on public.members
  for each row execute function public.log_code_migration_change();

drop trigger if exists agents_log_code_migration on public.agents;
create trigger agents_log_code_migration
  after update of agent_code on public.agents
  for each row execute function public.log_code_migration_change();

-- These sequence helpers are internal to trusted SECURITY DEFINER functions/triggers.
-- Do not expose them as callable Data API RPCs to browser roles.
revoke all on function public.ra_next_agent_code() from public, anon, authenticated;
revoke all on function public.ra_next_member_code() from public, anon, authenticated;
grant execute on function public.ra_next_agent_code() to service_role;
grant execute on function public.ra_next_member_code() to service_role;
