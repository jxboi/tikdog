\set QUIET 1
create function public.test_assert(condition boolean, message text) returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'FAIL: %', message; end if; end; $$;
insert into auth.users(id) values ('11111111-1111-4111-8111-111111111111'),('22222222-2222-4222-8222-222222222222');
update public.users set accepted_terms_version='2026-10-18',accepted_terms_at=now();
set request.jwt.claim.sub='11111111-1111-4111-8111-111111111111';
insert into public.dogs(id,owner_id,name,breed) values
 ('00000000-0000-4000-8000-000000000001','11111111-1111-4111-8111-111111111111','Cabby','Cavapoo'),
 ('00000000-0000-4000-8000-000000000002','22222222-2222-4222-8222-222222222222','Mochi','Shiba Inu');
update public.dogs set status='ready';
insert into public.videos(id,dog_id,media_path,thumbnail_path,duration) values
 ('10000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000001','https://example.com/a.mp4','https://example.com/a.jpg',10),
 ('10000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000002','https://example.com/b.mp4','https://example.com/b.jpg',10);
update public.videos set status='ready';
set request.jwt.claim.sub='';
set role anon;
select public.test_assert((public.bootstrap()->>'user_id') is null,'guest bootstrap');
select public.test_assert(jsonb_array_length(public.get_feed()->'videos')=2,'guest browsing');
select public.test_assert((select count(*) from public.bookmarks)=0,'guest cannot see bookmarks');
do $$ begin perform public.set_like('10000000-0000-4000-8000-000000000001','true'); raise exception 'guest write allowed'; exception when insufficient_privilege then null; end $$;
reset role;
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
set role authenticated;
select public.set_like('10000000-0000-4000-8000-000000000001','true');
select public.set_like('10000000-0000-4000-8000-000000000001','true');
select public.test_assert((select like_count from public.videos where id='10000000-0000-4000-8000-000000000001')=1,'idempotent like counter');
select public.set_bookmark('10000000-0000-4000-8000-000000000001','true');
select public.set_follow('00000000-0000-4000-8000-000000000001','true');
select public.test_assert(jsonb_array_length(public.get_feed('following')->'videos')=1,'following feed');
select public.test_assert((public.get_feed('for_you','0','1')->>'next_offset')::int=1,'feed pagination');
select public.test_assert((public.add_comment('10000000-0000-4000-8000-000000000001','Good dog!')->>'body')='Good dog!','comment creation');
select public.test_assert(jsonb_array_length(public.cast_daily_vote('00000000-0000-4000-8000-000000000001'))=2,'daily vote');
do $$ begin perform public.cast_daily_vote('00000000-0000-4000-8000-000000000002'); raise exception 'second vote allowed'; exception when raise_exception then if SQLERRM='second vote allowed' then raise; end if; end $$;
select public.test_assert((select count(*) from public.daily_votes)=1,'one vote per user/day');
do $$ begin update public.videos set like_count=99999; raise exception 'forged counters allowed'; exception when insufficient_privilege then null; end $$;
do $$ begin update public.dogs set is_featured=true; raise exception 'forged badge allowed'; exception when insufficient_privilege then null; end $$;
do $$ begin perform public.save_dog('00000000-0000-4000-8000-000000000001','Stolen','Corgi','','',''); raise exception 'foreign profile edit allowed'; exception when insufficient_privilege then null; end $$;
select public.test_assert((public.save_dog('00000000-0000-4000-8000-000000000003','Luna','Corgi','','Short legs','')->>'name')='Luna','own profile creation');
-- Storage RLS: an attacker cannot choose someone else's upload folder.
do $$ begin insert into storage.objects(bucket_id,name,owner_id) values('videos','11111111-1111-4111-8111-111111111111/attack.mp4','22222222-2222-4222-8222-222222222222'); raise exception 'foreign storage write allowed'; exception when insufficient_privilege then null; end $$;
insert into storage.objects(bucket_id,name,owner_id) values
 ('videos','22222222-2222-4222-8222-222222222222/10000000-0000-4000-8000-000000000003.mp4','22222222-2222-4222-8222-222222222222'),
 ('thumbnails','22222222-2222-4222-8222-222222222222/10000000-0000-4000-8000-000000000003.jpg','22222222-2222-4222-8222-222222222222');
select public.test_assert((public.publish_video('10000000-0000-4000-8000-000000000003','00000000-0000-4000-8000-000000000003','New adventure','corgi','storage://videos/22222222-2222-4222-8222-222222222222/10000000-0000-4000-8000-000000000003.mp4','storage://thumbnails/22222222-2222-4222-8222-222222222222/10000000-0000-4000-8000-000000000003.jpg','10')->>'caption')='New adventure','storage-backed publication');
reset role;
set request.jwt.claim.role='service_role';
select public.moderate_content('comment',(select id::text from public.comments limit 1),'approve','Safe comment');
set request.jwt.claim.role='';
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
set role authenticated;
select public.test_assert((select count(*) from public.bookmarks)=0,'bookmarks are private');
select public.test_assert((select count(*) from public.notifications)=3,'interaction notifications');
select public.read_activity();
select public.test_assert((select bool_and(is_read) from public.notifications),'mark activity read');
select public.report_video('10000000-0000-4000-8000-000000000002','inappropriate');
select public.test_assert((select count(*) from public.videos where id='10000000-0000-4000-8000-000000000002')=0,'reported video hidden for reporter');
select public.block_owner('22222222-2222-4222-8222-222222222222');
select public.test_assert((select count(*) from public.dogs)=1,'blocked owner profiles hidden');
select public.test_assert(jsonb_array_length(public.get_feed()->'videos')=1,'blocked owner videos hidden');
reset role;
set request.jwt.claim.sub = '22222222-2222-4222-8222-222222222222';
set role authenticated;
select public.test_assert((select count(*) from public.dogs where owner_id='11111111-1111-4111-8111-111111111111')=0,'reciprocal blocking');
do $$ begin perform public.set_like('10000000-0000-4000-8000-000000000001','true'); raise exception 'blocked interaction allowed'; exception when insufficient_privilege then null; end $$;
reset role;
delete from auth.users where id='11111111-1111-4111-8111-111111111111';
set request.jwt.claim.sub = '11111111-1111-4111-8111-111111111111';
set role authenticated;
do $$ begin insert into storage.objects(bucket_id,name,owner_id) values('videos','11111111-1111-4111-8111-111111111111/stale-token.mp4','11111111-1111-4111-8111-111111111111'); raise exception 'deleted account storage write allowed'; exception when insufficient_privilege then null; end $$;
reset role;
\echo 'PASS: migrations, guest browsing, authorization, counters, pagination, votes, storage, reports, and reciprocal blocks'
