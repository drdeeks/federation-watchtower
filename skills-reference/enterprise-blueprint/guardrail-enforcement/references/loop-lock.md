# Loop Lock Reference

`lock.py` manages an **advisory** `.loop.lock` marker — the CL-040 mechanism that
keeps a skill's half-authored state from being auto-committed or packaged while
someone (or an orchestrator) is still working on it.

## What It Is

A `.loop.lock` at a directory's root is a JSON marker (`pid`, `token`, `host`,
`acquired_at`, `note`). Cooperating tools check for it and **skip** locked
directories:

- **`monitor.py`** — skips a locked skill: no baseline record, no version-bump
  auto-commit until the lock is released.
- **`verify_manifest.py`** — reports a locked skill as `info` and excuses its
  uncommitted / version-mismatch state (it's expected mid-authoring).
- Any packager/validator in the toolchain can call `lock.py check <dir>` (exit 0
  = locked) and decline to run.

## Why Advisory (and not `flock`/`chattr +i`)

There are three kinds of lock, and they're often confused:

| Mechanism | Enforces against | Cost |
|---|---|---|
| **Advisory file** (`.loop.lock`) | only tools that choose to check | none — portable, no sudo |
| **Kernel lock** (`flock`/`fcntl`) | only processes that also call the syscall | stuck locks on crash |
| **Immutable/permission** (`chmod 000`, `chattr +i`) | everything, at the FS layer | needs root to lock/unlock; guards the file, not the workflow |

A cooperating toolchain wants the advisory file: zero privilege, fully portable,
and it constrains exactly the tools that matter. The gaps an advisory lock leaves
(a raw `git commit`, an editor write) are closed by the **other** guardrail
layers — the git pre-commit hook (`install_hooks.py`) and the signed loop log
(`gate.py` + `verify_log.py`) — so the stack as a whole still catches bypasses.

## Usage

```bash
# Claim a skill while authoring (optional token gates the release)
python3 scripts/lock.py acquire /path/to/skills/my-skill --token "$SESSION" --note "reworking scripts"

# Cooperating tools now skip it
python3 scripts/monitor.py scan --config /path/to/skills/.monitor.json   # my-skill skipped

# Check / list
python3 scripts/lock.py check /path/to/skills/my-skill        # exit 0 if locked
python3 scripts/lock.py list  /path/to/skills --json          # every lock under a root

# Release when done (token must match unless --force)
python3 scripts/lock.py release /path/to/skills/my-skill --token "$SESSION"
```

## Lifecycle with the Watcher

1. `acquire` the skill's lock → begin editing.
2. Bump `SKILL.md` version, run `skill_enhance` to (re)validate and package.
3. `release` the lock.
4. Next `monitor.py scan` sees the new version on an unlocked skill → auto-commits
   `<skill> version bumped to v<version>`.

Because the lock file is transient it is git-ignored; it should never be
committed. It exists only for the duration of active authoring.
