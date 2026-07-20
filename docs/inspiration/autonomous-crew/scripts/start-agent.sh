#!/usr/bin/env bash
# start-agent.sh - Start the synthesis-1 agent + enforcer
set -euo pipefail

show_help() {
    cat <<'EOF'
Start Agent - Bootstrap synthesis-1 agent workspace

Usage: bash start-agent.sh <agent-id> [--help]

Arguments:
  agent-id    Agent identifier (e.g., synthesis-1)

Options:
  --help      Show this help message

Environment:
  WORKSPACE_ROOT      Root directory for agent workspaces (default: $HOME/agents)
  ENFORCER_SOCKET_DIR Directory for enforcer Unix sockets (default: $HOME/run/agent-enforcer)

Example:
  bash start-agent.sh synthesis-1
EOF
    exit 0
}

# Handle --help
case "${1:-}" in
    --help|-h) show_help ;;
esac

AGENT_ID="${1:-}"
if [[ -z "$AGENT_ID" ]]; then
    show_help
fi

WORKSPACE_ROOT="${WORKSPACE_ROOT:-}"
if [[ -z "$WORKSPACE_ROOT" ]]; then
    WORKSPACE_ROOT="$HOME/agents"
fi
PYTHON="${PYTHON:-python3}"
AGENT_DIR="$WORKSPACE_ROOT/$AGENT_ID"

echo "=== Starting $AGENT_ID ==="

# 1. Ensure workspace structure
echo "[1/4] Validating workspace..."
if [[ ! -d "$AGENT_DIR" ]]; then
    echo "ERROR: Workspace $AGENT_DIR does not exist"
    exit 1
fi

# 2. Test tools
echo "[2/4] Testing tool sanity..."
for tool in enforce.sh secret.sh memory-log.sh memory-promote.sh; do
    if [[ ! -x "$AGENT_DIR/tools/$tool" ]]; then
        echo "WARNING: Missing or non-executable tool: $tool"
    fi
done
echo "  Tool check complete"

# 3. Start memory curator (background, daily)
echo "[3/4] Running initial curation..."
$PYTHON "$AGENT_DIR/memory_curator.py" "$AGENT_ID" 2>&1 | sed 's/^/  /'

# 4. Start enforcer daemon (background)
echo "[4/4] Starting enforcer daemon..."
$PYTHON "$AGENT_DIR/enforcer_daemon.py" "$AGENT_ID" 2>&1 &
echo "  Enforcer PID: $!"

echo "=== Agent $AGENT_ID running ==="
echo "  Workspace: $AGENT_DIR"
echo "  Initial curation complete"
echo "  Enforcer daemon started"