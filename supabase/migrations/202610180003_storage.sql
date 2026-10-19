insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('videos','videos',true,52428800,array['video/mp4']),
 ('thumbnails','thumbnails',true,5242880,array['image/jpeg']),
 ('avatars','avatars',true,5242880,array['image/jpeg'])
on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

create policy tikdog_media_read on storage.objects for select to anon,authenticated using (bucket_id in ('videos','thumbnails','avatars'));
create policy tikdog_media_insert on storage.objects for insert to authenticated with check (
 bucket_id in ('videos','thumbnails','avatars') and (storage.foldername(name))[1]=auth.uid()::text
 and exists(select 1 from public.users where id=auth.uid())
);
create policy tikdog_media_delete on storage.objects for delete to authenticated using (
 bucket_id in ('videos','thumbnails','avatars') and (storage.foldername(name))[1]=auth.uid()::text
);
-- Objects are immutable: a new UUID is used on retry or replacement, and no UPDATE policy exists.
