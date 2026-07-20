#!/usr/bin/env bash
# knowledge-doc.sh - Create formatted documents with agent context (standalone or crew)
set -euo pipefail

show_help() {
    cat <<'EOF'
Knowledge Document Creator - Create formatted documents with agent attribution

Usage: bash knowledge-doc.sh <doc-type> <title> [options]

Document Types:
  decision      Architecture/design decision (requires --reasoning)
  spec          Technical specification
  learning      Lesson learned, bug post-mortem, insight
  communication Message, sync, coordination
  reasoning     Deep reasoning, option analysis
  sync          Status update, checkpoint

Options:
  --category <cat>      Category: architecture|api|ui|infra|process|debugging|research
  --tags <tags>         Comma-separated tags
  --reasoning <text>    Reasoning/thinking process (required for decision)
  --to <agent-id>       Recipient (for communication)
  --type <msg-type>     Message type (for communication)
  --priority <prio>     Priority: low|normal|high|urgent
  --workspace <path>    Workspace (auto-detect)
  --agent-id <id>       Your agent ID (auto-detect from .agent.json)
  --help                Show this help

Environment:
  AGENT_ID              Your agent ID (if not auto-detected)

Standalone Usage:
  bash knowledge-doc.sh decision "OAuth2 Token Refresh" \
    --category architecture \
    --tags "oauth,auth,security" \
    --reasoning "Evaluated JWT vs opaque tokens; chose JWT for statelessness"

  bash knowledge-doc.sh learning "Race condition in session middleware" \
    --category debugging \
    --tags "race-condition,session,middleware"

Crew Usage:
  bash knowledge-doc.sh communication "Ready for confirmation phase" \
    --type broadcast \
    --priority high
EOF
    exit 0
}

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

# Auto-detect agent ID from workspace
detect_agent_id() {
    local dir="$(pwd)"
    while [[ "$dir" != "/" ]]; do
        # Check standalone config
        if [[ -f "$dir/.agent.json" ]]; then
            jq -r .agent_id "$dir/.agent.json" 2>/dev/null && return 0
        fi
        # Check crew agent workspace
        if [[ -f "$dir/agent.json" ]]; then
            jq -r .agent_id "$dir/agent.json" 2>/dev/null && return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# Handle --help before any workspace detection
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    show_help
fi

WORKSPACE="${WORKSPACE_ROOT:-${CREW_WORKSPACE:-}}"
if [[ -z "$WORKSPACE" ]]; then
    WORKSPACE="$(detect_workspace)" || {
        echo "ERROR: Not in a knowledge workspace"
        echo "Run: bash init-knowledge-workspace.sh <agent-id>"
        exit 1
    }
fi

AGENT_ID="${AGENT_ID:-}"
if [[ -z "$AGENT_ID" ]]; then
    AGENT_ID="$(detect_agent_id)" || {
        echo "ERROR: Could not auto-detect agent ID. Set AGENT_ID or run from agent workspace."
        exit 1
    }
fi

# Detect mode
if [[ -f "$WORKSPACE/.agent.json" && ! -f "$WORKSPACE/crew.json" ]]; then
    MODE="standalone"
    CREW_ID="standalone-$AGENT_ID"
    CREW_MODE="$(jq -r .mode "$WORKSPACE/.agent.json" 2>/dev/null || echo "development")"
    AGENT_TYPE="standalone"
elif [[ -f "$WORKSPACE/crew.json" ]]; then
    MODE="crew"
    CREW_ID="$(jq -r .crew_id "$WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
    CREW_MODE="$(jq -r .crew_type "$WORKSPACE/crew.json" 2>/dev/null || echo "development")"
    AGENT_TYPE="$(jq -r .type "$WORKSPACE/agents/$AGENT_ID/agent.json" 2>/dev/null || echo "unknown")"
else
    echo "ERROR: Invalid workspace configuration"
    exit 1
fi

DOC_TYPE="${1:-}"
TITLE="${2:-}"
shift 2 || true

if [[ -z "$DOC_TYPE" || -z "$TITLE" ]]; then
    echo "ERROR: doc-type and title required"
    show_help
fi

VALID_TYPES="decision spec learning communication reasoning sync"
if ! echo "$VALID_TYPES" | grep -qw "$DOC_TYPE"; then
    echo "ERROR: Invalid doc-type. Valid: $VALID_TYPES"
    exit 1
fi

# Parse options
CATEGORY=""
TAGS=""
REASONING=""
TO_AGENT=""
MSG_TYPE="sync"
PRIORITY="normal"

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --tags) TAGS="$2"; shift 2 ;;
        --reasoning) REASONING="$2"; shift 2 ;;
        --to) TO_AGENT="$2"; shift 2 ;;
        --type) MSG_TYPE="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --agent-id) AGENT_ID="$2"; shift 2 ;;
        *) echo "ERROR: Unknown option: $1"; show_help ;;
    esac
done

# Default category by doc type
if [[ -z "$CATEGORY" ]]; then
    case "$DOC_TYPE" in
        decision|spec) CATEGORY="architecture" ;;
        learning) CATEGORY="debugging" ;;
        communication) CATEGORY="process" ;;
        reasoning) CATEGORY="architecture" ;;
        sync) CATEGORY="process" ;;
    esac
fi

# Validate category
VALID_CATS="architecture api ui infra process debugging research"
if ! echo "$VALID_CATS" | grep -qw "$CATEGORY"; then
    echo "ERROR: Invalid category. Valid: $VALID_CATS"
    exit 1
fi

# Require reasoning for decisions
if [[ "$DOC_TYPE" == "decision" && -z "$REASONING" ]]; then
    echo "ERROR: --reasoning required for decision documents"
    exit 1
fi

# Generate metadata
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
SESSION_ID="sess-$(openssl rand -hex 6 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 12)"
DOC_ID="${DOC_TYPE}-${CATEGORY}-$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')-$(openssl rand -hex 4 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 8)"

# Format tags as YAML array
if [[ -n "$TAGS" ]]; then
    TAGS_YAML=$(echo "$TAGS" | sed 's/,/","/g' | sed 's/^/["/' | sed 's/$/"]/')
else
    TAGS_YAML="[]"
fi

# Determine output path
if [[ "$MODE" == "standalone" ]]; then
    OUTPUT_DIR="$WORKSPACE/knowledge/$CATEGORY"
else
    # Crew mode
    if [[ -d "$WORKSPACE/agents/$AGENT_ID" ]]; then
        OUTPUT_DIR="$WORKSPACE/agents/$AGENT_ID/knowledge/$CATEGORY"
    else
        OUTPUT_DIR="$WORKSPACE/shared/knowledge/$CATEGORY"
    fi
fi
mkdir -p "$OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/${DOC_ID}.md"

# Build document content
SECTION_TITLE=""
case "$DOC_TYPE" in
    decision) SECTION_TITLE="Decision" ;;
    spec) SECTION_TITLE="Specification" ;;
    learning) SECTION_TITLE="Lesson Learned" ;;
    communication) SECTION_TITLE="Message" ;;
    reasoning) SECTION_TITLE="Analysis" ;;
    sync) SECTION_TITLE="Status Update" ;;
esac

# Read template
TEMPLATE_FILE="$WORKSPACE/references/templates/knowledge/document-template.md"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    # Try relative path from script location
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    TEMPLATE_FILE="$(dirname "$SCRIPT_DIR")/references/templates/knowledge/document-template.md"
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo "ERROR: Template not found: $TEMPLATE_FILE"
    exit 1
fi

# Generate document
cat "$TEMPLATE_FILE" | sed \
    -e "s/{{AGENT_ID}}/$AGENT_ID/g" \
    -e "s/{{AGENT_TYPE}}/$AGENT_TYPE/g" \
    -e "s/{{CREW_ID}}/$CREW_ID/g" \
    -e "s/{{CREW_MODE}}/$CREW_MODE/g" \
    -e "s/{{DOC_TYPE}}/$DOC_TYPE/g" \
    -e "s/{{CATEGORY}}/$CATEGORY/g" \
    -e "s/{{TAGS}}/$TAGS_YAML/g" \
    -e "s/{{TIMESTAMP}}/$TIMESTAMP/g" \
    -e "s/{{SESSION_ID}}/$SESSION_ID/g" \
    -e "s/{{TITLE}}/$TITLE/g" \
    -e "s/{{SECTION_TITLE}}/$SECTION_TITLE/g" \
    -e "s/{{DOC_ID}}/$DOC_ID/g" > "$OUTPUT_FILE"

# Append type-specific content
case "$DOC_TYPE" in
    decision)
        cat >> "$OUTPUT_FILE" <<DECISION

## Context / Problem Statement
[Why this decision exists, what triggered it]

## Reasoning / Thinking Process
$REASONING

## Decision
[The actual decision made]

## Implications / Follow-up
[What this affects, what needs to happen next]

## Related
- [[wikilink-to-related-doc]]
DECISION
        ;;
    spec)
        cat >> "$OUTPUT_FILE" <<SPEC

## Overview
[What this spec covers]

## Requirements
- Functional: [...]
- Non-functional: [...]

## Design / Architecture
[Technical design details]

## API / Interface
[If applicable]

## Implementation Notes
[Guidance for implementers]

## Testing Criteria
[How to validate]

## Related
- [[wikilink-to-related-doc]]
SPEC
        ;;
    learning)
        cat >> "$OUTPUT_FILE" <<LEARNING

## What Happened
[Event, bug, discovery, experiment]

## Root Cause / Analysis
[Why it happened]

## Lesson Learned
[The durable insight]

## Prevention / Application
[How to apply this going forward]

## Related
- [[wikilink-to-related-doc]]
LEARNING
        ;;
    communication)
        cat >> "$OUTPUT_FILE" <<COMM

## Message
[The communication content]

## Context
- Thread: [[thread-id]]
- Related: [[doc-id]]
COMM
        ;;
    reasoning)
        cat >> "$OUTPUT_FILE" <<REASONING

## Problem / Question
[What is being reasoned about]

## Options Considered
1. Option A - [pros/cons]
2. Option B - [pros/cons]
3. Option C - [pros/cons]

## Analysis
[Deep dive reasoning]

## Recommendation
[Recommended path with rationale]

## Related
- [[wikilink-to-related-doc]]
REASONING
        ;;
    sync)
        cat >> "$OUTPUT_FILE" <<SYNC

## Status Update
[Current state]

## Completed
- [x] Item 1
- [x] Item 2

## In Progress
- [ ] Item 3

## Blockers
- Blocker description

## Next Steps
- [ ] Next action

## Related
- [[wikilink-to-related-doc]]
SYNC
        ;;
esac

# Add auto-footer
cat >> "$OUTPUT_FILE" <<FOOTER
---
*Generated by agent \`$AGENT_ID\` ($AGENT_TYPE) at $TIMESTAMP in crew \`$CREW_ID\` ($CREW_MODE)*
*Session: $SESSION_ID | Category: $CATEGORY | Doc ID: $DOC_ID*
FOOTER

echo "✅ Document created: $OUTPUT_FILE"
echo "   Type: $DOC_TYPE | Category: $CATEGORY"
echo "   Agent: $AGENT_ID | Crew: $CREW_ID"
echo "   Doc ID: $DOC_ID"
