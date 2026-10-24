-- Royal Alliance migration 010: support the completed admin pages safely.
-- Apply only after migrations 001 through 009 in a staging project first.

-- Ensure the UI's operational tables have predictable indexes.
create index if not exists gift_deliveries_status_updated_idx
  on public.gift_deliveries(status, updated_at desc);
create index if not exists audit_logs_created_at_idx
  on public.audit_logs(created_at desc);
create index if not exists notification_logs_created_at_idx
  on public.notification_logs(created_at desc);

-- Recreate narrow manager policies idempotently. No agent can view financial audit logs.
drop policy if exists "gift delivery manager read" on public.gift_deliveries;
create policy "gift delivery manager read" on public.gift_deliveries
  for select to authenticated
  using (coalesce(public.current_app_role(),'') in ('admin','super_admin'));

drop policy if exists "gift delivery manager update" on public.gift_deliveries;
create policy "gift delivery manager update" on public.gift_deliveries
  for update to authenticated
  using (coalesce(public.current_app_role(),'') in ('admin','super_admin'))
  with check (coalesce(public.current_app_role(),'') in ('admin','super_admin'));

drop policy if exists "audit logs managers read" on public.audit_logs;
create policy "audit logs managers read" on public.audit_logs
  for select to authenticated
  using (coalesce(public.current_app_role(),'') in ('admin','super_admin'));

drop policy if exists "super admin manage settings" on public.company_settings;
create policy "super admin manage settings" on public.company_settings
  for all to authenticated
  using (coalesce(public.current_app_role(),'') = 'super_admin')
  with check (coalesce(public.current_app_role(),'') = 'super_admin');

-- Keep the application roles limited to explicit authenticated access.
revoke all on public.company_settings from anon;
revoke all on public.gift_deliveries from anon;
revoke all on public.audit_logs from anon;
grant select, insert, update, delete on public.company_settings to authenticated;
grant select, update on public.gift_deliveries to authenticated;
grant select on public.audit_logs to authenticated;
