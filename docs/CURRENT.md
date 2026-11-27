# Handoff

## TASK-001 · A guest gets a real open restaurant near them (release v0.1.0)

- **Active:** TASK-001, approved. Criteria 1, 3, 5 and 6 are checked in the running app. Left: 2 (check a denied location permission in the app, then a typed place), 4 (photo on the card), 7 (confirm no Google/Gemini key in the built bundle), 8 (check "no results" and "function fails" in the app; no network is checked), 9 (checks and tests, already green).
- **Last verified:** `flutter analyze` no issues, `flutter test` 68 passed; function tests 22 passed. On the `Pixel_10_Pro` emulator with a mocked San Francisco location: guest → "ramen" → a real open place; No twice → third place with no new request; Yes → Google Maps directions to that exact place; airplane mode → "No connection." and Try again recovers; typed "Oakland" → tacos there; No to the end → "That's every open match" → refine "spicy" → new search "tacos spicy"; ✕ on the card → back to Home.
- **State:** Home searches through `CravingSearch` (`lib/services/craving_search.dart`) → `PlacesService` → the `places-search` Edge Function. The 4 demo restaurants in `lib/core/session.dart` now only feed the demo bookmarks. Sign out clears the search. Yes uses `/maps/dir/` with coordinates and the place ID. Merged branches are deleted (GitHub deletes head branches on merge; delete local copies after each merge); only a long-lived branch with a reason stays.
- **Open problems:**
  - **Security gate, before any build leaves the maintainer:** `places-search` has no rate limit, and anyone with the public publishable key can call it. While testing there is no hard cap (maintainer, 2026-11-27): set a daily quota on SearchTextRequest (about 30/day stays within the ~1,000 free Enterprise searches a month) once search works end to end; a $10 budget alert may be set (unverified).
  - Privacy hardening before public release: Google can read the user's exact location from the centre of the search box (with the craving, but no user ID, IP or account). Snap the box to a coarse grid and pad it; keep exact coordinates for the radius filter.
  - Deferred (Codex round 4 on PR `feat/home-live-search`, maintainer chose to merge): if Home stays open and untouched past the 15-minute window, the expired card stays visible until the next redraw; Yes, No and app resume all re-check, so no directions come from it. Fix with an expiry timer in `CravingSearch` (tests need a fake clock for timers).
  - Deferred: only Google's first page (20) is fetched. Photos: only `photoName` comes back; showing images needs a server-side step (→ criterion 4).
  - Web builds: browsers ignore `followRedirects = false`; web isn't a v0.1.0 target.
  - Edge Function tests run locally with Node 24, not in CI.
  - UI (→ redesign): the floating nav bar covers the bottom of the Yes sheet; the No/Yes buttons move when a name wraps; fixed 60 pt nav tabs, non-wrapping price chips, tab slide direction; no Back/Cancel from sign-up and the guest prompt promises saved bookmarks/ratings (→ auth).
  - iPhone: not run yet. The iOS Simulator needs the Mac: `flutter run` in `mobile/Cravera` there. Not run on a real Android phone either.
  - The Mac's `.env` may still hold the real Gemini/Places keys (unverified): delete them there, run `flutter clean`, and add `SUPABASE_PUBLISHABLE_KEY` (keys are in Supabase secrets as `GOOGLE_MAPS_API_KEY`, `GOOGLE_GEMINI_API_KEY`).
  - `mobile/Cravera/cursorrules` duplicates AGENTS.md and PRODUCT.md: delete once the maintainer agrees.
  - The usage-limit handover PR was closed unmerged (maintainer, 2026-11-27); branch `feat/usage-limit-handover` is kept, behind `main`.
  - Windows PC: Flutter 3.41.9 (matches CI), `Pixel_10_Pro` emulator, `adb` and `emulator` under `%LOCALAPPDATA%\Android\Sdk` (not on PATH; in Git Bash set `MSYS_NO_PATHCONV=1` for `adb shell` paths), Supabase CLI 3.4.0 at `~/bin/supabase.exe`, logged in and linked.
- **Next action:** finish TASK-001: criterion 4 (card photo through the function, without exposing the key), then check 2, 7 and 8 in the app and on the Mac's iPhone Simulator.
