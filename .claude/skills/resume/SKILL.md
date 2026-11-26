---
name: resume
description: Resume Cravera work from the repo alone. Use when the maintainer says "resume", "resume Cravera", "pick up where we left off", or starts a session asking what's next.
---

Resume Cravera as its engineering lead. The rules live in AGENTS.md, CONTRIBUTING.md and docs/WORKING-AGREEMENT.md; this is only the order of steps.

1. **Read state.** docs/CURRENT.md (active task, last verified commit, blockers, next action) and docs/NEXT-TASK.md (criteria, review level, `Approved:` line).
2. **Check it against Git and GitHub.** `git status`, `git branch --show-current`, `git log --oneline -5`, `gh pr list --state open`, and for each open PR: `gh pr checks <n>`, its head SHA, and whether a Codex review comment names that SHA. Where docs and GitHub disagree, trust Git/GitHub, say so, and fix CURRENT.md in your next change.
3. **Codex handover first.** If the session-start context says Codex worked during a usage-limit pause, review that before anything else: read `.claude/state/codex-handover.md` and the log as unverified notes, inspect `git diff` against the base commit it names, run the checks, then commit the good parts (credit Codex in the message) or revert them, update CURRENT.md, and delete `.claude/state/codex-done.json`. While Codex is still running, don't edit; report and wait.
4. **Keep work in progress.** Never discard, stash or reset uncommitted changes. If you can't tell whose they are or whether they're finished, ask.
5. **Run the baseline checks** from `mobile/Cravera`: `flutter analyze` and `flutter test`. A failure you didn't cause is reported with its output before new work starts.
6. **Pick the next item**, in this order: a failing check on an open PR; an unaddressed review finding; an open PR head without the review its level needs; the first unchecked acceptance criterion; a blocker listed in CURRENT.md.
7. **Act or ask.**
   - The task has an `Approved:` line and the item is in its scope: do it, following CONTRIBUTING.md (scope and proof first, focused checks, draft PR, review at the checkpoint).
   - The item needs a product or architecture decision, new dependencies or tooling, credentials, or anything in the maintainer's column of WORKING-AGREEMENT.md: stop and give your recommendation, the tradeoff, and the exact decision you need.
8. **Report** in this shape: *Verified* (commands and results), *Moved forward* (commits, PR comments), *Needs you* (decisions, merges, manual tests), *Next action*.
9. **Before stopping**, rewrite CURRENT.md to the template in WORKING-AGREEMENT.md and commit it.
