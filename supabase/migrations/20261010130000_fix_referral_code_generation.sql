-- Fix member creation on projects where pgcrypto/gen_random_bytes is unavailable.
-- New referral codes are sequential and unique: RA-REF-000001, RA-REF-000002, ...
create sequence if not exists public.referral_code_seq start 1 increment 1 minvalue 1;

create or replace function public.prepare_member_insert()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $function$
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
  if new.member_code is null or trim(new.member_code)='' then
    new.member_code := 'RA-MB-'||lpad(nextval('public.member_code_seq')::text,6,'0');
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
  else
    new.referrer_member_id:=null;
  end if;
  return new;
end;
$function$;

-- To choose the first code for a fresh sequence, setval(..., N, false) makes the next code N.
-- Example for RA-REF-000001: select setval('public.referral_code_seq', 1, false);
