#!/usr/bin/env bash
# Core utilities: colors, logging, confirmations, dry-run, safe exec, traps

# Guard against double sourcing
if [[ -n "${UCA_CORE_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_CORE_SH_SOURCED=1

# Colors (only declare if not already set to avoid overriding caller)
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${CYAN:=\033[0;36m}"
: "${BOLD:=\033[1m}"
: "${NC:=\033[0m}"

# Default dry-run flag (honor caller if already set)
: "${DRY_RUN:=false}"

# Default log file (caller may override)
: "${LOG_FILE:=}"

uca_log() {
  # Usage: uca_log LEVEL MESSAGE...
  local level="$1"; shift
  local ts; ts=$(date +'%Y-%m-%d %H:%M:%S')
  local line="[$ts] [$level] $*"
  if [[ -n "$LOG_FILE" ]]; then
    printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
  fi
  printf '%s\n' "$line"
}

print_header()  { printf "\n${CYAN}${BOLD}=== %s ===${NC}\n\n" "$1"; }
print_success() { printf "${GREEN}✓${NC} %s\n" "$1"; uca_log SUCCESS "$1" >/dev/null 2>&1 || true; }
print_error()   { printf "${RED}✗${NC} %s\n" "$1"; uca_log ERROR   "$1" >/dev/null 2>&1 || true; }
print_warning() { printf "${YELLOW}⚠${NC} %s\n" "$1"; uca_log WARNING "$1" >/dev/null 2>&1 || true; }
print_info()    { printf "${BLUE}ℹ${NC} %s\n" "$1"; uca_log INFO    "$1" >/dev/null 2>&1 || true; }

confirm() {
  # confirm "Prompt" [default:y|n]
  local prompt="$1"; local def="${2:-n}"; local suffix="[y/N]"; [[ "$def" == "y" ]] && suffix="[Y/n]"
  printf "${YELLOW}%s %s:${NC} " "$prompt" "$suffix"
  local ans; read -r ans
  ans="${ans:-$def}"
  [[ "$ans" =~ ^[Yy]$ ]]
}

run_or_dry() {
  # run_or_dry cmd...  (uses DRY_RUN)
  if [[ "$DRY_RUN" == "true" ]]; then
    print_info "[DRY RUN] Would execute: $*"
    return 0
  fi
  "$@"
}

safe_exec() {
  # Usage: safe_exec "Description" timeout_secs cmd [args...]
  local desc="$1"; shift
  local timeout_secs="$1"; shift
  local rc=0 out=""
  if command -v timeout >/dev/null 2>&1; then
    out=$(timeout "$timeout_secs" "$@" 2>&1) || rc=$?
  else
    out=$("$@" 2>&1) || rc=$?
  fi
  if [[ $rc -ne 0 ]]; then
    print_error "$desc failed (exit $rc)"
    [[ -n "$out" ]] && print_error "Output: $out"
    return $rc
  fi
  return 0
}

set_standard_traps() {
  # Installs standard traps that avoid hard exits; caller can override
  trap 'print_warning "Interrupted"; return 130 2>/dev/null || exit 130' INT
  trap 'print_warning "Terminated"; return 143 2>/dev/null || exit 143' TERM
}

# CL-030: Resolve where component installs (aliases / bash profile / AV / clean
# state) should land for the current run. Honors UCA_MODE = usb | host.
#
#   usb  → on the mounted USB persistence, under <persistence>/etc/uca/
#          (so configs ride with the USB and never touch host $HOME)
#   host → under XDG_CONFIG_HOME (default $HOME/.config/usb-compute-automation/)
#
# Callers should use this rather than hardcoding $HOME — see CL-030 audit.
# Echoes the resolved absolute root on stdout. Returns 1 only when UCA_MODE=usb
# but no USB persistence is mountable (caller should fall back or fail).
_uca_install_root() {
  local mode="${UCA_MODE:-host}"
  case "$mode" in
    usb)
      local pfile=""
      # Preferred: caller (menu.sh) pre-resolved and exported the persistence
      # path so this helper works in spawned child scripts too.
      if [[ -n "${UCA_PERSISTENCE_PATH:-}" && -f "${UCA_PERSISTENCE_PATH}" ]]; then
        pfile="${UCA_PERSISTENCE_PATH}"
      elif command -v _uca_primary_persistence >/dev/null 2>&1; then
        pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
      fi
      if [[ -z "$pfile" ]]; then
        print_error "UCA_MODE=usb but no USB persistence resolvable (set UCA_PERSISTENCE_PATH or re-run menu)" >&2
        return 1
      fi
      # We don't write inside the .dat overlay directly from the host — instead
      # use a sibling config dir on the same Ventoy volume so the on-USB
      # live boot can mount and source it (../usb-hemlock/etc).
      local pmnt root
      pmnt=$(dirname "$(dirname "$pfile")")  # strip /persistence/<name>.dat
      root="${pmnt}/usb-hemlock/etc/uca"
      mkdir -p "$root" 2>/dev/null || true
      printf '%s\n' "$root"
      ;;
    host|*)
      local root="${XDG_CONFIG_HOME:-$HOME/.config}/usb-compute-automation"
      mkdir -p "$root" 2>/dev/null || true
      printf '%s\n' "$root"
      ;;
  esac
}

# CL-030: Where the user's shell rc should source our generated profile from.
# In USB mode this lives on the USB so it survives a re-image; in host mode it
# lives under XDG_CONFIG_HOME so we never alter ~/.bashrc more than once.
_uca_profile_source_line() {
  local root; root=$(_uca_install_root) || return 1
  printf 'source "%s/bash_profile.sh" 2>/dev/null || true\n' "$root"
}
