# Handoff

## TASK-001 · A guest gets a real open restaurant near them (release v0.1.0)

- **Active:** TASK-001, approved; criterion 1 done. The search backend and the app's search service are built; next is piece 3, wiring Home to `PlacesService` (criteria 2, 3, 5 and 8), then checking it on the emulator. The usage-limit handover to Codex was closed unmerged (maintainer, 2026-11-27); its branch `feat/usage-limit-handover` is kept, behind `main`, with two open findings on the PR.
- **Last verified:** `flutter analyze` no issues, `flutter test` 40 passed; `node --test supabase/functions/places-search/logic.test.ts` 22 passed. Live: "ramen" near a San Francisco test point → 20 open restaurants; no key or wrong key → 401; latitude 89.9 → 400. Reviews per PR are on the PRs; `main` at the PlacesService merge, checks re-run there.
- **State:** `places-search` Edge Function deployed (Places Text Search (New), open-now, restaurants only, inside the radius; publishable-key check because `verify_jwt` is off). `PlacesService` in the app calls it; the project URL is fixed in `AppConstants.supabaseUrl`, and `.env` holds only `SUPABASE_PUBLISHABLE_KEY`. No screen uses it yet: Home still shows the 4 demo restaurants in `lib/core/session.dart`. Review loop in CONTRIBUTING.md: the lead runs local Codex at each L2/L3 checkpoint and requests cloud Codex on every PR.
- **Open problems:**
  - **Security gate, before any build leaves the maintainer:** `places-search` has no rate limit, and anyone with the public publishable key can call it. While testing, cost is bounded only by a Google Cloud daily quota on Places API (New) (about 1,000 requests, maintainer setting it 2026-11-27; unverified) and a $10 budget alert (unverified). Build per-device and daily limits first (PRODUCT.md decision 3).
  - Deferred: only Google's first page (20) is fetched, so a page that falls entirely outside the circle shows "no results" (→ criterion 5, "results run out → refine"). Photos: only `photoName` is returned; images need a server-side step (→ criterion 4).
  - Privacy hardening before public release: Google can read the user's exact location from the centre of the search box (with the craving, but no user ID, IP or account). Snap the box to a coarse grid and pad it; keep exact coordinates for the radius filter (Codex, PR `feat/places-service`, deferred).
  - Web builds: browsers ignore `followRedirects = false`; web isn't a v0.1.0 target.
  - Edge Function tests run locally with Node 24, not in CI.
  - Deferred findings on earlier PRs: typed lookup lost if Home is left mid-lookup (→ piece 3); no Back/Cancel from sign-up and the guest prompt promises saved bookmarks/ratings (→ auth); fixed 60 pt nav tabs, non-wrapping price chips, tab slide direction (→ UI redesign).
  - The Mac's `.env` may still hold the real Gemini/Places keys (unverified): delete them there, run `flutter clean`, and add `SUPABASE_PUBLISHABLE_KEY` (keys are now in Supabase secrets as `GOOGLE_MAPS_API_KEY`, `GOOGLE_GEMINI_API_KEY`).
  - Not run on an iPhone or a real Android phone.
  - `mobile/Cravera/cursorrules` duplicates AGENTS.md and PRODUCT.md: delete once the maintainer agrees.
  - Windows PC: Flutter 3.41.9 (matches CI), `Pixel_10_Pro` emulator, `adb` at `%LOCALAPPDATA%\Android\Sdk\platform-tools` (not on PATH), Supabase CLI 3.4.0 at `~/bin/supabase.exe`, logged in and linked.
- **Next action:** piece 3 on a new branch from `main`: Home searches with `PlacesService` around the device or typed location, No shows the next result, and empty, no-network and failed searches each show a message with a retry; try it on the `Pixel_10_Pro` emulator with a mocked location.
