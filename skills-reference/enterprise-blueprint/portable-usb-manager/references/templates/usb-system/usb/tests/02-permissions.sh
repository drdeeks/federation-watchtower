#!/usr/bin/env bash
# Test 02: File Permissions
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing file permissions..."

# All .sh files should be readable
find "$USB_DIR" "$PROJECT_DIR/hemlock" -name '*.sh' -type f 2>/dev/null | while read -r f; do
  if [[ -r "$f" ]]; then
    assert_pass "$(echo "$f" | sed "s|$PROJECT_DIR/||") readable"
  else
    assert_fail "$(echo "$f" | sed "s|$PROJECT_DIR/||") not readable"
  fi
done

# Executable scripts should have +x
for f in "$USB_DIR/cli/usbctl" "$USB_DIR/usb-setup-assistant.sh" "$USB_DIR/sysman.sh" \
         "$USB_DIR/scripts/alias_manager.sh" "$USB_DIR/scripts/ssh_host_manager.sh" \
         "$USB_DIR/hemlock-tui" "$PROJECT_DIR/hemlock/hemlock-tui" "$PROJECT_DIR/hemlock/DEPLOY.sh" \
         "$PROJECT_DIR/menu.sh"; do
  [[ -f "$f" ]] && assert_executable "$f" "$(echo "$f" | sed "s|$PROJECT_DIR/||")"
done

log INFO "Permission tests complete"
