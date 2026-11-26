# 0001 · Agent workflow

- **Status:** Accepted
- **Date:** 2026-11-26

## Decision

Claude Code builds, Codex reviews through its Claude Code plugin, and the maintainer merges. The repo and GitHub are the only shared memory between sessions, models and people. Personal agent memory may supplement them, never replace them. Each rule has one home, and other docs link to it.

## Context

This workflow comes from an earlier project. Each rule answers a problem that happened there:

| Rule | Why |
|---|---|
| Review findings go on the PR | A review that existed only in chat left no record |
| CURRENT.md describes `main` after the merge, and each session checks it against Git | After merges it still described open drafts, and fresh sessions trusted the stale state |
| CURRENT.md doesn't name its own PR | A PR can't know its number in advance, so the reference went stale |
| Plans that need review go in `docs/plans/` | Plans existed only in chat |
| The session-start hook prints only counts and a commit ID | Hook output is trusted context. Printing commit messages or branch names would let anyone who writes them inject instructions |
| AGENTS.md is the entry point; CLAUDE.md only imports it | Claude Code reads CLAUDE.md. Codex reads AGENTS.md and ignores `@imports` |
| Small ADRs read on demand, not one growing log | The log mixed active and superseded rules, and one rule lived in three places |
| Review levels, checkpoints, triage, escalation after 3 rounds | One PR took 11 adversarial review rounds for a single CI step. Causes: little research before using unfamiliar tooling, no threat model, every finding treated as a requirement and fixed one at a time, a full review after every push, growing complexity and regressions from fixes, and rules kept in personal memory instead of the repo |
| No custom review enforcement until it's needed and proven | A per-turn adversarial Stop hook slowed every turn and drew about 15 review rounds on its own edge cases |
| Merge with `--match-head-commit` after checking the final head's reviews | A PR's last commit merged without the review the policy required |
| "Reviewed", "no blockers", "resolved" and "mergeable" are separate facts | Codex on GitHub isn't a merge gate, and its security-review receipt was once mistaken for the code review |
| Verify the stop gate with `/codex:status` in a fresh session | When the gate was enabled in a session that predated the plugin, the setting landed in a temp folder the hook never reads |
| Every rule records its reason | An unexplained rule caused a false P1 in review |
| Ask before folding out-of-scope fixes into a PR | A README PR grew into setup-code changes after review findings |
| Keep always-loaded docs short | Every line is paid for in tokens in every session |
| Run the checks at session start, before new work | Anthropic's published long-running-agent harness: a new session inherits whatever the last one broke, and builds on top of it unless it checks first |
| Tick a criterion only after trying it in the running app; never edit criteria | Same source: agents declared work done too early and marked features as passing without testing them the way a user would |
| Second-model review only at L2 and up; tune its guidelines when it misjudges | Same source: a separate reviewer is worth its cost only where the work is beyond what the model does reliably alone, and it needs calibrating against your judgment |

## Consequences

`AGENTS.md` and `CURRENT.md` stay short. Rules change only through a PR, with an ADR whenever the reason isn't obvious.
