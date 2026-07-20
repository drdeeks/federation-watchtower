#!/usr/bin/env bash
# init-prod-crew.sh - Initialize production crew workspace (persistent, agent subdirs)
set -euo pipefail

show_help() {
    cat <<'EOF'
Initialize Production Crew - Persistent workspace with agent subdirectories

Usage: bash init-prod-crew.sh <agent-types...> [--crew-id <id>] [--workspace <path>] [--help]

Arguments:
  agent-types     Agent types to spawn (ui, integration, blockchain, debugger,
                  documentation, optimization, architecture, validation, lead)

Options:
  --crew-id       Crew identifier (default: prod-crew-<timestamp>)
  --workspace     Root workspace path (default: $HOME/crews/<crew-id>)
  --help          Show this help

Environment:
  AGENT_IDENTITY_SKILL   Path to agent-identity-architecture skill
  CREW_SEMANTIC_ENABLED  Enable semantic search (requires TURBOPUFFER_API_KEY, OPENAI_API_KEY)
  VENTOY_MOUNT          Ventoy USB mount point for persistence (optional)

Example:
  bash init-prod-crew.sh lead ui blockchain validation --crew-id prod-trading
  bash init-prod-crew.sh lead ui blockchain --workspace \${VENTOY_MOUNT:-$HOME/crews}/prod-crew
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
CREW_ID="${CREW_ID:-prod-crew-$(date +%Y%m%d-%H%M%S)}"
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/crews/$CREW_ID}"
AGENT_IDENTITY_SKILL="${AGENT_IDENTITY_SKILL:-$HOME/.hermes/skills/devops/agent-identity-architecture}"

CREW_DIR="$WORKSPACE_ROOT"
AGENTS_DIR="$CREW_DIR/agents"
SHARED_DIR="$CREW_DIR/shared"
INDEX_DIR="$CREW_DIR/index"

echo "=== Initializing Production Crew: $CREW_ID ==="
echo "  Workspace: $CREW_DIR"
echo "  Agents: ${AGENT_TYPES[*]}"
echo "  Persistence: Long-term (git/Ventoy)"
echo ""

# Create crew root structure
mkdir -p "$CREW_DIR"
mkdir -p "$AGENTS_DIR"
mkdir -p "$SHARED_DIR"/{knowledge,communications,documents}
mkdir -p "$SHARED_DIR/knowledge"/{architecture,api,ui,infra,process,debugging,research}
mkdir -p "$SHARED_DIR/communications"/{messages,threads,broadcasts}
mkdir -p "$SHARED_DIR/documents"/{decisions,learnings,specs,communications}
mkdir -p "$INDEX_DIR"/{by-category,by-agent,by-tag,semantic}

# Create crew manifest
cat > "$CREW_DIR/crew.json" <<MANIFEST
{
  "crew_id": "$CREW_ID",
  "crew_type": "production",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace": "$CREW_DIR",
  "agents_dir": "$AGENTS_DIR",
  "shared_dir": "$SHARED_DIR",
  "index_dir": "$INDEX_DIR",
  "agent_types": $(printf '%s\n' "${AGENT_TYPES[@]}" | jq -R . | jq -s .),
  "semantic_enabled": ${CREW_SEMANTIC_ENABLED:-false},
  "secrets_mode": "real",
  "persistence": "long-term",
  "ventoy_mount": "${VENTOY_MOUNT:-}"
}
MANIFEST

# Create CHANGELOG
cat > "$CREW_DIR/CHANGELOG.md" <<CHANGELOG
# CHANGELOG

## [$CREW_ID] - $(date -u +%Y-%m-%d)

### Crew Initialized
- Crew ID: $CREW_ID
- Type: Production (persistent agent subdirectories)
- Agents: ${AGENT_TYPES[*]}
- Workspace: $CREW_DIR
- Persistence: Git/Ventoy
- Secrets: Real (enforcer-managed)

---
CHANGELOG

# Create shared knowledge index manifest
cat > "$INDEX_DIR/crew-manifest.json" <<MANIFEST
{
  "crew_id": "$CREW_ID",
  "crew_type": "production",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "index_version": "1.0",
  "categories": [
    "architecture", "api", "ui", "infra", 
    "process", "debugging", "research"
  ],
  "total_documents": 0,
  "last_indexed": null,
  "semantic_vectors": ${CREW_SEMANTIC_ENABLED:-false}
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

# Create enforcer registry
cat > "$CREW_DIR/.enforcer-registry.json" <<REGISTRY
{
  "crew_id": "$CREW_ID",
  "crew_type": "production",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "enforcers": {}
}
REGISTRY

# Create .gitignore for production crew
cat > "$CREW_DIR/.gitignore" <<GITIGNORE
# Crew persistence
.env*
*.key
*.pem
.secrets/
*.log
*.pid

# Ventoy persistence (set via VENTOY_MOUNT env var)
${VENTOY_MOUNT:-/mnt/ventoy}/

# Agent enforcer sockets
**/.agent/enforcer.sock

# Temporary files
*.tmp
*.swp
*~

# Semantic vectors (regeneratable)
**/semantic/vectors.faiss
**/semantic/metadata.json
GITIGNORE

# Initialize git repo
cd "$CREW_DIR" && git init -q && git add .gitignore crew.json CHANGELOG.md .enforcer-registry.json && git commit -q -m "chore: initialize production crew $CREW_ID" 2>/dev/null || true

echo "  ✅ Production crew structure created"
echo "  ✅ Git repository initialized"
echo "  ✅ Enforcer registry created"
echo "  ✅ Shared workspace configured"

# Create each agent with identity layer in their own subdirectory
for AGENT_TYPE in "${AGENT_TYPES[@]}"; do
    echo ""
    echo "  → Spawning $AGENT_TYPE agent in production mode..."
    
    CREW_WORKSPACE="$CREW_DIR" \
    CREW_ID="$CREW_ID" \
    WORKSPACE_ROOT="$AGENTS_DIR" \
    AGENT_IDENTITY_SKILL="$AGENT_IDENTITY_SKILL" \
    bash "$HOME/.hermes/skills/devops/autonomous-crew/scripts/create-crew-agent.sh" \
    "$AGENT_TYPE" 2>&1 | sed 's/^/     /'
    
    # Update enforcer registry with agent info
    AGENT_ID=$(ls -t "$AGENTS_DIR" | head -1)
    if [[ -f "$AGENTS_DIR/$AGENT_ID/agent.json" ]]; then
        python3 -c "
import json, sys
with open('$CREW_DIR/.enforcer-registry.json') as f:
    reg = json.load(f)
with open('$AGENTS_DIR/$AGENT_ID/agent.json') as f:
    agent = json.load(f)
reg['enforcers'][agent['agent_id']] = {
    'socket': agent['enforcer_socket'],
    'pid': None,
    'status': 'registered',
    'workspace': agent['workspace'],
    'identity_hash': agent['constitution_hash'],
    'started_utc': '$(date -u +%Y-%m-%dT%H:%M:%SZ)'
}
with open('$CREW_DIR/.enforcer-registry.json', 'w') as f:
    json.dump(reg, f, indent=2)
"
    fi
done

# Create production crew status script
cat > "$CREW_DIR/crew-status.sh" <<'STATUS'
#!/usr/bin/env bash
CREW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "=== Production Crew Status: $(basename "$CREW_DIR") ==="
echo ""
echo "--- Agents ---"
for agent_dir in "$CREW_DIR"/agents/*/; do
    [[ -d "$agent_dir" ]] || continue
    AGENT_ID=$(basename "$agent_dir")
    if [[ -f "$agent_dir/agent.json" ]]; then
        python3 -c "
import json
with open('$agent_dir/agent.json') as f:
    a = json.load(f)
print(f\"  {a['agent_id']} ({a['type']}): {a['name']} - {a.get('status', 'unknown')}\")
"
    fi
done
echo ""
echo "--- Enforcer Registry ---"
python3 -c "
import json
with open('$CREW_DIR/.enforcer-registry.json') as f:
    r = json.load(f)
for aid, info in r.get('enforcers', {}).items():
    print(f\"  {aid}: {info.get('status', 'unknown')} - {info.get('workspace', 'N/A')}\")
"
echo ""
echo "--- Knowledge Index ---"
if [[ -f "$CREW_DIR/index/crew-manifest.json" ]]; then
    python3 -c "
import json
with open('$CREW_DIR/index/crew-manifest.json') as f:
    m = json.load(f)
print(f\"  Documents: {m.get('total_documents', 0)}\")
print(f\"  Last indexed: {m.get('last_indexed', 'never')}\")
print(f\"  Semantic: {m.get('semantic_vectors', False)}\")
"
fi
STATUS
chmod +x "$CREW_DIR/crew-status.sh"

echo ""
echo "=== Production Crew $CREW_ID Ready ==="
echo "  Crew workspace: $CREW_DIR"
echo "  Agent workspaces: $AGENTS_DIR/<agent-id>/"
echo "  Shared knowledge: $SHARED_DIR/knowledge"
echo "  Crew index: $INDEX_DIR"
echo "  Enforcer registry: $CREW_DIR/.enforcer-registry.json"
echo "  Git repo: $CREW_DIR/.git"
echo ""
echo "Commands:"
echo "  Status: bash $CREW_DIR/crew-status.sh"
echo "  Index: bash scripts/crew-indexer.sh index"
echo "  Search: bash scripts/crew-indexer.sh search \"query\""
echo "  Communicate: bash scripts/crew-comm.sh send --from <id> --to <id> --subject ... --body ..."
echo "  Create doc: bash scripts/crew-doc.sh decision \"Title\" --category architecture"