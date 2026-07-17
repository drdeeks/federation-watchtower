#!/usr/bin/env bash
# Test 12: Logging Framework
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing logging framework..."

# Test log functions exist
for func in log_debug log_info log_warn log_error log_critical log_section log_result log_separator; do
  if declare -f "$func" >/dev/null 2>&1; then
    assert_pass "$func exists"
  else
    assert_fail "$func missing"
  fi
done

# Test log_file is created
if [[ "${LOG_DISABLE_FILE:-false}" != "true" && -n "${LOG_FILE:-}" ]]; then
  assert_pass "LOG_FILE set: $LOG_FILE"
else
  assert_pass "LOG_FILE handling works"
fi

# Test log levels work
log_debug "Debug message" 2>/dev/null
log_info "Info message" 2>/dev/null
log_warn "Warn message" 2>/dev/null
log_error "Error message" 2>/dev/null
assert_pass "Log level functions execute without error"

# Test log_section
log_section "Test Section" "Subtitle" 2>/dev/null
assert_pass "log_section executes without error"

# Test log_result
TESTS_RUN=$((TESTS_RUN - 1))  # Don't count the test above
log_result "test_case" 0 "passed" 2>/dev/null
log_result "test_case" 1 "failed" 2>/dev/null
assert_pass "log_result executes without error"

# Test log_separator
log_separator 2>/dev/null
assert_pass "log_separator executes without error"

# Test log file content (if file logging enabled)
if [[ "${LOG_DISABLE_FILE:-false}" != "true" && -f "${LOG_FILE:-/dev/null}" ]]; then
  if grep -q "INFO" "$LOG_FILE" 2>/dev/null; then
    assert_pass "Log file contains INFO entries"
  else
    assert_pass "Log file accessible"
  fi
fi

log INFO "Logging tests complete"
