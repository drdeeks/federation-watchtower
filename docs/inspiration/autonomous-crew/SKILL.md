---
name: autonomous-crew
description: Integrate agent identity architecture as the first layer in autonomous
  crew orchestration. Hardwires identity constitution (Layer 1, loaded at t=0), internalized
  habits, enforcer daemon, and memory pipeline into every crew agent at creation time.
  Includes knowledge sharing system with dual-mode workspaces, agent-attributed documents,
  semantic indexing, and structured agent communication. Enterprise-grade with skill-creator
  validation.
version: 1.2.5
license: MIT
metadata:
  category: devops
  tags:
  - autonomous-crew
  - agent-identity
  - first-layer-architecture
  - identity-constitution
  - enforcer-daemon
  - internalized-habits
  - memory-pipeline
  - crew-knowledge
  - agent-communication
  - semantic-indexing
  - knowledge-sharing
  - document-formatting
  - platform-agnostic
  - blueprint-chain-integration
  - self-healing
  - validation-over-syntax
  depends_on:
  - agent-identity-architecture
  - tool-enforcement
  - loop-enforcer
  - enterprise-blueprint
  provides:
  - crew-agent-with-identity
  - identity-first-crew-initialization
  - enforcer-per-agent
  - habit-gated-crew-operations
  - crew-knowledge-sharing
  - agent-communication-protocol
  - semantic-search-integration
  - blueprint-driven-crew-init
  - self-healing-accuracy-enforcement
  - validation-over-syntax
  - knowledge-indexer
  - document-creation
  - cross-agent-sync
  compatible_with:
  - openclaw-gateway
---

# Autonomous Crew Integration — Identity-First Architecture

**The autonomous crew system requires identity as Layer 1.** Every agent spawned in a crew gets:
- Constitution loaded at t=0 (before any tool access)
- 4 internalized habits (identity-enforcement, tool-enforcement, reflective-loop, blueprint-phase-gate)
- Private enforcer daemon (Unix socket RPC, workspace ownership)
- Memory pipeline (daily → weekly → long-term + knowledge index)
- Builder code registration (ERC-8021) with identity attestation

## Functional Autonomous Loop

Use `scripts/autonomous-loop.py` as the default runner for real autonomous work.
It works with one shared workspace and one or more logical agents by running a
builder pass followed by an independent reviewer pass for each active chain
item. It writes live status, child PID, elapsed time, timeout, stdout log,
evidence, and review files. It advances the chain only after the review file
ends with `VERDICT: PASS`.

Single-agent project loop:

```bash
python3 scripts/autonomous-loop.py \
  --root /path/to/project \
  --chain /path/to/project/.chain/project-blueprint.json \
  --chain-name project-blueprint \
  --preflight "python3 -m unittest discover" \
  --cycles 0
```

Multi-agent/reviewer loop with local Docker, package installers, and servers:

```bash
python3 scripts/autonomous-loop.py \
  --root /path/to/project \
  --chain /path/to/project/.chain/project-blueprint.json \
  --chain-name project-blueprint \
  --preflight "python3 scripts/full_blueprint_status.py" \
  --preflight "docker version --format {{.Server.Version}}" \
  --bypass \
  --cycles 0
```

Monitor without touching the run:

```bash
cat /path/to/project/.agent/runtime/autonomous-crew/autonomous-crew-status.json
```

Operational rules:
- Keep all agents in one shared workspace unless production isolation is
  explicitly required.
- Provision dependencies in `--preflight` before delegating to the builder or
  reviewer.
- Never complete a chain item from builder output alone; require the independent
  review file to contain final line `VERDICT: PASS`.
- If Docker, network, local ports, or package installs are required, use
  `--bypass` or an equivalent trusted external sandbox so validation is real.
- Treat `task-dispatcher.py` and `task-poller.py` as legacy Hermes/Kanban
  integration scripts. Do not use them as the default autonomous execution loop.

## Crew Mode Flag

| Mode | Workspace | Persistence | Secrets | Use Case |
|------|-----------|-------------|---------|----------|
| **development** (default) | Shared workspace, `crew/<id>/shared/` | Ephemeral | Placeholders | One-time spinup, rapid iteration |
| **production** | Per-agent subdirs, `crew/<id>/agents/<id>/` | Persistent (Ventoy/USB) | Enforcer-managed | Long-term engagement, real integrations |

```bash
# Development crew
python3 scripts/init-crew.py hackathon-2026-dev --mode development

# Production crew
python3 scripts/init-crew.py hackathon-2026-prod --mode production

# Switch modes
python3 scripts/transition-crew.py --source dev --target prod --mode development-to-production --preserve-all
```

---

## Knowledge Sharing System (Standalone or Crew-Integrated)

**Dual-mode workspaces with agent-attributed documents, semantic indexing, and structured communication.**

### Standalone Agent Usage

For single agents NOT in a crew, initialize a knowledge workspace:

```bash
# Quick initialization (symlinks knowledge system into current directory)
bash scripts/init-knowledge-workspace.sh my-agent-id

# Or with full crew structure for future promotion
bash scripts/init-knowledge-workspace.sh my-agent-id --mode full
```

### Crew Integration

When used within a crew, knowledge system automatically integrates with crew orchestration:

```bash
# Initialize crew with knowledge system
python3 scripts/init-crew.py my-project --mode development --agents ui-a1b2 integration-b2c3

# Knowledge is automatically available to all crew agents
bash scripts/knowledge-indexer.sh index
bash scripts/knowledge-comm.sh send --from ui-a1b2 --to integration-b2c3 --subject "API contract" --body "Need to align..."
```

### Knowledge System Features

| Feature | Standalone | Crew-Integrated |
|---------|------------|-----------------|
| **Document Creation** | `knowledge-doc.sh` with agent context | Auto-attributed to agent |
| **Knowledge Indexing** | `knowledge-indexer.sh` local index | Crew-wide index with agent filtering |
| **Communication** | `knowledge-comm.sh` direct messages | Threaded crew communication |
| **Semantic Search** | Optional Turbopuffer integration | Crew-wide semantic vectors |
| **Cross-Agent Sync** | N/A | `knowledge-sync.sh` syncs knowledge |

### Document Format Standard

Every document follows standardized format with agent attribution. See `references/templates/knowledge/document-template.md` for template.

### Knowledge Scripts

| Script | Purpose | Standalone | Crew |
|--------|---------|------------|------|
| `scripts/knowledge-indexer.sh` | Index/search knowledge base | ✅ | ✅ |
| `scripts/knowledge-comm.sh` | Agent communication protocol | ✅ | ✅ |
| `scripts/knowledge-doc.sh` | Create formatted documents | ✅ | ✅ |
| `scripts/knowledge-sync.sh` | Sync knowledge across agents | ✅ | ✅ |

### Category Schema

| Category | Sub-categories | Doc Types |
|----------|----------------|-----------|
| `architecture` | system-design, data-model, api-design | decisions, specs |
| `api` | rest, graphql, grpc, webhooks | specs, decisions |
| `ui` | components, design-system, accessibility | specs, learnings |
| `infra` | deployment, monitoring, scaling | decisions, specs |
| `process` | workflow, communication, review | learnings, comms |
| `debugging` | root-cause, performance, errors | reasoning, learnings |
| `research` | exploration, spikes, evaluation | learnings, specs |

See `references/templates/knowledge/` for complete documentation.

---

## Architecture: Identity as Crew Foundation

```
CREW ORCHESTRATION LAYER
  Blueprint → CrewManager → Agent Spawning → Checkpoint/Rollback
                      │
                      ▼
IDENTITY LAYER (Layer 1)
  Constitution (t=0) │ Habits (internalized) │ Enforcer (daemon)
                      ▼
MEMORY PIPELINE (Layer 2)
  daily/ → weekly/ → long-term/ → knowledge/
                      ▼
AGENT RUNTIME (Layer 3+)
  Tools → Skills → Reasoning → Planning → External APIs
```

---

## Blueprint-Driven Crew Initialization

```bash
# Full pipeline: validate blueprint → generate checklist → create chain → spawn agents → wire kanban → start dispatcher
python3 scripts/init-crew-from-blueprint.py <blueprint.md> <crew-id> [--mode dev|prod]
```

### Pipeline Steps

1. **Validate Blueprint** — `validate-blueprint.py` (0 FAIL required)
2. **Generate Checklist** — `generate-checklist.py` from blueprint
3. **Parse Phases** — `parse-checklist-phases.py` extracts phases with tags/flags
4. **Create Loop-Enforcer Chain** — `create-blueprint-chain.py` creates `.chain/<project>-blueprint.json`
5. **Generate Phase Validators** — `generate-phase-validators.py` creates deliverable validators (not syntax)
6. **Wire Kanban to Chain** — `wire-kanban-to-chain.py` creates tasks wired to chain steps
7. **Spawn Agents** — Each with identity layer + assigned chain step
8. **Start Dispatcher** — Embedded gateway dispatcher reads chain, dispatches next phase

See `references/blueprint-chain-integration.md` for complete details.

---

## Blueprint Chain Structure (Loop-Enforcer Integration)

Each project's blueprint becomes a **loop-enforcer chain**:
- **Steps** = Blueprint phases (Phase 0 through Phase N)
- **Marker files** = `.phase-{n}-{feature_flag}.marker` per phase
- **Validators** = Phase-specific validation scripts (deliverables, not syntax)
- **State machine** = locked → active → pending_verify → verified → complete
- **Agent assignment** = Each phase step assigned to specific agent profile

See `references/blueprint-chain-integration.md` for chain creation, validators, kanban wiring.

---

## Phase Validators: Beyond Syntax (Validation ≠ Syntax)

Phase validators check **DELIVERABLES**, not syntax. Four-tier validation:

1. **Syntax** (necessary but insufficient)
2. **Contract compliance** (interface + behavior)
3. **Functional completeness** (delivers what spec promises)
4. **Character alignment** (honors agent's constitution)

See `references/validation-over-syntax.md` for complete validation framework.

---

## Self-Healing / Accuracy Enforcement

Agent runtime runs self-healing loop every 5 minutes checking:
- Enforcer daemon health
- Constitution hash (tamper detection)
- Chain integrity
- Memory pipeline promotion
- Habit violations

See `references/self-healing-architecture.md` for integrity checks, recovery procedures, alerting.

---

## Agent Identity: Internal Character Guidance

The identity layer is **not a validator** — it's the agent's **internalized self-model** that gates EVERY reasoning step before any tool use. See `references/crew-constitution.md` for constitution template and `references/templates/habits/` for habit definitions.

---

## Memory Pipeline Integration (Identity-Aware)

Memory pipeline records actions with agent identity, constitution hash, and reflections. Promotes from daily → weekly → long-term memory with knowledge indexing.

See `references/crew-memory-pipeline.md` for complete pipeline configuration.

---

## Kanban Dispatcher Integration

Dispatcher reads from blueprint chain and assigns tasks to agents based on chain state. Workers must enforce chain check before work, verify+complete after.

See `references/chain-enforcement-integration.md` for worker lifecycle and chain enforcement.

---

## Habit Integration in Crew Operations

### Before Any Tool Invocation
1. IDENTITY HABIT: Verify constitution hash matches
2. TOOL HABIT: Validate workspace hygiene
3. RPC to enforcer (approves/denies)
4. Execute if approved
5. REFLECTIVE HABIT: Post-execution reflection

### Crew Phase Gates (Loop Enforcer Integration)
Phase transitions require `claim_completion()` from all agents.

### Heartbeat Validation (Every 5 min)
Enforcer daemon validates: constitution hash, workspace integrity, chain state, habit metrics.

See `references/templates/habits/` for habit definitions and `references/crew-workspace-structure.md` for workspace layout.

---

## Enforcer Workspace

See `references/crew-workspace-structure.md` for complete layout including per-agent dirs, memory pipeline, enforcer daemon, required tools.

---

## Integration with Existing Skills

### agent-identity-architecture (REQUIRED)
Provides: `enforcer_daemon.py`, `agent_runtime.py`, `memory_curator.py`, constitution template, habit YAMLs, tool templates.

### agent-workspace-enforcement
Validates workspace structure matches identity requirements. Runs as part of tool-enforcement habit.

### loop-enforcer
- Phase gates call `agent.claim_completion()` → triggers reflective-loop
- **Enforces sequential dependency chains** — blueprint phases as chain steps
- **Validator scripts** per phase gate — deliverables, not syntax
- **Chain state persistence** — `.chain/<project>-blueprint.json` tracks completion

### enterprise-blueprint-validation
- Blueprint validation includes identity layer check
- `FEAT_IDENTITY_LAYER` flag gates crew orchestration
- Generates checklists from blueprints (`generate_checklist.py`)
- Validates blueprints before crew initialization (`validate_blueprint.py`)

### kanban-orchestrator
- Task decomposition patterns with anti-temptation rules
- Chain-enforced phased tasks pattern (see loop-enforcer chain enforcement)
- Dispatcher reads chain state, workers enforce chain checks

---

## Scripts Reference

### Core Scripts
| Script | Purpose |
|--------|---------|
| `scripts/create-crew-agent.sh` | Create crew agent with full identity layer |
| `scripts/init-crew.py` | Initialize autonomous crew workspace |
| `scripts/init-crew-from-blueprint.py` | Full blueprint→crew pipeline |
| `scripts/verify-crew-identity.sh` | Verify all agents have operational identity |
| `scripts/crew-heartbeat.sh` | Aggregate heartbeat status |
| `scripts/install-identity-skill.py` | Install agent-identity-architecture |
| `scripts/create-blueprint-chain.py` | Create loop-enforcer chain from blueprint |
| `scripts/generate-phase-validators.py` | Generate phase validator scripts |
| `scripts/wire-kanban-to-chain.py` | Wire kanban tasks to chain steps |
| `scripts/chain_enforce.py` | Chain enforcement helper for kanban workers (check/complete/status) |
| `scripts/autonomous-loop.py` | Portable one-agent or builder/reviewer autonomous loop with live heartbeat, preflight, evidence, independent review, and chain advance |
| `scripts/self-healing-loop.py` | Run integrity checks (constitution, chain, memory, habits) |
| `scripts/crew-manager.py` | Create crews with blueprint enforcement, identity layer, and model configuration |
| `scripts/spawn-crew-agents.py` | Spawn all agents from blueprint.json |
| `scripts/start-crew-enforcers.py` | Start enforcer daemons for all agents in crew |
| `scripts/task-dispatcher.py` | Legacy Hermes/Kanban integration: sync kanban with chain state; unlock + assign active-phase subtasks |
| `scripts/task-poller.py` | Legacy Hermes/Kanban integration: per-project poller that queries tasks by project id and drives the configured runtime |
| `scripts/generate-tasks-from-checklist.py` | Generate granular kanban tasks from checklist.md |
| `scripts/progress-monitor.py` | Monitor project health, tests, API, chain progress |
| `scripts/enforcer_daemon.py` | Per-agent enforcer daemon (identity, habits, constitution) |
| `scripts/agent_runtime.py` | Agent runtime loop (identity, habits, memory, skills) |
| `scripts/memory_curator.py` | Memory pipeline (short/long term, semantic index) |
| `scripts/start-agent.sh` | Agent startup script (validates workspace, starts runtime) |

| `scripts/init-dev-crew.sh` | Initialize development crew workspace (ephemeral, shared) |
| `scripts/init-prod-crew.sh` | Initialize production crew workspace (persistent, per-agent) |
| `scripts/test_functional.py` | Functional test suite for the crew pipeline |
| `scripts/__init__.py` | Package marker for python imports |

### Blueprint Scripts
| Script | Purpose |
|--------|---------|
| `validate-blueprint.py` | Validate blueprint (from enterprise-blueprint-validation) |
| `generate-checklist.py` | Generate checklist from blueprint |
| `parse-checklist-phases.py` | Extract phases for chain creation |

### Transition Scripts
| Script | Purpose |
|--------|---------|
| `scripts/transition-crew.py` | Dev↔Prod migration preserving all data |
| `scripts/duplicate-crew.py` | Selective fork with new IDs |
| `scripts/crew-config-manager.py` | Active crew configs, pointers |

### Knowledge Scripts
| Script | Purpose | Standalone | Crew |
|--------|---------|------------|------|
| `scripts/knowledge-indexer.sh` | Index/search knowledge base | ✅ | ✅ |
| `scripts/knowledge-comm.sh` | Agent communication protocol | ✅ | ✅ |
| `scripts/knowledge-doc.sh` | Create formatted documents | ✅ | ✅ |
| `scripts/knowledge-sync.sh` | Sync knowledge across agents | ❌ | ✅ |

### Templates
- `references/templates/crew/` — Constitution, habits, agent config, phases, memory, builder code, agent types, enforcer registry
- `references/templates/habits/` — Identity-enforcement, tool-enforcement, reflective-loop, crew-phase-gate, blueprint-chain-enforcement, self-healing-habit, validation-over-syntax
- `references/templates/knowledge/` — Document template, dev/prod workspace templates

---

## Verification Checklist (Enterprise)

- [ ] Every crew agent has `.agent/constitution.yaml` readable at t=0
- [ ] Every crew agent has 4 internalized habits in `.agent/habits/`
- [ ] Every crew agent has running enforcer daemon on Unix socket
- [ ] Every crew agent has memory pipeline initialized
- [ ] Every crew agent has builder code with identity attestation
- [ ] Phase transitions require `claim_completion()` from all agents
- [ ] Heartbeat aggregation shows all agents healthy
- [ ] Zero hardcoded paths (uses `$WORKSPACE_ROOT`, `$HOME`)
- [ ] Crew transition preserves identity, memory, knowledge, communications
- [ ] Knowledge indexer finds all agent documents
- [ ] Chain enforcement wired into KANBAN_GUIDANCE step 2b
- [ ] All phase tasks enforce chain check before work, verify+complete after

---

## References

### Core References
- `references/verified-implementation.md` — Canonical implementation (synthesis-1)
- `references/crew-workspace-structure.md` — Per-agent workspace layout
- `references/blueprint-chain-integration.md` — Blueprint to chain wiring
- `references/self-healing-architecture.md` — Self-healing loop design
- `references/validation-over-syntax.md` — Deliverable validation vs syntax
- `references/crew-memory-pipeline.md` — Memory pipeline configuration
- `references/crew-constitution.md` — Base constitution template
- `references/crew-phases.md` — Blueprint phase definitions and gates
- `references/crew-agent-types.md` — Agent type catalog
- `references/crew-habits.md` — Habit definitions index
- `references/crew-builder-code.md` — ERC-8021 integration with identity
- `references/crew-enforcer-registry.md` — Enforcer registry operations
- `references/chain-enforcement-integration.md` — Chain enforcement integration with kanban/loop-enforcer
- `references/skill-creator-validation.md` — Enterprise skill validation workflow with skill_enhance.py

### Dispatcher/Poller Execution Model (verified 2026-07-09)
- `references/task-dispatcher-poller.md` — The execution model: dispatcher sync/unlock/assign, per-project poller contract
- `references/dispatcher-poller-orchestration.md` — Orchestration walkthrough of the dispatcher + poller pair
- `references/poller-chain-fix.md` — v1.1.15 fix: chain advance for ALL phases (not just Phase 0)
- `references/chain-enforcement-poller-fix.md` — Chain-enforcement integration on the poller side
- `references/session-2026-07-09-crew-poller-execution-stall.md` — Session: the assignee-query stall (query by project, never crew name)
- `references/status-reporting-and-kanban-query.md` — Status reporting + correct kanban query patterns
- `references/federation-tv-integration.md` — Federation TV integration for crew visibility
- `references/federation-tv-command-center.md` — TV command-center wiring
- `references/templates/agent-model-map.json` — Agent→model mapping template consumed by the poller runtime

### Operational References (sessions, lessons, providers)
- `references/blueprint-enforcement-philosophy.md` — Why enforcement lives in the blueprint layer
- `references/chain-enforcement-crew-integration.md` — Chain enforcement wired into crew lifecycle
- `references/chain-reset-procedure.md` — Safe chain reset procedure
- `references/enterprise-validation-pitfalls.md` — Validation pitfalls observed in production
- `references/model-quota-and-blueprint-json.md` — Model quota handling + blueprint.json notes
- `references/provider-configuration.md` — Provider configuration walkthrough
- `references/providers-and-model-config.md` — Providers + model config reference
- `references/self-healing-and-monitoring-setup.md` — Self-healing and monitoring setup
- `references/self-healing-progress-monitor.md` — Progress monitor design
- `references/session-2026-07-09-chain-location-and-sync.md` — Session: chain location + sync
- `references/session-2026-07-09-dispatcher-poller-sync-fix.md` — Session: dispatcher/poller sync fix
- `references/session-2026-07-09-mnemosyne-phase1-implementation.md` — Session: memory phase 1
- `references/session-2026-07-09-self-healing-vs-crew-work.md` — Session: self-healing vs crew work
- `references/chain-state-fix-and-production-verification.md` — Chain state fix + production verification
- `references/lessons/configurable-models.md` — Lesson: configurable models
- `references/lessons/skill-update-workflow.md` — Lesson: skill update workflow

### Knowledge References
- `references/templates/knowledge/category-schema.md` — Category/tag taxonomy for knowledge documents
- `references/templates/knowledge/communication-protocol.md` — Structured agent-to-agent messaging spec
- `references/templates/knowledge/document-format.md` — Document format standard with agent attribution
- `references/templates/knowledge/semantic-integration.md` — Turbopuffer semantic search integration
- `references/templates/knowledge/crew-status.md` — Crew health & knowledge status dashboard

### Templates
- `references/templates/crew/crew-phases.yaml` — Phase config template
- `references/templates/crew/crew-constitution.yaml` — Constitution template (YAML)
- `references/templates/crew/crew-habits.yaml` — Habit definitions (YAML)
- `references/templates/crew/crew-agent-config.yaml` — Enforcer config template
- `references/templates/crew/crew-memory-pipeline.yaml` — Memory pipeline template
- `references/templates/crew/crew-builder-code.yaml` — Builder code template
- `references/templates/crew/crew-agent-types.yaml` — Agent types template
- `references/templates/crew/crew-enforcer-registry.yaml` — Registry template
- `references/templates/habits/identity-enforcement.yaml` — Identity habit template
- `references/templates/habits/tool-enforcement.yaml` — Tool habit template
- `references/templates/habits/reflective-loop.yaml` — Reflective habit template
- `references/templates/habits/crew-phase-gate.yaml` — Crew phase gate habit
- `references/templates/habits/blueprint-chain-enforcement.yaml` — Blueprint chain enforcement habit
- `references/templates/habits/self-healing-habit.yaml` — Self-healing habit template
- `references/templates/habits/validation-over-syntax.yaml` — Validation over syntax habit

### Knowledge Templates
- `references/templates/knowledge/document-template.md` — Document template with placeholders
- `references/templates/knowledge/crew-workspace-dev.yaml` — Development crew workspace template
- `references/templates/knowledge/crew-workspace-prod.yaml` — Production crew workspace template
