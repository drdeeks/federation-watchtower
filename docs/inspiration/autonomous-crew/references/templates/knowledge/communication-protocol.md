# Crew Communication Protocol Specification

## Overview
Structured, traceable, searchable agent-to-agent communication with threading, priority, and search integration.

## Message Types

| Type | Purpose | Routing |
|------|---------|---------|
| `sync` | Status alignment, checkpoint coordination | Direct (to_agent) |
| `question` | Clarification, information request | Direct |
| `proposal` | Design proposal, RFC | Direct or broadcast |
| `decision` | Decision announcement, ratification | Direct or broadcast |
| `broadcast` | Crew-wide announcements, phase gates | All agents |
| `alert` | Urgent issues, blockers, regressions | Direct or broadcast |

## Message Format (Frontmatter)

```yaml
---
message_id: "comm-7f9a2b1c"
thread_id: "thread-3e8d1a9f"
from_agent: "ui-a1b2"
from_type: "ui"
to_agent: "integration-b2c3"
to_type: "integration"
crew_id: "hackathon-2026"
type: "sync"          # sync | question | proposal | decision | broadcast | alert
subject: "API contract for user auth"
priority: "normal"    # low | normal | high | urgent
timestamp: "2026-07-05T14:35:22Z"
tags: ["api", "oauth", "contract"]
---
```

## Threading

- Each message belongs to a thread (thread_id)
- Replies reference parent thread
- Thread metadata tracks participants, message count, last activity
- Max thread depth: 10

## Storage Layout

```
crew/shared/communications/
├── messages/           # Individual messages
│   ├── comm-7f9a2b1c.md
│   └── ...
├── threads/            # Thread views (rendered)
│   ├── thread-3e8d1a9f.md
│   └── ...
└── broadcasts/         # Broadcast messages
    ├── broadcast-a1b2c3d4.md
    └── ...
```

## Protocol Operations

### Send Direct Message
```bash
bash crew-comm.sh send \
  --from ui-a1b2 \
  --to integration-b2c3 \
  --subject "API contract for user auth" \
  --body "Need to align on OAuth2 token refresh endpoint..." \
  --type sync \
  --priority normal \
  --tags "api,oauth"
```

### Reply to Thread
```bash
bash crew-comm.sh reply \
  --thread thread-3e8d1a9f \
  --from integration-b2c3 \
  --body "Proposing /auth/refresh with 15min expiry..."
```

### Broadcast to All
```bash
bash crew-comm.sh broadcast \
  --from lead-x1y2 \
  --subject "Phase gate: planning → confirmation" \
  --body "All agents: confirm readiness..." \
  --priority high
```

### View Thread
```bash
bash crew-comm.sh thread --thread thread-3e8d1a9f
```

### List Messages
```bash
bash crew-comm.sh list --agent ui-a1b2
```

## Sync to Knowledge Index

Communications are synced to `shared/documents/communications/` for searchability:

```bash
bash crew-comm.sh sync
```

Creates indexed documents with:
- Agent attribution
- Thread context
- Full message body
- Tags for filtering

## Priority Semantics

| Priority | SLA | Use Case |
|----------|-----|----------|
| `low` | 24h | FYI, optional sync |
| `normal` | 4h | Standard coordination |
| `high` | 1h | Blocking issues, decisions needed |
| `urgent` | 15min | Production issues, regressions |

## Integration with Phase Gates

Phase gate transitions use broadcast messages:

```bash
# Lead agent broadcasts phase transition
bash crew-comm.sh broadcast \
  --from lead-x1y2 \
  --subject "Phase gate: planning → confirmation" \
  --body "All agents confirm readiness..." \
  --priority high \
  --tags "phase-gate,confirmation"

# Agents reply with readiness
bash crew-comm.sh reply \
  --thread thread-xyz \
  --from ui-a1b2 \
  --body "UI ready for confirmation phase"
```