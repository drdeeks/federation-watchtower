# Hemlock Enterprise Agent Framework — Blueprint

**Version:** 1.0.0
**Last Updated:** 2026-05-17
**Status:** Final Source of Truth
**Repository:** /home/drdeek/projects/hemlock/

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Dual Mode Operation](#2-dual-mode-operation)
3. [Directory Structure](#3-directory-structure)
4. [Agent Workspace](#4-agent-workspace)
5. [Component Details](#5-component-details)
6. [Configuration](#6-configuration)
7. [Agent Lifecycle](#7-agent-lifecycle)
8. [Crew Management](#8-crew-management)
9. [Security Model](#9-security-model)
10. [MCP Integration](#10-mcp-integration)
11. [Health System](#11-health-system)
12. [Deployment](#12-deployment)
13. [Scripts Reference](#13-scripts-reference)
14. [Docker Architecture](#14-docker-architecture)
15. [Troubleshooting](#15-troubleshooting)

---

## 1. Architecture Overview

### 1.1 Core Philosophy

Hemlock is an enterprise-grade multi-agent runtime framework built on a dual-component architecture:

- **OpenClaw (Control Plane)** — Drives: gateway, MCP, platform routing, agent lifecycle management
- **Hermes (Cognition Layer)** — Thinks: agent loop, self-learning brain, tool execution

The separation of concerns ensures that control-plane operations (routing, authentication, session management) remain distinct from cognitive operations (reasoning, memory, tool use).

### 1.2 Full Data Flow

```
User → Telegram → OpenClaw Gateway → MCP → Hermes (Agent Loop/Brain) → MCP → OpenClaw → Gateway → Telegram → User
```

Detailed breakdown:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              EXTERNAL LAYER                                  │
│                                                                              │
│   User ──→ Telegram/Discord/Slack/WhatsApp ──→ OpenClaw Gateway (port 18789) │
│                                                                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CONTROL PLANE (OpenClaw)                         │
│                                                                              │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│   │   Gateway    │───→│    MCP       │───→│   Platform   │                  │
│   │   Server     │    │   Router     │    │   Routing    │                  │
│   └──────────────┘    └──────────────┘    └──────────────┘                  │
│        │                   │                                                    │
│        │              ┌────▼─────┐                                          │
│        │              │ Session  │                                          │
│        │              │ Manager  │                                          │
│        │              └──────────┘                                          │
│                                                                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ MCP Protocol
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          COGNITION LAYER (Hermes)                           │
│                                                                              │
│   ┌──────────────┐    ┌──────────────┐    ┌──────────────┐                  │
│   │  Agent Loop  │───→│    Brain     │───→│    Tool      │                  │
│   │  (Main)      │    │  (Reasoning) │    │  Execution   │                  │
│   └──────────────┘    └──────────────┘    └──────────────┘                  │
│        │                   │                   │                            │
│        ▼                   ▼                   ▼                            │
│   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐                   │
│   │   Memory     │   │   Skills     │   │   Tools      │                   │
│   │   (STM/LTM)  │   │   Registry   │   │   (scripts)  │                   │
│   └──────────────┘   └──────────────┘   └──────────────┘                   │
│                                                                              │
└──────────────────────────────────────┬──────────────────────────────────────┘
                                       │ MCP Protocol
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          RESPONSE PATH                                      │
│                                                                              │
│   Hermes → MCP → OpenClaw Gateway → Platform Adapter → Telegram → User      │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.3 Architectural Principles

1. **Separation of Concerns:** OpenClaw handles routing/auth; Hermes handles cognition
2. **MCP as Bridge:** Model Context Protocol connects control plane to cognition layer
3. **Container Isolation:** Each agent runs in its own container with isolated workspace
4. **Persistent State:** Agent memory, sessions, and configuration survive restarts
5. **Plugin Architecture:** Skills, tools, and injections extend capabilities without core changes
6. **Health-First Design:** Doctor Bridge validates system state before and during operation

### 1.4 System Components

| Component | Role | Technology | Location |
|-----------|------|------------|----------|
| OpenClaw Gateway | Message routing, platform adapters | Node.js | `/opt/openclaw/` |
| Hermes Agent | Agent loop, reasoning, tool execution | Python 3.12 | `/opt/hermes/` |
| MCP Router | Protocol bridge between OpenClaw and Hermes | stdio/HTTP | In-process |
| Doctor Bridge | Health validation and auto-fix | Python | `health/doctor_bridge.py` |
| Key Injector | OpenClaw config → Hermes env mapping | Python | `scripts/key_inject.py` |
| Runtime Orchestrator | Agent/crew lifecycle management | Bash | `runtime.sh` |
| Plugin Manager | Skill/tool injection and enforcement | Bash/Python | `plugins/` |

---

## 2. Dual Mode Operation

Hemlock supports three operational modes controlled by environment variables. The mode determines which components are active and how they interact.

### 2.1 Mode: FULL (Default)

**Environment:** No special flags required (default behavior)

**Description:** Complete stack with OpenClaw as control plane driving Hermes as the cognition layer.

**Architecture:**
```
User → Platform → OpenClaw Gateway → MCP → Hermes Agent Loop → MCP → OpenClaw → Platform → User
```

**Active Components:**
- OpenClaw Gateway (port 18789)
- MCP Router (stdio/HTTP)
- Hermes Agent Loop
- Memory System (STM/LTM)
- Tool Execution Engine
- Skill Registry

**Use Cases:**
- Production deployments
- Multi-agent crews
- Platform-connected agents (Telegram, Discord, etc.)
- Full enterprise feature set

**Startup:**
```bash
docker compose -f docker-compose.runtime.yml up
```

### 2.2 Mode: HERMES_ONLY

**Environment:** `HERMES_ONLY=1` or `HERMES_MANAGED=false`

**Description:** Hermes runs standalone without OpenClaw gateway. Direct agent interaction without platform routing.

**Architecture:**
```
User → Hermes Agent Loop → Tool Execution → Response
```

**Active Components:**
- Hermes Agent Loop
- Memory System
- Tool Execution Engine
- Skill Registry

**Disabled Components:**
- OpenClaw Gateway
- MCP Router
- Platform Adapters

**Use Cases:**
- Development and testing
- Local agent interaction
- Debugging cognition layer
- Air-gapped environments

**Startup:**
```bash
HERMES_ONLY=1 python3 -m hermes.agent.run --agent-id my-agent
```

### 2.3 Mode: OPENCLAW_ONLY

**Environment:** `OPENCLAW_ONLY=1`

**Description:** OpenClaw gateway runs without Hermes brain. Gateway-only mode for routing and platform management.

**Architecture:**
```
User → Platform → OpenClaw Gateway → [No Hermes] → Platform → User
```

**Active Components:**
- OpenClaw Gateway (port 18789)
- MCP Router
- Platform Adapters
- Session Manager

**Disabled Components:**
- Hermes Agent Loop
- Memory System
- Tool Execution

**Use Cases:**
- Gateway testing
- Platform adapter validation
- Routing-only deployments
- Load balancing front-end

**Startup:**
```bash
OPENCLAW_ONLY=1 docker compose -f docker-compose.runtime.yml up runtime
```

### 2.4 Mode Comparison Matrix

| Feature | FULL | HERMES_ONLY | OPENCLAW_ONLY |
|---------|------|-------------|---------------|
| OpenClaw Gateway | Yes | No | Yes |
| Hermes Agent Loop | Yes | Yes | No |
| MCP Bridge | Yes | No | Yes |
| Platform Adapters | Yes | No | Yes |
| Memory System | Yes | Yes | No |
| Tool Execution | Yes | Yes | No |
| Crew Orchestration | Yes | Limited | No |
| Health Checks | Full | Basic | Gateway only |
| Docker Required | Yes | Optional | Yes |

### 2.5 Mode Detection

The entrypoint script (`docker/entrypoint.sh`) determines the mode at startup:

```bash
# Pseudocode from entrypoint.sh
if [ "${OPENCLAW_ONLY:-0}" = "1" ]; then
    # Start OpenClaw gateway only
    start_openclaw_gateway
elif [ "${HERMES_ONLY:-0}" = "1" ] || [ "${HERMES_MANAGED:-true}" = "false" ]; then
    # Start Hermes standalone
    start_hermes_standalone
else
    # Full mode: OpenClaw + Hermes
    start_openclaw_gateway &
    start_hermes_agent
fi
```

---

## 3. Directory Structure

### 3.1 Complete Tree

```
hemlock/
├── .env                          # Environment variables (gitignored)
├── .env.template                 # Environment template
├── .gitignore                    # Git ignore rules
├── .auto-update.sh               # Auto-update script
├── Makefile                      # Build and orchestration commands
├── README.md                     # Project overview
├── QUICKSTART.md                 # Quick start guide
│
├── docker-compose.yml            # Primary compose (bind mounts)
├── docker-compose.runtime.yml    # Portable compose (named volumes)
├── docker-config.yaml            # Docker build configuration
│
├── Dockerfile                    # Framework image
├── Dockerfile.runtime            # Runtime image (OpenClaw + Hermes)
├── Dockerfile.agent              # Individual agent image
├── Dockerfile.crew               # Crew export image
├── Dockerfile.export             # Export image
├── entrypoint.sh                 # Agent entrypoint script
│
├── config/
│   ├── gateway.yaml              # OpenClaw gateway configuration
│   └── runtime.yaml              # Runtime configuration
│
├── agents/                       # Agent workspaces
│   ├── active/                   # Active agent registrations (*.json)
│   ├── archive/                  # Archived agent registrations
│   ├── workspace-template/       # Template for new agents
│   │   ├── agent.json            # Agent identity
│   │   ├── SOUL.md               # Agent personality and purpose
│   │   ├── USER.md               # User preferences
│   │   ├── IDENTITY.md           # Agent identity details
│   │   ├── HEARTBEAT.md          # Periodic task definitions
│   │   ├── MEMORY.md             # Curated long-term memory
│   │   ├── AGENTS.md             # Workspace documentation
│   │   ├── TOOLS.md              # Tool documentation
│   │   ├── config.yaml           # Agent configuration
│   │   ├── memory/               # Daily memory notes
│   │   ├── sessions/             # Session history
│   │   ├── skills/               # Installed skills
│   │   ├── tools/                # Agent tools (scripts)
│   │   ├── projects/             # Active projects
│   │   ├── .secrets/             # Encrypted secrets
│   │   ├── .backups/             # Agent backups
│   │   ├── logs/                 # Agent logs
│   │   ├── media/                # User-sent media files
│   │   └── plugins/              # Agent plugins
│   ├── <agent-id>/               # Individual agent workspace
│   │   ├── agent.json
│   │   ├── SOUL.md
│   │   ├── USER.md
│   │   ├── IDENTITY.md
│   │   ├── HEARTBEAT.md
│   │   ├── MEMORY.md
│   │   ├── AGENTS.md
│   │   ├── TOOLS.md
│   │   ├── config.yaml
│   │   ├── .env                  # Agent environment variables
│   │   ├── memory/
│   │   ├── sessions/
│   │   ├── skills/
│   │   ├── tools/
│   │   ├── projects/
│   │   ├── .secrets/
│   │   ├── .backups/
│   │   ├── .archive/
│   │   ├── logs/
│   │   ├── media/
│   │   └── plugins/
│   └── README.md                 # Agent directory documentation
│
├── crews/                        # Crew definitions
│   └── <crew-name>/
│       ├── crew.json             # Crew configuration
│       ├── crew.yaml             # Crew YAML config
│       └── SOUL.md               # Crew identity
│
├── docker/                       # Docker build context
│   ├── hermes-agent/             # Hermes agent package
│   ├── openclaw-runtime/         # OpenClaw runtime binaries
│   │   ├── bin/                  # OpenClaw binaries
│   │   ├── lib/node_modules/     # Node.js dependencies
│   │   └── tools/node/           # Node.js tools
│   ├── agents/                   # Agent-specific Docker configs
│   ├── compose/                  # Compose overrides
│   ├── framework/                # Framework Docker configs
│   ├── models/                   # Model configurations
│   ├── orchestration/            # Orchestration scripts
│   ├── patches/                  # Docker patches
│   └── skills/                   # Docker-bundled skills
│
├── health/                       # Health check validators
│   ├── __init__.py
│   ├── doctor_bridge.py          # Main health orchestration
│   ├── paths/                    # Path validation
│   ├── env/                      # Environment validation
│   ├── identity/                 # Agent identity validation
│   ├── gateway/                  # Gateway connectivity validation
│   ├── imports/                  # Python import validation
│   ├── adapters/                 # Integration adapter validation
│   ├── orchestration/            # Crew orchestration validation
│   └── persistence/              # Data persistence validation
│
├── lib/
│   ├── common.sh                 # Shared utility functions
│   └── README.md
│
├── logs/                         # System logs
│
├── models/                       # AI model configurations
│
├── orchestration/                # Crew orchestration logic
│
├── plugins/                      # Plugin system
│   ├── injections/               # Skill/tool injections
│   │   ├── agent-memory/         # Memory management injection
│   │   ├── agent-workspace-enforcement/  # Workspace enforcement
│   │   ├── autonomy-protocol/    # Autonomy decision framework
│   │   ├── backup-protocol/      # Backup protocol injection
│   │   ├── subagent-driven-development/  # Subagent patterns
│   │   └── tool-enforcement/     # Tool validation injection
│   └── scripts/                  # Plugin scripts
│       └── agent-toolkit/        # Agent toolkit
│           ├── enforce.sh        # Workspace enforcement
│           ├── secret.sh         # Encrypted secret management
│           ├── memory-log.sh     # Memory logging
│           ├── memory-promote.sh # Memory promotion
│           ├── hemlock-doctor.sh # Plugin health check
│           ├── jsonfmt.py        # JSON formatting
│           └── TOOLS-GUIDE.md    # Tool reference
│
├── projects/                     # Shared project storage
│
├── runtime/                      # Runtime state (HERMES_HOME in Docker)
│   ├── .env                      # Runtime environment
│   ├── agent.json                # Runtime agent identity
│   ├── config.yaml               # Runtime configuration
│   ├── SOUL.md                   # Runtime soul
│   ├── USER.md                   # Runtime user config
│   ├── IDENTITY.md               # Runtime identity
│   ├── HEARTBEAT.md              # Runtime heartbeat
│   ├── MEMORY.md                 # Runtime memory
│   ├── AGENTS.md                 # Runtime agents doc
│   ├── TOOLS.md                  # Runtime tools doc
│   ├── state.db                  # SQLite state database
│   ├── gateway_state.json        # Gateway state
│   ├── channel_directory.json    # Channel mappings
│   ├── registered_skills.json    # Skill registry
│   ├── memory/                   # Runtime memory
│   │   ├── short_term.json       # Short-term memory
│   │   ├── long_term.json        # Long-term memory
│   │   └── summaries.json        # Memory summaries
│   ├── sessions/                 # Runtime sessions
│   ├── logs/                     # Runtime logs
│   │   ├── gateway.log           # Gateway activity log
│   │   ├── agent.log             # Agent activity log
│   │   └── errors.log            # Error log
│   ├── behavior/                 # Behavior profiles
│   ├── bin/                      # Runtime binaries
│   ├── checkpoints/              # State checkpoints
│   ├── cron/                     # Cron job definitions
│   ├── embeddings/               # Vector embeddings
│   ├── evolution/                # Agent evolution data
│   ├── generated_skills/         # Auto-generated skills
│   ├── openclaw_supervisor.py    # OpenClaw supervisor
│   ├── orchestration/            # Runtime orchestration
│   ├── platforms/                # Platform configurations
│   ├── queues/                   # Message queues
│   ├── reflections/              # Agent reflections
│   ├── routing/                  # Message routing
│   ├── sandboxes/                # Execution sandboxes
│   ├── skill_drafts/             # Skill development drafts
│   ├── skill_tests/              # Skill test results
│   ├── skills/                   # Runtime skills
│   ├── state/                    # State files
│   │   └── health.json           # Health state
│   └── summaries/                # Data summaries
│
├── runtimes/                     # Runtime configurations
│
├── scripts/                      # Management scripts (63 scripts)
│   ├── agent-control.sh          # Start/stop/restart agents
│   ├── agent-create.sh           # Create new agent
│   ├── agent-delete.sh           # Delete agent
│   ├── agent-export.sh           # Export agent to archive
│   ├── agent-import.sh           # Import agent from archive
│   ├── agent-logs.sh             # View agent logs
│   ├── agent-monitor.sh          # Monitor agent activity
│   ├── agent-restart.sh          # Restart agent
│   ├── agent-run.sh              # Run agent
│   ├── agent-stop.sh             # Stop agent
│   ├── autonomy.sh               # Autonomy configuration
│   ├── backup-interactive.sh     # Interactive backup tool
│   ├── backup.sh                 # Backup script
│   ├── clean.sh                  # Clean temporary files
│   ├── create_crew.py            # Crew creation (Python)
│   ├── crew-blueprint.sh         # Crew blueprint generation
│   ├── crew-create.sh            # Create new crew
│   ├── crew-dissolve.sh          # Dissolve crew
│   ├── crew-export.sh            # Export crew
│   ├── crew-import.sh            # Import crew
│   ├── crew-join.sh              # Agent joins crew
│   ├── crew-leave.sh             # Agent leaves crew
│   ├── crew-list.sh              # List crews
│   ├── crew-monitor.sh           # Monitor crew activity
│   ├── crew-start.sh             # Start crew
│   ├── crew-stop.sh              # Stop crew
│   ├── docs-indexer.sh           # Documentation indexer
│   ├── enforce.sh                # System enforcement
│   ├── gateway-setup.sh          # Gateway configuration
│   ├── health-check.sh           # Health check runner
│   ├── helpers.sh                # Shared helper functions
│   ├── hemlock-snapshot.sh       # System snapshot
│   ├── hermes-logs.sh            # Hermes log viewer
│   ├── hermes-run.sh             # Run Hermes standalone
│   ├── hermes-stop.sh            # Stop Hermes
│   ├── key_inject.py             # OpenClaw → Hermes key injection
│   ├── memory.sh                 # Memory management
│   ├── migrate-agent.sh          # Agent migration
│   ├── pm-create.sh              # Project manager creation
│   ├── restore.sh                # Restore from backup
│   ├── runtime-doctor.sh         # Runtime health check
│   ├── runtime-validate.sh       # Runtime validation
│   ├── runtime.sh                # Runtime menu system
│   ├── security-check.sh         # Security audit
│   ├── security-harden.sh        # Security hardening
│   ├── self-healing/             # Self-healing scripts
│   ├── setup-aliases.sh          # Shell alias setup
│   ├── setup-qwen3-llama.sh      # Qwen3 + Llama.cpp setup
│   ├── setup-wizard.sh           # Interactive setup wizard
│   ├── setup.sh                  # Basic system setup
│   ├── skills-install.sh         # Skill installation
│   ├── test.sh                   # Test runner
│   ├── tool-inject-memory.sh     # Memory context injection
│   ├── validate-all-skills.sh    # Skill validation
│   └── validate.sh               # Configuration validation
│
├── shared/                       # Shared resources
│
├── skills/                       # Skill registry
│   ├── skills/                   # Installed skills
│   └── LTC/                      # Long-term context skills
│
├── srv/                          # Server configurations
│
├── systemd/                      # Systemd service files
│   └── hermes-framework.service  # Systemd unit file
│
├── tests/                        # Test suite
│
├── tools/                        # System tools
│   ├── agent-toolkit/            # Agent toolkit reference
│   └── README.md
│
└── volumes/                      # Docker volume mounts
```

### 3.2 Key Directories Explained

| Directory | Purpose | Mount Point (Docker) |
|-----------|---------|---------------------|
| `agents/` | Agent workspaces (flat structure) | `/data/agents` |
| `crews/` | Crew definitions and configs | `/data/crews` |
| `config/` | System configuration files | `/config` |
| `docker/` | Docker build context and binaries | N/A (build only) |
| `health/` | Health check validators | `/opt/hermes/health/` |
| `lib/` | Shared utility libraries | N/A |
| `logs/` | System-wide logs | `/logs` |
| `models/` | AI model configurations | `/models` |
| `orchestration/` | Crew orchestration logic | N/A |
| `plugins/` | Plugin system (injections + scripts) | `/plugins` |
| `projects/` | Shared project storage | `/projects` |
| `runtime/` | Runtime state (HERMES_HOME) | `/runtime` |
| `scripts/` | Management and utility scripts | `/scripts` |
| `shared/` | Shared resources between components | N/A |
| `skills/` | Skill registry and definitions | `/skills` (read-only) |
| `srv/` | Server configurations | N/A |
| `systemd/` | Systemd service unit files | N/A |
| `tests/` | Test suite and fixtures | N/A |
| `tools/` | System-level tools | N/A |
| `volumes/` | Docker volume mount points | N/A |

### 3.3 Path Resolution

All paths are resolved via the `PathResolver` class (Python) using environment variables. No hardcoded `/home/` paths exist in the portable configuration.

**Environment Variables for Path Resolution:**

| Variable | Default | Description |
|----------|---------|-------------|
| `HERMES_HOME` | `/runtime` | Runtime data directory |
| `HERMES_AGENTS` | `/agents` | Agent storage directory |
| `HERMES_CREWS` | `/crews` | Crew storage directory |
| `HERMES_PROJECTS` | `/projects` | Project storage directory |
| `HERMES_SKILLS` | `/skills` | Skill registry directory |
| `HERMES_LOGS` | `/logs` | Log storage directory |
| `HERMES_MEMORY` | `/memory` | Memory storage directory |
| `HERMES_PLUGINS` | `/plugins` | Plugin directory |
| `HERMES_BACKUPS` | `/backups` | Backup storage directory |
| `HERMES_CONFIG` | `/config` | Configuration directory |
| `HERMES_SCRIPTS` | `/scripts` | Scripts directory |
| `HERMES_MODELS` | `/models` | Model storage directory |
| `PYTHONPATH` | `/opt/hermes` | Python module path |

---

## 4. Agent Workspace

### 4.1 Flat Structure

Each agent workspace follows a flat structure at `agents/<id>/`. This is the canonical layout that all agents must conform to.

```
agents/<agent-id>/
├── agent.json              # Agent identity and metadata
├── SOUL.md                 # Agent personality, purpose, core principles
├── USER.md                 # User preferences and working style
├── IDENTITY.md             # Agent identity details
├── HEARTBEAT.md            # Periodic task definitions (cron-like)
├── MEMORY.md               # Curated long-term memory (lessons, decisions, patterns)
├── AGENTS.md               # Workspace documentation and structure reference
├── TOOLS.md                # Tool documentation and usage guide
├── config.yaml             # Agent configuration (model, tools, memory, skills)
├── .env                    # Agent-specific environment variables
│
├── memory/                 # Daily memory notes (chronological)
├── sessions/               # Session history and transcripts
├── skills/                 # Installed skills (copied from canonical)
├── tools/                  # Agent tools (executable scripts)
│   ├── enforce.sh          # Workspace enforcement script
│   ├── secret.sh           # Encrypted secret management
│   ├── auth-login.sh       # Provider and model selection
│   ├── memory-log.sh       # Memory logging utility
│   ├── memory-promote.sh   # Memory promotion utility
│   └── TOOLS-GUIDE.md      # Tool reference documentation
├── projects/               # Active project directories
├── .secrets/               # Encrypted secrets (AES-256-CBC)
│   ├── .secret-key         # Encryption key (600 perms)
│   └── .<name>.json.enc    # Encrypted secret files
├── .backups/               # Agent backup archives
├── .archive/               # Archived runtime artifacts
├── logs/                   # Agent-specific logs
├── media/                  # User-sent media files (SACRED — never delete)
│   ├── images/agents/      # Agent-generated images
│   ├── images/misc/        # Miscellaneous images
│   └── files/              # Other media files
├── plugins/                # Agent-specific plugins
├── knowledge/              # Structured knowledge base
└── workflows/              # Workflow definitions
```

### 4.2 Core Files

#### agent.json

Agent identity and metadata. Created during agent creation, updated during finalization.

```json
{
  "agent_id": "<agent-id>",
  "name": "<display-name>",
  "display_name": "<display-name>",
  "type": "active|imported|archived",
  "personality": "Helpful, efficient, and direct",
  "expertise": ["general assistance"],
  "communication_style": "Clear and concise",
  "avatar_emoji": "🤖",
  "created_at": "2026-05-17T00:00:00+00:00",
  "version": "1.0.0",
  "model": "ollama/qwen3:0.6b",
  "builderCode": {
    "code": "bc_default",
    "hex": "0x62635f64656661756c74",
    "owner": "0x0000000000000000000000000000000000000000",
    "hardwired": true,
    "enforced": true
  }
}
```

#### SOUL.md

Agent personality, purpose, and core principles. This is the agent's "soul" — its fundamental identity.

```markdown
# SOUL.md — <agent-id>

**Identity:** <agent-id>
**Name:** <display-name>
**Purpose:** General purpose assistant
**Model:** ollama/qwen3:0.6b
**Created:** 2026-05-17T00:00:00+00:00

## Core Principles
- Move forward. When you screw up, fix it and keep going.
- Think like a COO, not an EA. Own outcomes, not tasks.
- Be genuine. Not performing cleverness. Just present and honest.
```

#### USER.md

User preferences, working style, and communication preferences.

```markdown
# USER.md — <agent-id>

**Owner:** User
**Preferences:** Direct and efficient communication
**Working Style:** Async-first, deep work blocks
**Current Focus:** To be determined

## Communication
- Get to the point quickly
- Lay out tradeoffs clearly
- Ask for clarification when uncertain
```

#### MEMORY.md

Curated long-term memory — lessons learned, decisions made, recurring patterns.

```markdown
# MEMORY.md — <agent-id>

**Purpose:** Curated wisdom, lessons learned, decisions made

---

## Lessons

*Lessons will be added as you learn them.*

---

## Decisions

*Major decisions and why they were made.*

---

## Patterns

*Recurring situations and how to handle them.*
```

#### config.yaml

Agent configuration including model provider, tool profile, memory settings, and skill enablement.

```yaml
model:
  default: xiaomi/mimo-v2-pro
  provider: nous
  base_url: https://inference-api.nousresearch.com/v1

tools:
  profile: coding

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
```

### 4.3 Directory Purposes

| Directory | Purpose | Permissions | Notes |
|-----------|---------|-------------|-------|
| `memory/` | Daily memory notes (chronological) | 755 | One file per day |
| `sessions/` | Session history and transcripts | 755 | JSON or markdown |
| `skills/` | Installed skills (copied from canonical) | 755 | Canonical: `~/.openclaw/agents/.skills/` |
| `tools/` | Executable scripts for agent use | 755 (dirs), 644 (files), 755 (.sh) | Must contain enforce.sh, secret.sh |
| `projects/` | Active project directories | 755 | Auto-archived after 30 days |
| `.secrets/` | Encrypted secrets | 755 | Secrets via secret.sh only |
| `.backups/` | Agent backup archives | 755 | Created by backup system |
| `.archive/` | Archived runtime artifacts | 755 | Auto-archived by enforce.sh |
| `logs/` | Agent-specific logs | 755 | Rotated: gzip after 1 day, delete after 30 |
| `media/` | User-sent media files | 755 | **SACRED** — never archive or delete |
| `plugins/` | Agent-specific plugins | 755 | Read-only mount from shared plugins |
| `knowledge/` | Structured knowledge base | 755 | Facts and reference data |
| `workflows/` | Workflow definitions | 755 | JSON workflow specs |

### 4.4 Workspace Template

New agents are created from `agents/workspace-template/`. The template contains the full directory structure and default files.

```bash
# Create agent from template
./scripts/agent-create.sh --id my-agent --model ollama/qwen3:0.6b
```

The template ensures:
- All required directories exist
- All required files are present
- Proper permissions (755 dirs, 644 files)
- Tools directory with enforce.sh, secret.sh, TOOLS-GUIDE.md
- .secrets/ directory with proper permissions

### 4.5 Agent Registration

Agents are registered in the `agents/active/` and `agents/archive/` directories as JSON files:

```
agents/
├── active/
│   ├── jack.json
│   ├── titan.json
│   └── aton.json
└── archive/
    ├── agent1.json
    └── agent2.json
```

- **active/** — Agents that are deployed and available
- **archive/** — Agent definitions that are not yet active

---

## 5. Component Details

### 5.1 OpenClaw Binary

OpenClaw serves as the control plane, providing:

- **Gateway Server:** WebSocket/HTTP server on port 18789
- **Platform Adapters:** Telegram, Discord, Slack, WhatsApp connectors
- **MCP Router:** Model Context Protocol bridge to Hermes
- **Session Manager:** Conversation state and context management
- **Agent Lifecycle:** Start, stop, monitor agent containers

**Location:** `/opt/openclaw/`
- `bin/openclaw-container` — Main binary
- `lib/node_modules/openclaw/` — Node.js dependencies
- `tools/node/` — Node.js tooling

**Version Check:**
```bash
openclaw --version
```

### 5.2 Hermes Gateway

Hermes is the cognition layer, providing:

- **Agent Loop:** Main reasoning cycle
- **Brain:** LLM inference and reasoning
- **Tool Execution:** Script and tool invocation
- **Memory System:** Short-term and long-term memory
- **Skill Registry:** Skill loading and execution
- **Self-Learning:** Reflection and memory promotion

**Location:** `/opt/hermes/`
- Python package installed via `pyproject.toml`
- Health validators in `health/`
- Key injection in `scripts/key_inject.py`

**Entry Point:**
```bash
hermes --agent-id <id> --model <model> --tui
```

### 5.3 MCP Servers

MCP (Model Context Protocol) connects OpenClaw to Hermes:

- **stdio MCP:** Local process communication
- **HTTP MCP:** Network-based communication
- **Tool Routing:** Routes tool calls from OpenClaw to Hermes
- **Context Passing:** Passes conversation context between layers

**Configuration:**
- MCP servers defined in `docker/openclaw-runtime/`
- stdio servers for local agent communication
- HTTP servers for network-based agent communication

### 5.4 Health System

The health system validates system state through the Doctor Bridge:

**Location:** `health/doctor_bridge.py`

**Categories:**
1. **Paths** — Filesystem path validation
2. **Environment** — Runtime environment validation
3. **Identity** — Agent identity verification
4. **Gateway** — OpenClaw gateway connectivity
5. **Imports** — Python dependency validation
6. **Adapters** — Integration adapter validation
7. **Orchestration** — Crew orchestration validation
8. **Persistence** — Data persistence validation

**Modes:**
- `--quick` — Essential checks only (paths, env, imports)
- `--json` — JSON output for automation
- `--fix` — Auto-fix issues where possible
- `--categories` — Specific categories to check

### 5.5 Orchestration

Crew orchestration manages multi-agent collaboration:

**Location:** `orchestration/` and `crews/`

**Features:**
- Crew creation and management
- Agent assignment to crews
- Crew channel routing
- Workflow definitions
- Crew lifecycle (create, start, stop, dissolve)

### 5.6 Persistence

Data persistence ensures state survives restarts:

**Components:**
- **SQLite Database:** `runtime/state.db` — State storage
- **JSON Files:** Gateway state, channel directory, skill registry
- **Memory Files:** Short-term, long-term, summaries
- **Session Files:** Conversation transcripts
- **Log Files:** Gateway, agent, error logs

**Environment Flags:**
```
ENABLE_PERSISTENT_MEMORY=true
ENABLE_AGENT_RESURRECTION=true
ENABLE_CONTINUOUS_RUNTIME=true
ENABLE_SKILL_LEARNING=true
ENABLE_MEMORY_FEEDBACK=true
ENABLE_SESSION_RECOVERY=true
```

---

## 6. Configuration

### 6.1 docker-compose.yml

Primary compose file using bind mounts for development:

```yaml
version: '3.8'

services:
  framework:
    build:
      context: .
      dockerfile: Dockerfile.runtime
    container_name: hermes_framework
    restart: unless-stopped
    volumes:
      - ./runtime:/runtime
      - ./agents:/data/agents
      - ./crews:/data/crews
      - ./models:/models
      - ./backups:/backups
      - ./skills/skills:/skills:ro
    environment:
      - ENABLE_PERSISTENT_MEMORY=true
      - ENABLE_AGENT_RESURRECTION=true
      - ENABLE_CONTINUOUS_RUNTIME=true
      - ENABLE_SKILL_LEARNING=true
      - ENABLE_MEMORY_FEEDBACK=true
      - ENABLE_SESSION_RECOVERY=true
      - PYTHONPATH=/opt/hermes
    healthcheck:
      test: ["CMD", "python3", "-m", "health.doctor_bridge", "--quick"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    command: []
```

### 6.2 docker-compose.runtime.yml

Portable compose file using named volumes for production:

```yaml
version: '3.8'

x-hemlock-env: &hemlock-env
  HEMLOCK_DOCKER: "1"
  HERMES_MANAGED: "false"
  HERMES_HOME: /runtime
  HERMES_AGENTS: /agents
  HERMES_CREWS: /crews
  HERMES_PROJECTS: /projects
  HERMES_SKILLS: /skills
  HERMES_LOGS: /logs
  HERMES_MEMORY: /memory
  HERMES_PLUGINS: /plugins
  HERMES_BACKUPS: /backups
  HERMES_CONFIG: /config
  HERMES_SCRIPTS: /scripts
  HERMES_MODELS: /models
  PYTHONPATH: /opt/hermes
  ENABLE_PERSISTENT_MEMORY: "true"
  ENABLE_AGENT_RESURRECTION: "true"
  ENABLE_CONTINUOUS_RUNTIME: "true"
  ENABLE_SKILL_LEARNING: "true"
  ENABLE_MEMORY_FEEDBACK: "true"
  ENABLE_SESSION_RECOVERY: "true"

services:
  runtime:
    build:
      context: .
      dockerfile: Dockerfile.runtime
    image: hemlock:latest
    container_name: hemlock_runtime
    restart: unless-stopped
    volumes:
      - runtime_data:/runtime
      - agents_data:/data/agents
      - crews_data:/data/crews
      - projects_data:/projects
      - logs_data:/logs
      - memory_data:/memory
      - skills_data:/skills:ro
      - backups_data:/backups
      - plugins_data:/plugins
      - config_data:/config
    environment:
      <<: *hemlock-env
    ports:
      - "18789:18789"
    healthcheck:
      test: ["CMD", "python3", "-m", "health.doctor_bridge", "--quick", "--json"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    command: []

  agent:
    image: hemlock:latest
    container_name: hemlock_agent
    restart: unless-stopped
    profiles: ["agent"]
    volumes:
      - runtime_data:/runtime
      - agents_data:/data/agents
      - skills_data:/skills:ro
      - logs_data:/logs
      - memory_data:/memory
    environment:
      <<: *hemlock-env
      AGENT_ID: ${AGENT_ID:-hermes}
      ENABLE_MCP_BRAIN: "true"
    depends_on:
      runtime:
        condition: service_healthy
    entrypoint: ["/opt/hermes/docker/entrypoint.sh"]

  doctor:
    image: hemlock:latest
    container_name: hemlock_doctor
    profiles: ["ops"]
    volumes:
      - runtime_data:/runtime
      - agents_data:/data/agents
      - crews_data:/data/crews
      - config_data:/config
      - skills_data:/skills:ro
    environment:
      <<: *hemlock-env
    command: ["--doctor", "--fix"]

  setup:
    image: hemlock:latest
    container_name: hemlock_setup
    profiles: ["ops"]
    volumes:
      - runtime_data:/runtime
      - config_data:/config
      - agents_data:/data/agents
      - ${OPENCLAW_CONFIG_PATH:-/dev/null}:/opt/hermes/openclaw_config.json:ro
    environment:
      <<: *hemlock-env
      OPENCLAW_CONFIG: /opt/hermes/openclaw_config.json
    command: ["--setup"]

volumes:
  runtime_data:
  agents_data:
  crews_data:
  projects_data:
  logs_data:
  memory_data:
  skills_data:
  backups_data:
  plugins_data:
  config_data:
```

### 6.3 Environment Variables

#### System-Level (.env)

```bash
# Image & Build
OPENCLAW_IMAGE=openclaw/gateway:latest

# Gateway Configuration
OPENCLAW_GATEWAY_BIND=lan
OPENCLAW_GATEWAY_PORT=18789
OPENCLAW_GATEWAY_TOKEN=change_this_to_a_secure_token

# Directories
OPENCLAW_CONFIG_DIR=~/.openclaw
OPENCLAW_WORKSPACE_DIR=~/.openclaw/workspace

# Security
GOG_KEYRING_PASSWORD=
XDG_CONFIG_HOME=/home/node/.openclaw

# Agent Defaults
DEFAULT_AGENT_MODEL=nous/mistral-large
DEFAULT_AGENT_NETWORK=agents_net
```

#### Runtime-Level (docker-compose.runtime.yml)

| Variable | Default | Description |
|----------|---------|-------------|
| `HEMLOCK_DOCKER` | `"1"` | Docker mode flag |
| `HERMES_MANAGED` | `"false"` | Hermes managed by OpenClaw |
| `HERMES_HOME` | `/runtime` | Runtime data directory |
| `HERMES_AGENTS` | `/agents` | Agent storage directory |
| `HERMES_CREWS` | `/crews` | Crew storage directory |
| `HERMES_PROJECTS` | `/projects` | Project storage directory |
| `HERMES_SKILLS` | `/skills` | Skill registry directory |
| `HERMES_LOGS` | `/logs` | Log storage directory |
| `HERMES_MEMORY` | `/memory` | Memory storage directory |
| `HERMES_PLUGINS` | `/plugins` | Plugin directory |
| `HERMES_BACKUPS` | `/backups` | Backup storage directory |
| `HERMES_CONFIG` | `/config` | Configuration directory |
| `HERMES_SCRIPTS` | `/scripts` | Scripts directory |
| `HERMES_MODELS` | `/models` | Model storage directory |
| `PYTHONPATH` | `/opt/hermes` | Python module path |
| `ENABLE_PERSISTENT_MEMORY` | `"true"` | Enable persistent memory |
| `ENABLE_AGENT_RESURRECTION` | `"true"` | Enable agent resurrection |
| `ENABLE_CONTINUOUS_RUNTIME` | `"true"` | Enable continuous runtime |
| `ENABLE_SKILL_LEARNING` | `"true"` | Enable skill learning |
| `ENABLE_MEMORY_FEEDBACK` | `"true"` | Enable memory feedback |
| `ENABLE_SESSION_RECOVERY` | `"true"` | Enable session recovery |

### 6.4 config.yaml Format

Agent-level configuration:

```yaml
model:
  default: <provider>/<model-name>
  provider: <provider-name>
  base_url: <api-base-url>
  api_key: <optional-api-key>

tools:
  profile: <tool-profile>  # coding, general, etc.

memory:
  enabled: true
  max_chars: 100000

skills:
  enabled: true
```

Runtime-level configuration (`config/runtime.yaml`):

```yaml
runtime:
  gateway:
    port: 18789
    token: "change_this_to_a_secure_token"
    bind: "lan"
  agents:
    default_model: "ollama/qwen3:0.6b"
    default_network: "agents_net"
  security:
    read_only: true
    cap_drop: true
    icc: false
    tmpfs: true
    tmpfs_size: "64m"
  logging:
    level: "info"
    max_size: "10m"
    max_files: 5
```

Gateway configuration (`config/gateway.yaml`):

```yaml
gateway:
  host: "0.0.0.0"
  port: 18789
  bind: "lan"
  token: "${OPENCLAW_GATEWAY_TOKEN}"
  auth:
    enabled: true
    required: true
  agents:
    default_timeout: 300
    max_concurrent: 10
  channels:
    telegram:
      enabled: true
      webhook: false
    discord:
      enabled: false
  logging:
    level: "info"
    file: "/var/log/openclaw/gateway.log"
    max_size: "10m"
    max_files: 5
  performance:
    max_memory: "512m"
    worker_threads: 4
```

---

## 7. Agent Lifecycle

### 7.1 Create

Creates a new agent workspace from the template.

```bash
# Using runtime.sh menu
./runtime.sh
# Select: 1) Create agents

# Using script directly
./scripts/agent-create.sh --id my-agent --model ollama/qwen3:0.6b --name "My Agent"
```

**Process:**
1. Validate agent ID format (3-16 chars, lowercase, alphanumeric + underscore)
2. Check agent doesn't already exist
3. Copy workspace template to `agents/<id>/`
4. Generate `agent.json` with identity metadata
5. Create `SOUL.md`, `USER.md`, `MEMORY.md`, `AGENTS.md` if missing
6. Set permissions (755 dirs, 644 files)
7. Run workspace enforcement
8. Register in `agents/active/<id>.json`

**Agent ID Validation:**
```bash
# Valid: my-agent, agent_1, test123
# Invalid: MyAgent (uppercase), ab (too short), agent-with-long-name-over-16-chars
```

### 7.2 Import

Imports an agent from an archive or directory.

```bash
# Using runtime.sh menu
./runtime.sh
# Select: Agent Import/Export → Import

# Using script directly
./scripts/agent-import.sh --source /path/to/agent --target my-agent
./scripts/agent-import.sh --source /path/to/agent.tar.gz --target my-agent
```

**Supported Source Types:**
- Directories (copies all files including hidden)
- Archives: `.tar.gz`, `.tgz`, `.tar`, `.zip`, `.tar.bz2`
- Unknown formats (auto-detection)

**Process:**
1. Validate target agent ID
2. Backup existing agent if `--overwrite` flag used
3. Extract/copy source to `agents/<target>/`
4. Flatten nested archive structures
5. Ensure workspace-template structure (create missing directories)
6. Ensure required files (SOUL.md, USER.md, AGENTS.md, agent.json)
7. Set permissions (NEVER 700)
8. Clean Mac artifacts (`__MACOSX`, `.DS_Store`)
9. Run workspace enforcement
10. Register in `agents/active/<target>.json`
11. Provision Docker volume (if available)
12. Prompt for model configuration
13. Prompt for channel pairing

### 7.3 Export

Exports an agent to directory, Docker volume, or container.

```bash
# Using runtime.sh menu
./runtime.sh
# Select: Agent Import/Export → Export

# Using script directly
./scripts/agent-export.sh --id my-agent --dest /tmp/export --mode STANDARD
./scripts/agent-export.sh --id my-agent --volume my-agent-vol --mode FULL
./scripts/agent-export.sh --id my-agent --container my-agent-ctr --mode MINIMAL
```

**Export Modes:**

| Mode | Categories | Use Case |
|------|-----------|----------|
| MINIMAL | CORE_IDENTITY | Safe sharing, identity only |
| STANDARD | CORE_IDENTITY, TOOLS, SKILLS, MEMORY, SECRETS | Team sharing |
| FULL | All categories | Complete backup |
| CUSTOM | User-selected | Specific needs |

**Export Categories:**
- `CORE_IDENTITY` — identity.md, IDENTITY.md, HEARTBEAT.md, config.yaml, SOUL.md, .env
- `TOOLS` — tools/ directory
- `SKILLS` — skills/ directory
- `MEMORY` — memory/, sessions/, reflections/ (recent 5 days for STANDARD, all for FULL)
- `SECRETS` — .secrets/, .env.enc, .secret-key (requires additional confirmation)
- `RUNTIME` — state/, workspace/, logs/
- `BACKUPS` — .backups/, .archive/
- `MEDIA` — media/, downloads/
- `PICTURE` — pictures/, images/

**Export Targets:**
- `--dest <path>` — Export to directory
- `--volume <name>` — Export to Docker volume
- `--container <name>` — Export to new container

**Manifests:**
Each export creates `export-manifest.yaml` and `export-manifest.json` with metadata.

### 7.4 Start

Starts an agent container.

```bash
./scripts/agent-control.sh start my-agent
```

**Process:**
1. Validate agent exists
2. Check if already running
3. Start container via docker-compose
4. Verify container is running
5. Log start event

### 7.5 Stop

Stops an agent container.

```bash
./scripts/agent-control.sh stop my-agent
./scripts/agent-control.sh stop my-agent --force
```

**Process:**
1. Validate agent exists
2. Check if running
3. Stop container via docker-compose
4. Verify container stopped
5. Force stop with `--force` flag if needed
6. Log stop event

### 7.6 Monitor

Monitors agent activity and health.

```bash
./scripts/agent-monitor.sh my-agent
./scripts/agent-logs.sh my-agent
```

**Monitoring Data:**
- Container status
- Log output (gateway.log, agent.log, errors.log)
- Health check results
- Memory usage
- Session activity

### 7.7 Delete

Deletes an agent and all its files.

```bash
./scripts/agent-delete.sh --id my-agent --force
```

**Process:**
1. Validate agent exists
2. Backup agent (optional, recommended)
3. Stop running container
4. Remove agent workspace directory
5. Remove registration from active/archive
6. Remove Docker volume (if exists)
7. Log deletion event

---

## 8. Crew Management

### 8.1 A2A Orchestration

Crews enable multi-agent collaboration through Agent-to-Agent (A2A) orchestration.

**Architecture:**
```
┌─────────────────────────────────────────────────────────────┐
│                        Crew: my-team                         │
│                                                              │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐               │
│  │ Agent 1  │    │ Agent 2  │    │ Agent 3  │               │
│  │ (titan)  │    │ (aton)   │    │ (allman) │               │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘               │
│       │               │               │                       │
│       └───────────────┼───────────────┘                       │
│                       │                                       │
│              ┌────────▼────────┐                             │
│              │  Crew Channel   │                             │
│              │  crew-my-team   │                             │
│              └────────┬────────┘                             │
│                       │                                       │
│              ┌────────▼────────┐                             │
│              │  OpenClaw       │                             │
│              │  Gateway        │                             │
│              └─────────────────┘                             │
└─────────────────────────────────────────────────────────────┘
```

**Key Principles:**
- Agents remain isolated (separate containers)
- No direct agent-to-agent communication
- All messages routed through Gateway
- Each agent maintains its own brain and memory
- Crew channel provides shared communication space

### 8.2 Crew Lifecycle

#### Create

```bash
./scripts/crew-create.sh my-team agent1 agent2 agent3
./scripts/crew-create.sh my-team --duration 86400 --owner admin --private
```

**Process:**
1. Validate crew name (3-21 chars, alphanumeric + underscore/hyphen)
2. Validate all agents exist
3. Create crew directory at `crews/<name>/`
4. Generate crew ID and channel name
5. Create `crew.yaml` with configuration
6. Create `crew.json` with metadata
7. Create crew `SOUL.md`
8. Install default skills for crew members
9. Create crew log directory

**Crew Configuration:**
```yaml
crew:
  name: my-team
  id: crew-1234567890-abc123
  channel: crew-my-team
  agents:
    - agent1
    - agent2
    - agent3
  created: 2026-05-17T00:00:00+00:00
  expires: 2026-05-18T00:00:00+00:00
  duration: 86400
  status: active
  owner: admin
  private: false
  security:
    isolate_agents: true
    allow_agent_dm: false
    shared_memory: false
```

#### Start

```bash
./scripts/crew-start.sh my-team
```

**Process:**
1. Validate crew exists
2. Stop all crew member agents
3. Add agents to crew channel
4. Start agents with crew channel configuration
5. Verify all agents connected

#### Stop

```bash
./scripts/crew-stop.sh my-team
```

**Process:**
1. Validate crew exists
2. Stop all crew member agents
3. Remove agents from crew channel
4. Reset agents to individual mode

#### Join

```bash
./scripts/crew-join.sh my-team agent1
```

**Process:**
1. Validate crew and agent exist
2. Stop agent
3. Add agent to crew channel
4. Start agent with crew configuration

#### Leave

```bash
./scripts/crew-leave.sh my-team agent1
```

**Process:**
1. Validate crew and agent exist
2. Stop agent
3. Remove agent from crew channel
4. Start agent in individual mode

#### Dissolve

```bash
./scripts/crew-dissolve.sh my-team
```

**Process:**
1. Validate crew exists
2. Stop all crew member agents
3. Remove all agents from crew channel
4. Archive crew configuration
5. Remove crew directory

#### Export

```bash
./scripts/crew-export.sh my-team --dest /tmp/crew-export
```

**Process:**
1. Validate crew exists
2. Export crew configuration
3. Export member agent configurations
4. Create crew archive

#### Import

```bash
./scripts/crew-import.sh --source /path/to/crew-export --target my-team
```

**Process:**
1. Extract crew archive
2. Validate crew configuration
3. Import crew to `crews/<target>/`
4. Import member agents
5. Register crew

### 8.3 Crew Monitoring

```bash
./scripts/crew-monitor.sh my-team
./scripts/crew-list.sh
```

**Monitoring Data:**
- Crew status (active/inactive)
- Member agent status
- Channel activity
- Workflow execution
- Message routing

---

## 9. Security Model

### 9.1 Core Principles

1. **HERMES_MANAGED=false** — Hermes is NOT managed by external processes; it manages itself
2. **NEVER chmod 700/600** — Restrictive permissions lock users out and cause data loss
3. **.secrets isolation** — Secrets encrypted at rest, accessed only through tool calls
4. **Container sandboxing** — Each agent runs in isolated container

### 9.2 Permission Rules

```
NEVER: chmod 700 or chmod 000 anywhere
ALWAYS: chmod 755 (directories), chmod 644 (files)
EXCEPTION: .secrets/.secret-key may be 600 (encryption key only)
```

**Rationale:** `chmod 700` locks the user out of their own files and has caused catastrophic data loss. The enforcement system actively scans for and fixes 700 permissions.

**Permission Enforcement:**
```bash
# Scan for problematic permissions
find /path/to/workspace -type d -perm 700
find /path/to/workspace -type f -perm 700

# Fix permissions
find /path/to/workspace -type d -perm 700 -exec chmod 755 {} \;
find /path/to/workspace -type f -perm 700 -exec chmod 644 {} \;
```

### 9.3 .secrets Isolation

Secrets are stored encrypted and accessed only through the `secret.sh` tool:

**Storage:**
```
.secrets/
  .secret-key              # Encryption key (auto-generated, 600 perms)
  .<name>.json.enc         # Encrypted secret files (AES-256-CBC)
```

**Access Pattern:**
```bash
# CORRECT: Use secret.sh tool
bash tools/secret.sh get telegram bot.token
bash tools/secret.sh set github token "ghp_xxx"

# WRONG: Never read .secrets/ files directly
cat .secrets/.telegram.json.enc    # Encrypted, useless
cat .secrets/.secret-key           # Security violation
```

**Encryption:**
- Algorithm: AES-256-CBC
- Key Derivation: PBKDF2
- Key File: `.secrets/.secret-key` (auto-generated, 600 permissions)
- File Format: `.json.enc` (encrypted JSON)

**Secret Commands:**
| Command | Description |
|---------|-------------|
| `secret.sh get <name> [key]` | Read a secret value |
| `secret.sh set <name> <key> <value>` | Set/update a secret |
| `secret.sh has <name> [key]` | Check if secret exists |
| `secret.sh list` | List all secret names |
| `secret.sh delete <name>` | Delete a secret |
| `secret.sh init` | Re-generate encryption key |
| `secret.sh migrate` | Convert plaintext to encrypted |

### 9.4 Container Sandboxing

Each agent runs in an isolated Docker container:

**Container Configuration:**
```yaml
security:
  read_only: true        # Read-only root filesystem
  cap_drop: true         # Drop all capabilities
  icc: false             # Disable inter-container communication
  tmpfs: true            # Use tmpfs for writable dirs
  tmpfs_size: "64m"      # Limit tmpfs size
```

**Container Identity:**
- User: `agent` (uid 1000), NOT root
- Working Directory: `/data/agents/<name>/`
- Plugin Mount: `/home/agent/.hermes/plugins/` (read-only)
- HERMES_HOME: `/data/agents/<name>/`

**Volume Mounts:**
```
Host: ~/.openclaw/agents/<name>/  →  Container: /data/agents/<name>/
Host: ~/.hermes/plugins/          →  Container: /data/agents/<name>/plugins/ (read-only)
```

### 9.5 Key Injection

OpenClaw configuration is mapped to Hermes environment variables via `key_inject.py`:

**Process:**
1. Read OpenClaw config (`~/.openclaw/openclaw.json`)
2. Map keys to Hermes environment variables
3. Write non-secret vars to `.env`
4. Write secrets to `.secrets/secrets.json` (encrypted)
5. Write individual secret files for shell compatibility
6. Update `config.yaml` with model configuration

**Key Mappings:**
| OpenClaw Key | Hermes Env Var | Secret |
|-------------|---------------|--------|
| `openrouter.api_key` | `OPENROUTER_API_KEY` | Yes |
| `openai.api_key` | `OPENAI_API_KEY` | Yes |
| `anthropic.api_key` | `ANTHROPIC_API_KEY` | Yes |
| `telegram.bot_token` | `TELEGRAM_BOT_TOKEN` | Yes |
| `discord.bot_token` | `DISCORD_BOT_TOKEN` | Yes |
| `exa.api_key` | `EXA_API_KEY` | Yes |
| `firecrawl.api_key` | `FIRECRAWL_API_KEY` | Yes |
| `tavily.api_key` | `TAVILY_API_KEY` | Yes |
| `github.token` | `GITHUB_TOKEN` | Yes |
| `inference.provider` | `HERMES_INFERENCE_PROVIDER` | No |
| `inference.base_url` | `OPENAI_BASE_URL` | No |
| `inference.model` | `HERMES_DEFAULT_MODEL` | No |

**Usage:**
```bash
# From OpenClaw onboarding
python3 -m scripts.key_inject --from-openclaw

# From JSON config file
python3 -m scripts.key_inject --from-file path/to/config.json

# Dry run
python3 -m scripts.key_inject --from-openclaw --dry-run
```

### 9.6 Security Hardening

```bash
./scripts/security-harden.sh
./scripts/security-check.sh
```

**Hardening Steps:**
1. Fix problematic permissions (700 → 755/644)
2. Validate secret encryption
3. Check container security settings
4. Audit agent identities
5. Verify plugin integrity
6. Rotate encryption keys (optional)

---

## 10. MCP Integration

### 10.1 Overview

MCP (Model Context Protocol) serves as the bridge between OpenClaw (control plane) and Hermes (cognition layer). It enables:

- Tool routing from OpenClaw to Hermes
- Context passing between layers
- Resource sharing
- Prompt management

### 10.2 Connection Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      OpenClaw Gateway                        │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐   │
│  │   Platform   │───→│   Session    │───→│    MCP       │   │
│  │   Adapters   │    │   Manager    │    │   Router     │   │
│  └──────────────┘    └──────────────┘    └──────┬───────┘   │
│                                                  │           │
└──────────────────────────────────────────────────┼───────────┘
                                                   │
                                    ┌──────────────┼──────────┐
                                    │    MCP Protocol        │
                                    │  (stdio or HTTP)       │
                                    └──────────────┼──────────┘
                                                   │
┌──────────────────────────────────────────────────┼───────────┐
│                      Hermes Agent                 │           │
│                                                  │           │
│  ┌──────────────┐    ┌──────────────┐    ┌──────▼───────┐   │
│  │  MCP Server  │───→│  Agent Loop  │───→│   Brain      │   │
│  │  (stdio/HTTP)│    │  (Main)      │    │  (Reasoning) │   │
│  └──────────────┘    └──────────────┘    └──────────────┘   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 10.3 stdio MCP Servers

Local process communication for single-container deployments:

**Configuration:**
```json
{
  "mcpServers": {
    "hermes": {
      "command": "hermes",
      "args": ["mcp", "stdio"],
      "env": {
        "HERMES_HOME": "/data/agents/<name>",
        "PYTHONPATH": "/opt/hermes"
      }
    }
  }
}
```

**Features:**
- Zero network overhead
- Direct process communication
- Suitable for single-agent deployments
- Lower latency

### 10.4 HTTP MCP Servers

Network-based communication for multi-container deployments:

**Configuration:**
```json
{
  "mcpServers": {
    "hermes": {
      "url": "http://hermes-agent:8080/mcp",
      "headers": {
        "Authorization": "Bearer <token>"
      }
    }
  }
}
```

**Features:**
- Cross-container communication
- Network isolation support
- Suitable for crew deployments
- Higher latency but more flexible

### 10.5 Tool Routing

Tool calls flow from OpenClaw to Hermes via MCP:

**Flow:**
1. User sends message via platform (Telegram, etc.)
2. OpenClaw Gateway receives message
3. Gateway routes to MCP Router
4. MCP Router forwards to Hermes MCP Server
5. Hermes Agent Loop processes message
6. Agent decides to use a tool
7. Tool executed (script, API call, etc.)
8. Result returned via MCP
9. Response routed back to user

**Tool Categories:**
| Category | Examples | Execution |
|----------|---------|-----------|
| Scripts | enforce.sh, secret.sh | Local bash execution |
| API Calls | Web search, GitHub | HTTP requests |
| Memory | Read/write memory | File I/O |
| Skills | Skill-specific actions | Skill handler |

---

## 11. Health System

### 11.1 Doctor Bridge

The Doctor Bridge (`health/doctor_bridge.py`) is the central health validation system.

**Location:** `health/doctor_bridge.py`

**Usage:**
```bash
# Quick health check (essential checks only)
python3 -m health.doctor_bridge --quick

# Full health check (all categories)
python3 -m health.doctor_bridge

# JSON output (for automation/monitoring)
python3 -m health.doctor_bridge --json

# Auto-fix mode
python3 -m health.doctor_bridge --fix

# Specific categories
python3 -m health.doctor_bridge --categories paths env identity

# Docker health check
python3 -m health.doctor_bridge --quick --json
```

### 11.2 Health Categories

| Category | Module | Function | Critical | Checks |
|----------|--------|----------|----------|--------|
| **Paths** | `health.paths.paths_validator` | `run_path_checks` | Yes | Directory existence, writability, path resolution |
| **Environment** | `health.env.env_validator` | `run_env_checks` | Yes | Environment variables, Python path, Docker detection |
| **Identity** | `health.identity.identity_validator` | `run_agent_identity_checks` | Yes | Agent ID, SOUL.md, agent.json, config.yaml |
| **Gateway** | `health.gateway.gateway_validator` | `run_gateway_checks` | Yes | Gateway connectivity, port availability, auth token |
| **Imports** | `health.imports.imports_validator` | `test_imports` | Yes | Python module imports, dependency availability |
| **Adapters** | `health.adapters.adapters_validator` | `test_adapters` | No | Platform adapter configuration, webhook setup |
| **Orchestration** | `health.orchestration.orchestration_validator` | `test_orchestration` | No | Crew configuration, agent assignments, channel routing |
| **Persistence** | `health.persistence.persistence_validator` | `test_persistence` | No | Database connectivity, file I/O, state consistency |

### 11.3 Health Report Format

**Human-Readable:**
```
============================================================
  Hemlock Health Check  ✓
  15 ok  2 warn  0 fail  (234.5ms)
============================================================

  [PATHS]
    ✓ hermes_home: /runtime exists and is writable
    ✓ agents_dir: /agents exists and is writable
    ✓ skills_root: /skills exists

  [ENVIRONMENT]
    ✓ python_path: /opt/hermes is set
    ✓ docker_mode: HEMLOCK_DOCKER=1
    ⚠ hermes_managed: HERMES_MANAGED not set (default: true)

  [IDENTITY]
    ✓ agent_json: agent.json exists and is valid
    ✓ soul_md: SOUL.md exists and is non-empty
    ✓ config_yaml: config.yaml exists

============================================================
  HEALTHY - All critical checks passed
============================================================
```

**JSON:**
```json
{
  "healthy": true,
  "total_checks": 17,
  "ok_count": 15,
  "warn_count": 2,
  "fail_count": 0,
  "duration_ms": 234.5,
  "results": [
    {
      "name": "hermes_home",
      "status": "ok",
      "detail": "/runtime exists and is writable",
      "path": "/runtime",
      "category": "paths"
    }
  ]
}
```

### 11.4 Docker Health Check

The Docker health check uses Doctor Bridge:

```yaml
healthcheck:
  test: ["CMD", "python3", "-m", "health.doctor_bridge", "--quick", "--json"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 40s
```

**Exit Codes:**
- `0` — Healthy (all critical checks passed)
- `1` — Unhealthy (one or more critical checks failed)

### 11.5 Auto-Fix Mode

The `--fix` flag enables automatic remediation:

```bash
python3 -m health.doctor_bridge --fix
```

**Auto-Fix Actions:**
- Create missing directories
- Fix file permissions (700 → 755/644)
- Generate missing default files
- Reset environment variables
- Rebuild corrupted state files

---

## 12. Deployment

### 12.1 Docker Build

**Build Runtime Image:**
```bash
docker build -t hemlock:latest -f Dockerfile.runtime .
```

**Build Framework Image:**
```bash
docker build --target framework -t openclaw/enterprise-framework:latest -f Dockerfile .
```

**Build Agent Image:**
```bash
docker build -t "openclaw/agent-my-agent:latest" \
  --build-arg AGENT_ID=my-agent \
  --build-arg MODEL=ollama/qwen3:0.6b \
  -f Dockerfile.agent .
```

**Build Crew Image:**
```bash
docker build -t "openclaw/crew-my-team:latest" \
  --build-arg CREW_ID=my-team \
  -f Dockerfile.crew .
```

### 12.2 Compose Up

**Development (bind mounts):**
```bash
docker compose up -d
```

**Production (named volumes):**
```bash
docker compose -f docker-compose.runtime.yml up -d
```

**With Agent:**
```bash
docker compose -f docker-compose.runtime.yml --profile agent up -d
```

**With Ops Tools:**
```bash
docker compose -f docker-compose.runtime.yml --profile ops up -d
```

### 12.3 runtime.sh Menu

The interactive management console:

```bash
./runtime.sh
```

**Menu Options:**
```
  ╔══════════════════════════════════════════════════════════════╗
  ║        HEMLOCK ENTERPRISE AGENT FRAMEWORK                    ║
  ║             Interactive Management Console                   ║
  ╚══════════════════════════════════════════════════════════════╝

  Agents: 27 (active: 1)  Crews: 1  Docker: available  Ollama: running

  [1] Agent Management
      1.1) List agents
      1.2) Create agents (deploy catalog)
      1.3) Delete agent
      1.4) Agent control (start/stop/restart)
      1.5) Agent logs
      1.6) Agent import/export
      1.7) Configure AI Model
      1.8) Configure Platform Channels

  [2] Crew Management
      2.1) List crews
      2.2) Create crew
      2.3) Crew control (start/stop)
      2.4) Crew monitoring
      2.5) Crew import/export

  [3] System
      3.1) System status
      3.2) Self-check
      3.3) Health check (doctor)
      3.4) Setup

  [4] Backup & Restore
      4.1) Backup
      4.2) Restore
      4.3) Backup status

  [5] Memory Management
      5.1) Inject memory (single agent)
      5.2) Inject memory (all agents)

  [6] Plugin Management
      6.1) List plugins
      6.2) Enable plugin
      6.3) Disable plugin

  [0] Exit
```

### 12.4 Makefile Commands

```bash
make help                    # Show available commands
make build                   # Build all Docker images
make build-framework         # Build framework image only
make build-agents            # Build all agent images
make build-agent AGENT_ID=x  # Build specific agent
make build-crew CREW_ID=x    # Build specific crew
make up                      # Start all services
make down                    # Stop all services
make clean                   # Remove containers and volumes
make export                  # Export all agents
make test                    # Run health checks
make status                  # Show framework status
make logs                    # Show all service logs
```

### 12.5 Systemd Service

For bare-metal deployments:

```ini
[Unit]
Description=Hermes/OpenClaw Framework Gateway
After=network.target

[Service]
Type=simple
User=hermes
Group=hermes
WorkingDirectory=/srv/framework
ExecStart=/usr/bin/python -m hermes.gateway.run
Restart=on-failure
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

Environment=HERMES_HOME=/var/lib/hermes
EnvironmentFile=-/etc/hermes/hermes.env

ProtectSystem=full
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
MemoryLimit=2G
CPUQuota=80%
LimitNOFILE=65536
LimitNPROC=100

[Install]
WantedBy=multi-user.target
```

**Installation:**
```bash
sudo cp systemd/hermes-framework.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable hermes-framework
sudo systemctl start hermes-framework
```

---

## 13. Scripts Reference

### 13.1 Agent Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `agent-create.sh` | Create new agent from template | `--id <id> [--model <model>] [--name <name>]` |
| `agent-delete.sh` | Delete agent and all files | `--id <id> [--force]` |
| `agent-export.sh` | Export agent to archive/volume/container | `--id <id> --dest <path> --mode <mode>` |
| `agent-import.sh` | Import agent from archive/directory | `--source <path> --target <id> [--overwrite]` |
| `agent-control.sh` | Start/stop/restart agent | `<command> <id> [--force]` |
| `agent-logs.sh` | View agent logs | `<id>` |
| `agent-monitor.sh` | Monitor agent activity | `<id>` |
| `agent-restart.sh` | Restart agent | `<id>` |
| `agent-run.sh` | Run agent directly | `<id>` |
| `agent-stop.sh` | Stop agent | `<id>` |
| `migrate-agent.sh` | Migrate agent from old format | `<old-path> <new-id>` |

### 13.2 Crew Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `crew-create.sh` | Create new crew | `<name> <agent1> [agent2] ...` |
| `crew-start.sh` | Start crew | `<name>` |
| `crew-stop.sh` | Stop crew | `<name>` |
| `crew-join.sh` | Agent joins crew | `<crew> <agent>` |
| `crew-leave.sh` | Agent leaves crew | `<crew> <agent>` |
| `crew-dissolve.sh` | Dissolve crew | `<name>` |
| `crew-export.sh` | Export crew | `<name> --dest <path>` |
| `crew-import.sh` | Import crew | `--source <path> --target <name>` |
| `crew-list.sh` | List all crews | (no args) |
| `crew-monitor.sh` | Monitor crew activity | `<name>` |
| `crew-blueprint.sh` | Generate crew blueprint | `<name>` |
| `create_crew.py` | Crew creation (Python) | `<name> [options]` |

### 13.3 System Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `runtime.sh` | Interactive management console | (interactive) |
| `setup.sh` | Basic system setup | (no args) |
| `setup-wizard.sh` | Interactive setup wizard | `--agent` |
| `setup-qwen3-llama.sh` | Qwen3 + Llama.cpp setup | (no args) |
| `setup-aliases.sh` | Shell alias setup | (no args) |
| `health-check.sh` | Health check runner | (no args) |
| `runtime-doctor.sh` | Runtime health check | (no args) |
| `runtime-validate.sh` | Runtime validation | (no args) |
| `validate.sh` | Configuration validation | (no args) |
| `validate-all-skills.sh` | Skill validation | (no args) |
| `clean.sh` | Clean temporary files | (no args) |
| `test.sh` | Test runner | (no args) |

### 13.4 Backup Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `backup.sh` | Backup script | `[options]` |
| `backup-interactive.sh` | Interactive backup tool | `[--mode <mode>]` |
| `restore.sh` | Restore from backup | `<backup-path>` |
| `hemlock-snapshot.sh` | System snapshot | (no args) |

### 13.5 Memory Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `memory.sh` | Memory management | (no args) |
| `tool-inject-memory.sh` | Memory context injection | `<id> [--all]` |
| `autonomy.sh` | Autonomy configuration | (no args) |

### 13.6 Security Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `security-check.sh` | Security audit | (no args) |
| `security-harden.sh` | Security hardening | `[--rotate]` |
| `key_inject.py` | OpenClaw → Hermes key injection | `--from-openclaw` |

### 13.7 Gateway Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `gateway-setup.sh` | Gateway configuration | `<platform> <agent>` |
| `hermes-run.sh` | Run Hermes standalone | (no args) |
| `hermes-stop.sh` | Stop Hermes | (no args) |
| `hermes-logs.sh` | Hermes log viewer | (no args) |

### 13.8 Utility Scripts

| Script | Purpose | Usage |
|--------|---------|-------|
| `helpers.sh` | Shared helper functions | (sourced) |
| `enforce.sh` | System enforcement | (no args) |
| `docs-indexer.sh` | Documentation indexer | (no args) |
| `pm-create.sh` | Project manager creation | (no args) |
| `skills-install.sh` | Skill installation | `<agent>` |
| `auto-sync-snaps.sh` | Auto-sync snapshots | (no args) |

### 13.9 Plugin Toolkit

Located in `plugins/scripts/agent-toolkit/`:

| Script | Purpose | Usage |
|--------|---------|-------|
| `enforce.sh` | Workspace enforcement | `[workspace-path]` |
| `secret.sh` | Encrypted secret management | `<command> [args]` |
| `memory-log.sh` | Memory logging | (no args) |
| `memory-promote.sh` | Memory promotion | (no args) |
| `hemlock-doctor.sh` | Plugin health check | (no args) |
| `jsonfmt.py` | JSON formatting | (no args) |
| `TOOLS-GUIDE.md` | Tool reference | (documentation) |

---

## 14. Docker Architecture

### 14.1 Dockerfile.runtime

The primary runtime image combining OpenClaw and Hermes:

```dockerfile
# =============================================================================
# Hemlock Runtime Dockerfile
#
# OpenClaw (control plane) + Hermes (cognition layer)
# OpenClaw drives: gateway, MCP, platform routing, agent lifecycle
# Hermes thinks: agent loop, self-learning brain, tool execution
#
# Dual mode:
#   Default: OpenClaw → MCP → Hermes (full stack)
#   HERMES_ONLY=1: Hermes standalone (no OpenClaw)
#   OPENCLAW_ONLY=1: OpenClaw gateway only (no Hermes brain)
# =============================================================================

FROM python:3.12-slim AS builder

WORKDIR /build

# Install build deps only
COPY docker/hermes-agent/pyproject.toml /build/
RUN pip install --no-cache-dir --upgrade pip setuptools wheel && \
    pip install --no-cache-dir --prefix=/install . && \
    pip install --no-cache-dir --prefix=/install python-telegram-bot>=20.0

# =============================================================================
# Runtime stage — OpenClaw + Hermes
# =============================================================================
FROM python:3.12-slim

# Portability: all paths via env vars, resolved by PathResolver
ENV HEMLOCK_DOCKER=1 \
    PYTHONUNBUFFERED=1 \
    PYTHONPATH=/opt/hermes \
    HERMES_HOME=/runtime \
    OPENCLAW_ROOT=/opt/openclaw

# Install node for OpenClaw runtime
RUN apt-get update && \
    apt-get install -y --no-install-recommends procps bash && \
    rm -rf /var/lib/apt/lists/*

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# ── OpenClaw (control plane) ─────────────────────────────────────────────────
# Three folders: bin/, lib/node_modules/openclaw/, tools/node/
COPY docker/openclaw-runtime/bin/ /opt/openclaw/bin/
COPY docker/openclaw-runtime/lib/node_modules/openclaw/ /opt/openclaw/lib/node_modules/openclaw/
COPY docker/openclaw-runtime/tools/node/ /opt/openclaw/tools/node/

RUN chmod +x /opt/openclaw/bin/openclaw-container && \
    ln -s /opt/openclaw/bin/openclaw-container /usr/local/bin/openclaw

# ── Hermes (cognition layer) ─────────────────────────────────────────────────
COPY docker/hermes-agent/ /opt/hermes/

# Copy health validators
COPY health/ /opt/hermes/health/

# Copy key injection script
COPY scripts/key_inject.py /opt/hermes/scripts/key_inject.py

# Create runtime directories (PathResolver will use /runtime, /agents, etc.)
RUN mkdir -p /runtime /agents /crews /projects /skills /backups /logs /memory /plugins /config /models /scripts

# Health check — verify core imports work and paths resolve
RUN python3 -c "\
from paths import resolver; \
print(f'PathResolver: root={resolver.root}, docker={resolver.is_docker}'); \
print(f'  agents={resolver.agents_dir}'); \
print(f'  skills={resolver.skills_root}'); \
print(f'  hermes_home={resolver.hermes_home}'); \
" && \
    python3 -c "import gateway.protocol; import autonomy.protocol; import crew.lifecycle" && \
    python3 -c "from health.doctor_bridge import run_all_checks; report = run_all_checks(quick=True); print(f'Health: {report.ok_count} ok, {report.warn_count} warn, {report.fail_count} fail')" && \
    echo "Core imports OK" && \
    openclaw --version 2>/dev/null || echo "OpenClaw binary ready"

WORKDIR /opt/hermes

EXPOSE 18789

# Health check via doctor bridge
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python3 -m health.doctor_bridge --quick --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if d.get('healthy') else 1)" || exit 1

# Entrypoint: dual mode — OpenClaw-driven (default), Hermes-only, or OpenClaw-only
ENTRYPOINT ["/opt/hermes/docker/entrypoint.sh"]
CMD []
```

### 14.2 entrypoint.sh

The entrypoint script handles dual-mode startup:

```bash
#!/bin/bash
# =============================================================================
# OpenClaw Hermes Agent Entrypoint
#
# Connects Hermes agent to OpenClaw Gateway and starts the agent loop
# Supports both individual agent mode and crew (multi-agent) mode
# =============================================================================

set -euo pipefail

# Validate required environment variables
if [[ -z "${AGENT_ID:-}" ]]; then
    echo "ERROR: AGENT_ID environment variable is required"
    exit 1
fi

if [[ -z "${MODEL:-}" ]]; then
    echo "ERROR: MODEL environment variable is required"
    exit 1
fi

if [[ -z "${OPENCLAW_GATEWAY_URL:-}" ]]; then
    echo "ERROR: OPENCLAW_GATEWAY_URL environment variable is required"
    exit 1
fi

if [[ -z "${OPENCLAW_GATEWAY_TOKEN:-}" ]]; then
    echo "ERROR: OPENCLAW_GATEWAY_TOKEN environment variable is required"
    exit 1
fi

# Determine if we're in crew mode
if [[ -n "${CREW_CHANNEL:-}" ]]; then
    echo "Mode: CREW (multi-agent collaboration)"
    # Connect to Gateway with crew channel
    hermes gateway connect \
      --url "$OPENCLAW_GATEWAY_URL" \
      --token "$OPENCLAW_GATEWAY_TOKEN" \
      --channel "$CREW_CHANNEL" &
    GATEWAY_PID=$!

    # Start Hermes agent in crew mode
    exec hermes --agent-id "$AGENT_ID" --model "$MODEL" --crew "$CREW_CHANNEL" --tui
else
    echo "Mode: INDIVIDUAL (single-agent)"
    # Connect to Gateway in individual mode
    hermes gateway connect \
      --url "$OPENCLAW_GATEWAY_URL" \
      --token "$OPENCLAW_GATEWAY_TOKEN" &
    GATEWAY_PID=$!

    # Start Hermes agent in individual mode
    exec hermes --agent-id "$AGENT_ID" --model "$MODEL" --tui
fi
```

### 14.3 Volume Mounts

**Development (docker-compose.yml):**
```yaml
volumes:
  - ./runtime:/runtime          # Runtime state
  - ./agents:/data/agents       # Agent workspaces
  - ./crews:/data/crews         # Crew definitions
  - ./models:/models            # Model configurations
  - ./backups:/backups          # Backup storage
  - ./skills/skills:/skills:ro  # Skills (read-only)
```

**Production (docker-compose.runtime.yml):**
```yaml
volumes:
  - runtime_data:/runtime       # Named volume
  - agents_data:/data/agents    # Named volume
  - crews_data:/data/crews      # Named volume
  - projects_data:/projects     # Named volume
  - logs_data:/logs             # Named volume
  - memory_data:/memory         # Named volume
  - skills_data:/skills:ro      # Named volume (read-only)
  - backups_data:/backups       # Named volume
  - plugins_data:/plugins       # Named volume
  - config_data:/config         # Named volume
```

### 14.4 Container Naming Convention

| Container | Purpose | Naming Pattern |
|-----------|---------|---------------|
| Runtime | Main runtime service | `hemlock_runtime` |
| Agent | Agent container | `hemlock_agent` |
| Doctor | Health check service | `hemlock_doctor` |
| Setup | Setup service | `hemlock_setup` |
| Individual Agent | Per-agent container | `oc-<agent-id>` |

### 14.5 Network Configuration

**Default Network:** `agents_net`

**Port Mapping:**
- `18789:18789` — OpenClaw Gateway (WebSocket/HTTP)

**Security:**
- `icc: false` — Inter-container communication disabled
- `read_only: true` — Read-only root filesystem
- `cap_drop: true` — All capabilities dropped
- `tmpfs: true` — Writable directories on tmpfs

---

## 15. Troubleshooting

### 15.1 Common Issues and Fixes

#### Agent Fails to Start

**Symptoms:**
- Container exits immediately
- `docker ps` shows container as "Exited"
- Health check fails

**Diagnosis:**
```bash
# Check container logs
docker logs oc-<agent-id>

# Check health status
docker inspect -f '{{.State.Health.Status}}' oc-<agent-id>

# Run health check
docker exec oc-<agent-id> python3 -m health.doctor_bridge --quick
```

**Fixes:**
1. Check environment variables are set correctly
2. Verify agent workspace exists and has required files
3. Run workspace enforcement: `docker exec oc-<agent-id> bash tools/enforce.sh`
4. Check Docker daemon is running: `docker info`
5. Verify port 18789 is not in use: `ss -tuln | grep 18789`

#### Permission Errors (chmod 700)

**Symptoms:**
- "Permission denied" errors
- Agent can't access its own files
- Enforcement script fails

**Diagnosis:**
```bash
# Find 700 permissions
find /path/to/workspace -type d -perm 700
find /path/to/workspace -type f -perm 700

# Check ownership
find /path/to/workspace -maxdepth 3 -user root
```

**Fixes:**
```bash
# Fix directory permissions
find /path/to/workspace -type d -perm 700 -exec chmod 755 {} \;

# Fix file permissions
find /path/to/workspace -type f -perm 700 -exec chmod 644 {} \;

# Fix ownership
sudo chown -R $(id -u):$(id -g) /path/to/workspace

# Run enforcement
bash tools/enforce.sh /path/to/workspace
```

#### Gateway Connectivity Issues

**Symptoms:**
- Agent can't connect to gateway
- "Connection refused" errors
- Messages not routing

**Diagnosis:**
```bash
# Check gateway is running
docker ps | grep gateway

# Check gateway logs
docker logs hermes_framework

# Test connectivity
curl http://localhost:18789/health
```

**Fixes:**
1. Restart gateway: `docker compose restart framework`
2. Check gateway token matches: `echo $OPENCLAW_GATEWAY_TOKEN`
3. Verify network connectivity: `docker network inspect agents_net`
4. Check firewall rules: `sudo iptables -L`

#### Memory Corruption

**Symptoms:**
- Agent loses context between sessions
- Memory files are corrupted
- State database errors

**Diagnosis:**
```bash
# Check memory files
ls -la /path/to/workspace/memory/

# Check state database
docker exec oc-<agent-id> python3 -c "import sqlite3; conn = sqlite3.connect('/runtime/state.db'); print('OK')"

# Run persistence check
python3 -m health.doctor_bridge --categories persistence
```

**Fixes:**
1. Restore from backup: `./scripts/restore.sh <backup-path>`
2. Rebuild state: `docker exec oc-<agent-id> python3 -m hermes.state.rebuild`
3. Clear corrupted memory: `rm /path/to/workspace/memory/*.json`

#### Key Injection Failure

**Symptoms:**
- API keys not available to agent
- "Key not found" errors
- Authentication failures

**Diagnosis:**
```bash
# Check OpenClaw config exists
ls -la ~/.openclaw/openclaw.json

# Run key injection
python3 -m scripts.key_inject --from-openclaw --dry-run

# Check injected keys
cat /runtime/.env
ls -la /runtime/.secrets/
```

**Fixes:**
1. Verify OpenClaw config file exists and is valid JSON
2. Re-run key injection: `python3 -m scripts.key_inject --from-openclaw`
3. Check .secrets/ directory permissions: `ls -la /runtime/.secrets/`
4. Re-generate encryption key: `bash tools/secret.sh init`

#### Docker Volume Issues

**Symptoms:**
- Volume not mounting
- Permission denied on volume
- Data not persisting

**Diagnosis:**
```bash
# List volumes
docker volume ls

# Inspect volume
docker volume inspect agents_data

# Check volume contents
docker run --rm -v agents_data:/data alpine ls -la /data
```

**Fixes:**
1. Remove and recreate volume: `docker volume rm agents_data && docker volume create agents_data`
2. Check Docker daemon: `sudo systemctl restart docker`
3. Verify disk space: `df -h`

#### Crew Communication Failure

**Symptoms:**
- Agents in crew can't communicate
- Messages not appearing in crew channel
- Crew status shows disconnected

**Diagnosis:**
```bash
# Check crew configuration
cat crews/<crew-name>/crew.yaml

# Check agent crew channel
docker exec oc-<agent-id> echo $CREW_CHANNEL

# Check gateway crew routing
docker logs hermes_framework | grep crew
```

**Fixes:**
1. Restart crew: `./scripts/crew-stop.sh <name> && ./scripts/crew-start.sh <name>`
2. Verify all agents are in crew channel
3. Check crew configuration is valid YAML
4. Restart gateway to reset routing

### 15.2 Diagnostic Commands

```bash
# Full system health check
python3 -m health.doctor_bridge

# System status
./runtime.sh
# Select: 3.1) System status

# Self-check
./runtime.sh
# Select: 3.2) Self-check

# Docker status
docker compose ps
docker compose logs

# Agent logs
docker logs oc-<agent-id>
./scripts/agent-logs.sh <agent-id>

# Runtime logs
tail -f logs/runtime.log
tail -f runtime/logs/gateway.log
tail -f runtime/logs/agent.log
tail -f runtime/logs/errors.log

# Resource usage
docker stats
df -h
free -m
```

### 15.3 Recovery Procedures

#### Full System Recovery

```bash
# 1. Stop all services
docker compose down

# 2. Backup current state
tar czf hemlock-backup-$(date +%Y%m%d).tar.gz \
  --exclude='.git' \
  --exclude='node_modules' \
  --exclude='__pycache__' \
  .

# 3. Pull latest images
docker compose pull

# 4. Rebuild if needed
docker compose build

# 5. Start services
docker compose up -d

# 6. Verify health
python3 -m health.doctor_bridge --quick
```

#### Agent Recovery

```bash
# 1. Stop agent
./scripts/agent-control.sh stop <agent-id>

# 2. Backup agent
./scripts/agent-export.sh --id <agent-id> --dest /tmp/agent-backup --mode FULL

# 3. Run enforcement
docker exec oc-<agent-id> bash tools/enforce.sh

# 4. Restart agent
./scripts/agent-control.sh start <agent-id>

# 5. Verify health
docker exec oc-<agent-id> python3 -m health.doctor_bridge --quick
```

#### Crew Recovery

```bash
# 1. Stop crew
./scripts/crew-stop.sh <crew-name>

# 2. Export crew
./scripts/crew-export.sh <crew-name> --dest /tmp/crew-backup

# 3. Verify crew config
cat crews/<crew-name>/crew.yaml

# 4. Restart crew
./scripts/crew-start.sh <crew-name>

# 5. Verify all agents connected
./scripts/crew-monitor.sh <crew-name>
```

### 15.4 Error States Reference

| Error State | Detection | Recovery |
|-------------|-----------|----------|
| Agent Crash | Health check failure, container exited | Automatic restart, manual start |
| Memory Corruption | Persistence validation failure | Restore from backup |
| Key Rotation Failure | Secret validation failure | Manual key re-injection |
| Network Partition | Gateway connectivity failure | Wait for network restoration |
| Disk Full | Disk usage monitoring | Clean logs/backups |
| Configuration Drift | Configuration validation failure | Re-apply configuration |
| Permission Lockout | 700 permissions found | Run enforcement, fix permissions |
| Identity Cross-Contamination | SOUL.md doesn't match agent name | Re-create SOUL.md, run enforcement |
| Secret Decryption Failure | .secret-key missing or corrupted | Re-generate key, migrate secrets |
| Gateway Token Mismatch | Auth failures on gateway | Sync tokens, restart gateway |

---

## Appendix A: Glossary

| Term | Definition |
|------|-----------|
| **Agent** | An autonomous AI entity with its own workspace, memory, and tools |
| **Crew** | A group of agents working together on a shared task |
| **OpenClaw** | The control plane: gateway, MCP, platform routing |
| **Hermes** | The cognition layer: agent loop, brain, tool execution |
| **MCP** | Model Context Protocol — bridge between OpenClaw and Hermes |
| **SOUL.md** | Agent personality and core principles |
| **HEARTBEAT.md** | Periodic task definitions (cron-like) |
| **Doctor Bridge** | Health validation system |
| **Enforcement** | Workspace structure validation and repair |
| **Key Injection** | Mapping OpenClaw config to Hermes environment |
| **A2A** | Agent-to-Agent communication |
| **HERMES_HOME** | Runtime data directory (default: /runtime) |
| **workspace-template** | Template for creating new agents |

## Appendix B: Quick Reference

### Essential Commands

```bash
# Start system
docker compose -f docker-compose.runtime.yml up -d

# Check health
python3 -m health.doctor_bridge --quick

# Create agent
./scripts/agent-create.sh --id my-agent --model ollama/qwen3:0.6b

# Create crew
./scripts/crew-create.sh my-team agent1 agent2

# Open management console
./runtime.sh

# View logs
docker compose logs -f

# Stop system
docker compose down
```

### File Locations

| File | Location | Purpose |
|------|----------|---------|
| Agent workspace | `agents/<id>/` | Agent files |
| Runtime state | `runtime/` | System state |
| Health checks | `health/` | Validators |
| Scripts | `scripts/` | Management tools |
| Plugins | `plugins/` | Extensions |
| Config | `config/` | Configuration |
| Crews | `crews/` | Crew definitions |
| Skills | `skills/` | Skill registry |

### Port Reference

| Port | Service | Protocol |
|------|---------|----------|
| 18789 | OpenClaw Gateway | WebSocket/HTTP |
| 11434 | Ollama (local) | HTTP |

---

*This blueprint is the final source of truth for the Hemlock Enterprise Agent Framework. All implementation details, configurations, and procedures documented herein reflect the actual codebase at `/home/drdeek/projects/hemlock/`.*

*For questions or updates, refer to the repository documentation or contact the framework maintainers.*