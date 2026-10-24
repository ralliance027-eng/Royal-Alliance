-- Additive support for operator-composed WhatsApp messages to saved Member/Agent records.
-- Does not modify or delete existing notification history.
alter table public.notification_logs
  add column if not exists recipient_type text,
  add column if not exists recipient_record_id uuid,
  add column if not exists message_body text,
  add column if not exists manual_consent_confirmed boolean not null default false;

alter table public.notification_logs
  drop constraint if exists notification_logs_recipient_type_check;
alter table public.notification_logs
  add constraint notification_logs_recipient_type_check
  check (recipient_type is null or recipient_type in ('member','agent'));

create index if not exists notification_logs_recipient_record_idx
  on public.notification_logs(recipient_type, recipient_record_id, created_at desc);

-- Distinguish a prepared WhatsApp Web handoff from a provider-confirmed API send.
alter table public.notification_logs drop constraint if exists notification_logs_status_check;
alter table public.notification_logs add constraint notification_logs_status_check check (status in ('queued','manual_opened','sent','delivered','failed','read'));
