# Blueprint Enforcement Philosophy

## Blueprints ARE the Project

The blueprint is NOT a description of what the project should be. The blueprint IS the project. It must be extensive enough that:

1. **Every deliverable is specified** — What files must exist, what they must contain, what tests must pass
2. **Every phase has validation gates** — Not just "implement feature X" but "verify feature X exists, passes tests, has documentation"
3. **Every agent knows exactly what to do** — No ambiguity, no "figure it out", no placeholder implementations
4. **Every completion is verifiable** — Chain enforcement validates DELIVERABLES, not just phase markers

### Anti-Pattern: Blueprint as Description
```
# WRONG — blueprint describes what the project COULD be
"Phase 1: Implement the memory system with knowledge graph and semantic search"

# RIGHT — blueprint specifies what MUST exist
"Phase 1: Core Store & Embedding Engine
Deliverables:
- src/engines/embedding-engine.js (must export EmbeddingEngine class)
- src/engines/memory-store.js (must export MemoryStore class with add/get/search/delete)
- tests/embedding-engine.test.js (must pass: npm test)
- tests/memory-store.test.js (must pass: npm test)
Validation Gate:
- All 4 files exist and are non-empty
- npm test passes with 0 failures
- No hardcoded paths or secrets"
```

## Project Manager Is the Orchestrator

The project-manager (from `crews/project-manager/`) is NOT just another agent. It is THE orchestrator responsible for:

1. **Outlining the blueprint** — Creating the master specification that IS the project
2. **Enforcing the blueprint** — Running validation gates, ensuring deliverables exist
3. **Managing the crew** — Assigning agents, tracking progress, blocking when chain is locked
4. **Quality enforcement** — Self-review → Peer review → PM validation → User approval

### The Flow
```
User Request → PM Creates Blueprint → Blueprint → Checklist → Chain → Kanban → Agents Execute
                                                                    ↑
                                                            PM Enforces
```

The PM doesn't just assign work and hope for the best. The PM:
- Validates the blueprint before work starts
- Ensures each phase has specific deliverables
- Runs validation gates after each phase
- Blocks phases that don't meet standards
- Refuses to mark phases complete without verified deliverables

## Kanban + Agents Enforce the Blueprint

The kanban is NOT a todo list. It's an enforcement mechanism:

1. **Chain steps** = Blueprint phases (sequential dependency)
2. **Kanban tasks** = Work items wired to chain steps
3. **Agents** = Workers with identity layer, enforcing habits
4. **Validation gates** = Check deliverables exist, not just code syntax

### Worker Lifecycle (Enforced)
```
Agent receives task → Chain check (can_proceed?) → Do work → Validate deliverables → Chain complete → Next phase
       ↓                      ↓                        ↓              ↓                      ↓
  Identity layer        Locked = STOP            Habits gate    Checklist verifies    Unlocks next
  Constitution          Active = PROCEED         Tool enforce   All files exist       Phase N+1
```

## Key Principle: Implementation Over Documentation

When a skill references scripts that don't exist → CREATE THEM
When a skill describes behavior that isn't wired up → WIRE IT
When a checklist has unchecked items → DO THE WORK
When a chain says "complete" but deliverables are missing → RESET AND REDO

Documentation without implementation is waste. The user's frustration signal: "these are all just a sham and a waste of time."
