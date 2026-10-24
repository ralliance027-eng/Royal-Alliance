-- Allow the same gift product to appear at multiple prize ranks in one draw.
-- Each rank is a distinct prize slot; quantity is the number of winners for that rank.
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conrelid = 'public.draw_prizes'::regclass
      and conname = 'draw_prizes_draw_id_gift_id_key'
  ) then
    alter table public.draw_prizes drop constraint draw_prizes_draw_id_gift_id_key;
  end if;
end $$;

-- A draw must have one configuration row per rank. Existing duplicate ranks, if any,
-- are normalized deterministically before adding the unique constraint.
with ranked as (
  select id, draw_id, sort_order,
         row_number() over (partition by draw_id, sort_order order by created_at, id) as rn
  from public.draw_prizes
)
update public.draw_prizes p
set sort_order = p.sort_order + 10000 + ranked.rn
from ranked
where ranked.id = p.id and ranked.rn > 1;

create unique index if not exists draw_prizes_draw_rank_uidx
  on public.draw_prizes(draw_id, sort_order);
create index if not exists draw_prizes_draw_quantity_idx
  on public.draw_prizes(draw_id, quantity);
