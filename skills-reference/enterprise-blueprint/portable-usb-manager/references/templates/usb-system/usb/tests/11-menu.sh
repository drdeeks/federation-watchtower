#!/usr/bin/env bash
# Test 11: Master Menu Integration
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing master menu..."

MENU="$PROJECT_DIR/menu.sh"

# Test menu exists
assert_file_exists "$MENU" "menu.sh"

# Test --help
output=$(bash "$MENU" --help 2>&1)
if echo "$output" | grep -qi "usage\|menu"; then
  assert_pass "menu.sh --help shows usage"
else
  assert_fail "menu.sh --help missing usage"
fi

# Test menu sources all libraries
if grep -q "source.*logging.sh" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh sources logging.sh"
else
  assert_fail "menu.sh missing logging.sh source"
fi

if grep -q "source.*core.sh" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh sources core.sh"
else
  assert_fail "menu.sh missing core.sh source"
fi

if grep -q "source.*menu.sh" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh sources lib/menu.sh"
else
  assert_fail "menu.sh missing lib/menu.sh source"
fi

if grep -q "source.*config.sh" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh sources config.sh"
else
  assert_fail "menu.sh missing config.sh source"
fi

if grep -q "source.*validation.sh" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh sources validation.sh"
else
  assert_fail "menu.sh missing validation.sh source"
fi

# Test menu references all major components
for component in "usb-setup-assistant" "alias_manager" "ssh_host_manager" "sysman" "hemlock-tui" "usbctl" "DEPLOY" "automount" "setup-essentials"; do
  if grep -q "$component" "$MENU" 2>/dev/null; then
    assert_pass "menu.sh references $component"
  else
    assert_fail "menu.sh missing reference to $component"
  fi
done

# Test --text flag
if grep -q "text" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh supports --text flag"
else
  assert_fail "menu.sh missing --text flag"
fi

# Test --dry-run flag
if grep -q "dry-run" "$MENU" 2>/dev/null; then
  assert_pass "menu.sh supports --dry-run flag"
else
  assert_fail "menu.sh missing --dry-run flag"
fi

log INFO "Master menu tests complete"
