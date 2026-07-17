---
name: guardrail-enforcement
description: "A composable guardrail toolchain: a WATCHER (monitor.py) that fires an action when a condition trips — e.g. auto-committing a 'skill version bumped to vX.Y.Z' message when a skill's SKILL.md version changes, discovering newly-added skills dynamically — and a GATE (gate.py) that enforces pre-checks then loop then post-checks and appends an HMAC-signed, hash-chained audit log. Plus an advisory .loop.lock so mid-authoring skills are skipped, git hooks that reject commits without a valid entry, and a manifest verifier that cross-checks the manifest against SKILL.md versions and git hashes. Watcher and gate are independent but compose. Config-driven and domain-agnostic; free-first $0 Python stdlib, path-agnostic, no external services. Triggers on 'guardrail', 'watch skill versions', 'auto commit on version bump', 'gate a workflow', 'enforce a loop', 'loop lock', 'signed audit log', 'pre-commit enforcement', 'loop enforcer'."
license: MIT
metadata:
  tags:
    - guardrail
    - enforcement
    - workflow-gate
    - audit-log
    - hmac
    - git-hooks
    - devops
  openclaw:
    tags:
      - guardrail
      - enforcement
      - audit
      - devops
    category: devops
    priority: high
  hermes:
    tags:
      - enforcement
      - validation
      - development
    category: development
    related_skills:
      - skill-creator
      - enterprise-blueprint-validation
  providers:
    - openai
    - claude
    - mistral
    - gemini
    - hermes
    - copilot
    - any
version: 0.1.3
---

# Guardrail Enforcement

Two composable halves that share one philosophy — nothing changes without being
watched, and nothing lands without being enforced:

- **Watcher** (`monitor.py`) — a directory-agnostic *condition → action* trigger.
  Its headline job: watch a canonical skills repo and, when a skill's `SKILL.md`
  `version:` changes, derive the skill name from its own directory and auto-commit
  `"<skill_name> version bumped to v<X.Y.Z>"`. New skills are discovered
  dynamically on every scan.
- **Gate** (`gate.py`) — enforces a user-defined loop (pre-checks → loop →
  post-checks) and, only when every stage passes, appends an HMAC-signed,
  hash-chained entry to a tamper-evident audit log.

They are **independent but compose**: run the watcher alone to auto-commit version
bumps, run the gate alone to enforce a loop, or point the watcher's action at the
gate to chain them. Supporting layers: an advisory **`.loop.lock`** (`lock.py`)
so mid-authoring skills are skipped, **git hooks** (`install_hooks.py`) that reject
commits without a valid entry, and a **manifest verifier** (`verify_manifest.py`)
that cross-checks the manifest, the on-disk SKILL.md versions, and git's tracked
hashes. Everything is config-driven and domain-agnostic.

## When to Use

- You maintain a **canonical skills repo** and want every version bump tracked as
  a uniform, rollback-friendly git commit — automatically.
- You want a workflow to run the same checks **every time**, in order, or not
  proceed.
- You need a **signed audit trail** of what ran and passed, resistant to
  after-the-fact editing.
- You want commits (or pushes) blocked unless a validated loop ran first.
- You want half-authored work skipped until it's ready (advisory lock).

## Workflow: Watch a Canonical Skills Repo

```bash
# 1. Configure the watch + record a baseline (interactive, or flag-driven)
python3 scripts/monitor.py setup /path/to/skills-repo \
  --condition skill_version --action git_commit --yes
python3 scripts/monitor.py scan --config /path/to/skills-repo/.monitor.json

# 2. After a version bump (e.g. via skill_enhance), detect + auto-commit
python3 scripts/monitor.py scan --config /path/to/skills-repo/.monitor.json
#   → commits "<skill> version bumped to v<version>" for each changed skill

# 3. Prove the repo is internally consistent
python3 scripts/verify_manifest.py --repo /path/to/skills-repo
```

Add a new skill directory to the repo and the next scan discovers and starts
tracking it — no config change. A skill holding a `.loop.lock` (mid-authoring) is
skipped until released. See [references/monitor-watcher.md](references/monitor-watcher.md)
and [references/loop-lock.md](references/loop-lock.md).

## Free-First Strategy

| Tier | Cost | Stack | Escalation |
|---|---|---|---|
| **Tier 0** | $0/mo | Python 3.8+ stdlib only | Default — covers all local and CI use |
| **Tier 1** | $0-5/mo | + CI runner executing the gate on every push | When gating a shared repo automatically |
| **Tier 2** | $5-20/mo | + Central audit-log store / secret manager | When multiple people must verify one trail |

Every script is Python stdlib only — zero pip installs, zero paid services. HMAC
secrets are generated locally with `secrets.token_hex`.

## Core Workflow

### 1. Configure the gate

```bash
# Interactive
python3 scripts/setup.py /path/to/dir

# Non-interactive (CI-safe): every field via flags
python3 scripts/setup.py /path/to/dir --yes \
  --pre-check "python3 validate.py {path}" \
  --loop-command "python3 build.py {path}" \
  --post-check "python3 validate.py {path}"
```

Writes `.gate.json` and generates the HMAC secret (`0600`) if absent. See
[references/gate-config.md](references/gate-config.md) for the full schema and
worked skills / k8s / pipeline configs.

### 2. Run the gate

```bash
# Preview the plan; run nothing, log nothing
python3 scripts/gate.py --config /path/to/dir/.gate.json --dry-run

# Execute: pre-checks -> loop -> post-checks -> signed log entry
python3 scripts/gate.py --config /path/to/dir/.gate.json --path ./target

# Machine-readable report for CI
python3 scripts/gate.py --config /path/to/dir/.gate.json --json
```

Any failing stage aborts with exit code 1 and writes **no** log entry. `{path}`
and `--var NAME=VALUE` substitute into every command.

### 3. Enforce via git hooks (optional)

```bash
python3 scripts/install_hooks.py --repo /path/to/repo --freshness 3600
```

Installs `pre-commit` / `post-commit` / `pre-push` hooks that reject commits
unless the loop log verifies and carries a PASS entry within the freshness
window. Existing hooks are backed up; `--uninstall` restores them. See
[references/git-hooks.md](references/git-hooks.md).

### 4. Verify the audit trail

```bash
# Full integrity check (signatures + chain)
python3 scripts/verify_log.py /path/to/dir/.loop-log.jsonl \
  --secret ~/.config/gate/hmac.key

# Require a valid PASS entry newer than N seconds (git-hook mode)
python3 scripts/verify_log.py .loop-log.jsonl --recent 3600
```

See [references/hmac-audit.md](references/hmac-audit.md) for how entries are
signed and chained.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/monitor.py` | **Watcher.** Watch a condition (skill version bump / file mtime) and fire an action (git commit / shell command / none). Dynamic skill discovery, lock-aware, `--dry-run`, `--json`. |
| `scripts/lock.py` | Advisory `.loop.lock` manager: acquire/release/check/list. Cooperating tools skip locked directories. |
| `scripts/verify_manifest.py` | Cross-verify manifest ↔ SKILL.md versions ↔ git hashes for a canonical skills repo; `--strict`, `--json`. |
| `scripts/gate.py` | **Gate.** Pre-checks → loop → post-checks → HMAC-signed, hash-chained log entry. `--dry-run`, `--json`, `{path}`/`--var`. |
| `scripts/setup.py` | Write `.gate.json` and generate the `0600` HMAC secret; interactive or flag-driven; `--dry-run`. |
| `scripts/verify_log.py` | Verify the loop log's signatures and hash chain; `--recent` freshness check for hooks. |
| `scripts/install_hooks.py` | Install/remove git hooks binding commits to a valid recent log entry; backs up existing hooks; `--dry-run`. |
| `scripts/menu.sh` | Interactive composable front-end: pick a directory, what to watch, what to trigger; run watcher/gate/locks/verifiers. |
| `scripts/pre-commit-hook.sh` | Stricter skills-specific example hook (per-skill `validate.py --basic`); template only. |

## Enforced Output Statistics

Every Python script emits structured JSON on completion:

```json
{
  "operation": "gate | gate_setup | verify_log",
  "status": "passed | failed | blocked | dry_run | verified",
  "cost": {"tier": 0, "amount_usd": 0.0, "service": "local"}
}
```

## Error Handling

| Error | Response |
|---|---|
| `.gate.json` not found | Report the path; suggest `setup.py` |
| HMAC secret missing/empty | Report the path; suggest `setup.py` to generate |
| Pre/loop/post command fails | Abort with the stage name + last output; no log entry written |
| Paired monitor service down | Status `blocked`, exit 1 — loop never runs |
| Loop log fails verification | `verify_log.py` reports the first (or all) defects; exit 1 |
| Existing non-guardrail git hook present | Backed up to `<hook>.pre-guardrail` before install |
| Python < 3.8 | Report minimum version; suggest upgrade |

## Safety Practices

- **Never destroys hooks** — existing hooks are backed up and restorable via
  `--uninstall`.
- **Secrets stay local** — generated `0600`, never inside the `.skill` archive,
  never committed. A shipped skill contains no secret.
- **Bypass is visible** — `git commit --no-verify` is allowed but leaves a gap in
  the audit trail that verification will surface.
- **`--dry-run` everywhere** — rehearse a full gate run before it mutates state or
  writes a log entry.

## Key References

- **Watcher: conditions, actions, dynamic skill discovery, version-bump commits**: [references/monitor-watcher.md](references/monitor-watcher.md)
- **Advisory `.loop.lock` mechanism and lifecycle**: [references/loop-lock.md](references/loop-lock.md)
- **Manifest ↔ skills ↔ git cross-verification**: [references/manifest-verification.md](references/manifest-verification.md)
- **Gate config schema and worked examples**: [references/gate-config.md](references/gate-config.md)
- **Signed, chained audit log internals**: [references/hmac-audit.md](references/hmac-audit.md)
- **Git hook enforcement, install, bypass**: [references/git-hooks.md](references/git-hooks.md)
- **Pairing the watcher and gate**: [references/monitor-crosscheck.md](references/monitor-crosscheck.md)
- **Design rationale (three-skill architecture) and parked questions**: [references/proposed-design.md](references/proposed-design.md)
- **Full content index and CL-040 snapshot locations**: [references/content-manifest.md](references/content-manifest.md)
