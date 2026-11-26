# Working agreement

## Roles

| Role | Who | Does |
|---|---|---|
| Builder | Claude Code | Plans, builds, runs checks, opens draft PRs, owns CURRENT.md |
| Reviewer | Codex (Claude Code plugin) | Reviews independently; `/codex:rescue` for a diagnosis or second implementation |
| Maintainer | Aaron | Assigns work, accepts and merges, approves anything outward-facing: merges, deletions, purchases, deployments, credentials |

Either model can take either role when assigned. The reviewer never reviews its own change.

## Tools

- Codex plugin: `/plugin marketplace add openai/codex-plugin-cc`, `/plugin install codex@openai-codex`, `/reload-plugins`, `/codex:setup`.
- Stop gate (optional, per clone): `/codex:setup --enable-review-gate`, then confirm with `/codex:status` in a **new** session. The gate is an ALLOW/BLOCK check of each editing turn, not a review, and never replaces the reviews a PR's level requires.

## Multi-agent work

Use the simplest structure that works: work alone first, then subagents. Each extra agent adds token cost. Every subagent prompt gives the objective, acceptance criteria, only the context it needs, the files it owns, prohibited actions, the checks to run and what to report. Subagents report to the lead and never edit CURRENT.md. Keep one writer per file. Only the lead changes Git state. Never use `bypassPermissions`, because helpers inherit it.

## Hand off

The lead overwrites CURRENT.md after meaningful progress and before stopping, including before a usage limit. It describes `main` as it will be after the open PR merges, without naming that PR's number. Leave out anything Git already records.

```md
## <task> · <title>
- **State:** what's on `main`; what's in progress, with branch.
- **Last change:** what this session did, exact checks and results, open findings.
- **Open problems:** blockers, failing checks, unverified assumptions.
- **Next action:** one concrete step.
```

Long-lived content goes elsewhere: acceptance criteria in NEXT-TASK.md, decisions in an ADR, scope in PRODUCT.md, review threads on the PR.
