-- TikDog's public surface is read-only for guests. Writes require authenticated ownership.
create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Dog person' check (char_length(display_name) between 1 and 60),
  created_at timestamptz not null default now()
);
create table public.dogs (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 30),
  breed text not null check (char_length(btrim(breed)) between 1 and 60),
  birthday text not null default '' check (birthday = '' or birthday ~ '^\d{4}-\d{2}-\d{2}$'),
  bio text not null default '' check (char_length(bio) <= 160),
  avatar_path text not null default '',
  follower_count integer not null default 0 check (follower_count >= 0),
  is_featured boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.videos (
  id uuid primary key default gen_random_uuid(),
  dog_id uuid not null references public.dogs(id) on delete cascade,
  caption text not null default '' check (char_length(caption) <= 300),
  hashtags text[] not null default '{}' check (cardinality(hashtags) <= 8),
  media_path text not null,
  thumbnail_path text not null,
  duration double precision not null check (duration >= 1 and duration <= 60.1),
  like_count integer not null default 0 check (like_count >= 0),
  comment_count integer not null default 0 check (comment_count >= 0),
  view_count integer not null default 0 check (view_count >= 0),
  status text not null default 'ready' check (status in ('ready','hidden')),
  created_at timestamptz not null default now()
);
create table public.likes (
  user_id uuid not null references public.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id, video_id)
);
create table public.follows (
  user_id uuid not null references public.users(id) on delete cascade,
  dog_id uuid not null references public.dogs(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id, dog_id)
);
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);
create table public.bookmarks (
  user_id uuid not null references public.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id, video_id)
);
create table public.blocks (
  user_id uuid not null references public.users(id) on delete cascade,
  blocked_owner_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz not null default now(), primary key(user_id, blocked_owner_id), check(user_id <> blocked_owner_id)
);
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  video_id uuid not null references public.videos(id) on delete cascade,
  reason text not null check (reason in ('animal_harm','inappropriate','spam')),
  created_at timestamptz not null default now(), unique(user_id,video_id)
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  actor_id uuid references public.users(id) on delete cascade,
  kind text not null check (kind in ('like','comment','follow','milestone')),
  dog_id uuid references public.dogs(id) on delete cascade,
  video_id uuid references public.videos(id) on delete cascade,
  message text not null, is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.daily_votes (
  user_id uuid not null references public.users(id) on delete cascade,
  dog_id uuid not null references public.dogs(id) on delete cascade,
  vote_day date not null default (now() at time zone 'utc')::date,
  created_at timestamptz not null default now(), primary key(user_id, vote_day)
);

create index dogs_owner_idx on public.dogs(owner_id);
create index dogs_name_idx on public.dogs(lower(name) text_pattern_ops);
create index dogs_breed_idx on public.dogs(lower(breed) text_pattern_ops);
create index videos_feed_idx on public.videos(created_at desc,id) where status = 'ready';
create index videos_dog_idx on public.videos(dog_id,created_at desc);
create index videos_tags_idx on public.videos using gin(hashtags);
create index likes_video_idx on public.likes(video_id);
create index follows_dog_idx on public.follows(dog_id);
create index comments_video_idx on public.comments(video_id,created_at);
create index bookmarks_video_idx on public.bookmarks(video_id);
create index notifications_user_idx on public.notifications(user_id,created_at desc);
create index blocks_target_idx on public.blocks(blocked_owner_id,user_id);
create index votes_day_idx on public.daily_votes(vote_day,dog_id);

create function public.handle_new_user() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.users(id,display_name) values(new.id,coalesce(nullif(left(new.raw_user_meta_data->>'display_name',60),''),'Dog person'));
  return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- Reciprocal blocking also prevents a blocked account from interacting with the blocker.
create function public.can_see_owner(target uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select not exists(select 1 from public.blocks where (user_id = auth.uid() and blocked_owner_id = target) or (user_id = target and blocked_owner_id = auth.uid()));
$$;
alter table public.users enable row level security;
alter table public.dogs enable row level security;
alter table public.videos enable row level security;
alter table public.likes enable row level security;
alter table public.follows enable row level security;
alter table public.comments enable row level security;
alter table public.bookmarks enable row level security;
alter table public.blocks enable row level security;
alter table public.reports enable row level security;
alter table public.notifications enable row level security;
alter table public.daily_votes enable row level security;

create policy users_read on public.users for select using (public.can_see_owner(id));
create policy dogs_read on public.dogs for select using (public.can_see_owner(owner_id));
create policy dogs_insert on public.dogs for insert to authenticated with check (owner_id = auth.uid());
create policy dogs_update on public.dogs for update to authenticated using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy dogs_delete on public.dogs for delete to authenticated using (owner_id = auth.uid());
create policy reports_read on public.reports for select to authenticated using (user_id = auth.uid());
create policy reports_insert on public.reports for insert to authenticated with check (user_id = auth.uid());
create policy blocks_own on public.blocks for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy videos_read on public.videos for select using (
  (status = 'ready' or exists(select 1 from public.dogs where id = dog_id and owner_id = auth.uid()))
  and exists(select 1 from public.dogs where id = dog_id)
  and not exists(select 1 from public.reports where video_id = videos.id and user_id = auth.uid())
);
create policy videos_insert on public.videos for insert to authenticated with check (exists(select 1 from public.dogs where id = dog_id and owner_id = auth.uid()));
create policy videos_delete on public.videos for delete to authenticated using (exists(select 1 from public.dogs where id = dog_id and owner_id = auth.uid()));
create policy likes_read on public.likes for select using (true);
create policy likes_insert on public.likes for insert to authenticated with check (user_id = auth.uid() and exists(select 1 from public.videos where id = video_id));
create policy likes_delete on public.likes for delete to authenticated using (user_id = auth.uid());
create policy follows_read on public.follows for select using (true);
create policy follows_insert on public.follows for insert to authenticated with check (user_id = auth.uid() and exists(select 1 from public.dogs where id = dog_id and owner_id <> auth.uid()));
create policy follows_delete on public.follows for delete to authenticated using (user_id = auth.uid());
create policy comments_read on public.comments for select using (public.can_see_owner(user_id) and exists(select 1 from public.videos where id = video_id));
create policy comments_insert on public.comments for insert to authenticated with check (user_id = auth.uid() and exists(select 1 from public.videos where id = video_id));
create policy comments_delete on public.comments for delete to authenticated using (user_id = auth.uid());
create policy bookmarks_read on public.bookmarks for select to authenticated using (user_id = auth.uid());
create policy bookmarks_insert on public.bookmarks for insert to authenticated with check (user_id = auth.uid() and exists(select 1 from public.videos where id = video_id));
create policy bookmarks_delete on public.bookmarks for delete to authenticated using (user_id = auth.uid());
create policy notifications_read on public.notifications for select to authenticated using (user_id = auth.uid() and public.can_see_owner(actor_id));
create policy notifications_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy votes_read on public.daily_votes for select to authenticated using (user_id = auth.uid());
create policy votes_insert on public.daily_votes for insert to authenticated with check (user_id = auth.uid() and vote_day = (now() at time zone 'utc')::date and exists(select 1 from public.dogs where id = dog_id));

-- Counters and notifications are owned by triggers; clients cannot forge them.
create function public.social_event() returns trigger language plpgsql security definer set search_path = '' as $$
declare recipient uuid; featured uuid; target uuid; actor text; delta integer;
begin
  delta := case when TG_OP = 'INSERT' then 1 else -1 end;
  if TG_TABLE_NAME = 'follows' then
    featured := case when TG_OP = 'INSERT' then new.dog_id else old.dog_id end;
    update public.dogs set follower_count = greatest(0,follower_count + delta) where id = featured returning owner_id into recipient;
  else
    target := case when TG_OP = 'INSERT' then new.video_id else old.video_id end;
    if TG_TABLE_NAME = 'likes' then update public.videos set like_count = greatest(0,like_count + delta) where id = target returning dog_id into featured;
    else update public.videos set comment_count = greatest(0,comment_count + delta) where id = target returning dog_id into featured; end if;
    select owner_id into recipient from public.dogs where id = featured;
  end if;
  if TG_OP = 'INSERT' and recipient is not null and recipient <> new.user_id and public.can_see_owner(recipient) then
    select display_name into actor from public.users where id = new.user_id;
    insert into public.notifications(user_id,actor_id,kind,dog_id,video_id,message)
    values(recipient,new.user_id,case TG_TABLE_NAME when 'likes' then 'like' when 'follows' then 'follow' else 'comment' end,featured,target,
      coalesce(actor,'A dog person') || case TG_TABLE_NAME when 'likes' then ' loved your video.' when 'follows' then ' started following your dog.' else ' left a little love on your video.' end);
  end if;
  if TG_OP = 'DELETE' then return old; else return new; end if;
end; $$;
create trigger like_event after insert or delete on public.likes for each row execute function public.social_event();
create trigger follow_event after insert or delete on public.follows for each row execute function public.social_event();
create trigger comment_event after insert or delete on public.comments for each row execute function public.social_event();

-- Narrow column grants keep verified badges, owners, and counters server-controlled.
grant usage on schema public to anon, authenticated;
grant select on public.users,public.dogs,public.videos,public.likes,public.follows,public.comments to anon,authenticated;
grant select on public.bookmarks,public.blocks,public.reports,public.notifications,public.daily_votes to anon,authenticated;
grant insert(id,owner_id,name,breed,birthday,bio,avatar_path), update(name,breed,birthday,bio,avatar_path), delete on public.dogs to authenticated;
grant insert(user_id,video_id),delete on public.likes,public.bookmarks to authenticated;
grant insert(user_id,dog_id),delete on public.follows to authenticated;
grant insert(user_id,video_id,body),delete on public.comments to authenticated;
grant insert(user_id,blocked_owner_id),delete on public.blocks to authenticated;
grant insert(user_id,video_id,reason) on public.reports to authenticated;
grant insert(user_id,dog_id,vote_day) on public.daily_votes to authenticated;
grant update(is_read) on public.notifications to authenticated;
