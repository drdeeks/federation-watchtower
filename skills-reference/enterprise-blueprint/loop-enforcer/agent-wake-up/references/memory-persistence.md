# Memory & Persistence Reference

## Memory Tiers

| Tier | Purpose | Example |
|------|---------|---------|
| HOT | Active task context | Current kanban task, working files |
| WARM | Session-level | Recent decisions, temporary state |
| COLD | Durable facts | User preferences, environment quirks |
| FROZEN | Archived | Completed task logs, old sessions |

## What Goes in Memory

### DO Save
- User preferences and corrections
- Environment facts (OS, tools, paths)
- Tool quirks and workarounds
- Stable conventions
- Provider status changes

### DO NOT Save
- Task progress or outcomes
- Completed work logs
- Temporary task context
- Session-specific context
- Anything stale in < 7 days

## Memory Format

```markdown
- Fact 1: Specific, declarative, compact
- Fact 2: Another durable fact
- Fact 3: Tool quirk discovered today
```

## Session Search

```python
# Find past sessions
session_search(query="docker networking", limit=3)

# Browse recent
session_search()

# Read specific session
session_search(session_id="abc123")
```

## Workspace Persistence

- `<agent-home>/` — Global config, skills, memory
- `<agent-home>/profiles/<name>/` — Per-profile config
- `~/agent-workspaces/workspaces/<project>/` — Project workspaces
- `<agent-home>/kanban/` — Task database

## Backup Strategy

```bash
# Backup critical files
tar czf hermes-backup-$(date +%Y%m%d).tar.gz \
  <agent-home>/config.yaml \
  <agent-home>/memory/ \
  <agent-home>/skills/ \
  ~/agent-workspaces/workspaces/
```
