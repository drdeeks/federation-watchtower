#!/usr/bin/env bash
# Platform detection and tool selection

if [[ -n "${UCA_PLATFORM_SH_SOURCED:-}" ]]; then
  return 0
fi
UCA_PLATFORM_SH_SOURCED=1

# shellcheck source=lib/core.sh
[[ -n "${UCA_CORE_SH_SOURCED:-}" ]] || source "${BASH_SOURCE[0]%/*}/core.sh"

detect_os() {
  # Echo: macOS | Linux | WSL | Windows | Unknown
  local u; u=$(uname -s 2>/dev/null || echo unknown)
  case "$u" in
    Darwin) echo macOS ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        echo WSL
      else
        echo Linux
      fi
      ;;
    MINGW*|MSYS*|CYGWIN*) echo Windows ;;
    *) echo Unknown ;;
  esac
}

detect_virtualization() {
  # Echo: kvm|hyperv|virtualbox|vmware|parallels|none|unknown
  if command -v systemd-detect-virt >/dev/null 2>&1; then
    local v; v=$(systemd-detect-virt 2>/dev/null || echo unknown)
    [[ "$v" == "none" ]] && { echo none; return; }
    echo "$v"; return
  fi
  echo unknown
}

select_best_tool() {
  # Usage: select_best_tool category
  local category="$1"
  local os; os=$(detect_os)
  local -a preferred
  case "$category" in
    terminal)
      preferred=(gnome-terminal konsole alacritty kitty wezterm xterm tmux)
      ;;
    virtualization)
      case "$os" in
        Linux) preferred=(qemu-system-x86_64 virt-manager virsh virtualbox vmware) ;;
        macOS) preferred=(UTM qemu-system-x86_64 virtualbox vmware-fusion parallels) ;;
        *) preferred=(qemu-system-x86_64 virtualbox) ;;
      esac
      ;;
    container)
      preferred=(docker podman nerdctl)
      ;;
    editor)
      preferred=(code vim nano micro helix zed)
      ;;
    *) preferred=() ;;
  esac
  local t
  for t in "${preferred[@]}"; do
    if command -v "$t" >/dev/null 2>&1; then
      echo "$t"; return 0
    fi
    # macOS .app support
    if [[ "$os" == macOS && -d "/Applications/${t}.app" ]]; then
      echo "$t"; return 0
    fi
  done
  return 1
}
