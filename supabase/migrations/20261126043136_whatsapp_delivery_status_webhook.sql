-- Record the provider-accepted-but-not-yet-confirmed state and allow delivery callbacks.
alter table public.notification_logs drop constraint if exists notification_logs_status_check;
alter table public.notification_logs add constraint notification_logs_status_check
  check (status in ('queued','manual_opened','sent','sent_unconfirmed','delivered','failed','read'));
create index if not exists notification_logs_provider_message_id_idx
  on public.notification_logs(provider_message_id) where provider_message_id is not null;
