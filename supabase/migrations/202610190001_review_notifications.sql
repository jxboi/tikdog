-- Decisions are visible only to the submitting account. Internal moderator notes stay private.
alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check
  check (kind in ('like','comment','follow','milestone','review'));

create function public.submission_review_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare recipient uuid; target_dog uuid; target_video uuid; subject text; result text;
begin
  if new.status = old.status or new.status not in ('ready','hidden') then return new; end if;
  if TG_TABLE_NAME = 'dogs' then
    recipient := new.owner_id; target_dog := new.id; subject := 'Your dog profile';
  else
    select owner_id into recipient from public.dogs where id=new.dog_id;
    target_dog := new.dog_id; target_video := new.id; subject := 'Your video';
  end if;
  result := case when new.status='ready' then ' was approved.' else ' was removed from public view. Open submission status for next steps.' end;
  if TG_TABLE_NAME='videos' and new.status='ready'
    and exists(select 1 from public.dogs where id=target_dog and status<>'ready') then
    result := result || ' It will appear publicly once your dog profile is approved too.';
  end if;
  insert into public.notifications(user_id,kind,dog_id,video_id,message)
  values(recipient,'review',target_dog,target_video,subject||result);
  return new;
end; $$;
revoke all on function public.submission_review_event() from public,anon,authenticated;
create trigger dog_review_outcome after update of status on public.dogs
  for each row execute function public.submission_review_event();
create trigger video_review_outcome after update of status on public.videos
  for each row execute function public.submission_review_event();
