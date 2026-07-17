#!/usr/bin/env bash
# Test 01: Syntax Validation
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing syntax of all shell files..."

# USB lib
for f in "$USB_DIR"/lib/*.sh; do
  assert_syntax "$f" "$(basename "$f")"
done

# USB cli
assert_syntax "$USB_DIR/cli/usbctl" "usbctl"

# USB scripts
for f in "$USB_DIR"/scripts/*.sh; do
  assert_syntax "$f" "$(basename "$f")"
done

# USB top-level
for f in usb-setup-assistant.sh sysman.sh hemlock-tui; do
  [[ -f "$USB_DIR/$f" ]] && assert_syntax "$USB_DIR/$f" "$f"
done

# USB automount
for f in "$USB_DIR"/usb-automount/*.sh; do
  [[ -f "$f" ]] && assert_syntax "$f" "$(basename "$f")"
done

# Config
[[ -f "$USB_DIR/config/initialize.sh" ]] && assert_syntax "$USB_DIR/config/initialize.sh" "initialize.sh"

# Hemlock
for f in DEPLOY.sh hemlock-tui; do
  [[ -f "$PROJECT_DIR/hemlock/$f" ]] && assert_syntax "$PROJECT_DIR/hemlock/$f" "hemlock/$f"
done

# Hemlock runtime scripts
if [[ -d "$PROJECT_DIR/hemlock/hemlock-runtime/scripts" ]]; then
  find "$PROJECT_DIR/hemlock/hemlock-runtime/scripts" \( -name '*.sh' -o -name 'hemlock' \) -type f | while read -r f; do
    assert_syntax "$f" "$(echo "$f" | sed "s|$PROJECT_DIR/hemlock/hemlock-runtime/||")"
  done
fi

# Master menu
[[ -f "$PROJECT_DIR/menu.sh" ]] && assert_syntax "$PROJECT_DIR/menu.sh" "menu.sh"

# Test scripts
for f in "$SCRIPT_DIR"/*.sh; do
  [[ "$(basename "$f")" == "test-helpers.sh" ]] && continue
  [[ "$(basename "$f")" == "run-all.sh" ]] && continue
  assert_syntax "$f" "tests/$(basename "$f")"
done

log INFO "Syntax tests complete"
