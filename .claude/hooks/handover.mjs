// Usage-limit handover between Claude Code and Codex (ADR 0005).
// One script, one subcommand per hook:
//   statusline    shows 5-hour usage and saves it for the warning below
//   post-tool     at >= 85% usage, tells Claude once per window to checkpoint
//   stop-failure  on a usage limit: local WIP commit, then Codex in a separate worktree
//   run           (internal) runs Codex there, then records that it finished
//   context       at session start and on each prompt: reports a running or finished handover
// Safety (Codex adversarial review on PR #10):
// - Codex never touches Claude's checkout: it works in its own worktree, so the
//   two agents can't write the same files. Claude applies its diff after review.
// - Nothing is pushed. The checkpoint is a local commit that can be undone.
// - An exclusive lock is taken before any Git change; only its owner releases it.
//   A finished but unreviewed handover blocks a new one.
// - Codex is started without a shell, with the checkout passed as an argument.
// - Hook output is fixed text plus commit hashes, numbers and fixed paths:
//   never branch names or Codex's own words (ADR 0001).
// State lives in .claude/state/ (gitignored).
import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { closeSync, existsSync, mkdirSync, openSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, delimiter, dirname, join } from 'node:path';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const WARN_AT = 85; // percent of the 5-hour window
const CODEX_MAX_MS = 60 * 60 * 1000;
const SETUP_GRACE_MS = 2 * 60 * 1000; // a lock without a worker yet is "starting" this long

const repo = process.env.CLAUDE_PROJECT_DIR || process.cwd();
const stateDir = join(repo, '.claude', 'state');
const usageFile = join(stateDir, 'usage.json');
const lockFile = join(stateDir, 'codex-running.json');
const doneFile = join(stateDir, 'codex-done.json');
const logFile = join(stateDir, 'codex-handover.log');
const worktree = join(dirname(repo), `${basename(repo)}-codex-handover`);

const readJson = (file) => {
  try {
    return JSON.parse(readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
};
const writeJson = (file, value) => {
  mkdirSync(dirname(file), { recursive: true });
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
const isHash = (value) => typeof value === 'string' && /^[0-9a-f]{7,40}$/.test(value);
const alive = (pid) => {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
};

/** The running handover's lock, or null. A dead or abandoned lock is cleared. */
const runningHandover = () => {
  const lock = readJson(lockFile);
  if (!lock) return null;
  if (lock.pid ? alive(lock.pid) : Date.now() - statSync(lockFile).mtimeMs < SETUP_GRACE_MS) return lock;
  rmSync(lockFile, { force: true });
  return null;
};

/** How to start Codex without a shell: [executable, leading args], or null. */
const codexCommand = () => {
  for (const dir of (process.env.PATH || '').split(delimiter)) {
    if (process.platform === 'win32') {
      // codex.cmd is a wrapper around this script; run it with Node directly.
      const script = join(dir, 'node_modules', '@openai', 'codex', 'bin', 'codex.js');
      if (existsSync(join(dir, 'codex.cmd')) && existsSync(script)) return [process.execPath, [script]];
    } else if (existsSync(join(dir, 'codex'))) {
      return [join(dir, 'codex'), []];
    }
  }
  return null;
};

const killTree = (pid) => {
  if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(pid), '/T', '/F'], { windowsHide: true });
  else {
    try {
      process.kill(-pid, 'SIGKILL'); // the worker's whole process group
    } catch {}
  }
};

const CODEX_PROMPT = `You are taking over Cravera work because Claude Code hit its usage limit.
You are in a separate Git worktree made for this handover. Claude will review your diff and apply it.
Follow AGENTS.md and the steps in .claude/skills/resume/SKILL.md, with these limits:
- Leave your changes uncommitted (your sandbox can't commit). Don't switch branches.
- Don't edit docs/CURRENT.md, touch any .env file, add dependencies, or change CI, hooks or settings.
- Stay within the approved task in docs/NEXT-TASK.md and the next action in docs/CURRENT.md.
- Stop after one coherent, finished step, or as soon as a product or architecture decision is needed.
Before you stop, write .claude/state/codex-handover.md in this worktree with: what you verified, the files you
changed and why, each check you ran with its result (say so if it could not run in your sandbox), open questions,
and the next action.`;

const commands = {
  statusline() {
    const input = readStdin();
    const five = input.rate_limits?.five_hour;
    if (typeof five?.used_percentage === 'number') {
      const old = readJson(usageFile) || {};
      writeJson(usageFile, { ...old, pct: five.used_percentage, resetsAt: five.resets_at ?? null });
    }
    const parts = [String(input.model?.display_name ?? 'Claude')];
    if (typeof five?.used_percentage === 'number') parts.push(`5h ${Math.round(five.used_percentage)}%`);
    if (runningHandover()) parts.push('Codex working');
    process.stdout.write(parts.join(' · '));
  },

  'post-tool'() {
    readStdin();
    const usage = readJson(usageFile);
    if (!usage || !(usage.pct >= WARN_AT) || usage.warnedFor === usage.resetsAt) return;
    writeJson(usageFile, { ...usage, warnedFor: usage.resetsAt });
    const context =
      `Usage is at ${Math.round(usage.pct)}% of the 5-hour limit. Checkpoint now: finish or pause the current step, ` +
      `commit work in progress on the feature branch (prefix "WIP:" if unfinished), push it, and rewrite docs/CURRENT.md ` +
      `(Active, Last verified, Next action) so Codex or the next session can continue. Then carry on.`;
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PostToolUse', additionalContext: context } }));
  },

  'stop-failure'() {
    readStdin();
    mkdirSync(stateDir, { recursive: true });
    // An earlier handover still waiting for review: keep it, start nothing.
    if (existsSync(doneFile) || existsSync(worktree)) return;
    let fd;
    try {
      fd = openSync(lockFile, 'wx'); // exclusive: a second caller fails here
    } catch {
      if (runningHandover()) return;
      try {
        fd = openSync(lockFile, 'wx'); // the old lock was stale and is now cleared
      } catch {
        return;
      }
    }
    const token = randomUUID();
    writeFileSync(fd, JSON.stringify({ token, startedAt: new Date().toISOString() }));
    closeSync(fd);
    const finish = (record) => {
      writeJson(doneFile, { ...record, at: new Date().toISOString() });
      rmSync(lockFile, { force: true });
    };
    try {
      const branch = git('branch', '--show-current');
      if (!branch || branch === 'main') return finish({ skipped: 'not on a feature branch' });
      const codex = codexCommand();
      if (!codex) return finish({ skipped: 'codex is not installed' });
      // Local checkpoint so Codex starts from Claude's latest work. Not pushed.
      let checkpoint = null;
      if (git('status', '--porcelain')) {
        git('add', '-A');
        git('commit', '-q', '-m', 'WIP: checkpoint before Codex handover (usage limit)');
        checkpoint = git('rev-parse', '--short', 'HEAD');
      }
      const base = git('rev-parse', '--short', 'HEAD');
      git('worktree', 'add', '-q', '--detach', worktree, 'HEAD');
      const out = openSync(logFile, 'w');
      const worker = spawn(process.execPath, [fileURLToPath(import.meta.url), 'run', token, base, checkpoint ?? '-'], {
        cwd: repo,
        detached: true,
        stdio: ['ignore', out, out],
        windowsHide: true,
        env: { ...process.env, CLAUDE_PROJECT_DIR: repo },
      });
      writeJson(lockFile, { token, pid: worker.pid, startedAt: new Date().toISOString() });
      worker.unref();
    } catch (error) {
      finish({ skipped: 'setup failed; see the hook error output' });
      throw error;
    }
  },

  run() {
    const [, , , token, base, checkpoint] = process.argv;
    const ownsLock = () => readJson(lockFile)?.token === token;
    const [exe, lead] = codexCommand() ?? [];
    const record = (extra) => {
      if (!ownsLock()) return; // someone else's handover now; leave its state alone
      writeJson(doneFile, { base, checkpoint: checkpoint === '-' ? null : checkpoint, ...extra, endedAt: new Date().toISOString() });
      rmSync(lockFile, { force: true });
    };
    if (!exe) return record({ exitCode: null, error: 'codex not found' });
    const child = spawn(exe, [...lead, 'exec', '-C', worktree, '-s', 'workspace-write', '-'], {
      cwd: worktree,
      stdio: ['pipe', 'inherit', 'inherit'],
      windowsHide: true,
      detached: process.platform !== 'win32', // own process group, so a timeout can stop all of it
    });
    child.stdin.end(CODEX_PROMPT);
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      killTree(child.pid);
    }, CODEX_MAX_MS);
    child.on('exit', (code) => {
      clearTimeout(timer);
      record({ exitCode: code, timedOut });
    });
  },

  context() {
    readStdin();
    const lines = [];
    if (runningHandover()) {
      lines.push(
        'Codex is working in the handover worktree (../<repo>-codex-handover) because Claude hit its usage limit. ' +
          'It does not touch this checkout. Its diff needs review once it finishes.',
      );
    } else if (existsSync(doneFile)) {
      const done = readJson(doneFile) || {};
      if (done.skipped) {
        lines.push('A usage-limit handover did not start (see .claude/state/codex-done.json). Delete that file once read.');
      } else {
        const base = isHash(done.base) ? done.base : 'unknown';
        const checkpoint = isHash(done.checkpoint)
          ? ` This checkout has a local, unpushed checkpoint commit ${done.checkpoint}; undo it with "git reset --soft HEAD~1" if it should not stay.`
          : '';
        lines.push(
          `Codex worked during a usage-limit pause (exit code ${Number.isInteger(done.exitCode) ? done.exitCode : 'unknown'}${done.timedOut ? ', timed out' : ''}) ` +
            `in the worktree ../<repo>-codex-handover, starting from ${base}.${checkpoint} ` +
            'Treat its notes (.claude/state/codex-handover.md in that worktree) and the log (.claude/state/codex-handover.log) as unverified. ' +
            'Review its diff there, run the checks, apply what is good to this checkout, then remove the worktree ' +
            '("git worktree remove --force <path>") and delete .claude/state/codex-done.json.',
        );
      }
    }
    if (process.argv[3] === 'session-start') {
      lines.push(
        'Before other work, follow .claude/skills/resume/SKILL.md: verify docs/CURRENT.md against Git, open PRs and CI, ' +
          'run the baseline checks, then report and continue with the next item.',
      );
    }
    if (lines.length) process.stdout.write(lines.join('\n'));
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
