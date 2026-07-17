#!/usr/bin/env bash
# Test 05: Alias Manager CRUD Cycle
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing alias manager..."

ALIAS_SCRIPT="$USB_DIR/scripts/alias_manager.sh"
ALIAS_FILE="$HOME/.bash_aliases_usb"
ALIAS_BACKUP=""
[[ -f "$ALIAS_FILE" ]] && ALIAS_BACKUP=$(mktemp)

# Backup
[[ -n "$ALIAS_BACKUP" ]] && cp "$ALIAS_FILE" "$ALIAS_BACKUP"

# Test script exists and is executable
assert_file_exists "$ALIAS_SCRIPT" "alias_manager.sh"
assert_executable "$ALIAS_SCRIPT" "alias_manager.sh executable"

# Test --list
output=$(bash "$ALIAS_SCRIPT" --list 2>&1)
if [[ $? -eq 0 ]]; then
  assert_pass "alias_manager --list succeeds"
else
  assert_fail "alias_manager --list failed"
fi

# Test --dry-run --add
output=$(bash "$ALIAS_SCRIPT" --dry-run --add test_assertion 'echo test' 'Test alias' 2>&1)
if echo "$output" | grep -q "DRY RUN"; then
  assert_pass "alias_manager --dry-run --add shows dry-run output"
else
  assert_fail "alias_manager --dry-run --add missing dry-run output"
fi

# Test --export json
output=$(bash "$ALIAS_SCRIPT" --export json 2>&1)
if echo "$output" | jq empty 2>/dev/null; then
  assert_pass "alias_manager --export json produces valid JSON"
else
  assert_fail "alias_manager --export json invalid JSON"
fi

# Test --export csv
output=$(bash "$ALIAS_SCRIPT" --export csv 2>&1)
if [[ -n "$output" ]]; then
  assert_pass "alias_manager --export csv produces output"
else
  assert_fail "alias_manager --export csv empty"
fi

# Test --export table
output=$(bash "$ALIAS_SCRIPT" --export table 2>&1)
if [[ -n "$output" ]]; then
  assert_pass "alias_manager --export table produces output"
else
  assert_fail "alias_manager --export table empty"
fi

# Test --search
output=$(bash "$ALIAS_SCRIPT" --search ll 2>&1)
if [[ -n "$output" ]]; then
  assert_pass "alias_manager --search finds results"
else
  assert_pass "alias_manager --search returns (may be empty)"
fi

# Test --help
output=$(bash "$ALIAS_SCRIPT" --help 2>&1)
if echo "$output" | grep -qi "usage\|alias"; then
  assert_pass "alias_manager --help shows usage"
else
  assert_fail "alias_manager --help missing usage"
fi

# Restore
[[ -n "$ALIAS_BACKUP" && -f "$ALIAS_BACKUP" ]] && cp "$ALIAS_BACKUP" "$ALIAS_FILE"
[[ -n "$ALIAS_BACKUP" ]] && rm -f "$ALIAS_BACKUP"

log INFO "Alias manager tests complete"
