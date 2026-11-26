# Handoff

## TASK-001 · A guest gets a real open restaurant near them (release v0.1.0)

- **Active:** TASK-001, approved. Three stacked branches, merge in order: `feat/task-001-guest-search` → `feat/ui-rehaul` (TASK-UI-1) → `docs/workflow-plan`. The location branch had 3 Codex adversarial rounds; round 3's finding (a SnackBar can echo a typed address over the sign-in screen after sign out) and round 2's deferred finding (location is collected before search uses it) wait on the maintainer, as recorded on that branch's PR. The UI branch has no Codex review yet (L2); it must take the location branch's latest commits before review.
- **Last verified:** `ba24b3b` (location branch): `flutter analyze` no issues, `flutter test` 13 passed, CI `secrets` + `checks` green. `9e360f0` (UI branch): analyze clean, 8 tests; emulator screenshots of sign-in, home, Saved, Profile in the violet + sage palette, no Flutter errors in logcat.
- **State after these merge:** full UI on demo data (4 hardcoded restaurants in `lib/core/session.dart`); guest mode; device location with a typed-place fallback, cleared on sign out, stale cached fixes rejected, only the newest lookup kept; app named Cravera (`com.cravera.app`); violet + sage palette; `/resume` skill, `Approved:` line on tasks, release rows in PRODUCT.md (ADR 0004). All four services in `lib/services/` are still stubs; nothing talks to Supabase.
- **Open problems:**
  - Maintainer decisions on the location branch's round 2 and round 3 findings (see its PR).
  - Cloud Codex review isn't enabled yet (no `chatgpt-codex-connector` review on any PR): maintainer turns it on at chatgpt.com/settings/code-review, then `@codex review` on a PR verifies it.
  - Real keys (including Gemini) are in the Mac's `.env`: move them to Supabase Edge Function secrets during TASK-001 and remove them from `.env`. The Windows `.env` has placeholders only.
  - Unverified: Places API (New) enabled on the maintainer's Google Cloud project. Not run on an iPhone or a real Android phone.
  - `mobile/Cravera/cursorrules` duplicates AGENTS.md and PRODUCT.md: delete once the maintainer agrees.
  - Windows PC: Flutter 3.41.9 (matches CI), `Pixel_10_Pro` emulator, `adb` at `%LOCALAPPDATA%\Android\Sdk\platform-tools` (not on PATH), Supabase CLI 3.4.0 at `~/bin/supabase.exe`.
- **Next action:** once the maintainer decides on the location findings, apply the round 3 fix if approved and run round 4. Then criterion 3: with the maintainer, link Supabase and set the Google key as an Edge Function secret (ADR 0003), and write a `places-search` Edge Function (Text Search (New), open-now, location restriction) called from `PlacesService`.
