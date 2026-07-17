#!/usr/bin/env bash
# ============================================================================
# Logging Framework — USB-Hemlock Unified Compute Platform
# ============================================================================
# Structured logging with file output, log levels, rotation, and context.
# Sources: core.sh (for colors)
#
# Usage:
#   source lib/logging.sh
#   log_info "Starting process"
#   log_warn "Low disk space"
#   log_error "Connection failed" --context "host=example.com"
#   log_debug "Variable x=$x"
#   log_section "Phase 1" "USB Foundation"
#   log_result "test_name" 0 "passed"
#
# Environment:
#   LOG_FILE          — Path to log file (default: /tmp/usb-hemlock-<pid>.log)
#   LOG_LEVEL         — Minimum level: DEBUG < INFO < WARN < ERROR < CRITICAL (default: INFO)
#   LOG_MAX_SIZE      — Max log file size in bytes before rotation (default: 10485760 = 10MB)
#   LOG_DISABLE_FILE  — Set to "true" to disable file logging
#   LOG_DISABLE_COLOR — Set to "true" to disable color output
# ============================================================================

if [[ -n "${UCA_LOGGING_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_LOGGING_SH_SOURCED=1

# shellcheck source=lib/core.sh
[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"

# ── Log Levels ──────────────────────────────────────────────────────────────
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3
LOG_LEVEL_CRITICAL=4

# Map string level to numeric
declare -A _LOG_LEVEL_MAP=(
  [debug]=0 [DEBUG]=0
  [info]=1 [INFO]=1
  [warn]=2 [WARN]=2
  [warning]=2 [WARNING]=2
  [error]=3 [ERROR]=3
  [critical]=4 [CRITICAL]=4
)

: "${LOG_LEVEL:=INFO}"
: "${LOG_MAX_SIZE:=10485760}"
: "${LOG_DISABLE_FILE:=false}"
: "${LOG_DISABLE_COLOR:=false}"

# Determine numeric threshold
_LOG_THRESHOLD="${_LOG_LEVEL_MAP[${LOG_LEVEL^^}]:-1}"

# ── Color Definitions ───────────────────────────────────────────────────────
if [[ "$LOG_DISABLE_COLOR" != "true" ]]; then
  _LOG_CLR_DEBUG="\033[0;36m"
  _LOG_CLR_INFO="\033[0;32m"
  _LOG_CLR_WARN="\033[1;33m"
  _LOG_CLR_ERROR="\033[0;31m"
  _LOG_CLR_CRITICAL="\033[1;31m"
  _LOG_CLR_RESET="\033[0m"
  _LOG_CLR_BOLD="\033[1m"
  _LOG_CLR_DIM="\033[2m"
else
  _LOG_CLR_DEBUG=""
  _LOG_CLR_INFO=""
  _LOG_CLR_WARN=""
  _LOG_CLR_ERROR=""
  _LOG_CLR_CRITICAL=""
  _LOG_CLR_RESET=""
  _LOG_CLR_BOLD=""
  _LOG_CLR_DIM=""
fi

# ── Log File Setup ──────────────────────────────────────────────────────────
_init_log_file() {
  if [[ "$LOG_DISABLE_FILE" == "true" ]]; then
    return 0
  fi
  if [[ -z "${LOG_FILE:-}" ]]; then
    LOG_FILE="/tmp/usb-hemlock-$$.$(date +%Y%m%d).log"
  fi
  local log_dir
  log_dir=$(dirname "$LOG_FILE")
  if [[ ! -d "$log_dir" ]]; then
    mkdir -p "$log_dir" 2>/dev/null || return 0
  fi
  touch "$LOG_FILE" 2>/dev/null || return 0
}

# ── Log Rotation ────────────────────────────────────────────────────────────
_rotate_log() {
  [[ "$LOG_DISABLE_FILE" == "true" ]] && return 0
  [[ -z "${LOG_FILE:-}" || ! -f "$LOG_FILE" ]] && return 0
  local size
  size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
  if (( size > LOG_MAX_SIZE )); then
    local rotated="${LOG_FILE}.$(date +%Y%m%d-%H%M%S).bak"
    mv "$LOG_FILE" "$rotated" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true
    # Keep only last 5 rotated logs
    local log_dir log_base
    log_dir=$(dirname "$LOG_FILE")
    log_base=$(basename "$LOG_FILE")
    ls -1t "${log_dir}/${log_base}".*.bak 2>/dev/null | tail -n +6 | xargs rm -f 2>/dev/null || true
  fi
}

# ── Core Log Function ───────────────────────────────────────────────────────
_log() {
  local level_name="$1"
  local level_num="$2"
  local color="$3"
  shift 3

  # Skip if below threshold
  (( level_num < _LOG_THRESHOLD )) && return 0

  local ts
  ts=$(date +'%Y-%m-%d %H:%M:%S')
  local msg="$*"

  # Strip ANSI for file output
  local plain_msg
  plain_msg=$(printf '%s' "$msg" | sed 's/\x1b\[[0-9;]*m//g')

  # Console output (with color)
  printf "${color}[%s] %-8s${_LOG_CLR_RESET} %s\n" "$ts" "[$level_name]" "$msg" >&2

  # File output (plain text)
  if [[ "$LOG_DISABLE_FILE" != "true" && -n "${LOG_FILE:-}" ]]; then
    _rotate_log
    printf '[%s] [%-8s] %s\n' "$ts" "$level_name" "$plain_msg" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

# ── Public Logging Functions ────────────────────────────────────────────────
log_debug()   { _log "DEBUG"   "$LOG_LEVEL_DEBUG"   "$_LOG_CLR_DEBUG"   "$@"; }
log_info()    { _log "INFO"    "$LOG_LEVEL_INFO"    "$_LOG_CLR_INFO"    "$@"; }
log_warn()    { _log "WARN"    "$LOG_LEVEL_WARN"    "$_LOG_CLR_WARN"    "$@"; }
log_error()   { _log "ERROR"   "$LOG_LEVEL_ERROR"   "$_LOG_CLR_ERROR"   "$@"; }
log_critical(){ _log "CRITICAL""$LOG_LEVEL_CRITICAL" "$_LOG_CLR_CRITICAL" "$@"; }

# ── Structured Logging ──────────────────────────────────────────────────────
log_section() {
  local title="${1:-Section}"
  local subtitle="${2:-}"
  local line="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  _log "INFO" "$LOG_LEVEL_INFO" "${_LOG_CLR_BOLD}${_LOG_CLR_CYAN:-}" "" >&2
  printf "${_LOG_CLR_BOLD}${_LOG_CLR_CYAN:-}${line}${_LOG_CLR_RESET}\n" >&2
  if [[ -n "$subtitle" ]]; then
    printf "${_LOG_CLR_BOLD}  %s — %s${_LOG_CLR_RESET}\n" "$title" "$subtitle" >&2
  else
    printf "${_LOG_CLR_BOLD}  %s${_LOG_CLR_RESET}\n" "$title" >&2
  fi
  printf "${_LOG_CLR_BOLD}${_LOG_CLR_CYAN:-}${line}${_LOG_CLR_RESET}\n" >&2
  if [[ "$LOG_DISABLE_FILE" != "true" && -n "${LOG_FILE:-}" ]]; then
    printf '\n%s\n  %s\n%s\n' "$line" "$title" "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
}

log_result() {
  local test_name="$1"
  local rc="$2"
  local detail="${3:-}"
  if [[ "$rc" -eq 0 ]]; then
    printf "${_LOG_CLR_GREEN:-}${_LOG_CLR_INFO}  ✓ PASS${_LOG_CLR_RESET}  %s" "$test_name" >&2
  else
    printf "${_LOG_CLR_RED:-}${_LOG_CLR_ERROR}  ✗ FAIL${_LOG_CLR_RESET}  %s" "$test_name" >&2
  fi
  [[ -n "$detail" ]] && printf " — %s" "$detail" >&2
  printf '\n' >&2
  if [[ "$LOG_DISABLE_FILE" != "true" && -n "${LOG_FILE:-}" ]]; then
    local status="PASS"; [[ "$rc" -ne 0 ]] && status="FAIL"
    printf '[%s] [TEST] %-6s %s' "$(date +'%Y-%m-%d %H:%M:%S')" "$status" "$test_name" >> "$LOG_FILE" 2>/dev/null || true
    [[ -n "$detail" ]] && printf ' — %s' "$detail" >> "$LOG_FILE" 2>/dev/null || true
    printf '\n' >> "$LOG_FILE" 2>/dev/null || true
  fi
}

log_separator() {
  local char="${1:-─}"
  local len="${2:-60}"
  local line=""
  for ((i=0; i<len; i++)); do line+="$char"; done
  printf '%s\n' "$line" >&2
}

# ── Initialization ──────────────────────────────────────────────────────────
_init_log_file
