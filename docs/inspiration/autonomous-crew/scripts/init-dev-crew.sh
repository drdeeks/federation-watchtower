#!/usr/bin/env bash
# init-dev-crew.sh - Initialize development crew workspace (ephemeral, shared)
set -euo pipefail

show_help() {
    cat <<'EOF'
Initialize Development Crew - Ephemeral shared workspace for agent collaboration

Usage: bash init-dev-crew.sh <agent-types...> [--crew-id <id>] [--workspace <path>] [--help]

Arguments:
  agent-types     Agent types to spawn (ui, integration, blockchain, debugger,
                  documentation, optimization, architecture, validation, lead)

Options:
  --crew-id       Crew identifier (default: dev-crew-<timestamp>)
  --workspace     Root workspace path (default: $HOME/crews/<crew-id>)
  --help          Show this help

Environment:
  AGENT_IDENTITY_SKILL   Path to agent-identity-architecture skill
  CREW_SEMANTIC_ENABLED  Enable semantic search (requires TURBOPUFFER_API_KEY, OPENAI_API_KEY)

Example:
  bash init-dev-crew.sh ui integration blockchain validation --crew-id hackathon-2026
  bash init-dev-crew.sh lead ui blockchain --workspace /tmp/my-crew
EOF
    exit 0
}

# Parse args
AGENT_TYPES=()
CREW_ID=""
WORKSPACE_ROOT=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --crew-id) CREW_ID="$2"; shift 2 ;;
        --workspace) WORKSPACE_ROOT="$2"; shift 2 ;;
        *) AGENT_TYPES+=("$1"); shift ;;
    esac
done

if [[ ${#AGENT_TYPES[@]} -eq 0 ]]; then
    echo "ERROR: At least one agent-type required"
    show_help
fi

# Defaults
CREW_ID="${CREW_ID:-dev-crew-$(date +%Y%m%d-%H%M%S)}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/crews/$CREW_ID}"
AGENT_IDENTITY_SKILL="${AGENT_IDENTITY_SKILL:-$HOME/.hermes/skills/devops/agent-identity-architecture}"

CREW_DIR="$WORKSPACE_ROOT"
SHARED_DIR="$CREW_DIR/shared"
AGENTS_DIR="$CREW_DIR/agents"
INDEX_DIR="$CREW_DIR/index"

echo "=== Initializing Development Crew: $CREW_ID ==="
echo "  Workspace: $CREW_DIR"
echo "  Agents: ${AGENT_TYPES[*]}"
echo ""

# Create shared workspace structure (all agents share this)
mkdir -p "$SHARED_DIR"/{knowledge,communications,documents,index}
mkdir -p "$SHARED_DIR/knowledge"/{architecture,api,ui,infra,process,debugging,research}
mkdir -p "$SHARED_DIR/communications"/{messages,threads,broadcasts}
mkdir -p "$SHARED_DIR/documents"/{decisions,learnings,specs,communications}
mkdir -p "$SHARED_DIR/index"/{by-category,by-agent,by-tag,semantic}

# Create agents directory
mkdir -p "$AGENTS_DIR"

# Create crew manifest
cat > "$CREW_DIR/crew.json" <<MANIFEST
{
  "crew_id": "$CREW_ID",
  "crew_type": "development",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace": "$CREW_DIR",
  "shared_dir": "$SHARED_DIR",
  "agents_dir": "$AGENTS_DIR",
  "agent_types": $(printf '%s\n' "${AGENT_TYPES[@]}" | jq -R . | jq -s .),
  "semantic_enabled": ${CREW_SEMANTIC_ENABLED:-false},
  "secrets_mode": "placeholders",
  "persistence": "ephemeral"
}
MANIFEST

# Create CHANGELOG
cat > "$CREW_DIR/CHANGELOG.md" <<CHANGELOG
# CHANGELOG

## [$CREW_ID] - $(date -u +%Y-%m-%d)

### Crew Initialized
- Crew ID: $CREW_ID
- Type: Development (ephemeral shared workspace)
- Agents: ${AGENT_TYPES[*]}
- Workspace: $CREW_DIR
- Secrets: Placeholders only

---
CHANGELOG

# Create shared knowledge index manifest
cat > "$SHARED_DIR/index/crew-manifest.json" <<MANIFEST
{
  "crew_id": "$CREW_ID",
  "crew_type": "development",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "index_version": "1.0",
  "categories": [
    "architecture", "api", "ui", "infra", 
    "process", "debugging", "research"
  ],
  "total_documents": 0,
  "last_indexed": null
}
MANIFEST

# Create communication protocol config
cat > "$SHARED_DIR/communications/protocol.json" <<PROTOCOL
{
  "crew_id": "$CREW_ID",
  "protocol_version": "1.0",
  "message_types": ["sync", "question", "proposal", "decision", "broadcast", "alert"],
  "priorities": ["low", "normal", "high", "urgent"],
  "storage": {
    "messages_dir": "messages",
    "threads_dir": "threads", 
    "broadcasts_dir": "broadcasts"
  },
  "threading": {
    "enabled": true,
    "max_depth": 10
  }
}
PROTOCOL

echo "  ✅ Shared workspace structure created"
echo "  ✅ Crew manifest written"
echo "  ✅ Communication protocol configured"

# Now create each agent with identity layer
AGENT_INFO=()
for AGENT_TYPE in "${AGENT_TYPES[@]}"; do
    echo ""
    echo "  → Spawning $AGENT_TYPE agent..."
    
    # Use the create-crew-agent.sh from autonomous-crew
    CREW_WORKSPACE="$CREW_DIR" \
    CREW_ID="$CREW_ID" \
    WORKSPACE_ROOT="$HOME/agents" \
    AGENT_IDENTITY_SKILL="$AGENT_IDENTITY_SKILL" \
    bash "$HOME/.hermes/skills/devops/autonomous-crew/scripts/create-crew-agent.sh" \
    "$AGENT_TYPE" 2>&1 | sed 's/^/     /'
    
    # Wait a moment and check for newly created agent
    sleep 0.5
done

# After all agents created, scan global workspace and update crew.json with agent info
echo "  → Recording agent workspaces..."
AGENTS_JSON=()
for agent_dir in "$HOME/agents"/*/; do
    [[ -d "$agent_dir" ]] || continue
    agent_id=$(basename "$agent_dir")
    # Check if this agent belongs to our crew (by checking agent.json)
    agent_json="$agent_dir/agent.json"
    if [[ -f "$agent_json" ]]; then
        crew_id=$(jq -r '.crew_id // empty' "$agent_json" 2>/dev/null || echo "")
        if [[ "$crew_id" == "$CREW_ID" ]]; then
            AGENTS_JSON+=("{\"agent_id\":\"$agent_id\",\"workspace\":\"$agent_dir\",\"crew_id\":\"$CREW_ID\"}")
        fi
    fi
done

# Update crew.json with agent info
if [[ ${#AGENTS_JSON[@]} -gt 0 ]]; then
    AGENTS_JSON_STR=$(IFS=,; echo "[${AGENTS_JSON[*]}]")
    jq --argjson agents "$AGENTS_JSON_STR" '.agents = $agents' "$CREW_DIR/crew.json" > "$CREW_DIR/crew.json.tmp" && mv "$CREW_DIR/crew.json.tmp" "$CREW_DIR/crew.json"
fi

echo ""
echo "=== Development Crew $CREW_ID Ready ==="
echo "  Crew workspace: $CREW_DIR"
echo "  Shared knowledge: $SHARED_DIR/knowledge"
echo "  Communications: $SHARED_DIR/communications"
echo "  Documents: $SHARED_DIR/documents"
echo ""
echo "Agents can now:"
echo "  - Communicate: bash scripts/crew-comm.sh send --from <id> --to <id> --subject ... --body ..."
echo "  - Create docs: bash scripts/crew-doc.sh decision \"Title\" --category architecture"
echo "  - Search knowledge: bash scripts/crew-indexer.sh search \"query\""
echo "  - Sync knowledge: bash scripts/crew-sync.sh"