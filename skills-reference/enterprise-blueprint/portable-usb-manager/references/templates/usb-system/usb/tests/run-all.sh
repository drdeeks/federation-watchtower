#!/usr/bin/env bash
# ============================================================================
# Test Runner — USB-Hemlock Unified Compute Platform
# ============================================================================
# Runs all test suites with structured output and logging.
#
# Usage:
#   bash tests/run-all.sh                    # Run all tests
#   bash tests/run-all.sh --syntax           # Syntax checks only
#   bash tests/run-all.sh --runtime          # Runtime behavior only
#   bash tests/run-all.sh --integration      # Integration tests only
#   bash tests/run-all.sh --dry-run          # Dry-run tests (no mutations)
#   bash tests/run-all.sh --verbose          # Verbose output
#   bash tests/run-all.sh --help             # Show help
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
USB_DIR="$PROJECT_DIR/usb"

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Test Counters (exported so child test scripts can increment them) ───────
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0
export TESTS_RUN TESTS_PASSED TESTS_FAILED TESTS_SKIPPED

TEST_LOG="/tmp/usb-hemlock-tests-$$.$(date +%Y%m%d).log"
export TEST_LOG USB_DIR PROJECT_DIR

# ── Options ─────────────────────────────────────────────────────────────────
RUN_SYNTAX=false
RUN_RUNTIME=false
RUN_INTEGRATION=false
export DRY_RUN=false
VERBOSE=false
export VERBOSE

while [[ $# -gt 0 ]]; do
  case "$1" in
    --syntax)      RUN_SYNTAX=true; shift ;;
    --runtime)     RUN_RUNTIME=true; shift ;;
    --integration) RUN_INTEGRATION=true; shift ;;
    --dry-run)     DRY_RUN=true; export DRY_RUN; shift ;;
    --verbose|-v)  VERBOSE=true; export VERBOSE; shift ;;
    --help|-h)
      cat << 'EOF'
Test Runner — USB-Hemlock Unified Compute Platform

Usage: tests/run-all.sh [OPTIONS]

Options:
  (no args)     Run all tests
  --syntax      Syntax checks only (01-syntax, 02-permissions, 03-lib-modules)
  --runtime     Runtime behavior only (04-config through 09-validation, 10-hemlock, 12-logging)
  --integration Integration tests only (00-env, 11-menu, 13-deploy)
  --dry-run     Dry-run tests (no mutations)
  --verbose     Verbose output
  --help        Show this help

Test files:
EOF
      ls -1 "$SCRIPT_DIR"/[0-9]*.sh 2>/dev/null | xargs -I{} basename {} || true
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 2 ;;
  esac
done

if [[ "$RUN_SYNTAX" == "false" && "$RUN_RUNTIME" == "false" && "$RUN_INTEGRATION" == "false" ]]; then
  RUN_SYNTAX=true
  RUN_RUNTIME=true
  RUN_INTEGRATION=true
fi

# ── Summary ─────────────────────────────────────────────────────────────────
print_summary() {
  echo ""
  printf "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}\n" >&2
  printf "${CYAN}${BOLD}  TEST SUMMARY${NC}\n" >&2
  printf "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}\n" >&2
  printf "  Total:   %d\n" "$TESTS_RUN" >&2
  printf "${GREEN}  Passed:  %d${NC}\n" "$TESTS_PASSED" >&2
  if [[ $TESTS_FAILED -gt 0 ]]; then
    printf "${RED}  Failed:  %d${NC}\n" "$TESTS_FAILED" >&2
  else
    printf "  Failed:  0\n" >&2
  fi
  if [[ $TESTS_SKIPPED -gt 0 ]]; then
    printf "${YELLOW}  Skipped: %d${NC}\n" "$TESTS_SKIPPED" >&2
  fi
  printf "  Log:     %s\n" "$TEST_LOG" >&2
  printf "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}\n" >&2
}

# ── Run Test Files ──────────────────────────────────────────────────────────
run_test_files() {
  local category="$1"
  local pattern="$2"

  printf "\n${CYAN}${BOLD}── %s Tests ──${NC}\n" "$category" >&2

  local test_files
  test_files=$(find "$SCRIPT_DIR" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort)

  if [[ -z "$test_files" ]]; then
    printf "  No test files matching: %s\n" "$pattern" >&2
    return 0
  fi

  for test_file in $test_files; do
    local test_name
    test_name=$(basename "$test_file" .sh)
    printf "\n${BOLD}── %s ──${NC}\n" "$test_name" >&2

    # Run each test in a subshell so test counters are captured
    (
      source "$SCRIPT_DIR/test-helpers.sh"
      source_libs 2>/dev/null || true
      source "$test_file" 2>/dev/null
    )
    # Note: test counters in subshell don't propagate to parent.
    # The test file's output (PASS/FAIL) goes to stderr and the log.
  done
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  echo ""
  printf "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}\n" >&2
  printf "${CYAN}${BOLD}  USB-Hemlock Test Suite${NC}\n" >&2
  printf "${CYAN}${BOLD}  %s${NC}\n" "$(date)" >&2
  printf "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}\n" >&2

  # Run each test script directly (not in subshell) so counters propagate
  local all_test_files=""

  if [[ "$RUN_SYNTAX" == "true" ]]; then
    all_test_files+=" $(find "$SCRIPT_DIR" -maxdepth 1 \( -name '01-*.sh' -o -name '02-*.sh' -o -name '03-*.sh' \) -type f 2>/dev/null | sort)"
  fi
  if [[ "$RUN_RUNTIME" == "true" ]]; then
    all_test_files+=" $(find "$SCRIPT_DIR" -maxdepth 1 \( -name '04-*.sh' -o -name '05-*.sh' -o -name '06-*.sh' -o -name '07-*.sh' -o -name '08-*.sh' -o -name '09-*.sh' -o -name '10-*.sh' -o -name '12-*.sh' \) -type f 2>/dev/null | sort)"
  fi
  if [[ "$RUN_INTEGRATION" == "true" ]]; then
    all_test_files+=" $(find "$SCRIPT_DIR" -maxdepth 1 \( -name '00-*.sh' -o -name '11-*.sh' -o -name '13-*.sh' \) -type f 2>/dev/null | sort)"
  fi

  for test_file in $all_test_files; do
    local test_name
    test_name=$(basename "$test_file" .sh)
    printf "\n${BOLD}── %s ──${NC}\n" "$test_name" >&2

    # Source helpers
    source "$SCRIPT_DIR/test-helpers.sh"

    # Source the test file — its top-level code runs immediately
    # shellcheck source=/dev/null
    source "$test_file" || {
      TESTS_FAILED=$((TESTS_FAILED + 1))
      printf "${RED}[FAIL]${NC} %s exited with error\n" "$test_name" >&2
    }
  done

  print_summary

  if [[ $TESTS_FAILED -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
