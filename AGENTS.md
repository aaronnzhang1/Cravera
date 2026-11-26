# Cravera

A Flutter app where a guest describes a craving in plain language and gets one nearby restaurant that is open now. Supabase/Postgres is the backend. Code lives in `mobile/Cravera/` (Dart package `cravera`, app ID `com.cravera.app`).

## Start or resume a session

1. Read [CURRENT.md](docs/CURRENT.md).
2. Check it against `git status`, `git log --oneline -5`, `gh pr view <n>` for each PR it names, and `gh pr list --state open`. If they disagree, trust Git and GitHub, say so, and fix CURRENT.md in your change.
3. From `mobile/Cravera`, run `flutter analyze` and `flutter test`. If they fail, fix that before starting new work.
4. Open other docs only when the task needs them:

| Question | Read |
|---|---|
| Scope, roadmap, open decisions | [PRODUCT.md](docs/PRODUCT.md) |
| What the active task must prove | [NEXT-TASK.md](docs/NEXT-TASK.md) |
| Setting up a machine, running the app | [HOW_TO_RUN.md](HOW_TO_RUN.md) |
| Review levels, triage, merging | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Secrets and leaks | [SECURITY.md](SECURITY.md) |
| Roles, multi-agent rules, handoff | [WORKING-AGREEMENT.md](docs/WORKING-AGREEMENT.md) |
| Why something is built this way | [Decision records](docs/adr/README.md): read the index, open only what you need |

## Coding rules

- Stack: Flutter (Dart), Supabase, Gemini, Google Places ([ADR 0002](docs/adr/0002-stack.md)).
- **The LLM never produces restaurant data.** Gemini only turns a craving into structured search filters (JSON). Every name, photo, address, price, hour and distance shown comes from Google Places. Always search with open-now.
- Keep secrets and business rules server-side. `.env` is bundled into the app, so nothing secret may rely on it ([ADR 0003](docs/adr/0003-api-key-handling.md)). Deny by default. Client-supplied IDs grant nothing. Enforce permissions in code (Supabase RLS), never in prompts.
- API and business logic go in `lib/services/`, not in screen widgets. Navigation uses go_router.
- Use only fictional data in code, tests, logs and fixtures.
- Start the app with `flutter run` from `mobile/Cravera` (needs a `.env`; copy `.env.example`). Before review, run the checks, and try user-facing changes in the running app the way a user would. Report actual results.
- Work on one acceptance criterion at a time, and commit each working step with a descriptive message.
- These instructions don't authorize history rewrites, merges, purchases, deployments or messages to other people.

## Before you stop

Update CURRENT.md ([handoff](docs/WORKING-AGREEMENT.md#hand-off)). The next session must be able to resume from CURRENT.md and Git alone.

## Review guidelines

For Codex reviews. Review adversarially: look for reasons the change should not ship.

- P1: access-control gaps (client-supplied IDs, missing scoping, not default-deny, missing RLS); data-integrity risks (irreversible migrations, partial failure, non-idempotent retries, stale writes); secrets or personal data in code, tests, logs or the bundled `.env`; LLM output used as restaurant data; a search that can return closed restaurants; a security change without a denial-path test; a CI job rename that breaks required checks; a review level that is missing or understated ([levels](CONTRIBUTING.md#review-levels)).
- For a committed secret, cite the file and line only, never the value.
- Every finding names the file, line, failure scenario and a concrete fix.
