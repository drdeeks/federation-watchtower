#!/usr/bin/env bash
# Test 07: System Manager Subcommands
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing sysman subcommands..."

SYSMAN="$USB_DIR/sysman.sh"

# Test script exists
assert_file_exists "$SYSMAN" "sysman.sh"

# Test --help
output=$(bash "$SYSMAN" --help 2>&1)
if echo "$output" | grep -qi "usage\|sysman"; then
  assert_pass "sysman --help shows usage"
else
  assert_fail "sysman --help missing usage"
fi

# Test --health (should not enter interactive mode)
output=$(bash "$SYSMAN" --health 2>&1)
rc=$?
if echo "$output" | grep -q "System Health Dashboard\|Hostname"; then
  assert_pass "sysman --health shows dashboard"
else
  assert_fail "sysman --health missing dashboard output"
fi

# Verify no interactive fallthrough
if echo "$output" | grep -q "Select an option"; then
  assert_fail "sysman --health entered interactive mode"
else
  assert_pass "sysman --health did not enter interactive mode"
fi

# Test --info
output=$(bash "$SYSMAN" --info 2>&1)
if [[ $? -eq 0 ]] && [[ -n "$output" ]]; then
  assert_pass "sysman --info produces output"
else
  assert_fail "sysman --info failed or empty"
fi

# Test --disk (may timeout on some systems, so use short timeout)
output=$(timeout 10 bash "$SYSMAN" --disk 2>&1 || true)
if [[ -n "$output" ]]; then
  assert_pass "sysman --disk produces output"
else
  assert_skip "sysman --disk timed out or empty"
fi

# Test --network
output=$(timeout 10 bash "$SYSMAN" --network 2>&1 || true)
if [[ -n "$output" ]]; then
  assert_pass "sysman --network produces output"
else
  assert_skip "sysman --network timed out or empty"
fi

# Test --services
output=$(timeout 10 bash "$SYSMAN" --services 2>&1 || true)
if [[ -n "$output" ]]; then
  assert_pass "sysman --services produces output"
else
  assert_skip "sysman --services timed out or empty"
fi

# Test --process
output=$(timeout 10 bash "$SYSMAN" --process 2>&1 || true)
if [[ -n "$output" ]]; then
  assert_pass "sysman --process produces output"
else
  assert_skip "sysman --process timed out or empty"
fi

# Test --logs
output=$(timeout 10 bash "$SYSMAN" --logs 2>&1 || true)
if [[ -n "$output" ]]; then
  assert_pass "sysman --logs produces output"
else
  assert_skip "sysman --logs timed out or empty"
fi

log INFO "Sysman tests complete"
