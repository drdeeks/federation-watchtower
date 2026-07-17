# Kanban System Reference

## Task Lifecycle

```
created → ready → running → done
                  ↘ blocked → ready (re-dispatch)
                  ↘ crashed → ready (reclaim)
```

## Key Commands

```bash
# Create task with dependency
hermes kanban create "title" --assignee <profile> --parent <parent_id>

# List tasks
hermes kanban list
hermes kanban list --status=ready
hermes kanban list --status=running

# Dispatch ready tasks
hermes kanban dispatch

# Reclaim stuck tasks
hermes kanban reclaim <task_id>

# Check task details
hermes kanban show <task_id>

# Check worker logs
hermes kanban log <task_id> --tail 20
```

## Task Fields

| Field | Description |
|-------|-------------|
| id | Unique task identifier (t_XXXXXXXX) |
| title | Human-readable task name |
| assignee | Profile name for the worker |
| parents | Task IDs that must complete first |
| status | ready, todo, running, done, blocked |
| workspace | scratch, worktree, or dir:path |

## Profile Requirements

Each profile MUST have:
1. `config.yaml` with working model/provider
2. `skills/` symlink to <agent-home>/skills
3. Correct model (<your-primary-model>)

## Self-Healing

When workers crash or loop:
1. `hermes kanban reclaim <task_id>` — reset task
2. Check profile config is valid
3. `hermes kanban dispatch` — respawn worker

## Pitfalls

- Workers write to PROJECT dirs, not scratch workspaces
- Dead API keys = silent failure (no output)
- `--parent` is singular (repeatable), not `--parents`
- YAML dump destroys config formatting (use regex)
