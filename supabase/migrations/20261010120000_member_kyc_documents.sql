-- Member KYC documents: metadata protected by RLS; files live in a PRIVATE bucket.
create table if not exists public.member_kyc_documents (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  document_type text not null check (document_type in ('pan_card','aadhaar_card','driving_license','passport')),
  document_number text not null check (length(trim(document_number)) between 2 and 80),
  storage_path text not null unique,
  original_file_name text not null,
  content_type text not null check (content_type in ('application/pdf','image/jpeg','image/png','image/webp')),
  file_size bigint not null check (file_size > 0 and file_size <= 10485760),
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);
create index if not exists member_kyc_documents_member_idx on public.member_kyc_documents(member_id, created_at desc);
alter table public.member_kyc_documents enable row level security;

-- Super Admin can access all KYC metadata; Admins only their assigned agents' members;
-- Agents only their own members.
drop policy if exists "member KYC read authorized team" on public.member_kyc_documents;
create policy "member KYC read authorized team" on public.member_kyc_documents
for select to authenticated using (
  exists (
    select 1 from public.profiles p
    where p.id=auth.uid() and p.status='active' and (
      p.role='super_admin' or
      (p.role='admin' and exists(select 1 from public.members m join public.agents a on a.id=m.assigned_agent_id where m.id=member_kyc_documents.member_id and a.admin_id=auth.uid())) or
      (p.role='agent' and exists(select 1 from public.members m where m.id=member_kyc_documents.member_id and m.assigned_agent_id=auth.uid()))
    )
  )
);
drop policy if exists "member KYC insert authorized team" on public.member_kyc_documents;
create policy "member KYC insert authorized team" on public.member_kyc_documents
for insert to authenticated with check (
  uploaded_by=auth.uid() and exists (
    select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and (
      p.role='super_admin' or
      (p.role='admin' and exists(select 1 from public.members m join public.agents a on a.id=m.assigned_agent_id where m.id=member_kyc_documents.member_id and a.admin_id=auth.uid())) or
      (p.role='agent' and exists(select 1 from public.members m where m.id=member_kyc_documents.member_id and m.assigned_agent_id=auth.uid()))
    )
  )
);

insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('royal-alliance-kyc','royal-alliance-kyc',false,10485760,array['application/pdf','image/jpeg','image/png','image/webp'])
on conflict (id) do update set public=false,file_size_limit=10485760,allowed_mime_types=array['application/pdf','image/jpeg','image/png','image/webp'];

drop policy if exists "KYC upload own member path" on storage.objects;
create policy "KYC upload own member path" on storage.objects for insert to authenticated
with check (
  bucket_id='royal-alliance-kyc' and (storage.foldername(name))[1]=auth.uid()::text and
  exists (
    select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and (
      p.role='super_admin' or
      (p.role='admin' and exists(select 1 from public.members m join public.agents a on a.id=m.assigned_agent_id where m.id::text=(storage.foldername(name))[2] and a.admin_id=auth.uid())) or
      (p.role='agent' and exists(select 1 from public.members m where m.id::text=(storage.foldername(name))[2] and m.assigned_agent_id=auth.uid()))
    )
  )
);
drop policy if exists "KYC read authorized member team" on storage.objects;
create policy "KYC read authorized member team" on storage.objects for select to authenticated
using (
  bucket_id='royal-alliance-kyc' and exists (
    select 1 from public.member_kyc_documents k join public.members m on m.id=k.member_id
    where k.storage_path=name and (
      exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.role='super_admin') or
      exists(select 1 from public.profiles p join public.agents a on a.admin_id=p.id where p.id=auth.uid() and p.status='active' and p.role='admin' and a.id=m.assigned_agent_id) or
      exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.role='agent' and m.assigned_agent_id=p.id)
    )
  )
);
-- No public read, anonymous access, or direct update/delete policy is granted for KYC objects.
