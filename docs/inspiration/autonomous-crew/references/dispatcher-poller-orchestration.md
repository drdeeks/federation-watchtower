# Dispatcher-Poller Orchestration Pattern (Verified 2026-07-09)

## The Complete Loop

This session proved the kanban-orchestrated crew loop works end-to-end across 5 simultaneous projects.

```
┌─────────────────────────────────────────────────────────────────┐
│                    LOOP ENFORCER CHAIN                          │
│  Phase 0 → Phase 1 → Phase 2 → ... → Phase N                   │
│     │        │         │              │                         │
│     ▼        ▼         ▼              ▼                         │
│  locked  locked    locked         locked                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  TASK DISPATCHER (every 30s)                    │
│  1. Reads chain state (.crew-*/.blueprint-chain/*-blueprint.json)│
│  2. Syncs kanban status ↔ chain step state                      │
│  3. Finds active phase, unlocks subtasks                        │
│  4. Assigns ALL subtasks for active phase                       │
│  5. Marks kanban: pending → in_progress, creates .agent/task.json│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 TASK POLLER (per agent, every 15s)              │
│  1. Polls kanban for tasks assigned to THIS agent_id            │
│  2. For each task with status IN ("pending", "in_progress"):    │
│     a. chain_enforce.py check <project> <phase>                 │
│     b. If can_proceed: execute phase work                       │
│     c. verify_deliverables() — checks actual artifacts exist    │
│     d. If verified: chain_enforce.py complete <project> <phase> │
│     e. Marks kanban: in_progress → completed                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                     Chain advances
                     Next phase unlocks
```

## Verified Configuration (5 projects, 6 processes)

| Process | Command | PID |
|---------|---------|-----|
| Dispatcher | `python3 task-dispatcher.py` | 307040 |
| Poller (mnemosyne) | `task-poller.py mnemosyne-crew /path/mnemosyne mnemosyne` | 307101 |
| Poller (autopilot) | `task-poller.py autopilot-crew /path/autopilot autopilot` | 307364 |
| Poller (aires) | `task-poller.py aires-crew /path/aires aires` | 307393 |
| Poller (agora) | `task-poller.py agora-crew /path/agora agora` | 307468 |
| Poller (edgewalker) | `task-poller.py edgewalker-crew /path/edgewalker edgewalker` | 307497 |

**All 6 processes ran simultaneously** — dispatcher assigns, 5 pollers execute in parallel.

## Chain State Progression (All 5 Projects)

| Project | Before Fix | After 1 Poller Cycle |
|---------|------------|---------------------|
| mnemosyne | Phase 1 active | Phase 2 active |
| autopilot | Phase 1 active | Phase 3 active |
| aires | Phase 1 active | Phase 3 active |
| agora | Phase 1 active | Phase 3 active |
| edgewalker | Phase 1 active | Phase 3 active |

Phase 1 tasks completed → chain step marked `complete` → Phase 2 unlocked → dispatcher assigns Phase 2 tasks.

## Critical Contracts

### Dispatcher → Poller Contract
- Dispatcher marks assigned task `in_progress` (NOT `pending`)
- Poller MUST execute tasks with status `in_progress` (fixed 2026-07-09)

### Poller → Chain Contract  
- Poller verifies deliverables BEFORE calling `chain_enforce.py complete`
- If verification fails: chain stays open, task NOT marked complete
- Only `verified=true` → advance chain

### Chain → Dispatcher Contract
- Dispatcher reads chain state each cycle
- `_sync_kanban_with_chain()` ensures kanban matches chain
- Chain `active` → dispatcher unlocks subtasks
- Chain `complete` → dispatcher marks phase task `completed`

## Starting the Full Stack

```bash
cd $HOME/qwen-cloud-2026
export WORKSPACE_ROOT=$HOME/qwen-cloud-2026
export HEMLOCK_HOME=$HOME/.hermes

# 1. Start dispatcher (background)
python3 $HEMLOCK_HOME/skills/devops/autonomous-crew-integration/scripts/task-dispatcher.py &
DISPATCHER_PID=$!

# 2. Start one poller PER PROJECT (background)
for proj in mnemosyne autopilot aires agora edgewalker; do
    python3 $HEMLOCK_HOME/skills/devops/autonomous-crew-integration/scripts/task-poller.py \
        ${proj}-crew \
        $WORKSPACE_ROOT/$proj \
        $proj &
done

# All processes now running — crew is self-driving
```

## Verification Commands

```bash
# Check chain state for any project
python3 -c "
import json
f='$PROJ/.crew-${PROJ}-crew/.blueprint-chain/${PROJ}-blueprint.json'
d=json.load(open(f))
for s in d.get('steps',[]):
    print('step', s.get('index'), s.get('title')[:40], '->', s.get('state'))
"

# Check kanban task statuses
python3 -c "
import sqlite3,os
db=os.path.expanduser('~/.hermes/kanban.db')
c=sqlite3.connect(db)
for p in ['mnemosyne','autopilot','aires','agora','edgewalker']:
    rows=c.execute('SELECT status,COUNT(*) FROM tasks WHERE id LIKE ? GROUP BY status',(f'{p}%',)).fetchall()
    print(p, dict(rows))
"
```

## Common Pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| Poller only handles `pending` | Tasks stuck at `in_progress`, chain never advances | Poller must execute `in_progress` tasks (fixed) |
| Poller completes chain for Phase 0 only | Phase 1 stalls forever | Poller must call `chain_enforce complete` for ALL phases (fixed) |
| Dispatcher not syncing | Kanban shows `active` but chain is `locked` | Run `_sync_kanban_with_chain()` each cycle |
| No agents spawned | No tasks assigned, agents dir empty | Run `spawn-crew-agents.py <project> <crew-name>` first |
| Chain dir mismatch | `chain_enforce.py` can't find chain | Patched to search `.crew-*/.blueprint-chain/` first |

## What the Agent Does NOT Do

The agent does **NOT** hand-code project files. The kanban/chain/blueprint system drives the work:
- Blueprint → Checklist → Chain → Kanban tasks → Dispatcher → Poller → Agent executes
- Each phase's deliverables are defined in the checklist, enforced by chain validators
- The agent's role: ensure the orchestration layer is running and healthy