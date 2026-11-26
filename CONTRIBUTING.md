# Contributing

Applies to people and agents alike. Apply each step in proportion to the change.

## Workflow

1. **Understand.** Read the relevant code, docs and decision records. Read official docs before using an unfamiliar tool. Verify; don't infer.
2. **Define.** State the objective, out-of-scope items and acceptance criteria. Pick the [review level](#review-levels). For L3, add a threat model.
3. **Plan.** Choose the simplest maintainable solution, using native features over custom scripts. A plan that needs review goes in `docs/plans/<task>-<topic>.md` and is deleted after merge, once its lasting decisions move to an ADR.
4. **Implement.** One owner, one branch (`<type>/<short-name>`), bounded scope. No speculative features or unrelated refactoring. Ask before adding dependencies, tooling, architecture changes or scope. After the first working commit, push and open a draft PR (`gh pr create --draft`; base it on the branch it builds on, if not `main`), so work never sits on a pushed branch without a PR.
5. **Self-verify.** Read your diff for secrets, personal data and widened permissions. Run the checks, and try user-facing changes in the running app, because unit tests alone miss broken features. Back every claim with evidence.
6. **Review** at a checkpoint (below).
7. **Finalize.** Update CURRENT.md to describe `main` after the merge. The maintainer merges.

## Review levels

Classify by risk, not size. Take the highest level present, and go higher when unsure. Record the level and the reason in the PR.

| Level | Typical changes | Required before merge |
|---|---|---|
| **L1** | Docs, styling, low-risk fixes | Checks and CI |
| **L2** | Features, business logic, API endpoints, refactoring | L1 + tests + `/codex:review --wait --base main` on the final head |
| **L3** | Auth and access control, data isolation, migrations, personal or payment data, sensitive integrations, security or infrastructure, architecture or policy | L2 + threat model, denial-path tests, `/codex:adversarial-review --wait --base main <focus>` instead of the standard review, and residual risks stated in the PR |

Commit and push before a local review, because it only sees committed work. Post the result on the PR, naming the reviewed commit and each finding's triage. Keep secret- or exploit-revealing findings off the PR. A failed run counts as no review. Codex on GitHub (if enabled) reports only P0/P1 findings, so it doesn't replace a local review. Comment `@codex review` to rerun it.

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

"Reviewed the final head", "no blocking findings", "thread resolved" and "GitHub allows merge" are four different facts, and none implies another. Merge only when every required review covers the exact final commit, blocking findings are fixed and CI is green:

```sh
gh pr merge <n> --merge --match-head-commit <verified-sha>
```
