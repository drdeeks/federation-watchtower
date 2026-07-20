# Crew Workspace Structure

## Per-Agent Workspace Layout

```
crew-workspace/
├── agents/
│   ├── <agent-id>/
│   │   ├── .agent/
│   │   │   ├── constitution.yaml       # Loaded at t=0
│   │   │   ├── genesis.md              # Agent's origin story
│   │   │   ├── habits/
│   │   │   │   ├── identity-enforcement.yaml
│   │   │   │   ├── tool-enforcement.yaml
│   │   │   │   ├── reflective-loop.yaml
│   │   │   │   ├── blueprint-chain-enforcement.yaml
│   │   │   │   ├── self-healing-habit.yaml
│   │   │   │   └── validation-over-syntax.yaml
│   │   │   ├── logs/habit-violations.jsonl
│   │   │   ├── metrics/
│   │   │   └── templates/tool-enforcement/
│   │   ├── tools/                      # 5 required tools
│   │   ├── memory/
│   │   │   ├── daily/
│   │   │   ├── weekly/
│   │   │   ├── long-term/MEMORY.md
│   │   │   └── knowledge-index.json
│   │   ├── agent_runtime.py
│   │   ├── enforcer_daemon.py
│   │   ├── memory_curator.py
│   │   └── start-agent.sh
│   └── <another-agent-id>/             # Each agent isolated
├── shared/                             # Development mode: shared workspace
│   ├── blueprints/
│   ├── checklists/
│   └── knowledge-index.json
├── .enforcer-registry.json
├── crew.json
└── CHANGELOG.md
```

## Mode Differences

| Mode | Workspace | Persistence | Secrets |
|------|-----------|-------------|---------|
| **development** (default) | `crew/<id>/shared/` | Ephemeral | Placeholders |
| **production** | `crew/<id>/agents/<id>/` | Persistent (Ventoy/USB) | Enforcer-managed |

## Required Tools Per Agent

1. `terminal` - Shell execution
2. `file` - File operations
3. `web` - Web search/extract
4. `skills` - Skill loading
5. `session_search` - Session recall

## Enforcer Daemon

Each agent runs a private enforcer daemon on Unix socket:
- Socket: `{workspace}/.agent/enforcer.sock`
- RPC methods: `validate_workspace`, `execute_tool`, `heartbeat`
- Validates: constitution hash, workspace hygiene, chain state
- Logs: `{workspace}/.agent/logs/habit-violations.jsonl`

## Memory Pipeline Structure

```
memory/
├── daily/           # Raw events, tagged with identity context
├── weekly/          # Synthesized patterns (promoted from daily)
├── long-term/       # Lessons shaping character (promoted from weekly)
│   └── MEMORY.md    # Curated long-term lessons
└── knowledge-index.json  # Semantic search index
```

## Promotion Schedule

- **Daily → Weekly**: Every 7 days, curator synthesizes patterns
- **Weekly → Long-term**: Every 30 days, curator extracts character lessons
- **Knowledge Index**: Updated on every long-term promotion