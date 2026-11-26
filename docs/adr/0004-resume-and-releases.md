# 0004 · Resume entry point, task approval and releases

- **Status:** Accepted (maintainer, 2026-11-26)
- **Date:** 2026-11-26

## Context

Sessions lost context: one started outside the repo, so no instructions or hook loaded; CURRENT.md drifted into a narrative of branches; branches were pushed without PRs; two PR heads sat without the Codex review their level requires. The maintainer had to ask for each of these. Nothing recorded which tasks were approved or what had shipped.

## Decision

- One entry point, the repo skill `/resume`, runs the AGENTS.md start steps and picks the next item. The SessionStart hook stays minimal (ADR 0001); longer checks run inside `/resume`.
- NEXT-TASK.md carries an `Approved:` line. With it, Claude works the task's criteria without asking again.
- Releases are PRODUCT.md rows with exit criteria, shipped as Git tags. One task ID runs through the spec, branch, PR title and release row.
- PR follow-up uses the built-in `/steward`; second-model review on GitHub uses Codex cloud review (P0/P1 only), in addition to the local review the level requires.

## Consequences

No new hooks or CI. If a step is still skipped, name it and add the smallest enforcement that fixes it. A Stop gate stays off for the reasons in ADR 0001.
