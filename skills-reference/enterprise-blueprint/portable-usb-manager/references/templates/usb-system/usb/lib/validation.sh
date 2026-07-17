#!/usr/bin/env bash
# Validation utilities: health checks and self‑heal helpers

if [[ -n "${UCA_VALIDATION_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_VALIDATION_SH_SOURCED=1

# shellcheck source=lib/core.sh
[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"
# shellcheck source=lib/config.sh
[[ -n "${UCA_CONFIG_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/config.sh"
# shellcheck source=lib/usb.sh
[[ -n "${UCA_USB_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/usb.sh"
# shellcheck source=lib/menu.sh
[[ -n "${UCA_MENU_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/menu.sh"

# Triple validation pattern:
# 1. Perform check
# 2. Verify result against expected criteria
# 3. Log and optionally self‑heal

validate_host_id() {
  if ! command -v jq >/dev/null 2>&1; then
    print_error "jq required for validation"
    return 1
  fi
  config_init
  local host_entry
  host_entry=$(config_get '.host_id.host_id' 2>/dev/null)
  if [[ -z "$host_entry" || "$host_entry" == "null" ]]; then
    print_warning "Host ID missing; generating..."
    generate_host_id || return 1
  else
    if [[ "$host_entry" != usb-compute-* ]]; then
      print_warning "Host ID malformed ($host_entry); regenerating..."
      generate_host_id || return 1
    fi
  fi
  print_success "Host ID validation passed"
  return 0
}

validate_usb_mount() {
  # Ensure any attached Ventoy USB is mounted at expected mount point
  if [[ -z "${SELECTED_DEVICE:-}" ]]; then
    print_error "SELECTED_DEVICE not set; cannot validate USB mount"
    return 1
  fi
  if ! detect_ventoy_mount; then
    print_error "Ventoy device not detected or not mounted"
    return 1
  fi
  if [[ -z "$VENTOY_MOUNT" || ! -d "$VENTOY_MOUNT" ]]; then
    print_error "Mount point invalid for $SELECTED_DEVICE"
    return 1
  fi
  print_success "USB mount validation passed: $SELECTED_DEVICE -> $VENTOY_MOUNT"
  return 0
}

validate_menu_stack() {
  # Ensure menu stack is not corrupted (no empty entries)
  if (( ${#UCA_MENU_STACK[@]} == 0 )); then
    print_warning "Menu stack empty; resetting"
    menu_clear
  else
    for entry in "${UCA_MENU_STACK[@]}"; do
      if [[ -z "$entry" ]]; then
        print_warning "Empty menu entry found; resetting stack"
        menu_clear
        break
      fi
    done
  fi
  print_success "Menu stack validation passed"
  return 0
}

# Self‑heal wrapper: runs a validation and optional fix function
# Usage: self_heal <validation_fn> <heal_fn>
self_heal() {
  local validator="$1"; shift
  local healer="$1"; shift
  if "$validator"; then
    return 0
  else
    if [[ -n "$healer" ]]; then
      print_info "Attempting self‑heal via $healer"
      "$healer" && "$validator"
    fi
    return 1
  fi
}

# Example composite check that runs all three with triple validation
run_full_validation() {
  validate_host_id && validate_usb_mount && validate_menu_stack
}