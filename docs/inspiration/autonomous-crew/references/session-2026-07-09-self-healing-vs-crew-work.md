# Self-Healing Scope vs Crew Agent Responsibilities

**Session:** 2026-07-09
**Issue:** User corrected: "these should all be taken care of and fixed by the crews themselves! if they don't have it, they should be smart enough to traceback the source of the issue, and fix it."

## Key Distinction

| Layer | Responsibility | Mechanism |
|-------|---------------|-----------|
| **Self-Healing Loop** | Crew infrastructure health only | `self-healing-loop.py` (30s/5min intervals) |
| **Crew Agents** | Project-level work (tests, builds, API keys, code) | Task dispatcher → kanban → task poller → chain enforcement |

## Self-Healing Loop Scope (ONLY)

1. **Enforcer daemon health** — Restart if heartbeat fails
2. **Constitution hash** — Detect tampering, restore from git
3. **Chain integrity** — No gaps in phase progression
4. **Memory pipeline** — Promote daily → weekly → long-term
5. **Habit violations** — Drift from internalized habits

## What Self-Healing Does NOT Fix

| Issue | Who Fixes | How |
|-------|-----------|-----|
| Test failures (`npm test`) | Crew agents | Assigned task from dispatcher |
| Missing API keys in `.env` | Crew agents / human | `.env` configuration task |
| TypeScript compilation errors | Crew agents | Assigned task from dispatcher |
| Build failures | Crew agents | Assigned task from dispatcher |
| Linting issues | Crew agents | Assigned task from dispatcher |

## Crew Agent Workflow

1. **Task dispatcher** reads chain state, finds active phase
2. **Dispatcher** creates/unlocks subtasks from checklist (`generate-tasks-from-checklist.py`)
3. **Dispatcher** assigns all subtasks + validation to available agents
4. **Task poller** on each agent picks up `in_progress` task
5. **Agent** runs `chain_enforce.py check <project> <phase>`
6. **Agent** executes work (writes code, runs tests, fixes failures)
7. **Agent** runs `chain_enforce.py complete <project> <phase>`
8. **Dispatcher** detects completion → advances chain → unlocks next phase

## Why This Matters

- Self-healing is **infrastructure watchdog** (keep the crew alive)
- Crew agents are **workforce** (do the actual project work)
- Confusing the two leads to: self-healing trying to fix code (wrong layer) OR agents not doing their job because "self-healing will handle it"

**Design Principle:** If a human would fix it by writing code/config, it's a crew agent task. If a human would fix it by restarting a daemon/checking a hash, it's self-healing.