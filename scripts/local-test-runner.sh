#!/usr/bin/env bash
# Federation Watchtower - Local Development Test Runner
# Runs comprehensive tests against a local development environment.
# Requires: npm, node, wrangler configured with local D1/R2

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SERVERLESS_DIR="$PROJECT_ROOT/source/federation-serverless"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; exit 1; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "========================================"
echo "Federation Watchtower - Local Test Suite"
echo "========================================"
echo ""

cd "$SERVERLESS_DIR"

# Step 1: Install dependencies
log "Installing dependencies..."
npm install --silent > /dev/null 2>&1 || npm install
pass "Dependencies installed"
echo ""

# Step 2: TypeScript compilation
log "Compiling TypeScript..."
if npm run types > /dev/null 2>&1; then
  pass "TypeScript compilation successful"
else
  fail "TypeScript compilation failed"
fi
echo ""

# Step 3: Run unit tests
log "Running unit tests..."
if npm test 2>&1 | tee /tmp/test-output.txt; then
  TEST_COUNT=$(grep "^# pass" /tmp/test-output.txt | grep -o "[0-9]*" | head -1)
  pass "Unit tests passed ($TEST_COUNT tests)"
else
  fail "Unit tests failed"
fi
echo ""

# Step 4: Validate JavaScript syntax
log "Validating JavaScript syntax..."
JS_FILES=(
  "$PROJECT_ROOT/source/federation-tv-widget/public/tv-widget.js"
  "$PROJECT_ROOT/source/federation-tv-widget/src/tv-widget.js"
)

for file in "${JS_FILES[@]}"; do
  if node --check "$file" 2>/dev/null; then
    pass "JavaScript syntax valid: $(basename "$file")"
  else
    fail "JavaScript syntax error in $file"
  fi
done
echo ""

# Step 5: Check git cleanliness
log "Checking git status..."
cd "$PROJECT_ROOT"
if git diff --check 2>&1 | grep -q "error"; then
  fail "Git whitespace errors found"
else
  pass "Git diff clean"
fi

if git status --porcelain | grep -q "^??" ; then
  warn "Untracked files present (this is OK for test runs)"
  git status --porcelain | grep "^??" | head -5
else
  pass "No untracked files"
fi
echo ""

# Step 6: Validate schema migrations exist
log "Validating database migrations..."
MIGRATION_FILES=(
  "0001_watchtower_enforcement.sql"
  "0002_watchtower_control_loop.sql"
  "0003_watchtower_access_gateway.sql"
  "0004_federation_lifecycle.sql"
  "0005_management.sql"
  "0006_alert_webhook_receipts.sql"
)

for migration in "${MIGRATION_FILES[@]}"; do
  if [[ -f "$SERVERLESS_DIR/src/migrations/$migration" ]]; then
    pass "Migration exists: $migration"
  else
    fail "Missing migration: $migration"
  fi
done
echo ""

# Step 7: Validate critical source files
log "Validating critical source files..."
SOURCE_FILES=(
  "src/index.ts"
  "src/lifecycle.ts"
  "src/federation-coordinator.ts"
  "src/agent-watchdog.ts"
  "src/project-guardrail.ts"
  "src/agent-registry.ts"
  "src/room-scene.ts"
  "src/watchtower.ts"
)

for file in "${SOURCE_FILES[@]}"; do
  if [[ -f "$SERVERLESS_DIR/$file" ]]; then
    pass "Source file exists: $file"
  else
    fail "Missing source file: $file"
  fi
done
echo ""

# Step 8: Validate HTML pages
log "Validating HTML pages..."
HTML_FILES=(
  "index.html"
  "join.html"
  "integrate.html"
  "organization.html"
  "federation.html"
  "operator.html"
  "onboarding.html"
  "manage.html"
  "demo.html"
)

for file in "${HTML_FILES[@]}"; do
  if [[ -f "$PROJECT_ROOT/source/federation-tv-widget/public/$file" ]]; then
    pass "HTML page exists: $file"
  else
    fail "Missing HTML page: $file"
  fi
done
echo ""

# Step 9: Validate documentation
log "Validating documentation..."
DOC_FILES=(
  "README.md"
  "AGENTS.md"
  "FINAL_SUBMISSION_STATUS.md"
  "VIDEO_RECORDING_GUIDE.md"
)

for file in "${DOC_FILES[@]}"; do
  if [[ -f "$PROJECT_ROOT/$file" ]]; then
    pass "Documentation exists: $file"
  else
    fail "Missing documentation: $file"
  fi
done
echo ""

# Step 10: SDK tests
log "Running SDK tests..."
cd "$PROJECT_ROOT/packages/watchtower-sdk"
if npm install --silent > /dev/null 2>&1 || npm install > /dev/null 2>&1; then
  if npm test 2>&1 | tee /tmp/sdk-test-output.txt; then
    SDK_COUNT=$(grep "^# pass" /tmp/sdk-test-output.txt | grep -o "[0-9]*" | head -1)
    pass "SDK tests passed ($SDK_COUNT tests)"
  else
    fail "SDK tests failed"
  fi
else
  fail "SDK dependency installation failed"
fi
echo ""

echo "========================================"
pass "All Local Tests Passed"
echo "========================================"
echo ""
echo "Next steps:"
echo "  1. Deploy to Cloudflare: cd source/federation-serverless && npm run deploy"
echo "  2. Run E2E tests: ./scripts/e2e-agent-lifecycle.sh"
echo "  3. Test guardrail failures: ./scripts/test-guardrail-failures.sh"
echo ""
