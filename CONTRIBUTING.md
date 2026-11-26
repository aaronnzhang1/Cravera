# Contributing

Applies to people and agents alike. Apply each step in proportion to the change.

## Workflow

1. **Understand.** Read the relevant code, docs and decision records. Read official docs before using an unfamiliar tool. Verify; don't infer.
2. **Define.** State the objective, out-of-scope items and acceptance criteria. Pick the [review level](#review-levels). For L3, add a threat model.
3. **Plan.** Choose the simplest maintainable solution, using native features over custom scripts. A plan that needs review goes in `docs/plans/<task>-<topic>.md` and is deleted after merge, once its lasting decisions move to an ADR.
4. **Implement.** One owner, one branch (`<type>/<short-name>`), bounded scope. No speculative features or unrelated refactoring. Ask before adding dependencies, tooling, architecture changes or scope. After the first working commit, push and open a draft PR (`gh pr create --draft`; base it on the branch it builds on, if not `main`), so work never sits on a pushed branch without a PR.
5. **Check as you go.** Run focused checks as each part becomes testable. Diagnose and fix failures your change caused, then rerun. Report failures you didn't cause with their output; don't fix them without asking.
6. **Self-verify.** Read your diff for secrets, personal data and widened permissions. Run the checks, and try user-facing changes in the running app, because unit tests alone miss broken features. Back every claim with evidence.
7. **Review** at a checkpoint with the [review loop](#review-loop); the lead runs it without being asked. Once a PR is open, the maintainer can type `/steward` (built into Claude Code) so CI failures and review comments are handled without reminders; it never merges.
8. **Merge brief.** When the PR is ready, post on it and in chat: the user-visible result; evidence (CI run, reviewed SHA = head SHA, what was tried in the app); decisions or manual tests that remain; the exact merge command.
9. **Finalize.** Update CURRENT.md to describe `main` after the merge. The maintainer merges.

## Releases

A release is a row in PRODUCT.md (`vX.Y.Z`, its tasks, its exit criteria). When every task in it is merged and its exit criteria are checked on `main`, the maintainer approves, then tags it: `git tag vX.Y.Z <sha>`, `git push origin vX.Y.Z`, `gh release create vX.Y.Z --notes "<PRs>"`. If docs and GitHub disagree about what shipped, tags and merged PRs win.

## Review levels

Classify by risk, not size. Take the highest level present, and go higher when unsure. Record the level and the reason in the PR.

| Level | Typical changes | Required before merge |
|---|---|---|
| **L1** | Docs, styling, low-risk fixes | Checks, CI and cloud Codex |
| **L2** | Features, business logic, API endpoints, refactoring | L1 + tests + `/codex:review --wait --base main` on the final head |
| **L3** | Auth and access control, data isolation, migrations, personal or payment data, sensitive integrations, security or infrastructure, architecture or policy | L2 + threat model, denial-path tests, `/codex:adversarial-review --wait --base main <focus>` instead of the standard review, and residual risks stated in the PR |

Commit and push before a local review, because it only sees committed work. Post the result on the PR, naming the reviewed commit and each finding's triage. Keep secret- or exploit-revealing findings off the PR. A failed run counts as no review. Codex on GitHub (if enabled) reports only P0/P1 findings, so it doesn't replace a local review. Comment `@codex review` to rerun it.

## Review loop

The lead runs this itself; the maintainer never has to ask. The reviewer is always the model that did not build the change: Codex when Claude Code built it, Claude Code (`/code-review`) when Codex built it.

1. **Local review, at each checkpoint of an L2 or L3 change.** Commit and push, then run the review the level needs through the plugin script that `/codex:review` uses (`node <plugin>/scripts/codex-companion.mjs review` or `adversarial-review --wait --base <base> [focus]`). Read and triage every finding, fix the blocking ones, push, and rerun on the new head until no blocking findings remain or the [escalation](#escalation) limit is reached. A blocking finding the builder calls invalid stays open until the reviewer drops it on a rerun or the maintainer agrees on the PR.
2. **Cloud Codex, on every PR, before it is marked ready.** If no `chatgpt-codex-connector` summary names the head SHA, comment `@codex review` and wait up to 30 minutes; if nothing names the head SHA, ask once more and wait another 30. Still nothing: leave the PR in draft and tell the maintainer, who decides on the PR whether to wait or merge without it. Treat its findings like local ones. A fix makes a new head, so step 1 (for L2/L3) and step 2 run again.
3. **Post each round on the PR:** reviewed SHA, verdict, and each finding with its triage.

## Review checkpoints

Review when a coherent unit is done and self-verified, not after every push. Batch fixes. If the head changes (including an update from `main`), the new head needs its reviews again.

## Triaging findings

Decide the stopping rule before the review runs. Put each finding in one category:

| Category | Action |
|---|---|
| **Blocking** (security, data loss, broken behavior, regression, failed criterion) | Fix before merge |
| **Valid, nonblocking** | Fix if proportionate, otherwise defer with a reason |
| **Invalid** | Reject with a reproducible reason |
| **Out of scope** | Record why; escalate if serious |

Act on findings without waiting to be asked. Reply before resolving any thread. Don't reopen an accepted finding without new evidence. If Codex keeps raising the same invalid finding or missing a kind of bug, fix the review guidelines in AGENTS.md.

## Escalation

After **three review rounds** with unresolved findings, stop and hand the decision to the maintainer: what's unresolved, why, the alternatives and the decision needed. Escalate earlier when a fix needs new dependencies, tooling, architecture or scope. This is a threshold for asking, never permission to merge a blocking finding.

## Merging

"Reviewed the final head", "no blocking findings", "thread resolved" and "GitHub allows merge" are four different facts, and none implies another. Merge only when every required review, cloud Codex included, covers the exact final commit, blocking findings are fixed and CI is green:

```sh
gh pr merge <n> --merge --match-head-commit <verified-sha>
```
