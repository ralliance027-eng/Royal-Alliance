create or replace function public.finalize_booking_product_allocation(p_draw_year integer)
returns table(allocated_count integer, not_yet_chosen_count integer)
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_role text; v_draw_count integer; v_complete_count integer; v_allocated integer; v_pending integer;
begin
 v_role:=public.current_app_role();
 if v_role not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can finalize booking products'; end if;
 if p_draw_year<2020 or p_draw_year>2200 then raise exception 'Invalid draw year'; end if;
 select count(*),count(*) filter(where status='completed') into v_draw_count,v_complete_count from public.draws where draw_year=p_draw_year;
 if v_draw_count<>12 or v_complete_count<>12 then raise exception 'All 12 monthly draws for this year must be configured and completed first'; end if;
 update public.member_booking_choices c set choice_status='allocated',allocated_at=now(),updated_at=now()
 where c.choice_status='chosen' and c.booking_product_id is not null
 and exists(select 1 from public.members m where m.id=c.member_id and m.status='active')
 and not exists(select 1 from public.draw_results r join public.draws d on d.id=r.draw_id where r.member_id=c.member_id and r.status='winner' and d.draw_year=p_draw_year)
 and not exists(select 1 from public.draws d where d.draw_year=p_draw_year and d.winner_member_id=c.member_id);
 get diagnostics v_allocated=row_count;
 select count(*) into v_pending from public.member_booking_choices c join public.members m on m.id=c.member_id
 where c.choice_status='not_yet_chosen' and m.status='active'
 and not exists(select 1 from public.draw_results r join public.draws d on d.id=r.draw_id where r.member_id=c.member_id and r.status='winner' and d.draw_year=p_draw_year)
 and not exists(select 1 from public.draws d where d.draw_year=p_draw_year and d.winner_member_id=c.member_id);
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details)
 values(auth.uid(),'booking_products.finalized','draw_year',p_draw_year::text,jsonb_build_object('allocated_count',v_allocated,'not_yet_chosen_count',v_pending));
 allocated_count:=v_allocated; not_yet_chosen_count:=v_pending; return next;
end; $$;
revoke all on function public.finalize_booking_product_allocation(integer) from public,anon;
grant execute on function public.finalize_booking_product_allocation(integer) to authenticated;
