#!/usr/bin/env bash
# init-knowledge-workspace.sh - Initialize standalone knowledge workspace for single agent
set -euo pipefail

show_help() {
    cat <<'EOF'
Initialize Standalone Knowledge Workspace

Usage: bash init-knowledge-workspace.sh <agent-id> [options]

Arguments:
  <agent-id>              Your agent identifier (e.g., ui-a1b2, my-agent)

Options:
  --workspace <path>      Workspace root (default: current directory)
  --mode <mode>           Workspace mode: development|production (default: development)
  --help                  Show this help

Examples:
  bash init-knowledge-workspace.sh my-agent
  bash init-knowledge-workspace.sh ui-a1b2 --workspace /path/to/workspace
  bash init-knowledge-workspace.sh lead --mode production

What This Creates:
  <workspace>/
  ├── knowledge/              # Your knowledge base
  │   ├── architecture/
  │   ├── api/
  │   ├── ui/
  │   ├── infra/
  │   ├── process/
  │   ├── debugging/
  │   └── research/
  ├── communications/         # Your messages (if needed)
  │   ├── messages/
  │   └── threads/
  ├── documents/              # Formatted documents
  │   ├── decisions/
  │   ├── specs/
  │   └── learnings/
  ├── index/                  # Search index
  │   ├── by-category/
  │   ├── by-tag/
  │   └── agent-manifest.json
  └── .agent.json             # Agent configuration
EOF
    exit 0
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
fi

AGENT_ID="${1:-}"
if [[ -z "$AGENT_ID" ]]; then
    echo "ERROR: agent-id required"
    show_help
fi

# Parse options
WORKSPACE="$(pwd)"
MODE="development"

while [[ $# -gt 0 ]]; do
    case $1 in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        *) shift ;;
    esac
done

# Validate mode
if [[ "$MODE" != "development" && "$MODE" != "production" ]]; then
    echo "ERROR: Invalid mode. Use: development or production"
    exit 1
fi

echo "=== Initializing Standalone Knowledge Workspace ==="
echo "  Agent ID: $AGENT_ID"
echo "  Workspace: $WORKSPACE"
echo "  Mode: $MODE"
echo ""

# Create directory structure
echo "Creating directory structure..."

# Knowledge directories (by category)
mkdir -p "$WORKSPACE/knowledge"/{architecture,api,ui,infra,process,debugging,research}

# Communications (for self-documentation)
mkdir -p "$WORKSPACE/communications"/{messages,threads}

# Documents
mkdir -p "$WORKSPACE/documents"/{decisions,specs,learnings}

# Index
mkdir -p "$WORKSPACE/index"/{by-category,by-tag}

# Create agent configuration
cat > "$WORKSPACE/.agent.json" <<AGENT
{
  "agent_id": "$AGENT_ID",
  "mode": "$MODE",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace": "$WORKSPACE",
  "knowledge_enabled": true,
  "communication_enabled": true,
  "semantic_enabled": false
}
AGENT

# Create crew.json for compatibility (single-agent crew)
cat > "$WORKSPACE/crew.json" <<CREW
{
  "crew_id": "standalone-$AGENT_ID",
  "crew_type": "$MODE",
  "created_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "workspace": "$WORKSPACE",
  "agents": [
    {
      "agent_id": "$AGENT_ID",
      "workspace": "$WORKSPACE",
      "type": "standalone"
    }
  ],
  "agent_types": ["standalone"],
  "semantic_enabled": false,
  "secrets_mode": "$([ "$MODE" = "production" ] && echo "real" || echo "placeholders")",
  "persistence": "$([ "$MODE" = "production" ] && echo "long-term" || echo "ephemeral")"
}
CREW

echo ""
echo "✅ Standalone knowledge workspace initialized!"
echo ""
echo "Directory structure:"
echo "  knowledge/          - Your knowledge base (7 categories)"
echo "  communications/     - Messages and threads"
echo "  documents/          - Formatted documents"
echo "  index/              - Search index"
echo "  .agent.json         - Agent configuration"
echo "  crew.json           - Single-agent crew config (for compatibility)"
echo ""
echo "Next steps:"
echo "  1. Create a document:  bash scripts/knowledge-doc.sh decision 'My Decision' --category architecture"
echo "  2. Index knowledge:    bash scripts/knowledge-indexer.sh index"
echo "  3. Search knowledge:   bash scripts/knowledge-indexer.sh search 'query'"
echo "  4. View help:          bash scripts/knowledge-indexer.sh --help"
