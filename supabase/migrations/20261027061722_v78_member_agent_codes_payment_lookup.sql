-- Royal Alliance V78: compact member/agent codes and payment lookup support.
-- Existing member/payment records are preserved; new codes use the requested formats.
create sequence if not exists public.member_code_seq start 1;
create sequence if not exists public.agent_code_seq start 1;

create or replace function public.ra_next_member_code()
returns text language plpgsql security definer set search_path=public
as $$
declare n bigint;
begin
  n := nextval('public.member_code_seq');
  if n > 99999 then raise exception 'Member code range 00001-99999 exhausted'; end if;
  return lpad(n::text,5,'0');
end $$;

create or replace function public.ra_next_agent_code()
returns text language plpgsql security definer set search_path=public
as $$
declare n bigint;
begin
  n := nextval('public.agent_code_seq');
  if n > 999 then raise exception 'Agent code range 001-999 exhausted'; end if;
  return lpad(n::text,3,'0');
end $$;

-- Set sequences beyond numeric codes already in use so future inserts do not collide.
select setval('public.member_code_seq',
  greatest(1, coalesce((select max(nullif(regexp_replace(member_code,'[^0-9]','','g'),'')::bigint)
    from public.members where member_code ~ '^[0-9]{5}$'),0)+1), false);
select setval('public.agent_code_seq',
  greatest(1, coalesce((select max(nullif(regexp_replace(agent_code,'[^0-9]','','g'),'')::bigint)
    from public.agents where agent_code ~ '^[0-9]{3}$'),0)+1), false);

create or replace function public.prepare_member_insert()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare ref_id uuid; role_name text;
begin
  role_name := public.current_app_role();
  if coalesce(role_name,'') not in ('agent','admin','super_admin') then
    raise exception 'Not authorized to create members';
  end if;
  if role_name='agent' then
    new.assigned_agent_id := auth.uid();
  elsif role_name='admin' then
    if new.assigned_agent_id is null or not public.is_admin_of_agent(new.assigned_agent_id) then
      raise exception 'Admin can only assign members to agents in their own team';
    end if;
  elsif new.assigned_agent_id is null then
    raise exception 'An assigned agent is required';
  end if;
  if new.member_code is null or trim(new.member_code)='' or new.member_code like 'RA-MB-%' then
    new.member_code := public.ra_next_member_code();
  end if;
  if new.referral_code is null or trim(new.referral_code)='' then
    new.referral_code := 'RA-REF-'||lpad(nextval('public.referral_code_seq')::text,6,'0');
  end if;
  select a.agent_code into new.agent_code from public.agents a
    where a.id=new.assigned_agent_id and a.status='active';
  if new.agent_code is null then raise exception 'Assigned Agent is not an active Agent account'; end if;
  if new.created_by is null then new.created_by:=auth.uid(); end if;
  if nullif(trim(new.referred_by_code),'') is not null then
    select m.id into ref_id from public.members m
      where m.referral_code=trim(new.referred_by_code) and m.status in ('active','winner') limit 1;
    if ref_id is null then raise exception 'Referral code is invalid or inactive'; end if;
    if new.id is not null and ref_id=new.id then raise exception 'Self referral is not allowed'; end if;
    new.referrer_member_id:=ref_id;
  else new.referrer_member_id:=null;
  end if;
  return new;
end $$;

create or replace function public.sync_agent_profile()
returns trigger language plpgsql security definer set search_path=public,auth as $$
declare assigned_code text;
begin
  if new.role in ('agent','sub_agent') then
    select agent_code into assigned_code from public.agents where id=new.id;
    if assigned_code is null or assigned_code like 'RA-AG-%' then
      assigned_code := public.ra_next_agent_code();
    end if;
    insert into public.agents(id,agent_code,admin_id,full_name,email,mobile,status,role,parent_agent_id)
    values(new.id,assigned_code,coalesce(new.assigned_admin_id,(select assigned_admin_id from public.profiles where id=new.parent_agent_id)),new.full_name,new.email,new.mobile,new.status,new.role,new.parent_agent_id)
    on conflict (id) do update set full_name=excluded.full_name,email=excluded.email,mobile=excluded.mobile,status=excluded.status,role=excluded.role,parent_agent_id=excluded.parent_agent_id,admin_id=excluded.admin_id;
  else
    delete from public.agents where id=new.id;
  end if;
  return new;
end $$;

drop trigger if exists profiles_sync_agent on public.profiles;
create trigger profiles_sync_agent after insert or update of role,assigned_admin_id,parent_agent_id,full_name,email,mobile,status on public.profiles
for each row execute function public.sync_agent_profile();

-- Lookup by member code for the payment-entry screen. Respects RLS of caller.
create index if not exists payment_entries_member_date_idx
on public.payment_entries(member_id,payment_date desc,created_at desc);
create index if not exists members_member_code_lookup_idx on public.members(member_code);
