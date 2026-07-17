#!/usr/bin/env bash
# USB utilities: Ventoy mount/persistence helpers (extracted, unified)

if [[ -n "${UCA_USB_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_USB_SH_SOURCED=1

# shellcheck source=lib/core.sh
[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"
# shellcheck source=lib/platform.sh
[[ -n "${UCA_PLATFORM_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/platform.sh"

# Global mount point variable managed by detect_ventoy_mount/unmount_ventoy
VENTOY_MOUNT=""

detect_ventoy_mount() {
  # Relies on SELECTED_DEVICE exported by caller; sets VENTOY_MOUNT on success
  # Returns: 0 if mounted and Ventoy detected, 1 otherwise
  local os; os=$(detect_os)
  [[ -z "${SELECTED_DEVICE:-}" ]] && return 1

  VENTOY_MOUNT=""

  # Method 1: /proc/mounts
  if [[ -f /proc/mounts ]]; then
    VENTOY_MOUNT=$(grep -m1 "^${SELECTED_DEVICE}[1s1]*[[:space:]]" /proc/mounts 2>/dev/null | awk '{print $2}' || true)
  fi

  # Method 2: df
  if [[ -z "$VENTOY_MOUNT" ]]; then
    if [[ "$os" == macOS ]]; then
      VENTOY_MOUNT=$(df 2>/dev/null | grep -m1 "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
    else
      VENTOY_MOUNT=$(df 2>/dev/null | grep -m1 "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
    fi
  fi

  # Method 3: findmnt (Linux)
  if [[ -z "$VENTOY_MOUNT" ]] && command -v findmnt >/dev/null 2>&1; then
    VENTOY_MOUNT=$(findmnt -n -o TARGET "${SELECTED_DEVICE}1" 2>/dev/null || true)
  fi

  # Method 4: lsblk (Linux)
  if [[ -z "$VENTOY_MOUNT" ]] && command -v lsblk >/dev/null 2>&1; then
    VENTOY_MOUNT=$(lsblk -n -o MOUNTPOINT "${SELECTED_DEVICE}1" 2>/dev/null | head -1 || true)
    [[ "$VENTOY_MOUNT" == "null" ]] && VENTOY_MOUNT=""
  fi

  # Method 5: diskutil (macOS)
  if [[ -z "$VENTOY_MOUNT" && "$os" == macOS ]] && command -v diskutil >/dev/null 2>&1; then
    VENTOY_MOUNT=$(diskutil info "${SELECTED_DEVICE}s1" 2>/dev/null | awk -F': ' '/Mount Point/{print $2}' || true)
  fi

  # Verify Ventoy signature
  if [[ -n "$VENTOY_MOUNT" && -d "$VENTOY_MOUNT" ]]; then
    if compgen -G "$VENTOY_MOUNT/*.iso" >/dev/null || [[ -d "$VENTOY_MOUNT/ventoy" ]] || [[ -d "$VENTOY_MOUNT/persistence" ]]; then
      return 0
    fi
  fi

  # Try mounting to a known path
  local mpt
  if [[ "$os" == macOS ]]; then mpt="/Volumes/Ventoy"; else mpt="/mnt/ventoy"; fi
  mkdir -p "$mpt" 2>/dev/null || true

  if [[ "$os" == macOS ]]; then
    mount "${SELECTED_DEVICE}s1" "$mpt" 2>/dev/null && VENTOY_MOUNT="$mpt"
  else
    mount "${SELECTED_DEVICE}1" "$mpt" 2>/dev/null && VENTOY_MOUNT="$mpt"
    [[ -z "$VENTOY_MOUNT" ]] && mount -t exfat "${SELECTED_DEVICE}1" "$mpt" 2>/dev/null && VENTOY_MOUNT="$mpt"
    [[ -z "$VENTOY_MOUNT" ]] && mount -t ntfs-3g "${SELECTED_DEVICE}1" "$mpt" 2>/dev/null && VENTOY_MOUNT="$mpt"
  fi

  # Final verification
  if [[ -n "$VENTOY_MOUNT" && -d "$VENTOY_MOUNT" ]]; then
    if compgen -G "$VENTOY_MOUNT/*.iso" >/dev/null || [[ -d "$VENTOY_MOUNT/ventoy" ]] || [[ -d "$VENTOY_MOUNT/persistence" ]]; then
      return 0
    fi
    # Mounted wrong target
    unmount_ventoy
    VENTOY_MOUNT=""
  fi
  return 1
}

unmount_ventoy() {
  if [[ -n "$VENTOY_MOUNT" ]]; then
    case "$VENTOY_MOUNT" in
      /Volumes/Ventoy|/mnt/ventoy)
        umount "$VENTOY_MOUNT" 2>/dev/null || true ;;
      *) : ;; # leave user mounts alone
    esac
    VENTOY_MOUNT=""
  fi
}

check_persistence_exists() {
  [[ -n "$VENTOY_MOUNT" ]] || return 1
  [[ -f "$VENTOY_MOUNT/persistence/ubuntu-persistence.dat" ]]
}

get_persistence_size() {
  if [[ -z "$VENTOY_MOUNT" ]]; then echo "unknown"; return; fi
  du -h "$VENTOY_MOUNT/persistence/ubuntu-persistence.dat" 2>/dev/null | cut -f1 || echo "unknown"
}
