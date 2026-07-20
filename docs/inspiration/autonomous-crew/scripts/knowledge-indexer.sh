#!/usr/bin/env bash
# knowledge-indexer.sh - Knowledge indexer (standalone or crew-integrated)
set -euo pipefail

show_help() {
    cat <<'EOF'
Knowledge Indexer - Index and search knowledge base

Usage: bash knowledge-indexer.sh <command> [options]

Commands:
  index                 Index all knowledge (default)
  index-agent <id>      Index specific agent's knowledge directory
  search <query>        Search knowledge (keyword + category filter)
  semantic-search <query>  Semantic vector search (requires TURBOPUFFER_API_KEY)
  hybrid-search <query>    Combined keyword + semantic search
  rebuild               Rebuild entire index from scratch
  rebuild --semantic    Rebuild with semantic vectors
  status                Show index status
  list [category]       List indexed documents

Options:
  --workspace <path>    Workspace root (default: auto-detect)
  --category <cat>      Filter by category (architecture|api|ui|infra|process|debugging|research)
  --agent <id>          Filter by agent ID
  --tags <tags>         Filter by tags (comma-separated)
  --limit <n>           Limit results (default: 10)
  --help                Show this help

Environment:
  SEMANTIC_ENABLED      Enable semantic search (default: false)
  TURBOPUFFER_API_KEY   Turbopuffer API key for semantic search
  OPENAI_API_KEY        OpenAI API key for embeddings
  WORKSPACE_ROOT        Workspace root

Standalone Usage:
  bash knowledge-indexer.sh index
  bash knowledge-indexer.sh search "oauth authentication" --category architecture

Crew Usage:
  bash knowledge-indexer.sh index
  bash knowledge-indexer.sh index-agent ui-a1b2
  SEMANTIC_ENABLED=true bash knowledge-indexer.sh rebuild --semantic
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
        # Check for standalone agent config
        if [[ -f "$dir/.agent.json" ]]; then
            echo "$dir"
            return 0
        fi
        # Check for crew config
        if [[ -f "$dir/crew.json" ]]; then
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
        echo "ERROR: Not in a knowledge workspace (no .agent.json or crew.json found)"
        echo "Run: bash init-knowledge-workspace.sh <agent-id>"
        exit 1
    }
fi

# Detect if standalone or crew mode
if [[ -f "$WORKSPACE/.agent.json" && ! -f "$WORKSPACE/crew.json" ]]; then
    MODE="standalone"
    AGENT_ID="$(jq -r .agent_id "$WORKSPACE/.agent.json" 2>/dev/null || echo "unknown")"
    CREW_ID="standalone-$AGENT_ID"
    CREW_TYPE="$(jq -r .mode "$WORKSPACE/.agent.json" 2>/dev/null || echo "development")"
elif [[ -f "$WORKSPACE/crew.json" ]]; then
    MODE="crew"
    CREW_ID="$(jq -r .crew_id "$WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
    CREW_TYPE="$(jq -r .crew_type "$WORKSPACE/crew.json" 2>/dev/null || echo "development")"
    AGENT_ID=""
else
    echo "ERROR: Invalid workspace configuration"
    exit 1
fi

# Set up directory paths based on mode
if [[ "$MODE" == "standalone" ]]; then
    KNOWLEDGE_DIR="$WORKSPACE/knowledge"
    INDEX_DIR="$WORKSPACE/index"
else
    # Crew mode - check for shared or agent-specific directories
    if [[ -d "$WORKSPACE/shared" ]]; then
        KNOWLEDGE_DIR="$WORKSPACE/shared/knowledge"
    else
        KNOWLEDGE_DIR="$WORKSPACE/knowledge"
    fi
    INDEX_DIR="$WORKSPACE/index"
fi

SEMANTIC_ENABLED="${SEMANTIC_ENABLED:-${CREW_SEMANTIC_ENABLED:-false}}"
TURBOPUFFER_API_KEY="${TURBOPUFFER_API_KEY:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

COMMAND="${1:-index}"
shift || true

# Parse options
FILTER_CATEGORY=""
FILTER_AGENT=""
FILTER_TAGS=""
LIMIT=10

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --category) FILTER_CATEGORY="$2"; shift 2 ;;
        --agent) FILTER_AGENT="$2"; shift 2 ;;
        --tags) FILTER_TAGS="$2"; shift 2 ;;
        --limit) LIMIT="$2"; shift 2 ;;
        *) break ;;
    esac
done

# Ensure index directories exist
mkdir -p "$INDEX_DIR"/{by-category,by-tag,semantic}

case "$COMMAND" in
    index)
        echo "=== Indexing Knowledge: $CREW_ID ==="
        echo "  Mode: $MODE"
        
        # Index knowledge directory
        echo "  Indexing knowledge..."
        index_directory "$KNOWLEDGE_DIR" "knowledge" "$CREW_TYPE"
        
        # Update manifest
        update_manifest
        
        echo "  ✅ Indexing complete"
        ;;
        
    index-agent)
        AGENT_ID="${1:-}"
        if [[ -z "$AGENT_ID" ]]; then
            echo "ERROR: agent-id required for index-agent"
            exit 1
        fi
        
        # In standalone mode, index the main knowledge dir
        if [[ "$MODE" == "standalone" ]]; then
            echo "=== Indexing Agent: $AGENT_ID ==="
            index_directory "$KNOWLEDGE_DIR" "$AGENT_ID" "$CREW_TYPE"
        else
            # Crew mode - index specific agent
            agent_dir="$WORKSPACE/agents/$AGENT_ID"
            if [[ ! -d "$agent_dir" ]]; then
                echo "ERROR: Agent not found: $AGENT_ID"
                exit 1
            fi
            
            knowledge_dir="$agent_dir/knowledge"
            if [[ ! -d "$knowledge_dir" ]]; then
                echo "ERROR: No knowledge directory for agent: $AGENT_ID"
                exit 1
            fi
            
            echo "=== Indexing Agent: $AGENT_ID ==="
            index_directory "$knowledge_dir" "$AGENT_ID" "$CREW_TYPE"
        fi
        
        update_manifest
        echo "  ✅ Agent index complete"
        ;;
        
    search)
        QUERY="${1:-}"
        if [[ -z "$QUERY" ]]; then
            echo "ERROR: search query required"
            exit 1
        fi
        
        echo "=== Searching Knowledge: $CREW_ID ==="
        echo "  Query: $QUERY"
        [[ -n "$FILTER_CATEGORY" ]] && echo "  Category: $FILTER_CATEGORY"
        [[ -n "$FILTER_AGENT" ]] && echo "  Agent: $FILTER_AGENT"
        echo ""
        
        search_keyword "$QUERY"
        ;;
        
    semantic-search)
        if [[ "$SEMANTIC_ENABLED" != "true" ]]; then
            echo "ERROR: Semantic search not enabled. Set SEMANTIC_ENABLED=true"
            exit 1
        fi
        
        QUERY="${1:-}"
        if [[ -z "$QUERY" ]]; then
            echo "ERROR: search query required"
            exit 1
        fi
        
        echo "=== Semantic Search: $CREW_ID ==="
        echo "  Query: $QUERY"
        semantic_search "$QUERY"
        ;;
        
    hybrid-search)
        QUERY="${1:-}"
        if [[ -z "$QUERY" ]]; then
            echo "ERROR: search query required"
            exit 1
        fi
        
        echo "=== Hybrid Search: $CREW_ID ==="
        echo "  Query: $QUERY"
        search_keyword "$QUERY"
        if [[ "$SEMANTIC_ENABLED" == "true" ]]; then
            echo ""
            echo "--- Semantic Results ---"
            semantic_search "$QUERY"
        fi
        ;;
        
    rebuild)
        REBUILD_SEMANTIC=false
        if [[ "${1:-}" == "--semantic" ]]; then
            REBUILD_SEMANTIC=true
        fi
        
        echo "=== Rebuilding Index: $CREW_ID ==="
        rm -rf "$INDEX_DIR"/{by-category,by-tag,semantic}
        mkdir -p "$INDEX_DIR"/{by-category,by-tag,semantic}
        
        bash "$0" index
        
        if [[ "$REBUILD_SEMANTIC" == "true" ]]; then
            if [[ "$SEMANTIC_ENABLED" != "true" ]]; then
                echo "ERROR: --semantic requires SEMANTIC_ENABLED=true"
                exit 1
            fi
            echo "  Building semantic vectors..."
            build_semantic_vectors
        fi
        
        echo "  ✅ Rebuild complete"
        ;;
        
    status)
        echo "=== Index Status: $CREW_ID ==="
        if [[ -f "$INDEX_DIR/crew-manifest.json" ]]; then
            cat "$INDEX_DIR/crew-manifest.json" | jq .
        else
            echo "  No index manifest found"
        fi
        ;;
        
    list)
        CAT="${1:-}"
        list_documents "$CAT"
        ;;
        
    *)
        echo "ERROR: Unknown command: $COMMAND"
        show_help
        ;;
esac

# ============================================================================
# Internal Functions
# ============================================================================

index_directory() {
    local dir="$1"
    local source_id="$2"
    local crew_type="$3"
    
    if [[ ! -d "$dir" ]]; then
        return 0
    fi
    
    local doc_count=0
    
    # Find all markdown files
    while IFS= read -r -d '' file; do
        # Extract metadata from frontmatter
        local agent_id=$(extract_frontmatter "$file" "agent_id")
        local doc_type=$(extract_frontmatter "$file" "doc_type")
        local category=$(extract_frontmatter "$file" "category")
        local tags=$(extract_frontmatter "$file" "tags")
        local timestamp=$(extract_frontmatter "$file" "timestamp")
        local title=$(extract_title "$file")
        
        # Apply filters
        [[ -n "$FILTER_CATEGORY" && "$category" != "$FILTER_CATEGORY" ]] && continue
        [[ -n "$FILTER_AGENT" && "$agent_id" != "$FILTER_AGENT" ]] && continue
        [[ -n "$FILTER_TAGS" && ! $(echo "$tags" | grep -qE "$(echo "$FILTER_TAGS" | sed 's/,/|/g')") ]] && continue
        
        # Create document entry
        local doc_id="${source_id}-$(basename "$file" .md)"
        local entry=$(jq -n \
            --arg id "$doc_id" \
            --arg source "$source_id" \
            --arg agent "$agent_id" \
            --arg type "$doc_type" \
            --arg cat "$category" \
            --arg tags "$tags" \
            --arg ts "$timestamp" \
            --arg title "$title" \
            --arg path "$file" \
            '{id: $id, source: $source, agent_id: $agent, doc_type: $type, category: $cat, tags: $tags, timestamp: $ts, title: $title, path: $path}')
        
        # Index by category
        if [[ -n "$category" ]]; then
            echo "$entry" | jq -s '.[0]' >> "$INDEX_DIR/by-category/$category.jsonl"
        fi
        
        # Index by tags
        IFS=',' read -ra TAG_ARRAY <<< "$tags"
        for tag in "${TAG_ARRAY[@]}"; do
            tag=$(echo "$tag" | xargs)  # trim
            [[ -n "$tag" ]] && echo "$entry" | jq -s '.[0]' >> "$INDEX_DIR/by-tag/$tag.jsonl"
        done
        
        ((doc_count++))
    done < <(find "$dir" -name "*.md" -print0 2>/dev/null)
    
    echo "    Indexed $doc_count documents from $source_id"
}

extract_frontmatter() {
    local file="$1"
    local key="$2"
    
    if [[ ! -f "$file" ]]; then
        echo ""
        return
    fi
    
    # Extract YAML frontmatter value
    awk -v k="$key" '
        /^---$/ { in_fm = !in_fm; next }
        in_fm && $0 ~ "^" k ":" { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/^"|"$/, ""); print; exit }
    ' "$file"
}

extract_title() {
    local file="$1"
    # First h1 or filename
    awk '/^# / { sub(/^# /, ""); print; exit } END { if (!NR) print FILENAME }' "$file"
}

search_keyword() {
    local query="$1"
    local results=()
    
    # Search in all category indexes
    for cat_file in "$INDEX_DIR/by-category"/*.jsonl; do
        [[ -f "$cat_file" ]] || continue
        
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local title=$(echo "$line" | jq -r .title)
            local content=$(cat "$(echo "$line" | jq -r .path)" 2>/dev/null | head -200)
            
            if echo -e "$title\n$content" | grep -qi "$query"; then
                results+=("$line")
            fi
        done < "$cat_file"
    done
    
    # Apply filters
    local filtered=()
    for entry in "${results[@]}"; do
        local agent=$(echo "$entry" | jq -r .agent_id)
        local category=$(echo "$entry" | jq -r .category)
        local tags=$(echo "$entry" | jq -r .tags)
        
        [[ -n "$FILTER_AGENT" && "$agent" != "$FILTER_AGENT" ]] && continue
        [[ -n "$FILTER_CATEGORY" && "$category" != "$FILTER_CATEGORY" ]] && continue
        [[ -n "$FILTER_TAGS" && ! $(echo "$tags" | grep -qE "$(echo "$FILTER_TAGS" | sed 's/,/|/g')") ]] && continue
        
        filtered+=("$entry")
    done
    
    # Sort by timestamp (newest first) and limit
    printf '%s\n' "${filtered[@]}" | \
        jq -s 'sort_by(.timestamp) | reverse | .[:'"$LIMIT"']' | \
        jq -r '.[] | "\(.timestamp) | \(.agent_id) | \(.category) | \(.title) | \(.tags)"' | \
        head -n "$LIMIT"
}

semantic_search() {
    local query="$1"
    
    if [[ ! -f "$INDEX_DIR/semantic/vectors.faiss" ]]; then
        echo "  No semantic index found. Run: bash knowledge-indexer.sh rebuild --semantic"
        return 1
    fi
    
    # Use Python for semantic search
    python3 -c "
import sys, json, numpy as np
sys.path.insert(0, '$WORKSPACE/scripts')

# Load index metadata
with open('$INDEX_DIR/semantic/metadata.json') as f:
    metadata = json.load(f)

# Load vectors (placeholder - would use faiss in production)
# For now, return message
print('  Semantic search requires full vector implementation')
print('  Install faiss-cpu and run: pip install faiss-cpu openai')
"
}

build_semantic_vectors() {
    echo "  Building semantic vectors requires:"
    echo "    - TURBOPUFFER_API_KEY"
    echo "    - OPENAI_API_KEY"
    echo "    - python packages: openai, faiss-cpu"
    echo "  Run: pip install openai faiss-cpu"
}

update_manifest() {
    local total_docs=0
    for cat_file in "$INDEX_DIR/by-category"/*.jsonl; do
        [[ -f "$cat_file" ]] && total_docs=$((total_docs + $(wc -l < "$cat_file")))
    done
    
    cat > "$INDEX_DIR/crew-manifest.json" <<MANIFEST
{
  "crew_id": "$CREW_ID",
  "crew_type": "$CREW_TYPE",
  "mode": "$MODE",
  "index_version": "1.0",
  "categories": ["architecture", "api", "ui", "infra", "process", "debugging", "research"],
  "total_documents": $total_docs,
  "last_indexed": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "semantic_vectors": ${SEMANTIC_ENABLED:-false}
}
MANIFEST
}

list_documents() {
    local cat="${1:-}"
    
    if [[ -n "$cat" ]]; then
        if [[ -f "$INDEX_DIR/by-category/$cat.jsonl" ]]; then
            cat "$INDEX_DIR/by-category/$cat.jsonl" | jq -r '. | "\(.timestamp) | \(.agent_id) | \(.title) | \(.tags)"'
        else
            echo "Category not found: $cat"
        fi
    else
        for cat_file in "$INDEX_DIR/by-category"/*.jsonl; do
            [[ -f "$cat_file" ]] || continue
            cat_name=$(basename "$cat_file" .jsonl)
            count=$(wc -l < "$cat_file")
            echo "$cat_name: $count documents"
        done
    fi
}
