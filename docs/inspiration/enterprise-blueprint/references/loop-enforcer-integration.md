# Loop-Enforcer Integration — Enterprise Blueprint

## Current State (v1.0.3)

| Component | Integration Status |
|-----------|-------------------|
| `enterprise-blueprint/__init__.py` | Uses loop-enforcer chain.py via `LOOP_ENFORCER` env var — **phase-level only** |
| `scripts/enforce_blueprint.py` | Creates checklist-level chain + `deliverables.json` — **not auto-triggered** |
| `loop-enforcer/scripts/chain_enforce.py` (worker API) | **Exists but has hardcoded paths, wrong chain name pattern** |
| `skill-creator/scripts/skill_enhance.py` | Uses OWN vendored chain.py — **doesn't delegate to loop-enforcer skill** |

## Environment Variables (Required for Path Agnosticism)

```bash
# Point to loop-enforcer skill (NOT hardcoded `${USB_MOUNT}/.hermes/skills` or `$HOME/.hermes/skills`)
export LOOP_ENFORCER_ROOT=/path/to/loop-enforcer

# Target agent/crew workspace
export AGENT_WORKSPACE=/path/to/agent-or-crew-dir

# Enforcer daemon socket (for ACK character enforcement)
export ENFORCER_SOCKET=/run/ack-enforcer.sock

# Habit/log paths (ACK conventions)
export ACK_HABITS_DIR=/path/to/habits
export ACK_ACK_LOG=/var/log/ack/ack.log
export ACK_INJECT_LOG=/var/log/ack/inject.log
```

**NEVER hardcode paths.** `__init__.py` line 14 currently has `SKILLS_ROOT = Path("${USB_MOUNT}/.hermes/skills")` — must use `LOOP_ENFORCER_ROOT`.

## Chain File Naming (CRITICAL - per autonomous-crew-integration lesson)

**Chain JSON must reference `checklist`, not `blueprint`** (ref: `autonomous-crew-integration/references/chain-enforcement-checklist-vs-blueprint.md`):

```bash
# WRONG - chain files named *-blueprint.json
.blueprint-chain/canon-os-blueprint.json

# CORRECT - chain files named *-checklist.json
.blueprint-chain/canon-os-checklist.json
```

Dispatcher (`chain_enforce.py`) searches in priority order:
1. `.crew-*/.blueprint-chain/` (highest - crew-manager chains)
2. `.blueprint-chain/` (standard)
3. `.chain/` (fallback)

**enterprise-blueprint must write to `.blueprint-chain/<project>-checklist.json`**

## loop-enforcer/scripts/chain_enforce.py — REQUIRED FIXES

Current implementation has **hardcoded paths** and **wrong chain name pattern**:

```python
# CURRENT (lines 10-11) - WRONG
CHAIN_SCRIPT = os.path.expanduser("${USB_MOUNT}/.hermes/skills/devops/loop-enforcer/scripts/chain.py")
PROJECT_BASE = os.path.expanduser("${PROJECT_BASE}")
```
# CURRENT (line 34) - WRONG pattern
if f.endswith(".json") and "blueprint" in f:
```

### Required Fixes:

| Issue | Current | Fixed |
|-------|---------|-------|
| Hardcoded chain.py path | `~/.hermes/skills/...` | `os.environ.get("LOOP_ENFORCER_ROOT") + "/scripts/chain.py"` |
| Hardcoded project base | `~/qwen-cloud-2026` | `os.environ.get("AGENT_WORKSPACE", os.getcwd())` |
| Chain name pattern | `"blueprint" in f` | `"checklist" in f` |
| Search locations | `.chain/` only | Priority: `.crew-*/.blueprint-chain/` → `.blueprint-chain/` → `.chain/` |

## Required Worker API — enterprise-blueprint/scripts/chain_enforce.py (MISSING)

enterprise-blueprint needs its own worker API wrapper compatible with loop-enforcer pattern:

```python
#!/usr/bin/env python3
"""Worker API wrapper for loop-enforcer chain.py — compatible with autonomous-crew-integration."""

import subprocess
import sys
import os
import json
from pathlib import Path

# Use env vars, not hardcoded paths
CHAIN_PY = Path(os.environ.get("LOOP_ENFORCER_ROOT", Path.home() / ".hermes" / "skills" / "devops" / "loop-enforcer")) / "scripts" / "chain.py"

def find_chain(project_dir):
    """Search priority: .crew-*/.blueprint-chain/ > .blueprint-chain/ > .chain/"""
    project = Path(project_dir)
    for pattern in [".crew-*/.blueprint-chain", ".blueprint-chain", ".chain"]:
        for chain_dir in project.glob(pattern):
            for json_file in chain_dir.glob("*-checklist.json"):
                return str(chain_dir), json_file.stem
    return None, None

def check(project_dir, phase_num):
    chain_dir, chain_name = find_chain(project_dir)
    if not chain_dir:
        return {"can_proceed": False, "reason": "No checklist chain found"}
    step_path = f"phase-{phase_num:02d}"
    # ... call chain.py check
    return {"can_proceed": True, "step": step_path}

def complete(project_dir, phase_num):
    chain_dir, chain_name = find_chain(project_dir)
    # ... call chain.py verify + complete
    return {"ok": True}
```

## Integration Gaps to Close

| Gap | Location | Fix |
|-----|----------|-----|
| Hardcoded skills path | `__init__.py:14` | Use `LOOP_ENFORCER_ROOT` env var (like skill_enhance.py:33) |
| Phase-level only chain | `__init__.py:80-90` | Call `enforce_blueprint.py --init` for checklist-level steps |
| No auto-trigger on checklist generation | `generate_checklist.py` | Hook `enforce_blueprint.py --init` after generation |
| No worker API in enterprise-blueprint | Missing script | Create `scripts/chain_enforce.py` |
| No agent discovery | — | Add `discover_agents.py` scan |
| No crew/agent-dir targeting | `__init__.py enhance_skill()` | Add `--target-dir`, `--crew`, `--agent-dir` flags |
| Test execution not integrated | `test-runner.py` | Run real test suites (pytest, cargo, npm) as validation gate |

## skill_enhance.py Pattern (Reference for env var delegation)

```python
# skill_enhance.py lines 30-43 — uses LOOP_ENFORCER_ROOT env var
_le_env = os.environ.get("LOOP_ENFORCER_ROOT")
if _le_env and (Path(_le_env) / "scripts" / "chain.py").exists():
    LOOP_ENFORCER = Path(_le_env)
    CHAIN_PY = LOOP_ENFORCER / "scripts" / "chain.py"
    VALIDATE_PY = LOOP_ENFORCER / "scripts" / "validate.py"
    CHAIN_REPORT_PY = LOOP_ENFORCER / "scripts" / "chain_report.py"
else:
    LOOP_ENFORCER = SKILL_CREATOR_ROOT
    CHAIN_PY = SCRIPT_DIR / "chain.py"  # built-in fallback
```

## Enhancement Pipeline (Proposed for enterprise-blueprint)

```bash
# Target: apply blueprint enforcement to agent dir or crew dir
python3 -m enterprise_blueprint.enhance_skill \
  --target ./my-agent \
  --noninteractive

# Or target crew
python3 -m enterprise_blueprint.enhance_skill \
  --crew ./my-crew \
  --noninteractive
```

**Internal flow:**
1. `generate_checklist.py` → writes `checklist.md` to target
2. `enforce_blueprint.py --init` → creates `.blueprint-chain/<project>-checklist.json` + `deliverables.json`
3. `discover_agents.py` → scans target for agent workspaces, writes `assignments.json`
4. `chain_enforce.py` available for workers to call `check`/`verify`/`complete`

## Test Gates (Not Just Syntax)

| Tier | Command | Purpose |
|------|---------|---------|
| Syntax | `validate.py --syntax auto` | Already in loop-enforcer |
| Unit | `pytest -xvs` / `cargo test` / `npm test` | **Must run actual test suites** |
| Integration | `hemlock test-integration` | Service health, API contracts |
| E2E | `hemlock test-e2e` / `playwright test` | Full workflows |
| Blueprint | `validate_blueprint.py --json` | 58+ enterprise rules |

`test-runner.py` must execute REAL test commands, not just syntax checks.

## Lessons Learned (This Session)

1. **Two chain implementations exist** — skill-creator's built-in + loop-enforcer skill. Pick one canonical (loop-enforcer) and delegate via `LOOP_ENFORCER_ROOT`.
2. **Checklist is the enforcement contract** — Blueprint is spec; checklist is deliverable. Chain steps must map to checklist items.
3. **Worker API is mandatory** — Agents/crews need `chain_enforce.py check/complete` to integrate with kanban dispatcher.
4. **Path agnosticism requires env vars** — No hardcoded `${USB_MOUNT}/` anywhere.
5. **Test validation must be real** — Syntax-only passes broken code.
6. **loop-enforcer's chain_enforce.py has bugs** — Hardcoded paths, wrong chain name pattern (`blueprint` vs `checklist`), limited search locations.