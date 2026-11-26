# Handoff

## TASK-001 · A guest gets a real open restaurant near them

- **State.** `main` has the full UI on demo data (4 hardcoded restaurants in `lib/core/session.dart`), the agent workflow docs, the session-start hook, and CI (`secrets` gitleaks scan + `checks`: `flutter analyze` and `flutter test` on Flutter 3.41.9). All four services in `lib/services/` are empty stubs. Sign-in accepts anything; bookmarks and ratings live in memory; the filter sheet discards its values; Friends and the recs inbox are placeholders; Yes searches Google Maps by name only. Nothing in the repo talks to Supabase yet (no client package, schema or functions).
- **Last change.** On branch `feat/task-001-guest-search` (not pushed, no PR): added "Continue as guest" (commit 277e207). `AppSession` has a guest state separate from sign-in, the router lets guests into `/app`, and sign out clears it. Checks on Windows: `flutter analyze` no issues; `flutter test` 2 passed. Not yet tried in the running app, so the NEXT-TASK box is unticked.
- **Open problems.**
  - `.env.example` holds only public Supabase config (Codex review finding). The Mac's `.env` holds real private keys (including Gemini): move them to Supabase Edge Function secrets during TASK-001 and remove them from `.env`. The Windows `.env` has placeholders only.
  - The `secrets` CI job is defined in a workflow a PR can edit; GitHub secret scanning with push protection is the independent control (repo setting).
  - Unverified: the Android maps launch (the manifest has no `<queries>` entry for https links); a Google Cloud project with the Places API (New) enabled.
  - Windows PC (2026-11-26): Flutter 3.41.9 matches CI; Android SDK and a `Pixel_10_Pro` emulator exist (`flutter emulators --launch Pixel_10_Pro`). Still to do: accept the Android licenses (`flutter doctor --android-licenses`), install the Supabase CLI, and update Git to 2.56.1 with Claude Code closed. Dart packages are behind (geolocator 11 → 14, go_router 13 → 18). Upgrade them as code changes, not as setup.
  - `mobile/Cravera/cursorrules` repeats rules now in AGENTS.md and PRODUCT.md; delete it if Cursor is no longer used. `C:\Developer\Cravera Docs\Cravio-Project-Status.md` is superseded by this file.
  - The app is still called Cravio in code (PRODUCT.md open decision 2).
- **Next action.** Try the guest button in the running app and tick its box. Then do the location criterion (device location, with typed-address fallback). The Places search needs the Google key and Supabase CLI first (ADR 0003: keys go in Edge Function secrets).
