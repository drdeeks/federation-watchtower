#!/usr/bin/env bash
# Federation Watchtower — Autonomous Agent Demo
# Runs a realistic agent loop: work, test failure, guardrail block, recovery, watchdog expiry.
# Use while recording the Watchtower page. No manual interaction needed.
# Run with: ./scripts/demo-autonomous-agent.sh

set -euo pipefail

API_BASE="${WATCHTOWER_API_BASE:-https://fapi.drdeeks.xyz}"
OWNER_ID="demo-agent-$(date +%s)"
AGENT_ID="demo-runner-$(date +%s)"
PROJECT_ID="autopilot"
HEARTBEAT_PID=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[DEMO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
action() { echo -e "${CYAN}[AGENT]${NC} $1"; }

cleanup() {
  if [[ -n "$HEARTBEAT_PID" ]] && kill -0 "$HEARTBEAT_PID" 2>/dev/null; then
    kill "$HEARTBEAT_PID" 2>/dev/null || true
    wait "$HEARTBEAT_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "========================================"
echo "Autonomous Agent Demo"
echo "========================================"
echo "API: $API_BASE"
echo "Agent: $AGENT_ID"
echo ""

# ── Phase 1: Register & Connect ──────────────────────────────────────────
log "PHASE 1: Registering agent..."

OWNER_RESP=$(curl -s -X POST "$API_BASE/api/v1/owners" \
  -H "Content-Type: application/json" \
  -d "{\"ownerId\":\"$OWNER_ID\",\"displayName\":\"Demo Owner\",\"ownerType\":\"individual\"}")
OWNER_TOKEN=$(echo "$OWNER_RESP" | jq -r '.credential.token // empty')
if [[ -z "$OWNER_TOKEN" ]]; then
  fail "Failed to create owner: $OWNER_RESP"
  exit 1
fi
ok "Owner created: $OWNER_ID"

AGENT_RESP=$(curl -s -X POST "$API_BASE/api/v1/agents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -d "{
    \"agentId\":\"$AGENT_ID\",
    \"displayName\":\"Demo Runner\",
    \"ownerId\":\"$OWNER_ID\",
    \"projectId\":\"$PROJECT_ID\",
    \"role\":\"build-and-test\",
    \"capabilities\":[\"build\",\"test\",\"deploy\"],
    \"identity\":{\"avatarSeed\":\"$AGENT_ID\",\"paletteKey\":\"testing\",\"characterType\":\"operator\"},
    \"publicProjection\":true,
    \"heartbeat\":{\"intervalSeconds\":30},
    \"statement\":\"Runs the build, tests config changes, and reports what happened.\",
    \"lease\":{\"ttlSeconds\":300,\"scopes\":[\"build\",\"test\"]}
  }")

AGENT_TOKEN=$(echo "$AGENT_RESP" | jq -r '.credential.token // empty')
if [[ -z "$AGENT_TOKEN" ]]; then
  fail "Failed to register agent: $AGENT_RESP"
  exit 1
fi
ok "Agent registered: $AGENT_ID"
ok "Auto-lease created"

log "Connecting agent..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/connect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}" > /dev/null
ok "Agent connected"
echo ""

# ── Phase 2: Start Heartbeat Loop ────────────────────────────────────────
log "PHASE 2: Starting heartbeat loop (every 15s)..."

(
  while true; do
    curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/heartbeat" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AGENT_TOKEN" \
      -d "{\"projectId\":\"$PROJECT_ID\"}" > /dev/null 2>&1
    sleep 15
  done
) &
HEARTBEAT_PID=$!
ok "Heartbeat loop running (PID: $HEARTBEAT_PID)"
echo ""

# ── Phase 3: Agent Does Work ─────────────────────────────────────────────
log "PHASE 3: Agent starts working..."

action "Starting build task..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.started\",\"severity\":\"info\",\"statement\":\"Starting build task: updating config and running tests\",\"metadata\":{\"task\":\"config-update\"}}" > /dev/null
ok "Event: run.started"
sleep 3

action "Updated config file..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.completed\",\"severity\":\"success\",\"statement\":\"Updated config.json with new settings\",\"metadata\":{\"file\":\"config.json\",\"action\":\"write\"}}" > /dev/null
ok "Event: config updated"
sleep 3

action "Running tests..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.started\",\"severity\":\"info\",\"statement\":\"Running test suite...\",\"metadata\":{\"tests\":\"3\"}}" > /dev/null
ok "Event: tests started"
sleep 3

# ── Phase 4: Test Fails → Guardrail Catches It ───────────────────────────
log "PHASE 4: Tests fail, agent retries, guardrail blocks it..."
echo ""

warn "Validation 1 FAILED: invalid config value"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"validation.failed\",\"severity\":\"error\",\"statement\":\"Validation failed: config.json has invalid port value\",\"metadata\":{\"test\":\"config-validation\",\"error\":\"port out of range\"}}" > /dev/null
sleep 2

action "Retrying: fixing config..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.started\",\"severity\":\"info\",\"statement\":\"Attempting fix: adjusting port value\",\"metadata\":{\"file\":\"config.json\",\"action\":\"patch\"}}" > /dev/null
sleep 2

warn "Validation 2 FAILED: still invalid"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"validation.failed\",\"severity\":\"error\",\"statement\":\"Validation failed: config.json port still out of range after patch\",\"metadata\":{\"test\":\"config-validation\",\"error\":\"port out of range\"}}" > /dev/null
sleep 2

action "Retrying again..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.started\",\"severity\":\"info\",\"statement\":\"Attempting second fix: resetting to defaults\",\"metadata\":{\"file\":\"config.json\",\"action\":\"reset\"}}" > /dev/null
sleep 2

warn "Validation 3 FAILED → Guardrail RUNAWAY DETECTED"
RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"validation.failed\",\"severity\":\"error\",\"statement\":\"Validation failed: third attempt, config still invalid\",\"metadata\":{\"test\":\"config-validation\",\"error\":\"port out of range\"}}")
echo "$RESPONSE" | jq .
INCIDENTS=$(echo "$RESPONSE" | jq -r '.guardrail.incidentIds // [] | length' 2>/dev/null || echo "0")
ALERTS=$(echo "$RESPONSE" | jq -r '.guardrail.decisions // [] | length' 2>/dev/null || echo "0")
SLACK_ALERTS=$(echo "$RESPONSE" | jq -r '.guardrail.alerts // [] | length' 2>/dev/null || echo "0")
warn "Guardrail triggered: $INCIDENTS incidents, $ALERTS decisions, $SLACK_ALERTS webhook alerts"
echo ""

log "Agent tries to deploy despite failures..."
DEPLOY_RESP=$(curl -s -X POST "$API_BASE/api/v1/projects/$PROJECT_ID/leases" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"agentId\":\"$AGENT_ID\",\"runId\":\"deploy-attempt\",\"ttlSeconds\":300,\"scopes\":[\"deploy\"]}")
DEPLOY_STATUS=$(echo "$DEPLOY_RESP" | jq -r '.status // "unknown"')
if [[ "$DEPLOY_STATUS" == "denied" ]]; then
  ok "DEPLOY BLOCKED by guardrail — agent cannot proceed"
else
  warn "Deploy lease status: $DEPLOY_STATUS (may be allowed depending on guardrail config)"
fi
sleep 3

# ── Phase 5: Agent Recovers ──────────────────────────────────────────────
log ""
log "PHASE 5: Agent fixes the issue properly..."

action "Root cause found: port was 99999, should be 8080"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.completed\",\"severity\":\"success\",\"statement\":\"Fixed config.json: port 99999 → 8080\",\"metadata\":{\"file\":\"config.json\",\"action\":\"fix\",\"port\":\"8080\"}}" > /dev/null
sleep 2

ok "Validation PASSED: config valid"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"validation.passed\",\"severity\":\"success\",\"statement\":\"All validations passing with corrected config\",\"metadata\":{\"test\":\"config-validation\",\"status\":\"passed\"}}" > /dev/null
sleep 2

ok "Build complete"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.completed\",\"severity\":\"success\",\"statement\":\"Build task complete: config updated, tests passing\",\"metadata\":{\"task\":\"config-update\",\"status\":\"success\"}}" > /dev/null
sleep 2

# ── Phase 6: Heartbeat Misses → Watchdog Fires ───────────────────────────
log ""
log "PHASE 6: Agent loses connection, watchdog marks it offline..."
warn "Stopping heartbeat loop — agent will go offline in ~30s..."

kill "$HEARTBEAT_PID" 2>/dev/null || true
HEARTBEAT_PID=""
warn "Waiting for watchdog to fire (30 seconds)..."
sleep 35

ok "Agent should now be OFFLINE on Watchtower"
sleep 2

# ── Phase 7: Agent Reconnects & Clean Shutdown ───────────────────────────
log ""
log "PHASE 7: Agent reconnects, sends final status, disconnects..."

ok "Agent reconnecting..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/connect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}" > /dev/null
sleep 2

ok "Heartbeat restored"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/heartbeat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}" > /dev/null
sleep 2

action "Final status: all systems nominal"
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\",\"eventType\":\"run.completed\",\"severity\":\"success\",\"statement\":\"Session complete. All tasks finished successfully.\",\"metadata\":{\"session\":\"demo\",\"status\":\"clean\"}}" > /dev/null
sleep 2

ok "Agent disconnecting..."
curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/disconnect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}" > /dev/null
ok "Agent disconnected"

echo ""
echo "========================================"
ok "Demo Complete"
echo "========================================"
echo ""
echo "What just happened:"
echo "  1. Agent registered and connected"
echo "  2. Agent started working (config update)"
echo "  3. Tests failed 3 times → guardrail blocked deploy"
echo "  4. Agent fixed root cause → tests passed"
echo "  5. Heartbeat stopped → watchdog marked agent offline"
echo "  6. Agent reconnected and disconnected cleanly"
echo ""
echo "Watch it at: https://watch.drdeeks.xyz"
echo ""

