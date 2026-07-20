# Manifest Verification Reference

`verify_manifest.py` cross-checks the three sources of truth in a canonical
skills repository so they cannot silently drift apart. It is the integrity
backstop for the whole guardrail: the monitor commits version bumps, the gate
signs loop entries, and this verifier confirms the record, the files, and git
all agree.

## The Three Sources

1. **The manifest** — `.skill-manifest.json`, the packager's record of every
   skill's `current_version` and update history.
2. **The skills on disk** — each skill's `SKILL.md` frontmatter `version:`, and
   the set of skill directories actually present.
3. **Git** — tracks the byte-level hash of every file (as blob SHAs) and the
   monitor's auto-commit history (`<skill> version bumped to v<version>`).

Git is what makes "verify by hash" real: a clean, all-committed working tree whose
versions reconcile with the manifest means the manifest, the files, and the
git-tracked hashes are mutually consistent. Nothing recomputes SHA-256 by hand —
git already stores and checks content hashes; this tool confirms the working tree
is committed so those hashes are current.

## Findings

| Type | Severity | Meaning |
|---|---|---|
| `version_mismatch` | fail (info if locked) | manifest `current_version` ≠ on-disk SKILL.md version |
| `missing_in_manifest` | fail (info if locked) | skill dir on disk, absent from manifest — **a newly-added skill** |
| `missing_on_disk` | fail | manifest names a skill whose directory is gone |
| `uncommitted` | warn | skill has changes not committed to git (tracked hash is stale) |
| `no_version_commit` | warn | no `v<current>` auto-commit found in git history for the skill |
| `locked` | info | skill holds `.loop.lock`; excused from strict checks (mid-authoring) |
| `manifest_missing` / `manifest_corrupt` | fail | the manifest itself is absent or unparseable |
| `not_a_git_repo` | warn | hash tracking unavailable — repo isn't under git |

## Usage

```bash
# Standard report
python3 scripts/verify_manifest.py --repo /path/to/skills-repo

# CI gate: treat warnings (uncommitted, no_version_commit) as failures too
python3 scripts/verify_manifest.py --repo /path/to/skills-repo --strict --json
```

Exit code is 0 only when there are no failures (or, with `--strict`, no failures
or warnings). Wire it as a gate `post_check` or a pre-push hook to guarantee the
canonical repo is always internally consistent before anything leaves it.

## How the Layers Reinforce Each Other

- The **monitor** turns a version bump into a git commit → git now holds the new
  hash and a labelled history entry.
- The **manifest** (written by `skill_enhance`/packager) records that version.
- **verify_manifest** confirms manifest == SKILL.md == a real committed state, and
  flags any skill git doesn't yet track or the manifest doesn't yet know about.
- The **loop lock** excuses skills that are legitimately mid-authoring, so the
  verifier never cries wolf on work in progress.

Together they mean: every finalized version of every curated skill is recorded in
the manifest, materialized on disk, and pinned by an immutable git hash — with a
verifier that proves all three still line up.
