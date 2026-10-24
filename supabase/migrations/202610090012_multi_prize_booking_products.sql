-- Royal Alliance: multi-prize monthly draws and fallback booking products.
-- Additive migration; preserves the existing single-winner columns for backward compatibility.
create table if not exists public.draw_prizes (
  id uuid primary key default gen_random_uuid(),
  draw_id uuid not null references public.draws(id) on delete cascade,
  gift_id uuid not null references public.gifts(id),
  quantity integer not null default 1 check (quantity > 0),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  unique(draw_id, gift_id)
);
create index if not exists draw_prizes_draw_idx on public.draw_prizes(draw_id, sort_order);

create table if not exists public.draw_results (
  id uuid primary key default gen_random_uuid(),
  draw_id uuid not null references public.draws(id) on delete cascade,
  prize_id uuid not null references public.draw_prizes(id),
  member_id uuid not null references public.members(id),
  selected_by uuid references public.profiles(id),
  selected_at timestamptz not null default now(),
  status text not null default 'winner' check (status in ('winner','cancelled')),
  notes text,
  unique(draw_id, prize_id, member_id)
);
create index if not exists draw_results_draw_idx on public.draw_results(draw_id);
create index if not exists draw_results_member_idx on public.draw_results(member_id);

create table if not exists public.booking_products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  estimated_value numeric(12,2) not null default 0 check (estimated_value >= 0),
  image_url text,
  storage_path text,
  status text not null default 'active' check (status in ('active','inactive')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists booking_products_status_idx on public.booking_products(status);

create table if not exists public.member_booking_choices (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null unique references public.members(id) on delete cascade,
  booking_product_id uuid references public.booking_products(id),
  choice_status text not null default 'not_yet_chosen'
    check (choice_status in ('not_yet_chosen','chosen','allocated','delivered')),
  selected_by uuid references public.profiles(id),
  selected_at timestamptz,
  allocated_at timestamptz,
  delivered_at timestamptz,
  delivery_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_booking_choice_consistent check (
    (choice_status = 'not_yet_chosen' and booking_product_id is null)
    or (choice_status <> 'not_yet_chosen' and booking_product_id is not null)
  )
);
create index if not exists member_booking_choices_status_idx on public.member_booking_choices(choice_status);

alter table public.draw_prizes enable row level security;
alter table public.draw_results enable row level security;
alter table public.booking_products enable row level security;
alter table public.member_booking_choices enable row level security;

drop policy if exists "draw prizes read authenticated" on public.draw_prizes;
create policy "draw prizes read authenticated" on public.draw_prizes for select to authenticated using (true);
drop policy if exists "managers manage draw prizes" on public.draw_prizes;
create policy "managers manage draw prizes" on public.draw_prizes for all to authenticated
using (current_app_role() in ('admin','super_admin'))
with check (current_app_role() in ('admin','super_admin'));

drop policy if exists "draw results read authenticated" on public.draw_results;
create policy "draw results read authenticated" on public.draw_results for select to authenticated using (true);
drop policy if exists "managers manage draw results" on public.draw_results;
create policy "managers manage draw results" on public.draw_results for all to authenticated
using (current_app_role() in ('admin','super_admin'))
with check (current_app_role() in ('admin','super_admin'));

drop policy if exists "booking products read authenticated" on public.booking_products;
create policy "booking products read authenticated" on public.booking_products for select to authenticated using (true);
drop policy if exists "managers manage booking products" on public.booking_products;
create policy "managers manage booking products" on public.booking_products for all to authenticated
using (current_app_role() in ('admin','super_admin'))
with check (current_app_role() in ('admin','super_admin'));

drop policy if exists "booking choices read team" on public.member_booking_choices;
create policy "booking choices read team" on public.member_booking_choices for select to authenticated
using (
  current_app_role() = 'super_admin'
  or exists (select 1 from public.members m where m.id = member_booking_choices.member_id
    and (m.assigned_agent_id = auth.uid()
      or (current_app_role() = 'admin' and is_admin_of_agent(m.assigned_agent_id))))
);
drop policy if exists "booking choices insert team" on public.member_booking_choices;
create policy "booking choices insert team" on public.member_booking_choices for insert to authenticated
with check (
  current_app_role() in ('agent','admin','super_admin')
  and exists (select 1 from public.members m where m.id = member_booking_choices.member_id
    and (current_app_role() = 'super_admin' or m.assigned_agent_id = auth.uid()
      or (current_app_role() = 'admin' and is_admin_of_agent(m.assigned_agent_id))))
);
drop policy if exists "booking choices update team" on public.member_booking_choices;
create policy "booking choices update team" on public.member_booking_choices for update to authenticated
using (
  current_app_role() = 'super_admin'
  or exists (select 1 from public.members m where m.id = member_booking_choices.member_id
    and (m.assigned_agent_id = auth.uid()
      or (current_app_role() = 'admin' and is_admin_of_agent(m.assigned_agent_id))))
)
with check (
  current_app_role() = 'super_admin'
  or exists (select 1 from public.members m where m.id = member_booking_choices.member_id
    and (m.assigned_agent_id = auth.uid()
      or (current_app_role() = 'admin' and is_admin_of_agent(m.assigned_agent_id))))
);

grant select on public.draw_prizes, public.draw_results, public.booking_products to authenticated;
grant insert, update, delete on public.draw_prizes, public.draw_results, public.booking_products to authenticated;
grant select, insert, update on public.member_booking_choices to authenticated;
