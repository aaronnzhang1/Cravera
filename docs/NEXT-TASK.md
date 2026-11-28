# TASK-004 · Saved hub

**Goal.** Saved becomes "a central hub for places you've been to or want to go" (maintainer): a signed-in person's saved places live in their own Supabase rows, sorted into Want to go and Been, grouped by city, on a real Google map, with notes; tapping a place opens the same full page as the smart card. From [the v0.2 plan](plans/v0.2-hub.md) (task 2).

**Release:** v0.2.0 · Accounts. Follows TASK-UI-4 (merged in #40; its four remaining criteria are listed in CURRENT.md and its full spec is in this file's history at a9d8eec).
**Approved:** 2026-11-27 (maintainer: "Ok go for it"), as written, including `google_maps_flutter` and applying the migration after clean reviews. Decided earlier the same day: a real Google map with a restricted Maps SDK key in the app ([ADR 0006](adr/0006-maps-sdk-key-in-app.md)); the list loads only basic facts and the full details load when a place is tapped; stay inside the free tiers while testing. Claude may work any criterion below without asking again; anything outside this file's scope still needs approval.
**Review level:** L3: a migration with RLS, personal data (what places someone saves, their notes), a Google key in the app, a new Edge Function.

## What may be stored

Google's terms (as understood 2026-11-27; recheck when building): a place ID may be stored indefinitely; names, addresses, photos, ratings and coordinates may not be kept (coordinates up to 30 days). So a row holds the place ID and the person's own data only, and every fact shown is fetched fresh.

## Acceptance criteria

Tick a box only after checking it in the running app with real data. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [ ] `saved_places` (id, `user_id` = `auth.uid()` by default, `place_id` checked against the Places ID format, status `want_to_go` | `been`, note ≤ 500 characters, timestamps; one row per person and place) with RLS on and deny by default: a person selects, inserts, updates and deletes only their own rows; no Google content is stored besides the place ID. Applied to the hosted project only after clean reviews and the maintainer's go.
- [ ] Denial-path tests against a local Supabase: another person's rows can't be read, changed or deleted; anonymous requests get nothing; a client-supplied `user_id` grants nothing; a malformed place ID or status is refused.
- [ ] Bookmark on the pick saves the place for a signed-in person (Want to go) and removing it deletes the row; a guest gets "Create an account to save places" and nothing is stored on the device as if saved.
- [ ] Saved shows Want to go and Been, each grouped by city, with name and address fetched fresh through an Edge Function using only basic Place Details fields (Google's Essentials tier); one request per saved place per open, at most 50 places, failures shown per row without hiding the rest.
- [ ] Map view: a Google map (Maps SDK) with a pin for each place in the current tab; tapping a pin or a row opens the place's full page (the smart card's, loaded then); the Places and Gemini keys never reach the app.
- [ ] A person can move a place between Want to go and Been, add or edit a note, and remove it; each change saves to their own row, survives a restart and shows on another sign-in; a failed save says so and keeps the old state.
- [ ] Signing out or another account signing in clears Saved and closes any open place page (as Profile does).
- [ ] Function tests (input validation, publishable-key and caller checks, field mask is Essentials only, no logging of place IDs with a user); `flutter analyze` and `flutter test` pass, with tests for each state (empty, loading, loaded, a failed row, guest) and the accessibility guidelines at 1x and 2x text.
- [ ] Checked in the app on Android and iPhone with real saved places; the built app's key scan finds only the restricted Maps SDK key.

## Needs from the maintainer before building

1. Create the Maps SDK key in Google Cloud Console and restrict it (Android: package `com.cravera.app` with the debug SHA-1, which Claude will print; iOS: bundle ID; APIs: Maps SDK for Android and iOS only). Put it in a local file Claude names, not in chat.
2. A daily quota on Place Details Essentials (for example 300/day; about 10,000 a month are free).
3. OK to add `google_maps_flutter` (official Flutter plugin) and to apply the migration after review.

## Out of scope

- Tags, visited dates, sorting options, sharing saved places with friends, offline maps.
