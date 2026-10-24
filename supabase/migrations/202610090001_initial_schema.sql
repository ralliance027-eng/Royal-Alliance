-- Royal Alliance Annual Member Draw System
-- Apply in Supabase SQL Editor or via `supabase db push`.
create extension if not exists pgcrypto;
create sequence if not exists public.member_code_seq start 1;
create sequence if not exists public.agent_code_seq start 1;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  email text,
  mobile text,
  role text not null default 'agent' check (role in ('super_admin','admin','agent')),
  status text not null default 'pending' check (status in ('active','inactive','pending')),
  assigned_admin_id uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_role_status_idx on public.profiles(role,status);

create table if not exists public.agents (
  id uuid primary key references public.profiles(id) on delete cascade,
  agent_code text unique not null,
  admin_id uuid references public.profiles(id),
  full_name text not null default '',
  email text,
  mobile text,
  status text not null default 'active' check (status in ('active','inactive','pending')),
  role text not null default 'agent',
  address text,
  joining_date date not null default current_date,
  created_at timestamptz not null default now()
);

create table if not exists public.members (
  id uuid primary key default gen_random_uuid(),
  member_code text unique not null,
  full_name text not null,
  mobile text not null,
  address text,
  nominee_name text,
  nominee_mobile text,
  joining_date date not null default current_date,
  installment_amount numeric(12,2) not null default 0 check (installment_amount >= 0),
  installment_frequency text not null default 'monthly' check (installment_frequency in ('monthly','yearly','one_time')),
  assigned_agent_id uuid not null references public.profiles(id),
  agent_code text,
  referred_by_code text,
  referrer_member_id uuid references public.members(id),
  referral_code text unique not null,
  status text not null default 'active' check (status in ('active','inactive','winner','blocked')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (mobile)
);
create index if not exists members_agent_idx on public.members(assigned_agent_id);
create index if not exists members_referrer_idx on public.members(referrer_member_id);
create index if not exists members_status_idx on public.members(status);

create table if not exists public.gifts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  estimated_value numeric(12,2) not null default 0 check (estimated_value >= 0),
  image_url text,
  storage_path text,
  status text not null default 'active' check (status in ('active','inactive','reserved','awarded')),
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.draws (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  draw_month int not null check (draw_month between 1 and 12),
  draw_year int not null check (draw_year between 2020 and 2200),
  gift_id uuid references public.gifts(id),
  draw_date date,
  status text not null default 'upcoming' check (status in ('draft','upcoming','open','completed','cancelled')),
  winner_member_id uuid references public.members(id),
  declared_by uuid references public.profiles(id),
  declared_at timestamptz,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(draw_month,draw_year)
);
insert into public.draws(title,draw_month,draw_year,status)
select to_char(make_date(extract(year from current_date)::int, month_num, 1), 'FMMonth') || ' Draw', month_num, extract(year from current_date)::int, 'upcoming'
from generate_series(1,12) as month_num
on conflict(draw_month,draw_year) do nothing;

create table if not exists public.payment_entries (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id),
  agent_id uuid not null references public.profiles(id),
  amount numeric(12,2) not null check (amount > 0),
  installment_month text not null,
  payment_mode text not null default 'cash' check (payment_mode in ('cash','upi','bank_transfer','cheque','other')),
  payment_date date not null default current_date,
  transaction_reference text,
  notes text,
  status text not null default 'pending' check (status in ('pending','approved','rejected','reversed','refunded')),
  submitted_at timestamptz not null default now(),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  office_cash_received boolean not null default false,
  office_received_by uuid references public.profiles(id),
  office_received_at timestamptz,
  office_receipt_number text,
  rejection_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists payments_member_idx on public.payment_entries(member_id,created_at desc);
create index if not exists payments_agent_idx on public.payment_entries(agent_id,status);
create index if not exists payments_status_idx on public.payment_entries(status,created_at desc);
create unique index if not exists payments_reference_unique_idx on public.payment_entries(transaction_reference) where transaction_reference is not null and transaction_reference <> '';

create table if not exists public.cash_deposit_batches (
  id uuid primary key default gen_random_uuid(),
  agent_id uuid not null references public.profiles(id),
  received_by uuid not null references public.profiles(id),
  amount numeric(12,2) not null check (amount > 0),
  deposit_date date not null default current_date,
  receipt_number text unique,
  notes text,
  status text not null default 'received' check (status in ('received','reconciled','disputed')),
  created_at timestamptz not null default now()
);

create table if not exists public.earnings_ledger (
  id uuid primary key default gen_random_uuid(),
  beneficiary_profile_id uuid references public.profiles(id),
  beneficiary_member_id uuid references public.members(id),
  earning_type text not null check (earning_type in ('agent_commission','member_referral')),
  source_payment_id uuid not null references public.payment_entries(id),
  basis_amount numeric(12,2) not null check (basis_amount >= 0),
  rate numeric(6,4) not null check (rate >= 0),
  amount numeric(12,2) not null check (amount >= 0),
  status text not null default 'available' check (status in ('available','reserved','paid','reversed')),
  created_at timestamptz not null default now(),
  unique(earning_type,source_payment_id)
);
create index if not exists earnings_beneficiary_profile_idx on public.earnings_ledger(beneficiary_profile_id,status);
create index if not exists earnings_beneficiary_member_idx on public.earnings_ledger(beneficiary_member_id,status);

create table if not exists public.payout_requests (
  id uuid primary key default gen_random_uuid(),
  requested_by_profile_id uuid not null default auth.uid() references public.profiles(id),
  beneficiary_member_id uuid references public.members(id),
  amount numeric(12,2) not null check (amount > 0),
  payout_method text not null default 'bank_transfer' check (payout_method in ('bank_transfer','upi','cash','cheque')),
  account_reference text,
  status text not null default 'requested' check (status in ('requested','under_review','approved','paid','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  paid_at timestamptz,
  payment_reference text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.draw_eligible_members (
  id uuid primary key default gen_random_uuid(),
  draw_id uuid not null references public.draws(id) on delete cascade,
  member_id uuid not null references public.members(id),
  eligibility_status text not null default 'eligible' check (eligibility_status in ('eligible','excluded','winner')),
  reason text,
  snapshotted_at timestamptz not null default now(),
  unique(draw_id,member_id)
);

create table if not exists public.gift_deliveries (
  id uuid primary key default gen_random_uuid(),
  draw_id uuid not null unique references public.draws(id),
  member_id uuid not null references public.members(id),
  gift_id uuid references public.gifts(id),
  status text not null default 'pending' check (status in ('pending','approved','dispatched','delivered','cancelled')),
  delivery_address text,
  tracking_reference text,
  updated_by uuid references public.profiles(id),
  delivered_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.notification_logs (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members(id),
  recipient_phone text not null,
  template_name text not null,
  related_payment_id uuid references public.payment_entries(id),
  related_draw_id uuid references public.draws(id),
  provider_message_id text,
  status text not null default 'queued' check (status in ('queued','sent','delivered','failed','read')),
  error_message text,
  attempt_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.company_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);
insert into public.company_settings(key,value) values
 ('company', '{"name":"Royal Alliance Multiventure Services Pvt. Ltd.","theme":"green-gold-white"}'),
 ('commission', '{"agent_rate":0.10}'),
 ('referral', '{"rate":0.02,"minimum_valid_referrals":2,"basis":"approved_referred_collection"}'),
 ('draw', '{"months":12,"exclude_previous_winners":true}')
on conflict (key) do nothing;

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function public.current_app_role()
returns text language sql stable security definer set search_path=public,auth
as $$ select role from public.profiles where id=auth.uid() and status='active' $$;

create or replace function public.is_admin_of_agent(p_agent_id uuid)
returns boolean language sql stable security definer set search_path=public,auth
as $$ select exists(select 1 from public.agents a where a.id=p_agent_id and a.admin_id=auth.uid()) $$;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path=public
as $$ begin new.updated_at=now(); return new; end $$;

create or replace function public.handle_auth_user_created()
returns trigger language plpgsql security definer set search_path=public,auth
as $$ begin
 insert into public.profiles(id,full_name,email,role,status)
 values(new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email, 'agent', 'pending')
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_auth_user_created();

create or replace function public.sync_agent_profile()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
 if new.role='agent' then
   insert into public.agents(id,agent_code,admin_id,full_name,email,mobile,status,role)
   values(new.id,'RA-AG-'||lpad(nextval('public.agent_code_seq')::text,4,'0'),new.assigned_admin_id,new.full_name,new.email,new.mobile,new.status,new.role)
   on conflict(id) do update set admin_id=excluded.admin_id,full_name=excluded.full_name,email=excluded.email,mobile=excluded.mobile,status=excluded.status,role=excluded.role;
 else
   delete from public.agents where id=new.id;
 end if;
 return new;
end $$;
drop trigger if exists profiles_sync_agent on public.profiles;
create trigger profiles_sync_agent after insert or update of role,assigned_admin_id on public.profiles for each row execute function public.sync_agent_profile();

create or replace function public.prepare_member_insert()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare ref_id uuid;
begin
 if coalesce(public.current_app_role(), '') not in ('agent','admin','super_admin') then raise exception 'Not authorized to create members'; end if;
 if public.current_app_role()='agent' then new.assigned_agent_id:=auth.uid();
 elsif new.assigned_agent_id is null then raise exception 'An assigned agent is required'; end if;
 if new.member_code is null or new.member_code='' then new.member_code:='RA-MB-'||lpad(nextval('public.member_code_seq')::text,6,'0'); end if;
 if new.referral_code is null or new.referral_code='' then new.referral_code:='RA-REF-'||upper(substr(encode(gen_random_bytes(5),'hex'),1,8)); end if;
 select agent_code into new.agent_code from public.agents where id=new.assigned_agent_id;
 if new.created_by is null then new.created_by:=auth.uid(); end if;
 if new.referred_by_code is not null and new.referred_by_code<>'' then
   select id into ref_id from public.members where referral_code=new.referred_by_code limit 1;
   if ref_id=new.id then raise exception 'Self referral is not allowed'; end if;
   if ref_id is not null then new.referrer_member_id:=ref_id; end if;
 end if;
 return new;
end $$;
drop trigger if exists members_prepare_insert on public.members;
create trigger members_prepare_insert before insert on public.members for each row execute function public.prepare_member_insert();

create or replace function public.prepare_payment_insert()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare m public.members%rowtype;
begin
 select * into m from public.members where id=new.member_id;
 if not found then raise exception 'Member not found'; end if;
 if m.status='winner' then raise exception 'Future payment collection is disabled for winners'; end if;
 if public.current_app_role()='agent' then
   if m.assigned_agent_id<>auth.uid() then raise exception 'You can only record payments for your own members'; end if;
   new.agent_id:=auth.uid();
 elsif public.current_app_role() in ('admin','super_admin') then
   new.agent_id:=m.assigned_agent_id;
 else raise exception 'Not authorized to record payments'; end if;
 new.status:='pending'; new.reviewed_by:=null; new.reviewed_at:=null;
 return new;
end $$;
drop trigger if exists payments_prepare_insert on public.payment_entries;
create trigger payments_prepare_insert before insert on public.payment_entries for each row execute function public.prepare_payment_insert();

create or replace function public.approve_payment(p_payment_id uuid, p_reason text default null)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare p public.payment_entries%rowtype; m public.members%rowtype; role_name text; referred_count int;
begin
 role_name:=public.current_app_role();
 if coalesce(role_name, '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can approve payments'; end if;
 select * into p from public.payment_entries where id=p_payment_id for update;
 if not found then raise exception 'Payment entry not found'; end if;
 if p.status<>'pending' then raise exception 'Only pending payments can be approved'; end if;
 if role_name='admin' and not public.is_admin_of_agent(p.agent_id) then raise exception 'Payment is outside your assigned team'; end if;
 select * into m from public.members where id=p.member_id;
 update public.payment_entries set status='approved',reviewed_by=auth.uid(),reviewed_at=now(),office_cash_received=(p.payment_mode='cash'),office_received_by=case when p.payment_mode='cash' then auth.uid() else null end,office_received_at=case when p.payment_mode='cash' then now() else null end,office_receipt_number=case when p.payment_mode='cash' then coalesce(nullif(p_reason,''),'OFFICE-'||upper(substr(replace(p.id::text,'-',''),1,8))) else null end,updated_at=now(),notes=case when p_reason is not null then concat_ws(E'\n',notes,'Approval note: '||p_reason) else notes end where id=p_payment_id;
 -- Unique source-payment key prevents duplicate commission/referral ledger entries.
 insert into public.earnings_ledger(beneficiary_profile_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
 values(p.agent_id,'agent_commission',p.id,p.amount,0.10,round(p.amount*0.10,2),'available')
 on conflict(earning_type,source_payment_id) do nothing;
 if m.referrer_member_id is not null then
   select count(*) into referred_count from public.members where referrer_member_id=m.referrer_member_id and status in ('active','winner');
   if referred_count>=2 then
     insert into public.earnings_ledger(beneficiary_member_id,earning_type,source_payment_id,basis_amount,rate,amount,status)
     values(m.referrer_member_id,'member_referral',p.id,p.amount,0.02,round(p.amount*0.02,2),'available')
     on conflict(earning_type,source_payment_id) do nothing;
   end if;
 end if;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'payment.approved','payment_entry',p.id::text,jsonb_build_object('amount',p.amount,'member_id',p.member_id,'agent_id',p.agent_id));
 return jsonb_build_object('ok',true,'payment_id',p.id,'status','approved','message','Payment approved; eligible earnings recorded.');
end $$;

create or replace function public.reject_payment(p_payment_id uuid,p_reason text default 'Rejected by reviewer')
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare p public.payment_entries%rowtype; role_name text;
begin
 role_name:=public.current_app_role();
 if coalesce(role_name, '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can reject payments'; end if;
 select * into p from public.payment_entries where id=p_payment_id for update;
 if not found then raise exception 'Payment entry not found'; end if;
 if p.status<>'pending' then raise exception 'Only pending payments can be rejected'; end if;
 if role_name='admin' and not public.is_admin_of_agent(p.agent_id) then raise exception 'Payment is outside your assigned team'; end if;
 update public.payment_entries set status='rejected',reviewed_by=auth.uid(),reviewed_at=now(),rejection_reason=coalesce(p_reason,'Rejected'),updated_at=now() where id=p_payment_id;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'payment.rejected','payment_entry',p.id::text,jsonb_build_object('reason',coalesce(p_reason,'Rejected')));
 return jsonb_build_object('ok',true,'payment_id',p.id,'status','rejected');
end $$;

create or replace function public.update_draw_config(p_draw_id uuid,p_title text,p_month int,p_year int,p_gift_id uuid,p_draw_date date)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare role_name text; d public.draws%rowtype;
begin
 role_name:=public.current_app_role();
 if coalesce(role_name, '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can configure draws'; end if;
 select * into d from public.draws where id=p_draw_id for update;
 if not found then raise exception 'Draw not found'; end if;
 if d.status='completed' then raise exception 'Completed draws cannot be edited'; end if;
 if p_month not between 1 and 12 then raise exception 'Month must be between 1 and 12'; end if;
 update public.draws set title=p_title,draw_month=p_month,draw_year=p_year,gift_id=p_gift_id,draw_date=p_draw_date,updated_at=now() where id=p_draw_id;
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'draw.config_updated','draw',p_draw_id::text,jsonb_build_object('title',p_title,'month',p_month,'year',p_year,'gift_id',p_gift_id,'draw_date',p_draw_date));
 return jsonb_build_object('ok',true,'draw_id',p_draw_id);
end $$;

create or replace function public.declare_draw_winner(p_draw_id uuid,p_member_id uuid)
returns jsonb language plpgsql security definer set search_path=public,auth
as $$
declare d public.draws%rowtype; m public.members%rowtype; role_name text;
begin
 role_name:=public.current_app_role();
 if coalesce(role_name, '') not in ('admin','super_admin') then raise exception 'Only Admin or Super Admin can declare a winner'; end if;
 select * into d from public.draws where id=p_draw_id for update;
 if not found then raise exception 'Draw not found'; end if;
 if d.status='completed' or d.winner_member_id is not null then raise exception 'This draw already has a winner'; end if;
 select * into m from public.members where id=p_member_id for update;
 if not found or m.status<>'active' then raise exception 'Member is not active or eligible'; end if;
 if exists(select 1 from public.draws where winner_member_id=p_member_id and status='completed') then raise exception 'Member has already won a previous draw'; end if;
 if exists(select 1 from public.draw_eligible_members where draw_id=p_draw_id and member_id=p_member_id and eligibility_status='excluded') then raise exception 'Member is excluded from this draw'; end if;
 update public.draws set winner_member_id=p_member_id,status='completed',declared_by=auth.uid(),declared_at=now(),updated_at=now() where id=p_draw_id;
 update public.members set status='winner',updated_at=now() where id=p_member_id;
 insert into public.gift_deliveries(draw_id,member_id,gift_id,status,updated_by) values(d.id,m.id,d.gift_id,'pending',auth.uid()) on conflict(draw_id) do nothing;
 insert into public.draw_eligible_members(draw_id,member_id,eligibility_status,reason) values(d.id,m.id,'winner','Declared winner') on conflict(draw_id,member_id) do update set eligibility_status='winner',reason='Declared winner';
 insert into public.audit_logs(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'draw.winner_declared','draw',d.id::text,jsonb_build_object('member_id',m.id,'gift_id',d.gift_id));
 return jsonb_build_object('ok',true,'draw_id',d.id,'winner_member_id',m.id,'member_status','winner');
end $$;


create or replace function public.guard_member_winner_status()
returns trigger language plpgsql security definer set search_path=public
as $$ begin
 if new.status='winner' and old.status is distinct from new.status and not exists(select 1 from public.draws d where d.winner_member_id=new.id and d.status='completed') then
   raise exception 'Winner status can only be assigned through a completed draw';
 end if;
 return new;
end $$;
drop trigger if exists members_guard_winner_status on public.members;
create trigger members_guard_winner_status before update of status on public.members for each row execute function public.guard_member_winner_status();

-- RLS
alter table public.profiles enable row level security;
alter table public.agents enable row level security;
alter table public.members enable row level security;
alter table public.gifts enable row level security;
alter table public.draws enable row level security;
alter table public.payment_entries enable row level security;
alter table public.cash_deposit_batches enable row level security;
alter table public.earnings_ledger enable row level security;
alter table public.payout_requests enable row level security;
alter table public.draw_eligible_members enable row level security;
alter table public.gift_deliveries enable row level security;
alter table public.notification_logs enable row level security;
alter table public.company_settings enable row level security;
alter table public.audit_logs enable row level security;

create policy "profiles read self and authorized team" on public.profiles for select to authenticated using (id=auth.uid() or public.current_app_role()='super_admin' or (public.current_app_role()='admin' and assigned_admin_id=auth.uid()));
-- Profile role/status changes are intentionally not allowed from the browser client. Use the protected create-user Edge Function / Supabase Dashboard.
create policy "agents read by team" on public.agents for select to authenticated using (id=auth.uid() or public.current_app_role()='super_admin' or (public.current_app_role()='admin' and admin_id=auth.uid()));
create policy "members read by owner or managers" on public.members for select to authenticated using (assigned_agent_id=auth.uid() or public.current_app_role()='super_admin' or (public.current_app_role()='admin' and public.is_admin_of_agent(assigned_agent_id)));
create policy "agents create own members" on public.members for insert to authenticated with check (public.current_app_role() in ('agent','admin','super_admin') and (public.current_app_role()<>'agent' or assigned_agent_id=auth.uid()));
create policy "managers update members" on public.members for update to authenticated using (public.current_app_role() in ('admin','super_admin') and (public.current_app_role()='super_admin' or public.is_admin_of_agent(assigned_agent_id))) with check (public.current_app_role()='super_admin' or (public.current_app_role()='admin' and public.is_admin_of_agent(assigned_agent_id)));
create policy "gifts read authenticated" on public.gifts for select to authenticated using (true);
create policy "managers manage gifts" on public.gifts for all to authenticated using (public.current_app_role() in ('admin','super_admin')) with check (public.current_app_role() in ('admin','super_admin'));
create policy "draws read authenticated" on public.draws for select to authenticated using (true);
create policy "managers insert draws" on public.draws for insert to authenticated with check (public.current_app_role() in ('admin','super_admin'));
-- Draw result/status updates are performed through declare_draw_winner RPC, not direct browser updates.
create policy "payments read by owner and managers" on public.payment_entries for select to authenticated using (agent_id=auth.uid() or public.current_app_role()='super_admin' or (public.current_app_role()='admin' and public.is_admin_of_agent(agent_id)));
create policy "agents insert payment entries" on public.payment_entries for insert to authenticated with check (public.current_app_role() in ('agent','admin','super_admin'));
-- No direct UPDATE policy on payment_entries: approval/rejection must go through protected RPCs.
create policy "cash batches visible to manager team" on public.cash_deposit_batches for select to authenticated using (public.current_app_role()='super_admin' or received_by=auth.uid() or public.is_admin_of_agent(agent_id));
create policy "admins manage cash batches" on public.cash_deposit_batches for insert to authenticated with check (public.current_app_role() in ('admin','super_admin'));
create policy "earnings visible to beneficiary or managers" on public.earnings_ledger for select to authenticated using (beneficiary_profile_id=auth.uid() or public.current_app_role()='super_admin' or (public.current_app_role()='admin' and (beneficiary_profile_id is null or public.is_admin_of_agent(beneficiary_profile_id))));
create policy "payouts visible to requester or managers" on public.payout_requests for select to authenticated using (requested_by_profile_id=auth.uid() or public.current_app_role() in ('admin','super_admin'));
create policy "agent request payout" on public.payout_requests for insert to authenticated with check (requested_by_profile_id=auth.uid() and public.current_app_role()='agent');
create policy "managers update payouts" on public.payout_requests for update to authenticated using (public.current_app_role() in ('admin','super_admin')) with check (public.current_app_role() in ('admin','super_admin'));
create policy "draw eligibility managers only" on public.draw_eligible_members for select to authenticated using (public.current_app_role() in ('admin','super_admin'));
create policy "draw eligibility manager manage" on public.draw_eligible_members for all to authenticated using (public.current_app_role() in ('admin','super_admin')) with check (public.current_app_role() in ('admin','super_admin'));
create policy "gift delivery manager read" on public.gift_deliveries for select to authenticated using (public.current_app_role() in ('admin','super_admin'));
create policy "gift delivery manager update" on public.gift_deliveries for update to authenticated using (public.current_app_role() in ('admin','super_admin')) with check (public.current_app_role() in ('admin','super_admin'));
create policy "notification logs managers read" on public.notification_logs for select to authenticated using (public.current_app_role() in ('admin','super_admin'));
create policy "settings read authenticated" on public.company_settings for select to authenticated using (true);
create policy "super admin manage settings" on public.company_settings for all to authenticated using (public.current_app_role()='super_admin') with check (public.current_app_role()='super_admin');
create policy "audit logs managers read" on public.audit_logs for select to authenticated using (public.current_app_role() in ('admin','super_admin'));

-- Sensitive RPCs are callable by authenticated users, but enforce roles inside the function.
revoke all on function public.approve_payment(uuid,text) from public;
grant execute on function public.approve_payment(uuid,text) to authenticated;
revoke all on function public.reject_payment(uuid,text) from public;
grant execute on function public.reject_payment(uuid,text) to authenticated;
revoke all on function public.declare_draw_winner(uuid,uuid) from public;
grant execute on function public.declare_draw_winner(uuid,uuid) to authenticated;
revoke all on function public.update_draw_config(uuid,text,int,int,uuid,date) from public;
grant execute on function public.update_draw_config(uuid,text,int,int,uuid,date) to authenticated;

-- Storage bucket for uploaded prize images. Upload permissions can be refined per deployment.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('prize-images','prize-images',true,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do nothing;
create policy "authenticated users can view prize images" on storage.objects for select to authenticated using (bucket_id='prize-images');
create policy "admins can upload prize images" on storage.objects for insert to authenticated with check (bucket_id='prize-images' and public.current_app_role() in ('admin','super_admin'));
create policy "admins can update prize images" on storage.objects for update to authenticated using (bucket_id='prize-images' and public.current_app_role() in ('admin','super_admin')) with check (bucket_id='prize-images' and public.current_app_role() in ('admin','super_admin'));

-- Common updated_at triggers
DO $$ DECLARE t text; BEGIN FOREACH t IN ARRAY ARRAY['profiles','members','gifts','draws','payment_entries','payout_requests','notification_logs','gift_deliveries'] LOOP EXECUTE format('drop trigger if exists %I_updated_at on public.%I',t,t); EXECUTE format('create trigger %I_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t); END LOOP; END $$;
