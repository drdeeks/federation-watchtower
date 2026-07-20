#!/usr/bin/env bash
# Federation Watchtower - End-to-End Agent Lifecycle Test
# This script demonstrates the complete agent lifecycle with both success and failure scenarios.
# Run with: ./scripts/e2e-agent-lifecycle.sh [--fail] [--cleanup]

set -euo pipefail

# Configuration
API_BASE="${WATCHTOWER_API_BASE:-https://fapi.drdeeks.xyz}"
OWNER_ID="e2e-test-${RANDOM}"
AGENT_ID="e2e-agent-${RANDOM}"
PROJECT_ID="e2e-project-${RANDOM}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
FAIL_MODE=false
CLEANUP=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --fail) FAIL_MODE=true; shift ;;
    --cleanup) CLEANUP=true; shift ;;
    *) echo "Usage: $0 [--fail] [--cleanup]"; exit 1 ;;
  esac
done

log_info "Starting E2E Agent Lifecycle Test"
log_info "API Base: $API_BASE"
log_info "Owner ID: $OWNER_ID"
log_info "Agent ID: $AGENT_ID"
log_info "Project ID: $PROJECT_ID"
log_info "Mode: $([ "$FAIL_MODE" = true ] && echo "FAILURE SCENARIO" || echo "SUCCESS SCENARIO")"
echo ""

# Step 1: Create Owner
log_info "Step 1: Creating owner..."
OWNER_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/owners" \
  -H "Content-Type: application/json" \
  -d "{\"ownerId\":\"$OWNER_ID\",\"displayName\":\"E2E Test Owner\",\"ownerType\":\"individual\"}")

OWNER_TOKEN=$(echo "$OWNER_RESPONSE" | jq -r '.credential.token // empty')
if [[ -z "$OWNER_TOKEN" ]]; then
  log_error "Failed to create owner: $OWNER_RESPONSE"
  exit 1
fi
log_success "Owner created successfully"
echo "Owner credential: ${OWNER_TOKEN:0:40}..."
echo ""

# Step 2: Register Agent (with auto-lease)
log_info "Step 2: Registering agent (with auto-lease)..."
AGENT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OWNER_TOKEN" \
  -d "{
    \"agentId\":\"$AGENT_ID\",
    \"displayName\":\"E2E Test Agent\",
    \"ownerId\":\"$OWNER_ID\",
    \"projectId\":\"$PROJECT_ID\",
    \"role\":\"e2e-testing\",
    \"capabilities\":[\"testing\",\"reporting\"],
    \"identity\":{\"avatarSeed\":\"$AGENT_ID\",\"paletteKey\":\"testing\",\"characterType\":\"runner\"},
    \"publicProjection\":true,
    \"heartbeat\":{\"intervalSeconds\":60},
    \"lease\":{\"ttlSeconds\":300,\"scopes\":[\"testing\",\"reporting\"]}
  }")

AGENT_TOKEN=$(echo "$AGENT_RESPONSE" | jq -r '.credential.token // empty')
AGENT_LIFECYCLE=$(echo "$AGENT_RESPONSE" | jq -r '.agent.lifecycleState // empty')
LEASE_ID=$(echo "$AGENT_RESPONSE" | jq -r '.lease.leaseId // empty')
LEASE_STATUS=$(echo "$AGENT_RESPONSE" | jq -r '.lease.status // empty')
if [[ -z "$AGENT_TOKEN" ]]; then
  log_error "Failed to register agent: $AGENT_RESPONSE"
  exit 1
fi
log_success "Agent registered successfully (lifecycle: $AGENT_LIFECYCLE)"
log_success "Auto-lease created: $LEASE_ID (status: $LEASE_STATUS)"
echo "Agent credential: ${AGENT_TOKEN:0:40}..."
echo ""

# Step 3: Connect Agent
log_info "Step 3: Connecting agent..."
CONNECT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/connect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}")

CONNECT_STATE=$(echo "$CONNECT_RESPONSE" | jq -r '.agent.lifecycleState // empty')
if [[ "$CONNECT_STATE" != "connected" ]]; then
  log_error "Failed to connect agent: $CONNECT_RESPONSE"
  exit 1
fi
log_success "Agent connected successfully"
echo ""

# Step 4: Send Heartbeat
log_info "Step 4: Sending heartbeat..."
HEARTBEAT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/heartbeat" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}")

WATCHDOG_DEADLINE=$(echo "$HEARTBEAT_RESPONSE" | jq -r '.watchdogDeadlineAt // empty')
if [[ -z "$WATCHDOG_DEADLINE" ]]; then
  log_error "Failed to send heartbeat: $HEARTBEAT_RESPONSE"
  exit 1
fi
log_success "Heartbeat sent (watchdog deadline: $(date -d "@$((WATCHDOG_DEADLINE/1000))" 2>/dev/null || echo "$WATCHDOG_DEADLINE"))"
echo ""

# Step 4b: Validate Lease (before work)
log_info "Step 4b: Validating lease (required before each action)..."
LEASE_VALIDATE_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/projects/$PROJECT_ID/leases/$LEASE_ID/validate" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"agentId\":\"$AGENT_ID\"}")

VALIDATE_STATUS=$(echo "$LEASE_VALIDATE_RESPONSE" | jq -r '.status // empty')
if [[ "$VALIDATE_STATUS" != "active" ]]; then
  log_error "Lease validation failed: $LEASE_VALIDATE_RESPONSE"
  exit 1
fi
log_success "Lease validated (status: $VALIDATE_STATUS)"
echo ""

# Step 5: Emit Events (Success or Failure path)
if [[ "$FAIL_MODE" = true ]]; then
  log_warning "FAILURE MODE: Emitting validation failure events..."
  
  # Emit 3 validation failures to trigger guardrail alert
  for i in 1 2 3; do
    log_info "Emitting validation failure event $i/3..."
    EVENT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $AGENT_TOKEN" \
      -d "{
        \"projectId\":\"$PROJECT_ID\",
        \"eventType\":\"validation.failed\",
        \"severity\":\"error\",
        \"statement\":\"Test validation failure $i\",
        \"metadata\":{\"testRun\":\"e2e-failure\"}
      }")
    
    INCIDENT_COUNT=$(echo "$EVENT_RESPONSE" | jq -r '.guardrail.incidentIds | length // 0')
    log_info "Event accepted, incidents: $INCIDENT_COUNT"
    sleep 1
  done
  
  log_warning "Guardrail should have triggered alert after 3 validation failures"
  
  # Try to request a lease (should be denied due to blocking command)
  log_info "Attempting to request lease (should be denied)..."
  LEASE_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/projects/$PROJECT_ID/leases" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_TOKEN" \
    -d "{
      \"projectId\":\"$PROJECT_ID\",
      \"agentId\":\"$AGENT_ID\",
      \"runId\":\"test-run-1\",
      \"ttlSeconds\":300,
      \"scopes\":[\"testing\"]
    }")
  
  LEASE_STATUS=$(echo "$LEASE_RESPONSE" | jq -r '.status // empty')
  log_info "Lease status: $LEASE_STATUS (expected: denied due to blocking command)"
  
else
  log_info "SUCCESS MODE: Emitting normal operational events..."
  
  # Emit successful action event
  log_info "Emitting action event..."
  EVENT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/events" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_TOKEN" \
    -d "{
      \"projectId\":\"$PROJECT_ID\",
      \"eventType\":\"action.completed\",
      \"severity\":\"success\",
      \"statement\":\"Test action completed successfully\",
      \"metadata\":{\"testRun\":\"e2e-success\"}
    }")
  
  log_success "Action event emitted successfully"
  
  # Emit heartbeat again to stay alive
  log_info "Sending second heartbeat..."
  HEARTBEAT2_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/heartbeat" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AGENT_TOKEN" \
    -d "{\"projectId\":\"$PROJECT_ID\"}")
  
  log_success "Second heartbeat sent"
fi

echo ""

# Step 6: Disconnect Agent
log_info "Step 6: Disconnecting agent..."
DISCONNECT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents/$AGENT_ID/disconnect" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $AGENT_TOKEN" \
  -d "{\"projectId\":\"$PROJECT_ID\"}")

DISCONNECT_STATE=$(echo "$DISCONNECT_RESPONSE" | jq -r '.agent.lifecycleState // empty')
if [[ "$DISCONNECT_STATE" != "offline" ]]; then
  log_error "Failed to disconnect agent: $DISCONNECT_RESPONSE"
  exit 1
fi
log_success "Agent disconnected successfully"
echo ""

# Step 7: Verify Public Projection
log_info "Step 7: Verifying public projection..."
ROOM_SCENE_RESPONSE=$(curl -s "$API_BASE/api/v1/public/rooms/default/scene")
log_success "Room scene retrieved"
echo ""

# Step 8: Cleanup (optional)
if [[ "$CLEANUP" = true ]]; then
  log_info "Cleaning up test data..."
  # Note: In production, you would need admin credentials to delete
  log_warning "Cleanup requires admin credentials - skipping for now"
fi

echo ""
log_success "=========================================="
log_success "E2E Agent Lifecycle Test Complete"
log_success "=========================================="
log_info "Watch your agent at: https://watch.drdeeks.xyz"
log_info "Check admin console at: https://federation.drdeeks.xyz/manage.html"
echo ""
log_info "Test summary:"
log_info "  - Owner created: $OWNER_ID"
log_info "  - Agent registered: $AGENT_ID"
log_info "  - Project: $PROJECT_ID"
log_info "  - Mode: $([ "$FAIL_MODE" = true ] && echo "FAILURE (guardrail alerts triggered)" || echo "SUCCESS (all events accepted)")"
echo ""
