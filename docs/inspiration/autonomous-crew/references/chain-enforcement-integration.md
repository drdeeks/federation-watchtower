# Chain Enforcement Integration with Kanban Workers

## Overview

This document describes the integration of loop-enforcer chain enforcement into the kanban worker lifecycle, implemented in prompt_builder.py KANBAN_GUIDANCE step 2b and the chain_enforce.py helper script.

## Architecture

```
Kanban Worker receives phased task
         │
         ▼
Step 2b: Chain Enforcement (MANDATORY)
         │
         ▼
   chain_enforce.py check <project> <phase>
         │
    ┌────┴────┐
    │         │
can_proceed=true  can_proceed=false
    │         │
    ▼         ▼
Do the work   kanban_block("Chain locked: prior phase not complete")
    │
    ▼
Work complete
    │
    ▼
chain_enforce.py complete <project> <phase>
    │
    ▼
Log: kanban_comment("Chain enforced: <chain> step <N> verified+complete")
```

## Helper Script: chain_enforce.py

**Location:** `<HEMLOCK_HOME>/scripts/chain_enforce.py` (or `<WORKSPACE_ROOT>/scripts/chain_enforce.py`)

**Commands:**
```bash
# Check if phase can proceed (exit 0 = proceed, exit 1 = blocked)
python3 chain_enforce.py check <project> <phase_num>

# Verify + complete phase after work (unlocks next phase)
python3 chain_enforce.py complete <project> <phase_num>

# Show full chain status
python3 chain_enforce.py status <project>
```

**Project Names:** `aires`, `autopilot`, `agora`, `edgewalker`, `mnemosyne`

**Chain Location:** `<WORKSPACE_ROOT>/qwen-cloud-2026/<project>/.chain/<project>-blueprint.json`

## Project Directory Structure

```
<WORKSPACE_ROOT>/
├── qwen-cloud-2026/
│   ├── mnemosyne/
│   │   └── .chain/
│   │       └── blueprint-mnemosyne.json
│   ├── autopilot/
│   │   └── .chain/
│   │       └── autopilot-blueprint.json
│   ├── aires/
│   │   └── .chain/
│   │       └── blueprint-aires.json
│   ├── agora/
│   │   └── .chain/
│   │       └── blueprint-agora.json
│   └── edgewalker/
│       └── .chain/
│           └── blueprint-edgewalker.json
├── mnemosyne -> qwen-cloud-2026/mnemosyne      (symlink)
├── autopilot -> qwen-cloud-2026/autopilot      (symlink)
├── aires -> qwen-cloud-2026/aires              (symlink)
├── agora -> qwen-cloud-2026/agora              (symlink)
└── edgewalker -> qwen-cloud-2026/edgewalker    (symlink)
```

**Key Rule:** Chain JSON paths must point to the REAL directory (`qwen-cloud-2026/<project>`), NOT the symlink.

## KANBAN_GUIDANCE Step 2b (Injected into Every Worker)

```
2b. **Chain enforcement (MANDATORY for phased tasks).** If your task title
contains 'Phase' and a `.chain` directory exists in the project root
(e.g. `${WORKSPACE_ROOT}/<project>/.chain/` or `qwen-cloud-2026/<project>/.chain/`),
you MUST enforce the loop-enforcer chain before doing ANY work:

a) Identify the chain: `ls <project>/.chain/*.json`
b) Read the chain JSON to find the step matching your phase
c) Run: `python3 ~/.hermes/skills/devops/loop-enforcer/scripts/chain.py check <project_dir> <chain_name> <marker_path>`
d) If state is 'locked': STOP. Call `kanban_block(reason='Chain locked: prior phase not complete. Run chain.py complete on the previous phase first.')` and exit.
e) If state is 'active': proceed with work.
f) When work is COMPLETE, run: `python3 ~/.hermes/skills/devops/loop-enforcer/scripts/chain.py verify <project_dir> <chain_name> <marker_path>`
   then `python3 ~/.hermes/skills/devops/loop-enforcer/scripts/chain.py complete <project_dir> <chain_name> <marker_path>`
   to unlock the next phase.
g) Log the chain enforcement: `kanban_comment(body='Chain enforced: <chain_name> step <N> verified+complete')`
```

## Common Pitfalls & Fixes

### 1. Empty Phase Markers
**Problem:** `.phase-*.marker` files created as empty stubs signal "done" without actual work.
**Fix:** Delete empty markers, reset chain step to `active`. Markers only created by `chain.py complete` after verification.

### 2. Root Directory vs qwen-cloud-2026
**Problem:** Chain JSON paths point to `${WORKSPACE_ROOT}/<project>` but code lives in `${WORKSPACE_ROOT}/qwen-cloud-2026/<project>`.
**Fix:** Ensure root dirs are symlinks. Chain paths must point to real directory. Reset chain if mismatched.

### 3. Chain State Mismatch
**Problem:** Code is complete but chain shows locked/active wrong step.
**Fix:** Use `reset_chain.py <project>` to reset to clean state (step[0]=active, rest=locked), then re-verify completed phases.

### 4. Workers Skipping Chain Check
**Problem:** Kanban dispatcher runs all phases simultaneously; workers don't check chain.
**Fix:** KANBAN_GUIDANCE step 2b mandates chain check. Verify it's in prompt_builder.py.

### 5. Chain File Not Found
**Problem:** `chain_enforce.py` looks in wrong workspace path.
**Fix:** Script uses `<WORKSPACE_ROOT>/qwen-cloud-2026/<project>/.chain/`. Ensure WORKSPACE_ROOT env var or fallback works.

## Reset Procedure

```bash
# 1. Reset all phase tasks to "ready" in kanban
sqlite3 ~/.hermes/kanban.db "UPDATE tasks SET status='ready' WHERE title LIKE '%Phase%';"

# 2. Reset chain state
python3 reset_chain.py <project>

# 3. Remove empty marker files
find <project> -name ".phase-*.marker" -size 0 -delete

# 4. Re-verify completed phases in order
for phase in 0 1 2 3 4 5 6; do
    python3 chain_enforce.py check <project> $phase
    python3 chain_enforce.py complete <project> $phase
done
```

## Verification Checklist

- [ ] `chain_enforce.py` at `<HEMLOCK_HOME>/scripts/chain_enforce.py`
- [ ] KANBAN_GUIDANCE step 2b in prompt_builder.py
- [ ] All 5 projects have `.chain/<project>-blueprint.json`
- [ ] Root dirs are symlinks to `qwen-cloud-2026/<project>`
- [ ] Chain paths point to real directory, not symlink
- [ ] Workers can execute `chain_enforce.py check/complete/status`
- [ ] No empty `.phase-*.marker` files