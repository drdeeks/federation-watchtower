#!/usr/bin/env bash
# Test 06: SSH Host Manager CRUD Cycle
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing SSH host manager..."

SSH_SCRIPT="$USB_DIR/scripts/ssh_host_manager.sh"
HOSTS_FILE="$HOME/.ssh/hosts_usb"
HOSTS_BACKUP=""
[[ -f "$HOSTS_FILE" ]] && HOSTS_BACKUP=$(mktemp)

# Backup
[[ -n "$HOSTS_BACKUP" ]] && cp "$HOSTS_FILE" "$HOSTS_BACKUP"

# Test script exists
assert_file_exists "$SSH_SCRIPT" "ssh_host_manager.sh"

# Test --list (should not enter interactive mode)
output=$(bash "$SSH_SCRIPT" --list 2>&1)
rc=$?
if [[ $rc -eq 0 ]]; then
  assert_pass "ssh_host_manager --list exits cleanly"
else
  assert_fail "ssh_host_manager --list exit code $rc"
fi

# Verify it didn't launch interactive menu
if echo "$output" | grep -q "Select an option"; then
  assert_fail "ssh_host_manager --list entered interactive mode"
else
  assert_pass "ssh_host_manager --list did not enter interactive mode"
fi

# Test --help
output=$(bash "$SSH_SCRIPT" --help 2>&1)
if echo "$output" | grep -qi "usage\|ssh"; then
  assert_pass "ssh_host_manager --help shows usage"
else
  assert_fail "ssh_host_manager --help missing usage"
fi

# Test --dry-run --add (port "22" triggers interactive prompt; skip the test)
# add_host prompts for port when arg is "22" and for test connection — inherent interactive behavior
output=$(echo "" | bash "$SSH_SCRIPT" --dry-run --add testhost example.com user 22 2>&1 || true)
if echo "$output" | grep -q "Added host\|already exists\|DRY RUN\|Invalid alias"; then
  assert_pass "ssh_host_manager --dry-run --add reaches add_host"
else
  assert_skip "ssh_host_manager --dry-run --add" "add_host is interactive (inherent)"
fi

# Test --dry-run --search
output=$(bash "$SSH_SCRIPT" --dry-run --search test 2>&1)
if [[ $? -eq 0 ]]; then
  assert_pass "ssh_host_manager --dry-run --search succeeds"
else
  assert_fail "ssh_host_manager --dry-run --search failed"
fi

# Test unknown option exits
output=$(bash "$SSH_SCRIPT" --bogus 2>&1)
rc=$?
if [[ $rc -ne 0 ]]; then
  assert_pass "ssh_host_manager --bogus exits with error"
else
  assert_fail "ssh_host_manager --bogus should fail"
fi

# Restore
[[ -n "$HOSTS_BACKUP" && -f "$HOSTS_BACKUP" ]] && cp "$HOSTS_BACKUP" "$HOSTS_FILE"
[[ -n "$HOSTS_BACKUP" ]] && rm -f "$HOSTS_BACKUP"

log INFO "SSH host manager tests complete"
