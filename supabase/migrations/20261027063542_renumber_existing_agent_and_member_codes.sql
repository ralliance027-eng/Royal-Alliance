begin;

create table if not exists public.code_migration_history (
  id bigint generated always as identity primary key,
  entity_type text not null check (entity_type in ('agent','member')),
  record_id uuid not null,
  old_code text not null,
  new_code text not null,
  changed_at timestamptz not null default now(),
  unique (entity_type, record_id, new_code)
);

-- Build deterministic maps; UUIDs and all relationship columns remain unchanged.
create temporary table _ra_agent_code_map on commit drop as
select id, agent_code as old_code,
       lpad(row_number() over (order by created_at nulls first, id)::text, 3, '0') as new_code
from public.agents;
create temporary table _ra_member_code_map on commit drop as
select id, member_code as old_code,
       lpad(row_number() over (order by created_at nulls first, id)::text, 5, '0') as new_code
from public.members;

-- Guardrails: avoid silently exceeding the agreed code ranges.
do $$ begin
  if (select count(*) from _ra_agent_code_map) > 999 then
    raise exception 'Agent count exceeds 3-digit code capacity';
  end if;
  if (select count(*) from _ra_member_code_map) > 99999 then
    raise exception 'Member count exceeds 5-digit code capacity';
  end if;
end $$;

insert into public.code_migration_history(entity_type, record_id, old_code, new_code)
select 'agent', id, old_code, new_code from _ra_agent_code_map
where old_code is distinct from new_code;
insert into public.code_migration_history(entity_type, record_id, old_code, new_code)
select 'member', id, old_code, new_code from _ra_member_code_map
where old_code is distinct from new_code;

-- Two-stage update avoids collisions with unique constraints while renumbering.
update public.agents a
set agent_code = '__RA_AGENT_MIGRATING__' || replace(a.id::text, '-', '')
where exists (select 1 from _ra_agent_code_map m where m.id = a.id and m.old_code is distinct from m.new_code);
update public.members m
set member_code = '__RA_MEMBER_MIGRATING__' || replace(m.id::text, '-', '')
where exists (select 1 from _ra_member_code_map x where x.id = m.id and x.old_code is distinct from x.new_code);

update public.agents a set agent_code = m.new_code
from _ra_agent_code_map m where a.id = m.id and m.old_code is distinct from m.new_code;
update public.members m set member_code = x.new_code
from _ra_member_code_map x where m.id = x.id and x.old_code is distinct from x.new_code;

-- Keep the cached agent code on each member aligned with the assigned agent.
update public.members m
set agent_code = a.agent_code
from public.agents a
where m.assigned_agent_id = a.id
  and m.agent_code is distinct from a.agent_code;

-- Make future generated codes continue after the existing records.
create sequence if not exists public.member_code_seq;
create sequence if not exists public.agent_code_seq;
select setval('public.member_code_seq', greatest((select count(*) from public.members), 1), true);
select setval('public.agent_code_seq', greatest((select count(*) from public.agents), 1), true);

commit;

notify pgrst, 'reload schema';