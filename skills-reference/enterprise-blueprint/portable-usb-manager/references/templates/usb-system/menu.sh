#!/usr/bin/env bash
# ============================================================================
# Master Menu — USB-Hemlock Unified Compute Platform
# ============================================================================
# Singular interactive entry point for ALL components.
#
# Usage:
#   bash menu.sh                     # Interactive menu (default)
#   bash menu.sh --text              # Force text menu (no whiptail)
#   bash menu.sh --dry-run           # Dry-run mode (no mutations)
#   bash menu.sh --hemlock|-H        # Reveal the Hemlock Manager (opt-in)
#   bash menu.sh --log-file PATH     # Custom log file path
#   bash menu.sh --help              # Show help
#
# Environment:
#   DRY_RUN=true         Preview mutations without executing
#   HEMLOCK_ENABLED=true Same as --hemlock
#   LOG_FILE=path        Write logs to this file
#   LOG_LEVEL=DEBUG|INFO|WARN|ERROR  Minimum log level
#   HEMLOCK_DIR=path     Path to hemlock-runtime (auto-detected if unset)
#   SELECTED_DEVICE=dev  USB device (e.g. /dev/sdb)
#   UCA_ENVIRONMENT=...  usb-boot | usb-mounted | native (auto-detected,
#                        prompted on ambiguity, persisted to usb-paths.conf)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USB_DIR="$SCRIPT_DIR/usb"
HEMLOCK_DIR="${HEMLOCK_DIR:-}"
LOG_FILE="${LOG_FILE:-/tmp/usb-hemlock-menu-$$.$(date +%Y%m%d).log}"
DRY_RUN="${DRY_RUN:-false}"

# ── Source Libraries ────────────────────────────────────────────────────────
source "$USB_DIR/lib/logging.sh"
source "$USB_DIR/lib/core.sh"
source "$USB_DIR/lib/menu.sh"
source "$USB_DIR/lib/config.sh"
source "$USB_DIR/lib/validation.sh"
source "$USB_DIR/lib/usb.sh"
source "$USB_DIR/lib/platform.sh"

# ── Auto-detect HEMLOCK_DIR ────────────────────────────────────────────────
: "${DIM:=\033[2m}"
if [[ -z "$HEMLOCK_DIR" ]]; then
  for candidate in \
    "$SCRIPT_DIR/hemlock/hemlock-runtime" \
    "$SCRIPT_DIR/../hemlock/hemlock-runtime" \
    "$SCRIPT_DIR/hemlock-runtime" \
    "$SCRIPT_DIR/../hemlock-runtime" \
    "$SCRIPT_DIR/hemlock-complete-deployment/hemlock-runtime"; do
    if [[ -d "$candidate/scripts" && -f "$candidate/scripts/hemlock" ]]; then
      HEMLOCK_DIR="$candidate"
      break
    fi
  done
fi

# ── USB Auto-Detection ─────────────────────────────────────────────────────
# Scans for Ventoy USB devices at startup. If exactly one is found, it is
# selected automatically. If multiple are found, the user is prompted.
# If none are found, SELECTED_DEVICE remains unset and the menu explains
# how to set it manually.

# CL-031: Discover EVERY USB-attached block device — Ventoy-formatted, other
# filesystem, blank/raw, doesn't matter. Returns base disk paths (e.g.
# /dev/sdc, not /dev/sdc1) deduplicated. Combines three independent signals so
# a USB attached through a weird bridge that hides the TRAN=usb hint is still
# caught by /sys removable + udev ID_BUS.
#
# Excludes the disk that backs / so we never accidentally treat the host root
# as a removable target even if removable=1 lies (rare but seen on hot-plug
# SATA caddies).
_detect_all_usb_devices() {
  local devices=()
  local root_disk=""
  # Identify root disk so we can exclude it.
  if command -v findmnt >/dev/null 2>&1; then
    local root_src
    root_src=$(findmnt -no SOURCE / 2>/dev/null || echo "")
    if [[ -n "$root_src" && -b "$root_src" ]]; then
      root_disk=$(lsblk -no PKNAME "$root_src" 2>/dev/null | head -1)
      [[ -z "$root_disk" ]] && root_disk=$(basename "$root_src" | sed 's/p\?[0-9]*$//')
    fi
  fi

  # Method 1: lsblk -d -o NAME,TRAN,SIZE — TRAN=usb is the authoritative signal.
  # Skip 0-byte devices (card readers with no media inserted, USB hub
  # placeholders) so the prompt doesn't list a drive you can't write to.
  if command -v lsblk >/dev/null 2>&1; then
    while IFS= read -r line; do
      local name tran size_bytes
      name=$(awk '{print $1}' <<<"$line")
      tran=$(awk '{print $2}' <<<"$line")
      size_bytes=$(awk '{print $3}' <<<"$line")
      [[ "$tran" == "usb" && -n "$name" && "$name" != "$root_disk" && -b "/dev/$name" ]] || continue
      [[ -n "$size_bytes" && "$size_bytes" != "0" ]] || continue
      devices+=("/dev/$name")
    done < <(lsblk -d -n -b -o NAME,TRAN,SIZE 2>/dev/null)
  fi

  # Method 2: /sys/block/<dev>/removable — catches USB-attached drives behind
  # bridges that don't report TRAN=usb but DO mark removable.
  for sys in /sys/block/*; do
    [[ -e "$sys/removable" ]] || continue
    local rm; rm=$(cat "$sys/removable" 2>/dev/null)
    [[ "$rm" == "1" ]] || continue
    local name; name=$(basename "$sys")
    [[ "$name" == "$root_disk" ]] && continue
    # Skip optical (sr0/sr1) — removable=1 but not USB sticks.
    [[ "$name" =~ ^sr[0-9]+$ ]] && continue
    # Skip if zero-sized (floppy-style placeholders).
    local sz; sz=$(cat "$sys/size" 2>/dev/null || echo 0)
    [[ "$sz" == "0" ]] && continue
    [[ -b "/dev/$name" ]] && devices+=("/dev/$name")
  done

  # Method 3: udev ID_BUS=usb — final safety net for hot-plugged drives that
  # /sys hasn't fully labelled yet but udev has. Skip 0-sector devices so
  # empty card readers don't show up.
  if command -v udevadm >/dev/null 2>&1; then
    for blk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9] /dev/mmcblk[0-9]; do
      [[ -b "$blk" ]] || continue
      local base; base=$(basename "$blk")
      [[ "$base" == "$root_disk" ]] && continue
      local sec; sec=$(cat "/sys/block/$base/size" 2>/dev/null || echo 0)
      [[ "$sec" == "0" ]] && continue
      local bus
      bus=$(udevadm info --query=property --name="$blk" 2>/dev/null | grep -E '^ID_BUS=' | cut -d= -f2)
      [[ "$bus" == "usb" ]] && devices+=("$blk")
    done
  fi

  # Deduplicate (preserve order).
  local unique=() d found u
  for d in "${devices[@]}"; do
    found=false
    for u in "${unique[@]}"; do
      [[ "$d" == "$u" ]] && found=true && break
    done
    $found || unique+=("$d")
  done
  echo "${unique[@]}"
}

# CL-031: Classify a base-disk device (/dev/sdX) into:
#   ventoy   — has the dual Ventoy/VTOYEFI partition layout
#   formatted — has at least one mountable filesystem but isn't Ventoy
#   blank    — no recognized filesystem (raw / wiped / unpartitioned)
# Returns the classification on stdout. Best-effort; ambiguous = "formatted".
_classify_usb_device() {
  local dev="$1"
  [[ -z "$dev" || ! -b "$dev" ]] && { echo "unknown"; return 1; }
  # Ventoy check — VTOYEFI partition is the unmistakable fingerprint.
  if lsblk -n -o LABEL "$dev" 2>/dev/null | grep -qiE '^(Ventoy|VTOYEFI)$'; then
    echo "ventoy"; return 0
  fi
  # Any partition with a known filesystem?
  if lsblk -n -o FSTYPE "$dev" 2>/dev/null | grep -qE '^(ext[234]|exfat|vfat|ntfs|btrfs|xfs|f2fs)$'; then
    echo "formatted"; return 0
  fi
  echo "blank"
}

# Back-compat shim — existing callers (auto-detect at startup, _select_uca_mode,
# device-config submenu) used `_detect_usb_devices` and expected ALL hits to be
# Ventoy. CL-031 changes the contract: it now returns ALL USB devices. Callers
# that need "only Ventoy ones" call _detect_usb_devices_ventoy.
_detect_usb_devices() { _detect_all_usb_devices; }

_detect_usb_devices_ventoy() {
  local all out=() d
  all=$(_detect_all_usb_devices)
  for d in $all; do
    [[ "$(_classify_usb_device "$d")" == "ventoy" ]] && out+=("$d")
  done
  echo "${out[@]}"
}

_setup_device_interactive() {
  # CL-026 / SPEC-T02 (MOD-002, MOD-003): Auto-detect is RE-RUN whenever the
  # operator picks option 11. The 5-method scan (lsblk + udev + blkid +
  # /proc/mounts + ventoy-marker) lives in _detect_usb_devices and runs
  # below. Result is persisted to SELECTED_DEVICE for the rest of the
  # session; manual entry remains available as a fallback.
  log_section "USB Device Setup" "Identify and select any USB drive (Ventoy or blank)"

  echo ""
  echo "  Scanning for USB devices..."
  echo ""

  # Show all block devices for full context.
  if command -v lsblk >/dev/null 2>&1; then
    echo "  Available block devices:"
    echo "  ─────────────────────────────────────────────────"
    lsblk -n -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | while IFS= read -r line; do
      echo "  $line"
    done
    echo "  ─────────────────────────────────────────────────"
  fi

  # CL-031: auto-detect ANY USB device (Ventoy or not) so a blank USB shows
  # up here and can be routed into the "Install Ventoy" flow (menu option 1).
  local detected
  detected=$(_detect_all_usb_devices)
  local dev_array=($detected)

  if [[ ${#dev_array[@]} -eq 0 ]]; then
    echo ""
    echo "  ${YELLOW}No USB device auto-detected.${NC}"
    echo ""
    echo "  This is normal if:"
    echo "    - No USB drive is plugged in"
    echo "    - USB is connected through a bridge that hides removable=1"
    echo ""
    echo "  You can:"
    echo "    1) Plug in a USB and re-scan"
    echo "    2) Enter the device path manually"
    echo "    3) Skip for now"
    printf "\n  Choice [3]: "
    local sel; read -r sel
    if [[ "$sel" == "2" ]]; then
      printf "  Enter device path (e.g. /dev/sdb): "
      read -r SELECTED_DEVICE
      [[ -b "$SELECTED_DEVICE" ]] && export SELECTED_DEVICE || { log_error "Not a block device"; return 1; }
    fi
    return 0
  fi

  # CL-031: render every device with its classification + size + label so the
  # operator sees at a glance which is Ventoy, which is a blank target, etc.
  echo ""
  echo "  ${BOLD}USB devices found:${NC}"
  local i=1 d class size label
  for d in "${dev_array[@]}"; do
    class=$(_classify_usb_device "$d")
    size=$(lsblk -d -n -o SIZE "$d" 2>/dev/null | head -1 | tr -d ' ')
    label=$(lsblk -n -o LABEL "$d" 2>/dev/null | head -1 | tr -d ' ')
    [[ -z "$label" ]] && label="(no label)"
    case "$class" in
      ventoy)    printf "  ${CYAN}%d)${NC} %s  ${GREEN}[VENTOY]${NC}     %s  %s\n" "$i" "$d" "$size" "$label" ;;
      formatted) printf "  ${CYAN}%d)${NC} %s  ${YELLOW}[FORMATTED]${NC}  %s  %s (not Ventoy — option 1 reformats)\n" "$i" "$d" "$size" "$label" ;;
      blank)     printf "  ${CYAN}%d)${NC} %s  ${YELLOW}[BLANK]${NC}      %s  %s (ready for Ventoy install via option 1)\n" "$i" "$d" "$size" "$label" ;;
      *)         printf "  ${CYAN}%d)${NC} %s  [%s]  %s  %s\n" "$i" "$d" "$class" "$size" "$label" ;;
    esac
    i=$((i + 1))
  done
  echo "  ${CYAN}0)${NC} Enter manually"
  printf "\n  Select device number [1]: "
  local idx; read -r idx
  idx="${idx:-1}"
  if [[ "$idx" == "0" ]]; then
    printf "  Enter device path (e.g. /dev/sdb): "
    read -r SELECTED_DEVICE
    [[ -b "$SELECTED_DEVICE" ]] || { log_error "Not a block device: $SELECTED_DEVICE"; return 1; }
    export SELECTED_DEVICE
  elif [[ "$idx" -ge 1 && "$idx" -le ${#dev_array[@]} ]] 2>/dev/null; then
    export SELECTED_DEVICE="${dev_array[$((idx - 1))]}"
  else
    log_error "Invalid selection"
    return 1
  fi
  log_info "SELECTED_DEVICE set to $SELECTED_DEVICE"
  # Surface the classification so the operator knows next step.
  local picked_class; picked_class=$(_classify_usb_device "$SELECTED_DEVICE")
  case "$picked_class" in
    ventoy)
      if detect_ventoy_mount; then
        log_success "Ventoy mounted at $VENTOY_MOUNT"
      else
        log_info "Ventoy detected but not yet mounted (mount via menu option 2)"
      fi ;;
    blank|formatted)
      log_warn "Selected device is ${picked_class^^} — run menu option 1 to install Ventoy"
      [[ "$picked_class" == "formatted" ]] && \
        log_warn "Option 1 will WIPE this drive. Confirm carefully."
      ;;
  esac
  return 0
}

_show_device_status() {
  local dev="${SELECTED_DEVICE:-<none>}"
  local mount="${VENTOY_MOUNT:-<not mounted>}"
  local persist="no"
  local env="${UCA_ENVIRONMENT:-?}"

  # Dynamic: find the FIRST discoverable persistence volume rather than
  # hardcoding ubuntu-persistence.dat. _uca_list_volumes already merges the
  # auto-discovered .dat/.img files with any extras configured by the user.
  if [[ -n "${VENTOY_MOUNT:-}" ]]; then
    local first_vol
    first_vol=$(_uca_list_volumes 2>/dev/null | head -1)
    if [[ -n "$first_vol" && -f "$first_vol" ]]; then
      persist=$(du -h "$first_vol" 2>/dev/null | cut -f1 || echo "yes")
    fi
  fi

  printf "  ${BOLD}USB Device:${NC} %-20s ${BOLD}Mount:${NC} %-20s ${BOLD}Persistence:${NC} %s\n" "$dev" "$mount" "$persist"
  # Two-arg printf so the colors and the env value share one line; the
  # Hemlock badge is concatenated into the value with printf-friendly escapes.
  local hemlock_badge=""
  [[ "$HEMLOCK_ENABLED" == "true" ]] && hemlock_badge=" ${YELLOW}[Hemlock enabled]${NC}"
  printf "  ${BOLD}Environment:${NC} %-19s${hemlock_badge}\n" "$env"
}

# ── Ventoy Mount Resolver ───────────────────────────────────────────────────
# Resolve the active Ventoy mount point, robust to WHERE it was auto-mounted.
# Desktop Linux (GNOME/udisks) mounts removable media at /media/$USER/Ventoy or
# /run/media/$USER/Ventoy — NOT the /mnt/ventoy the in-repo helpers assume. This
# resolver prefers a mount the library already detected, then re-detects via
# SELECTED_DEVICE, then scans the conventional auto-mount locations. Echoes the
# mount path and returns 0 on success; returns 1 if Ventoy is not mounted.
_resolve_ventoy_mount() {
  if [[ -n "${VENTOY_MOUNT:-}" ]] && mountpoint -q "${VENTOY_MOUNT}" 2>/dev/null; then
    printf '%s\n' "$VENTOY_MOUNT"; return 0
  fi
  if detect_ventoy_mount 2>/dev/null && [[ -n "${VENTOY_MOUNT:-}" ]]; then
    printf '%s\n' "$VENTOY_MOUNT"; return 0
  fi
  local user="${USER:-$(id -un 2>/dev/null || echo "")}"
  local cand
  for cand in \
    "/media/${user}/Ventoy" "/run/media/${user}/Ventoy" \
    /media/*/Ventoy /run/media/*/Ventoy \
    /mnt/ventoy /Volumes/Ventoy; do
    if mountpoint -q "$cand" 2>/dev/null || [[ -d "$cand/ventoy" || -d "$cand/persistence" ]]; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  return 1
}

# ── Formatting Helpers (consistent menu rendering) ──────────────────────────
# All sub-menus use these for uniform appearance.

_menu_header() {
  # ═══ Section Title ═══
  local title="$1"
  printf "\n  ${BOLD}${CYAN}═══ %s ═══${NC}\n" "$title"
}

_menu_subheader() {
  # ── subsection ──
  local title="$1"
  printf "  ${DIM}── %s ──${NC}\n" "$title"
}

_menu_item() {
  #   N)  Description                    [TARGET]    Detail
  # target/detail are optional (e.g. a bare "0) Back"); default them so the
  # `set -u` in effect cannot turn a 2-arg call into an unbound-variable crash.
  local num="$1" desc="$2" target="${3:-}" detail="${4:-}"
  if [[ -n "$target" ]]; then
    printf "  ${CYAN}%-4s${NC}) %-34s ${GREEN}[%s]${NC}    %s\n" "$num" "$desc" "$target" "$detail"
  else
    printf "  ${CYAN}%-4s${NC}) %s\n" "$num" "$desc"
  fi
}

_menu_prompt() {
  #   ▸ Select option:
  printf "\n  ${YELLOW}▸ %s${NC} " "$1"
}

_menu_info() {
  #   ℹ Info text
  printf "  ${BLUE}ℹ %s${NC}\n" "$1"
}

_menu_warn() {
  #   ⚠ Warning text
  printf "  ${YELLOW}⚠ %s${NC}\n" "$1"
}

_menu_error() {
  #   ✗ Error text
  printf "  ${RED}✗ %s${NC}\n" "$1"
}

_menu_success() {
  #   ✓ Success text
  printf "  ${GREEN}✓ %s${NC}\n" "$1"
}

_menu_divider() {
  printf "  ${DIM}────────────────────────────────────────────────${NC}\n"
}

_menu_confirm() {
  # Prompts Y/n, returns 0 on yes
  local msg="$1"
  printf "  ${YELLOW}▸ %s [Y/n]: ${NC}" "$msg"
  local ans; read -r ans
  [[ "${ans,,}" != "n" && "${ans,,}" != "no" ]]
}

# ── Whiptail Detection ─────────────────────────────────────────────────────
HAS_WHIPTAIL=false
command -v whiptail >/dev/null 2>&1 && HAS_WHIPTAIL=true
FORCE_TEXT=false

# Hemlock is OPT-IN. The Hemlock Manager option only appears when --hemlock /
# -H is passed (or HEMLOCK_ENABLED=true is exported). Short flag is -H not -h
# because -h is the universal --help shortcut and we don't want to shadow it.
HEMLOCK_ENABLED="${HEMLOCK_ENABLED:-false}"

# ── Parse Arguments ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; export DRY_RUN; shift ;;
    --text)      FORCE_TEXT=true; shift ;;
    --log-file)  LOG_FILE="$2"; export LOG_FILE; shift 2 ;;
    --hemlock|-H) HEMLOCK_ENABLED=true; export HEMLOCK_ENABLED; shift ;;
    --mode)
      case "${2:-}" in
        usb|host) UCA_MODE="$2"; export UCA_MODE; shift 2 ;;
        *) log_error "--mode requires 'usb' or 'host' (got: ${2:-empty})"; exit 1 ;;
      esac ;;
    --usb)       UCA_MODE=usb;  export UCA_MODE; shift ;;
    --host)      UCA_MODE=host; export UCA_MODE; shift ;;
    --help|-h)
      echo "USB-Hemlock Unified Compute Platform — Master Menu"
      echo ""
      echo "Usage:"
      echo "  $0                     Interactive menu (whiptail or text fallback)"
      echo "  $0 --text              Force text-based menu"
      echo "  $0 --dry-run           Dry-run mode (no mutations)"
      echo "  $0 --hemlock | -H      Show the Hemlock Manager option (opt-in)"
      echo "  $0 --mode usb|host     Skip the boot prompt; force install target"
      echo "  $0 --usb | --host      Shorthand for --mode usb / --mode host"
      echo "  $0 --log-file PATH     Custom log file path"
      echo "  $0 --help              Show this help"
      echo ""
      echo "Environment:"
      echo "  DRY_RUN=true           Preview mutations without executing"
      echo "  HEMLOCK_ENABLED=true   Same as --hemlock"
      echo "  UCA_MODE=usb|host      Same as --mode"
      echo "  LOG_FILE=path          Write logs to this file"
      echo "  LOG_LEVEL=LEVEL        Minimum log level (DEBUG/INFO/WARN/ERROR)"
      echo "  HEMLOCK_DIR=path       Path to hemlock-runtime"
      echo "  SELECTED_DEVICE=dev    USB device (e.g. /dev/sdb)"
      echo "  UCA_ENVIRONMENT=...    usb-boot | usb-mounted | native"
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Logging Setup ───────────────────────────────────────────────────────────
export LOG_FILE DRY_RUN
log_info "Master menu started (PID $$, log: $LOG_FILE)"
log_info "Dry-run: $DRY_RUN"

# ── Component Runners ───────────────────────────────────────────────────────
_run_usb_setup() {
  log_section "USB Setup Assistant" "Interactive installer"
  local args=()
  [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
  bash "$USB_DIR/usb-setup-assistant.sh" "${args[@]+"${args[@]}"}" || log_warn "USB setup exited with code $?"
}

_run_usbctl() {
  _menu_header "Unified CLI (usbctl)"
  _menu_subheader "USB — subcommand selector"
  echo ""
  _menu_item "1" "usb detect"       "USB" "List USB devices"
  _menu_item "2" "usb mount"        "USB" "Mount Ventoy USB"
  _menu_item "3" "usb unmount"      "USB" "Unmount Ventoy"
  _menu_item "4" "usb persistence"  "USB" "Show persistence status"
  _menu_item "5" "config host-id"   "USB" "Generate host ID"
  _menu_item "6" "config show"      "USB" "Show full config"
  _menu_item "7" "config init"      "USB" "Initialize config"
  _menu_item "8" "alias --list"     "USB" "List aliases"
  _menu_item "9" "validate all"     "USB" "Run all validations"
  _menu_item "0" "Back"
  _menu_prompt "Select subcommand"
  local choice; read -r choice
  case "$choice" in
    1) bash "$USB_DIR/cli/usbctl" usb detect ;;
    2) bash "$USB_DIR/cli/usbctl" usb mount ;;
    3) bash "$USB_DIR/cli/usbctl" usb unmount ;;
    4) bash "$USB_DIR/cli/usbctl" usb persistence ;;
    5) bash "$USB_DIR/cli/usbctl" config host-id ;;
    6) bash "$USB_DIR/cli/usbctl" config show ;;
    7) bash "$USB_DIR/cli/usbctl" config init ;;
    8) bash "$USB_DIR/cli/usbctl" alias --list ;;
    9) bash "$USB_DIR/cli/usbctl" validate all ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

_run_alias_manager() {
  # CL-030: target follows UCA_MODE — alias_manager.sh resolves the file
  # itself via _uca_install_root.
  local tgt; tgt=$(_uca_install_root 2>/dev/null || echo "$HOME")
  log_section "Alias Manager" "${UCA_MODE^^} — ${tgt}/bash_aliases.sh"
  local args=()
  [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
  bash "$USB_DIR/scripts/alias_manager.sh" "${args[@]+"${args[@]}"}" "$@"
}

_run_ssh_manager() {
  log_section "SSH Host Manager" "HOST — ~/.ssh/hosts_usb"
  local args=()
  [[ "$DRY_RUN" == "true" ]] && args+=(--dry-run)
  bash "$USB_DIR/scripts/ssh_host_manager.sh" "${args[@]+"${args[@]}"}" "$@"
}

_run_sysman() {
  log_section "System Manager" "HOST — health, network, disk, services"
  bash "$USB_DIR/sysman.sh" "$@"
}

_run_hemlock_tui() {
  log_section "Hemlock Agent Runtime TUI" "CONTAINER — agent management"
  if [[ -z "$HEMLOCK_DIR" || ! -d "$HEMLOCK_DIR/scripts" ]]; then
    log_error "HEMLOCK_DIR not set or invalid: ${HEMLOCK_DIR:-<unset>}"
    log_info "Set HEMLOCK_DIR to the absolute path of hemlock-runtime/"
    return 1
  fi
  export HEMLOCK_DIR
  bash "$USB_DIR/hemlock-tui" "$@"
}

_run_hemlock_status() {
  log_section "Hemlock Runtime Status" "CONTAINER — runtime check"
  if [[ -n "$HEMLOCK_DIR" && -f "$HEMLOCK_DIR/scripts/hemlock" ]]; then
    bash "$HEMLOCK_DIR/scripts/hemlock" status 2>&1 || log_warn "Hemlock status check failed"
  else
    log_error "Hemlock runtime not found"
  fi
}

_run_deploy() {
  _menu_header "Master Deployment (DEPLOY.sh)"
  _uca_sudo_init
  _menu_subheader "HOST + USB + CONTAINER"
  echo ""
  _menu_warn "DEPLOY.sh requires root and modifies:"
  echo "    - System packages, services, configs (HOST)"
  echo "    - USB persistence, Ventoy setup (USB)"
  echo "    - Docker containers, runtime configs (CONTAINER)"
  echo ""
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "Running DEPLOY.sh in dry-run mode (no mutations)"
    sudo -n bash "$SCRIPT_DIR/hemlock/DEPLOY.sh" --dry-run 2>&1 || {
      _menu_warn "DEPLOY dry-run requires sudo. Run 'sudo -v' first, or try without root."
    }
  else
    _menu_warn "DEPLOY.sh requires root. You may be prompted for your password."
    sudo bash "$SCRIPT_DIR/hemlock/DEPLOY.sh" 2>&1 || _menu_warn "DEPLOY exited with code $?"
  fi
}

_run_validation() {
  _menu_header "System Validation"
  _menu_subheader "ALL — validate all components"
  bash "$USB_DIR/cli/usbctl" validate all 2>&1
}

_run_essentials() {
  _menu_header "Build Essentials Installer"
  _uca_sudo_init
  # Policy: tooling installs onto the USB by default. Only fall through to the
  # host installer when the user explicitly overrides, with the trade-off
  # explained here in the terminal.
  if [[ "${UCA_INSTALL_TARGET:-usb}" == "usb" ]]; then
    _menu_subheader "Install target = USB (project default)"
    echo ""
    _menu_info "Per policy, dev tooling installs onto the portable USB persistence,"
    _menu_info "not this host. The host installer below writes to /opt and /var/log"
    _menu_info "and only makes sense if you want tools on THIS machine."
    echo ""
    if _menu_confirm "Install into the USB persistence instead (recommended)?"; then
      _uca_install_tooling_usb
      return 0
    fi
    _menu_warn "Overriding to a HOST install for this run (USB remains the default)."
  fi
  _menu_subheader "HOST — installs to /opt, /var/log"
  echo ""
  _menu_warn "This installs build tools system-wide (HOST only):"
  echo "    - llama.cpp, ollama, rust, foundry, hardhat, playwright, tauri, bun"
  echo "    - Writes to /opt, /var/log, requires root"
  echo ""
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "Running essentials installer in dry-run mode"
    sudo -n bash "$USB_DIR/scripts/setup-essentials-enhanced.sh" --dry-run 2>&1 || {
      _menu_warn "Essentials dry-run requires sudo. Run 'sudo -v' first, or try without root."
    }
  else
    _menu_warn "Essentials installer requires root. You may be prompted for your password."
    sudo bash "$USB_DIR/scripts/setup-essentials-enhanced.sh" 2>&1 || _menu_warn "Essentials exited"
  fi
}

_run_automount() {
  _menu_header "USB Auto-Mount Setup"
  _uca_sudo_init
  _menu_subheader "HOST — udev rules + systemd service"
  echo ""
  _menu_warn "Auto-mount installs udev rules and a systemd service on HOST."
  echo "    - Requires root for install/removal"
  echo "    - Affects all USB devices system-wide"
  echo ""
  _menu_item "1" "Install auto-mount" "" "setup-usb-automount.sh"
  _menu_item "2" "Remove auto-mount"  "" "teardown-usb-automount.sh"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1)
      _menu_info "Installing USB auto-mount (requires root)..."
      sudo bash "$USB_DIR/usb-automount/setup-usb-automount.sh" || _menu_warn "Auto-mount install failed"
      ;;
    2)
      _menu_info "Removing USB auto-mount (requires root)..."
      sudo bash "$USB_DIR/usb-automount/teardown-usb-automount.sh" || _menu_warn "Auto-mount removal failed"
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

_run_logs() {
  _menu_header "Log Viewer"
  _menu_subheader "HOST — log files"
  _menu_info "Log file: $LOG_FILE"
  if [[ -f "$LOG_FILE" ]]; then
    echo ""
    _menu_subheader "Last 30 lines"
    tail -30 "$LOG_FILE"
    _menu_divider
    echo ""
    _menu_item "1" "Tail log (live — 10s timeout)"
    _menu_item "2" "Search log"
    _menu_item "3" "Clear log"
    _menu_item "0" "Back"
    _menu_prompt "Select option"
    local choice; read -r choice
    case "$choice" in
      1)
        _menu_info "Tailing log for 10 seconds (Ctrl+C to stop early)..."
        if command -v timeout >/dev/null 2>&1; then
          timeout 10 tail -f "$LOG_FILE" 2>/dev/null || true
        else
          tail -f "$LOG_FILE" &
          local tailpid=$!
          sleep 10
          kill "$tailpid" 2>/dev/null || true
          wait "$tailpid" 2>/dev/null || true
        fi
        ;;
      2) printf "  Search query: "; local q; read -r q; grep -i "$q" "$LOG_FILE" || echo "  No matches" ;;
      3) echo "" > "$LOG_FILE" && _menu_success "Log cleared" ;;
      0) return 0 ;;
      *) _menu_error "Invalid option: $choice" ;;
    esac
  else
    _menu_info "No log file yet — run some operations first"
  fi
}

_run_diag() {
  _menu_header "Diagnostics"
  _menu_subheader "HOST — system info"
  echo ""
  printf "  ${BOLD}Hostname${NC}  : %s\n" "$(hostname)"
  printf "  ${BOLD}Kernel${NC}    : %s\n" "$(uname -r)"
  printf "  ${BOLD}OS${NC}        : %s\n" "$(source "$USB_DIR/lib/platform.sh" && detect_os)"
  printf "  ${BOLD}Virt${NC}      : %s\n" "$(source "$USB_DIR/lib/platform.sh" && detect_virtualization)"
  printf "  ${BOLD}Bash${NC}      : %s\n" "${BASH_VERSION}"
  printf "  ${BOLD}jq${NC}        : %s\n" "$(jq --version 2>&1 || echo 'not found')"
  printf "  ${BOLD}Docker${NC}    : %s\n" "$(docker --version 2>&1 || echo 'not found')"
  printf "  ${BOLD}HEMLOCK${NC}   : %s\n" "${HEMLOCK_DIR:-<unset>}"
  printf "  ${BOLD}DEVICE${NC}    : %s\n" "${SELECTED_DEVICE:-<unset>}"
  printf "  ${BOLD}DRY_RUN${NC}   : %s\n" "$DRY_RUN"
  printf "  ${BOLD}LOG_FILE${NC}  : %s\n" "$LOG_FILE"
  echo ""
  printf "  ${BOLD}Config${NC}    : %s\n" "${HOME}/.config/usb-compute-automation/config.json"
  if [[ -f "${HOME}/.config/usb-compute-automation/config.json" ]]; then
    printf "  ${BOLD}Host ID${NC}   : %s\n" "$(jq -r '.host_id.host_id // "unset"' "${HOME}/.config/usb-compute-automation/config.json" 2>/dev/null)"
  fi
  echo ""
  _menu_item "1" "Install antivirus toolkit (clamav+rkhunter+lynis+trivy, scheduled cron)"
  _menu_item "2" "Run antivirus action (scan/fullscan/rootkit/selfheal/quarantine)"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1) _run_antivirus_install ;;
    2) _run_antivirus_action ;;
    0) return 0 ;;
    *) _menu_info "(no action)" ;;
  esac
}

_run_antivirus_install() {
  _menu_header "Antivirus Toolkit Install"
  _uca_sudo_init
  _menu_subheader "HOST — installs clamav, rkhunter, lynis, trivy + /usr/local/bin/virus"
  local boot="$USB_DIR/scripts/install-antivirus.sh"
  if [[ ! -f "$boot" ]]; then
    _menu_error "install-antivirus.sh missing at $boot"; return 1
  fi
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: would 'sudo bash $boot' (root required for apt + /usr/local/bin)"
    return 0
  fi
  _menu_warn "Requires sudo (apt install + writes to /usr/local/bin + cron + ufw)."
  _menu_confirm "Proceed?" || return 0
  sudo bash "$boot" || _menu_warn "Antivirus install exited with code $?"
}

_run_antivirus_action() {
  _menu_header "Antivirus Action"
  if ! command -v virus >/dev/null 2>&1; then
    _menu_error "'virus' command not installed. Run option 1 first."
    return 1
  fi
  _menu_item "1" "Quick scan (auto-quarantine on hit)"
  _menu_item "2" "Full system scan (auto-quarantine on hit)"
  _menu_item "3" "Rootkit check (rkhunter + chkrootkit)"
  _menu_item "4" "Self-heal (tier 1+2+3 hardening)"
  _menu_item "5" "Remediate (refresh definitions + baseline)"
  _menu_item "6" "Quarantine — list contents"
  _menu_item "7" "Quarantine — purge (destructive)"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local c; read -r c
  case "$c" in
    1) sudo virus scan ;;
    2) sudo virus fullscan ;;
    3) sudo virus rootkit ;;
    4) sudo virus selfheal ;;
    5) sudo virus remediate ;;
    6) sudo virus quarantine list ;;
    7) _menu_confirm "PURGE all quarantined files? This is irreversible." && sudo virus quarantine purge --yes ;;
    0) return 0 ;;
    *) _menu_info "(no action)" ;;
  esac
}

# ── Startup Manager ─────────────────────────────────────────────────────────
# CL-026 / SPEC-T05 (MOD-008, MOD-013): USB-first target resolver.
# Default target for any startup-script write is the active USB persistence's
# rc.local (auto-discovered via _uca_primary_persistence — no hardcoded
# ubuntu-persistence.dat). Returns absolute path to the persistence file on
# stdout, 0 on success. Callers loop-mount the result and write inside
# <mount>/etc/rc.local. Refuses to silently fall back to the host's
# /etc/rc.local. Host writes require the operator to call
# _startup_confirm_host_target() and answer "HOST" verbatim.
_startup_target_must_be_usb() {
  if [[ -z "${SELECTED_DEVICE:-}" ]]; then
    _menu_error "No USB device selected — use option 11 (USB Device Setup) to detect one." >&2
    return 1
  fi
  if [[ ! -b "${SELECTED_DEVICE}" ]]; then
    _menu_error "SELECTED_DEVICE=${SELECTED_DEVICE} is not a block device." >&2
    return 1
  fi
  local pfile
  if ! pfile=$(_uca_primary_persistence 2>/dev/null) || [[ -z "$pfile" ]]; then
    _menu_error "No persistence file found on USB — create one via option 9." >&2
    return 1
  fi
  printf '%s\n' "$pfile"
}

_startup_confirm_host_target() {
  echo ""
  _menu_warn "Writing to the HOST will modify your live system."
  printf "Type ${BOLD}HOST${NC} verbatim to confirm (anything else cancels): "
  local ans=""
  read -r ans </dev/tty 2>/dev/null || ans=""
  [[ "$ans" == "HOST" ]]
}

_run_startup_manager() {
  _menu_header "Startup Manager"
  _menu_subheader "USB-FIRST — boot scripts default to USB persistence (option 4 = inject)"
  echo ""
  _menu_item "1" "List startup scripts"               "" "USB + host"
  _menu_item "2" "Edit USB startup.sh"                "" ""
  _menu_item "3" "View USB persistence rc.local"      "" ""
  _menu_item "4" "Inject startup.sh into rc.local"    "" ""
  _menu_item "5" "View host rc.local"                 "" "/etc/rc.local"
  _menu_item "6" "View host profile.d scripts"        "" ""
  _menu_item "7" "View host systemd services"         "" ""
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1)
      echo ""
      _menu_subheader "USB Persistence rc.local"
      if [[ -n "${SELECTED_DEVICE:-}" && -b "${SELECTED_DEVICE}" ]]; then
        local vmp=""
        vmp=$(_resolve_ventoy_mount) || vmp=""
        local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
        if [[ -n "$pfile" ]]; then
          local tmpmnt="/tmp/usb-persist-$$"
          mkdir -p "$tmpmnt"
          if sudo mount -o loop,ro "$pfile" "$tmpmnt" 2>/dev/null; then
            if [[ -f "$tmpmnt/etc/rc.local" ]]; then
              cat "$tmpmnt/etc/rc.local"
            else
              _menu_info "(no rc.local in persistence)"
            fi
            sudo umount "$tmpmnt" 2>/dev/null || true
          else
            _menu_info "(could not mount persistence for inspection)"
          fi
          rmdir "$tmpmnt" 2>/dev/null || true
        else
          _menu_info "(Ventoy not mounted — mount USB first)"
        fi
      else
        _menu_info "(no USB device selected)"
      fi
      echo ""
      _menu_subheader "USB startup.sh"
      if [[ -n "${SELECTED_DEVICE:-}" ]]; then
        local vmp2=""
        vmp2=$(_resolve_ventoy_mount) || vmp2=""
        if [[ -n "$vmp2" && -f "$vmp2/startup.sh" ]]; then
          cat "$vmp2/startup.sh"
        else
          _menu_info "(no startup.sh on USB)"
        fi
      fi
      echo ""
      _menu_subheader "Host rc.local"
      if [[ -f /etc/rc.local ]]; then
        cat /etc/rc.local
      else
        _menu_info "(no /etc/rc.local)"
      fi
      echo ""
      _menu_subheader "Host profile.d"
      if [[ -d /etc/profile.d ]]; then
        ls -1 /etc/profile.d/*.sh 2>/dev/null | while read -r f; do
          echo "  $(basename "$f")"
        done
      else
        _menu_info "(no /etc/profile.d/)"
      fi
      ;;
    2)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set — use option 14 (USB Device Setup)"
        return 1
      fi
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      if [[ -z "$vmp" ]]; then
        _menu_error "Ventoy not mounted — mount USB first"
        return 1
      fi
      local startup="$vmp/startup.sh"
      if [[ ! -f "$startup" ]]; then
        cat > "$startup" << 'STARTUP'
#!/usr/bin/env bash
# USB Startup Script — runs on every boot of the USB live environment
# This script is executed by rc.local during boot.
# Add your custom startup commands below.

# Wait for network
sleep 3

# Your custom commands here:
# echo "USB boot complete — $(date)"
STARTUP
        chmod +x "$startup"
        _menu_success "Created $startup with template"
      fi
      ${EDITOR:-nano} "$startup"
      _menu_success "Startup script saved: $startup"
      ;;
    3)
      if [[ -n "${SELECTED_DEVICE:-}" ]]; then
        local vmp=""
        vmp=$(_resolve_ventoy_mount) || vmp=""
        local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
        if [[ -n "$pfile" ]]; then
          local tmpmnt="/tmp/usb-persist-$$"
          mkdir -p "$tmpmnt"
          if sudo mount -o loop,ro "$pfile" "$tmpmnt" 2>/dev/null; then
            if [[ -f "$tmpmnt/etc/rc.local" ]]; then
              _menu_subheader "rc.local in persistence"
              cat "$tmpmnt/etc/rc.local"
            else
              _menu_info "No rc.local found in persistence image"
            fi
            sudo umount "$tmpmnt" 2>/dev/null || true
          else
            _menu_error "Could not mount persistence"
          fi
          rmdir "$tmpmnt" 2>/dev/null || true
        else
          _menu_error "Persistence file not found — create persistence first"
        fi
      else
        _menu_error "No USB device selected"
      fi
      ;;
    4)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set"
        return 1
      fi
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
      if [[ -z "$pfile" ]]; then
        _menu_error "Persistence file not found"
        return 1
      fi
      if [[ ! -f "$vmp/startup.sh" ]]; then
        _menu_error "No startup.sh on USB — create one first (option 2)"
        return 1
      fi
      local tmpmnt="/tmp/usb-persist-$$"
      mkdir -p "$tmpmnt"
      if sudo mount -o loop "$pfile" "$tmpmnt" 2>/dev/null; then
        local rclocal="$tmpmnt/etc/rc.local"
        if [[ -f "$rclocal" ]]; then
          if grep -q "startup.sh" "$rclocal"; then
            _menu_info "startup.sh already referenced in rc.local"
          else
            echo "" >> "$rclocal"
            echo "# Run USB startup script" >> "$rclocal"
            echo "bash /media/*/Ventoy/startup.sh &" >> "$rclocal"
            _menu_success "Injected startup.sh into rc.local"
          fi
        else
          cat > "$rclocal" << 'RCLOCAL'
#!/bin/bash
# USB persistence autostart
bash /media/*/Ventoy/startup.sh &
exit 0
RCLOCAL
          chmod +x "$rclocal"
          _menu_success "Created rc.local with startup.sh reference"
        fi
        sudo umount "$tmpmnt" 2>/dev/null || true
      else
        _menu_error "Could not mount persistence"
      fi
      rmdir "$tmpmnt" 2>/dev/null || true
      ;;
    5)
      if [[ -f /etc/rc.local ]]; then
        _menu_subheader "/etc/rc.local"
        cat /etc/rc.local
      else
        _menu_info "No /etc/rc.local on host"
      fi
      ;;
    6)
      if [[ -d /etc/profile.d ]]; then
        for f in /etc/profile.d/*.sh; do
          [[ -f "$f" ]] || continue
          _menu_subheader "$(basename "$f")"
          cat "$f"
        done
      else
        _menu_info "No /etc/profile.d/ on host"
      fi
      ;;
    7)
      _menu_subheader "Enabled systemd services"
      systemctl list-unit-files --type=service --state=enabled 2>/dev/null | head -30 || _menu_info "(systemctl not available)"
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

# ── Persistence Manager ─────────────────────────────────────────────────────
_run_persistence_manager() {
  _menu_header "Persistence Manager"
  _menu_subheader "USB — persistence partitions"
  echo ""
  _menu_item "1" "View persistence status"              "" ""
  _menu_item "2" "Create persistence"                   "" "WARNING: formats .dat file"
  _menu_item "3" "Resize persistence"                   "" "WARNING: destructive"
  _menu_item "4" "Browse persistence"                   "" "loop-mount read-only"
  _menu_item "5" "Check persistence health"             "" "fsck"
  _menu_item "6" "View Ventoy partition layout"         "" ""
  _menu_item "7" "Rename a persistence volume (.dat)"   "" "filename only"
  _menu_item "8" "Relabel a persistence volume (ext4)"  "" "DATA volumes — protects casper-rw"
  _menu_item "9" "Ventoy.json doctor"                   "" "validate boot routing"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1)
      echo ""
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "No USB device selected — use option 14 (USB Device Setup)"
        return 0
      fi
      printf "  ${BOLD}Device:${NC} %s\n" "$SELECTED_DEVICE"
      echo ""
      lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null || _menu_info "(lsblk failed)"
      echo ""
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      if [[ -n "$vmp" ]]; then
        printf "  ${BOLD}Ventoy mount:${NC} %s\n" "$vmp"
        local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
        if [[ -n "$pfile" ]]; then
          local psize
          psize=$(du -h "$pfile" 2>/dev/null | cut -f1)
          printf "  ${BOLD}Persistence:${NC} %s (%s)\n" "$pfile" "$psize"
          printf "  ${BOLD}Label:${NC} %s\n" "$(sudo blkid -o value -s LABEL "$pfile" 2>/dev/null || echo 'unknown')"
          printf "  ${BOLD}Type:${NC} %s\n" "$(sudo blkid -o value -s TYPE "$pfile" 2>/dev/null || echo 'unknown')"
        else
          _menu_info "Persistence: NOT CREATED"
        fi
      else
        _menu_info "Ventoy: NOT MOUNTED"
      fi
      ;;
    2)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set"
        return 1
      fi
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      if [[ -z "$vmp" ]]; then
        _menu_error "Ventoy not mounted — mount USB first"
        return 1
      fi
      local pdir="$vmp/persistence"
      mkdir -p "$pdir"
      # CL-026 / SPEC-T03 (MOD-006): multi-volume support. Persistence Manager
      # MUST allow adding additional volumes (e.g. hemlock.dat, models.dat,
      # docker.dat) alongside an existing primary. We list existing volumes
      # first so the user knows what's already there, then auto-suggest a
      # non-colliding default. Overwrite of an existing file is allowed but
      # explicitly opt-in (default is to pick a new name).
      echo ""
      _menu_subheader "Existing persistence volumes in $pdir"
      local existing_count=0
      if [[ -d "$pdir" ]]; then
        while IFS= read -r -d '' f; do
          local sz; sz=$(du -h "$f" 2>/dev/null | cut -f1)
          local lbl; lbl=$(sudo blkid -o value -s LABEL "$f" 2>/dev/null || echo '?')
          printf "  • %s  (%s, label=%s)\n" "$(basename "$f")" "$sz" "$lbl"
          existing_count=$((existing_count + 1))
        done < <(find "$pdir" -maxdepth 1 -type f \( -name '*.dat' -o -name 'casper-rw' \) -print0 2>/dev/null)
      fi
      [[ "$existing_count" -eq 0 ]] && echo "  (none yet)"
      echo ""
      # Auto-suggest a non-colliding default: ubuntu-persistence.dat if absent,
      # else hemlock.dat, models.dat, data-1.dat, data-2.dat, ...
      local suggest=""
      for cand in ubuntu-persistence.dat hemlock.dat models.dat data.dat; do
        [[ ! -f "$pdir/$cand" ]] && { suggest="$cand"; break; }
      done
      if [[ -z "$suggest" ]]; then
        for n in 1 2 3 4 5 6 7 8 9; do
          if [[ ! -f "$pdir/data-$n.dat" ]]; then suggest="data-$n.dat"; break; fi
        done
      fi
      printf "  New filename in $pdir [%s]: " "$suggest"
      local pname; read -r pname; pname="${pname:-$suggest}"
      # Refuse path traversal / slashes in the basename.
      [[ "$pname" =~ / ]] && { _menu_error "Filename must be a plain basename"; return 1; }
      local pfile="$pdir/$pname"
      # If the user typed an existing name, REQUIRE explicit overwrite consent.
      # No 'denial' on existing-name — but also no silent overwrite default.
      if [[ -f "$pfile" ]]; then
        _menu_warn "'$pname' already exists — overwrite is destructive"
        _menu_info "Tip: pick a different name (e.g. ${suggest}) to keep both volumes"
        if ! _menu_confirm "OVERWRITE existing $pname?"; then
          _menu_info "Cancelled — no changes made. Re-run and pick a unique filename to add a NEW volume."
          return 0
        fi
      fi
      # CL-006 label safety: only the PRIMARY volume gets the casper-rw label.
      # For non-primary additions, suggest a meaningful label.
      local plabel="casper-rw"
      if [[ "$pname" != "ubuntu-persistence.dat" && "$pname" != "casper-rw" ]]; then
        # derive a label from the filename (basename minus .dat, max 16 chars)
        local auto_label="${pname%.dat}"
        auto_label="${auto_label:0:16}"
        printf "  Label for ext4 [%s]: " "$auto_label"
        local lbl_in; read -r lbl_in
        plabel="${lbl_in:-$auto_label}"
        [[ "$plabel" == "casper-rw" ]] && {
          _menu_warn "Label 'casper-rw' is reserved for the primary; using '$auto_label'"
          plabel="$auto_label"
        }
      fi
      # CL-033: show max available so the operator picks something realistic.
      local max_mib reserved_mib max_gb
      max_mib=$(_uca_max_new_volume_mib 2>/dev/null) || max_mib=0
      reserved_mib=$((UCA_RESERVED_BYTES / 1024 / 1024))
      max_gb=$((max_mib / 1024))
      _menu_info "Reserved for configs/scripts/profiles: ${reserved_mib}MiB"
      _menu_info "Max new volume size: ${max_mib}MiB (~${max_gb}GiB)"
      printf "  Size in GB [8]: "
      local size_gb; read -r size_gb
      size_gb="${size_gb:-8}"
      [[ "$size_gb" =~ ^[0-9]+$ ]] || { _menu_error "Size must be an integer GB"; return 1; }
      local size_mib=$((size_gb * 1024))
      if ! _uca_validate_persistence_size_mib "$size_mib"; then
        _menu_error "Size validation failed — cancelled."
        return 1
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: Would create ${size_gb}GB persistence at $pfile"
        return 0
      fi
      _menu_info "Creating ${size_gb}GB persistence file..."
      dd if=/dev/zero of="$pfile" bs=1M count="$size_mib" status=progress 2>&1 || {
        _menu_error "dd failed"; return 1
      }
      _menu_info "Formatting as ext4 with label '$plabel'..."
      mkfs.ext4 -F -L "$plabel" "$pfile" 2>&1 || {
        _menu_error "mkfs.ext4 failed"; return 1
      }
      _menu_success "Persistence created: $pfile (${size_gb}GB, ext4, label=$plabel)"
      _menu_info "Tip: link this to a profile via Device/Boot Profiles → edit manifest → data_volumes[]"
      ;;
    3)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set"
        return 1
      fi
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
      if [[ -z "$pfile" ]]; then
        _menu_error "Persistence file not found (no profile primary, no discovered volume)"
        return 1
      fi
      local cur_size_mib
      cur_size_mib=$(du -m "$pfile" 2>/dev/null | cut -f1)
      # CL-033: show what's actually available so resize requests are bounded.
      local max_mib reserved_mib
      max_mib=$(_uca_max_new_volume_mib 2>/dev/null) || max_mib=0
      reserved_mib=$((UCA_RESERVED_BYTES / 1024 / 1024))
      # When resizing the SAME file we reclaim its current bytes, so effective
      # ceiling = max_new + current_size.
      local resize_max_mib=$((max_mib + cur_size_mib))
      printf "  Current size: ${cur_size_mib}MiB\n"
      _menu_info "Reserved for configs/scripts/profiles: ${reserved_mib}MiB"
      _menu_info "Max resize target: ${resize_max_mib}MiB (~$((resize_max_mib / 1024))GiB)"
      printf "  New size in GB: "
      local new_gb; read -r new_gb
      [[ "$new_gb" =~ ^[0-9]+$ && "$new_gb" -ge 1 ]] || { _menu_error "Invalid size"; return 1; }
      local new_mib=$((new_gb * 1024))
      [[ "$new_mib" -lt 256 ]] && { _menu_error "Minimum persistence size is 256MiB"; return 1; }
      if [[ "$new_mib" -gt "$resize_max_mib" ]]; then
        _menu_error "Requested ${new_mib}MiB exceeds resize ceiling ${resize_max_mib}MiB (reservation + existing volumes)"
        return 1
      fi
      _menu_warn "This will ERASE ALL DATA on the persistence file."
      _menu_confirm "Continue?" || return 0
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: Would resize to ${new_gb}GB"
        return 0
      fi
      dd if=/dev/zero of="$pfile" bs=1M count="$new_mib" status=progress 2>&1 || {
        _menu_error "dd failed"; return 1
      }
      resize2fs "$pfile" 2>&1 || {
        _menu_error "resize2fs failed"; return 1
      }
      _menu_success "Persistence resized to ${new_gb}GB"
      ;;
    4)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set"
        return 1
      fi
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
      if [[ -z "$pfile" ]]; then
        _menu_error "Persistence file not found (no profile primary, no discovered volume)"
        return 1
      fi
      local tmpmnt="/tmp/usb-persist-browse-$$"
      mkdir -p "$tmpmnt"
      if sudo mount -o loop,ro "$pfile" "$tmpmnt" 2>/dev/null; then
        _menu_subheader "Persistence contents (read-only)"
        sudo ls -la "$tmpmnt/" 2>/dev/null
        echo ""
        _menu_subheader "Files in /etc"
        sudo ls -1 "$tmpmnt/etc/" 2>/dev/null | head -20
        sudo umount "$tmpmnt" 2>/dev/null || true
      else
        _menu_error "Could not mount persistence"
      fi
      rmdir "$tmpmnt" 2>/dev/null || true
      ;;
    5)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set"
        return 1
      fi
      local vmp=""
      vmp=$(_resolve_ventoy_mount) || vmp=""
      local pfile; pfile=$(_uca_primary_persistence 2>/dev/null) || pfile=""
      if [[ -z "$pfile" ]]; then
        _menu_error "Persistence file not found (no profile primary, no discovered volume)"
        return 1
      fi
      _menu_info "Running fsck on persistence..."
      sudo fsck.ext4 -f "$pfile" 2>&1 || _menu_warn "fsck reported issues"
      ;;
    6)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        _menu_error "SELECTED_DEVICE not set"
        return 1
      fi
      _menu_subheader "Partition layout for $SELECTED_DEVICE"
      lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null || _menu_info "(lsblk failed)"
      echo ""
      _menu_subheader "Block device details"
      lsblk -b -o NAME,SIZE,TYPE,FSTYPE,LABEL "$SELECTED_DEVICE" 2>/dev/null | awk 'NR==1{print} NR>1{printf "%-12s %10d %s %s %s\n",$1,$2,$3,$4,$5}'
      ;;
    9)
      _uca_ventoy_doctor
      ;;
    7)
      # Rename a persistence volume FILE (not its filesystem label). Detects
      # whether the file is referenced by ventoy.json and warns — renaming a
      # primary overlay without updating ventoy.json will break boot routing.
      local vol; vol=$(_uca_select_volume) || { _menu_error "No volume found"; return 1; }
      printf "  Current : %s\n" "$vol"
      printf "  New filename (basename only, e.g. tooling.dat): "
      local newname; read -r newname
      [[ -z "$newname" ]] && { _menu_info "Cancelled"; return 0; }
      if [[ "$newname" =~ [/[:space:]] ]]; then
        _menu_error "Use a plain basename (no slashes/spaces)"; return 1
      fi
      local dest; dest="$(dirname "$vol")/$newname"
      [[ "$vol" == "$dest" ]] && { _menu_info "No change"; return 0; }
      [[ -e "$dest" ]] && { _menu_error "Destination exists: $dest"; return 1; }
      # Cross-check ventoy.json so we don't silently break the boot mapping.
      local m vj
      m=$(_uca_mount 2>/dev/null) && vj="$m/ventoy/ventoy.json"
      if [[ -n "${vj:-}" && -f "$vj" ]] && grep -qF "$(basename "$vol")" "$vj"; then
        _menu_warn "$(basename "$vol") is referenced in ventoy.json (boot mapping)."
        _menu_warn "Rename will break boot unless you ALSO update that file."
        _menu_confirm "Proceed anyway?" || return 0
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: mv '$vol' '$dest'"; return 0
      fi
      mv "$vol" "$dest" && _menu_success "Renamed: $vol -> $dest" \
        || _menu_error "Rename failed (file in use? cross-fs?)"
      ;;
    8)
      # Relabel an ext4 persistence volume. Guard the casper-rw label: casper
      # boot REQUIRES it on the primary overlay, so we refuse to remove it
      # without an explicit override.
      local vol; vol=$(_uca_select_volume) || { _menu_error "No volume found"; return 1; }
      local cur
      cur=$(sudo blkid -s LABEL -o value "$vol" 2>/dev/null || echo "")
      local type
      type=$(sudo blkid -s TYPE -o value "$vol" 2>/dev/null || echo "")
      printf "  Volume     : %s\n" "$vol"
      printf "  Current    : LABEL='%s' TYPE='%s'\n" "$cur" "$type"
      if [[ "$type" != "ext4" && "$type" != "ext3" && "$type" != "ext2" ]]; then
        _menu_error "e2label only supports ext2/3/4 (got '$type')"; return 1
      fi
      if [[ "$cur" == "casper-rw" ]]; then
        _menu_warn "This volume is the PRIMARY casper-rw overlay."
        _menu_warn "Renaming its label will break Ubuntu live-boot persistence."
        _menu_confirm "Are you absolutely sure (I will accept the boot risk)?" || return 0
      fi
      printf "  New label (max 16 chars, [A-Za-z0-9_-]): "
      local newlabel; read -r newlabel
      [[ -z "$newlabel" ]] && { _menu_info "Cancelled"; return 0; }
      if [[ ${#newlabel} -gt 16 || ! "$newlabel" =~ ^[A-Za-z0-9_-]+$ ]]; then
        _menu_error "Invalid label"; return 1
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: sudo e2label '$vol' '$newlabel'"; return 0
      fi
      # Run fsck first — e2label refuses to write to a mounted/dirty fs.
      if sudo fsck.ext4 -p "$vol" >/dev/null 2>&1 \
         && sudo e2label "$vol" "$newlabel"; then
        _menu_success "Relabel ok: $(basename "$vol") -> '$newlabel'"
      else
        _menu_error "Relabel failed (volume mounted? dirty? not ext4?)"
      fi
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

# ── Bash Profile Manager ────────────────────────────────────────────────────
# Two opt-in triggers auto-install llmrl: (a) choosing llama.cpp during
# Build Essentials, (b) installing the enhanced bash profile here. Both call
# this helper. Otherwise the bootstrapper is staged to USB persistence for a
# later manual run. Keeps llmrl out of the "default install everywhere" path.
_uca_auto_install_llmrl_after_profile() {
  local boot="$USB_DIR/scripts/setup-llmrl.sh"
  if [[ ! -f "$boot" ]]; then
    _menu_warn "llmrl bootstrapper missing at $boot"
    return 1
  fi
  if ! command -v npm >/dev/null 2>&1; then
    _menu_info "llmrl needs Node/npm. Install via Build Essentials (option 7) → node group, then re-run."
    return 0
  fi
  echo ""
  _menu_info "llmrl (HuggingFace model browser) pairs naturally with the enhanced shell —"
  _menu_info "instant 'llmrl search', 'llmrl show', and 'llmrl download' from your prompt."
  if _menu_confirm "Install llmrl now?"; then
    if [[ "$DRY_RUN" == "true" ]]; then
      _menu_info "DRY RUN: would bootstrap llmrl in /opt/llmrl with MODEL_DIR=$HOME/llm-models"
      return 0
    fi
    local target_dir="${HOME}/.local/share"
    mkdir -p "$target_dir"
    if ( cd "$target_dir" && MODEL_DIR="${HOME}/llm-models" bash "$boot" ); then
      _menu_success "llmrl installed at $target_dir/llmrl"
    else
      _menu_warn "llmrl install failed — see output above"
    fi
  else
    # Copy-to-persistence fallback: stage the bootstrapper on the mounted USB so
    # the user (or a future menu run) can install it without the repo nearby.
    local mnt; mnt=$(_resolve_ventoy_mount 2>/dev/null || echo "")
    if [[ -n "$mnt" && -d "$mnt" ]]; then
      local stage="$mnt/tools"
      mkdir -p "$stage" 2>/dev/null || true
      if cp "$boot" "$stage/setup-llmrl.sh" 2>/dev/null; then
        chmod +x "$stage/setup-llmrl.sh"
        _menu_info "Staged llmrl bootstrapper on USB: $stage/setup-llmrl.sh"
        _menu_info "Run later with: bash $stage/setup-llmrl.sh"
      fi
    fi
  fi
}

_run_bash_profile() {
  # CL-030: install target follows UCA_MODE.
  local install_root dest_label
  install_root=$(_uca_install_root) || install_root="$HOME"
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    dest_label="USB persistence ($install_root)"
  else
    dest_label="host ($install_root)"
  fi
  _menu_header "Bash Profile Manager"
  _menu_subheader "Target: ${dest_label}"
  echo ""
  _menu_item "1" "Install enhanced bash profile"                     "" ""
  _menu_item "2" "View current ~/.bashrc"                            "" ""
  _menu_item "3" "View enhanced profile (bash_enhanced.sh)"          "" ""
  _menu_item "4" "Source aliases into current shell"                 "" ""
  _menu_item "5" "Show all alias sources"                            "" "$install_root/*"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  local profile_dest="$install_root/bash_profile.sh"
  local alias_dest="$install_root/bash_aliases.sh"
  case "$choice" in
    1)
      local src="$USB_DIR/scripts/bash_enhanced.sh"
      if [[ ! -f "$src" ]]; then
        _menu_error "bash_enhanced.sh not found at $src"
        return 1
      fi
      if [[ -f "$profile_dest" ]]; then
        _menu_warn "Enhanced profile already exists at $profile_dest"
        _menu_confirm "Overwrite?" || return 0
      fi
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: Would copy $src -> $profile_dest"
        return 0
      fi
      mkdir -p "$install_root"
      cp "$src" "$profile_dest"
      chmod +x "$profile_dest"
      # The host's ~/.bashrc gets ONE source line that points at the resolved
      # location. In USB mode, the line still goes into host .bashrc (one-time
      # bridge write) so the operator's shell can find the profile on USB.
      local source_line="source \"$profile_dest\" 2>/dev/null || true"
      if ! grep -q "bash_profile.sh" "$HOME/.bashrc" 2>/dev/null && \
         ! grep -q "bash_profile_enhanced" "$HOME/.bashrc" 2>/dev/null; then
        echo "" >> "$HOME/.bashrc"
        echo "# USB-Hemlock enhanced profile (CL-030) — points at ${UCA_MODE^^} install root" >> "$HOME/.bashrc"
        echo "$source_line" >> "$HOME/.bashrc"
        _menu_success "Added source line to ~/.bashrc (one-time bridge write)"
      fi
      _menu_success "Enhanced profile installed at $profile_dest"
      _menu_info "Run: source ~/.bashrc  (or log out/in)"
      # Bash profile setup is one of two opt-in triggers for llmrl auto-install
      # (the other is choosing llama.cpp during essentials). Falls back to a
      # copy-to-persistence pattern so the user can install manually later.
      _uca_auto_install_llmrl_after_profile
      ;;
    2)
      if [[ -f "$HOME/.bashrc" ]]; then
        local total; total=$(wc -l < "$HOME/.bashrc")
        _menu_subheader "~/.bashrc ($total lines)"
        head -50 "$HOME/.bashrc"
        if [[ "$total" -gt 50 ]]; then
          _menu_info "... ($((total - 50)) more lines)"
        fi
      else
        _menu_info "No ~/.bashrc found"
      fi
      ;;
    3)
      local src="$USB_DIR/scripts/bash_enhanced.sh"
      if [[ -f "$src" ]]; then
        local total; total=$(wc -l < "$src")
        _menu_subheader "bash_enhanced.sh ($total lines)"
        head -60 "$src"
        if [[ "$total" -gt 60 ]]; then
          _menu_info "... ($((total - 60)) more lines)"
        fi
      else
        _menu_error "bash_enhanced.sh not found"
      fi
      ;;
    4)
      if [[ -f "$alias_dest" ]]; then
        # shellcheck disable=SC1090
        source "$alias_dest" 2>/dev/null && _menu_success "Aliases loaded from $alias_dest" || _menu_warn "Some aliases failed"
      elif [[ -f "$HOME/.bash_aliases_usb" ]]; then
        # Legacy fallback if user ran the old version of alias_manager.
        # shellcheck disable=SC1090
        source "$HOME/.bash_aliases_usb" 2>/dev/null && _menu_success "Aliases loaded (legacy ~/.bash_aliases_usb)" || _menu_warn "Some aliases failed"
      else
        _menu_error "No alias file at $alias_dest — create aliases first (menu option 3)"
      fi
      ;;
    5)
      _menu_subheader "~/.bashrc aliases"
      local rc_count; rc_count=$(grep -c "^alias " "$HOME/.bashrc" 2>/dev/null || echo 0)
      printf "  %s aliases\n" "$rc_count"
      echo ""
      _menu_subheader "~/.bash_aliases_usb"
      if [[ -f "$HOME/.bash_aliases_usb" ]]; then
        local al_count; al_count=$(grep -c "^alias " "$HOME/.bash_aliases_usb" 2>/dev/null || echo 0)
        printf "  %s aliases\n" "$al_count"
        echo ""
        _menu_subheader "First 20"
        grep "^alias " "$HOME/.bash_aliases_usb" 2>/dev/null | head -20
      else
        _menu_info "(not found)"
      fi
      echo ""
      _menu_subheader "~/.bash_profile_enhanced"
      if [[ -f "$HOME/.bash_profile_enhanced" ]]; then
        local lines; lines=$(wc -l < "$HOME/.bash_profile_enhanced")
        printf "  Installed (%s lines)\n" "$lines"
      else
        _menu_info "(not installed — use option 1)"
      fi
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

# ── Per-Device Config ───────────────────────────────────────────────────────
_run_device_config() {
  _menu_header "Device / Boot Profiles"
  _menu_subheader "USB-first — profiles travel on the drive"
  local cfgdir="$HOME/.config/usb-compute-automation"
  local cfgfile="$cfgdir/config.json"
  local pdir; pdir=$(_uca_profile_dir)
  echo ""
  _menu_info "Profile store: $pdir"
  _menu_info "Location     : $(_uca_profile_location_label)"
  _menu_info "A profile marked 'default' is auto-loaded at startup (autoboot)."
  echo ""
  _menu_item "1" "Show current device config"          "" ""
  _menu_item "2" "List all saved profiles"             "" ""
  _menu_item "3" "Save current as a profile"           "" ""
  _menu_item "4" "Load/switch profile"                 "" ""
  _menu_item "5" "Delete profile"                      "" ""
  _menu_item "6" "Generate host-id for current device" "" ""
  _menu_item "7" "Set default (autoboot) profile"      "" ""
  _menu_item "8" "Edit profile manifest"               "" "primary + data volumes"
  _menu_item "9" "Compile profile → ventoy.json"       "" "boot routing (backed up)"
  _menu_item "10" "Apply profile mounts to primary"    "" "systemd auto-mount"
  _menu_item "11" "Preview profile (read-only)"        "" ""
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1)
      echo ""
      printf "  ${BOLD}Device:${NC} %s\n" "${SELECTED_DEVICE:-<not set>}"
      printf "  ${BOLD}Config:${NC} %s\n" "$cfgfile"
      if [[ -f "$cfgfile" ]]; then
        echo ""
        _menu_subheader "Config contents"
        jq '.' "$cfgfile" 2>/dev/null || cat "$cfgfile"
      else
        _menu_error "No config file — run: usbctl config init"
      fi
      ;;
    2)
      echo ""
      _menu_subheader "Saved profiles ($pdir)"
      if [[ -d "$pdir" ]]; then
        local count=0 f
        for f in "$pdir"/*.json; do
          [[ -f "$f" ]] || continue
          count=$((count + 1))
          local dev hid def
          dev=$(jq -r '.device // "unknown"' "$f" 2>/dev/null)
          hid=$(jq -r '.host_id.host_id // "none"' "$f" 2>/dev/null)
          def=$(jq -r 'if .default then " [DEFAULT/autoboot]" else "" end' "$f" 2>/dev/null)
          echo "  $(basename "$f" .json)  device=$dev  host-id=$hid$def"
        done
        [[ "$count" -eq 0 ]] && echo "  (no profiles saved)"
      else
        echo "  (no profiles directory yet)"
      fi
      ;;
    3)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        log_error "SELECTED_DEVICE not set"
        return 1
      fi
      printf "  Profile name [auto from device]: "
      local pname; read -r pname
      local safename
      if [[ -n "$pname" ]]; then
        safename=$(echo "$pname" | sed 's|[^A-Za-z0-9._-]|_|g')
      else
        safename=$(echo "$SELECTED_DEVICE" | sed 's|/|_|g; s|^_||')
      fi
      local dest="$pdir/${safename}.json"
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: would save profile to $dest"; return 0
      fi
      if [[ ! -f "$cfgfile" ]]; then
        log_error "No config to save — run: usbctl config init"; return 1
      fi
      mkdir -p "$pdir" || { log_error "Cannot create $pdir"; return 1; }
      local tmp; tmp=$(mktemp)
      # Carry device + resolved iso/primary so the profile can drive autoboot.
      jq --arg dev "$SELECTED_DEVICE" \
         --arg iso "${UCA_ISO_PATH:-}" \
         '. + {device:$dev, iso:$iso, saved_at:(now|todate), default:(.default // false)}' \
         "$cfgfile" > "$tmp" && mv "$tmp" "$dest" \
        && log_success "Profile saved: $dest ($(_uca_profile_location_label))" \
        || { rm -f "$tmp"; log_error "Save failed"; }
      ;;
    4)
      echo ""
      _menu_subheader "Available profiles"
      if [[ ! -d "$pdir" ]]; then echo "  (none)"; return 0; fi
      local profiles=() f
      for f in "$pdir"/*.json; do
        [[ -f "$f" ]] || continue
        profiles+=("$f")
        local dev; dev=$(jq -r '.device // "unknown"' "$f" 2>/dev/null)
        echo "  ${#profiles[@]}) $(basename "$f" .json)  device=$dev"
      done
      if [[ ${#profiles[@]} -eq 0 ]]; then echo "  (none)"; return 0; fi
      printf "\n  Select profile number (0=cancel): "
      local pidx; read -r pidx
      [[ "$pidx" == "0" ]] && return 0
      if [[ "$pidx" =~ ^[0-9]+$ ]] && [[ "$pidx" -ge 1 && "$pidx" -le ${#profiles[@]} ]]; then
        local sel="${profiles[$((pidx - 1))]}"
        if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would load $(basename "$sel")"; return 0; fi
        cp "$sel" "$cfgfile"
        local dev; dev=$(jq -r '.device // "unknown"' "$sel" 2>/dev/null)
        [[ -n "$dev" && "$dev" != "unknown" ]] && export SELECTED_DEVICE="$dev"
        log_success "Loaded profile: $(basename "$sel" .json) (device=$dev)"
      else
        log_error "Invalid selection"
      fi
      ;;
    5)
      echo ""
      if [[ ! -d "$pdir" ]]; then echo "  (no profiles)"; return 0; fi
      local f
      for f in "$pdir"/*.json; do [[ -f "$f" ]] && echo "  $(basename "$f" .json)"; done
      printf "  Profile name to delete (0=cancel): "
      local dname; read -r dname
      [[ "$dname" == "0" || -z "$dname" ]] && return 0
      local target="$pdir/${dname}.json"
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would delete $target"; return 0; fi
      if [[ -f "$target" ]]; then rm -f "$target"; log_success "Deleted profile: $dname"
      else log_error "Profile not found: $dname"; fi
      ;;
    6)
      if [[ -z "${SELECTED_DEVICE:-}" ]]; then log_error "SELECTED_DEVICE not set"; return 1; fi
      log_info "Generating host-id for $SELECTED_DEVICE..."
      generate_host_id 2>/dev/null && log_success "Host-id generated" || log_warn "Host-id generation failed"
      ;;
    7)
      echo ""
      _menu_subheader "Set the default (autoboot) profile"
      if [[ ! -d "$pdir" ]]; then echo "  (no profiles)"; return 0; fi
      local profiles=() f
      for f in "$pdir"/*.json; do
        [[ -f "$f" ]] || continue
        profiles+=("$f")
        local d; d=$(jq -r 'if .default then "DEFAULT" else "" end' "$f" 2>/dev/null)
        echo "  ${#profiles[@]}) $(basename "$f" .json)  $d"
      done
      if [[ ${#profiles[@]} -eq 0 ]]; then echo "  (none)"; return 0; fi
      printf "\n  Number to set as default (0=clear all autoboot): "
      local sidx; read -r sidx
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would update default flags"; return 0; fi
      # Clear default on every profile first.
      for f in "${profiles[@]}"; do
        local tmp; tmp=$(mktemp); jq '.default=false' "$f" > "$tmp" 2>/dev/null && mv "$tmp" "$f" || rm -f "$tmp"
      done
      if [[ "$sidx" =~ ^[0-9]+$ ]] && [[ "$sidx" -ge 1 && "$sidx" -le ${#profiles[@]} ]]; then
        local t="${profiles[$((sidx - 1))]}"
        local tmp; tmp=$(mktemp); jq '.default=true' "$t" > "$tmp" 2>/dev/null && mv "$tmp" "$t" || rm -f "$tmp"
        log_success "Autoboot profile: $(basename "$t" .json) — applied at next launch"
      else
        log_success "Cleared autoboot — no profile auto-loads"
      fi
      ;;
    8)  _uca_profile_edit_manifest ;;
    9)  _uca_profile_compile_ventoy ;;
    10) _uca_profile_apply_mounts ;;
    11) _uca_profile_preview ;;
    0) return 0 ;;
    *) log_error "Invalid option: $choice" ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# Configurable USB Paths & Environment  (MOD-008 extension, FS-008)
# ════════════════════════════════════════════════════════════════════════════
# Every USB path is configurable so the file-tree schema can be whatever the
# user wants. Defaults derive from the live mount; overrides persist in a
# sourced KEY=VALUE file the user can edit by hand or via the menu.

UCA_CFG_DIR="${UCA_CONFIG_DIR:-$HOME/.config/usb-compute-automation}"
UCA_PATHS_CONF="$UCA_CFG_DIR/usb-paths.conf"
UCA_ENV_CONF="$UCA_CFG_DIR/usb-env.conf"

# Configurable values (defaults; overridden by usb-paths.conf when present).
: "${UCA_VENTOY_MOUNT:=}"             # explicit mount override; empty = auto-detect
: "${UCA_PERSISTENCE_DIR:=}"          # dir holding persistence volumes; empty = <mount>/persistence
: "${UCA_PERSISTENCE_VOLUMES:=}"      # colon-separated EXTRA volume paths (beyond auto-discovered)
: "${UCA_STARTUP_SCRIPT:=}"           # startup.sh path on USB; empty = <mount>/startup.sh
: "${UCA_ESSENTIALS_SCRIPT:=}"        # essentials installer path; empty = <mount>/scripts/setup-essentials.sh
: "${UCA_RCLOCAL_PATH:=etc/rc.local}" # rc.local path *within* a mounted persistence rootfs
: "${UCA_ISO_PATH:=}"                 # ISO to boot; empty = first *.iso on the mount
: "${UCA_QEMU_RAM:=4G}"
: "${UCA_QEMU_CPUS:=2}"
: "${UCA_QEMU_SSH_PORT:=2222}"
: "${UCA_BOOT_TARGET:=device}"        # device (whole USB) | iso

# ════════════════════════════════════════════════════════════════════════════
# Sudo Cache + Triple-Notification Consent  (CL-015 prep)
# ════════════════════════════════════════════════════════════════════════════
# Initial USB setup needs root for: ufw/port-forward edits, minimal host deps
# (qemu/sshd/tailscale), permission normalization. Goal: cache the sudo
# password once at session start, kill the cache cleanly at exit, and (when
# the user opts in) survive across sessions via the system keyring so they
# never re-paste it.
#
# Three policies — set once via triple-confirmation, persisted in sudo-policy:
#   encrypted = stored in libsecret (gnome-keyring/kwallet); script types it
#               in via `sudo -S`; password is NEVER printed back to the user.
#   session   = `sudo -v` keepalive for this menu run only; `sudo -k` on exit.
#   none      = legacy; sudo prompts on every call.
#
# Autoboot bypasses the whole flow — services are already running.

UCA_SUDO_POLICY_FILE="$UCA_CFG_DIR/sudo-policy"
UCA_SUDO_KEEPER_PID=""

_uca_autoboot_active() {
  # An autoboot profile is one marked default in the profile store. When that's
  # present, the headless/SSH/Tailscale layer is already running and the user
  # shouldn't have to elevate to use the interactive menu at all.
  local pdir; pdir=$(_uca_profile_dir 2>/dev/null) || return 1
  [[ -f "$pdir/default" ]]
}

_uca_sudo_consent_flow() {
  if [[ -f "$UCA_SUDO_POLICY_FILE" ]]; then
    UCA_SUDO_POLICY=$(<"$UCA_SUDO_POLICY_FILE")
    return 0
  fi
  _menu_header "Sudo Password Policy — first-run setup"
  _menu_subheader "HOST — root needed only for setup (firewall, ports, host deps, perms)"
  cat <<'POLICY'
  USB-Hemlock needs sudo briefly during INITIAL setup for:
    • UFW rules + port forwarding for headless/SSH access
    • Installing the minimal host packages (qemu, openssh, tailscale)
    • Normalizing config-file ownership so later menu runs DO NOT need sudo

  After initial setup, files in ~/.config/usb-compute-automation are owned by
  you and writable without root. Pick how the sudo password should be cached:

    [A] ENCRYPTED-AT-REST  Stored in system keyring (libsecret); script types
                           it in via `sudo -S`. Never displayed. Survives
                           reboots. Cleared by: virus quarantine purge --yes
                           OR `secret-tool clear application usb-hemlock-sudo`.
                           Requires: gnome-keyring or kwallet.

    [B] SESSION CACHE      `sudo -v` keepalive for THIS menu run only.
                           Cleared at exit. Re-prompted next time.

    [C] NO CACHE           OS default; prompts every elevation.
POLICY
  echo ""
  printf "  Choice [A/B/C, default B]: "
  local ch1; read -r ch1; ch1="${ch1:-B}"

  # Notification 2 — explain consequence
  echo ""
  case "$ch1" in
    [Aa])
      _menu_warn "ENCRYPTED-AT-REST: password stored in your system keyring."
      _menu_warn "Threat note: an attacker with a logged-in user session can"
      _menu_warn "  read the keyring. Keyring storage is obfuscation against"
      _menu_warn "  casual access, not root compromise."
      ;;
    [Bb])
      _menu_warn "SESSION CACHE: keepalive runs every 60s while menu is open."
      _menu_warn "  On exit/Ctrl-C, the cache is invalidated (sudo -k)."
      ;;
    *)
      _menu_warn "NO CACHE: each elevation re-prompts. Safest, most friction."
      ;;
  esac
  printf "  Confirm choice? [Y/n]: "
  local ch2; read -r ch2
  if [[ "$ch2" =~ ^[Nn]$ ]]; then
    _menu_info "Aborted — re-run the menu to choose again"
    return 1
  fi

  # Notification 3 — persistence commit
  echo ""
  _menu_info "Final confirmation — this saves the choice to:"
  _menu_info "  $UCA_SUDO_POLICY_FILE"
  _menu_info "Remove that file (or pick option in Diagnostics → Reset) to re-prompt."
  printf "  Save preference? [Y/n]: "
  local ch3; read -r ch3
  if [[ "$ch3" =~ ^[Nn]$ ]]; then
    _menu_info "Not saved — will ask again next run"
    return 1
  fi

  case "$ch1" in
    [Aa]) UCA_SUDO_POLICY="encrypted" ;;
    [Bb]) UCA_SUDO_POLICY="session"   ;;
    *)    UCA_SUDO_POLICY="none"      ;;
  esac
  mkdir -p "$UCA_CFG_DIR" 2>/dev/null
  printf '%s\n' "$UCA_SUDO_POLICY" > "$UCA_SUDO_POLICY_FILE"
  chmod 600 "$UCA_SUDO_POLICY_FILE" 2>/dev/null
  _menu_success "Policy saved: $UCA_SUDO_POLICY"
}

# Prime the sudo cache according to the chosen policy. Idempotent — call at
# the top of every action that may elevate; subsequent calls within a session
# are near-free.
_uca_sudo_init() {
  if _uca_autoboot_active; then
    return 0   # autoboot handles services; interactive menu shouldn't elevate
  fi
  _uca_sudo_consent_flow || return 0
  case "$UCA_SUDO_POLICY" in
    encrypted)
      if command -v secret-tool >/dev/null 2>&1; then
        local pass
        pass=$(secret-tool lookup application usb-hemlock-sudo 2>/dev/null || true)
        if [[ -z "$pass" ]]; then
          _menu_info "First-time encrypted-at-rest setup — enter sudo password"
          _menu_info "(stored in keyring, never displayed again)"
          read -rsp "  Password: " pass; echo
          printf '%s' "$pass" | secret-tool store --label="USB-Hemlock sudo" \
            application usb-hemlock-sudo 2>/dev/null \
            || { _menu_warn "Could not write to keyring — falling back to session cache"
                 sudo -v; unset pass; return 0; }
        fi
        printf '%s\n' "$pass" | sudo -S -v 2>/dev/null \
          || { _menu_warn "Cached password rejected; clearing keyring entry"
               secret-tool clear application usb-hemlock-sudo 2>/dev/null || true; }
        unset pass
      else
        _menu_warn "secret-tool (libsecret-tools) not installed — using session cache"
        sudo -v
      fi
      ;;
    session) sudo -v ;;
    none)    : ;;
  esac
  if [[ "$UCA_SUDO_POLICY" != "none" && -z "$UCA_SUDO_KEEPER_PID" ]]; then
    ( while true; do sudo -n true 2>/dev/null || exit; sleep 60; done ) &
    UCA_SUDO_KEEPER_PID=$!
  fi
}

_uca_sudo_cleanup() {
  if [[ -n "$UCA_SUDO_KEEPER_PID" ]]; then
    kill "$UCA_SUDO_KEEPER_PID" 2>/dev/null || true
    UCA_SUDO_KEEPER_PID=""
  fi
  # Session policy: invalidate cache on exit. Encrypted policy: leave the
  # keyring entry intact so next run is seamless.
  if [[ "${UCA_SUDO_POLICY:-}" == "session" ]]; then
    sudo -k 2>/dev/null || true
  fi
}

# Normalize ownership + permissions on UCA-managed config and profile dirs.
# Goal: after initial setup, every menu action the user takes runs without
# sudo. We chown back to $USER (in case an earlier sudo'd write left files
# as root), reset dirs to 755, regular files to 644, and secrets to 600.
_uca_normalize_permissions() {
  local cfg="$UCA_CFG_DIR"
  [[ -d "$cfg" ]] || return 0
  if command -v sudo >/dev/null 2>&1; then
    sudo -n chown -R "${USER}:${USER}" "$cfg" 2>/dev/null || true
  fi
  find "$cfg" -type d -exec chmod 755 {} \; 2>/dev/null || true
  find "$cfg" -type f -exec chmod 644 {} \; 2>/dev/null || true
  # Secrets keep 600
  for f in "$cfg/sudo-policy" "$cfg/usb-paths.conf" "$cfg/usb-env.conf"; do
    [[ -f "$f" ]] && chmod 600 "$f" 2>/dev/null || true
  done
}

_uca_load_paths_config() {
  if [[ -f "$UCA_PATHS_CONF" ]]; then
    # shellcheck disable=SC1090
    source "$UCA_PATHS_CONF" 2>/dev/null || _menu_warn "Could not load $UCA_PATHS_CONF"
  fi
  if [[ -f "$UCA_ENV_CONF" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$UCA_ENV_CONF" 2>/dev/null || true
    set +a
  fi
}

_uca_save_paths_config() {
  mkdir -p "$UCA_CFG_DIR" 2>/dev/null || true
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: would write $UCA_PATHS_CONF"
    return 0
  fi
  cat > "$UCA_PATHS_CONF" <<EOF
# USB-Hemlock configurable paths — sourced by menu.sh at startup.
# Edit by hand or via menu option "USB Paths & Environment".
# Empty values mean "auto-detect / use default".
UCA_VENTOY_MOUNT="$UCA_VENTOY_MOUNT"
UCA_PERSISTENCE_DIR="$UCA_PERSISTENCE_DIR"
UCA_PERSISTENCE_VOLUMES="$UCA_PERSISTENCE_VOLUMES"
UCA_STARTUP_SCRIPT="$UCA_STARTUP_SCRIPT"
UCA_ESSENTIALS_SCRIPT="$UCA_ESSENTIALS_SCRIPT"
UCA_RCLOCAL_PATH="$UCA_RCLOCAL_PATH"
UCA_ISO_PATH="$UCA_ISO_PATH"
UCA_QEMU_RAM="$UCA_QEMU_RAM"
UCA_QEMU_CPUS="$UCA_QEMU_CPUS"
UCA_QEMU_SSH_PORT="$UCA_QEMU_SSH_PORT"
UCA_BOOT_TARGET="$UCA_BOOT_TARGET"
UCA_INSTALL_TARGET="$UCA_INSTALL_TARGET"
EOF
  _menu_success "Saved $UCA_PATHS_CONF"
}

# Effective (override-or-default) path resolvers.
_uca_mount() {
  if [[ -n "$UCA_VENTOY_MOUNT" ]]; then printf '%s\n' "$UCA_VENTOY_MOUNT"; return 0; fi
  _resolve_ventoy_mount
}
_uca_persistence_dir() {
  if [[ -n "$UCA_PERSISTENCE_DIR" ]]; then printf '%s\n' "$UCA_PERSISTENCE_DIR"; return 0; fi
  local m; m=$(_uca_mount) || return 1
  printf '%s/persistence\n' "$m"
}
_uca_startup_script() {
  if [[ -n "$UCA_STARTUP_SCRIPT" ]]; then printf '%s\n' "$UCA_STARTUP_SCRIPT"; return 0; fi
  local m; m=$(_uca_mount) || return 1
  printf '%s/startup.sh\n' "$m"
}

# Resolve the "primary" persistence file (the casper-rw rootfs overlay):
#   1. If a Phase-2 profile is loaded with .primary.file → use that.
#   2. Else prefer the volume labelled `casper-rw` (the actual rootfs overlay).
#   3. Else fall back to the legacy ubuntu-persistence.dat path.
#   4. Else use the first discovered volume as last resort.
# CL-034: a multi-volume USB (hemlock.dat + ubuntu-persistence.dat + ...) must
# pick the rootfs overlay, NOT whichever sorts first by name. Without this fix
# the menu would report hemlock.dat as "primary" because h < u alphabetically.
# Echoes the absolute path on stdout. Returns 1 if nothing resolves.
_uca_primary_persistence() {
  local m; m=$(_uca_mount 2>/dev/null) || return 1
  # 1) Active profile primary.
  local pdir prof
  pdir=$(_uca_profile_dir 2>/dev/null) || pdir=""
  if [[ -n "$pdir" && -d "$pdir" ]] && command -v jq >/dev/null 2>&1; then
    for prof in "$pdir"/*.json; do
      [[ -f "$prof" ]] || continue
      if [[ "$(jq -r '.default // false' "$prof" 2>/dev/null)" == "true" ]]; then
        local rel; rel=$(jq -r '.primary.file // empty' "$prof" 2>/dev/null)
        if [[ -n "$rel" && -f "$m/${rel#/}" ]]; then
          printf '%s\n' "$m/${rel#/}"; return 0
        fi
      fi
    done
  fi
  # 2) Look for a volume labelled `casper-rw` — that's the actual rootfs overlay.
  local v
  while IFS= read -r v; do
    [[ -f "$v" ]] || continue
    local lbl
    lbl=$(sudo -n blkid -o value -s LABEL "$v" 2>/dev/null || echo "")
    if [[ "$lbl" == "casper-rw" ]]; then
      printf '%s\n' "$v"; return 0
    fi
  done < <(_uca_list_volumes 2>/dev/null)
  # 3) Legacy default filename.
  local legacy="$m/persistence/ubuntu-persistence.dat"
  [[ -f "$legacy" ]] && { printf '%s\n' "$legacy"; return 0; }
  # 4) First discovered volume — last resort, may be a data volume.
  local first
  first=$(_uca_list_volumes 2>/dev/null | head -1)
  [[ -n "$first" && -f "$first" ]] && { printf '%s\n' "$first"; return 0; }
  return 1
}

# ── Environment detection (USB boot vs USB plugged vs native) ───────────────
# Returns one of:
#   usb-boot     — booted from the USB live env (rootfs is a loop-mounted .dat,
#                  or kernel cmdline mentions casper)
#   usb-mounted  — running on a regular host but a Ventoy USB is plugged in
#   native       — running on a regular host, no USB visible
# Honors UCA_ENVIRONMENT if pre-set; persists detected value to usb-paths.conf.
_uca_detect_environment() {
  [[ -n "${UCA_ENVIRONMENT:-}" ]] && { printf '%s\n' "$UCA_ENVIRONMENT"; return 0; }

  # 1) Live-boot signals.
  if [[ -r /proc/cmdline ]] && grep -qE '(^|\s)(boot=casper|casper|live-media)' /proc/cmdline 2>/dev/null; then
    printf 'usb-boot\n'; return 0
  fi
  # findmnt: source of "/" — if it's a loop device backed by a .dat, we're
  # running off a persistence overlay.
  local root_src
  root_src=$(findmnt -no SOURCE / 2>/dev/null || echo "")
  if [[ "$root_src" == /dev/loop* ]]; then
    local back
    back=$(losetup -no BACK-FILE "$root_src" 2>/dev/null || true)
    [[ "$back" == *.dat || "$back" == *.img ]] && { printf 'usb-boot\n'; return 0; }
  fi
  # rootfs label is casper-rw or the overlay file system says casper
  if findmnt -no FSTYPE,SOURCE / 2>/dev/null | grep -qE 'overlay.*casper|aufs.*casper'; then
    printf 'usb-boot\n'; return 0
  fi

  # 2) USB plugged but not live-booted? Reuse the existing detector.
  local devs; devs=$(_detect_usb_devices 2>/dev/null || echo "")
  if [[ -n "${devs// /}" ]]; then printf 'usb-mounted\n'; return 0; fi

  # 3) Default.
  printf 'native\n'
}

# Get-or-prompt-and-persist. Always returns a value on stdout.
_uca_resolve_environment() {
  local env
  env=$(_uca_detect_environment)
  # If the detector returned a strong signal, trust it. We only prompt when
  # the user has neither set UCA_ENVIRONMENT nor we got a confident answer
  # AND we are running interactively on a TTY.
  if [[ -z "${UCA_ENVIRONMENT:-}" && "$env" == "native" && -t 0 ]]; then
    # Be quiet: only prompt if the user-paths config doesn't yet have a value.
    if [[ ! -f "$UCA_PATHS_CONF" ]] || ! grep -q '^UCA_ENVIRONMENT=' "$UCA_PATHS_CONF" 2>/dev/null; then
      {
        echo ""
        echo "  Environment auto-detect inconclusive."
        echo "    1) USB persistence (live boot)"
        echo "    2) Standard (native host)"
        echo "    3) Re-scan"
        printf "  Choose [2]: "
      } >&2
      local ans; read -r ans; ans="${ans:-2}"
      case "$ans" in
        1) env="usb-boot" ;;
        3) env=$(_uca_detect_environment) ;;
        *) env="native" ;;
      esac
    fi
  fi
  UCA_ENVIRONMENT="$env"
  export UCA_ENVIRONMENT
  # Persist quietly; respect DRY_RUN.
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    mkdir -p "$UCA_CFG_DIR" 2>/dev/null || true
    if [[ -f "$UCA_PATHS_CONF" ]]; then
      grep -v '^UCA_ENVIRONMENT=' "$UCA_PATHS_CONF" > "$UCA_PATHS_CONF.tmp" 2>/dev/null || true
      mv "$UCA_PATHS_CONF.tmp" "$UCA_PATHS_CONF"
    fi
    printf 'UCA_ENVIRONMENT="%s"\n' "$env" >> "$UCA_PATHS_CONF" 2>/dev/null || true
  fi
  printf '%s\n' "$env"
}

# ── Boot/device profiles — USB-first storage (Phase 1) ──────────────────────
# Profiles live ON the Ventoy drive (portable, travel with the USB) under
# /<mount>/usb-hemlock/profiles, falling back to the host config dir when the
# USB is not mounted/writable. Each profile is a small JSON describing the
# device, ISO, primary persistence + data volumes, env, and a 'default' flag
# that drives auto-load at startup. (Agent/crew ROLE orchestration is Hemlock's
# job; a volume's "role" here is only a storage-routing hint.)
UCA_USB_SUBDIR="usb-hemlock"

_uca_profile_dir() {
  local m; m=$(_uca_mount 2>/dev/null) || m=""
  if [[ -n "$m" && -d "$m" && -w "$m" ]]; then
    printf '%s/%s/profiles\n' "$m" "$UCA_USB_SUBDIR"; return 0
  fi
  printf '%s/profiles\n' "$UCA_CFG_DIR"
}

# Where is a given profile actually stored (USB or host)? For display.
_uca_profile_location_label() {
  local pdir; pdir=$(_uca_profile_dir)
  case "$pdir" in
    "$UCA_CFG_DIR"/*) printf 'HOST (USB not mounted/writable)';;
    *) printf 'USB drive (portable)';;
  esac
}

# At startup, if a USB profile is marked "default": true, apply it: select its
# device and export its env block before auto-detection runs.
_uca_autoload_profile() {
  local pdir; pdir=$(_uca_profile_dir) || return 0
  [[ -d "$pdir" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  local def="" f
  for f in "$pdir"/*.json; do
    [[ -f "$f" ]] || continue
    if [[ "$(jq -r '.default // false' "$f" 2>/dev/null)" == "true" ]]; then def="$f"; break; fi
  done
  [[ -n "$def" ]] || return 0
  log_info "Auto-loading default USB profile: $(basename "$def" .json)"
  local dev; dev=$(jq -r '.device // empty' "$def" 2>/dev/null)
  [[ -n "$dev" && -b "$dev" ]] && export SELECTED_DEVICE="$dev"
  # Optional path overrides the profile may carry.
  local iso; iso=$(jq -r '.iso // empty' "$def" 2>/dev/null); [[ -n "$iso" ]] && UCA_ISO_PATH="$iso"
  local prim; prim=$(jq -r '.primary // empty' "$def" 2>/dev/null)
  [[ -n "$prim" ]] && UCA_PERSISTENCE_VOLUMES="$prim${UCA_PERSISTENCE_VOLUMES:+:$UCA_PERSISTENCE_VOLUMES}"
  # Env block. CL-026 / SPEC-T04 (MOD-007): HEMLOCK_ENABLED is BLACKLISTED
  # from profile auto-export. Hemlock is opt-in via --hemlock/-H or an
  # explicit shell export; a stored profile must NEVER silently enable it.
  # If a profile previously stored HEMLOCK_ENABLED, we log a warning so the
  # user knows their profile would have enabled it (and how to do it
  # explicitly if they actually want that).
  local k v
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    if [[ "$k" == "HEMLOCK_ENABLED" ]]; then
      log_warn "Profile '$def' contains HEMLOCK_ENABLED — ignored per SPEC-T04 (use --hemlock to opt in)"
      continue
    fi
    v=$(jq -r --arg k "$k" '.env[$k] // empty' "$def" 2>/dev/null)
    export "$k=$v"
  done < <(jq -r '.env // {} | keys[]?' "$def" 2>/dev/null)
}

# List persistence volumes: auto-discovered *.dat/*.img in the persistence dir,
# plus any colon-separated extras in UCA_PERSISTENCE_VOLUMES. Deduplicated.
_uca_list_volumes() {
  local pdir; pdir=$(_uca_persistence_dir 2>/dev/null) || pdir=""
  {
    if [[ -n "$pdir" && -d "$pdir" ]]; then
      local f
      for f in "$pdir"/*.dat "$pdir"/*.img; do
        [[ -f "$f" ]] && printf '%s\n' "$f"
      done
    fi
    if [[ -n "$UCA_PERSISTENCE_VOLUMES" ]]; then
      local IFS=':' extra
      for extra in $UCA_PERSISTENCE_VOLUMES; do
        [[ -n "$extra" && -f "$extra" ]] && printf '%s\n' "$extra"
      done
    fi
  } | awk '!seen[$0]++'
}

# CL-033: Reserved bytes left untouched on the USB for config files / scripts /
# ventoy.json / profiles / etc. Hard floor regardless of total USB size.
# 256 MiB = 256 * 1024 * 1024 = 268435456
: "${UCA_RESERVED_BYTES:=268435456}"

# CL-033: Compute the max NEW persistence volume size (in MiB) that can be
# created on the currently mounted USB without violating the reservation or
# overrunning existing volumes. Returns 0 with size on stdout, or 1 if nothing
# can fit.
_uca_max_new_volume_mib() {
  local pdir; pdir=$(_uca_persistence_dir 2>/dev/null) || return 1
  [[ -d "$pdir" ]] || return 1
  # df -B1 returns free bytes for the filesystem holding the persistence dir.
  local free_bytes
  free_bytes=$(df -B1 --output=avail "$pdir" 2>/dev/null | tail -1 | tr -d ' ')
  [[ -n "$free_bytes" && "$free_bytes" -gt 0 ]] || return 1
  local usable=$((free_bytes - UCA_RESERVED_BYTES))
  [[ "$usable" -le 0 ]] && return 1
  # Round down to whole MiB.
  printf '%d\n' "$((usable / 1024 / 1024))"
}

# CL-033: Validate a requested persistence size in MiB against current free
# space (minus reservation). Echoes nothing on success, an error on stderr +
# returns 1 on failure.
_uca_validate_persistence_size_mib() {
  local requested_mib="$1"
  [[ -z "$requested_mib" || ! "$requested_mib" =~ ^[0-9]+$ ]] && {
    echo "Invalid size (must be a positive integer in MiB)" >&2; return 1
  }
  [[ "$requested_mib" -lt 256 ]] && {
    echo "Minimum persistence size is 256MiB (got ${requested_mib}MiB)" >&2; return 1
  }
  local max_mib; max_mib=$(_uca_max_new_volume_mib 2>/dev/null) || {
    echo "Could not compute available space on USB" >&2; return 1
  }
  if [[ "$requested_mib" -gt "$max_mib" ]]; then
    local reserved_mib=$((UCA_RESERVED_BYTES / 1024 / 1024))
    cat >&2 <<ERR
Requested ${requested_mib}MiB exceeds max ${max_mib}MiB available.
  - ${reserved_mib}MiB is reserved for USB-Hemlock configs/scripts/profiles.
  - Existing persistence volumes already consume some space.
  Shrink the size, delete an existing volume, or pick a larger USB.
ERR
    return 1
  fi
  return 0
}

# Choose a persistence volume. Echoes the path on stdout; prompts on stderr.
# 0 volumes -> return 1; 1 volume -> auto; many -> numbered prompt.
_uca_select_volume() {
  local vols=()
  while IFS= read -r v; do [[ -n "$v" ]] && vols+=("$v"); done < <(_uca_list_volumes)
  if [[ ${#vols[@]} -eq 0 ]]; then return 1; fi
  if [[ ${#vols[@]} -eq 1 ]]; then printf '%s\n' "${vols[0]}"; return 0; fi
  {
    echo ""
    echo "  Multiple persistence volumes found:"
    local i=1 v
    for v in "${vols[@]}"; do
      printf "    %d) %s (%s)\n" "$i" "$(basename "$v")" "$(du -h "$v" 2>/dev/null | cut -f1 || echo '?')"
      i=$((i + 1))
    done
    printf "  Select volume [1]: "
  } >&2
  local idx; read -r idx; idx="${idx:-1}"
  if [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -ge 1 && "$idx" -le ${#vols[@]} ]]; then
    printf '%s\n' "${vols[$((idx - 1))]}"; return 0
  fi
  return 1
}

# ── Profile manifest helpers (Phase 2 — modular multi-state) ────────────────
# A profile is a portable JSON describing how to assemble a boot:
#   device       /dev/sdX                       (set at save time)
#   iso          "/name.iso"                    (relative to USB mount)
#   primary      { file:"/persistence/tooling.dat", label:"casper-rw" }
#   data_volumes [ {file, mount, role, options?}, ... ]
#   env          { KEY: VALUE, ... }            (written to /etc/environment)
#   default      bool                           (autoboot on menu.sh launch)
#   boot_mode    "ventoy" | "qemu"              (qemu = use opt 20→7 for ISO)
#   notes        free-form
#
# Operations:
#   compile  -> write Ventoy persistence plugin (ISO + primary overlay)
#   apply    -> loop-mount primary, install systemd auto-mount + docker drop-in
#   preview  -> show planned effect, read-only

UCA_VOL_MOUNT_SCRIPT="/usr/local/sbin/uca-mount-volumes.sh"
UCA_VOL_SYSTEMD_UNIT="/etc/systemd/system/uca-volumes.service"

_uca_profile_validate() {
  local f="$1"
  [[ -f "$f" ]] || { echo "missing: $f" >&2; return 1; }
  jq -e . "$f" >/dev/null 2>&1 || { echo "invalid JSON: $f" >&2; return 1; }
  local bm; bm=$(jq -r '.boot_mode // "ventoy"' "$f")
  if [[ "$bm" == "ventoy" ]]; then
    jq -e '.primary.file' "$f" >/dev/null 2>&1 || { echo "missing .primary.file (boot_mode=ventoy)" >&2; return 1; }
    jq -e '.iso'          "$f" >/dev/null 2>&1 || { echo "missing .iso (boot_mode=ventoy)" >&2; return 1; }
  fi
  return 0
}

# Pick a profile interactively. Echoes path on stdout; prompts on stderr.
_uca_pick_profile() {
  local pdir; pdir=$(_uca_profile_dir)
  [[ -d "$pdir" ]] || { echo "no profile dir" >&2; return 1; }
  local files=() f
  for f in "$pdir"/*.json; do [[ -f "$f" ]] && files+=("$f"); done
  [[ ${#files[@]} -eq 0 ]] && { echo "no profiles saved" >&2; return 1; }
  if [[ ${#files[@]} -eq 1 ]]; then printf '%s\n' "${files[0]}"; return 0; fi
  {
    echo ""
    echo "  Profiles:"
    local i=1
    for f in "${files[@]}"; do printf "    %d) %s\n" "$i" "$(basename "$f" .json)"; i=$((i + 1)); done
    printf "  Select [1]: "
  } >&2
  local idx; read -r idx; idx="${idx:-1}"
  [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#files[@]} )) || return 1
  printf '%s\n' "${files[$((idx - 1))]}"
}

# Edit a profile's structured fields: set primary, add/remove data volumes,
# edit env, or open the whole JSON in $EDITOR.
_uca_profile_edit_manifest() {
  local p; p=$(_uca_pick_profile) || { _menu_error "no profile"; return 1; }
  _menu_subheader "Editing: $(basename "$p" .json)"
  echo ""
  _menu_item "1" "Show current manifest"            "" ""
  _menu_item "2" "Set primary overlay (rootfs)"     "" "tooling.dat etc."
  _menu_item "3" "Add a data volume"                "" "hemlock/models/docker/custom"
  _menu_item "4" "Remove a data volume"             "" ""
  _menu_item "5" "Set boot_mode (ventoy/qemu)"      "" "qemu = different ISO"
  _menu_item "6" "Set ISO"                          "" ""
  _menu_item "7" "Open full JSON in \$EDITOR"        "" ""
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local c; read -r c
  local tmp
  case "$c" in
    1) jq '.' "$p" ;;
    2)
      local pdir_on_usb; pdir_on_usb=$(_uca_persistence_dir 2>/dev/null) || pdir_on_usb=""
      echo ""
      if [[ -n "$pdir_on_usb" && -d "$pdir_on_usb" ]]; then
        echo "  Volumes on USB ($pdir_on_usb):"
        ls -1 "$pdir_on_usb"/*.dat "$pdir_on_usb"/*.img 2>/dev/null | sed 's|.*|    & |'
      fi
      printf "  Primary file path (relative to USB mount, e.g. /persistence/tooling.dat): "
      local pf; read -r pf
      [[ -z "$pf" ]] && return 0
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: set primary.file=$pf"; return 0; fi
      tmp=$(mktemp)
      jq --arg pf "$pf" '.primary = (.primary // {}) + {file:$pf, label:(.primary.label // "casper-rw")}' "$p" > "$tmp" \
        && mv "$tmp" "$p" && _menu_success "Set primary -> $pf" \
        || { rm -f "$tmp"; _menu_error "Update failed"; }
      ;;
    3)
      printf "  Data volume file (e.g. /persistence/hemlock.dat): "; local df; read -r df; [[ -z "$df" ]] && return 0
      printf "  Mount point inside the booted system (e.g. /opt/hemlock): "; local dm; read -r dm; [[ -z "$dm" ]] && return 0
      echo   "  Role hint (tooling|hemlock|models|docker|custom)"
      printf "    Note: 'docker' role triggers a docker.service drop-in (After=uca-volumes)\n"
      printf "  Role [custom]: "; local dr; read -r dr; dr="${dr:-custom}"
      printf "  Mount options [defaults,nofail]: "; local do_; read -r do_; do_="${do_:-defaults,nofail}"
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: add data_volume {$df -> $dm, role=$dr}"; return 0; fi
      tmp=$(mktemp)
      jq --arg f "$df" --arg m "$dm" --arg r "$dr" --arg o "$do_" \
         '.data_volumes = ((.data_volumes // []) + [{file:$f, mount:$m, role:$r, options:$o}])' \
         "$p" > "$tmp" && mv "$tmp" "$p" && _menu_success "Added data volume: $df -> $dm ($dr)" \
        || { rm -f "$tmp"; _menu_error "Update failed"; }
      ;;
    4)
      local rows; rows=$(jq -c '.data_volumes[]?' "$p" 2>/dev/null)
      [[ -z "$rows" ]] && { _menu_info "(no data volumes)"; return 0; }
      local i=0
      while IFS= read -r row; do
        i=$((i + 1))
        printf "  %d) %s -> %s\n" "$i" "$(jq -r .file <<<"$row")" "$(jq -r .mount <<<"$row")"
      done <<< "$rows"
      printf "  Number to remove (0=cancel): "; local rm_idx; read -r rm_idx
      [[ "$rm_idx" == "0" || -z "$rm_idx" ]] && return 0
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: remove data_volume #$rm_idx"; return 0; fi
      tmp=$(mktemp)
      jq --argjson i "$((rm_idx - 1))" 'del(.data_volumes[$i])' "$p" > "$tmp" \
        && mv "$tmp" "$p" && _menu_success "Removed data_volume #$rm_idx" \
        || { rm -f "$tmp"; _menu_error "Update failed"; }
      ;;
    5)
      printf "  boot_mode (ventoy|qemu) [ventoy]: "; local bm; read -r bm; bm="${bm:-ventoy}"
      if [[ "$bm" != "ventoy" && "$bm" != "qemu" ]]; then _menu_error "invalid"; return 1; fi
      tmp=$(mktemp); jq --arg m "$bm" '.boot_mode=$m' "$p" > "$tmp" && mv "$tmp" "$p" && _menu_success "boot_mode=$bm"
      ;;
    6)
      printf "  ISO path (relative to USB mount): "; local iso; read -r iso; [[ -z "$iso" ]] && return 0
      tmp=$(mktemp); jq --arg i "$iso" '.iso=$i' "$p" > "$tmp" && mv "$tmp" "$p" && _menu_success "iso=$iso"
      ;;
    7) ${EDITOR:-nano} "$p"; _uca_profile_validate "$p" >/dev/null 2>&1 || _menu_warn "manifest now fails validation" ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $c" ;;
  esac
}

# Compile a profile -> Ventoy persistence plugin in ventoy.json (with backup).
_uca_profile_compile_ventoy() {
  local p; p=$(_uca_pick_profile) || { _menu_error "no profile"; return 1; }
  local err; err=$(_uca_profile_validate "$p" 2>&1) || { _menu_error "$err"; return 1; }
  local bm; bm=$(jq -r '.boot_mode // "ventoy"' "$p")
  if [[ "$bm" != "ventoy" ]]; then
    _menu_info "boot_mode='$bm' — not compiled to ventoy.json (use Access & Boot → 7 to launch ISO in QEMU)"
    return 0
  fi
  local iso primary; iso=$(jq -r '.iso' "$p"); primary=$(jq -r '.primary.file' "$p")
  local m; m=$(_uca_mount 2>/dev/null) || { _menu_error "ventoy not mounted"; return 1; }
  local vj="$m/ventoy/ventoy.json"
  _menu_info "Profile : $(basename "$p" .json)"
  _menu_info "ISO     : $iso"
  _menu_info "Primary : $primary"
  _menu_info "Target  : $vj"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: would back up $vj and write persistence plugin"
    return 0
  fi
  _menu_confirm "Write ventoy.json now? (backed up first)" || return 0
  mkdir -p "$m/ventoy" 2>/dev/null || true
  if [[ -f "$vj" ]]; then local b; b=$(_uca_ventoy_json_backup "$vj") && _menu_info "Backup: $b"; fi
  local tmp; tmp=$(mktemp)
  if [[ -f "$vj" ]]; then
    jq --arg iso "$iso" --arg bk "$primary" \
       '.persistence = [{image:$iso, backend:$bk, autosel:1}]' "$vj" > "$tmp" \
      || { rm -f "$tmp"; _menu_error "jq merge failed"; return 1; }
  else
    jq -n --arg iso "$iso" --arg bk "$primary" \
       '{persistence:[{image:$iso, backend:$bk, autosel:1}]}' > "$tmp" \
      || { rm -f "$tmp"; _menu_error "jq build failed"; return 1; }
  fi
  mv "$tmp" "$vj" && _menu_success "Wrote $vj"
  _menu_info "Run the Ventoy.json Doctor (12→9) to verify."
}

# Generate the in-rootfs mount script body from a profile.
_uca_render_mount_script() {
  local p="$1"
  cat <<'HEAD'
#!/usr/bin/env bash
# Auto-generated by USB-Hemlock — regenerate via menu (15→10). DO NOT hand-edit.
set -u
LOG=/var/log/uca-volumes.log
mkdir -p /var/log; : >"$LOG"
log(){ echo "[uca-volumes] $*" | tee -a "$LOG" >&2; }

# Find the USB by its Ventoy label (path-agnostic).
USB_MNT=""
for try in 1 2 3 4 5; do
  USB_MNT=$(findmnt -nr -o TARGET -S "LABEL=Ventoy" 2>/dev/null | head -1)
  [[ -n "$USB_MNT" ]] && break
  USB_MNT=$(lsblk -no MOUNTPOINT,LABEL 2>/dev/null | awk '$2=="Ventoy"{print $1; exit}')
  [[ -n "$USB_MNT" ]] && break
  sleep 1
done
[[ -z "$USB_MNT" ]] && { log "USB (LABEL=Ventoy) not mounted; nothing to do"; exit 0; }
log "USB at $USB_MNT"

mount_vol(){
  local rel="$1" mnt="$2" opts="${3:-defaults,nofail}"
  local file="$USB_MNT$rel"
  [[ -f "$file" ]] || { log "  miss: $file"; return 0; }
  mkdir -p "$mnt"
  mountpoint -q "$mnt" && { log "  already: $mnt"; return 0; }
  if mount -o "loop,$opts" "$file" "$mnt"; then log "  mounted: $file -> $mnt"
  else log "  FAILED: $file -> $mnt"; fi
}

HEAD
  jq -r '.data_volumes[]? | "mount_vol " + (.file|@sh) + " " + (.mount|@sh) + " " + ((.options // "defaults,nofail")|@sh)' "$p"
  echo ""
  echo 'log "done"'
}

# Apply a profile: loop-mount primary; install mount script + systemd unit;
# (optionally) install docker.service drop-in; write env to /etc/environment.
_uca_profile_apply_mounts() {
  local p; p=$(_uca_pick_profile) || { _menu_error "no profile"; return 1; }
  local err; err=$(_uca_profile_validate "$p" 2>&1) || { _menu_error "$err"; return 1; }
  local bm; bm=$(jq -r '.boot_mode // "ventoy"' "$p")
  [[ "$bm" != "ventoy" ]] && _menu_warn "boot_mode='$bm' — apply assumes a Linux primary overlay"
  local m; m=$(_uca_mount 2>/dev/null) || { _menu_error "ventoy not mounted"; return 1; }
  local primary; primary=$(jq -r '.primary.file' "$p")
  local primary_fs="$m/${primary#/}"
  [[ -f "$primary_fs" ]] || { _menu_error "primary not found on USB: $primary_fs"; return 1; }
  _menu_info "Profile : $(basename "$p" .json)"
  _menu_info "Primary : $primary_fs"
  local n_vols; n_vols=$(jq '.data_volumes | length // 0' "$p")
  _menu_info "Volumes : $n_vols data volume(s) to inject"

  # Cross-check each data_volume file exists on the USB.
  local missing=0 file
  while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    [[ -f "$m/${file#/}" ]] || { _menu_warn "  missing on USB: $file"; missing=$((missing + 1)); }
  done < <(jq -r '.data_volumes[]?.file' "$p")
  [[ $missing -gt 0 ]] && _menu_warn "$missing data volume(s) missing — boot will skip them"

  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: would loop-mount $primary_fs and install:"
    _menu_info "  $UCA_VOL_MOUNT_SCRIPT"
    _menu_info "  $UCA_VOL_SYSTEMD_UNIT"
    _menu_info "  enable via multi-user.target.wants symlink"
    return 0
  fi
  _menu_confirm "Apply these mounts into the primary overlay now?" || return 0

  local mnt="/tmp/uca-apply-$$"
  sudo mkdir -p "$mnt" || { _menu_error "mkdir failed"; return 1; }
  if ! sudo mount -o loop "$primary_fs" "$mnt" 2>/dev/null; then
    _menu_error "Could not loop-mount primary (already mounted RW?)"; sudo rmdir "$mnt" 2>/dev/null; return 1
  fi
  if [[ ! -x "$mnt/bin/bash" && ! -L "$mnt/bin/bash" ]]; then
    _menu_warn "primary doesn't look like a Linux rootfs (no /bin/bash) — installing anyway"
  fi

  # Mount script.
  local script_tmp; script_tmp=$(mktemp)
  _uca_render_mount_script "$p" > "$script_tmp"
  sudo install -Dm755 "$script_tmp" "$mnt$UCA_VOL_MOUNT_SCRIPT"
  rm -f "$script_tmp"
  _menu_success "Installed $UCA_VOL_MOUNT_SCRIPT"

  # systemd unit.
  sudo mkdir -p "$mnt/etc/systemd/system"
  sudo tee "$mnt$UCA_VOL_SYSTEMD_UNIT" >/dev/null <<EOF
[Unit]
Description=USB-Hemlock data volumes auto-mount
DefaultDependencies=no
After=local-fs.target
Before=docker.service containerd.service multi-user.target
ConditionPathExists=$UCA_VOL_MOUNT_SCRIPT

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=$UCA_VOL_MOUNT_SCRIPT

[Install]
WantedBy=multi-user.target
EOF
  # Enable by symlink (can't run systemctl inside chroot reliably here).
  sudo mkdir -p "$mnt/etc/systemd/system/multi-user.target.wants"
  sudo ln -sf "$UCA_VOL_SYSTEMD_UNIT" \
    "$mnt/etc/systemd/system/multi-user.target.wants/uca-volumes.service"
  _menu_success "Installed + enabled $UCA_VOL_SYSTEMD_UNIT"

  # docker.service drop-in if any docker volume present.
  local has_docker; has_docker=$(jq '[.data_volumes[]? | select(.role=="docker" or .mount=="/var/lib/docker")] | length' "$p")
  if [[ "$has_docker" -gt 0 ]]; then
    sudo mkdir -p "$mnt/etc/systemd/system/docker.service.d"
    sudo tee "$mnt/etc/systemd/system/docker.service.d/10-uca-after-volumes.conf" >/dev/null <<'EOF'
[Unit]
After=uca-volumes.service
Requires=uca-volumes.service
EOF
    _menu_success "docker.service drop-in: After=uca-volumes.service"
  fi

  # Env vars.
  local n_env; n_env=$(jq '.env | length // 0' "$p")
  if [[ "$n_env" -gt 0 ]]; then
    sudo touch "$mnt/etc/environment"
    local env_line k
    while IFS= read -r env_line; do
      [[ -z "$env_line" ]] && continue
      k="${env_line%%=*}"
      sudo sed -i "/^${k}=/d" "$mnt/etc/environment" 2>/dev/null || true
      echo "$env_line" | sudo tee -a "$mnt/etc/environment" >/dev/null
    done < <(jq -r '.env | to_entries[]? | "\(.key)=\(.value)"' "$p")
    _menu_success "Wrote $n_env env var(s) to /etc/environment"
  fi

  sudo umount "$mnt" 2>/dev/null || _menu_warn "umount failed — still at $mnt"
  sudo rmdir "$mnt" 2>/dev/null || true
  _menu_info "Done. Next boot will auto-mount the data volumes."
}

# Read-only preview: show what compile + apply WOULD do.
_uca_profile_preview() {
  local p; p=$(_uca_pick_profile) || { _menu_error "no profile"; return 1; }
  local err; err=$(_uca_profile_validate "$p" 2>&1) || { _menu_warn "Validation: $err"; }
  local m; m=$(_uca_mount 2>/dev/null) || m=""
  echo ""
  _menu_subheader "Profile: $(basename "$p" .json)"
  printf "  ${BOLD}boot_mode:${NC} %s\n" "$(jq -r '.boot_mode // "ventoy"' "$p")"
  printf "  ${BOLD}device:${NC}    %s\n" "$(jq -r '.device    // "<unset>"' "$p")"
  printf "  ${BOLD}iso:${NC}       %s\n" "$(jq -r '.iso       // "<unset>"' "$p")"
  printf "  ${BOLD}primary:${NC}   %s\n" "$(jq -r '.primary.file // "<unset>"' "$p")"
  printf "  ${BOLD}default:${NC}   %s\n" "$(jq -r '.default   // false' "$p")"
  echo ""
  _menu_subheader "Data volumes"
  local rows; rows=$(jq -c '.data_volumes[]?' "$p" 2>/dev/null)
  if [[ -z "$rows" ]]; then
    _menu_info "  (none)"
  else
    printf "  %-32s %-10s %-22s %s\n" "file" "role" "mount" "status"
    while IFS= read -r r; do
      local f rl mn st="?"
      f=$(jq -r '.file' <<<"$r"); rl=$(jq -r '.role // "-"' <<<"$r"); mn=$(jq -r '.mount' <<<"$r")
      [[ -n "$m" ]] && { [[ -f "$m/${f#/}" ]] && st="ok" || st="MISSING"; }
      printf "  %-32s %-10s %-22s [%s]\n" "$f" "$rl" "$mn" "$st"
    done <<< "$rows"
  fi
  echo ""
  _menu_subheader "Env vars"
  local n_env; n_env=$(jq '.env | length // 0' "$p")
  if [[ "$n_env" -gt 0 ]]; then
    jq -r '.env | to_entries[]? | "  " + .key + "=" + (.value|tostring)' "$p"
  else
    _menu_info "  (none)"
  fi
  echo ""
  _menu_subheader "Apply would write"
  printf "  ${BOLD}ventoy.json:${NC}    %s/ventoy/ventoy.json   (boot routing)\n" "${m:-<usb>}"
  printf "  ${BOLD}rootfs script:${NC}  %s            (inside primary)\n" "$UCA_VOL_MOUNT_SCRIPT"
  printf "  ${BOLD}systemd unit:${NC}   %s   (inside primary)\n" "$UCA_VOL_SYSTEMD_UNIT"
  local has_docker; has_docker=$(jq '[.data_volumes[]? | select(.role=="docker" or .mount=="/var/lib/docker")] | length' "$p" 2>/dev/null || echo 0)
  [[ "$has_docker" -gt 0 ]] && \
    printf "  ${BOLD}docker drop-in:${NC} /etc/systemd/system/docker.service.d/10-uca-after-volumes.conf\n"
  echo ""
}

# ── Ventoy.json doctor (read-only validator) ────────────────────────────────
# Validates the Ventoy boot-routing config: file exists, valid JSON, plugin
# schemas, and that every referenced ISO and persistence backend resolves to a
# real file on disk. Reports findings; does not mutate. (Any future writes
# will back the file up first — convention enforced via `_uca_ventoy_json_backup`.)
_uca_ventoy_json_path() {
  local m; m=$(_uca_mount 2>/dev/null) || return 1
  printf '%s/ventoy/ventoy.json\n' "$m"
}

_uca_ventoy_json_backup() {
  local f="$1"; [[ -f "$f" ]] || return 0
  local ts; ts=$(date +%Y%m%d-%H%M%S)
  cp "$f" "$f.bak.$ts" && printf '%s.bak.%s\n' "$f" "$ts"
}

_uca_ventoy_doctor() {
  _menu_header "Ventoy.json Doctor"
  _menu_subheader "USB — read-only validator (see blueprint/ventoy-reference.md)"
  local m vj
  m=$(_uca_mount 2>/dev/null) || { _menu_error "Ventoy not mounted"; return 1; }
  vj="$m/ventoy/ventoy.json"
  printf "  ${BOLD}Mount       :${NC} %s\n" "$m"
  printf "  ${BOLD}ventoy.json :${NC} %s\n" "$vj"
  local issues=0 warnings=0

  if [[ ! -d "$m/ventoy" ]]; then
    _menu_error "no /ventoy directory at the mount — Ventoy may not be installed"
    return 1
  fi
  if [[ ! -f "$vj" ]]; then
    _menu_info "ventoy.json absent — Ventoy uses defaults (no plugins configured)."
    _menu_info "This is normal; add ventoy.json only when you want plugins."
    return 0
  fi
  command -v jq >/dev/null 2>&1 || { _menu_error "jq missing — install jq to run the doctor"; return 1; }
  echo ""
  _menu_subheader "1. JSON parse"
  if jq -e . "$vj" >/dev/null 2>&1; then
    _menu_success "valid JSON"
  else
    _menu_error "INVALID JSON — fix syntax before booting"
    jq . "$vj" 2>&1 | head -5 | sed 's/^/    /'
    return 1
  fi

  _menu_subheader "2. Known plugin keys"
  # Subset of Ventoy plugins documented in blueprint/ventoy-reference.md
  local known="control theme menu_alias menu_class menu_extension menu_tip auto_install persistence injection conf_replace password image_list image_blacklist dud auto_memdisk"
  local k
  for k in $(jq -r 'keys[]' "$vj" 2>/dev/null); do
    if [[ " $known " == *" $k "* ]]; then
      printf "    ok    %s\n" "$k"
    else
      printf "    ?     %s   (unknown plugin — check ventoy docs / typo?)\n" "$k"
      warnings=$((warnings + 1))
    fi
  done

  _menu_subheader "3. persistence plugin"
  if jq -e '.persistence' "$vj" >/dev/null 2>&1; then
    local rows
    rows=$(jq -c '.persistence[]?' "$vj" 2>/dev/null)
    [[ -z "$rows" ]] && _menu_warn "persistence: present but empty"
    while IFS= read -r row; do
      [[ -z "$row" ]] && continue
      local img bk autosel
      img=$(jq -r '.image // empty'   <<<"$row")
      bk=$(jq -r '.backend // empty' <<<"$row")
      autosel=$(jq -r '.autosel // empty' <<<"$row")
      printf "    image=%s\n    backend=%s\n" "$img" "$bk"
      [[ -n "$autosel" ]] && printf "    autosel=%s\n" "$autosel"
      # image path is RELATIVE to the Ventoy mount root.
      if [[ -n "$img" ]]; then
        local imgfs="$m${img#/}"; imgfs="$m/${img#/}"
        if [[ -f "$imgfs" ]]; then
          _menu_success "image exists ($(du -h "$imgfs" 2>/dev/null | cut -f1))"
        else
          _menu_error "image NOT FOUND: $imgfs"; issues=$((issues + 1))
        fi
      else
        _menu_error "persistence entry missing 'image'"; issues=$((issues + 1))
      fi
      # backend is also relative to the mount root.
      if [[ -n "$bk" ]]; then
        local bkfs="$m/${bk#/}"
        if [[ -f "$bkfs" ]]; then
          _menu_success "backend exists ($(du -h "$bkfs" 2>/dev/null | cut -f1))"
        else
          _menu_error "backend NOT FOUND: $bkfs"; issues=$((issues + 1))
        fi
      else
        _menu_error "persistence entry missing 'backend'"; issues=$((issues + 1))
      fi
      echo ""
    done <<< "$rows"
  else
    _menu_info "(no persistence plugin configured)"
  fi

  _menu_subheader "4. control plugin (boot defaults)"
  if jq -e '.control' "$vj" >/dev/null 2>&1; then
    jq -r '.control[] | to_entries[] | "    \(.key) = \(.value)"' "$vj" 2>/dev/null
  else
    _menu_info "(no control plugin — Ventoy defaults apply)"
  fi

  _menu_subheader "5. ISO inventory cross-check"
  local n_isos
  n_isos=$(find "$m" -maxdepth 2 -iname '*.iso' 2>/dev/null | wc -l)
  printf "    ISO files on USB: %s\n" "$n_isos"

  echo ""
  if [[ $issues -eq 0 && $warnings -eq 0 ]]; then
    _menu_success "ventoy.json doctor: HEALTHY"
  else
    _menu_warn "ventoy.json doctor: $issues issue(s), $warnings warning(s)"
    _menu_info "Reference: blueprint/ventoy-reference.md"
  fi
}

# ── USB Paths & Environment submenu ─────────────────────────────────────────
_run_usb_paths() {
  _menu_header "USB Paths & Environment"
  _menu_subheader "HOST — configurable file-tree schema & env vars"
  local mount pdir
  mount=$(_uca_mount 2>/dev/null) || mount="<not mounted>"
  pdir=$(_uca_persistence_dir 2>/dev/null) || pdir="<unknown>"
  echo ""
  printf "  ${BOLD}Config file:${NC} %s %s\n" "$UCA_PATHS_CONF" "$([[ -f "$UCA_PATHS_CONF" ]] && echo '(exists)' || echo '(defaults)')"
  printf "  ${BOLD}Env file:${NC}    %s %s\n" "$UCA_ENV_CONF" "$([[ -f "$UCA_ENV_CONF" ]] && echo '(exists)' || echo '(none)')"
  echo ""
  _menu_subheader "Current settings (blank = auto-detect)"
  printf "  %-22s %s\n" "Mount override"       "${UCA_VENTOY_MOUNT:-<auto>}"
  printf "  %-22s %s\n" "  -> resolved"        "$mount"
  printf "  %-22s %s\n" "Persistence dir"      "${UCA_PERSISTENCE_DIR:-<auto>}"
  printf "  %-22s %s\n" "  -> resolved"        "$pdir"
  printf "  %-22s %s\n" "Extra volumes"        "${UCA_PERSISTENCE_VOLUMES:-<none>}"
  printf "  %-22s %s\n" "Startup script"       "${UCA_STARTUP_SCRIPT:-<auto: mount/startup.sh>}"
  printf "  %-22s %s\n" "Essentials script"    "${UCA_ESSENTIALS_SCRIPT:-<auto: mount/scripts/setup-essentials.sh>}"
  printf "  %-22s %s\n" "rc.local path"        "$UCA_RCLOCAL_PATH"
  printf "  %-22s %s\n" "ISO path"             "${UCA_ISO_PATH:-<auto: first *.iso>}"
  printf "  %-22s %s\n" "QEMU RAM / CPUs"      "${UCA_QEMU_RAM} / ${UCA_QEMU_CPUS}"
  printf "  %-22s %s\n" "QEMU SSH port"        "$UCA_QEMU_SSH_PORT"
  printf "  %-22s %s\n" "Boot target"          "$UCA_BOOT_TARGET"
  printf "  %-22s %s\n" "Install target"       "$UCA_INSTALL_TARGET  (usb=on drive, host=on this machine)"
  echo ""
  _menu_item "1" "Edit a setting"                "" ""
  _menu_item "2" "Manage environment variables"  "" "$UCA_ENV_CONF"
  _menu_item "3" "Open paths config in \$EDITOR"  "" ""
  _menu_item "4" "Save current settings"          "" ""
  _menu_item "5" "Reset all to auto-detect"       "" ""
  _menu_item "6" "Discover persistence volumes"   "" ""
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1) _uca_edit_setting ;;
    2) _uca_manage_env ;;
    3)
      mkdir -p "$UCA_CFG_DIR" 2>/dev/null || true
      [[ -f "$UCA_PATHS_CONF" ]] || _uca_save_paths_config
      ${EDITOR:-nano} "$UCA_PATHS_CONF"
      _uca_load_paths_config
      _menu_success "Reloaded config"
      ;;
    4) _uca_save_paths_config ;;
    5)
      _menu_confirm "Reset ALL path settings to auto-detect?" || return 0
      UCA_VENTOY_MOUNT=""; UCA_PERSISTENCE_DIR=""; UCA_PERSISTENCE_VOLUMES=""
      UCA_STARTUP_SCRIPT=""; UCA_ESSENTIALS_SCRIPT=""; UCA_RCLOCAL_PATH="etc/rc.local"
      UCA_ISO_PATH=""; UCA_QEMU_RAM="4G"; UCA_QEMU_CPUS="2"; UCA_QEMU_SSH_PORT="2222"
      UCA_BOOT_TARGET="device"; UCA_INSTALL_TARGET="usb"
      _uca_save_paths_config
      ;;
    6)
      echo ""
      _menu_subheader "Discovered persistence volumes"
      local found=0 v
      while IFS= read -r v; do
        [[ -n "$v" ]] || continue
        found=$((found + 1))
        printf "  %s (%s)\n" "$v" "$(du -h "$v" 2>/dev/null | cut -f1 || echo '?')"
      done < <(_uca_list_volumes)
      [[ "$found" -eq 0 ]] && _menu_info "(none found — check persistence dir / mount)"
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

_uca_edit_setting() {
  echo ""
  _menu_subheader "Editable settings"
  local keys=(UCA_VENTOY_MOUNT UCA_PERSISTENCE_DIR UCA_PERSISTENCE_VOLUMES \
             UCA_STARTUP_SCRIPT UCA_ESSENTIALS_SCRIPT UCA_RCLOCAL_PATH \
             UCA_ISO_PATH UCA_QEMU_RAM UCA_QEMU_CPUS UCA_QEMU_SSH_PORT UCA_BOOT_TARGET \
             UCA_INSTALL_TARGET)
  local i=1 k
  for k in "${keys[@]}"; do
    printf "  %2d) %-24s = %s\n" "$i" "$k" "${!k:-<empty>}"
    i=$((i + 1))
  done
  printf "  Select setting number (0=cancel): "
  local sel; read -r sel
  [[ "$sel" == "0" || -z "$sel" ]] && return 0
  if ! [[ "$sel" =~ ^[0-9]+$ ]] || [[ "$sel" -lt 1 || "$sel" -gt ${#keys[@]} ]]; then
    _menu_error "Invalid selection"; return 1
  fi
  local key="${keys[$((sel - 1))]}"
  printf "  New value for %s (blank to clear): " "$key"
  local val; read -r val
  declare -g "$key=$val"
  _menu_success "$key = ${val:-<empty>}"
  _menu_confirm "Save to config now?" && _uca_save_paths_config
}

_uca_manage_env() {
  _menu_header "Environment Variables"
  _menu_subheader "HOST — persisted to $UCA_ENV_CONF"
  echo ""
  if [[ -f "$UCA_ENV_CONF" ]]; then
    _menu_subheader "Current env vars"
    grep -vE '^[[:space:]]*(#|$)' "$UCA_ENV_CONF" 2>/dev/null | sed 's/^/  /' || true
  else
    _menu_info "(no env file yet)"
  fi
  echo ""
  _menu_item "1" "Add / update a variable" "" ""
  _menu_item "2" "Remove a variable"       "" ""
  _menu_item "3" "Open env file in \$EDITOR" "" ""
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1)
      printf "  Variable name: "; local name; read -r name
      [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || { _menu_error "Invalid variable name"; return 1; }
      printf "  Value: "; local value; read -r value
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: would set $name=$value in $UCA_ENV_CONF"; return 0
      fi
      mkdir -p "$UCA_CFG_DIR" 2>/dev/null || true
      touch "$UCA_ENV_CONF"
      grep -vE "^${name}=" "$UCA_ENV_CONF" > "$UCA_ENV_CONF.tmp" 2>/dev/null || true
      printf '%s=%q\n' "$name" "$value" >> "$UCA_ENV_CONF.tmp"
      mv "$UCA_ENV_CONF.tmp" "$UCA_ENV_CONF"
      export "$name=$value"
      _menu_success "Set $name (also exported into this session)"
      ;;
    2)
      printf "  Variable name to remove: "; local name; read -r name
      [[ -f "$UCA_ENV_CONF" ]] || { _menu_info "(no env file)"; return 0; }
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would remove $name"; return 0; fi
      grep -vE "^${name}=" "$UCA_ENV_CONF" > "$UCA_ENV_CONF.tmp" 2>/dev/null || true
      mv "$UCA_ENV_CONF.tmp" "$UCA_ENV_CONF"
      _menu_success "Removed $name (unset on next launch)"
      ;;
    3)
      mkdir -p "$UCA_CFG_DIR" 2>/dev/null || true
      touch "$UCA_ENV_CONF"
      ${EDITOR:-nano} "$UCA_ENV_CONF"
      _uca_load_paths_config
      _menu_success "Reloaded env"
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# USB Access & Boot  (FS-009): terminal exec, chroot, QEMU headless/GUI, SSH
# ════════════════════════════════════════════════════════════════════════════

# ── Install policy: USB-first ───────────────────────────────────────────────
# Project policy: dev tooling/packages install onto the USB (persistence) by
# default. The host is only touched for dependencies that genuinely cannot run
# from the portable drive — QEMU/KVM (host CPU/RAM for the VM), port-forwarding,
# and headless-boot autostart — and only after an explained prompt.
: "${UCA_INSTALL_TARGET:=usb}"   # usb (default) | host

# OS-detected host package manager (name on stdout; 1 if none known).
_uca_pkg_manager() {
  local pm
  for pm in apt-get dnf yum pacman zypper brew; do
    command -v "$pm" >/dev/null 2>&1 && { printf '%s\n' "$pm"; return 0; }
  done
  return 1
}
# Install command string for the detected manager + given packages.
_uca_pkg_install_cmd() {
  local pm="$1"; shift
  case "$pm" in
    apt-get) printf 'sudo apt-get install -y %s' "$*" ;;
    dnf)     printf 'sudo dnf install -y %s' "$*" ;;
    yum)     printf 'sudo yum install -y %s' "$*" ;;
    pacman)  printf 'sudo pacman -S --noconfirm %s' "$*" ;;
    zypper)  printf 'sudo zypper install -y %s' "$*" ;;
    brew)    printf 'brew install %s' "$*" ;;
    *)       printf 'install %s' "$*" ;;
  esac
}

# Gate a HOST dependency that genuinely must live on the host (not the USB).
# Explains WHY, then prompts to install via the OS-detected package manager.
# Honors DRY_RUN. Returns 0 if available/installed, 1 if missing/declined.
_uca_require_host_dep() {
  local bin="$1" pkg="$2" reason="$3"
  command -v "$bin" >/dev/null 2>&1 && return 0
  _menu_warn "Required HOST dependency missing: $bin"
  _menu_info  "Why it must be on the host (not the portable USB):"
  _menu_info  "  $reason"
  local pm; pm=$(_uca_pkg_manager) || {
    _menu_error "No known package manager detected — install '$pkg' manually."; return 1; }
  local cmd; cmd=$(_uca_pkg_install_cmd "$pm" "$pkg")
  _menu_info  "Proposed (host): $cmd"
  if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: $cmd"; return 1; fi
  _menu_confirm "Install '$pkg' on the HOST now?" || { _menu_warn "Skipped — $bin stays unavailable"; return 1; }
  if eval "$cmd" && command -v "$bin" >/dev/null 2>&1; then
    _menu_success "$bin installed on host"; return 0
  fi
  _menu_error "Install failed or $bin still missing"; return 1
}

_uca_qemu_check() {
  _uca_require_host_dep qemu-system-x86_64 "qemu-system-x86 qemu-utils" \
    "QEMU runs the USB image as a VM using THIS machine's CPU/RAM and wires up the SSH port-forward to the guest, so it must run on the host — it cannot be served from the portable USB." || return 1
  [[ -e /dev/kvm ]] || _menu_warn "/dev/kvm absent — VM will run WITHOUT KVM (slow)"
  return 0
}

# Reverse-order cleanup of a chroot/loop mount tree.
_uca_unmount_tree() {
  local mnt="$1"
  local sub
  for sub in dev/pts dev proc sys tmp ""; do
    sudo umount "$mnt/$sub" 2>/dev/null || true
  done
  sudo rmdir "$mnt" 2>/dev/null || true
}

_run_usb_access() {
  _menu_header "USB Access & Boot"
  _menu_subheader "USB+HOST — terminal, chroot, QEMU, SSH"
  local mount; mount=$(_uca_mount 2>/dev/null) || mount="<not mounted>"
  echo ""
  printf "  ${BOLD}Mount:${NC} %s   ${BOLD}Device:${NC} %s   ${BOLD}Boot target:${NC} %s\n" \
    "$mount" "${SELECTED_DEVICE:-<unset>}" "$UCA_BOOT_TARGET"
  echo ""
  _menu_item "1" "Open shell at Ventoy mount"          "" "browse USB files"
  _menu_item "2" "Exec shell INTO persistence"         "" "loop-mount RW (root)"
  _menu_item "3" "Chroot into persistence"             "" "full env (root)"
  _menu_item "4" "Edit rc.local on a persistence vol"  "" "(root)"
  _menu_item "5" "Headless boot + SSH (QEMU)"          "" "serial console"
  _menu_item "6" "Desktop / GUI boot (QEMU)"           "" "graphical window"
  _menu_item "7" "Boot ISO in QEMU"                    "" "live ISO"
  _menu_item "8" "SSH into running headless VM"        "" "port $UCA_QEMU_SSH_PORT"
  _menu_item "9" "Install dev tooling INTO USB"        "" "comprehensive (default)"
  _menu_item "10" "Validate services (ssh/docker)"     "" "offline + runtime"
  _menu_item "11" "Headless-boot autostart"            "" "OS-aware (host)"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1) _uca_shell_at_mount ;;
    2) _uca_exec_into_persistence ;;
    3) _uca_chroot_persistence ;;
    4) _uca_edit_rclocal ;;
    5) _uca_boot_headless ;;
    6) _uca_boot_gui ;;
    7) _uca_boot_iso ;;
    8) _uca_ssh_vm ;;
    9) _uca_install_tooling_usb ;;
    10) _uca_validate_services ;;
    11) _uca_boot_autostart ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

_uca_shell_at_mount() {
  local m; m=$(_uca_mount 2>/dev/null) || { _menu_error "Ventoy not mounted"; return 1; }
  [[ -d "$m" ]] || { _menu_error "Mount path not a directory: $m"; return 1; }
  _menu_info "Opening a shell at $m — type 'exit' to return to the menu."
  ( cd "$m" && exec "${SHELL:-bash}" ) || _menu_warn "Shell exited (code $?)"
}

_uca_exec_into_persistence() {
  local vol; vol=$(_uca_select_volume) || { _menu_error "No persistence volume found"; return 1; }
  _menu_info "Volume: $vol"
  _menu_warn "This loop-mounts the volume READ-WRITE; changes are permanent."
  _menu_confirm "Mount and open a shell inside it?" || return 0
  local mnt="/tmp/uca-persist-$$"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: sudo mount -o loop '$vol' '$mnt' && shell"
    return 0
  fi
  sudo mkdir -p "$mnt" || { _menu_error "mkdir failed"; return 1; }
  if sudo mount -o loop "$vol" "$mnt" 2>/dev/null; then
    _menu_success "Mounted at $mnt (read-write). Type 'exit' to unmount & return."
    ( cd "$mnt" && sudo "${SHELL:-bash}" ) || _menu_warn "Shell exited (code $?)"
    sudo umount "$mnt" 2>/dev/null || _menu_warn "Unmount failed — still mounted at $mnt"
  else
    _menu_error "Could not mount $vol (already mounted? wrong filesystem?)"
  fi
  sudo rmdir "$mnt" 2>/dev/null || true
}

_uca_chroot_persistence() {
  local vol; vol=$(_uca_select_volume) || { _menu_error "No persistence volume found"; return 1; }
  _menu_info "Volume: $vol"
  _menu_warn "Chroot gives a full root environment inside the persistence rootfs"
  _menu_warn "(binds /dev /proc /sys /dev/pts /tmp). Changes are permanent."
  _menu_confirm "Chroot into it now?" || return 0
  local mnt="/tmp/uca-chroot-$$"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: mount loop + bind dev/proc/sys + chroot '$mnt' /bin/bash"
    return 0
  fi
  sudo mkdir -p "$mnt" || { _menu_error "mkdir failed"; return 1; }
  if ! sudo mount -o loop "$vol" "$mnt" 2>/dev/null; then
    _menu_error "Could not mount $vol"; sudo rmdir "$mnt" 2>/dev/null || true; return 1
  fi
  if [[ ! -d "$mnt/bin" && ! -L "$mnt/bin" ]]; then
    _menu_warn "Volume does not look like a root filesystem (no /bin) — chroot may fail"
  fi
  sudo mount --bind /dev "$mnt/dev" 2>/dev/null || true
  sudo mount --bind /proc "$mnt/proc" 2>/dev/null || true
  sudo mount --bind /sys "$mnt/sys" 2>/dev/null || true
  sudo mount --bind /dev/pts "$mnt/dev/pts" 2>/dev/null || true
  sudo cp /etc/resolv.conf "$mnt/etc/resolv.conf" 2>/dev/null || true
  _menu_success "Entering chroot — type 'exit' to leave and clean up."
  sudo chroot "$mnt" /bin/bash || _menu_warn "chroot session ended (code $?)"
  _menu_info "Cleaning up mounts..."
  _uca_unmount_tree "$mnt"
  _menu_success "Unmounted and cleaned up."
}

_uca_edit_rclocal() {
  local vol; vol=$(_uca_select_volume) || { _menu_error "No persistence volume found"; return 1; }
  local mnt="/tmp/uca-rclocal-$$"
  local rcrel="$UCA_RCLOCAL_PATH"
  _menu_info "Volume: $vol   rc.local: $rcrel"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: mount '$vol', edit '$rcrel', unmount"
    return 0
  fi
  sudo mkdir -p "$mnt" || { _menu_error "mkdir failed"; return 1; }
  if ! sudo mount -o loop "$vol" "$mnt" 2>/dev/null; then
    _menu_error "Could not mount $vol"; sudo rmdir "$mnt" 2>/dev/null || true; return 1
  fi
  local rcpath="$mnt/$rcrel"
  sudo mkdir -p "$(dirname "$rcpath")" 2>/dev/null || true
  if [[ ! -f "$rcpath" ]]; then
    _menu_info "rc.local not present — creating a template."
    sudo tee "$rcpath" >/dev/null <<'RCLOCAL'
#!/bin/bash
# rc.local — runs at boot inside the USB persistence environment.
# Add startup commands above the final 'exit 0'.

exit 0
RCLOCAL
    sudo chmod +x "$rcpath"
  fi
  sudo "${EDITOR:-nano}" "$rcpath"
  sudo chmod +x "$rcpath" 2>/dev/null || true
  _menu_success "Saved $rcrel in $(basename "$vol")"
  sudo umount "$mnt" 2>/dev/null || _menu_warn "Unmount failed — still at $mnt"
  sudo rmdir "$mnt" 2>/dev/null || true
}

_uca_boot_headless() {
  _uca_qemu_check || return 1
  local dev="${SELECTED_DEVICE:-}"
  [[ -n "$dev" ]] || { _menu_error "No USB device set (option 14)"; return 1; }
  [[ -b "$dev" ]] || { _menu_error "$dev is not a block device"; return 1; }
  local kvm=""; [[ -e /dev/kvm ]] && kvm="-enable-kvm"
  _menu_warn "Booting the whole USB device ($dev) in a VM."
  _menu_warn "The drive is also mounted on this host, so by default the VM runs"
  _menu_warn "in SNAPSHOT mode (guest writes are DISCARDED) to avoid corruption."
  _menu_info  "SSH forwarded: host port ${UCA_QEMU_SSH_PORT} -> guest 22"
  local snap="-snapshot"
  if ! _menu_confirm "Use safe snapshot mode (recommended)?"; then
    _menu_warn "Persistent mode writes directly to $dev. Unmount the host Ventoy"
    _menu_warn "mount FIRST or you risk filesystem corruption."
    _menu_confirm "I understand the risk — boot in PERSISTENT mode?" || return 0
    snap=""
  fi
  local cmd=(sudo qemu-system-x86_64 $kvm -m "$UCA_QEMU_RAM" -smp "$UCA_QEMU_CPUS"
    -drive "file=$dev,format=raw,if=virtio" -boot c
    -netdev "user,id=net0,hostfwd=tcp::${UCA_QEMU_SSH_PORT}-:22"
    -device virtio-net-pci,netdev=net0 -nographic $snap)
  if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: ${cmd[*]}"; return 0; fi
  _menu_info "Starting QEMU. Quit the serial console with: Ctrl-A then X"
  _menu_info "From another terminal: ssh -p ${UCA_QEMU_SSH_PORT} <user>@localhost"
  "${cmd[@]}" || _menu_warn "QEMU exited (code $?)"
}

_uca_boot_gui() {
  _uca_qemu_check || return 1
  local dev="${SELECTED_DEVICE:-}"
  [[ -b "$dev" ]] || { _menu_error "No USB device set (option 14)"; return 1; }
  [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] || _menu_warn "No DISPLAY/WAYLAND_DISPLAY — a window may not open"
  local kvm=""; [[ -e /dev/kvm ]] && kvm="-enable-kvm"
  _menu_warn "Graphical boot of $dev. Snapshot mode (writes discarded) by default."
  local snap="-snapshot"
  if ! _menu_confirm "Use safe snapshot mode (recommended)?"; then
    _menu_confirm "Boot in PERSISTENT mode (risk of corruption while host-mounted)?" || return 0
    snap=""
  fi
  local cmd=(sudo qemu-system-x86_64 $kvm -m "$UCA_QEMU_RAM" -smp "$UCA_QEMU_CPUS"
    -drive "file=$dev,format=raw,if=virtio" -boot c -vga virtio
    -netdev "user,id=net0,hostfwd=tcp::${UCA_QEMU_SSH_PORT}-:22"
    -device virtio-net-pci,netdev=net0 $snap)
  if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: ${cmd[*]}"; return 0; fi
  _menu_info "Launching graphical QEMU window (close the window to return)..."
  "${cmd[@]}" || _menu_warn "QEMU exited (code $?)"
}

_uca_boot_iso() {
  _uca_qemu_check || return 1
  local iso="$UCA_ISO_PATH"
  if [[ -z "$iso" ]]; then
    local m; m=$(_uca_mount 2>/dev/null) || m=""
    [[ -n "$m" ]] && iso=$(ls "$m"/*.iso 2>/dev/null | head -1 || true)
  fi
  [[ -n "$iso" && -f "$iso" ]] || { _menu_error "No ISO found (set ISO path in Paths config)"; return 1; }
  local kvm=""; [[ -e /dev/kvm ]] && kvm="-enable-kvm"
  _menu_info "ISO: $iso"
  local graphic="-nographic"
  _menu_confirm "Graphical window? (No = headless serial)" && graphic="-vga virtio"
  local cmd=(qemu-system-x86_64 $kvm -m "$UCA_QEMU_RAM" -smp "$UCA_QEMU_CPUS"
    -cdrom "$iso" -boot d
    -netdev "user,id=net0,hostfwd=tcp::${UCA_QEMU_SSH_PORT}-:22"
    -device virtio-net-pci,netdev=net0 $graphic)
  if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: ${cmd[*]}"; return 0; fi
  _menu_info "Booting ISO in QEMU..."
  "${cmd[@]}" || _menu_warn "QEMU exited (code $?)"
}

_uca_ssh_vm() {
  printf "  SSH username [ubuntu]: "; local u; read -r u; u="${u:-ubuntu}"
  local port="$UCA_QEMU_SSH_PORT"
  _menu_info "Connecting: ssh -p $port ${u}@localhost (VM must be running & sshd up)"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: ssh -p $port ${u}@localhost"; return 0
  fi
  ssh -p "$port" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${u}@localhost" \
    || _menu_warn "SSH session ended (code $?)"
}

# Mount a persistence volume and enter a prepared chroot (binds + resolv.conf),
# run a callback that emits the in-chroot command on stdout, then clean up.
# Usage: _uca_with_chroot VOLUME COMMAND...   (COMMAND runs via chroot bash -c)
# Echoes "ready" prep messages; returns the chroot command's exit status.
_uca_with_chroot() {
  local vol="$1"; shift
  local mnt="/tmp/uca-chroot-$$-$RANDOM"
  sudo mkdir -p "$mnt" || { _menu_error "mkdir failed"; return 1; }
  if ! sudo mount -o loop "$vol" "$mnt" 2>/dev/null; then
    _menu_error "Could not mount $vol (already mounted? wrong fs?)"; sudo rmdir "$mnt" 2>/dev/null || true; return 1
  fi
  if [[ ! -x "$mnt/bin/bash" && ! -L "$mnt/bin/bash" ]]; then
    _menu_error "Volume is not a bootable rootfs (no /bin/bash) — cannot chroot."
    _uca_unmount_tree "$mnt"; return 1
  fi
  sudo mount --bind /dev "$mnt/dev" 2>/dev/null || true
  sudo mount --bind /proc "$mnt/proc" 2>/dev/null || true
  sudo mount --bind /sys "$mnt/sys" 2>/dev/null || true
  sudo mount --bind /dev/pts "$mnt/dev/pts" 2>/dev/null || true
  sudo cp /etc/resolv.conf "$mnt/etc/resolv.conf" 2>/dev/null || true
  local rc=0
  sudo chroot "$mnt" /bin/bash -c "$*" || rc=$?
  _uca_unmount_tree "$mnt"
  return $rc
}

# Comprehensive, categorized dev-tooling installer that runs INSIDE the USB
# persistence (project default). Mirrors the host toolchain. Each category is
# optional; openssh + base services are installed and ENABLED so they are
# active on boot. Network installers (rust/node/docker/ollama/tailscale/gh) are
# best-effort and logged to /var/log/uca-essentials.log inside the volume.
_uca_install_tooling_usb() {
  _menu_header "Install Dev Tooling — USB-first"
  _menu_subheader "USB — comprehensive toolchain on the portable drive"
  local vol; vol=$(_uca_select_volume) || { _menu_error "No persistence volume found"; return 1; }
  echo ""
  _menu_info "Categories (comma-separated). Default 'recommended' = the everyday set."
  echo "  Recommended (installed by default):"
  echo "    core      build-essential gcc/g++ make cmake pkg-config git curl wget rsync unzip zip tar"
  echo "    editors   vim nano tmux htop tree jq less fzf ripgrep bat fd bash-completion"
  echo "    net       net-tools iproute2 dnsutils iputils openssh-client"
  echo "    ssh       openssh-server (enabled) + sshd defaults"
  echo "    python    python3 pip venv pipx + cryptography/pynacl/web3/eth-account"
  echo "    node      Node LTS + corepack (pnpm/yarn)"
  echo "    crypto    openssl libssl-dev gnupg age libsodium  (encryption/keys)"
  echo "    web3      foundry (forge/cast/anvil) + hardhat/ethers/viem/solc"
  echo "    docker    docker.io + compose (enabled)  [agent harnesses/crews]"
  echo "    cloud     gh, cloudflared, wrangler, tailscale"
  echo "  Opt-in (only if named):"
  echo "    rust  rustup+cargo   go  golang   ai  ollama+hf-cli"
  echo "    llmrl HF model browser/downloader CLI (Node)   extras  ruby,socat,nmap"
  echo "  Use 'recommended', 'all' (incl. opt-ins), or a custom list (e.g. core,web3,docker)."
  printf "  Selection [recommended]: "
  local groups; read -r groups; groups="${groups:-recommended}"
  _menu_info "Volume : $vol"
  _menu_info "Target : USB persistence (chroot) — NOT the host"
  _menu_info "Groups : $groups"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: would generate /tmp/uca-essentials.sh in $vol and run groups: $groups"
    return 0
  fi
  _menu_confirm "Install these INTO the USB persistence now? (network + time heavy)" || return 0

  local mnt="/tmp/uca-tooling-$$"
  sudo mkdir -p "$mnt" || { _menu_error "mkdir failed"; return 1; }
  if ! sudo mount -o loop "$vol" "$mnt" 2>/dev/null; then
    _menu_error "Could not mount $vol"; sudo rmdir "$mnt" 2>/dev/null || true; return 1
  fi
  if [[ ! -x "$mnt/bin/bash" && ! -L "$mnt/bin/bash" ]]; then
    _menu_error "Volume is not a bootable rootfs (no /bin/bash) — cannot chroot-install."
    _menu_info  "Use option 7 (Build Essentials) for a host install, or pick a rootfs volume."
    _uca_unmount_tree "$mnt"; return 1
  fi
  sudo mount --bind /dev "$mnt/dev" 2>/dev/null || true
  sudo mount --bind /proc "$mnt/proc" 2>/dev/null || true
  sudo mount --bind /sys "$mnt/sys" 2>/dev/null || true
  sudo mount --bind /dev/pts "$mnt/dev/pts" 2>/dev/null || true
  sudo cp /etc/resolv.conf "$mnt/etc/resolv.conf" 2>/dev/null || true

  # Generate the in-persistence installer (idempotent, best-effort per group).
  sudo mkdir -p "$mnt/tmp"
  sudo tee "$mnt/tmp/uca-essentials.sh" >/dev/null <<'ESS'
#!/usr/bin/env bash
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
# NOTE: do not name this GROUPS — that is a bash special array (the user's
# group IDs) and assignments to it are silently ignored.
SEL="${1:-recommended}"
LOG=/var/log/uca-essentials.log
mkdir -p /var/log; : >"$LOG"
say(){ echo "[uca-essentials] $*" | tee -a "$LOG"; }
api(){ apt-get install -y --no-install-recommends "$@" >>"$LOG" 2>&1 || say "  (some of: $* failed)"; }
# 'recommended' = the everyday set; 'all' = recommended + opt-ins; or a custom list.
RECO="core editors net ssh python node crypto web3 docker cloud"
want(){
  local g="$1" r
  [[ ",$SEL," == *",all,"* ]] && return 0
  if [[ ",$SEL," == *",recommended,"* ]]; then
    for r in $RECO; do [[ "$r" == "$g" ]] && return 0; done
  fi
  [[ ",$SEL," == *",$g,"* ]] && return 0
  return 1
}

say "apt update"; apt-get update -y >>"$LOG" 2>&1 || say "apt update warnings"
apt-get install -y ca-certificates curl wget gnupg lsb-release apt-transport-https software-properties-common >>"$LOG" 2>&1 || true

if want core; then say "core build toolchain"
  api build-essential gcc g++ make cmake pkg-config autoconf automake libtool \
      git curl wget rsync unzip zip tar xz-utils file; fi
if want editors; then say "editors & shell tools"
  api vim nano tmux htop tree jq less man-db bash-completion
  api fzf ripgrep bat fd-find 2>/dev/null || true; fi
if want net; then say "networking tools (lean)"
  api net-tools iproute2 dnsutils iputils-ping openssh-client; fi
if want ssh; then say "openssh-server (+ enable)"
  api openssh-server
  mkdir -p /etc/ssh/sshd_config.d
  cat >/etc/ssh/sshd_config.d/10-usb-hemlock.conf <<'SSHD'
# USB-Hemlock defaults — edit to taste
PasswordAuthentication yes
PermitRootLogin prohibit-password
X11Forwarding yes
ClientAliveInterval 60
SSHD
  systemctl enable ssh >>"$LOG" 2>&1 || systemctl enable sshd >>"$LOG" 2>&1 || \
    { [ -d /etc/rc5.d ] && update-rc.d ssh enable >>"$LOG" 2>&1; } || say "  could not enable ssh (will still start if default)"
  ssh-keygen -A >>"$LOG" 2>&1 || true
fi
if want python; then say "python toolchain + crypto/web3 libs"
  api python3 python3-pip python3-venv python3-dev pipx python3-cryptography python3-nacl
  # web3/eth libs are pip-only on 24.04 (PEP668) — best-effort, system-wide.
  pip install --break-system-packages --no-input web3 eth-account >>"$LOG" 2>&1 || say "  pip web3/eth-account skipped (use a venv per project)"
fi
if want crypto; then say "encryption / key tooling"
  api openssl libssl-dev gnupg2 age libsodium-dev pass; fi
if want node; then say "Node.js LTS via NodeSource"
  if ! command -v node >/dev/null 2>&1; then
    curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >>"$LOG" 2>&1 || say "  nodesource failed; trying distro nodejs"
    api nodejs || api npm
  fi
  command -v corepack >/dev/null 2>&1 && corepack enable >>"$LOG" 2>&1 || true; fi
if want web3; then say "web3 toolchain (foundry + hardhat/ethers/viem/solc)"
  # Foundry: system-wide under /opt/foundry, symlinked into PATH for all users.
  if ! command -v forge >/dev/null 2>&1; then
    export FOUNDRY_DIR=/opt/foundry
    curl -L https://foundry.paradigm.xyz | bash >>"$LOG" 2>&1 || say "  foundry bootstrap failed"
    /opt/foundry/bin/foundryup >>"$LOG" 2>&1 || say "  foundryup failed"
    for b in forge cast anvil chisel; do [ -x "/opt/foundry/bin/$b" ] && ln -sf "/opt/foundry/bin/$b" "/usr/local/bin/$b"; done
  fi
  if command -v npm >/dev/null 2>&1; then
    npm install -g hardhat solc ethers viem >>"$LOG" 2>&1 || say "  npm global web3 libs had issues"
  else
    say "  npm not present — install 'node' group for hardhat/ethers/viem"
  fi
fi
if want docker; then say "Docker (in-persistence) + compose"
  api docker.io docker-compose-v2 || api docker.io
  systemctl enable docker >>"$LOG" 2>&1 || true
  systemctl enable containerd >>"$LOG" 2>&1 || true; fi
if want cloud; then say "gh + cloudflared + wrangler + tailscale"
  if ! command -v gh >/dev/null 2>&1; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli.gpg >/dev/null 2>&1 || true
    chmod go+r /etc/apt/keyrings/githubcli.gpg 2>/dev/null || true
    echo "deb [signed-by=/etc/apt/keyrings/githubcli.gpg] https://cli.github.com/packages stable main" >/etc/apt/sources.list.d/github-cli.list
    apt-get update -y >>"$LOG" 2>&1 || true; api gh
  fi
  if ! command -v cloudflared >/dev/null 2>&1; then
    mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /etc/apt/keyrings/cloudflare-main.gpg >/dev/null 2>&1 || true
    echo "deb [signed-by=/etc/apt/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main" >/etc/apt/sources.list.d/cloudflared.list 2>/dev/null || true
    apt-get update -y >>"$LOG" 2>&1 || true; api cloudflared || say "  cloudflared apt failed"
  fi
  command -v npm >/dev/null 2>&1 && { npm install -g wrangler >>"$LOG" 2>&1 || say "  wrangler npm failed"; }
  command -v tailscale >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh >>"$LOG" 2>&1 || say "  tailscale install failed"; fi

# ── Opt-in groups (only when explicitly named or 'all') ──
if want rust; then say "Rust via rustup (system-wide)"
  if ! command -v rustc >/dev/null 2>&1; then
    export RUSTUP_HOME=/opt/rust CARGO_HOME=/opt/rust
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path >>"$LOG" 2>&1 || say "  rustup failed"
    for b in rustc cargo rustup; do [ -x "/opt/rust/bin/$b" ] && ln -sf "/opt/rust/bin/$b" "/usr/local/bin/$b"; done
  fi; fi
if want go; then say "Go"; api golang-go; fi
if want ai; then say "Ollama + huggingface-cli (opt-in)"
  command -v ollama >/dev/null 2>&1 || curl -fsSL https://ollama.com/install.sh | sh >>"$LOG" 2>&1 || say "  ollama install failed"
  command -v pipx >/dev/null 2>&1 && { pipx install huggingface_hub >>"$LOG" 2>&1 || true; }; fi
if want extras; then say "extras (ruby, socat, nmap)"; api ruby socat nmap; fi
if want llmrl; then say "llmrl — HuggingFace model browser/downloader (Node)"
  if ! command -v npm >/dev/null 2>&1; then
    say "  npm not present — install 'node' group first; skipping llmrl"
  elif [ ! -f /tmp/setup-llmrl.sh ]; then
    say "  /tmp/setup-llmrl.sh not staged by host installer; skipping llmrl"
  else
    mkdir -p /opt
    ( cd /opt && MODEL_DIR="${MODEL_DIR:-/opt/llm-models}" bash /tmp/setup-llmrl.sh ) >>"$LOG" 2>&1 \
      || say "  llmrl bootstrap had issues — see $LOG"
    command -v llmrl >/dev/null 2>&1 && say "  llmrl ready (project at /opt/llmrl, models default /opt/llm-models)"
  fi
fi

say "=== summary ==="
for b in gcc make cmake git python3 pip3 node npm forge cast anvil hardhat solc docker sshd gh cloudflared wrangler tailscale rustc go ollama llmrl; do
  if command -v "$b" >/dev/null 2>&1; then say "  present: $b"; fi
done
say "Enabled services:"; systemctl list-unit-files --state=enabled 2>/dev/null | grep -E 'ssh|docker' | tee -a "$LOG" || true
say "DONE — full log at $LOG (inside the persistence)"
ESS
  sudo chmod +x "$mnt/tmp/uca-essentials.sh"
  # Stage the llmrl bootstrapper so the 'llmrl' opt-in group can find it inside the chroot.
  if [[ -f "$USB_DIR/scripts/setup-llmrl.sh" ]]; then
    sudo cp "$USB_DIR/scripts/setup-llmrl.sh" "$mnt/tmp/setup-llmrl.sh" 2>/dev/null || true
    sudo chmod +x "$mnt/tmp/setup-llmrl.sh" 2>/dev/null || true
  fi
  _menu_info "Running comprehensive installer inside the persistence (this can take a while)..."
  if sudo chroot "$mnt" /bin/bash /tmp/uca-essentials.sh "$groups"; then
    _menu_success "Tooling installed into the USB persistence (groups: $groups)"
    _menu_info "Services (ssh/docker) are ENABLED — they become ACTIVE on boot."
    _menu_info "Verify at runtime: boot headless (opt 5), then 'Validate VM services' (this menu)."
  else
    _menu_warn "Installer reported issues — see /var/log/uca-essentials.log inside the volume"
  fi
  _menu_info "Cleaning up mounts..."
  _uca_unmount_tree "$mnt"
}

# Validate that key services are installed+enabled in a persistence volume
# (offline check via chroot) and, if a VM is running, that they are ACTIVE
# (runtime check via SSH).
_uca_validate_services() {
  _menu_header "Validate Persistence Services"
  _menu_subheader "offline (enabled) + runtime (active via SSH)"
  local vol; vol=$(_uca_select_volume) || { _menu_error "No persistence volume found"; return 1; }
  echo ""
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: chroot $vol -> systemctl is-enabled ssh docker; ssh -p $UCA_QEMU_SSH_PORT is-active"
    return 0
  fi
  _menu_subheader "Offline check (installed + enabled-at-boot)"
  _uca_with_chroot "$vol" '
    for s in ssh sshd docker containerd; do
      if systemctl list-unit-files 2>/dev/null | grep -q "^$s"; then
        printf "  %-12s installed, enabled=%s\n" "$s" "$(systemctl is-enabled "$s" 2>/dev/null || echo no)"
      fi
    done
    for b in sshd dockerd node python3 rustc ollama; do
      command -v "$b" >/dev/null 2>&1 && printf "  bin present: %s\n" "$b"
    done
  ' || _menu_warn "Offline check had issues"
  echo ""
  _menu_subheader "Runtime check (needs the VM booted — option 5)"
  if _menu_confirm "Is the headless VM running and do you want to SSH-check it?"; then
    printf "  SSH username [ubuntu]: "; local u; read -r u; u="${u:-ubuntu}"
    ssh -p "$UCA_QEMU_SSH_PORT" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o ConnectTimeout=8 "${u}@localhost" \
      'for s in ssh docker; do printf "  %-10s active=%s\n" "$s" "$(systemctl is-active $s 2>/dev/null)"; done; echo "  uname: $(uname -a)"' \
      || _menu_warn "Could not reach the VM over SSH (booted? sshd up? port $UCA_QEMU_SSH_PORT?)"
  fi
}

# Configure OS-aware autostart of the headless USB VM. On Linux this installs a
# systemd *user* service; other OSes get clear guidance. The VM provides host
# compute + SSH port-forward, so the autostart is necessarily host-side.
_uca_boot_autostart() {
  _menu_header "Headless-Boot Autostart"
  _menu_subheader "HOST — auto-launch the USB VM (OS-aware)"
  local os; os=$(detect_os 2>/dev/null || echo "Unknown")
  _menu_info "Detected OS: $os"
  local dev="${SELECTED_DEVICE:-<set via option 14>}"
  echo ""
  case "$os" in
    Linux|WSL)
      local unit_dir="$HOME/.config/systemd/user"
      local unit="$unit_dir/usb-headless.service"
      _menu_info "systemd user service: $unit"
      _menu_item "1" "Enable autostart (snapshot, SSH :$UCA_QEMU_SSH_PORT)" "" ""
      _menu_item "2" "Disable autostart" "" ""
      _menu_item "3" "Show service status" "" ""
      _menu_item "0" "Back"
      _menu_prompt "Select option"
      local c; read -r c
      case "$c" in
        1)
          [[ -b "${SELECTED_DEVICE:-}" ]] || { _menu_error "Set a USB device first (option 14)"; return 1; }
          _uca_require_host_dep qemu-system-x86_64 "qemu-system-x86 qemu-utils" \
            "The autostart launches QEMU on the host to run the USB headless with SSH forwarding." || return 1
          if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would write $unit and enable it"; return 0; fi
          mkdir -p "$unit_dir"
          local kvm=""; [[ -e /dev/kvm ]] && kvm="--enable-kvm"
          cat > "$unit" <<EOF
[Unit]
Description=USB-Hemlock headless boot (QEMU + SSH forward)
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/qemu-system-x86_64 $kvm -m $UCA_QEMU_RAM -smp $UCA_QEMU_CPUS -drive file=$SELECTED_DEVICE,format=raw,if=virtio -boot c -netdev user,id=net0,hostfwd=tcp::${UCA_QEMU_SSH_PORT}-:22 -device virtio-net-pci,netdev=net0 -nographic -snapshot
Restart=no

[Install]
WantedBy=default.target
EOF
          if command -v systemctl >/dev/null 2>&1; then
            systemctl --user daemon-reload 2>/dev/null || true
            systemctl --user enable usb-headless.service 2>/dev/null \
              && _menu_success "Autostart enabled (starts on next login; 'systemctl --user start usb-headless' to run now)" \
              || _menu_warn "Wrote $unit but could not enable via systemctl --user"
          else
            _menu_warn "systemctl not available — wrote $unit but cannot enable it"
          fi
          ;;
        2)
          if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would disable + remove $unit"; return 0; fi
          systemctl --user disable usb-headless.service 2>/dev/null || true
          rm -f "$unit"; systemctl --user daemon-reload 2>/dev/null || true
          _menu_success "Autostart disabled"
          ;;
        3) systemctl --user status usb-headless.service --no-pager 2>&1 | head -15 || _menu_info "(not installed)" ;;
        0) return 0 ;;
        *) _menu_error "Invalid option: $c" ;;
      esac
      ;;
    macOS)
      _menu_info "On macOS, autostart uses a launchd agent."
      _menu_info "Create ~/Library/LaunchAgents/com.usbhemlock.headless.plist invoking:"
      _menu_info "  qemu-system-x86_64 ... -drive file=$dev,format=raw,if=virtio -nographic -snapshot"
      _menu_info "then: launchctl load ~/Library/LaunchAgents/com.usbhemlock.headless.plist"
      _menu_warn "Automated macOS install not yet wired — guidance only."
      ;;
    *)
      _menu_warn "Autostart not implemented for '$os'. Run headless boot manually (option 5)."
      ;;
  esac
}

# ════════════════════════════════════════════════════════════════════════════
# Hemlock Manager (opt-in; revealed via --hemlock / -H)
# ════════════════════════════════════════════════════════════════════════════
# Consolidates the former options 8/9/10 (TUI / Status / Master Deploy) into
# a single submenu. Future work (H1–H5) will fill in: dynamic volume CRUD,
# Hemlock Doctor wired to doctor_bridge, mode switcher, gateway-token
# bootstrap, per-process log viewer, agent/crew CRUD via volumes.
_run_hemlock_manager() {
  _menu_header "Hemlock Manager"
  _menu_subheader "CONTAINER — gateway, agents, crews, deploy, doctor"
  local has_dir="no"
  [[ -n "$HEMLOCK_DIR" && -d "$HEMLOCK_DIR/scripts" ]] && has_dir="$HEMLOCK_DIR"
  echo ""
  printf "  ${BOLD}HEMLOCK_DIR:${NC} %s\n" "${HEMLOCK_DIR:-<not detected>}"
  printf "  ${BOLD}Container :${NC} %s\n" "$(docker ps -f name=hemlock_runtime --format '{{.Status}}' 2>/dev/null || echo '<docker unavailable>')"
  printf "  ${BOLD}Env       :${NC} %s\n" "${UCA_ENVIRONMENT:-?}"
  echo ""
  _menu_item "1" "Launch in-container TUI"        "" "interactive agent menu"
  _menu_item "2" "Runtime status"                  "" "docker ps + healthcheck"
  _menu_item "3" "Master Deploy (DEPLOY.sh)"      "" "full stack — needs root"
  _menu_item "4" "Hemlock Doctor"                  "" "health check (8 categories)"
  _menu_item "5" "Launch Hemlock Control (GUI)"    "" "OpenClaw Control web UI, app-mode (CL-012)"
  _menu_item "6" "Volume management"               "" "list/inspect/backup/destroy hemlock_* volumes (CL-014)"
  _menu_item "7" "Check for updates"                "" "self-update with rollback (.auto-update.sh)"
  _menu_item "8" "Skills repo sync"                 "" "pull drdeeks/skills + manage daily timer (CL-016)"
  _menu_item "9" "Crew PM blueprint workflow"       "" "PM interrogation → triple-confirm → crew (CL-019)"
  _menu_item "10" "Register agent on-chain (stub)"   "" "registrar: create+register agent (CL-020)"
  _menu_item "11" "Registry audit"                   "" "list registrar entries + verify attestations"
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local choice; read -r choice
  case "$choice" in
    1) _run_hemlock_tui ;;
    2) _run_hemlock_status ;;
    3) _run_deploy ;;
    4) _run_hemlock_doctor ;;
    5) _run_hemlock_control ;;
    6) _run_hemlock_volumes ;;
    7) _run_hemlock_update ;;
    8) _run_hemlock_skills_sync ;;
    9) _run_hemlock_pm_blueprint ;;
    10) _run_hemlock_register_agent ;;
    11) _run_hemlock_registry_audit ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $choice" ;;
  esac
}

# Registrar — create + register an agent on-chain (CL-020 stub mode).
_run_hemlock_register_agent() {
  _menu_header "Register Agent On-Chain"
  _menu_subheader "CONTAINER — registrar (stub mode: local ledger; real RPC follow-up)"
  if ! docker ps -q -f name=hemlock_runtime 2>/dev/null | grep -q .; then
    _menu_warn "hemlock_runtime not running"; return 0
  fi
  printf "  Agent ID (e.g. alice, tom): "
  local id; read -r id; [[ -z "$id" ]] && { _menu_info "Aborted"; return 0; }
  printf "  Display name [default: \$id]: "
  local name; read -r name; [[ -z "$name" ]] && name="$id"
  printf "  Model [default: anthropic/claude-sonnet-4-5]: "
  local model; read -r model; [[ -z "$model" ]] && model="anthropic/claude-sonnet-4-5"
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: docker exec hemlock_runtime /scripts/agent-register.sh --id $id --name '$name' --model $model"
    return 0
  fi
  docker exec -e HEMLOCK_NONINTERACTIVE=1 hemlock_runtime /scripts/agent-register.sh \
    --id "$id" --name "$name" --model "$model"
}

# Registrar — list registry entries + verify attestations
_run_hemlock_registry_audit() {
  _menu_header "Registry Audit"
  _menu_subheader "CONTAINER — registrar local ledger contents"
  if ! docker ps -q -f name=hemlock_runtime 2>/dev/null | grep -q .; then
    _menu_warn "hemlock_runtime not running"; return 0
  fi
  docker exec hemlock_runtime sh -c '
    if [ -f /data/agents/registrar/.secrets/local-registry.json ]; then
      echo "=== Local Registry ==="
      cat /data/agents/registrar/.secrets/local-registry.json | python3 -m json.tool 2>/dev/null
      echo ""
      echo "=== Recent log entries ==="
      tail -20 /data/agents/registrar/logs/registry.log 2>/dev/null || echo "(no log entries)"
    else
      echo "Registry not yet initialized — register first agent via option 10"
    fi
  '
}

# Crew Project Manager blueprint workflow (CL-019). Drives the in-container
# crew-pm-blueprint.sh script that interrogates the user with a 6-question
# drilled-down questionnaire, renders a blueprint JSON, triple-confirms it,
# recommends crew members from the agent registry, and hands off to
# crew-create.sh with the blueprint wired into crew.yaml.
_run_hemlock_pm_blueprint() {
  _menu_header "Crew PM Blueprint Workflow"
  _menu_subheader "CONTAINER — interrogate → blueprint → triple-confirm → crew"
  if ! command -v docker >/dev/null 2>&1; then _menu_error "docker not installed"; return 1; fi
  local container="hemlock_runtime"
  if ! docker ps -q -f name="$container" 2>/dev/null | grep -q .; then
    _menu_warn "$container not running — start it first (option 19 → 5 or 3)"
    return 0
  fi
  echo ""
  _menu_item "1" "Run PM interrogation (interactive — 6 questions + 3 confirms)"
  _menu_item "2" "Run with answers file (non-interactive, --answers /tmp/<file>.json)"
  _menu_item "3" "List existing blueprints (/data/crews/.blueprints/)"
  _menu_item "0" "Back"
  _menu_prompt "Select"
  local c; read -r c
  case "$c" in
    1)
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: docker exec -it $container /scripts/crew-pm-blueprint.sh"; return 0; }
      docker exec -it "$container" /scripts/crew-pm-blueprint.sh
      ;;
    2)
      printf "  Answers file path (inside container, e.g. /tmp/answers.json): "
      local af; read -r af
      [[ -z "$af" ]] && { _menu_info "Aborted"; return 0; }
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: HEMLOCK_NONINTERACTIVE=1 docker exec $container /scripts/crew-pm-blueprint.sh --answers $af"; return 0; }
      docker exec -e HEMLOCK_NONINTERACTIVE=1 "$container" /scripts/crew-pm-blueprint.sh --answers "$af"
      ;;
    3) docker exec "$container" sh -c 'ls -la /data/crews/.blueprints/ 2>/dev/null || echo "(none yet)"' ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $c" ;;
  esac
}

# Skills repo orchestrator (CL-016). Skills live INSIDE the container at /skills,
# a named docker volume. Image bakes a clone of github.com/drdeeks/skills at
# /opt/skills_seed; entrypoint rsyncs it into /skills on first start; an
# in-container cron pulls updates daily (03:17). This menu lets the operator
# trigger a pull on-demand, inspect status, or browse skills, all via docker
# exec — no host filesystem coupling.
_run_hemlock_skills_sync() {
  _menu_header "Hemlock Skills Sync"
  _menu_subheader "CONTAINER — /skills named volume, seeded from github.com/drdeeks/skills"
  if ! command -v docker >/dev/null 2>&1; then
    _menu_error "docker not installed on this host"; return 1
  fi
  local container="hemlock_runtime"
  if ! docker ps -q -f name="$container" 2>/dev/null | grep -q .; then
    _menu_warn "$container is not running — start it first (option 19 → 5 or 3)"
    return 0
  fi

  # Status: ask container for count + last cron run
  local skill_count head_commit cron_state
  skill_count=$(docker exec "$container" sh -c 'ls /skills 2>/dev/null | grep -v "^\." | wc -l' 2>/dev/null || echo "?")
  head_commit=$(docker exec "$container" sh -c 'cd /skills && git rev-parse --short HEAD 2>/dev/null' 2>/dev/null || echo "<not-git>")
  cron_state=$(docker exec "$container" sh -c 'pgrep -x cron >/dev/null && echo running || echo not-running' 2>/dev/null || echo "?")
  printf "  ${BOLD}Container    :${NC} %s\n" "$container"
  printf "  ${BOLD}Skills count :${NC} %s entries\n" "$skill_count"
  printf "  ${BOLD}HEAD commit  :${NC} %s\n" "$head_commit"
  printf "  ${BOLD}Cron daemon  :${NC} %s (scheduled 03:17 daily)\n" "$cron_state"
  echo ""
  _menu_item "1" "Pull now (git pull --ff-only inside container)"
  _menu_item "2" "Pull now — FORCE (git reset --hard origin/main)"
  _menu_item "3" "Show last sync log"
  _menu_item "4" "List skill entries"
  _menu_item "5" "Re-seed /skills from /opt/skills_seed (destructive)"
  _menu_item "0" "Back"
  _menu_prompt "Select"
  local c; read -r c
  case "$c" in
    1)
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: docker exec $container sh -c 'cd /skills && git pull --ff-only'"; return 0; }
      docker exec "$container" sh -c 'cd /skills && git pull --ff-only' 2>&1
      ;;
    2)
      _menu_warn "FORCE discards local edits in the /skills volume"
      _menu_confirm "Proceed?" || return 0
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: docker exec $container sh -c 'cd /skills && git fetch && git reset --hard origin/main'"; return 0; }
      docker exec "$container" sh -c 'cd /skills && git fetch origin && git reset --hard origin/main' 2>&1
      ;;
    3)
      docker exec "$container" sh -c 'tail -30 /var/log/hemlock-skills-sync.log 2>/dev/null || echo "(no log yet)"' 2>&1
      ;;
    4)
      docker exec "$container" sh -c 'ls /skills | grep -v "^\." | head -40' 2>&1
      ;;
    5)
      _menu_warn "Re-seed: rsync /opt/skills_seed/ → /skills/ (destructive)"
      _menu_confirm "Proceed?" || return 0
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: re-seed from /opt/skills_seed"; return 0; }
      docker exec "$container" sh -c 'rm -f /skills/.hemlock_skills_seeded && rsync -a --delete /opt/skills_seed/ /skills/ && date -Iseconds > /skills/.hemlock_skills_seeded' 2>&1
      _menu_success "Re-seeded"
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $c" ;;
  esac
}

# Hemlock self-update — thin wrapper around hemlock/hemlock-runtime/.auto-update.sh.
# That script ships HTTPS-only, SHA256-verified, with rollback (5 versions).
# AUTO_UPDATE_URL is unset by default (silent network calls are off); this
# wizard prompts the operator for the URL once and persists it to the
# Hemlock runtime env file.
_run_hemlock_update() {
  _menu_header "Hemlock Self-Update"
  _menu_subheader "CONTAINER — pulls latest .auto-update.sh, verifies SHA256, rolls back on failure"
  local upd="$HEMLOCK_DIR/.auto-update.sh"
  if [[ ! -x "$upd" ]]; then
    _menu_error ".auto-update.sh missing at $upd"
    return 1
  fi
  local env_file="$HEMLOCK_DIR/.auto-update.env"
  if [[ -f "$env_file" ]]; then
    # shellcheck disable=SC1090
    source "$env_file"
  fi
  if [[ -z "${AUTO_UPDATE_URL:-}" ]]; then
    _menu_warn "AUTO_UPDATE_URL not configured."
    _menu_info "Provide the raw HTTPS URL to the upstream .auto-update.sh (and its .sha256)."
    printf "  AUTO_UPDATE_URL (or blank to abort): "
    local url; read -r url
    [[ -z "$url" ]] && { _menu_info "Aborted"; return 0; }
    printf "  AUTO_UPDATE_SIG_URL (blank for {url}.sha256): "
    local sig; read -r sig
    [[ -z "$sig" ]] && sig="${url}.sha256"
    {
      echo "AUTO_UPDATE_URL=\"$url\""
      echo "AUTO_UPDATE_SIG_URL=\"$sig\""
    } > "$env_file"
    chmod 600 "$env_file"
    export AUTO_UPDATE_URL="$url" AUTO_UPDATE_SIG_URL="$sig"
    _menu_success "Saved config to $env_file"
  fi
  _menu_item "1" "Check for updates (run if interval elapsed)"
  _menu_item "2" "Force update now"
  _menu_item "3" "List rollback versions"
  _menu_item "4" "Rollback to latest"
  _menu_item "5" "Show current config"
  _menu_item "0" "Back"
  _menu_prompt "Select"
  local c; read -r c
  case "$c" in
    1)
      if [[ "$DRY_RUN" == "true" ]]; then _menu_info "DRY RUN: would run $upd"; return 0; fi
      bash "$upd"
      ;;
    2)
      _menu_warn "Force update bypasses interval check"
      _menu_confirm "Proceed?" || return 0
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: $upd --force"; return 0; }
      bash "$upd" --force
      ;;
    3) bash "$upd" --rollback-list ;;
    4)
      _menu_warn "Rollback restores the previous .auto-update.sh"
      _menu_confirm "Proceed?" || return 0
      [[ "$DRY_RUN" == "true" ]] && { _menu_info "DRY RUN: $upd --rollback"; return 0; }
      bash "$upd" --rollback
      ;;
    5)
      printf "  AUTO_UPDATE_URL     : %s\n" "${AUTO_UPDATE_URL:-<unset>}"
      printf "  AUTO_UPDATE_SIG_URL : %s\n" "${AUTO_UPDATE_SIG_URL:-<unset>}"
      printf "  Config file         : %s\n" "$env_file"
      printf "  Script              : %s\n" "$upd"
      ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $c" ;;
  esac
}

# ── H2 — Volume orchestrator submenu (CL-014) ───────────────────────────────
# Lists every docker volume labelled framework=hemlock, lets the operator
# inspect, back up, or destroy individual volumes. Pure docker — no host
# binds, no Docker socket inside the container. Backups stream the volume
# contents into a local tarball via a throwaway alpine container, matching
# the restart-on-CRUD pattern locked in CL-012.
_uca_hemlock_volume_list() {
  docker volume ls --filter label=framework=hemlock \
    --format '{{.Name}}\t{{.Labels}}' 2>/dev/null
}

_uca_hemlock_volume_kind() {
  case "$1" in
    hemlock_agent_*) printf 'agent\n';;
    hemlock_crew_*)  printf 'crew\n';;
    hemlock_skills*) printf 'skills\n';;
    *)               printf 'other\n';;
  esac
}

_run_hemlock_volumes() {
  _menu_header "Hemlock Volume Management"
  _menu_subheader "CONTAINER — docker named volumes (labelled framework=hemlock)"
  if ! command -v docker >/dev/null 2>&1; then
    _menu_error "docker not installed on this host"; return 1
  fi

  local rows
  rows=$(_uca_hemlock_volume_list)
  if [[ -z "$rows" ]]; then
    _menu_warn "No hemlock-labelled volumes found."
    _menu_info "Create one by running scripts/agent-create.sh or scripts/crew-create.sh inside the runtime."
    return 0
  fi

  echo ""
  printf "  ${BOLD}%-4s %-32s %s${NC}\n" "#" "Volume" "Kind"
  local -a names=()
  local i=0
  while IFS=$'\t' read -r name labels; do
    [[ -z "$name" ]] && continue
    i=$((i + 1))
    names+=("$name")
    printf "  %-4s %-32s %s\n" "$i" "$name" "$(_uca_hemlock_volume_kind "$name")"
  done <<< "$rows"
  echo ""
  _menu_item "i <N>" "Inspect volume metadata + on-disk size"
  _menu_item "b <N>" "Backup volume to tarball (./hemlock-backups/<name>-<ts>.tgz)"
  _menu_item "d <N>" "Destroy volume (refuses if in use; ask --force to retry)"
  _menu_item "r"     "Refresh list"
  _menu_item "0"     "Back"
  _menu_prompt "Action"
  local action; read -r action
  [[ -z "$action" || "$action" == "0" ]] && return 0
  if [[ "$action" == "r" ]]; then _run_hemlock_volumes; return $?; fi

  local op idx force=""
  op=$(printf '%s\n' "$action" | awk '{print $1}')
  idx=$(printf '%s\n' "$action" | awk '{print $2}')
  [[ "$(printf '%s' "$action" | awk '{print $3}')" == "--force" ]] && force="--force"
  if ! [[ "$idx" =~ ^[0-9]+$ ]] || (( idx < 1 || idx > ${#names[@]} )); then
    _menu_error "Bad index: '$idx'"; return 1
  fi
  local target="${names[$((idx - 1))]}"

  case "$op" in
    i)
      _menu_info "docker volume inspect $target"
      docker volume inspect "$target" 2>&1 | head -40
      _menu_info "Disk usage:"
      docker run --rm -v "${target}:/v" alpine:3 du -sh /v 2>/dev/null \
        || _menu_warn "(du failed — image may need to pull)"
      ;;
    b)
      local out_dir="./hemlock-backups"
      mkdir -p "$out_dir"
      local ts; ts=$(date +%Y%m%d-%H%M%S)
      local out_file="${out_dir}/${target}-${ts}.tgz"
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: would tar $target → $out_file"
        return 0
      fi
      _menu_info "Backing up $target → $out_file"
      if docker run --rm -v "${target}:/v:ro" -v "$(pwd)/${out_dir}:/out" alpine:3 \
            sh -c "tar -C /v -czf /out/${target}-${ts}.tgz ." 2>&1; then
        _menu_success "Wrote $out_file ($(du -sh "$out_file" | awk '{print $1}'))"
      else
        _menu_error "Backup failed"
      fi
      ;;
    d)
      _menu_warn "About to remove volume: $target"
      _menu_info "This is destructive — back it up first if you might need it."
      _menu_confirm "Proceed?" || return 0
      if [[ "$DRY_RUN" == "true" ]]; then
        _menu_info "DRY RUN: would 'docker volume rm $force $target'"
        return 0
      fi
      if docker volume rm $force "$target" 2>&1; then
        _menu_success "Removed $target"
      else
        _menu_warn "Removal failed (likely in use). Stop the runtime container or rerun with --force."
        _menu_info "Hint: $op $idx --force"
      fi
      ;;
    *)
      _menu_error "Unknown action: $op (use i/b/d/r/0)"
      ;;
  esac
}

# ── H7 — Gateway token resolver + GUI launcher (CL-012/CL-013) ──────────────
# Resolves the OpenClaw gateway token without forcing the user to paste it.
# Priority: container env var → `openclaw dashboard` parse. Returns 1 if the
# container is down or no token can be obtained. NOT cached on disk —
# regenerating is fast (~1s) and avoids leaving a secret in a sourced config.
_uca_hemlock_token() {
  docker ps -q -f name=hemlock_runtime 2>/dev/null | grep -q . || return 1
  local tok
  tok=$(docker exec hemlock_runtime sh -c 'printenv OPENCLAW_GATEWAY_TOKEN 2>/dev/null' 2>/dev/null | tr -d '[:space:]')
  if [[ -z "$tok" ]]; then
    tok=$(docker exec hemlock_runtime openclaw dashboard 2>/dev/null \
          | grep -oE '#token=[a-f0-9]+' | head -1 | sed 's/^#token=//')
  fi
  [[ -z "$tok" ]] && return 1
  printf '%s\n' "$tok"
}

# Launch the Hemlock GUI: OpenClaw Control web UI in chromium app-mode.
# Auto-starts the container if stopped (with confirmation). Auto-fills the
# auth token. Falls back to xdg-open if no chromium-family browser exists.
_run_hemlock_control() {
  _menu_header "Hemlock Control (GUI)"
  _menu_subheader "CONTAINER — OpenClaw Control SPA, chromium app-mode"

  # Container up?
  if ! docker ps -q -f name=hemlock_runtime 2>/dev/null | grep -q .; then
    _menu_warn "hemlock_runtime is not running."
    if ! _menu_confirm "Start it now?"; then return 1; fi
    if ! docker start hemlock_runtime >/dev/null 2>&1; then
      _menu_error "Failed to start container — try option 3 (Master Deploy)"; return 1
    fi
    _menu_info "Container starting; waiting up to 30s for healthy state..."
    local i=0
    while [[ $i -lt 30 ]]; do
      [[ "$(docker inspect -f '{{.State.Health.Status}}' hemlock_runtime 2>/dev/null)" == "healthy" ]] && break
      sleep 1; i=$((i + 1))
    done
    [[ $i -ge 30 ]] && _menu_warn "Container still not healthy after 30s — proceeding anyway"
  fi

  # Token (auto-fills #token=... in the URL so user never sees the auth wall).
  local tok url="http://localhost:18789/"
  tok=$(_uca_hemlock_token 2>/dev/null) || true
  if [[ -n "$tok" ]]; then
    url="http://localhost:18789/#token=${tok}"
    _menu_info "Token auto-resolved (${#tok} chars)"
  else
    _menu_warn "Token could not be resolved — you may hit the auth wall in the UI."
  fi
  _menu_info "URL : $url"

  # Browser. Prefer chromium-family for true app-mode; fall back to xdg-open.
  local browser=""
  for cand in chromium chromium-browser google-chrome google-chrome-stable; do
    command -v "$cand" >/dev/null 2>&1 && { browser="$cand"; break; }
  done

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$browser" ]]; then
      _menu_info "DRY RUN: $browser --app=$url --class=Hemlock-Control"
    else
      _menu_info "DRY RUN: xdg-open $url  (no chromium-family browser)"
    fi
    return 0
  fi

  mkdir -p "$HOME/.hemlock-control" 2>/dev/null || true
  if [[ -n "$browser" ]]; then
    nohup "$browser" --app="$url" \
      --user-data-dir="$HOME/.hemlock-control" \
      --class=Hemlock-Control \
      --no-default-browser-check --no-first-run \
      >/dev/null 2>&1 &
    _menu_success "Launched (PID $!). Look for the new app window — chromeless, titled 'Hemlock Control'."
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$url" >/dev/null 2>&1 &
    _menu_success "Opened in default browser (PID $!)."
  else
    _menu_error "No browser found. Install chromium or xdg-utils."
    return 1
  fi
}

# Hemlock Doctor — runs the in-container health checks via doctor_bridge.
# Offers: quick (paths/env/imports), full (all 8 categories), --fix, JSON.
_run_hemlock_doctor() {
  _menu_header "Hemlock Doctor"
  _menu_subheader "CONTAINER — health/doctor_bridge.py (8 categories)"
  if ! docker ps -q -f name=hemlock_runtime 2>/dev/null | grep -q .; then
    _menu_error "Container 'hemlock_runtime' is not running."
    _menu_info "Start it via option 3 (Master Deploy) or 'docker compose -f hemlock-runtime/docker-compose.runtime.yml up -d'."
    return 1
  fi
  echo ""
  _menu_item "1" "Quick check"          "" "paths + env + imports"
  _menu_item "2" "Full check"           "" "all 8 validator categories"
  _menu_item "3" "Full check + auto-fix" "" "--fix where safe"
  _menu_item "4" "JSON output (machine-readable)" "" ""
  _menu_item "0" "Back"
  _menu_prompt "Select option"
  local c; read -r c
  local cmd=()
  case "$c" in
    1) cmd=(python3 -m health.doctor_bridge --quick) ;;
    2) cmd=(python3 -m health.doctor_bridge) ;;
    3) cmd=(python3 -m health.doctor_bridge --fix) ;;
    4) cmd=(python3 -m health.doctor_bridge --json) ;;
    0) return 0 ;;
    *) _menu_error "Invalid option: $c"; return 1 ;;
  esac
  if [[ "$DRY_RUN" == "true" ]]; then
    _menu_info "DRY RUN: docker exec hemlock_runtime ${cmd[*]}"
    return 0
  fi
  _menu_info "Running: docker exec hemlock_runtime ${cmd[*]}"
  echo ""
  docker exec hemlock_runtime "${cmd[@]}" || _menu_warn "Doctor reported issues (exit $?)"
}

# ── Text Menu Render/Handler ────────────────────────────────────────────────
# Hemlock is OPT-IN: options 19/20/21 are USB-only by default; option 22
# (Hemlock Manager) only appears when HEMLOCK_ENABLED=true. The OLD options
# 8/9/10 (Hemlock TUI / Status / Master Deploy) collapse into that single
# manager submenu — they're no longer pre-listed.
# CL-030: Is this menu option allowed in the current UCA_MODE?
# usb  → all options allowed
# host → only the local-enhancement subset (alias / ssh / sysman / essentials /
#        bash profile / validation / diag / logs / paths / dry-run toggle).
#        USB setup, usbctl, automount (udev), startup wizard, persistence mgr,
#        USB device setup, device config, USB access, Hemlock are HIDDEN.
_uca_option_visible() {
  local opt="$1" mode="${UCA_MODE:-host}"
  [[ "$mode" == "usb" ]] && return 0
  case "$opt" in
    3|4|5|7|10|13|14|15|16|18) return 0 ;;
    *) return 1 ;;
  esac
}

_main_menu_render() {
  _show_device_status
  printf "\n"
  printf "${BOLD}Mode:${NC} ${CYAN}%s${NC}  (override with --mode usb|host)\n" "${UCA_MODE^^}"
  printf "\n"
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    printf "${BOLD}USB Components:${NC}\n"
    printf "  ${CYAN}1${NC})  USB Setup Assistant        ${GREEN}[USB]${NC}      Interactive Ventoy installer\n"
    printf "  ${CYAN}2${NC})  Unified CLI (usbctl)       ${GREEN}[USB]${NC}      USB/config/alias/validate\n"
  fi
  printf "  ${CYAN}3${NC})  Alias Manager              ${GREEN}[%s]${NC}      Aliases on %s\n" \
    "${UCA_MODE^^}" "$([[ ${UCA_MODE} == usb ]] && echo "USB persistence" || echo "host \$HOME")"
  printf "  ${CYAN}4${NC})  SSH Host Manager           ${GREEN}[%s]${NC}      SSH config on %s\n" \
    "${UCA_MODE^^}" "$([[ ${UCA_MODE} == usb ]] && echo "USB persistence" || echo "host")"
  printf "  ${CYAN}5${NC})  System Manager (sysman)    ${GREEN}[HOST]${NC}     Health/network/disk/services\n"
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    printf "  ${CYAN}6${NC})  USB Auto-Mount             ${GREEN}[HOST]${NC}     udev + systemd setup (initial bridge)\n"
  fi
  printf "  ${CYAN}7${NC})  Build Essentials           ${GREEN}[%s]${NC}     Install dev toolchain\n" "${UCA_MODE^^}"
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    printf "\n${BOLD}Configuration:${NC}\n"
    printf "  ${CYAN}8${NC})  Startup Manager            ${GREEN}[USB+HOST]${NC} Boot scripts & autostart\n"
    printf "  ${CYAN}9${NC})  Persistence Manager        ${GREEN}[USB]${NC}      Persistence partitions\n"
  fi
  printf "  ${CYAN}10${NC}) Bash Profile Manager       ${GREEN}[%s]${NC}      Shell config & aliases\n" "${UCA_MODE^^}"
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    printf "  ${CYAN}11${NC}) USB Device Setup           ${GREEN}[USB]${NC}      Detect/select USB device\n"
    printf "  ${CYAN}12${NC}) Device Config              ${GREEN}[HOST]${NC}     Per-device profiles\n"
  fi
  printf "\n${BOLD}System:${NC}\n"
  printf "  ${CYAN}13${NC}) Run Validation             ${GREEN}[ALL]${NC}      Validate all components\n"
  printf "  ${CYAN}14${NC}) Diagnostics                ${GREEN}[HOST]${NC}     System info & config\n"
  printf "  ${CYAN}15${NC}) View Logs                  ${GREEN}[HOST]${NC}     Log viewer & search\n"
  printf "\n${BOLD}Access & Configuration:${NC}\n"
  printf "  ${CYAN}16${NC}) USB Paths & Environment    ${GREEN}[HOST]${NC}     Configure paths, schema & env\n"
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    printf "  ${CYAN}17${NC}) USB Access & Boot          ${GREEN}[USB+HOST]${NC} Terminal/chroot/QEMU/SSH\n"
  fi
  printf "  ${CYAN}18${NC}) Toggle Dry-Run             Current: ${YELLOW}%s${NC}\n" "$DRY_RUN"
  if [[ "$HEMLOCK_ENABLED" == "true" && "${UCA_MODE:-host}" == "usb" ]]; then
    printf "\n${BOLD}Hemlock:${NC}\n"
    printf "  ${CYAN}19${NC}) Hemlock Manager            ${GREEN}[CONTAINER]${NC} Runtime/agents/crews/deploy\n"
  elif [[ "${UCA_MODE:-host}" != "usb" ]]; then
    printf "\n${DIM}  (USB + Hemlock options hidden — re-launch with --mode usb to reveal)${NC}\n"
  else
    printf "\n${DIM}  (Hemlock options hidden — re-launch with --hemlock or -H to reveal)${NC}\n"
  fi
  printf "\n"
}

# CL-026 / SPEC-T06 (MOD-011): Error-resilient action wrapper.
# Every dispatch is invoked through _dispatch_action so a failing component
# (non-zero exit) prints a clear [FAIL] line and pauses, rather than silently
# returning to the menu (which made debugging impossible) or — worse —
# dropping the operator back to bash.
_dispatch_action() {
  local label="$1"; shift
  if "$@"; then
    return 0
  fi
  local rc=$?
  echo ""
  printf "${RED}[FAIL]${NC} %s exited with code %d\n" "$label" "$rc" >&2
  return $rc
}

_main_menu_handler() {
  local choice="$1"
  # CL-030: block USB-only choices when in host mode (someone typing the
  # hidden number manually).
  if ! _uca_option_visible "$choice" && [[ "$choice" != "18" && "$choice" != "19" ]]; then
    log_error "Option $choice is hidden in HOST mode (re-run with --mode usb)"
    sleep 1
    return 0
  fi
  case "$choice" in
    1)  _dispatch_action "USB Setup"            _run_usb_setup ;;
    2)  _dispatch_action "usbctl"               _run_usbctl ;;
    3)  _dispatch_action "Alias Manager"        _run_alias_manager ;;
    4)  _dispatch_action "SSH Manager"          _run_ssh_manager ;;
    5)  _dispatch_action "System Manager"       _run_sysman ;;
    6)  _dispatch_action "USB Auto-Mount"       _run_automount ;;
    7)  _dispatch_action "Build Essentials"     _run_essentials ;;
    8)  _dispatch_action "Startup Manager"      _run_startup_manager ;;
    9)  _dispatch_action "Persistence Manager"  _run_persistence_manager ;;
    10) _dispatch_action "Bash Profile"         _run_bash_profile ;;
    11) _dispatch_action "USB Device Setup"     _setup_device_interactive ;;
    12) _dispatch_action "Device Config"        _run_device_config ;;
    13) _dispatch_action "Run Validation"       _run_validation ;;
    14) _dispatch_action "Diagnostics"          _run_diag ;;
    15) _dispatch_action "View Logs"            _run_logs ;;
    16) _dispatch_action "USB Paths"            _run_usb_paths ;;
    17) _dispatch_action "USB Access"           _run_usb_access ;;
    18)
      if [[ "$DRY_RUN" == "true" ]]; then
        DRY_RUN=false; export DRY_RUN
        log_info "Dry-run DISABLED"
      else
        DRY_RUN=true; export DRY_RUN
        log_info "Dry-run ENABLED"
      fi
      ;;
    19)
      # CL-026 / SPEC-T04: gate is checked in _main_menu_whiptail too, but
      # text-mode users can still type 19 — re-check here.
      if [[ "$HEMLOCK_ENABLED" == "true" ]]; then
        _dispatch_action "Hemlock Manager"      _run_hemlock_manager
      else
        log_error "Hemlock is opt-in; re-run with --hemlock or -H to enable."
      fi
      ;;
    *)  log_error "Invalid option: $choice"; sleep 1 ;;
  esac
  # CL-026 / SPEC-T06: bypass pause when DRY_RUN=true (CI/scripted use).
  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    echo ""
    printf "${YELLOW}Press Enter to continue...${NC}"
    read -r _ || true
  fi
}

# ── Whiptail Menu ───────────────────────────────────────────────────────────
_main_menu_whiptail() {
  local dry_label="Enable Dry-Run"
  [[ "$DRY_RUN" == "true" ]] && dry_label="Disable Dry-Run"
  local dev_label="USB Device: ${SELECTED_DEVICE:-none}"
  local choice
  # The 3>&1 1>&2 2>&3 dance routes whiptail's selection (normally on stderr)
  # to stdout so command substitution captures it, while the TUI itself draws
  # on the real terminal. A Cancel/ESC makes whiptail exit non-zero — we treat
  # that as "quit the program" by returning non-zero so the caller breaks.
  # Build the menu items dynamically so we can append the Hemlock entry only
  # when --hemlock / -H was passed.
  # CL-030: items vary by UCA_MODE.
  local mode_tag="${UCA_MODE^^}"
  local items=()
  if [[ "${UCA_MODE:-host}" == "usb" ]]; then
    items=(
      "1"  "USB Setup Assistant          [USB]"
      "2"  "Unified CLI (usbctl)         [USB]"
      "3"  "Alias Manager                [USB]"
      "4"  "SSH Host Manager             [USB]"
      "5"  "System Manager (sysman)      [HOST]"
      "6"  "USB Auto-Mount               [HOST]"
      "7"  "Build Essentials             [USB]"
      "8"  "Startup Manager              [USB+HOST]"
      "9"  "Persistence Manager          [USB]"
      "10" "Bash Profile Manager         [USB]"
      "11" "USB Device Setup             [USB]"
      "12" "Device Config                [HOST]"
      "13" "Run Validation               [ALL]"
      "14" "Diagnostics                  [HOST]"
      "15" "View Logs                    [HOST]"
      "16" "USB Paths & Environment      [HOST]"
      "17" "USB Access & Boot            [USB+HOST]"
      "18" "$dry_label"
    )
  else
    items=(
      "3"  "Alias Manager                [HOST]"
      "4"  "SSH Host Manager             [HOST]"
      "5"  "System Manager (sysman)      [HOST]"
      "7"  "Build Essentials             [HOST]"
      "10" "Bash Profile Manager         [HOST]"
      "13" "Run Validation               [ALL]"
      "14" "Diagnostics                  [HOST]"
      "15" "View Logs                    [HOST]"
      "16" "Paths & Environment          [HOST]"
      "18" "$dry_label"
    )
  fi
  if [[ "$HEMLOCK_ENABLED" == "true" && "${UCA_MODE:-host}" == "usb" ]]; then
    items+=( "19" "Hemlock Manager              [CONTAINER]" )
  fi
  if ! choice=$(whiptail --title "USB-Hemlock — Mode: ${mode_tag}" \
    --cancel-button "Quit" --menu \
    "$dev_label\nMode: ${mode_tag} (re-launch with --mode to change)\nSelect a component to manage (Quit/ESC to exit):" 38 78 24 \
    "${items[@]}" \
    3>&1 1>&2 2>&3); then
    return 1
  fi
  # Run the handler in a guarded context so a non-zero return from any
  # component runner cannot trip set -e or break the outer menu loop.
  _main_menu_handler "$choice" || true
}

# CL-030: Boot-time mode selector. Silent USB detect FIRST. If no USB present,
# silently default to UCA_MODE=host (only the local enhancement subset is
# offered). If USB IS present, prompt the operator to choose:
#   1) USB  — install everything to USB persistence; bridges host→USB for
#             compute only; after initial setup, no further host writes.
#   2) HOST — local bash/alias/cleanup only; never touches USB.
#
# Bypass: --mode usb|host CLI flag or pre-set UCA_MODE env var skips the prompt.
_select_uca_mode() {
  # Pre-set wins (CLI flag / env / env.example).
  if [[ -n "${UCA_MODE:-}" ]]; then
    case "${UCA_MODE,,}" in
      usb|host) UCA_MODE="${UCA_MODE,,}"; export UCA_MODE; return 0 ;;
    esac
  fi
  # CL-031: silent detection — find ANY USB (Ventoy or not). The mode prompt
  # fires whenever we see at least one USB so a blank USB can also be routed
  # to USB-mode (so the operator can run "install Ventoy" via option 1).
  local detected="" dev_array=()
  detected=$(_detect_all_usb_devices 2>/dev/null || true)
  read -r -a dev_array <<<"$detected"
  if [[ ${#dev_array[@]} -eq 0 ]]; then
    UCA_MODE="host"; export UCA_MODE
    log_info "No USB detected — running in HOST mode (local enhancements only)"
    return 0
  fi
  # Build a short classification summary for the prompt.
  local has_ventoy=false has_other=false d cls
  for d in "${dev_array[@]}"; do
    cls=$(_classify_usb_device "$d")
    [[ "$cls" == "ventoy" ]] && has_ventoy=true
    [[ "$cls" == "blank" || "$cls" == "formatted" ]] && has_other=true
  done
  echo "" >&2
  printf "${BOLD}${CYAN}USB device(s) detected:${NC}\n" >&2
  for d in "${dev_array[@]}"; do
    cls=$(_classify_usb_device "$d")
    local sz; sz=$(lsblk -d -n -o SIZE "$d" 2>/dev/null | head -1 | tr -d ' ')
    case "$cls" in
      ventoy)    printf "  ${GREEN}•${NC} %s  ${GREEN}[VENTOY]${NC}      %s\n" "$d" "$sz" >&2 ;;
      blank)     printf "  ${YELLOW}•${NC} %s  ${YELLOW}[BLANK]${NC}       %s  (option 1 will install Ventoy)\n" "$d" "$sz" >&2 ;;
      formatted) printf "  ${YELLOW}•${NC} %s  ${YELLOW}[FORMATTED]${NC}   %s  (option 1 will REFORMAT)\n" "$d" "$sz" >&2 ;;
    esac
  done
  echo "" >&2
  printf "${BOLD}Choose what to configure:${NC}\n" >&2
  printf "  ${BOLD}1)${NC} USB   — install/manage Ventoy + persistence + SSH + firewall + boot\n" >&2
  if $has_ventoy && ! $has_other; then
    printf "          bridge ON the USB; host untouched after initial setup.\n" >&2
  elif $has_other && ! $has_ventoy; then
    printf "          bridge — including INSTALLING VENTOY on the blank/formatted drive.\n" >&2
  else
    printf "          bridge ON the USB; existing Ventoy used or blank one initialized.\n" >&2
  fi
  printf "  ${BOLD}2)${NC} HOST  — enhanced bash + alias mgr + system cleanup, host only.\n" >&2
  printf "          No USB writes; existing USB state untouched.\n" >&2
  printf "${YELLOW}Choose [1]: ${NC}" >&2
  local ans=""
  read -r ans </dev/tty 2>/dev/null || ans=""
  ans="${ans:-1}"
  case "$ans" in
    2|h|H|host|HOST) UCA_MODE="host" ;;
    *)               UCA_MODE="usb"  ;;
  esac
  export UCA_MODE
  # CL-030: when USB mode wins, pre-resolve and export the persistence path
  # so child scripts (alias_manager, install-antivirus, bash_profile installer)
  # can compute _uca_install_root without re-implementing detection.
  if [[ "$UCA_MODE" == "usb" ]]; then
    local pfile
    if pfile=$(_uca_primary_persistence 2>/dev/null) && [[ -n "$pfile" ]]; then
      UCA_PERSISTENCE_PATH="$pfile"
      export UCA_PERSISTENCE_PATH
    else
      log_warn "USB mode chosen but no persistence resolved — child scripts will fall back to host paths."
    fi
  fi
  log_info "Mode: ${UCA_MODE^^}${UCA_PERSISTENCE_PATH:+ (persistence=$UCA_PERSISTENCE_PATH)}"
}

# CL-026 / SPEC-T01 (MOD-001, MOD-011): Confirm-before-exit on Ctrl-C.
# The default INT trap kills the menu and drops the operator to a bare
# shell — disorienting. Ask for confirmation; if the answer is no, return
# to the main loop. set_standard_traps must run first so this trap wins.
_menu_intr_handler() {
  echo ""
  printf "${YELLOW}Interrupt received — confirm exit? [y/N]: ${NC}" >&2
  local ans=""
  read -r ans </dev/tty 2>/dev/null || ans="y"
  case "${ans,,}" in
    y|yes) _uca_sudo_cleanup 2>/dev/null || true; exit 130 ;;
    *) return 0 ;;
  esac
}

# ── Main ────────────────────────────────────────────────────────────────────
main() {
  set_standard_traps
  trap '_uca_sudo_cleanup' EXIT TERM
  trap '_menu_intr_handler' INT
  clear 2>/dev/null || true

  log_info "══════════════════════════════════════════════════════════════"
  log_info "  USB-Hemlock Unified Compute Platform — Master Menu"
  log_info "══════════════════════════════════════════════════════════════"

  # Load user-configured paths & environment overrides (if any).
  _uca_load_paths_config
  # Normalize file ownership/perms so later runs DO NOT need sudo for menu actions.
  _uca_normalize_permissions
  # Apply a default (autoboot) USB profile if one is marked — must run before
  # auto-detection so the profile's device/env win.
  _uca_autoload_profile
  # Resolve which environment we're in (usb-boot / usb-mounted / native).
  # Persists once; subsequent runs read from usb-paths.conf without prompting.
  _uca_resolve_environment >/dev/null
  log_info "Environment: ${UCA_ENVIRONMENT:-unknown}; Hemlock: $HEMLOCK_ENABLED"

  # CL-030: Decide which install target the operator wants (USB persistence
  # vs host-local) BEFORE we render the menu, so menu_render can prune
  # USB-only options when in host mode.
  _select_uca_mode

  # Auto-detect USB device if not already set
  if [[ -z "${SELECTED_DEVICE:-}" ]]; then
    local detected
    detected=$(_detect_usb_devices)
    local dev_array=($detected)
    if [[ ${#dev_array[@]} -eq 1 ]]; then
      export SELECTED_DEVICE="${dev_array[0]}"
      log_info "Auto-detected USB device: $SELECTED_DEVICE"
      detect_ventoy_mount 2>/dev/null && log_info "Ventoy mounted at $VENTOY_MOUNT"
    elif [[ ${#dev_array[@]} -gt 1 ]]; then
      log_info "Multiple USB devices detected — select via menu option 14"
    else
      log_info "No USB device detected — set via menu option 14"
    fi
  fi

  # Whether the device was auto-detected or pre-set via SELECTED_DEVICE in the
  # environment, resolve its mount once up front so the status header and the
  # USB submenus reflect reality instead of showing "not mounted".
  if [[ -n "${SELECTED_DEVICE:-}" && -z "${VENTOY_MOUNT:-}" ]]; then
    detect_ventoy_mount 2>/dev/null && log_info "Ventoy mounted at $VENTOY_MOUNT" || true
  fi

  if [[ "$FORCE_TEXT" == "true" || "$HAS_WHIPTAIL" != "true" ]]; then
    # Text-mode loop. We deliberately do NOT use lib/menu_loop here: that
    # helper captures the handler's stdout via command substitution to read a
    # stay/back/exit verdict, which would hide every component's output. The
    # main handler instead prints directly and pauses itself, so we drive it
    # in-line and guard it with `|| true` so no component can trip set -e.
    local choice
    while true; do
      clear 2>/dev/null || true
      print_header "USB-Hemlock Unified Compute Platform"
      _main_menu_render
      printf "${YELLOW}Select option (q=quit): ${NC}"
      if ! read -r choice; then
        printf "\n"
        break
      fi
      case "$choice" in
        q|Q|quit|exit) break ;;
        "") continue ;;
        *) _main_menu_handler "$choice" || true ;;
      esac
    done
  else
    while true; do
      clear 2>/dev/null || true
      _main_menu_whiptail || break
    done
  fi
  log_info "Master menu exited"
}

main "$@"
