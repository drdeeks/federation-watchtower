# Testing Framework Reference

The validation skill treats testing as a set of **phase-gated tiers**. A tier
passes only when every suite inside it exits 0; a phase may not advance until its
gate tier passes. `scripts/test-runner.py` is the orchestrator that enforces
this.

## Tiers

| Tier | Directory | Purpose | Gate |
|---|---|---|---|
| `unit` | `tests/unit/` | Function-level validation of individual modules | ≥ 80% coverage of touched code |
| `integration` | `tests/integration/` | Cross-module contracts (gateway ↔ runtime ↔ skills) | 100% of critical paths |
| `e2e` | `tests/e2e/` | End-to-end user workflows (agent import → workspace → run) | 100% of critical user flows |
| `playwright` | `tests/playwright/` | Browser-driven dashboard scenarios | 100% of critical UI flows |

Discovery is convention-based: any `test_*.py`, `*_test.py`, `test_*.sh`, or
`*_test.sh` file inside a tier directory is a suite. Missing tiers are **skipped**
in `all` mode and **failed** when that single tier is requested by name.

## Runner Resolution

`test-runner.py` is runner-agnostic and installs nothing:

1. `.py` suites → `pytest -q` when `pytest` is on `PATH`, else
   `python -m unittest`.
2. `.sh` suites → `bash` (or `sh`) executing the file.
3. Everything runs with the **project root** as the working directory, resolved
   from `--root` or the current directory — never a hardcoded path.

## Invocation

```bash
# Whole matrix (absent tiers are skipped, not failed)
python3 scripts/test-runner.py all --json

# One gate tier — absence is a failure
python3 scripts/test-runner.py unit

# Preview the plan without executing anything
python3 scripts/test-runner.py all --dry-run

# Point at a project elsewhere on disk
python3 scripts/test-runner.py integration --root ./output/my-project
```

Exit code is `0` only when every requested tier passed (or on `--dry-run`);
otherwise `1`. CI gates should key off the exit code and, for detail, the
`status` field of the `--json` report.

## Safety Framework Integration

Implementation scripts under test should source a shared safety framework
(`safety-test-framework.sh` in the target project) providing:

- Confirmation prompts before destructive actions.
- Dry-run mode (`--dry-run` / `-n`) toggled from menus.
- Error recovery paths: retry, modify, skip, rollback, diagnostics.
- An automatic rollback stack unwound on failure.

The orchestrator honours `--dry-run` end-to-end so a full test matrix can be
rehearsed safely before any suite mutates state.
