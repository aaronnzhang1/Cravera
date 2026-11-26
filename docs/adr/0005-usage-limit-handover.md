# 0005 · Usage-limit handover to Codex

- **Status:** Accepted (maintainer, 2026-11-26)
- **Date:** 2026-11-26

## Context

The maintainer is on a usage-limited Claude plan and wants work to continue, without losing context or actions, when the limit hits mid-task, and every new session to check where things stand without being asked. Claude Code offers a `StopFailure` hook (matcher `rate_limit`) that can start a background process but cannot retry the turn, and the status line receives `rate_limits.five_hour.used_percentage`. A probe showed `codex exec -s workspace-write` can edit files but cannot write `.git`, so it can't commit or push.

## Decision

`.claude/hooks/handover.mjs`, wired in `.claude/settings.json`:
- **Status line** shows 5-hour usage and saves it. At 85%, a `PostToolUse` hook tells Claude once per window to commit, push and update CURRENT.md.
- **On a usage limit** (`StopFailure`, `rate_limit`), on a feature branch only: commit and push Claude's work in progress as a `WIP:` checkpoint, then start Codex in the background on the same branch with the resume steps and strict limits (no branch switch, CURRENT.md, `.env`, dependencies, CI or settings changes). Codex leaves its changes uncommitted and writes `.claude/state/codex-handover.md`.
- **While Codex runs**, Claude's file edits are blocked (`PreToolUse`), so there is one writer.
- **Every session start and prompt** reports a running or finished handover; session start also tells Claude to run the `/resume` steps. Claude reviews Codex's diff before committing it, so the reviewer never reviews its own change.

## Consequences

- Hook output is fixed text plus numbers and paths, never Codex's words (ADR 0001).
- Not covered: limits hit on `main` (skipped and reported), API-key sessions without `rate_limits`, and Codex being unable to run Flutter checks in its sandbox (Claude runs them on review). Codex stops after one step or 60 minutes.
- This is the first custom automation in the repo. If it misfires, remove the entries from `.claude/settings.json`; nothing else depends on it.
