// Usage-limit handover between Claude Code and Codex (ADR 0005).
// One script, one subcommand per hook, so the logic lives in one place:
//   statusline    shows 5-hour usage and saves it for the warning below
//   post-tool     at >= 85% usage, tells Claude once per window to checkpoint
//   stop-failure  on a usage limit: commits and pushes work in progress, then starts Codex
//   run           (internal) runs Codex, then marks the handover done
//   context       at session start and on each prompt: says if Codex is running or left work to review
//   pre-edit      blocks Claude's file edits while Codex is still running
// State lives in .claude/state/ (gitignored). Hook output is static text plus
// numbers and paths, never Codex's own words (see ADR 0001 on hook output).
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, openSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const WARN_AT = 85; // percent of the 5-hour window
const CODEX_MAX_MS = 60 * 60 * 1000;

const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const stateDir = join(repo, '.claude', 'state');
const usageFile = join(stateDir, 'usage.json');
const lockFile = join(stateDir, 'codex-running.json');
const doneFile = join(stateDir, 'codex-done.json');
const notesFile = join(stateDir, 'codex-handover.md');
const logFile = join(stateDir, 'codex-handover.log');

const readJson = (file) => {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
};
const writeJson = (file, value) => {
  mkdirSync(stateDir, { recursive: true });
  writeFileSync(file, JSON.stringify(value, null, 2));
};
const readStdin = () => {
  try {
    return JSON.parse(readFileSync(0, 'utf8') || '{}');
  } catch {
    return {};
  }
};
const git = (...args) =>
  execFileSync('git', ['-C', repo, ...args], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};
/** The running handover, or null. A lock whose process died is cleared. */
const runningHandover = () => {
  const lock = readJson(lockFile);
  if (!lock) return null;
  if (alive(lock.pid)) return lock;
  rmSync(lockFile, { force: true });
  return null;
};

const CODEX_PROMPT = `You are taking over Cravera work because Claude Code hit its usage limit.
Follow AGENTS.md and the steps in .claude/skills/resume/SKILL.md, with these limits:
- Your sandbox cannot commit or push. Leave your changes uncommitted; Claude reviews and commits them.
- Do not switch branches, edit docs/CURRENT.md, touch any .env file, add dependencies, or change CI, hooks or settings.
- Stay within the approved task in docs/NEXT-TASK.md and the next action in docs/CURRENT.md.
- Stop after one coherent, finished step, or as soon as a product or architecture decision is needed.
Before you stop, write .claude/state/codex-handover.md with: what you verified, the files you changed and why,
each check you ran with its result (say so if a check could not run in your sandbox), open questions, and the next action.`;

const commands = {
  statusline() {
    const input = readStdin();
    const five = input.rate_limits?.five_hour;
    if (five?.used_percentage != null) {
      const old = readJson(usageFile) || {};
      writeJson(usageFile, { ...old, pct: five.used_percentage, resetsAt: five.resets_at ?? null });
    }
    const parts = [input.model?.display_name ?? 'Claude'];
    if (five?.used_percentage != null) parts.push(`5h ${Math.round(five.used_percentage)}%`);
    if (runningHandover()) parts.push('Codex working');
    process.stdout.write(parts.join(' · '));
  },

  'post-tool'() {
    readStdin();
    const usage = readJson(usageFile);
    if (!usage || usage.pct < WARN_AT || usage.warnedFor === usage.resetsAt) return;
    writeJson(usageFile, { ...usage, warnedFor: usage.resetsAt });
    const context =
      `Usage is at ${Math.round(usage.pct)}% of the 5-hour limit. Checkpoint now: finish or pause the current step, ` +
      `commit work in progress on the feature branch (prefix "WIP:" if unfinished), push it, and rewrite docs/CURRENT.md ` +
      `(Active, Last verified, Next action) so Codex or the next session can continue. Then carry on.`;
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: context } }));
  },

  'stop-failure'() {
    readStdin();
    if (runningHandover()) return;
    const branch = git('branch', '--show-current');
    if (!branch || branch === 'main') {
      writeJson(doneFile, { skipped: `not on a feature branch (${branch || 'detached'})`, at: new Date().toISOString() });
      return;
    }
    // Keep Claude's unfinished work as its own commit, so Codex's changes are a separate diff.
    if (git('status', '--porcelain')) {
      git('add', '-A');
      git('commit', '-q', '-m', 'WIP: checkpoint before Codex handover (usage limit)');
    }
    try {
      git('push', '-q');
    } catch {
      // No upstream or offline: the commit is still safe locally.
    }
    const base = git('rev-parse', '--short', 'HEAD');
    mkdirSync(stateDir, { recursive: true });
    rmSync(doneFile, { force: true });
    rmSync(notesFile, { force: true });
    const out = openSync(logFile, 'w');
    const child = spawn(process.execPath, [fileURLToPath(import.meta.url), 'run'], {
      cwd: repo,
      detached: true,
      stdio: ['ignore', out, out],
      windowsHide: true,
      env: { ...process.env, CLAUDE_PROJECT_DIR: repo },
    });
    writeJson(lockFile, { pid: child.pid, branch, base, startedAt: new Date().toISOString() });
    child.unref();
  },

  run() {
    const lock = readJson(lockFile) || {};
    const result = spawnSync('codex', ['exec', '-C', `"${repo}"`, '-s', 'workspace-write', '-'], {
      input: CODEX_PROMPT,
      stdio: ['pipe', 'inherit', 'inherit'],
      shell: true, // codex is a .cmd shim on Windows
      timeout: CODEX_MAX_MS,
      windowsHide: true,
    });
    writeJson(doneFile, { ...lock, exitCode: result.status, timedOut: result.error?.code === 'ETIMEDOUT', endedAt: new Date().toISOString() });
    rmSync(lockFile, { force: true });
  },

  context() {
    readStdin();
    const lines = [];
    const running = runningHandover();
    if (running) {
      lines.push(
        `Codex is working on this repo (branch ${running.branch}, since ${running.startedAt}) because Claude hit its usage limit. ` +
          `Do not edit files until it finishes; file edits are blocked meanwhile. Check again on the next prompt.`,
      );
    } else if (existsSync(doneFile)) {
      const done = readJson(doneFile) || {};
      lines.push(
        done.skipped
          ? `A usage-limit handover was skipped: ${done.skipped}. Nothing ran.`
          : `Codex worked while Claude was at its usage limit (exit ${done.exitCode}${done.timedOut ? ', timed out' : ''}). ` +
              `Its changes are uncommitted on top of ${done.base} on ${done.branch}; its notes are in .claude/state/codex-handover.md ` +
              `and its log in .claude/state/codex-handover.log. Treat both as unverified: review the diff, run the checks, ` +
              `then commit or revert, update docs/CURRENT.md, and delete .claude/state/codex-done.json.`,
      );
    }
    if (process.argv[3] === 'session-start') {
      lines.push(
        'Before other work, follow .claude/skills/resume/SKILL.md: verify docs/CURRENT.md against Git, open PRs and CI, ' +
          'run the baseline checks, then report and continue with the next item.',
      );
    }
    if (lines.length) process.stdout.write(lines.join('\n'));
  },

  'pre-edit'() {
    readStdin();
    const running = runningHandover();
    if (!running) return;
    process.stdout.write(
      JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PreToolUse',
          permissionDecision: 'deny',
          permissionDecisionReason: `Codex is still working on ${running.branch} (usage-limit handover). Wait for it to finish, then review its changes first.`,
        },
      }),
    );
  },
};

const command = commands[process.argv[2]];
if (command) {
  try {
    command();
  } catch (error) {
    process.stderr.write(`handover ${process.argv[2]}: ${error.message}\n`);
  }
}
