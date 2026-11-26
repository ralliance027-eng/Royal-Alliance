-- In-app notification centre with role-scoped recipients and realtime delivery.
create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_type text not null,
  title text not null,
  message text not null,
  entity_type text,
  entity_id text,
  action_url text,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  event_key text not null,
  unique(user_id, event_key)
);

create index if not exists app_notifications_user_created_idx
  on public.app_notifications(user_id, created_at desc);
create index if not exists app_notifications_user_unread_idx
  on public.app_notifications(user_id, created_at desc) where is_read = false;

alter table public.app_notifications enable row level security;
drop policy if exists "users read own app notifications" on public.app_notifications;
create policy "users read own app notifications"
  on public.app_notifications for select to authenticated
  using (user_id = (select auth.uid()));
drop policy if exists "users mark own app notifications read" on public.app_notifications;
create policy "users mark own app notifications read"
  on public.app_notifications for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

grant select on public.app_notifications to authenticated;
grant update (is_read, read_at) on public.app_notifications to authenticated;
revoke all on function public.emit_app_notification(uuid,text,text,text,text,text,text,text) from public, anon, authenticated;

create or replace function public.emit_app_notification(
  p_user_id uuid, p_event_type text, p_title text, p_message text,
  p_entity_type text, p_entity_id text, p_event_key text, p_action_url text default '/dashboard'
) returns void
language sql
security definer
set search_path = public
as $$
  insert into public.app_notifications(user_id,event_type,title,message,entity_type,entity_id,event_key,action_url)
  select p_user_id,p_event_type,p_title,p_message,p_entity_type,p_entity_id,p_event_key,p_action_url
  where p_user_id is not null
  on conflict (user_id,event_key) do nothing;
$$;

create or replace function public.route_business_app_notifications()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  r record;
  v_id text;
  v_event text;
  v_title text;
  v_message text;
  v_entity text := TG_TABLE_NAME;
  v_row jsonb;
  v_old jsonb;
  v_member_id uuid;
  v_agent_id uuid;
  v_admin_id uuid;
  v_actor uuid;
  v_status text;
  v_old_status text;
  v_amount text;
  v_name text;
begin
  v_row := to_jsonb(NEW);
  if TG_OP = 'UPDATE' then v_old := to_jsonb(OLD); end if;
  v_id := coalesce(v_row->>'id', '');
  v_status := coalesce(v_row->>'status','');
  v_old_status := coalesce(v_old->>'status','');
  v_actor := nullif(v_row->>'created_by','')::uuid;
  v_member_id := nullif(v_row->>'member_id','')::uuid;
  v_agent_id := nullif(v_row->>'assigned_agent_id','')::uuid;
  v_amount := coalesce(v_row->>'amount','');
  v_name := coalesce(v_row->>'full_name',v_row->>'title',v_row->>'name','Record');

  if TG_TABLE_NAME = 'members' and TG_OP = 'INSERT' then
    v_event := 'member_created'; v_title := 'New member registered';
    v_message := v_name || ' joined the programme.';
    v_member_id := nullif(v_row->>'id','')::uuid;
    v_agent_id := nullif(v_row->>'assigned_agent_id','')::uuid;
  elsif TG_TABLE_NAME = 'agents' and TG_OP = 'INSERT' then
    v_event := 'agent_created'; v_title := 'New agent added';
    v_message := v_name || ' was added to the agent team.';
    v_agent_id := nullif(v_row->>'id','')::uuid;
  elsif TG_TABLE_NAME = 'payment_entries' and TG_OP = 'INSERT' then
    v_event := 'payment_submitted'; v_title := 'Payment submitted';
    v_message := 'A payment of ₹' || v_amount || ' is awaiting review.';
    v_member_id := nullif(v_row->>'member_id','')::uuid;
    v_agent_id := nullif(v_row->>'agent_id','')::uuid;
  -- Payment status events include approved and rejected transitions.
  elsif TG_TABLE_NAME = 'payment_entries' and TG_OP = 'UPDATE' and v_status is distinct from v_old_status and v_status in ('approved','rejected') then
    v_event := 'payment_' || v_status;
    v_title := case when v_status='approved' then 'Payment approved' else 'Payment rejected' end;
    v_message := 'Payment of ₹' || v_amount || ' was ' || v_status || '.';
    v_member_id := nullif(v_row->>'member_id','')::uuid;
    v_agent_id := nullif(v_row->>'agent_id','')::uuid;
  elsif TG_TABLE_NAME = 'payout_requests' and TG_OP = 'INSERT' then
    v_event := 'payout_requested'; v_title := 'Payout requested';
    v_message := 'A payout request of ₹' || v_amount || ' was submitted.';
    v_actor := nullif(v_row->>'requested_by_profile_id','')::uuid;
  elsif TG_TABLE_NAME = 'payout_requests' and TG_OP = 'UPDATE' and v_status is distinct from v_old_status then
    v_event := 'payout_' || v_status; v_title := 'Payout ' || replace(v_status,'_',' ');
    v_message := 'Payout request of ₹' || v_amount || ' is now ' || replace(v_status,'_',' ') || '.';
    v_actor := nullif(v_row->>'requested_by_profile_id','')::uuid;
  elsif TG_TABLE_NAME = 'draws' and TG_OP = 'UPDATE' and v_status='completed' and v_old_status is distinct from v_status then
    v_event := 'draw_completed'; v_title := 'Draw completed';
    v_message := v_name || ' has been completed and a winner declared.';
    v_member_id := nullif(v_row->>'winner_member_id','')::uuid;
  elsif TG_TABLE_NAME = 'gift_deliveries' and TG_OP = 'UPDATE' and v_status is distinct from v_old_status then
    v_event := 'gift_delivery_' || v_status; v_title := 'Gift delivery ' || replace(v_status,'_',' ');
    v_message := 'A gift delivery status changed to ' || replace(v_status,'_',' ') || '.';
    v_member_id := nullif(v_row->>'member_id','')::uuid;
  else
    return NEW;
  end if;

  -- Notify the assigned Agent/Sub-Agent, their Admin, and all Super Admins.
  if v_member_id is not null then
    select m.assigned_agent_id into v_agent_id from public.members m where m.id=v_member_id;
  end if;
  if v_agent_id is not null then
    select a.admin_id into v_admin_id from public.agents a where a.id=v_agent_id;
    perform public.emit_app_notification(v_agent_id,v_event,v_title,v_message,v_entity,v_id,v_event||':'||v_id||':'||v_agent_id::text);
    if v_admin_id is not null then
      perform public.emit_app_notification(v_admin_id,v_event,v_title,v_message,v_entity,v_id,v_event||':'||v_id||':'||v_admin_id::text);
    end if;
  end if;
  if v_actor is not null then
    perform public.emit_app_notification(v_actor,v_event,v_title,v_message,v_entity,v_id,v_event||':'||v_id||':'||v_actor::text);
    if TG_TABLE_NAME = 'payout_requests' then
      select a.admin_id into v_admin_id from public.agents a where a.id=v_actor;
      if v_admin_id is not null then
        perform public.emit_app_notification(v_admin_id,v_event,v_title,v_message,v_entity,v_id,v_event||':'||v_id||':'||v_admin_id::text);
      end if;
    end if;
  end if;
  if v_member_id is not null then
    -- Member accounts are not enabled; notifications go to the responsible staff above.
    null;
  end if;
  for r in select id from public.profiles where role='super_admin' and status='active' loop
    perform public.emit_app_notification(r.id,v_event,v_title,v_message,v_entity,v_id,v_event||':'||v_id||':'||r.id::text);
  end loop;
  return NEW;
end;
$$;

revoke all on function public.route_business_app_notifications() from public, anon, authenticated;

drop trigger if exists app_notify_member_created on public.members;
create trigger app_notify_member_created after insert on public.members
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_agent_created on public.agents;
create trigger app_notify_agent_created after insert on public.agents
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_payment_inserted on public.payment_entries;
create trigger app_notify_payment_inserted after insert on public.payment_entries
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_payment_status on public.payment_entries;
create trigger app_notify_payment_status after update of status on public.payment_entries
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_payout_inserted on public.payout_requests;
create trigger app_notify_payout_inserted after insert on public.payout_requests
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_payout_status on public.payout_requests;
create trigger app_notify_payout_status after update of status on public.payout_requests
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_draw_completed on public.draws;
create trigger app_notify_draw_completed after update of status on public.draws
for each row execute function public.route_business_app_notifications();
drop trigger if exists app_notify_gift_delivery_status on public.gift_deliveries;
create trigger app_notify_gift_delivery_status after update of status on public.gift_deliveries
for each row execute function public.route_business_app_notifications();

-- Enable Supabase Realtime for the notification table.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='app_notifications'
  ) then
    alter publication supabase_realtime add table public.app_notifications;
  end if;
exception when undefined_object then
  raise notice 'supabase_realtime publication not found; enable Realtime for public.app_notifications in Supabase Dashboard';
end $$;


create or replace function public.notify_draw_result_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  m record;
  a record;
  s record;
  v_title text := 'Draw winner declared';
  v_message text;
  v_name text;
begin
  select full_name, assigned_agent_id into m from public.members where id=NEW.member_id;
  select title into v_name from public.draws where id=NEW.draw_id;
  v_message := coalesce(m.full_name,'A member') || ' has been declared a winner in ' || coalesce(v_name,'the draw') || '.';
  if m.assigned_agent_id is not null then
    perform public.emit_app_notification(m.assigned_agent_id,'draw_winner',v_title,v_message,'draw_results',NEW.id::text,'draw_winner:'||NEW.id::text||':'||m.assigned_agent_id::text);
    select admin_id into a from public.agents where id=m.assigned_agent_id;
    if a.admin_id is not null then
      perform public.emit_app_notification(a.admin_id,'draw_winner',v_title,v_message,'draw_results',NEW.id::text,'draw_winner:'||NEW.id::text||':'||a.admin_id::text);
    end if;
  end if;
  for s in select id from public.profiles where role='super_admin' and status='active' loop
    perform public.emit_app_notification(s.id,'draw_winner',v_title,v_message,'draw_results',NEW.id::text,'draw_winner:'||NEW.id::text||':'||s.id::text);
  end loop;
  return NEW;
end;
$$;
revoke all on function public.notify_draw_result_insert() from public, anon, authenticated;
drop trigger if exists app_notify_draw_result_insert on public.draw_results;
create trigger app_notify_draw_result_insert after insert on public.draw_results
for each row execute function public.notify_draw_result_insert();
