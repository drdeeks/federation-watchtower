# Session 2026-07-09 — Crew Poller Execution Stall (Root Cause + Fix)

## Symptom
5 kanban-orchestrated crews ran for ~3.8h at 0% CPU with ZERO deliverable files.
Kanban showed tasks `active`/`in_progress` (looked like work), but nothing was produced.
The TV Command Center / MCP gateway showed 20 agents "registered" but no real activity.

## Root cause (two compounding defects)

### Defect A — fatal stall (wrong query)
- Pollers launched as `task-poller.py <crew> <ws> <project>` → `agent_id = "<project>-crew"`
  (e.g. `mnemosyne-crew`), but the poller queried
  `WHERE assignee = ?` with that crew name.
- Kanban tasks carry SPECIFIC agent IDs as `assignee` (`mnemosyne-learning-1`),
  never the crew name. So the query matched **zero rows** → `execute_task` returned
  `False` → poller slept (15s loop) forever. All 5 pollers hit this.
- Evidence: `ps` showed all 6 crew processes at 0.0% CPU, state `Ss` (sleeping);
  no child processes under any poller; no deliverable files; all active tasks
  `hb=never` (poller never wrote `last_heartbeat_at`).

### Defect B — missing execution step
- Even with a matching query, the original `execute_task` only called
  `verify_deliverables()` (checks if files ALREADY exist) and marked complete.
  It never INVOKED the agent runtime to WRITE the code.
- `spawn-crew-agents.py` only starts an **enforcer daemon** (idle constraint
  checker, loops `Fixed 0/5 violations`). It does NOT start a code-generating
  runtime. `current_task.json` is written by the dispatcher but nothing consumes it.
- Net: the entire pipeline had no component that actually generated code.

## The fix (user-designed: agent→model map + auto-consume task)
1. **`agent-model-map.json`** at workspace root: `agent_id → { role, profile }`,
   provider-agnostic (no model/provider/key/path). `profile` = existing platform
   runtime handle (Hermes profile).
2. **Rewrote `task-poller.py`**:
   - Query by PROJECT: `WHERE id LIKE '<project>-%' AND status IN ('pending','in_progress','active')`.
   - For each leaf task, resolve assignee → role → profile via the map.
   - Invoke `hemlock-agent -p <profile> -z "<task prompt>" --yolo` (cwd=project_dir).
   - Write `last_heartbeat_at` every cycle.
   - On runtime FAILURE → leave task `ACTIVE` for retry (no fake completion).
   - On success → `verify_deliverables()` → `chain_enforce.py complete` → mark `completed`.

## Verification recipe (minimal test first)
- Prove the execution primitive non-interactively:
  `hemlock-agent -p <profile> -z "Create proof.txt with: AGENT_RUNTIME_OK" --yolo`
  → confirms it writes a file in cwd without manual approval (`--yolo` bypasses
  `approvals.mode: manual`).
- Controlled rollout: kill ONE old poller, launch the fixed one for one project,
  confirm a real `src/...` file appears with a fresh timestamp, THEN roll out to all.
- Watch for the fake-completion trap: a task that fails the runtime but gets
  marked `completed`. The fix leaves it `active`.
- Common runtime failure: profile does not exist → `Profile 'X' does not exist`.
  The map's `profile` MUST match a real `hemlock-agent profile` name (e.g. `mnemosyne-memory`,
  NOT `mnemosyne-learning` — profiles are a different set than agent IDs).

## Outcome
After fix: 13+ Hermes runtimes actively coding; real `ingestion-engine.js`,
`recall-engine.js` + tests generated; mnemosyne 58 src files, aires 77, etc.
Crews no longer phantom — they build.
