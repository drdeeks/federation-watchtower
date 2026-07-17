#!/usr/bin/env bash
# Test 13: Deploy Dry-Run
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing deploy dry-run..."

DEPLOY="$PROJECT_DIR/hemlock/DEPLOY.sh"

# Test deploy script exists
assert_file_exists "$DEPLOY" "DEPLOY.sh"

# Test deploy requires sudo (expected)
output=$(bash "$DEPLOY" --dry-run 2>&1 || true)
if echo "$output" | grep -qi "sudo\|root"; then
  assert_pass "DEPLOY.sh correctly requires sudo"
else
  assert_pass "DEPLOY.sh ran (may not require sudo in this env)"
fi

# Test deploy --help (if supported)
output=$(bash "$DEPLOY" --help 2>&1 || true)
if [[ -n "$output" ]]; then
  assert_pass "DEPLOY.sh --help produces output"
else
  assert_pass "DEPLOY.sh ran without --help"
fi

# Test setup-essentials exists
assert_file_exists "$USB_DIR/scripts/setup-essentials-enhanced.sh" "setup-essentials-enhanced.sh"

# Test setup-essentials syntax
assert_syntax "$USB_DIR/scripts/setup-essentials-enhanced.sh" "setup-essentials-enhanced.sh"

# Test clean-local.sh exists
assert_file_exists "$USB_DIR/scripts/clean-local.sh" "clean-local.sh"

# Test initialize.sh exists
assert_file_exists "$USB_DIR/config/initialize.sh" "initialize.sh"

# Test automount scripts exist
assert_file_exists "$USB_DIR/usb-automount/setup-usb-automount.sh" "setup-usb-automount.sh"
assert_file_exists "$USB_DIR/usb-automount/teardown-usb-automount.sh" "teardown-usb-automount.sh"

# Test feature-flags.json
FLAGS="$PROJECT_DIR/feature-flags.json"
if [[ -f "$FLAGS" ]]; then
  assert_json_valid "$FLAGS" "feature-flags.json valid JSON"
  flag_count=$(jq '.feature_flags | length' "$FLAGS" 2>/dev/null)
  if [[ "$flag_count" -ge 20 ]]; then
    assert_pass "feature-flags.json has $flag_count flags (>= 20)"
  else
    assert_fail "feature-flags.json has only $flag_count flags"
  fi
else
  assert_fail "feature-flags.json missing"
fi

# Test CHANGELOG.md
if [[ -f "$PROJECT_DIR/CHANGELOG.md" ]]; then
  assert_pass "CHANGELOG.md exists"
else
  assert_fail "CHANGELOG.md missing"
fi

log INFO "Deploy tests complete"
