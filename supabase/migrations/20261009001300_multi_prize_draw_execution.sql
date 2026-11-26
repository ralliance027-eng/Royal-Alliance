-- Atomic multi-prize draw execution and per-prize delivery records.
-- Existing single-winner columns/functions are retained for compatibility.
create unique index if not exists gift_deliveries_draw_member_gift_uidx
  on public.gift_deliveries(draw_id, member_id, gift_id) where gift_id is not null;

do $$
begin
  if exists (select 1 from pg_constraint where conname = 'gift_deliveries_draw_id_key' and conrelid = 'public.gift_deliveries'::regclass) then
    alter table public.gift_deliveries drop constraint gift_deliveries_draw_id_key;
  end if;
end $$;

create or replace function public.execute_multi_prize_draw(p_draw_id uuid)
returns table(prize_id uuid, gift_id uuid, member_id uuid, member_code text, member_name text)
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_role text;
  v_prize record;
  v_member record;
  v_count integer;
  v_total integer := 0;
begin
  v_role := public.current_app_role();
  if v_role not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can execute a draw'; end if;
  perform 1 from public.draws where id = p_draw_id for update;
  if not found then raise exception 'Draw not found'; end if;
  if exists (select 1 from public.draw_results r where r.draw_id = p_draw_id and r.status = 'winner') then
    raise exception 'This draw already has results; multi-prize execution cannot be repeated';
  end if;
  if not exists (select 1 from public.draw_eligible_members e where e.draw_id = p_draw_id and e.eligibility_status = 'eligible') then
    raise exception 'Build an eligibility snapshot with eligible members before executing this draw';
  end if;
  for v_prize in
    select dp.id, dp.gift_id, dp.quantity
    from public.draw_prizes dp where dp.draw_id = p_draw_id order by dp.sort_order, dp.created_at
  loop
    v_count := 0;
    while v_count < v_prize.quantity loop
      select m.id, m.member_code, m.full_name
      into v_member
      from public.draw_eligible_members e
      join public.members m on m.id = e.member_id
      where e.draw_id = p_draw_id
        and e.eligibility_status = 'eligible'
        and coalesce(m.status, 'active') = 'active'
        and not exists (select 1 from public.draw_results r where r.member_id = m.id and r.status = 'winner')
        and not exists (select 1 from public.draws old where old.winner_member_id = m.id and old.id <> p_draw_id)
      order by random()
      limit 1
      for update of m skip locked;
      exit when not found;
      insert into public.draw_results(draw_id, prize_id, member_id, selected_by, status)
      values (p_draw_id, v_prize.id, v_member.id, auth.uid(), 'winner');
      insert into public.gift_deliveries(draw_id, member_id, gift_id, status, updated_by)
      values (p_draw_id, v_member.id, v_prize.gift_id, 'pending', auth.uid())
      on conflict (draw_id, member_id, gift_id) where gift_id is not null do nothing;
      update public.draw_eligible_members set eligibility_status = 'winner', reason = 'Selected in multi-prize draw'
      where draw_id = p_draw_id and member_id = v_member.id;
      update public.members set status = 'winner', updated_at = now() where id = v_member.id;
      prize_id := v_prize.id; gift_id := v_prize.gift_id; member_id := v_member.id;
      member_code := v_member.member_code; member_name := v_member.full_name;
      return next;
      v_count := v_count + 1;
      v_total := v_total + 1;
    end loop;
  end loop;
  if v_total = 0 then raise exception 'No eligible members remain for configured prizes'; end if;
  update public.draws set status = 'completed', declared_by = auth.uid(), declared_at = now(), updated_at = now() where id = p_draw_id;
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, details)
  values (auth.uid(), 'draw.multi_prize_executed', 'draw', p_draw_id::text, jsonb_build_object('winner_count', v_total));
end;
$$;
revoke all on function public.execute_multi_prize_draw(uuid) from public, anon;
grant execute on function public.execute_multi_prize_draw(uuid) to authenticated;
