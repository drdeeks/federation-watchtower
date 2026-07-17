#!/usr/bin/env bash
# Test 03: Library Module Loading
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing library module loading..."

# Test each module loads without error
modules=("core.sh" "platform.sh" "usb.sh" "config.sh" "menu.sh" "validation.sh" "logging.sh")
for mod in "${modules[@]}"; do
  local_file="$USB_DIR/lib/$mod"
  if [[ -f "$local_file" ]]; then
    # Reset guards to allow re-sourcing
    case "$mod" in
      core.sh)      UCA_CORE_SH_SOURCED="" ;;
      platform.sh)  UCA_PLATFORM_SH_SOURCED="" ;;
      usb.sh)       UCA_USB_SH_SOURCED="" ;;
      config.sh)    UCA_CONFIG_SH_SOURCED="" ;;
      menu.sh)      UCA_MENU_SH_SOURCED="" ;;
      validation.sh) UCA_VALIDATION_SH_SOURCED="" ;;
      logging.sh)   UCA_LOGGING_SH_SOURCED="" ;;
    esac
    if source "$local_file" 2>/dev/null; then
      assert_pass "$mod loads successfully"
    else
      assert_fail "$mod failed to load"
    fi
  else
    assert_skip "$mod not found"
  fi
done

# Test core.sh exports expected functions
source "$USB_DIR/lib/core.sh" 2>/dev/null
for func in print_header print_success print_error print_warning print_info confirm run_or_dry safe_exec set_standard_traps uca_log; do
  if declare -f "$func" >/dev/null 2>&1; then
    assert_pass "core.sh exports $func"
  else
    assert_fail "core.sh missing $func"
  fi
done

# Test platform.sh exports
source "$USB_DIR/lib/platform.sh" 2>/dev/null
for func in detect_os detect_virtualization select_best_tool; do
  if declare -f "$func" >/dev/null 2>&1; then
    assert_pass "platform.sh exports $func"
  else
    assert_fail "platform.sh missing $func"
  fi
done

# Test config.sh exports
source "$USB_DIR/lib/config.sh" 2>/dev/null
for func in config_init config_get config_set generate_host_id; do
  if declare -f "$func" >/dev/null 2>&1; then
    assert_pass "config.sh exports $func"
  else
    assert_fail "config.sh missing $func"
  fi
done

# Test validation.sh exports
source "$USB_DIR/lib/validation.sh" 2>/dev/null
for func in validate_host_id validate_usb_mount validate_menu_stack self_heal run_full_validation; do
  if declare -f "$func" >/dev/null 2>&1; then
    assert_pass "validation.sh exports $func"
  else
    assert_fail "validation.sh missing $func"
  fi
done

# Test logging.sh exports
source "$USB_DIR/lib/logging.sh" 2>/dev/null
for func in log_debug log_info log_warn log_error log_critical log_section log_result log_separator; do
  if declare -f "$func" >/dev/null 2>&1; then
    assert_pass "logging.sh exports $func"
  else
    assert_fail "logging.sh missing $func"
  fi
done

log INFO "Library tests complete"
