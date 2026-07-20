#!/usr/bin/env bash
# knowledge-comm.sh - Agent communication protocol (standalone or crew)
set -euo pipefail

show_help() {
    cat <<'EOF'
Knowledge Communication - Structured agent-to-agent messaging

Usage: bash knowledge-comm.sh <command> [options]

Commands:
  send                  Send message to another agent
  reply                 Reply to existing thread
  broadcast             Broadcast to all agents
  thread                View message thread
  list                  List messages/threads
  sync                  Sync communications to knowledge index

Options:
  --from <id>           Sender agent ID (required for send/reply/broadcast)
  --to <id>             Recipient agent ID (required for send)
  --thread <id>         Thread ID (required for reply/thread)
  --subject <text>      Message subject (required for send/broadcast)
  --body <text>         Message body (required for send/reply/broadcast)
  --type <type>         Message type: sync|question|proposal|decision|broadcast|alert (default: sync)
  --priority <prio>     Priority: low|normal|high|urgent (default: normal)
  --tags <tags>         Comma-separated tags
  --workspace <path>    Workspace (auto-detect)
  --help                Show this help

Standalone Usage:
  # Self-documentation (create a message for future reference)
  bash knowledge-comm.sh send --from my-agent --to my-agent --subject "Design decision" --body "Chose X because Y"

  # Create thread for tracking
  bash knowledge-comm.sh send --from my-agent --to my-agent --subject "Task tracking" --body "Starting work on feature X"

Crew Usage:
  bash knowledge-comm.sh send --from ui-a1b2 --to integration-b2c3 --subject "API contract" --body "Need to align..."
  bash knowledge-comm.sh reply --thread comm-7f9a2b1c --from integration-b2c3 --body "Proposing..."
  bash knowledge-comm.sh broadcast --from lead-x1y2 --subject "Phase gate" --body "All agents confirm..."
  bash knowledge-comm.sh thread comm-7f9a2b1c
EOF
    exit 0
}

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

# Detect mode
if [[ -f "$WORKSPACE/.agent.json" && ! -f "$WORKSPACE/crew.json" ]]; then
    MODE="standalone"
    CREW_ID="standalone-$(jq -r .agent_id "$WORKSPACE/.agent.json" 2>/dev/null || echo "unknown")"
elif [[ -f "$WORKSPACE/crew.json" ]]; then
    MODE="crew"
    CREW_ID="$(jq -r .crew_id "$WORKSPACE/crew.json" 2>/dev/null || echo "unknown")"
else
    echo "ERROR: Invalid workspace configuration"
    exit 1
fi

# Set up directory paths based on mode
if [[ "$MODE" == "standalone" ]]; then
    COMM_DIR="$WORKSPACE/communications"
else
    COMM_DIR="$WORKSPACE/shared/communications"
fi

MESSAGES_DIR="$COMM_DIR/messages"
THREADS_DIR="$COMM_DIR/threads"
BROADCASTS_DIR="$COMM_DIR/broadcasts"

mkdir -p "$MESSAGES_DIR" "$THREADS_DIR" "$BROADCASTS_DIR"

COMMAND="${1:-}"
shift || true

# Parse common options
FROM_AGENT=""
TO_AGENT=""
THREAD_ID=""
SUBJECT=""
BODY=""
MSG_TYPE="sync"
PRIORITY="normal"
TAGS=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h) show_help ;;
        --from) FROM_AGENT="$2"; shift 2 ;;
        --to) TO_AGENT="$2"; shift 2 ;;
        --thread) THREAD_ID="$2"; shift 2 ;;
        --subject) SUBJECT="$2"; shift 2 ;;
        --body) BODY="$2"; shift 2 ;;
        --type) MSG_TYPE="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --tags) TAGS="$2"; shift 2 ;;
        --workspace) WORKSPACE="$2"; shift 2 ;;
        *) break ;;
    esac
done

# Validate message type
VALID_TYPES="sync question proposal decision broadcast alert"
if ! echo "$VALID_TYPES" | grep -qw "$MSG_TYPE"; then
    echo "ERROR: Invalid message type. Valid: $VALID_TYPES"
    exit 1
fi

# Validate priority
VALID_PRIOS="low normal high urgent"
if ! echo "$VALID_PRIOS" | grep -qw "$PRIORITY"; then
    echo "ERROR: Invalid priority. Valid: $VALID_PRIOS"
    exit 1
fi

case "$COMMAND" in
    send)
        [[ -z "$FROM_AGENT" ]] && { echo "ERROR: --from required"; exit 1; }
        [[ -z "$TO_AGENT" ]] && { echo "ERROR: --to required"; exit 1; }
        [[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
        [[ -z "$BODY" ]] && { echo "ERROR: --body required"; exit 1; }
        
        send_message
        ;;
        
    reply)
        [[ -z "$FROM_AGENT" ]] && { echo "ERROR: --from required"; exit 1; }
        [[ -z "$THREAD_ID" ]] && { echo "ERROR: --thread required"; exit 1; }
        [[ -z "$BODY" ]] && { echo "ERROR: --body required"; exit 1; }
        
        reply_to_thread
        ;;
        
    broadcast)
        [[ -z "$FROM_AGENT" ]] && { echo "ERROR: --from required"; exit 1; }
        [[ -z "$SUBJECT" ]] && { echo "ERROR: --subject required"; exit 1; }
        [[ -z "$BODY" ]] && { echo "ERROR: --body required"; exit 1; }
        
        broadcast_message
        ;;
        
    thread)
        [[ -z "$THREAD_ID" ]] && { echo "ERROR: --thread required"; exit 1; }
        
        view_thread
        ;;
        
    list)
        list_messages
        ;;
        
    sync)
        sync_communications
        ;;
        
    *)
        echo "ERROR: Unknown command: $COMMAND"
        show_help
        ;;
esac

# ============================================================================
# Internal Functions
# ============================================================================

send_message() {
    local msg_id="comm-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local thread_id="thread-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    
    # Get sender agent type
    local from_type=$(get_agent_type "$FROM_AGENT")
    local to_type=$(get_agent_type "$TO_AGENT")
    
    # Create message file
    local msg_file="$MESSAGES_DIR/${msg_id}.md"
    cat > "$msg_file" <<MSG
---
message_id: "$msg_id"
thread_id: "$thread_id"
from_agent: "$FROM_AGENT"
from_type: "$from_type"
to_agent: "$TO_AGENT"
to_type: "$to_type"
crew_id: "$CREW_ID"
type: "$MSG_TYPE"
subject: "$SUBJECT"
priority: "$PRIORITY"
timestamp: "$timestamp"
tags: "$TAGS"
---

## Message

$BODY

## Context
- From: $FROM_AGENT ($from_type)
- To: $TO_AGENT ($to_type)
- Type: $MSG_TYPE
- Priority: $PRIORITY
MSG
    
    # Create/update thread
    local thread_file="$THREADS_DIR/${thread_id}.md"
    if [[ ! -f "$thread_file" ]]; then
        cat > "$thread_file" <<THREAD
---
thread_id: "$thread_id"
crew_id: "$CREW_ID"
created_utc: "$timestamp"
subject: "$SUBJECT"
participants: ["$FROM_AGENT", "$TO_AGENT"]
message_count: 1
last_activity: "$timestamp"
---

## Thread: $SUBJECT

### Message 1: $FROM_AGENT → $TO_AGENT ($timestamp)

$BODY

---
THREAD
    else
        # Append to existing thread
        local msg_count=$(grep -c "^### Message" "$thread_file" 2>/dev/null || echo 0)
        msg_count=$((msg_count + 1))
        
        # Update thread metadata
        sed -i "s/message_count: [0-9]*/message_count: $msg_count/" "$thread_file"
        sed -i "s/last_activity: .*/last_activity: \"$timestamp\"/" "$thread_file"
        
        # Add participant if new
        if ! grep -q "\"$FROM_AGENT\"" "$thread_file"; then
            sed -i "s/participants: \[/participants: [\"$FROM_AGENT\", /" "$thread_file"
        fi
        if ! grep -q "\"$TO_AGENT\"" "$thread_file"; then
            sed -i "s/participants: \[/participants: [\"$TO_AGENT\", /" "$thread_file"
        fi
        
        cat >> "$thread_file" <<THREAD

### Message $msg_count: $FROM_AGENT → $TO_AGENT ($timestamp)

$BODY

---
THREAD
    fi
    
    echo "✅ Message sent: $msg_id"
    echo "  Thread: $thread_id"
    echo "  From: $FROM_AGENT → To: $TO_AGENT"
    echo "  Subject: $SUBJECT"
}

reply_to_thread() {
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local from_type=$(get_agent_type "$FROM_AGENT")
    
    local thread_file="$THREADS_DIR/${THREAD_ID}.md"
    [[ -f "$thread_file" ]] || { echo "ERROR: Thread not found: $THREAD_ID"; exit 1; }
    
    local msg_id="comm-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local msg_file="$MESSAGES_DIR/${msg_id}.md"
    
    # Get thread subject and participants
    local thread_subject=$(grep "^subject:" "$thread_file" | cut -d'"' -f2)
    local participants=$(grep "participants:" "$thread_file" | sed 's/.*\[\(.*\)\].*/\1/')
    
    # Determine recipient (first participant that isn't sender)
    local to_agent=""
    for p in $(echo "$participants" | tr ',' ' '); do
        p=$(echo "$p" | tr -d '"' | xargs)
        if [[ "$p" != "$FROM_AGENT" ]]; then
            to_agent="$p"
            break
        fi
    done
    
    local to_type=$(get_agent_type "$to_agent")
    
    # Create reply message
    cat > "$msg_file" <<MSG
---
message_id: "$msg_id"
thread_id: "$THREAD_ID"
from_agent: "$FROM_AGENT"
from_type: "$from_type"
to_agent: "$to_agent"
to_type: "$to_type"
crew_id: "$CREW_ID"
type: "reply"
subject: "Re: $thread_subject"
priority: "$PRIORITY"
timestamp: "$timestamp"
tags: "$TAGS"
---

## Reply

$BODY

## Context
- Thread: $THREAD_ID
- In reply to: $thread_subject
- From: $FROM_AGENT ($from_type)
- To: $to_agent ($to_type)
MSG
    
    # Append to thread
    local msg_count=$(grep -c "^### Message" "$thread_file" 2>/dev/null || echo 0)
    msg_count=$((msg_count + 1))
    
    sed -i "s/message_count: [0-9]*/message_count: $msg_count/" "$thread_file"
    sed -i "s/last_activity: .*/last_activity: \"$timestamp\"/" "$thread_file"
    
    cat >> "$thread_file" <<THREAD

### Message $msg_count: $FROM_AGENT → $to_agent ($timestamp)

$BODY

---
THREAD
    
    echo "✅ Reply sent: $msg_id"
    echo "  Thread: $THREAD_ID"
    echo "  From: $FROM_AGENT → To: $to_agent"
}

broadcast_message() {
    local msg_id="broadcast-$(openssl rand -hex 8 2>/dev/null || cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16)"
    local timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    local from_type=$(get_agent_type "$FROM_AGENT")
    
    # Create broadcast file
    local broadcast_file="$BROADCASTS_DIR/${msg_id}.md"
    cat > "$broadcast_file" <<BROADCAST
---
broadcast_id: "$msg_id"
from_agent: "$FROM_AGENT"
from_type: "$from_type"
crew_id: "$CREW_ID"
subject: "$SUBJECT"
priority: "$PRIORITY"
timestamp: "$timestamp"
tags: "$TAGS"
---

## Broadcast

$BODY

## Context
- From: $FROM_AGENT ($from_type)
- Type: broadcast
- Priority: $PRIORITY
- Audience: All agents
BROADCAST
    
    echo "✅ Broadcast sent: $msg_id"
    echo "  From: $FROM_AGENT"
    echo "  Subject: $SUBJECT"
}

view_thread() {
    local thread_file="$THREADS_DIR/${THREAD_ID}.md"
    [[ -f "$thread_file" ]] || { echo "ERROR: Thread not found: $THREAD_ID"; exit 1; }
    
    cat "$thread_file"
}

list_messages() {
    echo "=== Messages for: $CREW_ID ==="
    echo ""
    echo "--- Direct Messages ---"
    for msg in "$MESSAGES_DIR"/*.md; do
        [[ -f "$msg" ]] || continue
        local from=$(grep "from_agent:" "$msg" | head -1 | cut -d'"' -f2)
        local to=$(grep "to_agent:" "$msg" | head -1 | cut -d'"' -f2)
        local subj=$(grep "subject:" "$msg" | head -1 | cut -d'"' -f2)
        local ts=$(grep "timestamp:" "$msg" | head -1 | cut -d'"' -f2)
        local type=$(grep "type:" "$msg" | head -1 | cut -d'"' -f2)
        echo "  $ts | $type | $from → $to | $subj"
    done | sort -r
    
    echo ""
    echo "--- Broadcasts ---"
    for bc in "$BROADCASTS_DIR"/*.md; do
        [[ -f "$bc" ]] || continue
        local from=$(grep "from_agent:" "$bc" | head -1 | cut -d'"' -f2)
        local subj=$(grep "subject:" "$bc" | head -1 | cut -d'"' -f2)
        local ts=$(grep "timestamp:" "$bc" | head -1 | cut -d'"' -f2)
        echo "  $ts | broadcast | $from | $subj"
    done | sort -r
    
    echo ""
    echo "--- Threads ---"
    for thread in "$THREADS_DIR"/*.md; do
        [[ -f "$thread" ]] || continue
        local tid=$(grep "thread_id:" "$thread" | head -1 | cut -d'"' -f2)
        local subj=$(grep "subject:" "$thread" | head -1 | cut -d'"' -f2)
        local count=$(grep "message_count:" "$thread" | head -1 | cut -d' ' -f2)
        local last=$(grep "last_activity:" "$thread" | head -1 | cut -d'"' -f2)
        echo "  $tid | $count msgs | $last | $subj"
    done | sort -r
}

sync_communications() {
    echo "=== Syncing Communications to Knowledge Index ==="
    
    # Index all messages into knowledge base
    local synced=0
    for msg in "$MESSAGES_DIR"/*.md; do
        [[ -f "$msg" ]] || continue
        local agent=$(grep "from_agent:" "$msg" | head -1 | cut -d'"' -f2)
        local timestamp=$(grep "timestamp:" "$msg" | head -1 | cut -d'"' -f2)
        local subject=$(grep "subject:" "$msg" | head -1 | cut -d'"' -f2)
        local type=$(grep "type:" "$msg" | head -1 | cut -d'"' -f2)
        local msg_id=$(grep "message_id:" "$msg" | head -1 | cut -d'"' -f2)
        
        # Create communication document
        if [[ "$MODE" == "standalone" ]]; then
            local comm_file="$WORKSPACE/documents/communications/${msg_id}.md"
        else
            local comm_file="$WORKSPACE/shared/documents/communications/${msg_id}.md"
        fi
        
        mkdir -p "$(dirname "$comm_file")"
        
        cat > "$comm_file" <<COMM
---
agent_id: "$agent"
crew_id: "$CREW_ID"
doc_type: "communication"
category: "process"
timestamp: "$timestamp"
tags: "communication,$type"
---

# Communication: $subject

**Type:** $type
**From:** $agent
**Timestamp:** $timestamp
**Message ID:** $msg_id

---

$(sed -n '/^## Message$/,/^## Context$/p' "$msg" | head -n -1)
COMM
        ((synced++))
    done
    
    echo "  ✅ Synced $synced communications to knowledge index"
    echo "  Run: bash scripts/knowledge-indexer.sh index to update search index"
}

get_agent_type() {
    local agent_id="$1"
    
    # Check standalone config
    if [[ -f "$WORKSPACE/.agent.json" ]]; then
        local config_agent_id=$(jq -r .agent_id "$WORKSPACE/.agent.json" 2>/dev/null)
        if [[ "$agent_id" == "$config_agent_id" ]]; then
            echo "standalone"
            return 0
        fi
    fi
    
    # Check crew agent workspace
    local agent_dir="$WORKSPACE/agents/$agent_id"
    if [[ -f "$agent_dir/agent.json" ]]; then
        jq -r .type "$agent_dir/agent.json" 2>/dev/null || echo "unknown"
    else
        # Try to infer from crew.json
        jq -r --arg aid "$agent_id" '.agent_types[] | select(. | contains($aid))' "$WORKSPACE/crew.json" 2>/dev/null | head -1 || echo "unknown"
    fi
}
