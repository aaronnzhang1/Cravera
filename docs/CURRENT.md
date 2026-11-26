# Handoff

## TASK-001 · A guest gets a real open restaurant near them

- **State.** `main` has the full UI on demo data (4 hardcoded restaurants in `lib/core/session.dart`), the agent workflow docs, the session-start hook, and CI (`secrets` gitleaks scan + `checks`: `flutter analyze` and `flutter test` on Flutter 3.41.9). All four services in `lib/services/` are empty stubs. Sign-in accepts anything; bookmarks and ratings live in memory; the filter sheet discards its values; Friends and the recs inbox are placeholders; Yes searches Google Maps by name only. Nothing in the repo talks to Supabase yet (no client package, schema or functions).
- **Last change.** Audited the project after a six-month break, synced with GitHub, fixed the smoke test (it expected the old `cravio.` wordmark), adopted the agent workflow kit, and merged the three roadmap sources and new ideas into PRODUCT.md. Checks on Windows: `flutter analyze` no issues; `flutter test` 1 passed.
- **Open problems.**
  - ADR 0003 (keys behind Supabase Edge Functions) is Proposed; TASK-001 is blocked until it's accepted.
  - `.env.example` holds only public Supabase config (Codex review finding). The Mac's `.env` holds real private keys (including Gemini): move them to Supabase Edge Function secrets during TASK-001 and remove them from `.env`. The Windows `.env` has placeholders only.
  - The `secrets` CI job is defined in a workflow a PR can edit; GitHub secret scanning with push protection is the independent control (repo setting).
  - Unverified: the Android maps launch (the manifest has no `<queries>` entry for https links); Supabase CLI access; a Google Cloud project with the Places API (New) enabled.
  - `mobile/Cravera/cursorrules` repeats rules now in AGENTS.md and PRODUCT.md; delete it if Cursor is no longer used. `C:\Developer\Cravera Docs\Cravio-Project-Status.md` is superseded by this file.
  - The app is still called Cravio in code (PRODUCT.md open decision 2).
- **Next action.** Maintainer accepts or amends ADR 0003; then start TASK-001 on a `feat/` branch with the guest entry criterion.
