# Model Quota Tracking and Blueprint JSON Generation

## Model Quota Tracking (model.json)

Every multi-project workspace MUST have a `model.json` at the root that tracks:
- Available models with tiers and capabilities
- Quota limits per model (RPM, TPM, daily requests)
- Current usage per project
- Recommended model assignments based on task type

### model.json Structure

```json
{
  "version": "1.0.0",
  "models": {
    "qwen3-max-preview": {
      "tier": "premium",
      "best_for": ["creative_writing", "complex_reasoning", "script_generation"],
      "daily_requests": 500,
      "current_usage": { "project-name": count }
    }
  },
  "projects": {
    "project-name": {
      "primary_model": "model-name",
      "models_used": ["model1", "model2"]
    }
  },
  "recommendations": {
    "model_selection_guide": { "task_type": "recommended_model" }
  }
}
```

### Why This Matters

Each model has a quota per model (not per API key). Without tracking:
- Premium models (qwen3-max-preview) can be exhausted quickly
- No visibility into which project is consuming quota
- No basis for model rotation decisions

The crew-manager.py reads model.json to populate blueprint.json token budgets.

---

## Crew Blueprint JSON (blueprint.json)

The crew-manager.py generates a complete `blueprint.json` for each crew that maps models to agents and tasks. This is the authoritative source for model assignments.

### blueprint.json Structure

```json
{
  "blueprint_id": "project_crew_001",
  "crew_name": "project-crew",
  "project_name": "project",
  "track": "Track N: Name",
  "token_budget": {
    "per_model_limit": 1000000,
    "rotation_strategy": "round_robin",
    "models_pool": ["model1", "model2"],
    "current_usage": { "model1": 0, "model2": 0 }
  },
  "agents": [
    {
      "agent_id": "project-role-1",
      "agent_type": "role",
      "display_name": "RoleName",
      "description": "What this agent does",
      "model": "assigned-model"
    }
  ],
  "success_criteria": ["criteria1", "criteria2"],
  "workflows": {
    "phases": [
      {"id": "phase_0", "name": "Foundation", "status": "active"}
    ]
  },
  "quality_gates": {
    "tests_must_pass": true,
    "documentation_required": true,
    "docker_deployment_required": true
  }
}
```

### Agent-to-Model Mapping

Each agent gets assigned a model based on:
1. Task complexity (creative → premium, simple → economy)
2. Model capabilities (vision → vl models, code → coder models)
3. Quota availability (check current_usage before assigning)

### Session Logs

Each crew creation generates a session log (`sessions/session-ses_*.md`) that documents:
- All actions taken during crew initialization
- Tool calls with inputs and outputs
- Model assignments and rationale
- Chain status and phase configuration

This provides a complete audit trail similar to session-ses_0d3e.md format.

---

## Integration with Crew Manager

The crew-manager.py script:
1. Reads model.json for project model assignments
2. Generates blueprint.json with agent-to-model mappings
3. Creates session log documenting all actions
4. Populates token_budget with model pool and rotation strategy

```bash
# Generate crew with blueprint.json
python3 scripts/crew-manager.py \
  --crew-name project-crew \
  --project-dir /path/to/project

# Output:
# - .crew-project-crew/blueprint.json (model mappings)
# - .crew-project-crew/sessions/session-ses_*.md (audit trail)
```
