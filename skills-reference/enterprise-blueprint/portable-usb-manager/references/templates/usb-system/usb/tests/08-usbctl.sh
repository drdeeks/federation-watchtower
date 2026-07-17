#!/usr/bin/env bash
# Test 08: Unified CLI (usbctl)
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing usbctl CLI..."

USBCTL="$USB_DIR/cli/usbctl"

# Test script exists and is executable
assert_file_exists "$USBCTL" "usbctl"
assert_executable "$USBCTL" "usbctl executable"

# Test --help
output=$(bash "$USBCTL" --help 2>&1)
if echo "$output" | grep -qi "usage\|usbctl"; then
  assert_pass "usbctl --help shows usage"
else
  assert_fail "usbctl --help missing usage"
fi

# Test config init
output=$(bash "$USBCTL" config init 2>&1)
if [[ $? -eq 0 ]]; then
  assert_pass "usbctl config init succeeds"
else
  assert_fail "usbctl config init failed"
fi

# Test config host-id
output=$(bash "$USBCTL" config host-id 2>&1)
if echo "$output" | grep -q "usb-compute-"; then
  assert_pass "usbctl config host-id generates ID"
else
  assert_fail "usbctl config host-id missing ID"
fi

# Test config show
output=$(bash "$USBCTL" config show 2>&1)
if echo "$output" | grep -q "version"; then
  assert_pass "usbctl config show displays config"
else
  assert_fail "usbctl config show missing config"
fi

# Test alias --list
output=$(bash "$USBCTL" alias --list 2>&1)
if [[ $? -eq 0 ]]; then
  assert_pass "usbctl alias --list succeeds"
else
  assert_fail "usbctl alias --list failed"
fi

# Test validate host
output=$(bash "$USBCTL" validate host 2>&1)
if echo "$output" | grep -q "passed\|Host ID"; then
  assert_pass "usbctl validate host passes"
else
  assert_fail "usbctl validate host failed"
fi

# Test validate all (partial - no USB)
output=$(bash "$USBCTL" validate all 2>&1)
if echo "$output" | grep -q "Host ID validation passed"; then
  assert_pass "usbctl validate all runs (host ID passes)"
else
  assert_fail "usbctl validate all failed"
fi

log INFO "usbctl tests complete"
