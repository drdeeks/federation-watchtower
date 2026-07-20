#!/usr/bin/env bash
# Federation Watchtower - Guardrail Failure Scenario Test
# This script demonstrates guardrail enforcement by triggering specific failure conditions.
# Run with: ./scripts/test-guardrail-failures.sh

set -euo pipefail

API_BASE="${WATCHTOWER_API_BASE:-https://fapi.drdeeks.xyz}"
TEST_ID="guardrail-test-${RANDOM}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[TEST]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "========================================"
echo "Guardrail Failure Scenario Tests"
echo "========================================"
echo ""

# Test 1: Validation Failure Runaway (3+ failures triggers alert)
log "Test 1: Validation Failure Runaway Detection"
echo "Creating test agent for validation failure test..."

OWNER_RESP=$(curl -s -X POST "$API_BASE/api/v1/owners" \
  -H "Content-Type: application/json" \
  -d "{\"ownerId\":\"${TEST_ID}-owner\",\"displayName\":\"Guardrail Test Owner\",\"ownerType\":\"individual\"}")
OWNER_TOKEN=$(echo "$OWNER_RESP" | jq -r '.credential.token')

AGENT_RESP=$(curl -s -X POST "$API_BASE/api/v1/agents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -d "{\"agentId\":\"${TEST_ID}-agent\",\"displayName\":\"Validation Test Agent\",\"ownerId\":\"${TEST_ID}-owner\",\"projectId\":\"${TEST_ID}-project\",\"role\":\"testing\",\"capabilities\":[\"testing\"],\"identity\":{\"avatarSeed\":\"${TEST_ID}\",\"paletteKey\":\"testing\",\"characterType\":\"runner\"},\"publicProjection\":true,\"heartbeat\":{\"intervalSeconds\":60}}")
AGENT_TOKEN=$(echo "$AGENT_RESP" | jq -r '.credential.token')

# Connect
curl -s -X POST "$API_BASE/api/v1/agents/${TEST_ID}-agent/connect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"${TEST_ID}-project\"}" > /dev/null

# Emit 3 validation failures
warn "Emitting 3 validation.failed events to trigger runaway rule..."
for i in 1 2 3; do
  RESP=$(curl -s -X POST "$API_BASE/api/v1/agents/${TEST_ID}-agent/events" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_TOKEN" \
    -d "{\"projectId\":\"${TEST_ID}-project\",\"eventType\":\"validation.failed\",\"severity\":\"error\",\"statement\":\"Validation failure $i\",\"metadata\":{}}")
  INCIDENTS=$(echo "$RESP" | jq -r '.guardrail.incidentIds | length // 0')
  echo "  Event $i: incidents=$INCIDENTS"
done

# Check if blocking command was created
COMMANDS=$(curl -s "$API_BASE/api/v1/projects/${TEST_ID}-project/agents/${TEST_ID}-agent/commands" \
  -H "Authorization: Bearer $AGENT_TOKEN")
COMMAND_COUNT=$(echo "$COMMANDS" | jq -r '.commands | length // 0')

if [[ "$COMMAND_COUNT" -gt 0 ]]; then
  pass "Blocking command created (count: $COMMAND_COUNT)"
  echo "  Commands: $(echo "$COMMANDS" | jq -r '.commands[].action' | tr '\n' ' ')"
else
  fail "No blocking commands created"
fi

# Try to acquire lease (should be denied)
LEASE_RESP=$(curl -s -X POST "$API_BASE/api/v1/projects/${TEST_ID}-project/leases" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"${TEST_ID}-project\",\"agentId\":\"${TEST_ID}-agent\",\"runId\":\"test-run\",\"ttlSeconds\":300,\"scopes\":[\"testing\"]}")
LEASE_STATUS=$(echo "$LEASE_RESP" | jq -r '.status')

if [[ "$LEASE_STATUS" == "denied" ]]; then
  pass "Lease correctly denied due to blocking command"
else
  fail "Lease status unexpected: $LEASE_STATUS"
fi

echo ""

# Test 2: Duplicate Chain Key Detection
log "Test 2: Duplicate Chain Key Detection"

AGENT2_RESP=$(curl -s -X POST "$API_BASE/api/v1/agents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -d "{\"agentId\":\"${TEST_ID}-agent2\",\"displayName\":\"Chain Test Agent\",\"ownerId\":\"${TEST_ID}-owner\",\"projectId\":\"${TEST_ID}-project\",\"role\":\"testing\",\"capabilities\":[\"testing\"],\"identity\":{\"avatarSeed\":\"${TEST_ID}2\",\"paletteKey\":\"testing\",\"characterType\":\"runner\"},\"publicProjection\":true,\"heartbeat\":{\"intervalSeconds\":60}}")
AGENT2_TOKEN=$(echo "$AGENT2_RESP" | jq -r '.credential.token')

curl -s -X POST "$API_BASE/api/v1/agents/${TEST_ID}-agent2/connect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT2_TOKEN" \
  -d "{\"projectId\":\"${TEST_ID}-project\"}" > /dev/null

CHAIN_KEY="duplicate-chain-${RANDOM}"
warn "Emitting 3 run.started events with same chainKey..."

for i in 1 2 3; do
  RESP=$(curl -s -X POST "$API_BASE/api/v1/agents/${TEST_ID}-agent2/events" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT2_TOKEN" \
    -d "{\"projectId\":\"${TEST_ID}-project\",\"eventType\":\"run.started\",\"severity\":\"info\",\"statement\":\"Starting run $i\",\"chainKey\":\"$CHAIN_KEY\",\"runId\":\"run-$i\",\"metadata\":{}}")
  INCIDENTS=$(echo "$RESP" | jq -r '.guardrail.incidentIds | length // 0')
  DECISIONS=$(echo "$RESP" | jq -r '.decisions | length // 0')
  echo "  Event $i: incidents=$INCIDENTS, decisions=$DECISIONS"
done

echo ""

# Test 3: Budget Threshold Alert
log "Test 3: Budget Threshold Alert"

AGENT3_RESP=$(curl -s -X POST "$API_BASE/api/v1/agents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -d "{\"agentId\":\"${TEST_ID}-agent3\",\"displayName\":\"Budget Test Agent\",\"ownerId\":\"${TEST_ID}-owner\",\"projectId\":\"${TEST_ID}-budget-project\",\"role\":\"testing\",\"capabilities\":[\"testing\"],\"identity\":{\"avatarSeed\":\"${TEST_ID}3\",\"paletteKey\":\"testing\",\"characterType\":\"runner\"},\"publicProjection\":true,\"heartbeat\":{\"intervalSeconds\":60}}")
AGENT3_TOKEN=$(echo "$AGENT3_RESP" | jq -r '.credential.token')

curl -s -X POST "$API_BASE/api/v1/agents/${TEST_ID}-agent3/connect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT3_TOKEN" \
  -d "{\"projectId\":\"${TEST_ID}-budget-project\"}" > /dev/null

warn "Emitting events with creditCostUsd to exceed default budget ($10)..."
CUMULATIVE=0
for i in 1 2 3 4 5; do
  COST=3
  CUMULATIVE=$((CUMULATIVE + COST))
  RESP=$(curl -s -X POST "$API_BASE/api/v1/agents/${TEST_ID}-agent3/events" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT3_TOKEN" \
    -d "{\"projectId\":\"${TEST_ID}-budget-project\",\"eventType\":\"action.completed\",\"severity\":\"success\",\"statement\":\"Expensive action $i\",\"metadata\":{\"creditCostUsd\":$COST}}")
  DECISIONS=$(echo "$RESP" | jq -r '.decisions[] | select(.ruleId=="budget.threshold") | .reason // empty')
  if [[ -n "$DECISIONS" ]]; then
    echo "  Event $i (cumulative: \$${CUMULATIVE}): BUDGET ALERT TRIGGERED"
  else
    echo "  Event $i (cumulative: \$${CUMULATIVE}): within budget"
  fi
done

echo ""

# Test 4: Controlled Tool Authorization
log "Test 4: Controlled Tool Authorization"

# First get an active lease
LEASE_RESP=$(curl -s -X POST "$API_BASE/api/v1/projects/${TEST_ID}-project/leases" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"${TEST_ID}-project\",\"agentId\":\"${TEST_ID}-agent\",\"runId\":\"tool-test-run\",\"ttlSeconds\":300,\"scopes\":[\"testing\"]}")
LEASE_ID=$(echo "$LEASE_RESP" | jq -r '.leaseId')

if [[ "$LEASE_ID" != "null" && "$LEASE_ID" != "" ]]; then
  warn "Requesting controlled tool authorization..."
  TOOL_RESP=$(curl -s -X POST "$API_BASE/api/v1/projects/${TEST_ID}-project/tools/authorize" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_TOKEN" \
    -d "{\"projectId\":\"${TEST_ID}-project\",\"agentId\":\"${TEST_ID}-agent\",\"leaseId\":\"$LEASE_ID\",\"toolName\":\"test.tool\",\"action\":\"execute\",\"requestId\":\"tool-req-${RANDOM}\",\"inputDigest\":\"sha256:test\"}")
  
  TOOL_STATUS=$(echo "$TOOL_RESP" | jq -r '.status')
  if [[ "$TOOL_STATUS" == "authorized" ]]; then
    pass "Tool authorization granted"
  else
    warn "Tool authorization: $TOOL_STATUS - $(echo "$TOOL_RESP" | jq -r '.reason // "no reason"')"
  fi
else
  warn "Skipping tool auth test - no active lease (blocking command present)"
fi

echo ""
echo "========================================"
echo "Guardrail Tests Complete"
echo "========================================"
echo ""
echo "Check results at:"
echo "  - Public Watchtower: https://watch.drdeeks.xyz"
echo "  - Admin Console: https://federation.drdeeks.xyz/manage.html"
echo "  - Incidents: https://fapi.drdeeks.xyz/api/v1/projects/${TEST_ID}-project/incidents (admin token required)"
echo ""
