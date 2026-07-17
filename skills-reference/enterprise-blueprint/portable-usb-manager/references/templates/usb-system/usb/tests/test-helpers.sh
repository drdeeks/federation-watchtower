#!/usr/bin/env bash
# ============================================================================
# Test Helpers — Assertion functions and utilities for the test suite
# ============================================================================
# This file defines ONLY test helper functions. It does NOT source lib/ modules.
# Individual test scripts source lib/ as needed via source_libs().
# ============================================================================

if [[ -n "${TEST_HELPERS_LOADED:-}" ]]; then
  return 0
fi
TEST_HELPERS_LOADED=1

# ── Resolve Paths ───────────────────────────────────────────────────────────
# Determine paths relative to the known project structure.
# tests/ is inside usb/, so tests/.. = usb/, tests/../.. = project root.
if [[ -n "${USB_DIR:-}" && -d "${USB_DIR}/lib" ]]; then
  # USB_DIR already set and valid (from run-all.sh or parent)
  _TEST_DIR="${USB_DIR}/tests"
  _PROJECT_DIR="${USB_DIR}/.."
else
  # Resolve from this file's location
  _SELF="${BASH_SOURCE[0]}"
  if [[ -L "$_SELF" ]]; then
    _SELF="$(readlink -f "$_SELF" 2>/dev/null || echo "$_SELF")"
  fi
  _TEST_DIR="$(cd "$(dirname "$_SELF")" && pwd)"
  _USB_DIR="$(cd "$_TEST_DIR/.." && pwd)"
  _PROJECT_DIR="$(cd "$_TEST_DIR/../.." && pwd)"
fi

# ── Re-export test counters if not set ──────────────────────────────────────
: "${TESTS_RUN:=0}"
: "${TESTS_PASSED:=0}"
: "${TESTS_FAILED:=0}"
: "${TESTS_SKIPPED:=0}"
: "${DRY_RUN:=false}"
: "${VERBOSE:=false}"
: "${USB_DIR:=$_USB_DIR}"
: "${PROJECT_DIR:=$_PROJECT_DIR}"

# ── Colors (standalone, no lib dependency) ──────────────────────────────────
_T_RED='\033[0;31m'
_T_GREEN='\033[0;32m'
_T_YELLOW='\033[1;33m'
_T_CYAN='\033[0;36m'
_T_BOLD='\033[1m'
_T_NC='\033[0m'

# ── Logging (standalone, no lib dependency) ─────────────────────────────────
log() {
  local level="$1"; shift
  local color="$_T_NC"
  case "$level" in
    PASS) color="$_T_GREEN" ;;
    FAIL) color="$_T_RED" ;;
    SKIP) color="$_T_YELLOW" ;;
    INFO) color="$_T_CYAN" ;;
  esac
  printf "${color}[%s]${_T_NC} %s\n" "$level" "$*" >&2
}

# ── Source Project Libraries ────────────────────────────────────────────────
# Each test script calls this to load lib/ modules.
# Only re-sources if guards are not set (avoids redundant loads).
source_libs() {
  source "$USB_DIR/lib/logging.sh" 2>/dev/null
  source "$USB_DIR/lib/core.sh" 2>/dev/null
  source "$USB_DIR/lib/platform.sh" 2>/dev/null
  source "$USB_DIR/lib/config.sh" 2>/dev/null
  source "$USB_DIR/lib/menu.sh" 2>/dev/null
  source "$USB_DIR/lib/validation.sh" 2>/dev/null
}

# ── Assertion Functions ─────────────────────────────────────────────────────
assert_pass() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  log PASS "$1"
}

assert_fail() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  log FAIL "$1"
  [[ -n "${2:-}" ]] && log FAIL "  Detail: $2"
}

assert_skip() {
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
  log SKIP "$1 — ${2:-skipped}"
}

assert_file_exists() {
  local file="$1"
  local desc="${2:-$file}"
  if [[ -f "$file" ]]; then
    assert_pass "$desc exists"
  else
    assert_fail "$desc missing" "Expected: $file"
  fi
}

assert_dir_exists() {
  local dir="$1"
  local desc="${2:-$dir}"
  if [[ -d "$dir" ]]; then
    assert_pass "$desc exists"
  else
    assert_fail "$desc missing" "Expected: $dir"
  fi
}

assert_executable() {
  local file="$1"
  local desc="${2:-$file}"
  if [[ -x "$file" ]]; then
    assert_pass "$desc is executable"
  else
    assert_fail "$desc not executable" "chmod +x $file"
  fi
}

assert_syntax() {
  local file="$1"
  local desc="${2:-$(basename "$file")}"
  if bash -n "$file" 2>/dev/null; then
    assert_pass "$desc syntax OK"
  else
    assert_fail "$desc syntax error" "bash -n $file"
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local desc="${3:-$file contains $pattern}"
  if grep -q "$pattern" "$file" 2>/dev/null; then
    assert_pass "$desc"
  else
    assert_fail "$desc" "Pattern not found: $pattern"
  fi
}

assert_json_valid() {
  local file="$1"
  local desc="${2:-$file is valid JSON}"
  if jq empty "$file" 2>/dev/null; then
    assert_pass "$desc"
  else
    assert_fail "$desc" "jq parse error"
  fi
}

assert_command() {
  local cmd="$1"
  local desc="${2:-$cmd runs}"
  local output
  if output=$(eval "$cmd" 2>&1); then
    assert_pass "$desc"
    [[ "${VERBOSE:-false}" == "true" ]] && log INFO "  Output: ${output:0:200}"
  else
    assert_fail "$desc" "Exit code: $?"
  fi
}

assert_dry_run() {
  local cmd="$1"
  local desc="${2:-$cmd dry-run}"
  local output
  if DRY_RUN=true output=$(eval "$cmd" 2>&1); then
    assert_pass "$desc"
  else
    assert_fail "$desc" "Dry-run failed"
  fi
}

# ── Utility Functions ───────────────────────────────────────────────────────
tmpfile() {
  mktemp /tmp/usb-hemlock-test-XXXXXX
}

tmpdir() {
  mktemp -d /tmp/usb-hemlock-test-XXXXXX
}

cleanup_tmp() {
  rm -rf /tmp/usb-hemlock-test-* 2>/dev/null || true
}
