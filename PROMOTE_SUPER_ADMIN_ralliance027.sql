-- Royal Alliance: promote an existing Auth account to Super Admin.
-- Run once in Supabase Dashboard > SQL Editor for the configured project.
-- This script fails safely if the email has not registered in Supabase Auth.

do $$
declare
  target_user_id uuid;
begin
  select id into target_user_id
  from auth.users
  where lower(email) = lower('ralliance027@gmail.com')
  limit 1;

  if target_user_id is null then
    raise exception 'No Supabase Auth user found for ralliance027@gmail.com. First sign up/login once, then run this script.';
  end if;

  insert into public.profiles (id, full_name, email, role, status)
  select target_user_id,
         coalesce(u.raw_user_meta_data->>'full_name', 'Royal Alliance Super Admin'),
         u.email,
         'super_admin',
         'active'
  from auth.users u
  where u.id = target_user_id
  on conflict (id) do update
    set role = 'super_admin',
        status = 'active',
        email = excluded.email,
        updated_at = now();
end $$;

-- Verify the resulting role/status (should return one row: super_admin / active).
select id, email, role, status
from public.profiles
where lower(email) = lower('ralliance027@gmail.com');
