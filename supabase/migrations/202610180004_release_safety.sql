-- All user contributions require approval. Clients cannot choose approval state.
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create table private.moderators (user_id uuid primary key references auth.users(id) on delete cascade);
create table private.apple_credentials (
 user_id uuid primary key references auth.users(id) on delete cascade,
 refresh_token text not null, apple_subject text not null, created_at timestamptz not null default now()
);
revoke all on all tables in schema private from public,anon,authenticated;

alter table public.users add column suspended_at timestamptz, add column deleting_at timestamptz,
 add column accepted_terms_version text, add column accepted_terms_at timestamptz;
alter table public.dogs add column status text not null default 'pending' check(status in ('pending','ready','hidden')), add column review_revision bigint not null default 1;
alter table public.comments add column status text not null default 'pending' check(status in ('pending','ready','hidden'));
alter table public.videos drop constraint videos_status_check;
alter table public.videos add constraint videos_status_check check(status in ('pending','ready','hidden'));
alter table public.videos alter column status set default 'pending';
-- Existing content is reviewed too; migrating a deployed community must not grandfather unsafe content.
update public.videos set status='pending';

alter table public.reports alter column video_id drop not null;
alter table public.reports add column comment_id uuid references public.comments(id) on delete cascade,
 add column dog_id uuid references public.dogs(id) on delete cascade,
 add column resolved_at timestamptz, add column resolution text;
alter table public.reports add constraint reports_one_target check(num_nonnulls(video_id,comment_id,dog_id)=1);
create unique index reports_comment_unique on public.reports(user_id,comment_id) where comment_id is not null;
create unique index reports_dog_unique on public.reports(user_id,dog_id) where dog_id is not null;
create index reports_open_idx on public.reports(created_at) where resolved_at is null;
create table public.moderation_actions (
 id bigint generated always as identity primary key,
 moderator_id uuid, target_kind text not null, target_id uuid not null,
 action text not null, note text not null, created_at timestamptz not null default now()
);
alter table public.moderation_actions enable row level security;
revoke all on public.moderation_actions from anon,authenticated;

create function public.is_moderator() returns boolean language sql stable security definer set search_path='' as $$
 select coalesce(auth.role()='service_role',false) or exists(select 1 from private.moderators where user_id=auth.uid());
$$;
create function public.active_owner(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users where id=target and suspended_at is null and deleting_at is null);
$$;
create function public.can_contribute() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.users where id=auth.uid() and suspended_at is null and deleting_at is null
 and accepted_terms_version='2026-10-18' and accepted_terms_at is not null);
$$;
create function public.accept_terms(terms_version text) returns void language plpgsql security definer set search_path='' as $$
begin
 if terms_version<>'2026-10-18' or not public.active_owner(auth.uid()) then raise exception 'Please sign in to accept the current terms.' using errcode='42501'; end if;
 update public.users set accepted_terms_version=terms_version,accepted_terms_at=now() where id=auth.uid();
end; $$;
create function public.account_state() returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('terms_version',accepted_terms_version,'is_suspended',suspended_at is not null,'is_deleting',deleting_at is not null)
 from public.users where id=auth.uid();
$$;
-- This helper deliberately bypasses dog RLS to avoid recursive video/storage policies.
create function public.visible_dog(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.dogs d where d.id=target and public.active_owner(d.owner_id)
 and public.can_see_owner(d.owner_id) and (d.status='ready' or d.owner_id=auth.uid()));
$$;
create function public.public_dog(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.dogs d where d.id=target and d.status='ready' and public.active_owner(d.owner_id) and public.can_see_owner(d.owner_id));
$$;
create function public.owns_dog(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.dogs where id=target and owner_id=auth.uid());
$$;

drop policy users_read on public.users;
create policy users_read on public.users for select using(id=auth.uid() or (public.active_owner(id) and public.can_see_owner(id)));
drop policy dogs_read on public.dogs;
create policy dogs_read on public.dogs for select using(public.visible_dog(id));
drop policy videos_read on public.videos;
create policy videos_read on public.videos for select using (
 public.visible_dog(dog_id) and (status='ready' or public.owns_dog(dog_id))
 and not exists(select 1 from public.reports where video_id=videos.id and user_id=auth.uid())
);
drop policy comments_read on public.comments;
create policy comments_read on public.comments for select using (
 public.active_owner(user_id) and public.can_see_owner(user_id) and (status='ready' or user_id=auth.uid())
 and exists(select 1 from public.videos where id=video_id)
 and not exists(select 1 from public.reports where comment_id=comments.id and user_id=auth.uid())
);
-- Block/remove/comment-report policies continue to work for suspended users; posting does not.
drop policy reports_insert on public.reports;
create policy reports_insert on public.reports for insert to authenticated with check(user_id=auth.uid() and public.active_owner(auth.uid()));

create function public.review_required() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if TG_OP='INSERT' then new.status := 'pending';
 elsif TG_TABLE_NAME='dogs' and row(new.name,new.breed,new.bio,new.avatar_path) is distinct from row(old.name,old.breed,old.bio,old.avatar_path) then new.status := 'pending'; new.review_revision:=old.review_revision+1;
 end if;
 if not public.can_contribute() then raise exception 'Accept the current terms before posting. Suspended or deleting accounts cannot post.' using errcode='42501'; end if;
 return new;
end; $$;
create trigger dog_review before insert or update of name,breed,bio,avatar_path on public.dogs for each row execute function public.review_required();
create trigger video_review before insert on public.videos for each row execute function public.review_required();
create trigger comment_review before insert on public.comments for each row execute function public.review_required();

-- Pending comments do not inflate public counts or notify another person before approval.
drop trigger comment_event on public.comments;
create function public.comment_approval_event() returns trigger language plpgsql security definer set search_path='' as $$
declare delta integer; recipient uuid; featured uuid;
begin
 delta := case when TG_OP<>'DELETE' and new.status='ready' then 1 else 0 end
        - case when TG_OP<>'INSERT' and old.status='ready' then 1 else 0 end;
 if delta<>0 then
  update public.videos set comment_count=greatest(0,comment_count+delta) where id=coalesce(new.video_id,old.video_id) returning dog_id into featured;
  select owner_id into recipient from public.dogs where id=featured;
  if delta=1 and recipient<>new.user_id then
   insert into public.notifications(user_id,actor_id,kind,dog_id,video_id,message)
   values(recipient,new.user_id,'comment',featured,new.video_id,'A dog person left a comment on your video.');
  end if;
 end if;
 return coalesce(new,old);
end; $$;
create trigger comment_event after insert or update of status or delete on public.comments for each row execute function public.comment_approval_event();

create or replace function public.dog_json(d public.dogs) returns jsonb language sql stable security invoker set search_path='' as $$
 select jsonb_build_object('id',d.id,'owner_id',d.owner_id,'name',d.name,'breed',d.breed,'birthday',d.birthday,'bio',d.bio,'avatar_path',d.avatar_path,'follower_count',d.follower_count,'following_count',(select count(*) from public.follows where user_id=d.owner_id),'is_featured',d.is_featured,'status',d.status);
$$;
create or replace function public.video_json(v public.videos) returns jsonb language sql stable security invoker set search_path='' as $$ select to_jsonb(v); $$;
-- get_feed's old JSON helper explicitly stripped status; replace those clauses below.
create or replace function public.get_feed(feed_kind text default 'for_you',page_offset text default '0',page_limit text default '8') returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare batch jsonb; dog_data jsonb; total integer; off integer; lim integer;
begin
 off:=greatest(0,least(page_offset::integer,10000)); lim:=greatest(1,least(page_limit::integer,30));
 with ranked as (
 select v.*,case when feed_kind='following' then extract(epoch from v.created_at)
 else (ln(1+v.like_count+v.comment_count*3+v.view_count*0.03)+1)*(case when d.follower_count<1000 then 1.4 else 1 end)/power(greatest(0,extract(epoch from(now()-v.created_at))/3600)+2,0.8) end as score
 from public.videos v join public.dogs d on d.id=v.dog_id where v.status='ready' and d.status='ready'
 and (feed_kind<>'following' or exists(select 1 from public.follows where user_id=auth.uid() and dog_id=v.dog_id))
 ), page as(select * from ranked order by score desc,id limit lim+1 offset off)
 select coalesce(jsonb_agg(to_jsonb(p)-'score' order by p.score desc,p.id),'[]'::jsonb),count(*) into batch,total from page p;
 if total>lim then batch:=batch-lim; end if;
 select coalesce(jsonb_agg(public.dog_json(d)),'[]'::jsonb) into dog_data from public.dogs d where d.id in(select (value->>'dog_id')::uuid from jsonb_array_elements(batch));
 return jsonb_build_object('videos',batch,'dogs',dog_data,'next_offset',case when total>lim then off+lim else null end);
end; $$;
create or replace function public.get_comments(target_video text) returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(to_jsonb(c)||jsonb_build_object('author',u.display_name) order by c.created_at),'[]'::jsonb)
 from(select * from public.comments where video_id=target_video::uuid order by created_at desc limit 100)c join public.users u on u.id=c.user_id;
$$;

-- Store only owned Storage paths. An arbitrary remote URL cannot be injected into the feed.
create or replace function public.save_dog(dog_id text,dog_name text,dog_breed text,dog_birthday text,dog_bio text,dog_avatar text) returns jsonb language plpgsql security invoker set search_path='' as $$
declare d public.dogs; path text;
begin
 if not public.can_contribute() then raise exception 'Accept the current terms before posting.' using errcode='42501'; end if;
 if dog_birthday<>'' and dog_birthday::date>current_date then raise exception 'Birthdays must be in the past.'; end if;
 if dog_avatar<>'' then
  path:=substring(dog_avatar from '^storage://avatars/(.+)$');
  if path is null or split_part(path,'/',1)<>auth.uid()::text or not exists(select 1 from storage.objects where bucket_id='avatars' and name=path and owner_id=auth.uid()::text) then raise exception 'Choose an uploaded profile photo.' using errcode='42501'; end if;
 end if;
 insert into public.dogs(id,owner_id,name,breed,birthday,bio,avatar_path) values(dog_id::uuid,auth.uid(),btrim(dog_name),btrim(dog_breed),dog_birthday,dog_bio,dog_avatar)
 on conflict(id) do update set name=excluded.name,breed=excluded.breed,birthday=excluded.birthday,bio=excluded.bio,avatar_path=excluded.avatar_path returning * into d;
 return public.dog_json(d);
end; $$;
create or replace function public.publish_video(video_id text,featured_dog text,video_caption text,video_tags text,media_url text,thumbnail_url text,duration_seconds text) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.videos; path text;
begin
 if not public.can_contribute() or not public.owns_dog(featured_dog::uuid) then raise exception 'You can only upload for your own dog after accepting the terms.' using errcode='42501'; end if;
 path:=auth.uid()::text||'/'||video_id::uuid::text;
 if media_url<>'storage://videos/'||path||'.mp4' or thumbnail_url<>'storage://thumbnails/'||path||'.jpg' then raise exception 'Invalid media path.'; end if;
 if not exists(select 1 from storage.objects where bucket_id='videos' and name=path||'.mp4' and owner_id=auth.uid()::text) or not exists(select 1 from storage.objects where bucket_id='thumbnails' and name=path||'.jpg' and owner_id=auth.uid()::text) then raise exception 'Upload both video and thumbnail before publishing.'; end if;
 insert into public.videos(id,dog_id,caption,hashtags,media_path,thumbnail_path,duration)
 values(video_id::uuid,featured_dog::uuid,video_caption,case when video_tags='' then '{}'::text[] else string_to_array(video_tags,',')end,media_url,thumbnail_url,duration_seconds::double precision)
 on conflict(id) do nothing returning * into v;
 if v.id is null then select * into strict v from public.videos where id=video_id::uuid and dog_id=featured_dog::uuid; end if;
 return public.video_json(v);
end; $$;
-- Direct REST writes must validate avatar ownership too, so RPC validation cannot be bypassed.
create function public.validate_avatar() returns trigger language plpgsql security definer set search_path='' as $$
declare path text;
begin
 if new.avatar_path<>'' then
  path:=substring(new.avatar_path from '^storage://avatars/(.+)$');
  if path is null or split_part(path,'/',1)<>new.owner_id::text or not exists(select 1 from storage.objects where bucket_id='avatars' and name=path and owner_id=new.owner_id::text) then raise exception 'Invalid profile photo.' using errcode='42501'; end if;
 end if;
 return new;
end; $$;
create trigger avatar_ownership before insert or update of avatar_path on public.dogs for each row execute function public.validate_avatar();

create function public.report_content(target_kind text,target_id text,report_reason text) returns void language plpgsql security invoker set search_path='' as $$
begin
 if target_kind='comment' then insert into public.reports(user_id,comment_id,reason) values(auth.uid(),target_id::uuid,report_reason) on conflict do nothing;
 elsif target_kind='dog' then insert into public.reports(user_id,dog_id,reason) values(auth.uid(),target_id::uuid,report_reason) on conflict do nothing;
 elsif target_kind='video' then perform public.report_video(target_id,report_reason);
 else raise exception 'Invalid report target.'; end if;
end; $$;
create function public.unblock_owner(target_owner text) returns void language sql security invoker set search_path='' as $$ delete from public.blocks where user_id=auth.uid() and blocked_owner_id=target_owner::uuid; $$;
create function public.blocked_accounts() returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',b.blocked_owner_id,'name',coalesce((select name from public.dogs where owner_id=b.blocked_owner_id order by created_at limit 1),'Dog person'))),'[]'::jsonb) from public.blocks b where user_id=auth.uid();
$$;

-- Private buckets stop pending or removed content leaking through a public object URL.
update storage.buckets set public=false where id in('videos','thumbnails','avatars');
drop policy tikdog_media_read on storage.objects;
create policy tikdog_media_read on storage.objects for select to anon,authenticated using (
 bucket_id in('videos','thumbnails','avatars') and (
  (split_part(name,'/',1)=auth.uid()::text and public.active_owner(auth.uid())) or public.is_moderator()
  or (bucket_id='avatars' and exists(select 1 from public.dogs d where d.avatar_path='storage://avatars/'||storage.objects.name and d.status='ready' and public.public_dog(d.id)))
  or (bucket_id in('videos','thumbnails') and exists(select 1 from public.videos v where v.status='ready' and public.public_dog(v.dog_id)
   and (v.media_path='storage://'||storage.objects.bucket_id||'/'||storage.objects.name or v.thumbnail_path='storage://'||storage.objects.bucket_id||'/'||storage.objects.name)))
 ));
drop policy tikdog_media_insert on storage.objects;
create policy tikdog_media_insert on storage.objects for insert to authenticated with check (
 bucket_id in('videos','thumbnails','avatars') and (storage.foldername(name))[1]=auth.uid()::text and public.can_contribute()
);

-- Admin operations are narrow RPCs. The service key never belongs in the app.
create function public.moderation_queue() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not public.is_moderator() then raise exception 'Moderator access required.' using errcode='42501'; end if;
 return jsonb_build_object(
  'videos',coalesce((select jsonb_agg(v) from(select * from public.videos where status='pending' order by created_at limit 100)v),'[]'::jsonb),
  'dogs',coalesce((select jsonb_agg(d) from(select * from public.dogs where status='pending' order by created_at limit 100)d),'[]'::jsonb),
  'comments',coalesce((select jsonb_agg(c) from(select * from public.comments where status='pending' order by created_at limit 100)c),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(r) from(select * from public.reports where resolved_at is null order by created_at limit 100)r),'[]'::jsonb),
  'oldest_open_report', (select min(created_at) from public.reports where resolved_at is null));
end; $$;
create function public.moderate_content(target_kind text,target_id text,decision text,moderator_note text,expected_revision text default null) returns void language plpgsql security definer set search_path='' as $$
declare next_status text; affected integer; revision bigint;
begin
 if not public.is_moderator() then raise exception 'Moderator access required.' using errcode='42501'; end if;
 if decision not in('approve','hide','dismiss','suspend','restore') or length(btrim(moderator_note))<3 then raise exception 'Choose a decision and record a reason.'; end if;
 if target_kind='dog' and decision='approve' then
  select review_revision into revision from public.dogs where id=target_id::uuid for update;
  if expected_revision is null or revision is distinct from expected_revision::bigint then raise exception 'Profile changed. Review its latest revision before approving.' using errcode='40001'; end if;
 end if;
 next_status:=case when decision='approve' then 'ready' else 'hidden' end;
 if target_kind='report' and decision='dismiss' then update public.reports set resolved_at=now(),resolution=moderator_note where id=target_id::uuid;
 elsif target_kind='account' and decision in('suspend','restore') then update public.users set suspended_at=case when decision='suspend' then now() else null end where id=target_id::uuid;
 elsif target_kind='video' and decision in('approve','hide') then update public.videos set status=next_status where id=target_id::uuid;
 elsif target_kind='dog' and decision in('approve','hide') then update public.dogs set status=next_status where id=target_id::uuid;
 elsif target_kind='comment' and decision in('approve','hide') then update public.comments set status=next_status where id=target_id::uuid;
 else raise exception 'Invalid moderation action.'; end if;
 get diagnostics affected=ROW_COUNT;
 if affected=0 then raise exception 'Content no longer exists.'; end if;
 if target_kind in('video','dog','comment') then update public.reports set resolved_at=now(),resolution=decision||': '||moderator_note
 where (video_id=target_id::uuid and target_kind='video') or (dog_id=target_id::uuid and target_kind='dog') or (comment_id=target_id::uuid and target_kind='comment'); end if;
 insert into public.moderation_actions(moderator_id,target_kind,target_id,action,note) values(auth.uid(),target_kind,target_id::uuid,decision,moderator_note);
end; $$;

revoke execute on all functions in schema public from public;
grant execute on function public.is_moderator(),public.active_owner(uuid),public.can_contribute(),public.visible_dog(uuid),public.public_dog(uuid),public.owns_dog(uuid),public.account_state() to anon,authenticated;
grant execute on function public.accept_terms(text),public.report_content(text,text,text),public.unblock_owner(text),public.blocked_accounts(),public.moderation_queue(),public.moderate_content(text,text,text,text,text) to authenticated;
grant usage on schema public,private to service_role;
grant all on all tables in schema public,private to service_role;
grant all on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin insert into public.users(id,display_name) values(new.id,'Dog person'); return new; end; $$;
-- Cached/legacy URLs are converted to canonical paths before private access is enabled.
update public.videos set media_path=regexp_replace(media_path,'^https://[^/]+/storage/v1/object/public/','storage://'),
 thumbnail_path=regexp_replace(thumbnail_path,'^https://[^/]+/storage/v1/object/public/','storage://');
-- Avatar updates are subject to review; migrated avatars with no owned object are cleared.
-- Disable only these triggers inside this owner-run migration, never for runtime callers.
alter table public.dogs disable trigger dog_review;
alter table public.dogs disable trigger avatar_ownership;
update public.dogs set avatar_path=regexp_replace(avatar_path,'^https://[^/]+/storage/v1/object/public/','storage://');
update public.dogs d set avatar_path='' where avatar_path<>'' and not exists(select 1 from storage.objects where bucket_id='avatars' and 'storage://avatars/'||name=d.avatar_path and owner_id=d.owner_id::text);
alter table public.dogs enable trigger dog_review;
alter table public.dogs enable trigger avatar_ownership;
revoke delete on public.dogs,public.videos from authenticated;
create or replace function public.daily_standings() returns jsonb language sql stable security definer set search_path='' as $$
 with totals as(select dog_id,vote_day,count(*) as votes from public.daily_votes group by dog_id,vote_day),
 winners as(select dog_id,vote_day,row_number() over(partition by vote_day order by votes desc,dog_id) as rank from totals where vote_day<(now() at time zone 'utc')::date)
 select coalesce(jsonb_agg(jsonb_build_object('dog_id',d.id,'votes',coalesce(t.votes,0),'wins',(select count(*)from winners w where w.dog_id=d.id and rank=1)) order by coalesce(t.votes,0) desc,d.id),'[]'::jsonb)
 from public.dogs d left join totals t on t.dog_id=d.id and t.vote_day=(now() at time zone 'utc')::date where public.public_dog(d.id);
$$;

create function public.begin_account_deletion(target_user uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service access required.' using errcode='42501'; end if;
 update public.users set deleting_at=coalesce(deleting_at,now()) where id=target_user;
end; $$;
create function public.store_apple_credentials(target_user uuid,apple_subject text,apple_refresh_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' or not public.active_owner(target_user) then raise exception 'Service access required.' using errcode='42501'; end if;
 insert into private.apple_credentials(user_id,apple_subject,refresh_token) values(target_user,apple_subject,apple_refresh_token)
 on conflict(user_id) do update set refresh_token=excluded.refresh_token,apple_subject=excluded.apple_subject;
end; $$;
create function public.apple_credentials_for_deletion(target_user uuid) returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' then raise exception 'Service access required.' using errcode='42501'; end if;
 return(select jsonb_build_object('refresh_token',refresh_token,'apple_subject',apple_subject) from private.apple_credentials where user_id=target_user);
end; $$;
revoke execute on function public.begin_account_deletion(uuid),public.store_apple_credentials(uuid,text,text),public.apple_credentials_for_deletion(uuid) from public,anon,authenticated;
grant execute on function public.begin_account_deletion(uuid),public.store_apple_credentials(uuid,text,text),public.apple_credentials_for_deletion(uuid) to service_role;
drop policy dogs_read on public.dogs;
create policy dogs_read on public.dogs for select using((owner_id=auth.uid() and public.active_owner(owner_id)) or (status='ready' and public.active_owner(owner_id) and public.can_see_owner(owner_id)
 and not exists(select 1 from public.reports where dog_id=dogs.id and user_id=auth.uid())));
create or replace function public.discover_dogs(search_query text default '') returns jsonb language sql stable security invoker set search_path='' as $$
 select coalesce(jsonb_agg(public.dog_json(d)),'[]'::jsonb) from(select * from public.dogs where status='ready' and (name ilike '%'||left(search_query,60)||'%' or breed ilike '%'||left(search_query,60)||'%') order by (follower_count<1000)desc,follower_count desc,id limit 50)d;
$$;

-- Serialize contribution commits with the deletion flag, not just a stale RLS snapshot.
create function public.lock_contributor() returns void language plpgsql security definer set search_path='' as $$
declare owner_row public.users;
begin
 select * into owner_row from public.users where id=auth.uid() for share;
 if not found or owner_row.suspended_at is not null or owner_row.deleting_at is not null
 or owner_row.accepted_terms_version is distinct from '2026-10-18' or owner_row.accepted_terms_at is null then
  raise exception 'This account cannot post. Accept the terms or finish pending account deletion.' using errcode='42501';
 end if;
end; $$;
create or replace function public.review_required() returns trigger language plpgsql security definer set search_path='' as $$
begin
 perform public.lock_contributor();
 if TG_OP='INSERT' then new.status:='pending';
 elsif TG_TABLE_NAME='dogs' and row(new.name,new.breed,new.bio,new.avatar_path) is distinct from row(old.name,old.breed,old.bio,old.avatar_path) then new.status:='pending'; new.review_revision:=old.review_revision+1; end if;
 return new;
end; $$;
create function public.check_storage_contributor() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if auth.role()='service_role' then return new; end if;
 if new.bucket_id in('videos','thumbnails','avatars') then perform public.lock_contributor(); end if;
 return new;
end; $$;
create trigger tikdog_storage_contributor before insert or update on storage.objects for each row execute function public.check_storage_contributor();
revoke execute on function public.lock_contributor(),public.check_storage_contributor() from public,anon,authenticated;

create or replace function public.visible_dog(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.dogs d where d.id=target and public.active_owner(d.owner_id) and public.can_see_owner(d.owner_id)
 and (d.status='ready' or d.owner_id=auth.uid()) and not exists(select 1 from public.reports where dog_id=target and user_id=auth.uid()));
$$;
create or replace function public.public_dog(target uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.dogs d where d.id=target and d.status='ready' and public.active_owner(d.owner_id) and public.can_see_owner(d.owner_id)
 and not exists(select 1 from public.reports where dog_id=target and user_id=auth.uid()));
$$;
create function public.prune_moderation_audit() returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_moderator() then raise exception 'Moderator access required.' using errcode='42501'; end if;
 delete from public.moderation_actions where created_at<now()-interval '90 days';
end; $$;
revoke execute on function public.prune_moderation_audit() from public,anon;
grant execute on function public.prune_moderation_audit() to authenticated,service_role;
-- Reactions and votes also respect terms acceptance and account suspension.
drop policy likes_insert on public.likes;
create policy likes_insert on public.likes for insert to authenticated with check(user_id=auth.uid() and public.can_contribute() and exists(select 1 from public.videos where id=video_id and status='ready'));
drop policy follows_insert on public.follows;
create policy follows_insert on public.follows for insert to authenticated with check(user_id=auth.uid() and public.can_contribute() and exists(select 1 from public.dogs where id=dog_id and status='ready' and owner_id<>auth.uid()));
drop policy bookmarks_insert on public.bookmarks;
create policy bookmarks_insert on public.bookmarks for insert to authenticated with check(user_id=auth.uid() and public.can_contribute() and exists(select 1 from public.videos where id=video_id and status='ready'));
drop policy votes_insert on public.daily_votes;
create policy votes_insert on public.daily_votes for insert to authenticated with check(user_id=auth.uid() and public.can_contribute() and vote_day=(now() at time zone 'utc')::date and public.public_dog(dog_id));
revoke select on public.users from anon,authenticated;
grant select(id,display_name) on public.users to anon,authenticated;
grant insert(comment_id,dog_id) on public.reports to authenticated;
-- Revocation failures may require fresh Apple authorization even for a frozen/suspended account.
create or replace function public.store_apple_credentials(target_user uuid,apple_subject text,apple_refresh_token text) returns void language plpgsql security definer set search_path='' as $$
begin
 if auth.role() is distinct from 'service_role' or not exists(select 1 from public.users where id=target_user) then raise exception 'Service access required.' using errcode='42501'; end if;
 insert into private.apple_credentials(user_id,apple_subject,refresh_token) values(target_user,apple_subject,apple_refresh_token)
 on conflict(user_id) do update set refresh_token=excluded.refresh_token,apple_subject=excluded.apple_subject;
end; $$;
-- Referenced media is immutable even after DELETE + re-upload. Only service deletion may remove it.
create function public.media_is_referenced(bucket text,object_name text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.videos where media_path='storage://'||bucket||'/'||object_name or thumbnail_path='storage://'||bucket||'/'||object_name)
 or exists(select 1 from public.dogs where avatar_path='storage://'||bucket||'/'||object_name);
$$;
revoke execute on function public.media_is_referenced(text,text) from public;
grant execute on function public.media_is_referenced(text,text) to anon,authenticated,service_role;
drop policy tikdog_media_insert on storage.objects;
create policy tikdog_media_insert on storage.objects for insert to authenticated with check (
 bucket_id in('videos','thumbnails','avatars') and (storage.foldername(name))[1]=auth.uid()::text and public.can_contribute() and not public.media_is_referenced(bucket_id,name)
);
drop policy tikdog_media_delete on storage.objects;
create policy tikdog_media_delete on storage.objects for delete to authenticated using (
 bucket_id in('videos','thumbnails','avatars') and (storage.foldername(name))[1]=auth.uid()::text and not public.media_is_referenced(bucket_id,name)
);
create index dogs_avatar_path_idx on public.dogs(avatar_path) where avatar_path<>'';
create index videos_media_path_idx on public.videos(media_path);
create index videos_thumbnail_path_idx on public.videos(thumbnail_path);
create index dogs_pending_idx on public.dogs(created_at) where status='pending';
create index videos_pending_idx on public.videos(created_at) where status='pending';
create index comments_pending_idx on public.comments(created_at) where status='pending';
