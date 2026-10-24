-- Shared image bucket for product/prize/booking-product uploads.
insert into storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
values ('royal-alliance-media','royal-alliance-media',true,5242880,array['image/png','image/jpeg','image/webp'])
on conflict (id) do update set public=true,file_size_limit=5242880,allowed_mime_types=array['image/png','image/jpeg','image/webp'];

drop policy if exists "Royal Alliance media public read" on storage.objects;
create policy "Royal Alliance media public read" on storage.objects for select
using (bucket_id='royal-alliance-media');

drop policy if exists "Royal Alliance media authenticated upload" on storage.objects;
create policy "Royal Alliance media authenticated upload" on storage.objects for insert to authenticated
with check (bucket_id='royal-alliance-media' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.role in ('super_admin','admin','agent')));

drop policy if exists "Royal Alliance media owner update" on storage.objects;
create policy "Royal Alliance media owner update" on storage.objects for update to authenticated
using (bucket_id='royal-alliance-media' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.role in ('super_admin','admin','agent')))
with check (bucket_id='royal-alliance-media' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.role in ('super_admin','admin','agent')));

drop policy if exists "Royal Alliance media owner delete" on storage.objects;
create policy "Royal Alliance media owner delete" on storage.objects for delete to authenticated
using (bucket_id='royal-alliance-media' and (storage.foldername(name))[1]=auth.uid()::text and exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active' and p.role in ('super_admin','admin','agent')));
