# Hemlock Agent Framework Integration Blueprint
## Enterprise-Grade Integration of Autonomous Crew, Workspace Template, Builder Codes & Enterprise Blueprint

**Generated**: 2026-06-14  
**Status**: Enterprise Grade Validated (45/48 checks passed, 3 warnings)  
**Rollback Tag**: `[INTEGRATION-BLUEPRINT-v1]`

---

## Integration Overview

This document captures the integration patterns for unifying four major subsystems into the Hemlock Minimal runtime:

| Subsystem | Source | Integration Target |
|-----------|--------|-------------------|
| **Autonomous Crew** | `/references/crew/autonomous-crew/` | Agent templates, blueprint workflows, checkpoints, agent roles |
| **Workspace Template** | `/references/add-ons/workspace-template/` | Agent identity stack (SOUL/AGENTS/IDENTITY/USER/TOOLS/MEMORY/HEARTBEAT/agent.json) |
| **Builder Codes** | `/skills/adding-builder-codes/` | ERC-8021 onchain attribution (Base) |
| **Enterprise Blueprint** | `/skills/enterprise-blueprint/` | Phase-gated validation, checklists, feature flags |

---

## Integration Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ HOST: usb-setup-assistant.sh                                    │
│  ├── USB Ventoy + Persistence                                   │
│  ├── VM Auto-Boot (headless, SSH 2222)                          │
│  ├── Hemlock Container Deployment (hemlock-runtime)             │
│  │   ├── Volumes: gateway, agents, crews, skills, models       │
│  │   ├── Ports: 18789 (gateway), 8080/8888/11434 (compute)     │
│  │   └── Auto-start (systemd/LaunchAgent)                       │
│  └── Auto-start Services                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ CONTAINER (hemlock-runtime)                                     │
│  ├── Management:                                                │
│  │   ├── /scripts/hemlock (host CLI)                            │
│  │   ├── /scripts/hemlock-tui (container TUI)                   │
│  │   ├── /scripts/model-manager.sh (llama.cpp mgmt)             │
│  │   ├── /scripts/agent_manager.py (agent lifecycle)            │
│  │   ├── /scripts/crew_manager.py (blueprint + checkpoints)     │
│  │   ├── /scripts/lead_agent.py (agent orchestration)           │
│  │   ├── /scripts/skill_installer/ (skill management)           │
│  │   ├── /scripts/builder_code_integration.py (ERC-8021)        │
│  │   ├── /scripts/setup-wizard.sh (interactive setup)           │
│  │   ├── /scripts/init_blueprint.py, validate_blueprint.py,     │
│  │   │   generate_checklist.py, assign_agents.py                │
│  │   └── /scripts/model-manager.sh (llama.cpp mgmt)             │
│  └── Volumes:                                                   │
│      ├── /workspace/gateway (config, token)                     │
│      ├── /agents/agent-id/ (workspace + identity stack)         │
│      ├── /crews/crew-id/ (blueprint + checkpoints + logs)       │
│      ├── /skills (157 skills, read-only)                        │
│      └── /models (GGUF models, llama.cpp, KV cache)             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Key Integration Patterns

### 1. Agent Identity Stack (Workspace Template → Agent Manager)

**Source**: `/references/add-ons/workspace-template/`

**Files to inject into `agent_manager.py` `create_agent()`**:
- `SOUL.md` — Core identity, personality, purpose, model, principles
- `AGENTS.md` — Session protocol, startup sequence, communication rules
- `IDENTITY.md` — Agent metadata, role, capabilities, relationships
- `USER.md` — Human operator profile, preferences, communication guidelines
- `TOOLS.md` — Available tools, specialized capabilities per expertise
- `MEMORY.md` — Long-term curated memory (flat files in `memory/`, sessions in `sessions/`)
- `HEARTBEAT.md` — Periodic tasks, health checks, session markers
- `agent.json` — Machine-readable identity (id, name, type, personality, expertise, **builderCode**)

**Integration Pattern** (in `agent_manager.py` `create_agent()`):
```python
# After workspace creation, generate all 8 identity files from templates
template_files = {
    "SOUL.md": soul_template,
    "AGENTS.md": agents_template,
    "IDENTITY.md": identity_template,
    "USER.md": user_template,
    "TOOLS.md": tools_template,
    "MEMORY.md": memory_template,
    "HEARTBEAT.md": heartbeat_template,
    "agent.json": agent_json_with_builder_code,
}
for filename, content in template_files.items():
    (agent_dir / filename).write_text(content.format(...))
```

**Builder Code Integration** (auto on creation):
```python
builder_manager = get_builder_code_manager()
agent_json['builderCode'] = {
    'code': builder_manager.BUILDER_CODE,
    'hex': builder_manager.BUILDER_CODE_HEX,
    'owner': builder_manager.OWNER_ADDRESS,
    'hardwired': True,
    'enforced': True
}
builder_manager.register_agent(
    agent_id=identity.agent_id,
    agent_name=identity.name,
    agent_type=agent_type,
    parent_agent="system",
    metadata={...}
)
```

### 2. Agent Templates (8 Specialized Types)

| Type | Prefix | Personality Traits | Expertise | Avatars |
|------|--------|-------------------|-----------|---------|
| `ui` |UI| Creative, user-focused, aesthetic-driven, iterative | UI Design, UX, Responsive, Accessibility, Design Systems | 🎨 🖌️ ✨ 🎯 |
| `integration` |Integ| Systematic, performance-obsessed, scalability-minded | System Architecture, API Design, Data Flow, Microservices | 🔗 ⚡ 🔄 🌐 |
| `blockchain` |Chain| Security-conscious, cryptographic expert, trust-minimizing | Blockchain Dev, Smart Contracts, Crypto Security, DeFi, ZK Proofs | 🔐 ⛓️ 🛡️ 🔒 |
| `debugger` |Debug| Investigative, root-cause obsessed, methodical | Root Cause Analysis, Debugging, Profiling, Error Handling | 🔍 🐛 🧪 🛠️ |
| `documentation` |Doc| Clear, concise, user-educator, structure-focused | Technical Writing, API Docs, User Guides, Code Docs | 📚 📝 📖 ✍️ |
| `optimization` |Opt| Performance-obsessed, efficiency-driven, data-analytical | Perf Optimization, Code Efficiency, Resource Mgmt, Caching, DB Optimization | ⚡ 🚀 📊 💨 |
| `architecture` |Arch| Big-picture, structure-focused, scalability-minded | System Architecture, Project Structure, Org Design, Workflow Opt | 🏗️ 📐 🏛️ 🧩 |
| `validation` |Val| Quality-obsessed, test-driven, standards-enforcing | QA, Test Automation, Validation, Compliance, Perf Testing | ✅ 🧪 🔬 🎯 |

**Template Structure** (per template):
```python
AgentTemplate(
    agent_type="ui",
    name_prefix="UI",
    personality_traits=["Creative...", "User-focused...", ...],
    expertise_areas=["User Interface Design", "UX Optimization", ...],
    communication_styles=["Visual...", "User-centric...", ...],
    avatar_options=["🎨", "🖌️", "✨", "🎯"],
    system_prompt_template="...",
    soul_template="...",
    agents_template="...",
)
```

### 3. Crew Orchestration (Blueprint + Checkpoints)

**Source**: `/references/crew/autonomous-crew/autonomous_crew.py`

**Phases**: `PLANNING` → `CONFIRMATION` → `ACTING` → `VALIDATION` → `COMPLETED`

**Artifacts Created**:
- `blueprint.json` — Project spec, success criteria, agent types, workflow steps, checkpoints
- `CHANGELOG.md` — Enterprise format (Added/Changed/Fixed per version)
- `checkpoint-<id>/` — Git-backed snapshots with rollback capability
- `.crew/agents/<id>.json` — Per-agent logs (actions, summary, files modified)

**Commands**:
```bash
hemlock crew-create <name> --agents alpha,beta
hemlock checkpoint create "msg"
hemlock checkpoint rollback <id>
hemlock crew-attach <name>
hemlock crew-detach <name>
hemlock crew-list
```

### 4. Model Management (llama.cpp + Hardware Detection)

**Dockerfile Build** (in `Dockerfile.runtime`):
```dockerfile
RUN apt-get update && apt-get install -y cmake git build-essential && \
    git clone https://github.com/ggerganov/llama.cpp /opt/llama.cpp && \
    cd /opt/llama.cpp && mkdir -p build && cd build && \
    cmake .. \
        -DLLAMA_CUDA=ON \
        -DLLAMA_METAL=ON \
        -DLLAMA_HIPBLAS=ON \
        -DLLAMA_BLAS=ON \
        -DLLAMA_OPENCL=ON \
        -DLLAMA_VULKAN=ON \
        -DCMAKE_BUILD_TYPE=Release && \
    make -j$(nproc) && \
    cp bin/* /usr/local/bin/ && \
    # cleanup...
```

**Model Manager Commands** (`/scripts/model-manager.sh`):
```bash
hemlock model-list              # List models with metadata
hemlock model-download          # Download from HF (TheBloke, bartowski, etc.)
hemlock model-load              # Load model (auto-ejects current)
hemlock model-unload            # Graceful unload (SIGTERM + timeout)
hemlock model-handoff           # Efficient swap: pre-load → SIGUSR1 → 30s graceful → swap
hemlock model-quantize          # Quantize GGUF (Q2_K through F32)
hemlock model-monitor           # Live VRAM/RAM/GPU monitor
hemlock model-optimize          # Quantize, split, convert, benchmark
hemlock model-mcp llama-model   # Register as MCP tool
```

**Handoff Protocol** (Singleton + Graceful):
```bash
# Singleton lock: /tmp/hemlock-model.lock
# 1. Pre-load next model on port 8081
# 2. Signal current → SIGUSR1 (wind down, 30s graceful)
# 3. Wait for graceful shutdown (30s timeout)
# 4. Swap to new model (port 8080)
# 5. Verify health → register MCP
```

### 5. Builder Codes (ERC-8021)

**Source**: `/skills/adding-builder-codes/`

**Framework Detection Priority**:
1. **Privy** — `@privy-io/react-auth` in package.json/imports
2. **Wagmi** — `wagmi` in package.json (without Privy)
3. **Viem** — `viem` in package.json, no React framework
4. **Standard RPC** — `ethers`, `window.ethereum`, or no Web3 library

**Integration**:
```python
# In agent_manager.create_agent():
builder_manager = get_builder_code_manager()
DATA_SUFFIX = builder_manager.generate_attribution(builder_code)

# In gateway transaction middleware:
# Append DATA_SUFFIX to all agent transactions
```

**Verification**:
- Base Sepolia tx → base.dev analytics shows builder code
- Block explorer confirms last 16 bytes = `8021` repeat

### 6. Setup Wizard (Interactive)

**Source**: `/references/add-ons/setup-wizard.sh`

**Flow**: Provider → Model → Runtime → Agents → Crews → Deploy

**Providers**: Ollama (local), OpenAI, Anthropic, Groq, Together, Mistral, Custom

**Persists**:
- `.env.wizard` — Provider/model env vars
- `config/runtime.yaml` — Gateway port, token, bind, log level
- `config/provider.yaml` — Provider config

### 7. Enterprise Blueprint Integration

**Source**: `/skills/enterprise-blueprint/`

**Scripts**: `init_blueprint.py`, `validate_blueprint.py`, `generate_checklist.py`, `assign_agents.py`

**Validation Gates** (at every phase):
```bash
# No phase advance without validation PASS
hemlock validate <project>           # validate_blueprint.py --json
hemlock checklist-sync <project>     # generate_checklist.py --sync
hemlock assign <agent> <phase|module>  # assign_agents.py
```

**Feature Flag Architecture**:
| Flag | Phase | Enable Condition |
|------|-------|------------------|
| `FEAT_AGENT_TEMPLATES` | 1 | PHASE-1 complete |
| `FEAT_CREW_ORCHESTRATION` | 2 | PHASE-2 complete |
| `FEAT_MODEL_MGMT` | 3a | PHASE-3a complete |
| `FEAT_MODEL_HANDOFF` | 3b | PHASE-3b complete |
| `FEAT_BUILDER_CODES` | 4 | PHASE-4 complete |
| `FEAT_SETUP_WIZARD` | 4 | PHASE-4 complete |
| `FEAT_BLUEPRINT_ENGINE` | 5 | PHASE-5 complete |

---

## Implementation Phases

| Phase | Week | Modules | Gate |
|-------|------|---------|------|
| **PHASE-1** | Week 1 | MOD-001/002/003 | `agent-create` → 8 files + builderCode |
| **PHASE-2** | Week 2 | MOD-004 | `crew-create` → blueprint + git + checkpoint |
| **PHASE-3a** | Week 2-3 | MOD-005 | `model-load` → API healthy |
| **PHASE-3b** | Week 3 | MOD-006 | `model-handoff` → swap <30s, zero loss |
| **PHASE-4** | Week 3 | MOD-007/008 | Wizard → gateway + Base attribution |
| **PHASE-5** | Week 3 | MOD-009/011/013 | Validator gates at every phase |
| **PHASE-6** | Week 4 | ALL | Full regression: USB → SSH → agents ready |

---

## Auto-Start Services

**Linux (systemd)**:
- `hemlock-gateway.service` — Container with `Restart=always`
- `hemlock-usb-detect.service` — Monitors Ventoy USB → starts VM + Hemlock

**macOS (LaunchAgent)**:
- `com.hemlock.gateway.plist` — KeepAlive, RestartInterval=10

**Flow on USB Insert**:
1. `hemlock-usb-detect` detects Ventoy via `blkid`
2. Ensures `hemlock-gateway` container running → auto-attaches agents
3. Starts QEMU VM headless with SSH port 2222

---

## Validation Gates (Enforced)

| Gate | Command | Success Criteria |
|------|---------|------------------|
| **M1** | `hemlock agent-create ui Test` | 8 files + agent.json with builderCode |
| **M2** | `hemlock crew-create <name> --agents` | blueprint + git + CHANGELOG + checkpoint-001 |
| **M3** | `hemlock model-load <model>` | API at `http://localhost:8080/v1/chat/completions` healthy |
| **M4** | `hemlock model-handoff <model>` | Swap <30s, zero request loss |
| **M5** | `hemlock validate --json` | PASS (0 FAIL, 0-4 WARN) |
| **M6** | USB plug-in → SSH → agents ready | All systems auto-start |

---

## Validation (Enterprise Grade)

```bash
# Validate blueprint (must pass 0 FAIL, 0-4 WARN)
python3 scripts/validate_blueprint.py INTEGRATION_BLUEPRINT.md --json

# Sync checklist after blueprint changes
python3 scripts/generate_checklist.py INTEGRATION_BLUEPRINT.md --sync

# Assign agents
python3 scripts/assign_agents.py ./project --assign "lead:PHASE-1-v1"
python3 scripts/assign_agents.py ./project --assign "integration:PHASE-2-v1"
python3 scripts/assign_agents.py ./project --assign "blockchain:PHASE-4-v1"
python3 scripts/assign_agents.py ./project --assign "optimization:PHASE-3-v1"
python3 scripts/assign_agents.py ./project --assign "validation:PHASE-5-v1"
```

---

## References

| File | Purpose |
|------|---------|
| `INTEGRATION_BLUEPRINT.md` | Full enterprise blueprint (validated) |
| `checklist.md` | Phase-gated implementation checklist |
| `references/autonomous-crew-agent-manager.md` | Agent manager patterns |
| `references/autonomous-crew-autonomous-crew.py` | Crew orchestration patterns |
| `references/workspace-template-identity-stack.md` | Agent identity stack files |
| `references/adding-builder-codes.md` | ERC-8021 integration |
| `references/enterprise-blueprint-toolkit.md` | Blueprint toolkit usage |
| `references/setup-wizard-patterns.md` | Interactive wizard patterns |
| `references/ventoy-usb-deployment.md` | Ventoy USB deployment |

---

*This integration blueprint is maintained alongside the Hemlock Minimal skill. Update both when integration patterns evolve.*