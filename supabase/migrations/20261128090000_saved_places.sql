-- TASK-004 Saved hub: the places a signed-in person saves.
--
-- Only the place ID and the person's own data are stored: Google's terms
-- don't allow keeping names, addresses, photos or ratings, so the app fetches
-- those fresh. Deny by default: a person reaches only their own rows, and
-- user_id always comes from the access token, never from the client.

create table public.saved_places (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  place_id text not null check (char_length(place_id) between 1 and 300 and place_id ~ '^[A-Za-z0-9_-]+$'),
  status text not null default 'want_to_go' check (status in ('want_to_go', 'been')),
  note text check (note is null or char_length(note) <= 500),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, place_id)
);

create index saved_places_user_id_idx on public.saved_places (user_id);

alter table public.saved_places enable row level security;

-- Column grants: the client may set only the place, status and note;
-- user_id, id and timestamps are set by the database.
revoke all on table public.saved_places from anon, authenticated;
grant select, delete on table public.saved_places to authenticated;
grant insert (place_id, status, note) on table public.saved_places to authenticated;
grant update (status, note) on table public.saved_places to authenticated;

create policy "saved_places: read own"
  on public.saved_places for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "saved_places: insert own"
  on public.saved_places for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "saved_places: update own"
  on public.saved_places for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "saved_places: delete own"
  on public.saved_places for delete to authenticated
  using ((select auth.uid()) = user_id);

create trigger saved_places_touch_updated_at
  before update on public.saved_places
  for each row execute function private.touch_updated_at();
