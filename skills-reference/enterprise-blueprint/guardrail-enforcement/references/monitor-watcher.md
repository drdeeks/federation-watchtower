# Monitor (Watcher) Reference

`monitor.py` is the **watcher** half of the guardrail: a directory-agnostic
*condition → action* trigger. It is independent of the gate (`gate.py`) but
composes with it — run it alone to auto-commit on version bumps, or point its
action at `gate.py` to chain a full enforced loop.

## Headline Use Case — Skill Version Tracking

Watch a canonical skills repository. When any skill's `SKILL.md` `version:` field
changes, derive the skill name from **its own directory** (the parent/owner of
that SKILL.md) and auto-commit:

```
<skill_name> version bumped to v<X.Y.Z>
```

This gives every skill a clean, uniform commit per version — consistent tracking
and precise rollback points.

```bash
# One-time: configure the watch and record a baseline
python3 scripts/monitor.py setup /path/to/skills-repo \
  --condition skill_version --action git_commit --yes
python3 scripts/monitor.py scan --config /path/to/skills-repo/.monitor.json   # baseline

# Later, after a version bump (e.g. via skill_enhance): detect + auto-commit
python3 scripts/monitor.py scan --config /path/to/skills-repo/.monitor.json
```

## Dynamic Skill Discovery

The `skill_version` condition **re-scans the immediate subdirectories on every
pass**. There is no fixed list of skills: add a new skill directory to the repo
and the very next scan discovers it, records its baseline version, and tracks it
from then on. This is what makes the repo a living canonical authority for *all*
curated skills, not just an initial set.

`verify_manifest.py` surfaces the same event from the integrity side: a new skill
on disk that the manifest hasn't recorded shows up as `missing_in_manifest`.

## Conditions

| Type | Watches | Trip data |
|---|---|---|
| `skill_version` | `<subdir>/SKILL.md` frontmatter `version:` for each immediate subdir | `skill_name`, `version`, `previous_version`, `skill_dir` |
| `file_mtime` | mtime of files matching a glob | `path`, `skill_name` (parent dir) |

Change is measured against `.monitor-state.json`, so "changed" means "changed
since the last scan". First sighting records a baseline and does **not** fire.

## Actions

| Type | Effect | Template variables |
|---|---|---|
| `git_commit` | `git add <scope>` + `git commit -m <rendered template>` in the enclosing repo | `{skill_name}` `{version}` `{previous_version}` `{subdir}` `{path}` `{skill_dir}` |
| `shell_command` | Run an arbitrary command (same substitutions) | as above |
| `none` | Observe/report only — watcher runs with no side effect | — |

`git_commit` default template is `{skill_name} version bumped to v{version}` and
default `scope` is `skill_dir` (commit only that skill's directory, for granular
rollback). Point `shell_command` at `gate.py` to make a version bump run the full
pre-check → loop → post-check → signed-log gate.

## Lock Awareness

Before recording or firing on a skill, the watcher checks for a `.loop.lock` at
that skill's root. A locked skill (mid-authoring) is **skipped entirely** — its
in-progress version is never recorded and never committed. The bump is detected
on the first scan after the lock is released. See [loop-lock.md](loop-lock.md).

## Interactive Menu

`scripts/menu.sh` is a composable front-end: option 1 walks you through picking a
directory, what to watch, and what to trigger (writing `.monitor.json`); other
options run the watcher, configure/run the gate, install hooks, manage locks, and
run the verifiers. `monitor.py setup` is itself interactive when run on a TTY, or
fully flag-driven for automation.

## Modes

```bash
python3 scripts/monitor.py setup <dir> [--condition ...] [--action ...] [--yes]
python3 scripts/monitor.py scan  [--config PATH] [--dry-run] [--json]
python3 scripts/monitor.py status [--config PATH]
```
