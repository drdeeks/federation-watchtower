#!/usr/bin/env bash
# verify-crew-identity.sh - Verify all agents in crew have operational identity layer
set -euo pipefail

show_help() {
    cat <<'EOF'
Verify Crew Identity - Validate identity layer across all crew agents

Usage: bash verify-crew-identity.sh <crew-id> [--help]

Arguments:
  crew-id     Crew identifier

Options:
  --help      Show this help message

Environment:
  WORKSPACE_ROOT      Root for crew workspaces (default: $HOME/crews)

Example:
  bash verify-crew-identity.sh hackathon-2026
EOF
    exit 0
}

case "${1:-}" in
    --help|-h) show_help ;;
esac

CREW_ID="${1:-}"
if [[ -z "$CREW_ID" ]]; then
    echo "ERROR: crew-id required"
    show_help
fi

WORKSPACE_ROOT="${WORKSPACE_ROOT:-$HOME/crews}"
CREW_DIR="$WORKSPACE_ROOT/$CREW_ID"
AGENTS_DIR="$CREW_DIR/agents"

IDENTITY_SKILL="${AGENT_IDENTITY_SKILL:-${HOME}/.hermes/skills/devops/agent-identity-architecture}"

if [[ ! -d "$AGENTS_DIR" ]]; then
    echo "ERROR: Crew directory not found: $CREW_DIR"
    exit 1
fi

echo "=== Verifying Crew Identity: $CREW_ID ==="
echo ""

TOTAL=0
PASS=0
FAIL=0

for agent_dir in "$AGENTS_DIR"/*/; do
    [[ -d "$agent_dir" ]] || continue
    AGENT_ID=$(basename "$agent_dir")
    TOTAL=$((TOTAL + 1))
    
    echo "--- $AGENT_ID ---"
    
    # Check constitution exists and readable
    if [[ -f "$agent_dir/.agent/constitution.yaml" ]]; then
        echo "  ✅ Constitution exists"
    else
        echo "  ❌ Constitution MISSING"
        FAIL=$((FAIL + 1))
        continue
    fi
    
    # Check 3 core habits
    HABIT_COUNT=$(ls "$agent_dir/.agent/habits"/*.yaml 2>/dev/null | wc -l)
    if [[ $HABIT_COUNT -ge 3 ]]; then
        echo "  ✅ Habits: $HABIT_COUNT internalized"
    else
        echo "  ❌ Habits: only $HABIT_COUNT (need 3+)"
        FAIL=$((FAIL + 1))
        continue
    fi
    
    # Check tools
    TOOL_COUNT=0
    for tool in enforce.sh secret.sh memory-log.sh memory-promote.sh; do
        [[ -x "$agent_dir/tools/$tool" ]] && TOOL_COUNT=$((TOOL_COUNT + 1))
    done
    if [[ $TOOL_COUNT -eq 5 ]]; then
        echo "  ✅ Tools: all 5 executable"
    else
        echo "  ❌ Tools: only $TOOL_COUNT/5 executable"
        FAIL=$((FAIL + 1))
        continue
    fi
    
    # Check memory pipeline
    if [[ -d "$agent_dir/memory/daily" && -d "$agent_dir/memory/weekly" && -d "$agent_dir/memory/long-term" ]]; then
        echo "  ✅ Memory pipeline directories exist"
    else
        echo "  ❌ Memory pipeline incomplete"
        FAIL=$((FAIL + 1))
        continue
    fi
    
    # Check enforcer daemon files
    if [[ -f "$agent_dir/enforcer_daemon.py" && -f "$agent_dir/agent_runtime.py" && -f "$agent_dir/memory_curator.py" ]]; then
        echo "  ✅ Enforcer runtime files present"
    else
        echo "  ❌ Enforcer runtime files missing"
        FAIL=$((FAIL + 1))
        continue
    fi
    
    # Check crew config
    if [[ -f "$agent_dir/.agent/crew-config.yaml" ]]; then
        echo "  ✅ Crew config present"
    else
        echo "  ❌ Crew config missing"
        FAIL=$((FAIL + 1))
        continue
    fi
    
    PASS=$((PASS + 1))
    echo "  ✅ $AGENT_ID: IDENTITY LAYER OPERATIONAL"
done

echo ""
echo "=== CREW IDENTITY VERIFICATION SUMMARY ==="
echo "  Total agents: $TOTAL"
echo "  Passed: $PASS"
echo "  Failed: $FAIL"

if [[ $FAIL -eq 0 && $TOTAL -gt 0 ]]; then
    echo "  Status: ✅ ALL AGENTS HAVE OPERATIONAL IDENTITY LAYER"
    exit 0
else
    echo "  Status: ❌ IDENTITY LAYER GAPS DETECTED"
    exit 1
fi