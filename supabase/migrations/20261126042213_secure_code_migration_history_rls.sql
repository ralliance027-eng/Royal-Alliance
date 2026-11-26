-- Initial lockdown for the code migration audit table; extended with automatic triggers later.
alter table public.code_migration_history enable row level security;
revoke all on table public.code_migration_history from public, anon, authenticated;
grant select on table public.code_migration_history to authenticated;
grant all on table public.code_migration_history to service_role;
drop policy if exists "code migration history super admin read" on public.code_migration_history;
create policy "code migration history super admin read"
  on public.code_migration_history for select to authenticated
  using ((select public.current_app_role()) = 'super_admin');
