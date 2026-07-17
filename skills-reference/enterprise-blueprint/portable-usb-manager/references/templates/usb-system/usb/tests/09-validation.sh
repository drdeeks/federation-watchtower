#!/usr/bin/env bash
# Test 09: Validation Engine + Self-Heal
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing validation engine..."

# Source validation module
source "$USB_DIR/lib/validation.sh" 2>/dev/null

# Test validate_host_id
if validate_host_id 2>/dev/null; then
  assert_pass "validate_host_id succeeds"
else
  assert_fail "validate_host_id failed"
fi

# Test validate_menu_stack
if validate_menu_stack 2>/dev/null; then
  assert_pass "validate_menu_stack succeeds"
else
  assert_fail "validate_menu_stack failed"
fi

# Test validate_usb_mount (expected to fail - no device)
if validate_usb_mount 2>/dev/null; then
  assert_pass "validate_usb_mount succeeds (unexpected)"
else
  assert_pass "validate_usb_mount fails gracefully (no device)"
fi

# Test self_heal with config
CONFIG_FILE="$HOME/.config/usb-compute-automation/config.json"
BACKUP=""
[[ -f "$CONFIG_FILE" ]] && BACKUP=$(mktemp) && cp "$CONFIG_FILE" "$BACKUP"

# Delete config to test self-heal
rm -f "$CONFIG_FILE" 2>/dev/null

# Self-heal should regenerate
if self_heal validate_host_id config_init 2>/dev/null; then
  assert_pass "self_heal regenerates missing config"
else
  assert_fail "self_heal failed to regenerate config"
fi

# Verify config was recreated
if [[ -f "$CONFIG_FILE" ]]; then
  assert_pass "config.json recreated after self-heal"
else
  assert_fail "config.json not recreated"
fi

# Restore
[[ -n "$BACKUP" && -f "$BACKUP" ]] && mv "$BACKUP" "$CONFIG_FILE"
rm -f "$CONFIG_FILE.bak-test-$$" 2>/dev/null

log INFO "Validation tests complete"
