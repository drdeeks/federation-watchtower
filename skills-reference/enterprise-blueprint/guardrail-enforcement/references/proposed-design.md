# Proposed Design — Three-Skill Guardrail Architecture
## Table of Contents

- [Motivation](#motivation)
- [The three skills](#the-three-skills)
- [Distribution matrix](#distribution-matrix)
- [Cross-check pattern (monitor ↔ gate)](#cross-check-pattern-monitor-↔-gate)
- [Interactive setup (`gate/scripts/setup.py` sketch)](#interactive-setup-`gate/scripts/setup.py`-sketch)
- [Small edits required in the pure `skill-creator`](#small-edits-required-in-the-pure-`skill-creator`)
- [What changes in the code we already wrote](#what-changes-in-the-code-we-already-wrote)
- [Open design questions (parked for the future session)](#open-design-questions-parked-for-the-future-session)


## Motivation

During the CL-040 session, we built enforcement (SKILL_LOOP_TOKEN gates on
mutating scripts, `skill_enhance.py` orchestrator, `.git/hooks/pre-commit`)
directly into `skill-creator`. That broke distributability: a `.skill` archive
of skill-creator now contains gated scripts that only work when a
loop-enforcer is present, which itself needs an HMAC secret and a loop log
that only the originator has.

The fix: split into three independent skills that compose.

## The three skills

### 1. `monitor` (generalization of the current `autowatch`)

Directory- and content-agnostic "condition → action" trigger.

**Conditions** (pluggable):
- File mtime change (current autowatch behavior)
- Timer / cron-like
- API poll (URL returns value that changed)
- Git branch update
- Log-file grep match

**Actions** (pluggable):
- Git commit (current autowatch behavior)
- HTTP webhook POST
- Run arbitrary shell command
- Send desktop notification (`notify-send`, macOS user notifications)
- Fire an OS event / start a systemd unit

Config lives at `<watched-dir>/.monitor.json` (or path passed via CLI):

```json
{
  "watches": [
    {
      "condition": {"type": "file_mtime", "pattern": "**/SKILL.md"},
      "action":    {"type": "git_commit", "template": "updated {subdir} to version {version}"},
      "debounce_seconds": 5
    },
    {
      "condition": {"type": "api_poll", "url": "https://api.twitter.com/...", "interval": 60},
      "action":    {"type": "shell_command", "cmd": "python3 respond_to_mention.py"}
    }
  ]
}
```

### 2. `gate` (generalization of the proposed `loop-enforcer`)

Workflow gate that enforces a user-defined loop before an action lands.

Steps per invocation:

1. Run configured **pre-checks** (e.g. `validate.py --basic`, `pytest`,
   `kubectl apply --dry-run`)
2. Run the configured **loop command** (the actual work — anything)
3. Run configured **post-checks** (e.g. re-validate, `grep '^SUCCESS' log`)
4. Sign an HMAC-256 log entry and append to `.loop-log.jsonl`
5. Optionally install `.git/hooks/{pre-commit,post-commit,pre-push}` that
   reject commits without a corresponding valid log entry
6. Optionally cross-check that a paired `monitor` service is active

Config at `<gated-dir>/.gate.json`:

```json
{
  "pre_checks":  [["python3", "skill-creator/scripts/validate.py", "{path}", "--basic"]],
  "loop_command": ["python3", "skill-creator/__init__.py", "--scaffold-or-update", "{path}"],
  "post_checks": [["python3", "skill-creator/scripts/validate.py", "{path}"]],
  "hmac_secret_path": "~/.config/gate/hmac.key",
  "log_path": ".loop-log.jsonl",
  "git_integration": true,
  "paired_monitor_service": "autowatch-curated"
}
```

Same tool, different use cases:

- **Skills authoring gate** — pre-check = validate.py, loop = skill_enhance.py, post = re-validate
- **Kubernetes deploy gate** — pre-check = `kubectl apply --dry-run`, loop = `./deploy.sh`, post = `./health-check.sh`
- **Batch pipeline gate (no git)** — pre-check = disk-space check, loop = `pipeline.py`, post = `grep SUCCESS log`. `git_integration: false` skips hooks.

### 3. `skill-creator` (pure tools variant — the target endpoint of the split)

- `validate.py` — public, read-only status check (as it is today)
- `auto_fix.py` — public (rename from current `_auto_fix.py`, drop the SKILL_LOOP_TOKEN gate)
- `package_skills.py` — public (rename from `_package_skills.py`, drop gate)
- `test_script.py`, `upgrade_to_enterprise.py`, `consolidate_skills.py` — same treatment
- `analyze_skill.py`, `verify_sources.py`, `detect_redundancy.py` — already public
- `__init__.py` — scaffolder (unchanged)
- No `skill_enhance.py` — that logic moves to whoever's orchestrating the workflow (typically `gate` with a skills-mode config)
- No SKILL_LOOP_TOKEN anywhere

Shipping `skill-creator.skill` alone gives a recipient pure, immediately-usable tools with zero policy overhead.

## Distribution matrix

| Ship | Recipient gets |
|---|---|
| `agent-mail.skill` alone | Just the skill. No enforcement anywhere. |
| `skill-creator.skill` alone | Pure tools. Validate/package/etc. any skill without any policy layer. |
| `monitor.skill` alone | Directory watcher. Configurable via interactive setup. No enforcement. |
| `gate.skill` alone | Workflow-gate tool. Configurable via interactive setup. |
| `skill-creator` + `gate` | Tools + a way to enforce a skill-authoring loop over them. |
| `monitor` + `gate` | Auto-triggered workflow with signed audit. |
| All three | Full enforced skill-authoring platform. |

## Cross-check pattern (monitor ↔ gate)

- `gate` optionally verifies its paired `monitor` service is running (`systemctl --user is-active <name>` or launchctl equivalent) before proceeding. If configured and missing → refuse.
- `monitor` optionally verifies its target dir is under a `gate` config. If configured and the target has changes without a matching log entry → hold off firing the action until gate has run.
- Neither is required. Either can run standalone. Together they form a bidirectional guardrail.

## Interactive setup (`gate/scripts/setup.py` sketch)

```
? What directory are you gating? /home/drdeek/bin/_curated
? Git integration? [Y/n]:
? Which paired monitor should be verified before every loop run?
  [none | existing service | install new]:
? Monitor service name:
? Pre-check command (run before loop) [multi]:
? Loop command (the actual work):
? Post-check command (verify result):
? Where to store the HMAC secret? [~/.config/gate/hmac.key]:
? Where to store the loop log? [<dir>/.loop-log.jsonl]:
? Install hooks now? [Y/n]:
✓ Config written to <dir>/.gate.json
✓ Secret generated at ~/.config/gate/hmac.key (mode 0600)
✓ Hooks installed (or skipped if git_integration=false)
✓ Ready.
```

## Small edits required in the pure `skill-creator`

Add a protected-files list to `validate.py`, `auto_fix.py`, and `package_skills.py`:

```python
GUARDRAIL_ARTIFACTS = {".loop-log.jsonl", ".gate.json", ".loop.lock",
                        ".monitor.json", ".autowatch.json"}
```

When walking the skill tree:
- If one of these files is at the skill root or watched-dir root → treat as opaque, don't count against structural rules, don't move, don't delete.
- If in an unexpected location (e.g. inside `scripts/`) → warn the user with "unexpected guardrail artifact — was this intentional?"
- Otherwise every other file goes through the normal rules.

This lets `skill-creator` remain unaware of the guardrail system while cooperating with it when present.

## What changes in the code we already wrote

To move from current state to this architecture:

1. Rename gated scripts back to public names, drop the SKILL_LOOP_TOKEN gates:
   - `_package_skills.py` → `package_skills.py`
   - `_test_script.py` → `test_script.py`
   - `_upgrade_to_enterprise.py` → `upgrade_to_enterprise.py`
   - `_consolidate_skills.py` → `consolidate_skills.py`
   - `_validate_pro.py` → `validate_pro.py`
   - `_auto_fix.py` → `auto_fix.py`
2. Move `skill_enhance.py` out of `skill-creator/scripts/`. It becomes either (a) a skills-mode default config bundled with `gate`, or (b) a small skill on its own that depends on both `skill-creator` and `gate`.
3. Move the current `.git/hooks/pre-commit` into `gate/scripts/install_hooks.py` — hook is installed by the tool, not shipped with the skills.
4. Build `monitor` (generalize autowatch): condition + action plugin architecture.
5. Build `gate`: pre-checks + loop_command + post-checks + HMAC log + optional hooks + optional monitor cross-check.
6. Add the `GUARDRAIL_ARTIFACTS` protected list to `skill-creator`'s three walker scripts.
7. Scaffold both new skills through `skill-creator/__init__.py --scaffold`.

## Open design questions (parked for the future session)

- HMAC secret rotation: how often, and how does log verification handle multiple valid keys during rotation?
- Signed log entries — do we sign each entry independently or chain them (Merkle-style) for tamper detection across the whole log?
- Monitor's condition/action plugins — Python entry_points, or a simpler "each plugin is a script in a subdir" pattern? Latter is more portable.
- `gate` + `monitor` running in the same repo — do they need to share config, or is duplication (each has its own JSON) fine?
- Bootstrapping: how does a fresh clone of a repo know it's supposed to install these tools? A `.guardrail-recipe.yaml` at the repo root that lists which skills to install?
