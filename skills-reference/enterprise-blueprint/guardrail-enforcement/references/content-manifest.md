# Content Manifest — Guardrail Enforcement

Plain-language index of this skill's contents, and where the CL-040 design
snapshots now live.

## Active tooling

Watcher + lock + integrity:
- **`../scripts/monitor.py`** — the watcher: condition (skill version / file
  mtime) → action (git commit / shell command / none). Dynamic skill discovery,
  lock-aware. Reads `.monitor.json`, tracks `.monitor-state.json`.
- **`../scripts/lock.py`** — advisory `.loop.lock` manager (acquire/release/
  check/list).
- **`../scripts/verify_manifest.py`** — cross-verifies `.skill-manifest.json` ↔
  on-disk SKILL.md versions ↔ git hashes for a canonical skills repo.

Gate + audit:
- **`../scripts/gate.py`** — the gate engine: pre-checks → loop → post-checks →
  HMAC-signed, hash-chained log entry. Reads `.gate.json`.
- **`../scripts/setup.py`** — writes `.gate.json` and generates the `0600` HMAC
  secret (interactive or fully flag-driven).
- **`../scripts/verify_log.py`** — verifies the loop log's signatures and chain;
  `--recent` mode answers the git-hook freshness question.
- **`../scripts/install_hooks.py`** — installs/removes the git hooks that bind
  commits to a valid recent log entry; backs up any existing hooks.
- **`../scripts/menu.sh`** — interactive composable front-end for all of the above.
- **`../scripts/pre-commit-hook.sh`** — a stricter, skills-specific example hook
  (runs `validate.py --basic` per staged skill dir). Template only.

## References

- **`monitor-watcher.md`** — the watcher: conditions, actions, dynamic skill
  discovery, version-bump auto-commits, lock awareness, interactive menu.
- **`loop-lock.md`** — the advisory `.loop.lock` mechanism and authoring lifecycle.
- **`manifest-verification.md`** — manifest ↔ skills ↔ git cross-verification.
- **`proposed-design.md`** — the full three-skill architecture (monitor, gate,
  pure skill-creator) this skill was factored out of. Read for rationale and the
  parked design questions.
- **`gate-config.md`** — the `.gate.json` schema with worked skills / k8s /
  pipeline configs.
- **`hmac-audit.md`** — how the signed, chained log is built and verified.
- **`git-hooks.md`** — what the hooks enforce, installation, and bypass.
- **`monitor-crosscheck.md`** — pairing the watcher and the gate.

## CL-040 reference snapshots (archived out of the active skill)

The binary snapshots that this directory used to carry — the pre-enforcement and
current `skill-creator` trees and the `autowatch` implementation — were moved out
of the active skill (binaries do not belong in a `.skill` archive) into the
canonical Hemlock archive:

    ~/projects/hemlock/archives/guardrail-cl040-snapshots/
      ├─ skill-creator-pre-enforcement.tar.gz          (~140 KB)
      ├─ skill-creator-current-with-enforcement.tar.gz (~172 KB)
      ├─ autowatch-current.tar.gz                      (~28 KB)
      └─ autowatch-config.json                         (~500 B)

They are preserved, not deleted. To pick up the CL-040 thread:

1. Read `proposed-design.md` end to end.
2. Extract `skill-creator-pre-enforcement.tar.gz` — the target shape for the
   pure-tools skill-creator.
3. Diff it against `skill-creator-current-with-enforcement.tar.gz` to see exactly
   which enforcement code moved here into `gate.py` / `install_hooks.py`.
4. Extract `autowatch-current.tar.gz` as the starting point for a future
   `monitor` skill; `autowatch-config.json` shows the config-driven pattern that
   `.gate.json` now follows.

## Status vs. the original design

Delivered here: the **gate** (`gate.py`), interactive **setup**, **hook
installation** (generalized from the old `pre-commit-hook.sh`), and the **signed
audit log** with chain verification. Still future work per the design: the
standalone **monitor** skill and backing the CL-040 enforcement out of
`skill-creator` into the pure-tools variant.
