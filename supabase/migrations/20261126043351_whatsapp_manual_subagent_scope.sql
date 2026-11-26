-- Allow manual WhatsApp handoff logs for active Sub-Agents, constrained to their own hierarchy.
drop policy if exists "authorized staff log manual WhatsApp handoff" on public.notification_logs;
create policy "authorized staff log manual WhatsApp handoff"
  on public.notification_logs
  for insert
  to authenticated
  with check (
    (select public.current_app_role()) in ('admin','super_admin','agent','sub_agent')
    and template_name='manual_text'
    and manual_consent_confirmed=true
    and status='queued'
    and case
      when recipient_type='member' then exists (
        select 1 from public.members m
        where m.id=notification_logs.recipient_record_id
          and m.mobile is not null
          and (
            (select public.current_app_role())='super_admin'
            or ((select public.current_app_role())='admin' and public.is_admin_of_agent(m.assigned_agent_id))
            or ((select public.current_app_role()) in ('agent','sub_agent') and public.is_agent_in_tree(auth.uid(),m.assigned_agent_id))
          )
      )
      when recipient_type='agent' then exists (
        select 1 from public.agents a
        where a.id=notification_logs.recipient_record_id
          and a.mobile is not null
          and (
            (select public.current_app_role())='super_admin'
            or ((select public.current_app_role())='admin' and a.admin_id=auth.uid())
            or ((select public.current_app_role()) in ('agent','sub_agent') and public.is_agent_in_tree(auth.uid(),a.id))
          )
      )
      else false
    end
  );
