# Verified Reference Implementation — synthesis-1
**Canonical working implementation of agent-identity-architecture for autonomous crew agents**

## Workspace
`${WORKSPACE_ROOT}/synthesis-1/` — Full identity-first agent workspace with all components verified operational.

## Verified Components

### Identity Constitution (t=0)
- **File:** `.agent/constitution.yaml`
- **Identity Hash:** `33b67cd3f423e0d7` (SHA256 of constitution + genesis.md, first 16 chars)
- **Loads before any tool, reasoning, or planning**

### Internalized Habits (3 + 1 crew-specific)
| Habit | File | Triggers | Enforcement |
|-------|------|----------|-------------|
| identity-enforcement | `.agent/habits/identity-enforcement.yaml` | before_any_action (200), agent_initialization (1), completion_claimed (100), heartbeat_received (50) | blocking |
| tool-enforcement | `.agent/habits/tool-enforcement.yaml` | before_tool_invocation (100), agent_initialization (10), workspace_change (50) | blocking + auto_remediate |
| reflective-loop | `.agent/habits/reflective-loop.yaml` | after_tool_invocation (50), completion_claimed (100), heartbeat_received (75) | reflection_required |
| crew-phase-gate | `.agent/habits/crew-phase-gate.yaml` | crew_phase_transition (150), completion_claimed (100), checkpoint_created (75) | blocking |

### Enforcer Daemon
- **Process:** `enforcer_daemon.py` (privileged, agent cannot kill/patch)
- **Socket:** `${ENFORCER_SOCKET_DIR}/synthesis-1.sock` (Unix domain, 0600)
- **RPC Methods:** `validate_workspace`, `execute_tool`, `heartbeat`
- **Validation Loop:** 30s interval, auto-remediates violations
- **Heartbeat Monitor:** 300s interval, stale threshold 600s
- **Audit Log:** `.agent/logs/audit.log` (append-only JSONL)

### Agent Runtime
- **Process:** `agent_runtime.py` (unprivileged, proxies ALL tools via enforcer RPC)
- **Identity Gate:** Runs identity-enforcement + tool-enforcement before every tool
- **Completion Gate:** Runs reflective-loop + crew-phase-gate on claim_completion()
- **Heartbeat:** Sends workspace hash + identity hash + metrics every 300s

### Memory Pipeline
- **Daily:** `memory/daily/YYYY-MM-DD.md` (timestamped entries with wikilinks)
- **Weekly:** `memory/weekly/YYYY-WNN.md` (curated insights/decisions/links)
- **Long-term:** `memory/long-term/MEMORY.md` (promoted lessons, permanent)
- **Knowledge Index:** `memory/knowledge-index.json` (entity → entries from wikilinks)
- **Curator:** `memory_curator.py` runs daily 02:00 UTC

### Required Tools (5)
| Tool | Purpose | Location |
|------|---------|----------|
| `enforce.sh` | Workspace structure validation | `tools/enforce.sh` |
| `secret.sh` | Encrypted secret management (AES-256) | `tools/secret.sh` |
| `memory-log.sh` | Daily memory logging | `tools/memory-log.sh` |
| `memory-promote.sh` | Daily → long-term promotion | `tools/memory-promote.sh` |
| `TOOLS-GUIDE.md` | Tool usage documentation | `tools/TOOLS-GUIDE.md` |

## Verification Results (2026-07-05)

```
✅ Constitution loaded at t=0 (identity hash: 33b67cd3f423e0d7)
✅ 3 internalized habits active + 1 crew-specific
✅ Enforcer RPC established on Unix socket
✅ Workspace hash integrity tracking operational
✅ Completion gated by identity reflection
✅ Memory pipeline: daily → weekly → long-term + knowledge-index
✅ Auto-remediation: missing dirs created, permissions corrected
✅ Builder code registration with identity attestation
```

## Crew Agent Creation Pattern

```bash
# In create-crew-agent.sh — every crew agent gets this identity layer
CREW_ID=hackathon-2026 bash create-crew-agent.sh ui "Frontend Specialist"

# Produces agent workspace with:
# - .agent/constitution.yaml (customized for agent type + crew)
# - .agent/habits/ (4 habits installed)
# - tools/ (5 required tools from templates)
# - memory/ directories
# - enforcer_daemon.py, agent_runtime.py, memory_curator.py
# - start-agent.sh, genesis.md, agent.json
# - Builder code registered with identity attestation
```

## Integration Points for Crew Orchestration

| Crew Operation | Identity Integration |
|----------------|---------------------|
| Phase transition | All agents must `claim_completion()` (reflective-loop) |
| Heartbeat aggregation | `crew-heartbeat.sh` polls all enforcer sockets |
| Identity verification | `verify-crew-identity.sh` checks all agents |
| Builder code | Each agent registered with constitution_hash + habits |
| Memory sharing | Shared knowledge index in `shared/knowledge-index.json` |

## Reproduction

```bash
# 1. Create agent workspace
WORKSPACE_ROOT=/home/agents AGENT_ID=test-agent \
  bash $HOME/.hermes/skills/devops/agent-identity-architecture/scripts/install-agent.sh test-agent

# 2. Start enforcer
python3 $HOME/agents/test-agent/enforcer_daemon.py test-agent &

# 3. Start agent
python3 $HOME/agents/test-agent/agent_runtime.py test-agent

# 4. Verify
bash $HOME/.hermes/skills/devops/agent-identity-architecture/scripts/verify-identity.sh test-agent
```

## Notes

- This implementation is the **canonical reference** for all autonomous crew agents
- Every agent created via `autonomous-crew` inherits this exact structure
- The enforcer daemon MUST run at a privilege level the agent cannot escalate to
- Unix socket permissions MUST be 0600/0700 owned by enforcer user
- All paths in identity files use `$WORKSPACE_ROOT` or `$HOME` — no hardcoded paths