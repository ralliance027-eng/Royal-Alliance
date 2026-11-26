-- Royal Alliance: protected settings change history for the Super Admin control centre.
create table if not exists public.company_settings_history (
  id bigint generated always as identity primary key,
  setting_key text not null,
  operation text not null check (operation in ('INSERT','UPDATE','DELETE')),
  changed_by uuid references public.profiles(id) on delete set null,
  changed_at timestamptz not null default now(),
  before_value jsonb,
  after_value jsonb
);

create index if not exists company_settings_history_changed_at_idx
  on public.company_settings_history(changed_at desc);
create index if not exists company_settings_history_key_changed_at_idx
  on public.company_settings_history(setting_key, changed_at desc);

alter table public.company_settings_history enable row level security;
revoke all on public.company_settings_history from anon;
revoke all on public.company_settings_history from authenticated;
grant select on public.company_settings_history to authenticated;

drop policy if exists "super admin read settings history" on public.company_settings_history;
create policy "super admin read settings history"
  on public.company_settings_history
  for select to authenticated
  using ((select public.current_app_role()) = 'super_admin');

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create or replace function private.capture_company_settings_history()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_actor uuid := auth.uid();
  v_key text;
  v_before jsonb;
  v_after jsonb;
  v_operation text;
begin
  if v_actor is not null and coalesce(public.current_app_role(), '') <> 'super_admin' then
    raise exception 'Only Super Admin can change company settings';
  end if;

  if tg_op = 'INSERT' then
    v_key := new.key;
    v_after := new.value;
    v_operation := 'INSERT';
  elsif tg_op = 'UPDATE' then
    v_key := new.key;
    v_before := old.value;
    v_after := new.value;
    v_operation := 'UPDATE';
  else
    v_key := old.key;
    v_before := old.value;
    v_operation := 'DELETE';
  end if;

  insert into public.company_settings_history(setting_key, operation, changed_by, before_value, after_value)
  values (v_key, v_operation, v_actor, v_before, v_after);

  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;

revoke all on function private.capture_company_settings_history() from public, anon, authenticated;

drop trigger if exists company_settings_history_capture on public.company_settings;
create trigger company_settings_history_capture
  after insert or update or delete on public.company_settings
  for each row execute function private.capture_company_settings_history();
