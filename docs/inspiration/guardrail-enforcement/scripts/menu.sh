#!/usr/bin/env bash
# Guardrail Enforcement — interactive menu
# ========================================
# A composable front-end for the guardrail toolchain. The watcher (monitor.py)
# and the action/gate (gate.py) are independent tools; this menu lets a user pick
# a directory, choose what to watch, and choose what to trigger — using either
# tool alone or both together. Nothing here is hardcoded: every path is prompted
# or resolved relative to this script.
#
# Non-interactive: responds to --help / --dry-run for inspection and testing.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    cat <<EOF
usage: menu.sh [--help] [--dry-run]

Interactive menu for the guardrail toolchain. Options:
  1) Configure a watcher        -> monitor.py setup   (pick dir + what to watch + what to trigger)
  2) Run watcher once           -> monitor.py scan
  3) Watcher status             -> monitor.py status
  4) Configure a gate/action    -> setup.py           (pre-checks -> loop -> post-checks)
  5) Run gate                   -> gate.py
  6) Install git hooks          -> install_hooks.py
  7) Lock / unlock a directory  -> lock.py            (advisory .loop.lock)
  8) Verify manifest <-> skills <-> git -> verify_manifest.py
  9) Verify signed loop log     -> verify_log.py
  0) Exit

--dry-run prints the option map and exits without prompting (for automation/tests).
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    --dry-run|-n) usage; echo "(--dry-run: no prompt)"; exit 0 ;;
esac

ask() { local q="$1" d="${2:-}"; local a; read -r -p "? $q${d:+ [$d]}: " a || true; echo "${a:-$d}"; }

py() { python3 "$SCRIPT_DIR/$1" "${@:2}"; }

while true; do
    echo ""
    echo "=== Guardrail Enforcement ==="
    echo " 1) Configure a watcher (what dir, what to watch, what to trigger)"
    echo " 2) Run watcher once"
    echo " 3) Watcher status"
    echo " 4) Configure a gate/action"
    echo " 5) Run gate"
    echo " 6) Install git hooks"
    echo " 7) Lock / unlock a directory"
    echo " 8) Verify manifest <-> skills <-> git"
    echo " 9) Verify signed loop log"
    echo " 0) Exit"
    choice="$(ask 'Choose' '0')"
    case "$choice" in
        1)
            dir="$(ask 'Directory to watch' "$(pwd)")"
            cond="$(ask 'What to watch? (skill_version/file_mtime)' 'skill_version')"
            act="$(ask 'What to trigger? (git_commit/shell_command/none)' 'git_commit')"
            py monitor.py setup "$dir" --condition "$cond" --action "$act" --yes
            ;;
        2) dir="$(ask 'Config directory' "$(pwd)")"; py monitor.py scan --config "$dir/.monitor.json" ;;
        3) dir="$(ask 'Config directory' "$(pwd)")"; py monitor.py status --config "$dir/.monitor.json" ;;
        4) dir="$(ask 'Directory to gate' "$(pwd)")"; py setup.py "$dir" ;;
        5) dir="$(ask 'Gated directory' "$(pwd)")"; py gate.py --config "$dir/.gate.json" ;;
        6) repo="$(ask 'Repo path' "$(pwd)")"; py install_hooks.py --repo "$repo" ;;
        7)
            dir="$(ask 'Directory' "$(pwd)")"
            op="$(ask 'acquire/release/check' 'check')"
            py lock.py "$op" "$dir"
            ;;
        8) repo="$(ask 'Skills repo' "$(pwd)")"; py verify_manifest.py --repo "$repo" ;;
        9) log="$(ask 'Loop log path' "$(pwd)/.loop-log.jsonl")"; py verify_log.py "$log" ;;
        0|"") echo "bye"; exit 0 ;;
        *) echo "unknown option: $choice" ;;
    esac
done
