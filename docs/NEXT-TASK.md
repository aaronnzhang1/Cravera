# TASK-004 · Saved hub

**Goal.** Saved becomes "a central hub for places you've been to or want to go" (maintainer): a signed-in person's saved places live in their own Supabase rows, sorted into Want to go and Been, grouped by city, on a real Google map, with notes; tapping a place opens the same full page as the smart card. From [the v0.2 plan](plans/v0.2-hub.md) (task 2).

**Release:** v0.2.0 · Accounts. Follows TASK-UI-4 (merged in #40; its four remaining criteria are listed in CURRENT.md and its full spec is in this file's history at a9d8eec).
**Approved:** 2026-11-27 (maintainer: "Ok go for it"), as written, including `google_maps_flutter` and applying the migration after clean reviews. Decided earlier the same day: a real Google map with a restricted Maps SDK key in the app ([ADR 0006](adr/0006-maps-sdk-key-in-app.md)); the list loads only basic facts and the full details load when a place is tapped; stay inside the free tiers while testing. Claude may work any criterion below without asking again; anything outside this file's scope still needs approval.
**Review level:** L3: a migration with RLS, personal data (what places someone saves, their notes), a Google key in the app, a new Edge Function.

## What may be stored

Google's terms (as understood 2026-11-27; recheck when building): a place ID may be stored indefinitely; names, addresses, photos, ratings and coordinates may not be kept (coordinates up to 30 days). So a row holds the place ID and the person's own data only, and every fact shown is fetched fresh.

## Acceptance criteria

Tick a box only after checking it in the running app with real data. Never delete or reword a criterion. Propose any change to the maintainer instead.

- [x] `saved_places` (id, `user_id` = `auth.uid()` by default, `place_id` checked against the Places ID format, status `want_to_go` | `been`, note ≤ 500 characters, timestamps; one row per person and place) with RLS on and deny by default: a person selects, inserts, updates and deletes only their own rows; no Google content is stored besides the place ID. Applied to the hosted project only after clean reviews and the maintainer's go.
- [x] Denial-path tests against a local Supabase: another person's rows can't be read, changed or deleted; anonymous requests get nothing; a client-supplied `user_id` grants nothing; a malformed place ID or status is refused.
- [ ] Bookmark on the pick saves the place for a signed-in person (Want to go) and removing it deletes the row; a guest gets "Create an account to save places" and nothing is stored on the device as if saved.
- [x] Saved shows Want to go and Been, each grouped by city, with name and address fetched fresh through an Edge Function using only basic Place Details fields (Google's Essentials tier); one request per saved place per open, at most 50 places, failures shown per row without hiding the rest.
- [ ] Map view: a Google map (Maps SDK) with a pin for each place in the current tab; tapping a pin or a row opens the place's full page (the smart card's, loaded then); the Places and Gemini keys never reach the app.
- [ ] A person can move a place between Want to go and Been, add or edit a note, and remove it; each change saves to their own row, survives a restart and shows on another sign-in; a failed save says so and keeps the old state.
- [ ] Signing out or another account signing in clears Saved and closes any open place page (as Profile does).
- [ ] Function tests (input validation, publishable-key and caller checks, field mask is Essentials only, no logging of place IDs with a user); `flutter analyze` and `flutter test` pass, with tests for each state (empty, loading, loaded, a failed row, guest) and the accessibility guidelines at 1x and 2x text.
- [ ] Checked in the app on Android and iPhone with real saved places; the built app's key scan finds only the restricted Maps SDK key.

## Decided while building (maintainer, 2026-11-27)

Google bills a place's name (`displayName`) in the **Pro** tier, not Essentials (Codex on PR #41 found the same). The maintainer chose **Pro for the list** (name, address, location, address parts), kept free by a daily Place Details Pro quota of about 150 (about 5,000 free a month). The list criterion's "Essentials tier" reads as "Pro tier" from here on; everything else in it stands.

## Needs from the maintainer before building

1. Create two Maps SDK keys in Google Cloud Console (a key takes one kind of app restriction): an Android key (package `com.cravera.app`, debug SHA-1 `E5:1C:1B:BE:54:88:19:82:6F:93:07:80:3B:BB:0C:A3:88:8A:6D:E5`; API: Maps SDK for Android only) and an iOS key (bundle ID; API: Maps SDK for iOS only). Android key in `mobile/Cravera/android/local.properties` as `MAPS_ANDROID_KEY=…` (git-ignored); the iOS key on the Mac, in a file Claude names then. Never in chat.
2. A daily quota on Place Details Pro (about 150/day; about 5,000 a month are free); Text Search back to about 30/day; a $1 budget alert.
3. OK to add `google_maps_flutter` (official Flutter plugin) and to apply the migration after review.

## Checked

- 2026-11-28 ~00:00 PST: `saved_places` applied to the hosted project (after local Codex rounds 1–4 and cloud Codex clean on 5c57ea0; the maintainer: "go for it"); live, anonymous select and insert answer 401 "permission denied". `saved-places` deployed; no token and a fake token answer 401. Local pgTAP: 20 saved_places + 17 profiles pass.
- 2026-11-28 ~23:50–23:54 PST (emulator clock), `Pixel_10_Pro`, San Francisco, signed in with the maintainer's test account, real data: "Cozy ramen nearby" → bookmark → "Saved to Want to go." (HINODEYA Ramen Union Square); No → bookmark HINODEYA Ramen Japantown. Saved: 2 places under "San Francisco", names and addresses fetched fresh. Union Square → Been ("Saved.", counts 1/1) → note "Try the spicy miso" ("Saved.", shown on the row). App restarted (reinstalled with data kept): still signed in, same 2 places, statuses kept. Show map: a real Google map (restricted Android key) with the Want to go pin at Japantown (Buchanan St). Both removed with "Remove from Saved"; Saved empty again (the account left as it was). Found and fixed: the place sheet opened under the nav bar (now above it, like Profile's).
- Not yet seen in the app: the guest prompt (widget-tested), a second sign-in showing the same places, sign-out clearing Saved (unit-tested), a failed save's message (unit-tested), the full page from Saved, iPhone.

## Out of scope

- Tags, visited dates, sorting options, sharing saved places with friends, offline maps.
