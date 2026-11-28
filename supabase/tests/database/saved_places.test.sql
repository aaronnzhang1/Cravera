-- Denial-path tests for public.saved_places (TASK-004). Run: supabase test db
-- (needs the local stack: supabase start). Fictional users and place IDs only.
begin;
select plan(20);

insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-4111-8111-111111111111', 'tester-a@example.test', '{}'),
  ('22222222-2222-4222-8222-222222222222', 'tester-b@example.test', '{}');

-- B already saved a place (as the owner, to set up the data).
insert into public.saved_places (user_id, place_id, note)
values ('22222222-2222-4222-8222-222222222222', 'fake-place-b', 'B''s private note');

-- Signed in as A.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

select lives_ok($$insert into public.saved_places (place_id) values ('fake-place-a')$$, 'A can save a place');
select is((select user_id from public.saved_places where place_id = 'fake-place-a'),
  '11111111-1111-4111-8111-111111111111'::uuid, 'user_id comes from the token');
select is((select status from public.saved_places where place_id = 'fake-place-a'), 'want_to_go', 'new places are Want to go');
select results_eq('select place_id from public.saved_places', $$values ('fake-place-a')$$, 'A reads only their own saved places');
select is((select count(*)::int from public.saved_places where place_id = 'fake-place-b'), 0, 'A cannot read B''s place by asking for it');

select throws_ok($$insert into public.saved_places (user_id, place_id)
  values ('22222222-2222-4222-8222-222222222222', 'fake-place-x')$$, '42501', null,
  'A cannot save for B (client-supplied user_id grants nothing)');
select throws_ok($$insert into public.saved_places (place_id) values ('fake-place-a')$$, '23505', null, 'a place is saved once per person');
select throws_ok($$insert into public.saved_places (place_id) values ('places/../x')$$, '23514', null, 'a malformed place ID is refused');
select throws_ok($$insert into public.saved_places (place_id, status) values ('fake-place-c', 'favourite')$$, '23514', null, 'an unknown status is refused');
select throws_ok($$insert into public.saved_places (place_id, note) values ('fake-place-d', repeat('x', 501))$$, '23514', null, 'an over-long note is refused');

select lives_ok($$update public.saved_places set status = 'been', note = 'Loved it' where place_id = 'fake-place-a'$$, 'A can update their own place');
update public.saved_places set note = 'hijacked' where place_id = 'fake-place-b';
delete from public.saved_places where place_id = 'fake-place-b';
select throws_ok($$update public.saved_places set user_id = '22222222-2222-4222-8222-222222222222' where place_id = 'fake-place-a'$$,
  '42501', null, 'A cannot move a row to another person');
select throws_ok($$update public.saved_places set place_id = 'fake-place-z' where place_id = 'fake-place-a'$$,
  '42501', null, 'A cannot change which place a row is');
select throws_ok($$update public.saved_places set created_at = now() where place_id = 'fake-place-a'$$,
  '42501', null, 'A cannot change created_at');

-- Anonymous: nothing at all.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok($$select * from public.saved_places$$, '42501', null, 'anonymous requests cannot read saved places');
select throws_ok($$insert into public.saved_places (place_id) values ('fake-place-anon')$$, '42501', null, 'anonymous requests cannot save');

-- Back to the owner to check what really happened.
reset role;
select is((select note from public.saved_places where place_id = 'fake-place-b'), 'B''s private note', 'B''s row is untouched by A');
select is((select status || ':' || note from public.saved_places where place_id = 'fake-place-a'), 'been:Loved it', 'A''s own update applied');
select ok((select updated_at > created_at or updated_at = created_at from public.saved_places where place_id = 'fake-place-a'), 'updated_at is maintained');

delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.saved_places where user_id = '11111111-1111-4111-8111-111111111111'), 0,
  'deleting the account removes its saved places');

select * from finish();
rollback;
