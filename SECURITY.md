# Security

## Never commit

- Credentials: passwords, API keys, tokens, private keys.
- Any `.env*` file except `.env.example` (placeholders only).
- Real people's data or private screenshots. Use fictional data.

Personal agent settings and memory stay in `~/.claude/` and `~/.codex/`. `.claude/settings.json` is tracked on purpose (the session-start hook).

## Scanning

CI's `secrets` job runs gitleaks over full history and current files on every PR. To check locally: `gitleaks git --redact -v`.

## If a credential leaks

1. **Rotate or revoke it first.** Deleting it from the code doesn't make it safe.
2. Agents stop and tell the maintainer, and never rewrite history on their own.
3. Remove it with a neutral commit message, without the value. CI keeps failing while the leaking commit is reachable: rebuild an unmerged branch without that commit, or, if it's on `main`, rewrite history or add a gitleaks exception for that one fingerprint (an L3 change).

Never describe a leak or vulnerability in a PR, issue or commit.
