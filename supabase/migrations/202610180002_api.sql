create function public.dog_json(d public.dogs) returns jsonb language sql stable security invoker set search_path = '' as $$
 select jsonb_build_object('id',d.id,'owner_id',d.owner_id,'name',d.name,'breed',d.breed,'birthday',d.birthday,'bio',d.bio,'avatar_path',d.avatar_path,'follower_count',d.follower_count,'following_count',(select count(*) from public.follows where user_id=d.owner_id),'is_featured',d.is_featured);
$$;
create function public.video_json(v public.videos) returns jsonb language sql stable security invoker set search_path = '' as $$
 select to_jsonb(v) - 'status';
$$;
create function public.daily_standings() returns jsonb language sql stable security definer set search_path = '' as $$
 with totals as (select dog_id,vote_day,count(*) as votes from public.daily_votes group by dog_id,vote_day),
 winners as (select dog_id,vote_day,row_number() over(partition by vote_day order by votes desc,dog_id) as rank from totals where vote_day < (now() at time zone 'utc')::date)
 select coalesce(jsonb_agg(jsonb_build_object('dog_id',d.id,'votes',coalesce(t.votes,0),'wins',(select count(*) from winners w where w.dog_id=d.id and rank=1)) order by coalesce(t.votes,0) desc,d.id),'[]'::jsonb)
 from public.dogs d left join totals t on t.dog_id=d.id and t.vote_day=(now() at time zone 'utc')::date
 where public.can_see_owner(d.owner_id);
$$;
create function public.get_feed(feed_kind text default 'for_you',page_offset text default '0',page_limit text default '8') returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare batch jsonb; dog_data jsonb; total integer; off integer; lim integer;
begin
 off := greatest(0,least(page_offset::integer,10000)); lim := greatest(1,least(page_limit::integer,30));
 with ranked as (
   select v.*,case when feed_kind='following' then extract(epoch from v.created_at)
     else (ln(1+v.like_count+v.comment_count*3+v.view_count*0.03)+1) * (case when d.follower_count<1000 then 1.4 else 1 end)
       / power(greatest(0,extract(epoch from (now()-v.created_at))/3600)+2,0.8) end as score
   from public.videos v join public.dogs d on d.id=v.dog_id
   where v.status='ready' and (feed_kind <> 'following' or exists(select 1 from public.follows where user_id=auth.uid() and dog_id=v.dog_id))
 ), page as (select * from ranked order by score desc,id limit lim+1 offset off)
 select coalesce(jsonb_agg(to_jsonb(p)-'status'-'score' order by p.score desc,p.id),'[]'::jsonb),count(*) into batch,total from page p;
 if total>lim then batch := batch - lim; end if;
 select coalesce(jsonb_agg(public.dog_json(d)),'[]'::jsonb) into dog_data from public.dogs d where d.id in (select (value->>'dog_id')::uuid from jsonb_array_elements(batch));
 return jsonb_build_object('videos',batch,'dogs',dog_data,'next_offset',case when total>lim then off+lim else null end);
end; $$;
create function public.discover_dogs(search_query text default '') returns jsonb language sql stable security invoker set search_path = '' as $$
 select coalesce(jsonb_agg(public.dog_json(d)),'[]'::jsonb) from (
   select * from public.dogs where name ilike '%'||left(search_query,60)||'%' or breed ilike '%'||left(search_query,60)||'%'
   order by (follower_count < 1000) desc,follower_count desc,id limit 50
 ) d;
$$;
create function public.dog_profile(target_dog text) returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare dog_row public.dogs; clips jsonb;
begin
 select * into strict dog_row from public.dogs where id=target_dog::uuid;
 select coalesce(jsonb_agg(public.video_json(v) order by v.created_at desc),'[]'::jsonb) into clips from (select * from public.videos where dog_id=dog_row.id order by created_at desc limit 90) v;
 return jsonb_build_object('dog',public.dog_json(dog_row),'videos',clips);
end; $$;
create function public.bootstrap() returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare feed_data jsonb; dog_data jsonb; activities jsonb;
begin
 feed_data := public.get_feed();
 select coalesce(jsonb_agg(public.dog_json(d)),'[]'::jsonb) into dog_data from public.dogs d
 where d.owner_id=auth.uid() or d.id in (select id from public.dogs order by follower_count desc,id limit 50)
 or d.id in (select v.dog_id from public.videos v join public.bookmarks b on b.video_id=v.id where b.user_id=auth.uid())
 or d.id in (select id from public.dogs where follower_count<1000 order by created_at desc,id limit 30);
 select coalesce(jsonb_agg(to_jsonb(n)-'user_id'-'actor_id' order by n.created_at desc),'[]'::jsonb) into activities from (select * from public.notifications where user_id=auth.uid() order by created_at desc limit 100) n;
 return jsonb_build_object(
  'dogs',dog_data,'videos',(feed_data->'videos') || coalesce((select jsonb_agg(public.video_json(v)) from public.videos v where v.id in(select video_id from public.bookmarks where user_id=auth.uid()) and v.id not in(select (value->>'id')::uuid from jsonb_array_elements(feed_data->'videos'))),'[]'::jsonb),
  'liked_video_ids',coalesce((select jsonb_agg(video_id) from public.likes where user_id=auth.uid()),'[]'::jsonb),
  'bookmarked_video_ids',coalesce((select jsonb_agg(video_id) from public.bookmarks where user_id=auth.uid()),'[]'::jsonb),
  'following_dog_ids',coalesce((select jsonb_agg(dog_id) from public.follows where user_id=auth.uid()),'[]'::jsonb),
  'blocked_owner_ids',coalesce((select jsonb_agg(blocked_owner_id) from public.blocks where user_id=auth.uid()),'[]'::jsonb),
  'activities',activities,'standings',public.daily_standings(),
  'voted_dog_id',(select dog_id from public.daily_votes where user_id=auth.uid() and vote_day=(now() at time zone 'utc')::date),
  'vote_day',to_char(now() at time zone 'utc','YYYY-MM-DD'),'user_id',auth.uid(),
  'display_name',coalesce((select display_name from public.users where id=auth.uid()),'Dog person'));
end; $$;

create function public.set_like(target_video text,enabled text) returns void language plpgsql security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to join the pack.' using errcode='42501'; end if;
 if enabled::boolean then insert into public.likes(user_id,video_id) values(auth.uid(),target_video::uuid) on conflict do nothing;
 else delete from public.likes where user_id=auth.uid() and video_id=target_video::uuid; end if;
end; $$;
create function public.set_bookmark(target_video text,enabled text) returns void language plpgsql security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to join the pack.' using errcode='42501'; end if;
 if enabled::boolean then insert into public.bookmarks(user_id,video_id) values(auth.uid(),target_video::uuid) on conflict do nothing;
 else delete from public.bookmarks where user_id=auth.uid() and video_id=target_video::uuid; end if;
end; $$;
create function public.set_follow(target_dog text,enabled text) returns void language plpgsql security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to join the pack.' using errcode='42501'; end if;
 if enabled::boolean then insert into public.follows(user_id,dog_id) values(auth.uid(),target_dog::uuid) on conflict do nothing;
 else delete from public.follows where user_id=auth.uid() and dog_id=target_dog::uuid; end if;
end; $$;
create function public.get_comments(target_video text) returns jsonb language sql stable security invoker set search_path = '' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'video_id',c.video_id,'user_id',c.user_id,'author',u.display_name,'body',c.body,'created_at',c.created_at) order by c.created_at),'[]'::jsonb)
 from (select * from public.comments where video_id=target_video::uuid order by created_at desc limit 100) c join public.users u on u.id=c.user_id;
$$;
create function public.add_comment(target_video text,comment_body text) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare c public.comments; author text;
begin
 insert into public.comments(user_id,video_id,body) values(auth.uid(),target_video::uuid,btrim(comment_body)) returning * into c;
 select display_name into author from public.users where id=auth.uid();
 return to_jsonb(c)||jsonb_build_object('author',author);
end; $$;
create function public.save_dog(dog_id text,dog_name text,dog_breed text,dog_birthday text,dog_bio text,dog_avatar text) returns jsonb language plpgsql security invoker set search_path = '' as $$
declare d public.dogs;
begin
 if auth.uid() is null then raise exception 'Sign in to join the pack.' using errcode='42501'; end if;
 if dog_birthday<>'' and dog_birthday::date > current_date then raise exception 'Birthdays must be in the past.'; end if;
 insert into public.dogs(id,owner_id,name,breed,birthday,bio,avatar_path) values(dog_id::uuid,auth.uid(),btrim(dog_name),btrim(dog_breed),dog_birthday,dog_bio,dog_avatar)
 on conflict(id) do update set name=excluded.name,breed=excluded.breed,birthday=excluded.birthday,bio=excluded.bio,avatar_path=excluded.avatar_path
 returning * into d;
 return public.dog_json(d);
end; $$;
-- This function is privileged only to insert server-controlled video metadata after storage ownership checks.
create function public.publish_video(video_id text,featured_dog text,video_caption text,video_tags text,media_url text,thumbnail_url text,duration_seconds text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.videos; path text;
begin
 if auth.uid() is null or not exists(select 1 from public.dogs where id=featured_dog::uuid and owner_id=auth.uid()) then raise exception 'You can only upload for your own dog.' using errcode='42501'; end if;
 path := auth.uid()::text||'/'||video_id::uuid::text;
 if media_url !~ ('^https://[^/]+/storage/v1/object/public/videos/'||path||'\.mp4$') or thumbnail_url !~ ('^https://[^/]+/storage/v1/object/public/thumbnails/'||path||'\.jpg$') then raise exception 'Invalid media path.'; end if;
 if not exists(select 1 from storage.objects where bucket_id='videos' and name=path||'.mp4' and owner_id=auth.uid()::text) or not exists(select 1 from storage.objects where bucket_id='thumbnails' and name=path||'.jpg' and owner_id=auth.uid()::text) then raise exception 'Upload both video and thumbnail before publishing.'; end if;
 insert into public.videos(id,dog_id,caption,hashtags,media_path,thumbnail_path,duration)
 values(video_id::uuid,featured_dog::uuid,video_caption,case when video_tags='' then '{}'::text[] else string_to_array(video_tags,',') end,media_url,thumbnail_url,duration_seconds::double precision)
 on conflict(id) do nothing returning * into v;
 if v.id is null then select * into strict v from public.videos where id=video_id::uuid and dog_id=featured_dog::uuid; end if;
 return public.video_json(v);
end; $$;
create function public.cast_daily_vote(target_dog text) returns jsonb language plpgsql security invoker set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in to vote.' using errcode='42501'; end if;
 insert into public.daily_votes(user_id,dog_id) values(auth.uid(),target_dog::uuid);
 return public.daily_standings();
exception when unique_violation then raise exception 'You have already voted today. Come back tomorrow!';
end; $$;
create function public.report_video(target_video text,report_reason text) returns void language plpgsql security invoker set search_path = '' as $$
begin
 insert into public.reports(user_id,video_id,reason) values(auth.uid(),target_video::uuid,report_reason) on conflict(user_id,video_id) do nothing;
end; $$;
create function public.block_owner(target_owner text) returns void language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or auth.uid()=target_owner::uuid then raise exception 'Choose a different account to block.' using errcode='42501'; end if;
 delete from public.follows where (user_id=auth.uid() and dog_id in(select id from public.dogs where owner_id=target_owner::uuid)) or (user_id=target_owner::uuid and dog_id in(select id from public.dogs where owner_id=auth.uid()));
 insert into public.blocks(user_id,blocked_owner_id) values(auth.uid(),target_owner::uuid) on conflict do nothing;
end; $$;
create function public.read_activity() returns void language sql security invoker set search_path = '' as $$ update public.notifications set is_read=true where user_id=auth.uid(); $$;

-- RPC allowlist. PostgreSQL gives function execution to PUBLIC unless explicitly revoked.
revoke execute on all functions in schema public from public,anon,authenticated;
grant execute on function public.can_see_owner(uuid),public.dog_json(public.dogs),public.video_json(public.videos),public.daily_standings(),public.get_feed(text,text,text),public.discover_dogs(text),public.dog_profile(text),public.bootstrap(),public.get_comments(text) to anon,authenticated;
grant execute on function public.set_like(text,text),public.set_bookmark(text,text),public.set_follow(text,text),public.add_comment(text,text),public.save_dog(text,text,text,text,text,text),public.publish_video(text,text,text,text,text,text,text),public.cast_daily_vote(text),public.report_video(text,text),public.block_owner(text),public.read_activity() to authenticated;
