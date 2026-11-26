# 0005 · Usage-limit handover to Codex

- **Status:** Accepted (maintainer, 2026-11-26)
- **Date:** 2026-11-26

## Context

The maintainer is on a usage-limited Claude plan and wants work to continue, without losing context or actions, when the limit hits mid-task, and every new session to check where things stand without being asked. Claude Code offers a `StopFailure` hook (matcher `rate_limit`) that can start a background process but cannot retry the turn, and the status line receives `rate_limits.five_hour.used_percentage`. A probe showed `codex exec -s workspace-write` can edit files but cannot write `.git`, so it can't commit or push.

## Decision

`.claude/hooks/handover.mjs`, wired in `.claude/settings.json`:
- **Status line** shows 5-hour usage and saves it. At 85%, a `PostToolUse` hook tells Claude once per window to update CURRENT.md and commit locally (pushing stays the normal rule: finished, checked work only).
- **On a usage limit** (`StopFailure`, `rate_limit`), on a feature branch only: take an exclusive lock, make a local `WIP:` checkpoint commit of Claude's work (never pushed), create a sibling worktree `../<repo>-codex-handover` at that commit, and start Codex there in the background with the resume steps and strict limits. Codex leaves its changes uncommitted and writes notes in that worktree.
- **Claude's checkout is never shared** with Codex, so no edit blocking is needed. A finished but unreviewed handover blocks a new one.
- **Every session start and prompt** reports a running or finished handover; session start also tells Claude to run the `/resume` steps. Claude reviews Codex's diff before applying it, so the reviewer never reviews its own change.

## Consequences

- The first version shared Claude's checkout, pushed automatically, took its lock late and ran Codex through a shell; the PR's adversarial review blocked all four, and printed branch names into context against ADR 0001. This version fixes each: separate worktree, no push, lock before any Git change and released only by its owner, no shell, and hook output limited to fixed text, commit hashes, numbers and fixed paths.
- Not covered: limits hit on `main` (recorded and skipped), API-key sessions without `rate_limits`, and Codex being unable to run Flutter checks in its sandbox (Claude runs them on review). Codex stops after one step or 60 minutes (the whole process tree is stopped).
- This is the first custom automation in the repo. If it misfires, remove its entries from `.claude/settings.json`; nothing else depends on it.
