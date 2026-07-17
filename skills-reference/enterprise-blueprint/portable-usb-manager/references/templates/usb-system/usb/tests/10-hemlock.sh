#!/usr/bin/env bash
# Test 10: Hemlock Runtime Detection
source "$(dirname "${BASH_SOURCE[0]}")/test-helpers.sh"
source_libs

log INFO "Testing hemlock runtime detection..."

HEMLOCK_RT="$PROJECT_DIR/hemlock/hemlock-runtime"

# Test hemlock-runtime directory exists
assert_dir_exists "$HEMLOCK_RT" "hemlock-runtime/"

# Test key scripts exist
for script in scripts/hemlock scripts/runtime.sh; do
  assert_file_exists "$HEMLOCK_RT/$script" "hemlock-runtime/$script"
done

# Test Docker compose files exist
for compose in docker-compose.runtime.yml docker-compose.yml; do
  assert_file_exists "$HEMLOCK_RT/$compose" "hemlock-runtime/$compose"
done

# Test Dockerfiles exist
for df in Dockerfile.runtime; do
  assert_file_exists "$HEMLOCK_RT/$df" "hemlock-runtime/$df"
done

# Test Makefile exists
assert_file_exists "$HEMLOCK_RT/Makefile" "hemlock-runtime/Makefile"

# Test hemlock CLI is syntax-correct
assert_syntax "$HEMLOCK_RT/scripts/hemlock" "scripts/hemlock"
assert_syntax "$HEMLOCK_RT/scripts/runtime.sh" "scripts/runtime.sh"

# Test hemlock-tui wrapper exists
assert_file_exists "$USB_DIR/hemlock-tui" "usb/hemlock-tui"
assert_file_exists "$PROJECT_DIR/hemlock/hemlock-tui" "hemlock/hemlock-tui"

# Test hemlock-tui has auto-detection
if grep -q "HEMLOCK_DIR" "$USB_DIR/hemlock-tui" 2>/dev/null; then
  assert_pass "hemlock-tui references HEMLOCK_DIR"
else
  assert_fail "hemlock-tui missing HEMLOCK_DIR logic"
fi

# Test skills directory
SKILLS_DIR="$PROJECT_DIR/hemlock/hemlock-minimal/skills"
if [[ -d "$SKILLS_DIR" ]]; then
  skill_count=$(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d | wc -l)
  assert_pass "skills/ exists with $skill_count bundles"
else
  assert_fail "skills/ missing"
fi

# Test master menu references hemlock
if grep -q "hemlock" "$PROJECT_DIR/menu.sh" 2>/dev/null; then
  assert_pass "master menu includes hemlock"
else
  assert_fail "master menu missing hemlock"
fi

log INFO "Hemlock detection tests complete"
