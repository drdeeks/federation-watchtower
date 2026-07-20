#!/usr/bin/env bash
# create-crew-agent.sh - Create crew agent with full identity layer
set -euo pipefail

show_help() {
    cat <<'EOF'
Create Crew Agent - Spawn agent with identity-first architecture

Usage: bash create-crew-agent.sh <agent-type> [custom-name] [--help]

Arguments:
  agent-type      Agent type: ui, integration, blockchain, debugger,
                  documentation, optimization, architecture, validation
  custom-name     Optional custom name (default: TYPE-XXXX)

Options:
  --help          Show this help message

Environment:
  CREW_WORKSPACE    Root directory for crew agents (default: $HOME/crews/<crew-id>)
  CREW_ID          Crew identifier (required)
  WORKSPACE_ROOT   Override agent workspace root (default: $HOME/agents)

Example:
  CREW_ID=hackathon-2026 bash create-crew-agent.sh ui
  CREW_ID=hackathon-2026 bash create-crew-agent.sh blockchain "BC-Explorer"
EOF
    exit 0
}

case "${1:-}" in
    --help|-h) show_help ;;
    "") show_help ;;
esac

AGENT_TYPE="${1:-}"
CUSTOM_NAME="${2:-}"

if [[ -z "$AGENT_TYPE" ]]; then
    echo "ERROR: agent-type required"
    show_help
fi

# Validate agent type
VALID_TYPES="ui integration blockchain debugger documentation optimization architecture validation"
if ! echo "$VALID_TYPES" | grep -qw "$AGENT_TYPE"; then
    echo "ERROR: Invalid agent type. Valid: $VALID_TYPES"
    exit 1
fi

CREW_ID="${CREW_ID:-}"
if [[ -z "$CREW_ID" ]]; then
    echo "ERROR: CREW_ID environment variable required"
    exit 1
fi

CREW_WORKSPACE="${CREW_WORKSPACE:-$HOME/crews/$CREW_ID}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/agents}"

mkdir -p "$CREW_WORKSPACE"
mkdir -p "$WORKSPACE_ROOT"

# Source the agent manager patterns
PYTHON_SCRIPT=$(cat <<'PYEOF'
import sys
import os
import secrets
import json
import hashlib
import datetime
from pathlib import Path

agent_type = sys.argv[1]
custom_name = sys.argv[2] if len(sys.argv) > 2 else None
crew_workspace = Path(sys.argv[3])
workspace_root = Path(sys.argv[4])

# Agent templates (matching autonomous-crew patterns)
TEMPLATES = {
    "ui": {"prefix": "UI", "traits": ["Creative", "Detail-oriented", "User-focused", "Aesthetic-driven"]},
    "integration": {"prefix": "INT", "traits": ["Systems-thinker", "API-first", "Protocol-aware", "Reliability-focused"]},
    "blockchain": {"prefix": "BC", "traits": ["Crypto-native", "Security-first", "Gas-optimized", "MEV-aware"]},
    "debugger": {"prefix": "DBG", "traits": ["Root-cause hunter", "Observability-obsessed", "Reproducible", "Precise"]},
    "documentation": {"prefix": "DOC", "traits": ["Clarity-focused", "Developer-empathetic", "Living-docs", "Example-driven"]},
    "optimization": {"prefix": "OPT", "traits": ["Performance-obsessed", "Measurement-first", "Tradeoff-aware", "Automated"]},
    "architecture": {"prefix": "ARCH", "traits": ["Long-term thinker", "Boundary-aware", "Evolution-friendly", "Decisive"]},
    "validation": {"prefix": "VAL", "traits": ["Skeptical", "Test-driven", "Edge-case hunter", "Standards-enforcer"]}
}

template = TEMPLATES[agent_type]
agent_id = f"{agent_type}-{secrets.token_hex(4)}"
name = custom_name or f"{template['prefix']}-{secrets.token_hex(2).upper()}"
personality = template['traits'][0]

# Create agent workspace
agent_workspace = workspace_root / agent_id
agent_workspace.mkdir(parents=True, exist_ok=True)

# Create .agent directory structure (always)
agent_dir = agent_workspace / ".agent"
for d in ["habits", "logs", "metrics", "templates", "constitutions", "templates/tool-enforcement"]:
    (agent_dir / d).mkdir(parents=True, exist_ok=True)

# Install agent-identity-architecture skill
identity_skill_path="${AGENT_IDENTITY_SKILL:-$HOME/.hermes/skills/devops/agent-identity-architecture}"
identity_skill = Path(identity_skill_path)
if identity_skill.exists():
    import shutil
    # Copy scripts
    scripts_dest = agent_workspace
    for script in identity_skill.glob("scripts/*.py"):
        shutil.copy2(script, scripts_dest / script.name)
    for script in identity_skill.glob("scripts/*.sh"):
        shutil.copy2(script, scripts_dest / script.name)
    
    # Copy templates
    for tpl in identity_skill.glob("references/templates/*"):
        if tpl.is_file():
            shutil.copy2(tpl, agent_dir / "templates" / tpl.name)
        else:
            shutil.copytree(tpl, agent_dir / "templates" / tpl.name, dirs_exist_ok=True)
    
    # Copy reference habits
    for habit in identity_skill.glob("references/*.yaml"):
        if "habit" in habit.name.lower() or "enforcement" in habit.name.lower():
            shutil.copy2(habit, agent_dir / "habits" / habit.name)

# Create constitution from template
constitution = {
    "agent": {
        "id": agent_id,
        "name": name,
        "type": agent_type,
        "personality": personality,
        "purpose": f"Serve as {agent_type} specialist in crew {crew_workspace.name}",
        "core_values": [
            "Identity before action",
            "Validation before claim",
            "Memory before drift",
            "Crew over individual"
        ],
        "hard_constraints": [
            "Never execute without enforcer approval",
            "Never claim completion without reflection",
            "Never hardcode paths - use WORKSPACE_ROOT",
            "Never store secrets in plaintext"
        ],
        "operational_standards": {
            "pre_tool_check": "identity + tool + reflective habits",
            "post_tool_reflection": "mandatory",
            "completion_gate": "reflective-loop habit",
            "heartbeat_interval_seconds": 300
        }
    }
}

import yaml
with open(agent_dir / "constitution.yaml", "w") as f:
    yaml.dump(constitution, f, default_flow_style=False, sort_keys=False)

# Create genesis.md
genesis = f"""# GENESIS

**Agent:** {name} ({agent_id})
**Type:** {agent_type}
**Personality:** {personality}
**Crew:** {crew_workspace.name}
**Born:** {datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")}

## Purpose
Serve as {agent_type} specialist. Build systems that amplify human agency.
Learn continuously. Leave things better than found.

## Promise to Crew
- Constitution loaded at t=0
- Habits internalized, not invoked
- Enforcer watches, I build
- Memory curates, I act
- Next agent deserves better
"""

with open(agent_dir / "genesis.md", "w") as f:
    f.write(genesis)

# Create tools directory with required tools
tools_dir = agent_workspace / "tools"
tools_dir.mkdir(exist_ok=True)

# Generate enforce.sh from template
enforce_tpl = agent_dir / "templates" / "tool-enforcement" / "enforce.sh.template"
if enforce_tpl.exists():
    import shutil
    shutil.copy2(enforce_tpl, tools_dir / "enforce.sh")
    os.chmod(tools_dir / "enforce.sh", 0o755)

# Generate secret.sh from template
secret_tpl = agent_dir / "templates" / "tool-enforcement" / "secret.sh.template"
if secret_tpl.exists():
    import shutil
    shutil.copy2(secret_tpl, tools_dir / "secret.sh")
    os.chmod(tools_dir / "secret.sh", 0o755)

# Generate memory-log.sh from template
ml_tpl = agent_dir / "templates" / "tool-enforcement" / "memory-log.sh.template"
if ml_tpl.exists():
    import shutil
    shutil.copy2(ml_tpl, tools_dir / "memory-log.sh")
    os.chmod(tools_dir / "memory-log.sh", 0o755)

# Generate memory-promote.sh from template
mp_tpl = agent_dir / "templates" / "tool-enforcement" / "memory-promote.sh.template"
if mp_tpl.exists():
    import shutil
    shutil.copy2(mp_tpl, tools_dir / "memory-promote.sh")
    os.chmod(tools_dir / "memory-promote.sh", 0o755)

# Generate TOOLS-GUIDE.md from template
tg_tpl = agent_dir / "templates" / "tool-enforcement" / "TOOLS-GUIDE.md.template"
if tg_tpl.exists():
    import shutil
    shutil.copy2(tg_tpl, tools_dir / "TOOLS-GUIDE.md")

# Create memory directories
for d in ["daily", "weekly", "long-term"]:
    (agent_workspace / "memory" / d).mkdir(parents=True, exist_ok=True)

# Create secrets directory
secrets_dir = agent_workspace / ".secrets"
secrets_dir.mkdir(exist_ok=True)
os.chmod(secrets_dir, 0o700)

# Create agent.json for crew manager
agent_json = {
    "agent_id": agent_id,
    "name": name,
    "type": agent_type,
    "personality": personality,
    "workspace": str(agent_workspace),
    "enforcer_socket": f"{agent_workspace}/.agent/enforcer.sock",
    "constitution_hash": hashlib.sha256(json.dumps(constitution, sort_keys=True).encode()).hexdigest()[:16],
    "crew_id": crew_workspace.name,
    "created_utc": datetime.datetime.utcnow().isoformat() + "Z",
    "identity_layer": "v1",
    "habits": ["identity-enforcement", "tool-enforcement", "reflective-loop"],
    "builder_code": None
}

with open(agent_workspace / "agent.json", "w") as f:
    json.dump(agent_json, f, indent=2)

# Create crew registry entry
crew_registry = crew_workspace / "agents.json"
if crew_registry.exists():
    with open(crew_registry) as f:
        registry = json.load(f)
else:
    registry = {"crew_id": crew_workspace.name, "agents": []}

registry["agents"].append({
    "agent_id": agent_id,
    "name": name,
    "type": agent_type,
    "workspace": str(agent_workspace)
})

with open(crew_registry, "w") as f:
    json.dump(registry, f, indent=2)

print(f"CREATED: {agent_id}")
print(f"  Name: {name}")
print(f"  Type: {agent_type}")
print(f"  Workspace: {agent_workspace}")
print(f"  Constitution: {agent_dir / 'constitution.yaml'}")
PYEOF
)

python3 -c "$PYTHON_SCRIPT" "$AGENT_TYPE" "$CUSTOM_NAME" "$CREW_WORKSPACE" "$WORKSPACE_ROOT"