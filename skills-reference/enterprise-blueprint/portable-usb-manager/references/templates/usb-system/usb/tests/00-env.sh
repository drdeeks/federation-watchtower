#!/usr/bin/env bash
# Test 00: Environment Prerequisites
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing environment prerequisites..."

# Bash version
if [[ "${BASH_VERSINFO[0]}" -ge 4 ]]; then
  assert_pass "Bash ${BASH_VERSION} >= 4.0"
else
  assert_fail "Bash version too old" "${BASH_VERSION}"
fi

# jq
if command -v jq >/dev/null 2>&1; then
  jq_ver=$(jq --version 2>&1)
  assert_pass "jq available ($jq_ver)"
else
  assert_fail "jq not found" "apt install jq"
fi

# Docker
if command -v docker >/dev/null 2>&1; then
  assert_pass "Docker available ($(docker --version 2>&1 | head -1))"
else
  assert_skip "Docker not found" "Optional for runtime tests"
fi

# Docker Compose
if docker compose version >/dev/null 2>&1; then
  assert_pass "Docker Compose available"
else
  assert_skip "Docker Compose not found" "Optional for runtime tests"
fi

# Python3
if command -v python3 >/dev/null 2>&1; then
  assert_pass "Python3 available ($(python3 --version 2>&1))"
else
  assert_skip "Python3 not found" "Optional"
fi

# File count
usb_count=$(find "$USB_DIR" -type f | wc -l)
if [[ "$usb_count" -ge 35 ]]; then
  assert_pass "usb/ has $usb_count files (>= 35)"
else
  assert_fail "usb/ has only $usb_count files" "Expected >= 35"
fi

# Hemlock directory
if [[ -d "$PROJECT_DIR/hemlock/hemlock-runtime" ]]; then
  assert_pass "hemlock-runtime/ exists"
else
  assert_fail "hemlock-runtime/ missing"
fi

# Hemlock skills
if [[ -d "$PROJECT_DIR/hemlock/hemlock-minimal/skills" ]]; then
  skill_count=$(find "$PROJECT_DIR/hemlock/hemlock-minimal/skills" -mindepth 1 -maxdepth 1 -type d | wc -l)
  assert_pass "hemlock-minimal/skills/ exists ($skill_count skills)"
else
  assert_fail "hemlock-minimal/skills/ missing"
fi

log INFO "Environment tests complete"
