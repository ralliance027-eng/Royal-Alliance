-- Keep current authenticated read behavior and remove duplicate permissive SELECT paths.
drop policy if exists "agents read by team" on public.agents;

-- Booking products: signed-in staff read; Admin/Super Admin mutate.
drop policy if exists "managers manage booking products" on public.booking_products;
create policy "managers insert booking products" on public.booking_products for insert to authenticated with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers update booking products" on public.booking_products for update to authenticated using ((select public.current_app_role()) in ('admin','super_admin')) with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers delete booking products" on public.booking_products for delete to authenticated using ((select public.current_app_role()) in ('admin','super_admin'));

-- Company settings: signed-in staff read; only Super Admin mutates.
drop policy if exists "super admin manage settings" on public.company_settings;
create policy "super admin insert settings" on public.company_settings for insert to authenticated with check ((select public.current_app_role()) = 'super_admin');
create policy "super admin update settings" on public.company_settings for update to authenticated using ((select public.current_app_role()) = 'super_admin') with check ((select public.current_app_role()) = 'super_admin');
create policy "super admin delete settings" on public.company_settings for delete to authenticated using ((select public.current_app_role()) = 'super_admin');

-- Eligibility snapshot: Admin/Super Admin only.
drop policy if exists "draw eligibility manager manage" on public.draw_eligible_members;
create policy "draw eligibility managers insert" on public.draw_eligible_members for insert to authenticated with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "draw eligibility managers update" on public.draw_eligible_members for update to authenticated using ((select public.current_app_role()) in ('admin','super_admin')) with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "draw eligibility managers delete" on public.draw_eligible_members for delete to authenticated using ((select public.current_app_role()) in ('admin','super_admin'));

-- Draw prizes/results and gifts: authenticated read; managers mutate.
drop policy if exists "managers manage draw prizes" on public.draw_prizes;
create policy "managers insert draw prizes" on public.draw_prizes for insert to authenticated with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers update draw prizes" on public.draw_prizes for update to authenticated using ((select public.current_app_role()) in ('admin','super_admin')) with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers delete draw prizes" on public.draw_prizes for delete to authenticated using ((select public.current_app_role()) in ('admin','super_admin'));

drop policy if exists "managers manage draw results" on public.draw_results;
create policy "managers insert draw results" on public.draw_results for insert to authenticated with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers update draw results" on public.draw_results for update to authenticated using ((select public.current_app_role()) in ('admin','super_admin')) with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers delete draw results" on public.draw_results for delete to authenticated using ((select public.current_app_role()) in ('admin','super_admin'));

drop policy if exists "managers manage gifts" on public.gifts;
create policy "managers insert gifts" on public.gifts for insert to authenticated with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers update gifts" on public.gifts for update to authenticated using ((select public.current_app_role()) in ('admin','super_admin')) with check ((select public.current_app_role()) in ('admin','super_admin'));
create policy "managers delete gifts" on public.gifts for delete to authenticated using ((select public.current_app_role()) in ('admin','super_admin'));

-- Cover outstanding FK columns; remove confirmed duplicate index only.
create index if not exists agents_parent_agent_id_idx on public.agents(parent_agent_id);
create index if not exists members_parent_agent_id_idx on public.members(parent_agent_id);
drop index if exists public.members_agent_idx;
