#!/usr/bin/env bash
# knowledge-sync.sh - Sync knowledge across agents and rebuild indexes (standalone or crew)
set -euo pipefail

show_help() {
    cat <<'EOF'
Knowledge Sync - Synchronize knowledge and update indexes

Usage: bash knowledge-sync.sh [options]

Options:
  --workspace <path>    Workspace (auto-detect)
  --full                Full sync (communications + knowledge)
  --comms-only          Sync communications only
  --knowledge-only      Sync knowledge only
  --reindex             Rebuild search index after sync
  --semantic            Rebuild semantic vectors (requires SEMANTIC_ENABLED=true)
  --help                Show this help

Standalone Usage:
  bash knowledge-sync.sh --full --reindex

Crew Usage:
  bash knowledge-sync.sh --full --reindex
  bash knowledge-sync.sh --comms-only
  SEMANTIC_ENABLED=true bash knowledge-sync.sh --full --reindex --semantic
EOF
    exit 0
}

# Handle --help BEFORE any workspace detection
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
fi

# Auto-detect workspace (standalone or crew)
detect_workspace() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/.agent.json" || -f "$dir/crew.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

WORKSPACE="${WORKSPACE_ROOT:-${CREW_WORKSPACE:-}}"
if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE="$(detect_workspace)" || {
        echo "ERROR: Not in a knowledge workspace"
        echo "Run: bash init-knowledge-workspace.sh <agent-id>"
        exit 1
    }
fi

# Detect mode
if [[ -f "$WORKSPACE/.agent.json" && ! -f "$WORKSPACE/crew.json" ]]; then
    MODE="standalone"
    CREW_ID="standalone-$(jq -r .agent_id "$WORKSPACE/.agent.json" 2>/dev/null || echo "unknown")"
    CREW_MODE="$(jq -r .mode "$WORKSPACE/.agent.json" 2>/dev/null || echo "development")"
elif [[ -f "$WORKSPACE/crew.json" ]]; then
    MODE="crew"
    CREW_ID="$(jq -r .crew_id "$WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
    CREW_MODE="$(jq -r .crew_type "$WORKSPACE/crew.json" 2>/dev/null || echo "development")"
else
    echo "ERROR: Invalid workspace configuration"
    exit 1
fi

# Set up directory paths based on mode
if [[ "$MODE" == "standalone" ]]; then
    KNOWLEDGE_DIR="$WORKSPACE/knowledge"
    COMM_DIR="$WORKSPACE/communications"
else
    KNOWLEDGE_DIR="$WORKSPACE/shared/knowledge"
    COMM_DIR="$WORKSPACE/shared/communications"
fi

FULL_SYNC=false
COMMS_ONLY=false
KNOWLEDGE_ONLY=false
REINDEX=false
SEMANTIC=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --full) FULL_SYNC=true; shift ;;
        --comms-only) COMMS_ONLY=true; shift ;;
        --knowledge-only) KNOWLEDGE_ONLY=true; shift ;;
        --reindex) REINDEX=true; shift ;;
        --semantic) SEMANTIC=true; shift ;;
        *) echo "ERROR: Unknown option: $1"; show_help ;;
    esac
done

# Default to full sync if no specific mode
if [[ "$COMMS_ONLY" == "false" && "$KNOWLEDGE_ONLY" == "false" && "$FULL_SYNC" == "false" ]]; then
    FULL_SYNC=true
fi

echo "=== Knowledge Sync: $CREW_ID ==="
echo "  Mode: $MODE"
if [[ "$FULL_SYNC" == "true" ]]; then
    echo "  Sync: Full (comms + knowledge + reindex)"
elif [[ "$COMMS_ONLY" == "true" ]]; then
    echo "  Sync: Communications only"
elif [[ "$KNOWLEDGE_ONLY" == "true" ]]; then
    echo "  Sync: Knowledge only"
fi
[[ "$REINDEX" == "true" ]] && echo "  Reindex: Yes"
[[ "$SEMANTIC" == "true" ]] && echo "  Semantic: Yes"
echo ""

# Sync communications
if [[ "$FULL_SYNC" == "true" || "$COMMS_ONLY" == "true" ]]; then
    echo "  → Syncing communications..."
    bash "$(dirname "$0")/knowledge-comm.sh" sync
    echo "    ✅ Communications synced to documents"
fi

# Rebuild index
if [[ "$REINDEX" == "true" ]]; then
    echo "  → Rebuilding search index..."
    REINDEX_ARGS="rebuild"
    [[ "$SEMANTIC" == "true" ]] && REINDEX_ARGS="rebuild --semantic"
    WORKSPACE_ROOT="$WORKSPACE" bash "$(dirname "$0")/knowledge-indexer.sh" $REINDEX_ARGS
    echo "    ✅ Search index rebuilt"
fi

echo ""
echo "=== Sync Complete ==="
echo "  Workspace: $WORKSPACE"
echo "  Last synced: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
