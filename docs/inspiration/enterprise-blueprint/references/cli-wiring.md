# CLI Wiring Reference

A validated blueprint is only useful if every phase it defines is reachable from
the project's command surface. This reference covers how blueprint phases map to
CLI commands and how to verify that mapping stays complete — the "unwired CLI
entries" pitfall from SKILL.md.

## The Contract

For each implementation script a phase introduces, there must be a corresponding
command entry in the project's dispatcher (an `entrypoint.sh`, a `hemlock`
launcher, or equivalent). The blueprint's Module Registry is the source of truth;
the dispatcher is the enforcement point.

| Blueprint artifact | Dispatcher obligation |
|---|---|
| `MOD-NNN` with a script | A named subcommand that invokes that script |
| `FEAT_*` feature flag | A guard that no-ops the command when the flag is off |
| Phase validation gate | A `test-*` subcommand that runs the gate tier |

## Verifying Wiring

There is no hidden state — verification is a text diff between what the blueprint
promises and what the dispatcher exposes:

```bash
# 1. Every script referenced by a phase actually exists
grep -oE '\b[a-z_-]+\.(py|sh)\b' blueprint.md | sort -u

# 2. Every command the dispatcher advertises resolves to a real file
grep -oE '^\s+[a-z-]+\)' entrypoint.sh | tr -d ' )' | sort -u

# 3. Syntax-check every shell entry before trusting the dispatcher
find . -name '*.sh' -print0 | xargs -0 -n1 bash -n
```

The two sorted lists should reconcile: no blueprint script without a command, no
command without a backing script. A mismatch is a wiring defect, not a warning.

## Standard Command Families

Projects following this skill expose at least these families; the test family is
provided directly by `scripts/test-runner.py`:

```
hemlock test-unit          # -> test-runner.py unit
hemlock test-integration   # -> test-runner.py integration
hemlock test-e2e           # -> test-runner.py e2e
hemlock test-playwright    # -> test-runner.py playwright
hemlock test-all           # -> test-runner.py all
```

## Portability Requirement

Dispatcher entries must resolve script paths relative to the dispatcher's own
location (e.g. `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"`), never via a
hardcoded absolute path. This keeps the command surface working regardless of
where the project is checked out or which USB/mount it runs from — the same
path-agnostic rule the validator enforces on the skill's own scripts.
