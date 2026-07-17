# Autonomous Crew Integration Patterns
## Agent Manager & Crew Orchestration Integration for Hemlock Minimal

**Source**: `/tmp/hemlock-minimal/hemlock-minimal/references/crew/autonomous-crew/`

---

## Agent Manager Patterns (`agent_manager.py`)

### Agent Templates with Rich Identity

The autonomous-crew system provides 8 specialized agent templates with full personality, expertise, and communication style definitions:

```python
AGENT_TEMPLATES = {
    "ui": AgentTemplate(
        agent_type="ui",
        name_prefix="UI",
        personality_traits=[
            "Creative and detail-oriented",
            "User-focused and empathetic",
            "Aesthetic-driven with strong design sense",
            "Iterative and perfectionist"
        ],
        expertise_areas=[
            "User Interface Design",
            "User Experience Optimization",
            "Responsive Design",
            "Accessibility Standards",
            "Design Systems",
            "Prototyping"
        ],
        communication_styles=[
            "Visual and descriptive",
            "User-centric language",
            "Solution-oriented",
            "Collaborative"
        ],
        avatar_options=["🎨", "🖌️", "✨", "🎯"],
        system_prompt_template="...",
        soul_template="...",
        agents_template="..."
    ),
    # ... 7 more types: integration, blockchain, debugger, documentation,
    # optimization, architecture, validation
}
```

### Agent Identity Generation

```python
def generate_identity(self, custom_name: Optional[str] = None) -> AgentIdentity:
    agent_id = f"{self.agent_type}-{secrets.token_hex(4)}"
    name = custom_name or f"{self.name_prefix}-{secrets.token_hex(2).upper()}"
    personality = random.choice(self.personality_traits)
    expertise = random.sample(self.expertise_areas, min(3, len(self.expertise_areas)))
    comm_style = random.choice(self.communication_styles)
    avatar = random.choice(self.avatar_options)
    return AgentIdentity(...)
```

### Workspace Initialization (Per Agent)

```python
# Standardized workspace structure
workspace_dir = self.agents_dir / identity.agent_id
agent_dir = workspace_dir / "agent"
agent_dir.mkdir(exist_ok=True)

# Core identity files
(agent_dir / "SOUL.md").write_text(soul_template)
(agent_dir / "AGENTS.md").write_text(agents_template)
(agent_dir / "IDENTITY.md").write_text(identity_template)
(agent_dir / "USER.md").write_text(user_template)
(agent_dir / "TOOLS.md").write_text(tools_template)
(agent_dir / "HEARTBEAT.md").write_text(heartbeat_template)
(agent_dir / "MEMORY.md").write_text("# MEMORY.md\n\nLong-term memories...")
(agent_dir / "agent.json").write_text(json.dumps(agent_json, indent=2))

# Directory structure
for d in ["memory", "sessions", "projects", "config", "cron", "logs", "media", "tools", "avatars"]:
    (workspace_dir / d).mkdir(exist_ok=True)
```

### Builder Code Integration (ERC-8021)

```python
# In create_agent():
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

### Telegram Bot Wizard (Automated)

```python
async def setup_telegram_bot(self, agent_id: str, bot_token: Optional[str] = None) -> Dict:
    # 1. Validate token format
    # 2. Get bot info from Telegram API
    # 3. Generate customized bot script from template
    # 4. Create systemd service file
    # 5. Enable/start service
    # 5. Update agent identity + agent.json
```

**Bot Script Template** (customized per agent):
```python
script = base_script.replace(
    'TOKEN="..."',
    f'TOKEN="{token}"'
).replace(
    "'bot_name': 'Titan'",
    f"'bot_name': '{agent.display_name}'"
).replace(
    "You are Titan, an AI agent...",
    f"You are {agent.display_name}, a {agent_type} specialist..."
).replace(
    "TONE: Casual-professional...",
    f"TONE: {agent.communication_style}. Expertise: {expertise_str}."
)
```

### Issue Detection

```python
def detect_missing_configuration(self, agent_id: Optional[str] = None) -> List[Dict]:
    issues = []
    for agent_id in agents_to_check:
        agent = self.agents[agent_id]
        if not agent.telegram_configured:
            issues.append({
                'type': 'telegram_not_configured',
                'description': 'Telegram bot not configured',
                'resolution': 'Run setup wizard to configure Telegram bot'
            })
        # Check workspace, service status...
    return issues
```

---

## Crew Orchestration (`autonomous_crew.py`)

### Blueprint Workflow

```python
class WorkflowPhase(Enum):
    PLANNING = "planning"
    CONFIRMATION = "confirmation"
    ACTING = "acting"
    VALIDATION = "validation"
    COMPLETED = "completed"

@dataclass
class Blueprint:
    project_name: str
    success_criteria: List[str]
    expected_outcomes: List[str]
    success_measures: List[str]
    agent_types: List[str]
    workflow_steps: List[Dict]  # Phase-gated steps
    checkpoints: List[Dict]
```

### CrewManager Operations

```python
def initialize_crew(self, project_name: str, success_criteria: List[str],
                    agent_types: List[str], expected_outcomes: List[str] = None):
    # 1. Create blueprint with phases
    # 2. Save blueprint.json
    # 2. Initialize CHANGELOG.md (enterprise format)
    # 3. Create agent logs per type
    # 4. Initialize git repo
    # 5. Create initial checkpoint
```

### Checkpoint/Rollback System

```python
def create_checkpoint(self, description: str) -> str:
    # 1. Snapshot project files (excluding .git, .crew)
    # 2. Save checkpoint metadata (id, description, timestamp, phase, agents)
    # 3. Add to blueprint.checkpoints

def rollback_to_checkpoint(self, checkpoint_id: str) -> bool:
    # 1. Backup current state
    # 2. Restore from checkpoint snapshot
    # 3. Log rollback in CHANGELOG.md
```

### Agent Workflow Templates

```python
workflows = {
    AgentType.LEAD.value: [
        "Create project blueprint",
        "Coordinate agent activities",
        "Monitor progress",
        "Validate results",
        "Create checkpoints"
    ],
    AgentType.UI.value: [
        "Analyze UI requirements",
        "Design user interface",
        "Implement UI components",
        "Test UI functionality",
        "Optimize user experience"
    ],
    # ... 7 more types
}
```

### Change Log Protocol

Fields (all required):
```
Date        : 2026-06-14 11:30 UTC
Contributor : Lead
Modules     : [MOD-001, MOD-002]
Section Tags: [[MOD-001-v1], [MOD-002-v1]]
Files Changed: [scripts/agent_manager.py, scripts/Dockerfile.runtime, .env.wizard]
Description : Added agent identity stack generation to create_agent()...
Tests Passing: [unit_agent_manager_create, integration_agent_create, blueprint_validate]
Phase       : PHASE-1
Rollback Ref: git:a1b2c3d4e5f6
```

---

## Key Integration Points for Hemlock Minimal

| Autonomous Crew Component | Hemlock Minimal Integration |
|---------------------------|----------------------------|
| `AgentTemplate` definitions | → `agent_manager.py` templates |
| `AgentIdentity` dataclass | → `AgentIdentity` in `create_agent()` |
| `builder_code_integration` | → `agent_manager.py` + gateway middleware |
| Telegram bot wizard | → `agent_manager.setup_telegram_bot()` |
| `Blueprint` + `checkpoints` | → `crew_manager.py` (new) |
| `agent_logs` + `agent_actions` | → `/crews/<id>/.crew/agents/<id>.json` |
| `rollback_to_checkpoint()` | → `hemlock checkpoint rollback` |
| `detect_missing_configuration()` | → `hemlock doctor` / TUI diagnostics |

---

## Builder Code (ERC-8021) Integration

### Framework Detection (Priority Order)
1. **Privy** — `@privy-io/react-auth` in package.json/imports
2. **Wagmi** — `wagmi` in package.json (without Privy)
3. **Viem** — `viem` in package.json, no React framework
4. **Standard RPC** — `ethers`, `window.ethereum`, or no Web3 library

### Integration Pattern

```python
# In builder_code_integration.py
DATA_SUFFIX = Attribution.toDataSuffix({"codes": ["YOUR-BUILDER-CODE"]})

# Framework-specific:
# Privy → dataSuffix plugin
# Wagmi → client config dataSuffix
# Viem → wallet client dataSuffix
# RPC → append to calldata
```

### Verification
- Base analytics: Check Onchain → Total Transactions for attribution
- Block explorer: Last 16 bytes = `8021` repeating
- Tool: https://builder-code-checker.vercel.app/

---

## Enterprise Blueprint Integration

### Blueprint Toolkit Scripts
```bash
# Initialize new blueprint
python3 scripts/init_blueprint.py "Project Name" --path ./output/project

# Validate blueprint (0 FAIL = Enterprise Grade)
python3 scripts/validate_blueprint.py blueprint.md --json

# Sync checklist after changes
python3 scripts/generate_checklist.py blueprint.md --sync

# Assign agents
python3 scripts/assign_agents.py ./project --assign "architect:PHASE-1"
python3 scripts/assign_agents.py ./project --report
```

### Feature Flag Gates
| Flag | Phase | Enable After |
|------|-------|--------------|
| `FEAT_AGENT_TEMPLATES` | PHASE-1 | Agent templates ready |
| `FEAT_CREW_ORCHESTRATION` | PHASE-2 | Crew system ready |
| `FEAT_MODEL_MGMT` | PHASE-3a | llama.cpp built |
| `FEAT_MODEL_HANDOFF` | PHASE-3b | Handoff working |
| `FEAT_BUILDER_CODES` | PHASE-4 | Attribution working |
| `FEAT_SETUP_WIZARD` | PHASE-4 | Wizard complete |
| `FEAT_BLUEPRINT_ENGINE` | PHASE-5 | Validator passing |

---

## Key Files for Reference

| File | Purpose |
|------|---------|
| `agent_manager.py` | Agent lifecycle, templates, Telegram, builder codes |
| `autonomous_crew.py` | Crew blueprint, checkpoints, rollback, git |
| `lead_agent.py` | Crew management CLI (create, list, setup, detect) |
| `builder_code_integration.py` | ERC-8021 attribution, framework detection |
| `setup-wizard.sh` | Interactive provider/model/runtime/agents/crews |
| `enterprise-blueprint/scripts/` | Blueprint lifecycle toolkit |

---

*This reference captures the autonomous-crew integration patterns validated during Hemlock Minimal integration session (2026-06-14).*