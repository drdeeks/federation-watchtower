# Task Dispatcher & Poller — Execution Model

## Task Dispatcher & Poller

### Task Dispatcher (`scripts/task-dispatcher.py`)

Runs every 30 seconds. Synchronizes kanban tasks with chain state and assigns work to available agents.

**Key behaviors:**
1. **Chain sync** — Reads chain state from `.crew-*/.blueprint-chain/*-blueprint.json` (priority over `.blueprint-chain/`)
2. **Kanban sync** — `_sync_kanban_with_chain()` ensures kanban task statuses match chain step states
3. **Subtask unlock** — When chain phase becomes `active`, unlocks all subtasks (`*-phase-NN-task-*` and `*-phase-NN-validation`) from `locked` → `pending`
4. **Full subtask assignment** — Assigns ALL subtasks for active phase, not just phase-level task
5. **Round-robin agent assignment** — Distributes subtasks across available agents (prefers agents with running enforcers)

See `scripts/task-dispatcher.py` for complete implementation.

### Checklist-Driven Task Generation (`scripts/generate-tasks-from-checklist.py`)

Parses each project's `checklist.md` to create granular kanban tasks from deliverables and validation gates.

**Input:** `checklist.md` with checkbox items under `## Phase N: Title` headers
**Output:** Kanban tasks per deliverable + validation gate per phase

**Supported checklist formats:**
- Mnemosyne style: `## Phase N — Title` + `- [ ] Deliverable`
- Aires/Autopilot/Agora/Edgewalker style: `## Phase N: Title` + `### Phase Validation Gate` markers

**Generated task IDs:**
- `{project}-phase-{NN}-task-{NN}` — Deliverable tasks
- `{project}-phase-{NN}-validation` — Validation gate task

**Status mapping:**
- Phase 0 → `active` (start immediately)
- Phases 1-6 → `locked` (unlocked by dispatcher when chain advances)
- Checked items → `completed`

Run after any checklist update:
```bash
python3 scripts/generate-tasks-from-checklist.py
```

### Dispatcher Workflow

1. Reads chain status for each project
2. Finds active phase (or activates first pending)
3. Matches kanban task to active phase
4. Assigns to available agent (prefers running enforcer)
5. Creates `.agent/current_task.json` in agent workspace
6. Updates kanban status: `pending` → `in_progress`
7. Updates chain step: `locked` → `active`

### Task Poller (`scripts/task-poller.py`)

Runs on **each agent**, polls kanban for assigned tasks, executes work.

**Agent-Side Execution (FINAL correct model — Session 2026-07-09):**
The poller is launched **per project** (e.g. `task-poller.py <crew> <ws> <project>`), NOT per agent. It drives the agent runtime to actually produce code — "executes work" means INVOKE THE RUNTIME, not just verify files exist.

1. **Query by PROJECT, never by crew-name assignee.** `SELECT ... FROM tasks WHERE id LIKE '<project>-%' AND status IN ('pending','in_progress','active')`. The launch arg `<crew>` is the crew name (e.g. `mnemosyne-crew`); kanban tasks are assigned to SPECIFIC agent IDs (`mnemosyne-learning-1`), never the crew name. Querying `WHERE assignee = '<crew>'` matches ZERO rows → poller sleeps forever at 0% CPU. This was the fatal 3.8h stall.
2. For each **leaf task** (`*-phase-NN-task-*` / `*-phase-NN-validation`), resolve assignee → `role` → execution `profile` via `agent-model-map.json`.
3. Invoke the agent runtime (platform-agnostic via profile handle):
   `hemlock-agent -p <profile> -z "<task prompt>" --yolo` with `cwd=<project_dir>`.
   The profile carries the concrete model+provider; the poller knows nothing about them.
4. Update `last_heartbeat_at` (the kanban `tasks` table has this column; the poller MUST write it or status shows `hb=never`).
5. On runtime success → `verify_deliverables()` → if true run `chain_enforce.py complete <project> <phase>` → mark `completed`.
6. **On runtime FAILURE (bad profile, timeout, error) → leave the task `ACTIVE` for retry. NEVER mark completed when the runtime failed** — that is fake completion and is explicitly banned.

**CRITICAL BUG FIX (Session 2026-07-09):** The poller originally only executed tasks with status `"pending"`, but the dispatcher marks assigned tasks as `"in_progress"` when creating the work file. This caused all dispatched tasks to be skipped. Fixed by changing the poller to execute both `"pending"` AND `"in_progress"` tasks assigned to the agent.

```python
# In run_once() - OLD (broken):
if task["status"] == "pending":
    self.execute_task(task)

# NEW (fixed):
if task["status"] in ("pending", "in_progress"):
    self.execute_task(task)
```

This is a **dispatcher-poller contract**: Dispatcher assigns → sets `in_progress` → Poller picks up `in_progress` tasks and executes them.

**CRITICAL BUG FIX (Session 2026-07-09 — Chain Advance):** The poller only called `chain_enforce.py complete` for **Phase 0**. For Phase 1+ it fell through — kanban task marked `completed` but chain step never advanced, so the dispatcher never unlocked the next phase. The chain stalled at Phase 1 across all 5 projects.

**Fix applied to `scripts/task-poller.py`:**
1. Added `verify_deliverables(project, project_dir, phase_num, task)` that checks actual deliverables exist (Phase 0: foundation files; Phase 1+: task-referenced files, test files, non-empty src tree).
2. After chain check passes, call `verify_deliverables()`. If true → call `chain_enforce.py complete` for **ALL phases**.
3. If false → leave chain step open, do NOT mark task complete.

```python
# NEW (fixed - in execute_task):
verified = verify_deliverables(project, project_dir, phase_num, task)
if verified:
    print(f"[{agent_id}] Deliverables verified, completing chain step {phase_num}")
    subprocess.run(['python3', str(CHAIN_ENFORCE_SCRIPT), 'complete', project, str(phase_num)], ...)
else:
    print(f"[{agent_id}] Deliverables NOT verified for phase {phase_num} — leaving chain step open")
    # Do NOT mark task completed, do NOT advance chain
```

**Result:** Phase 1 tasks now complete → chain advances → Phase 2 unlocks. Verified on all 5 projects (mnemosyne, autopilot, aires, agora, edgewalker).

**PITFALL — Fatal stall: poller queries `assignee = crew_name` (Session 2026-07-09).** The poller is launched with the crew name as its first arg (`task-poller.py mnemosyne-crew ...`), but kanban tasks carry SPECIFIC agent IDs as `assignee` (`mnemosyne-learning-1`), never the crew name. A query `WHERE assignee = 'mnemosyne-crew'` matches zero rows → `execute_task` returns `False` → poller sleeps at 0% CPU forever. All 5 crews stalled this way for 3.8h with zero deliverables. **Fix:** query `WHERE id LIKE '<project>-%'` (project-scoped). The crew name arg is only for logging.

**PITFALL — Missing execution step (the real Defect B).** A poller that only checks `verify_deliverables()` (do the files already exist?) and marks complete is a verifier, not an executor. If nothing ever WRITES the code, deliverables never appear and the crew produces nothing. **The poller MUST invoke the agent runtime** (`hemlock-agent -p <profile> -z "<task>" --yolo`, cwd=project_dir) to generate the deliverables. `spawn-crew-agents.py` only starts an idle enforcer daemon — it does NOT start a code-generating runtime. The execution trigger lives in the poller.

**PITFALL — Fake completion.** Never mark a task `completed` when the runtime invocation failed (bad profile, timeout, non-zero exit). Set it back to `active` for retry. The user bans fake completion absolutely; a "done" task with no real file on disk is the exact failure mode to prevent. `verify_deliverables()` is the gate, but only trust it AFTER a successful runtime run.

**PITFALL — Heartbeat column.** The kanban `tasks` table has `last_heartbeat_at`. If the poller never writes it, status queries show `hb=never` for every active task — indistinguishable from a real stall. Write `last_heartbeat_at` on every poll cycle.

### Wire Kanban to Chain (`scripts/wire-kanban-to-chain.py`)

Creates kanban tasks from chain steps, using the actual kanban schema (created_at/started_at/completed_at as integers).

```bash
python3 scripts/wire-kanban-to-chain.py \
  --project ${WORKSPACE_ROOT}/qwen-cloud-2026/mnemosyne \
  --chain ${WORKSPACE_ROOT}/qwen-cloud-2026/mnemosyne/.crew-mnemosyne-crew/.blueprint-chain/mnemosyne-blueprint.json
```

See `references/blueprint-chain-integration.md` for complete wiring details.


---

## Agent Model Map (Crew Execution Binding)

## Agent Model Map (Crew Execution Binding — Provider-Agnostic)

The poller resolves each kanban task's assignee to a concrete runtime via **`agent-model-map.json`** at the workspace root. This file is **strictly provider/platform agnostic**: it maps each `agent_id` → `{ role, profile }` only. It contains **NO model IDs, provider names, API keys, or absolute paths.** Concrete model+provider resolution is delegated to the agent's execution `profile` (the platform's runtime binding, which carries the model/provider), or overridden per-role at runtime via `MODEL_ROLE_<ROLE>` env vars.

```json
{
  "agents": {
    "mnemosyne-learning-1": { "role": "reasoning", "profile": "mnemosyne-memory" },
    "mnemosyne-ingestion-1": { "role": "coding", "profile": "mnemosyne-ingestion" }
  }
}
```

**Rules:**
- `role` is abstract: `reasoning | coding | creative | general | edge`. Never a model name.
- `profile` is an opaque handle to an existing platform agent runtime (e.g. a Hermes profile). Verify the profile EXISTS (`hemlock-agent profile create <name>` if missing) — invoking a non-existent profile fails the runtime and the task is left `active` for retry (not fake-completed).
- The poller loads this map once per `execute_task` call; env overrides take precedence over the profile's own model/provider.
- **Never hardcode model/provider in the map, the poller, or any crew script.** If a model name appears, the map is wrong.

See `references/templates/agent-model-map.json` for a full 20-agent template.

