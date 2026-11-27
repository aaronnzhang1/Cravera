-- TASK-003 · Accounts: one profile per auth user, readable and editable only
-- by that user. Deny by default: RLS on, no access for anon, and the
-- authenticated role may only select and update its own row (and only the
-- columns a person edits). Rows are created by the sign-up trigger and
-- removed with the auth user (ON DELETE CASCADE): no client insert or delete.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  home_city text check (home_city is null or char_length(home_city) <= 80),
  dietary_preferences text[] not null default '{}'
    check (cardinality(dietary_preferences) <= 12),
  default_radius_m integer not null default 5000
    check (default_radius_m between 500 and 20000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Supabase grants new public tables to the API roles by default: take that
-- back, then grant only what a signed-in person needs.
revoke all on table public.profiles from anon, authenticated;
grant select on table public.profiles to authenticated;
grant update (display_name, home_city, dietary_preferences, default_radius_m)
  on table public.profiles to authenticated;

create policy "profiles: read own"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

create policy "profiles: update own"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Keeps updated_at honest whatever the client sends.
create function public.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function public.touch_updated_at();

-- A profile for every new account. The display name comes from the sign-up
-- metadata (the person's own input), trimmed and capped; never from a
-- client-chosen user ID.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), 'there'), 60)
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
revoke execute on function public.touch_updated_at() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
