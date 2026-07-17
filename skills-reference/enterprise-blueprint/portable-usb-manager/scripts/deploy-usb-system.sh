#!/usr/bin/env bash
# deploy-usb-system.sh — deploy the complete USB management system payload.
#
# Copies the full, self-contained USB system (menu.sh orchestrator + usb/
# library tree: 7 lib modules, usbctl CLI, setup assistant, sysman, tests,
# automount units, ventoy volume profiles, env.example) from this skill's
# references/templates/usb-system/ to a target directory, restores execute
# permissions (templates ship read-only by skill policy), and reports the
# entry points.
#
# The deployed system is 100% standalone — it runs on any Linux system with
# bash, no Hemlock required. Hemlock integration is OPT-IN and hidden by
# default: it only surfaces when the operator passes -H/--hemlock (or sets
# HEMLOCK_ENABLED=true) AND a hemlock-runtime is auto-detected or pointed to
# via HEMLOCK_DIR. Without the flag, nothing Hemlock-related appears.
#
# Usage:
#   deploy-usb-system.sh --target <dir> [--dry-run]
#   deploy-usb-system.sh --help
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAYLOAD="$SCRIPT_DIR/../references/templates/usb-system"
TARGET=""
DRY_RUN=false

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="${2:?--target needs a directory}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 2 ;;
  esac
done

[[ -z "$TARGET" ]] && { echo "error: --target <dir> is required" >&2; exit 2; }
[[ -d "$PAYLOAD" ]] || { echo "error: payload not found at $PAYLOAD" >&2; exit 1; }

prefix=""; $DRY_RUN && prefix="[dry-run] "
echo "${prefix}deploying USB system → $TARGET"

if ! $DRY_RUN; then
  mkdir -p "$TARGET"
  cp -a "$PAYLOAD/." "$TARGET/"
  # Templates ship 0444 — restore working permissions on the deployed copy
  find "$TARGET" -type d -exec chmod 755 {} +
  find "$TARGET" -type f -name "*.sh" -exec chmod 755 {} +
  chmod 755 "$TARGET/usb/hemlock-tui" "$TARGET/usb/cli/usbctl" 2>/dev/null || true
  find "$TARGET" -type f ! -name "*.sh" ! -name "usbctl" ! -name "hemlock-tui" \
    -exec chmod 644 {} +
fi

count=$(find "$PAYLOAD" -type f | wc -l)
echo "${prefix}${count} files"
echo "${prefix}entry points:"
echo "${prefix}  $TARGET/menu.sh              # interactive TUI (USB-first)"
echo "${prefix}  $TARGET/menu.sh --hemlock    # reveal Hemlock Manager (opt-in)"
echo "${prefix}  $TARGET/usb/cli/usbctl       # non-interactive CLI"
echo "${prefix}  $TARGET/usb/usb-setup-assistant.sh"
echo "${prefix}Hemlock stays hidden unless -H/--hemlock is passed AND a"
echo "${prefix}hemlock-runtime is found (sibling dir or HEMLOCK_DIR)."
