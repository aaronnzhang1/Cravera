-- Denial-path tests for public.profiles (TASK-003). Run: supabase test db
-- (needs the local stack: supabase start). Fictional users only.
begin;
select plan(17);

-- Two fictional accounts; the sign-up trigger makes their profiles.
insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-4111-8111-111111111111', 'tester-a@example.test', '{"display_name": "  Test A  "}'),
  ('22222222-2222-4222-8222-222222222222', 'tester-b@example.test', '{}');

select is((select count(*)::int from public.profiles), 2, 'sign-up trigger creates one profile per account');
select is((select display_name from public.profiles where id = '11111111-1111-4111-8111-111111111111'),
  'Test A', 'display name comes from sign-up metadata, trimmed');
select is((select display_name from public.profiles where id = '22222222-2222-4222-8222-222222222222'),
  'there', 'missing display name falls back');

-- Signed in as A.
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "11111111-1111-4111-8111-111111111111", "role": "authenticated"}', true);

select results_eq('select id from public.profiles',
  $$values ('11111111-1111-4111-8111-111111111111'::uuid)$$, 'A reads only their own profile');
select is((select count(*)::int from public.profiles where id = '22222222-2222-4222-8222-222222222222'),
  0, 'A cannot read B by asking for B''s id');

select lives_ok($$update public.profiles set display_name = 'Test A2', home_city = 'Testville'
  where id = '11111111-1111-4111-8111-111111111111'$$, 'A can update their own profile');
update public.profiles set display_name = 'hijacked' where id = '22222222-2222-4222-8222-222222222222';

select throws_ok($$update public.profiles set id = '22222222-2222-4222-8222-222222222222'
  where id = '11111111-1111-4111-8111-111111111111'$$, '42501', null, 'A cannot change a profile''s id');
select throws_ok($$update public.profiles set created_at = now() - interval '1 year'
  where id = '11111111-1111-4111-8111-111111111111'$$, '42501', null, 'A cannot change created_at');
select throws_ok($$insert into public.profiles (id, display_name)
  values ('33333333-3333-4333-8333-333333333333', 'spoof')$$, '42501', null, 'A cannot insert a profile (client-supplied id grants nothing)');
select throws_ok($$delete from public.profiles where id = '11111111-1111-4111-8111-111111111111'$$,
  '42501', null, 'A cannot delete profiles from the client');
select throws_ok($$update public.profiles set default_radius_m = 999999
  where id = '11111111-1111-4111-8111-111111111111'$$, '23514', null, 'radius stays within limits');
reset role;
-- Asked as privilege checks (as the owner: API roles can't even see the
-- schema), not by calling: on supabase/postgres
-- 17.6.1.111 calling a revoked function crashes the server (supautils).
select ok(not has_schema_privilege('authenticated', 'private', 'usage')
  and not has_schema_privilege('anon', 'private', 'usage')
  and not has_function_privilege('authenticated', 'private.handle_new_user()', 'execute')
  and not has_function_privilege('anon', 'private.handle_new_user()', 'execute'),
  'API roles cannot reach the trigger functions');

-- Anonymous: nothing at all.
reset role;
set local role anon;
select set_config('request.jwt.claims', '{"role": "anon"}', true);
select throws_ok($$select * from public.profiles$$, '42501', null, 'anonymous requests cannot read profiles');
select throws_ok($$update public.profiles set display_name = 'x'$$, '42501', null, 'anonymous requests cannot update profiles');

-- Back to the owner to check what really happened.
reset role;
select is((select display_name from public.profiles where id = '22222222-2222-4222-8222-222222222222'),
  'there', 'B is untouched by A''s update attempt');
select is((select display_name from public.profiles where id = '11111111-1111-4111-8111-111111111111'),
  'Test A2', 'A''s own update applied');

-- Deleting the account removes the profile.
delete from auth.users where id = '11111111-1111-4111-8111-111111111111';
select is((select count(*)::int from public.profiles where id = '11111111-1111-4111-8111-111111111111'),
  0, 'deleting the account removes its profile');

select * from finish();
rollback;
