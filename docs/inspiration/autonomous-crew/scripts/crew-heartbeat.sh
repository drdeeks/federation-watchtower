#!/usr/bin/env bash
# crew-heartbeat.sh - Aggregate heartbeat status across all crew agents
set -euo pipefail

show_help() {
    cat <<'EOF'
Crew Heartbeat - Aggregate health status across all crew agents

Usage: bash crew-heartbeat.sh <crew-id> [--help] [--json]

Arguments:
  crew-id     Crew identifier

Options:
  --help      Show this help message
  --json      Output JSON for programmatic use

Environment:
  WORKSPACE_ROOT      Root for crew workspaces (default: $HOME/crews)

Example:
  bash crew-heartbeat.sh hackathon-2026
  bash crew-heartbeat.sh hackathon-2026 --json
EOF
    exit 0
}

JSON_OUTPUT=false
case "${1:-}" in
    --help|-h) show_help ;;
    --json) JSON_OUTPUT=true; CREW_ID="${2:-}" ;;
    *) CREW_ID="${1:-}" ;;
esac

if [[ -z "$CREW_ID" ]]; then
    echo "ERROR: crew-id required"
    show_help
fi

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/crews}"
CREW_DIR="$WORKSPACE_ROOT/$CREW_ID"
AGENTS_DIR="$CREW_DIR/agents"

if [[ ! -d "$AGENTS_DIR" ]]; then
    echo "ERROR: Crew directory not found: $CREW_DIR"
    exit 1
fi

if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo "{"
    echo "  \"crew_id\": \"$CREW_ID\","
    echo "  \"timestamp\": $(date +%s),"
    echo "  \"agents\": ["
fi

FIRST=true
OVERALL_HEALTHY=true

for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    AGENT_ID=$(basename "$agent_dir")
    
    # Check enforcer socket
    SOCKET="$agent_dir/.agent/enforcer.sock"
    if [[ -S "$SOCKET" ]]; then
        # Try RPC health check
        HEALTH_CHECK=$(timeout 2 python3 -c "
import asyncio, json, sys
async def check():
    try:
        reader, writer = await asyncio.open_unix_connection('$SOCKET')
        writer.write(json.dumps({'method': 'heartbeat', 'params': {'status': 'health_check'}}).encode() + b'\n')
        await writer.drain()
        line = await asyncio.wait_for(reader.readline(), timeout=2)
        writer.close()
        return json.loads(line.decode())
    except Exception as e:
        return {'error': str(e)}
print(json.dumps(asyncio.run(check())))
" 2>/dev/null || echo '{"error": "timeout"}')
        
        if echo "$HEALTH_CHECK" | grep -q '"status": "ok"'; then
            STATUS="healthy"
            LAST_HEARTBEAT=$(echo "$HEALTH_CHECK" | python3 -c "import sys, json; print(json.load(sys.stdin).get('timestamp', 0))" 2>/dev/null || echo 0)
        else
            STATUS="unhealthy"
            OVERALL_HEALTHY=false
            LAST_HEARTBEAT=0
        fi
    else
        STATUS="no_enforcer"
        OVERALL_HEALTHY=false
        LAST_HEARTBEAT=0
    fi
    
    # Get constitution hash
    CONST_HASH=""
    if [[ -f "$agent_dir/.agent/constitution.yaml" ]]; then
        CONST_HASH=$(sha256sum "$agent_dir/.agent/constitution.yaml" | cut -d' ' -f1 | head -c 16)
    fi
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        [[ "$FIRST" == "true" ]] || echo ","
        FIRST=false
        cat <<AGENT
    {
      "agent_id": "$AGENT_ID",
      "status": "$STATUS",
      "last_heartbeat": $LAST_HEARTBEAT,
      "constitution_hash": "$CONST_HASH",
      "enforcer_socket": "$SOCKET"
    }
AGENT
    else
        printf "  %-25s %s" "$AGENT_ID" "$STATUS"
        [[ "$STATUS" == "healthy" ]] && printf " ✅" || printf " ❌"
        [[ -n "$CONST_HASH" ]] && printf " (constitution: %s...)" "$CONST_HASH"
        echo ""
    fi
done

if [[ "$JSON_OUTPUT" == "true" ]]; then
    echo ""
    echo "  ],"
    echo "  \"overall_healthy\": $OVERALL_HEALTHY"
    echo "}"
fi

if [[ "$JSON_OUTPUT" != "true" ]]; then
    echo ""
    if [[ "$OVERALL_HEALTHY" == "true" ]]; then
        echo "✅ CREW HEALTHY - All agents reporting"
    else
        echo "❌ CREW DEGRADED - Some agents unhealthy"
    fi
fi

[[ "$OVERALL_HEALTHY" == "true" ]] && exit 0 || exit 1