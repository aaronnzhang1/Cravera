## Summary

<!-- What changes and why. -->

**Task:** <!-- e.g. TASK-001 item 2 -->

## Scope and acceptance criteria

<!-- What is in scope, what is explicitly out, and how we know it works. -->

## Review level

<!-- L1, L2 or L3 (CONTRIBUTING.md#review-levels), with the reason. Take the highest level present; when unsure, go higher. -->

## Risk

<!-- What could break. This is the focus of the review. For L3 or security-sensitive work, add the threat model here. -->

## Checks run

<!-- Exact commands and results. -->

## Residual risks and deferred findings

<!-- Required for L3. Known limits, nonblocking findings deferred and why. -->

## Before merge

- [ ] Reviews required by the level, each a **completed** result for the final head SHA (local review comment for L2 and L3). Queued, running, failed or stale reviews don't count
- [ ] Every finding triaged and replied to
- [ ] CI green on the final head
- [ ] CURRENT.md describes `main` after this merges
- [ ] Merge command with the verified SHA: `gh pr merge <n> --merge --match-head-commit <sha>`
