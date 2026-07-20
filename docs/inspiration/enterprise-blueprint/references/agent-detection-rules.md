# Agent/Crew Detection Rules — Singular Source of Truth
#
# FOREVER SYSTEM §1: "One canonical location per concern. Not 'a readme mentions it.'
# One file, one service, one port, one skill — that IS the truth."
#
# This document IS the detection logic. Code in discover_agents.py implements this.
# If they diverge, this document wins and code must be fixed.

## Detection Philosophy

**FAIL-CLOSED (§4):** When identity is ambiguous, BLOCK with clear error.
"A guard that fails open is no guard."

**SINGULAR SOURCE (§1):** These rules exist in ONE place — this document.
discover_agents.py is the executable implementation. This document is the contract.

---

## POSITIVE AGENT IDENTIFICATION

A directory is an **AGENT** iff ALL of the following exist:

| # | Requirement | Path | Purpose |
|---|-------------|------|---------|
| 1 | Enforcer identity layer | `.agent/` (directory) | Root-owned, enforcer-managed |
| 2 | Agent constitution | `SOUL.md` (file) | Character foundations (§6) |
| 3 | Identity declaration | `agent.json` OR `crew.json` with matching `agent_id` | Self-identification |
| 4 | Model configuration | `agent-model-map.yaml` OR `crew-model-map.yaml` | Phase→model mapping (§6) |

### agent.json Schema
```json
{
  "agent_id": "ui-a1b2",
  "agent_type": "ui",
  "crew_id": "hackathon-2026",        // optional
  "model_map": "agent-model-map.yaml", // optional
  "created_at": "2026-07-14T14:30:00Z",
  "version": "1.0"
}
```

### Validation Rules
- `agent_id` in JSON MUST match directory name (or be explicitly mapped in crew.json)
- `.agent/` MUST be a directory (not symlink, not file)
- `SOUL.md` MUST have content > 100 chars (not empty template)
- If `crew.json` exists instead of `agent.json`, it MUST contain an `agents[]` array with an entry matching the directory name

---

## POSITIVE CREW IDENTIFICATION

A directory is a **CREW** iff ALL of the following exist:

| # | Requirement | Path | Purpose |
|---|-------------|------|---------|
| 1 | Crew roster | `crew.json` (file) | Canonical agent list |
| 2 | Agent workspaces | `crew/agents/*/.agent/` (directories) | Multiple agent identities |
| 3 | Crew metadata | `.crew-config.yaml` (file) | Crew-level config |
| 4 | Orchestration layer | `crew-model-map.yaml` (file) | Cross-agent model coordination |

### crew.json Schema
```json
{
  "crew_id": "prod-trading",
  "crew_mode": "production",           // "development" | "production"
  "created_at": "2026-07-14T14:30:00Z",
  "agents": [
    {
      "agent_id": "lead-x1y2",
      "agent_type": "lead",
      "model_map": "agent-model-map.yaml",
      "phases": ["PHASE-0", "PHASE-5"],
      "scope": "phase-owner"
    },
    {
      "agent_id": "ui-a1b2",
      "agent_type": "ui",
      "model_map": "agent-model-map.yaml",
      "phases": ["PHASE-2", "PHASE-3"],
      "scope": "module",
      "modules": ["MOD-005", "MOD-012"]
    }
  ],
  "shared_model_pool": { ... },       // optional
  "phase_gates": { ... }              // optional
}
```

### .crew-config.yaml Schema
```yaml
crew_id: "prod-trading"
crew_mode: "production"
created_at: "2026-07-14T14:30:00Z"
enforcer_registry: ".enforcer-registry.json"
secrets_dir: ".secrets/"
knowledge_dir: "crew/shared/knowledge/"
```

### Validation Rules
- `crew_id` MUST match directory name (or be explicitly set)
- `agents[]` MUST have at least 1 entry
- Each agent in `agents[]` MUST have a corresponding `crew/agents/<agent_id>/.agent/` directory
- Agent `model_map` SHOULD reference existing `agent-model-map.yaml` in agent workspace

---

## NEITHER (Project Directory)

If NEITHER agent NOR crew criteria are fully met:

| Classification | Condition |
|----------------|-----------|
| **project** | Contains blueprint.md, checklist.md, or project files but no identity markers |
| **ambiguous** | Partial markers (e.g., `.agent/` but no `SOUL.md`) — FAIL CLOSED |

### Fail-Closed Errors (Ambiguous Identity)
```
ERROR: Ambiguous identity at ./my-workspace
  Found: .agent/ directory ✓
  Missing: SOUL.md ✗
  Missing: agent.json/crew.json with agent_id ✗
  → Run 'interactive_setup' to initialize proper agent structure
```

---

## SUB-AGENT DETECTION

Nested agents within an agent's workspace:

| Requirement | Path |
|-------------|------|
| Nested identity | `<parent>/<subdir>/.agent/` (directory) |
| Constitution | `<parent>/<subdir>/SOUL.md` (file) |
| Identity | `<parent>/<subdir>/agent.json` with unique `agent_id` |

Sub-agents:
- Have their own phase assignments (inherited or overridden)
- Report to parent agent in hierarchy
- Discovered recursively by `discover_agents.py`

---

## DETECTION PRECEDENCE

When a directory could match multiple types:

1. **Agent inside crew** → Detected as crew member, not standalone agent
   - Parent has `crew.json` + `crew/agents/`
   - Agent workspace is `crew/agents/<agent_id>/`
   
2. **Standalone agent** → No parent crew markers
   - No `crew.json` in parent
   - No `crew/agents/` in parent

3. **Crew root** → Has `crew.json` + `crew/agents/` + `.crew-config.yaml`
   - Even if also has `.agent/` (legacy), crew takes precedence

---

## PROGRAMMATIC INTERFACE

```python
from scripts.discover_agents import detect_identity

result = detect_identity(Path("./my-workspace"))
# Returns:
# {
#   "type": "agent" | "crew" | "none",
#   "workspace": "/abs/path",
#   "agent_id": "...",
#   "agent_type": "...",
#   "crew_id": "...",
#   "agents": [...],           # for crew
#   "sub_agents": [...],       # for agent
#   "config_files": {...},
#   "errors": [...]            # if type == "none" or ambiguous
# }
```

### Exit Codes (for shell integration)
| Code | Meaning |
|------|---------|
| 0 | Valid agent detected |
| 1 | Valid crew detected |
| 2 | Project directory (no identity) |
| 3 | Error / ambiguous |

---

## INTEGRATION POINTS

| Consumer | Uses Detection For |
|----------|-------------------|
| `apply_blueprint.py` | Target selection (--target vs --crew) |
| `assign_agents.py` | Scope assignment from roster |
| `interactive_setup.py` | Auto-detect and pre-fill config |
| `chain_worker.py` | Agent context for model reminders |
| ACK Enforcer | Character affirmation (§6) |

---

## CHANGE PROTOCOL (Forever §3)

**NEVER** silently edit detection rules. Changes are LAYERS:

1. Create `agent-detection-rules.v2.md` with new rules
2. Update `discover_agents.py` to implement v2
3. Add supersedes pointer: `Supersedes: agent-detection-rules.md`
4. Test both v1 and v2 paths
5. Update references

Rollback = delete v2 file. Core v1 remains intact.