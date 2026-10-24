-- Royal Alliance: concurrency-safe member registration (100+ simultaneous agents)
-- Safe to apply once to the linked project. Duplicate normalized mobile values abort the migration
-- instead of silently deleting or merging existing member records.

create or replace function public.normalize_member_mobile(p_mobile text)
returns text
language sql
immutable
strict
set search_path = public
as $$
  with digits as (
    select regexp_replace(p_mobile, '[^0-9]', '', 'g') as value
  )
  select case
    when value like '0091%' and length(value)=14 then substr(value,5)
    when value like '91%' and length(value)=12 then substr(value,3)
    when value like '0%' and length(value)=11 then substr(value,2)
    else value
  end
  from digits;
$$;

alter table public.members add column if not exists mobile_normalized text;
alter table public.members add column if not exists registration_request_id uuid;

-- Abort safely if historical data already contains equivalent phone numbers.
do $$
declare duplicate_groups integer;
begin
  update public.members
    set mobile_normalized = public.normalize_member_mobile(mobile)
    where mobile_normalized is distinct from public.normalize_member_mobile(mobile);

  select count(*) into duplicate_groups
  from (
    select mobile_normalized
    from public.members
    where mobile_normalized is not null and mobile_normalized <> ''
    group by mobile_normalized
    having count(*) > 1
  ) d;
  if duplicate_groups > 0 then
    raise exception 'Member registration hardening stopped: % duplicate normalized mobile group(s) already exist. Review and resolve those records before reapplying this migration.', duplicate_groups;
  end if;
end $$;

create unique index if not exists members_mobile_normalized_unique_idx
  on public.members(mobile_normalized)
  where mobile_normalized is not null and mobile_normalized <> '';
create unique index if not exists members_registration_request_unique_idx
  on public.members(registration_request_id);

create or replace function public.set_member_mobile_normalized()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.mobile_normalized := public.normalize_member_mobile(new.mobile);
  if new.mobile_normalized is null or length(new.mobile_normalized) < 10 then
    raise exception 'Enter a valid mobile number with at least 10 digits';
  end if;
  return new;
end;
$$;

drop trigger if exists members_normalize_mobile on public.members;
create trigger members_normalize_mobile
before insert or update of mobile on public.members
for each row execute function public.set_member_mobile_normalized();

-- Idempotency key makes retries of the same client submission return the same member row.
-- PostgreSQL sequences used by prepare_member_insert() are already atomic; the UNIQUE constraints
-- remain the final protection if two independent requests race.
create or replace function public.register_member_idempotent(
  p_request_id uuid,
  p_full_name text,
  p_mobile text,
  p_address text default null,
  p_nominee_name text default null,
  p_referred_by_code text default null,
  p_assigned_agent_id uuid default null,
  p_joining_date date default current_date,
  p_installment_amount numeric default 0,
  p_installment_frequency text default 'monthly'
)
returns public.members
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_member public.members%rowtype;
  role_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if p_request_id is null then
    raise exception 'Registration request key is required';
  end if;
  role_name := public.current_app_role();
  if coalesce(role_name, '') not in ('agent','admin','super_admin') then
    raise exception 'Not authorized to create members';
  end if;
  if nullif(trim(p_full_name),'') is null then
    raise exception 'Member name is required';
  end if;
  if nullif(trim(p_mobile),'') is null then
    raise exception 'Mobile number is required';
  end if;
  if p_installment_amount is null or p_installment_amount < 0 then
    raise exception 'Installment amount cannot be negative';
  end if;
  if coalesce(p_installment_frequency,'monthly') not in ('monthly','yearly','one_time') then
    raise exception 'Invalid installment frequency';
  end if;

  insert into public.members (
    registration_request_id, full_name, mobile, address, nominee_name,
    referred_by_code, assigned_agent_id, joining_date,
    installment_amount, installment_frequency
  ) values (
    p_request_id, trim(p_full_name), trim(p_mobile), nullif(trim(p_address),''),
    nullif(trim(p_nominee_name),''), nullif(trim(p_referred_by_code),''),
    p_assigned_agent_id, coalesce(p_joining_date,current_date),
    coalesce(p_installment_amount,0), coalesce(p_installment_frequency,'monthly')
  )
  on conflict (registration_request_id) do nothing;

  select * into created_member
  from public.members
  where registration_request_id = p_request_id;

  if not found then
    raise exception 'Registration could not be completed; retry with the same request key';
  end if;
  if role_name = 'agent' and created_member.assigned_agent_id <> auth.uid() then
    raise exception 'Registration request key is outside your assigned team';
  elsif role_name = 'admin' and not public.is_admin_of_agent(created_member.assigned_agent_id) then
    raise exception 'Registration request key is outside your assigned team';
  end if;
  return created_member;
exception
  when unique_violation then
    -- Keep the duplicate record untouched; return a clear message to the client.
    if exists (select 1 from public.members where registration_request_id = p_request_id) then
      select * into created_member from public.members where registration_request_id = p_request_id;
      if (role_name = 'agent' and created_member.assigned_agent_id <> auth.uid())
         or (role_name = 'admin' and not public.is_admin_of_agent(created_member.assigned_agent_id)) then
        raise exception 'Registration request key is outside your assigned team';
      end if;
      return created_member;
    end if;
    raise exception using errcode = '23505', message = 'This mobile number is already registered';
end;
$$;

revoke all on function public.register_member_idempotent(uuid,text,text,text,text,text,uuid,date,numeric,text) from public, anon;
grant execute on function public.register_member_idempotent(uuid,text,text,text,text,text,uuid,date,numeric,text) to authenticated;
revoke all on function public.normalize_member_mobile(text) from public, anon, authenticated;
revoke all on function public.set_member_mobile_normalized() from public, anon, authenticated;


-- Refresh PostgREST RPC schema cache so the frontend can discover the new RPC immediately.
notify pgrst, 'reload schema';
