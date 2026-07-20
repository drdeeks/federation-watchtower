#!/usr/bin/env bash
# Federation Watchtower - API Path Validation Script
# Traces every API route to ensure no stalls, silent failures, or crashes.
# Run with: ./scripts/validate-api-paths.sh [--verbose]

set -euo pipefail

API_BASE="${WATCHTOWER_API_BASE:-https://fapi.drdeeks.xyz}"
VERBOSE=false

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${BLUE}[PATH]${NC} $1"; }
pass() { echo -e "${GREEN}[OK]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# Parse arguments
[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

echo "========================================"
echo "API Path Validation"
echo "========================================"
echo "Base: $API_BASE"
echo "Verbose: $VERBOSE"
echo ""

# Test counter
TESTS=0
PASSED=0
FAILED=0

# Helper function to test endpoint
test_endpoint() {
  local method="$1"
  local path="$2"
  local description="$3"
  local expected_status="${4:-200}"
  local headers="${5:-}"
  local data="${6:-}"
  
  TESTS=$((TESTS + 1))
  
  log "$method $path - $description"
  
  local start_time=$(date +%s%3N)
  local response
  local http_code
  
  if [[ -n "$data" ]]; then
    response=$(curl -s -w "\n%{http_code}" -X "$method" "$API_BASE$path" \
      $headers \
      -H "Content-Type: application/json" \
      -d "$data" 2>/dev/null)
  else
    response=$(curl -s -w "\n%{http_code}" -X "$method" "$API_BASE$path" \
      $headers 2>/dev/null)
  fi
  
  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))
  
  http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | sed '$d')
  
  if [[ "$http_code" == "$expected_status" ]]; then
    pass "$http_code (${duration}ms)"
    PASSED=$((PASSED + 1))
    [[ "$VERBOSE" == true ]] && echo "  Response: ${body:0:200}"
    return 0
  else
    fail "$http_code (expected $expected_status) - ${duration}ms"
    FAILED=$((FAILED + 1))
    [[ "$VERBOSE" == true ]] && echo "  Response: ${body:0:200}"
    return 1
  fi
}

# Health checks
echo "=== HEALTH & DISCOVERY ==="
test_endpoint "GET" "/health" "Health check" 200
test_endpoint "GET" "/" "API discovery" 200
test_endpoint "GET" "/api/status" "System status" 200
test_endpoint "GET" "/api/projects" "Project list" 200
test_endpoint "GET" "/api/rooms" "Room list" 200
test_endpoint "GET" "/api/feed?limit=10" "Global feed" 200
test_endpoint "GET" "/api/health" "Health check all" 200
echo ""

# Public room scene
echo "=== PUBLIC READS ==="
test_endpoint "GET" "/api/v1/public/rooms/default/scene" "Default room scene" 200
test_endpoint "GET" "/api/search?q=test&limit=10" "Agent search" 200
echo ""

# Federation verification (public reads)
echo "=== FEDERATION VERIFICATION ==="
test_endpoint "GET" "/api/federation/verified" "Verified federations" 200
test_endpoint "GET" "/api/federation/speech" "Federation speech pool" 200
echo ""

# Create test owner for authenticated tests
info "Creating test owner for authenticated endpoints..."
OWNER_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/owners" \
  -H "Content-Type: application/json" \
  -d "{\"ownerId\":\"path-test-${RANDOM}\",\"displayName\":\"Path Test Owner\",\"ownerType\":\"individual\"}")
OWNER_TOKEN=$(echo "$OWNER_RESPONSE" | jq -r '.credential.token // empty')

if [[ -z "$OWNER_TOKEN" ]]; then
  warn "Could not create owner - skipping authenticated tests"
  OWNER_TOKEN=""
else
  pass "Test owner created"
  echo ""
  
  echo "=== OWNER LIFECYCLE ==="
  test_endpoint "POST" "/api/v1/agents" "Register agent" 201 \
    "-H \"Authorization: Bearer $OWNER_TOKEN\"" \
    "{\"agentId\":\"path-test-agent\",\"displayName\":\"Path Test Agent\",\"ownerId\":\"path-test-owner\",\"projectId\":\"path-test-project\",\"role\":\"testing\",\"capabilities\":[\"testing\"],\"identity\":{\"avatarSeed\":\"path-test\",\"paletteKey\":\"testing\",\"characterType\":\"runner\"},\"publicProjection\":true,\"heartbeat\":{\"intervalSeconds\":60}}"
  
  # Get agent token from response
  AGENT_RESPONSE=$(curl -s -X POST "$API_BASE/api/v1/agents" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $OWNER_TOKEN" \
    -d "{\"agentId\":\"path-test-agent-2\",\"displayName\":\"Path Test Agent 2\",\"ownerId\":\"path-test-owner\",\"projectId\":\"path-test-project\",\"role\":\"testing\",\"capabilities\":[\"testing\"],\"identity\":{\"avatarSeed\":\"path-test-2\",\"paletteKey\":\"testing\",\"characterType\":\"runner\"},\"publicProjection\":true,\"heartbeat\":{\"intervalSeconds\":60}}")
  AGENT_TOKEN=$(echo "$AGENT_RESPONSE" | jq -r '.credential.token // empty')
  
  if [[ -n "$AGENT_TOKEN" ]]; then
    echo ""
    echo "=== AGENT LIFECYCLE ==="
    test_endpoint "POST" "/api/v1/agents/path-test-agent-2/connect" "Agent connect" 200 \
      "-H \"Authorization: Bearer $AGENT_TOKEN\"" \
      "{\"projectId\":\"path-test-project\"}"
    
    test_endpoint "POST" "/api/v1/agents/path-test-agent-2/heartbeat" "Agent heartbeat" 200 \
      "-H \"Authorization: Bearer $AGENT_TOKEN\"" \
      "{\"projectId\":\"path-test-project\"}"
    
    test_endpoint "POST" "/api/v1/agents/path-test-agent-2/events" "Agent event" 201 \
      "-H \"Authorization: Bearer $AGENT_TOKEN\"" \
      "{\"projectId\":\"path-test-project\",\"eventType\":\"action.completed\",\"severity\":\"success\",\"statement\":\"Test event\",\"metadata\":{}}"
    
    test_endpoint "POST" "/api/v1/agents/path-test-agent-2/disconnect" "Agent disconnect" 200 \
      "-H \"Authorization: Bearer $AGENT_TOKEN\"" \
      "{\"projectId\":\"path-test-project\"}"
    
    echo ""
    echo "=== GUARDRAIL & CONTROL LOOP ==="
    test_endpoint "POST" "/api/v1/projects/path-test-project/leases" "Lease request" 201 \
      "-H \"Authorization: Bearer $AGENT_TOKEN\"" \
      "{\"projectId\":\"path-test-project\",\"agentId\":\"path-test-agent-2\",\"runId\":\"test-run\",\"ttlSeconds\":300,\"scopes\":[\"testing\"]}"
    
    test_endpoint "GET" "/api/v1/projects/path-test-project/agents/path-test-agent-2/commands" "Pending commands" 200 \
      "-H \"Authorization: Bearer $AGENT_TOKEN\""
    
    test_endpoint "GET" "/api/v1/projects/path-test-project/budget" "Budget status" 200
    test_endpoint "GET" "/api/v1/projects/path-test-project/sessions?limit=10" "Agent sessions" 200
  fi
fi

echo ""
echo "=== ADMIN ENDPOINTS (expected 401/403 without token) ==="
test_endpoint "GET" "/api/v1/admin/agents" "Admin agents list" 401
test_endpoint "GET" "/api/v1/admin/rooms" "Admin rooms list" 401
test_endpoint "GET" "/api/federation/applications" "Federation applications" 401
test_endpoint "GET" "/api/mcp/logs" "MCP access logs" 401
echo ""

echo "=== MCP ENDPOINTS ==="
test_endpoint "GET" "/mcp" "MCP endpoint (no auth)" 401
echo ""

echo "=== ERROR HANDLING ==="
test_endpoint "GET" "/api/v1/nonexistent" "Unknown route" 404
test_endpoint "POST" "/api/v1/events" "Events without auth" 401
test_endpoint "POST" "/api/v1/agents" "Agents without auth" 401
test_endpoint "GET" "/api/v1/public/rooms/nonexistent-room/scene" "Nonexistent room" 404
echo ""

echo "========================================"
echo "Path Validation Complete"
echo "========================================"
echo "Tests: $TESTS"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo ""

if [[ $FAILED -gt 0 ]]; then
  fail "$FAILED paths failed validation"
  exit 1
else
  pass "All $TESTS paths validated successfully"
  exit 0
fi
