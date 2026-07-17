#!/usr/bin/env bash
# Hemlock Popout Terminal Launcher Template
# Usage: bash launch-popout-terminal.sh [tui-script] [hemlock-dir]

set -euo pipefail

TUI_SCRIPT="${1:-/scripts/hemlock-tui}"
HEMLOCK_DIR="${2:-/tmp/hemlock-minimal/hemlock-minimal}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error() { echo -e "${RED}✗${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }

print_header "Launching Hemlock TUI in Popout Terminal"

# Detect available terminal emulators
terminal_cmd=""
terminal_name=""

if command -v gnome-terminal &>/dev/null; then
    terminal_cmd="gnome-terminal --"
    terminal_name="GNOME Terminal"
elif command -v konsole &>/dev/null; then
    terminal_cmd="konsole -e"
    terminal_name="Konsole"
elif command -v xterm &>/dev/null; then
    terminal_cmd="xterm -e"
    terminal_name="xterm"
elif command -v terminator &>/dev/null; then
    terminal_cmd="terminator -e"
    terminal_name="Terminator"
elif command -v alacritty &>/dev/null; then
    terminal_cmd="alacritty -e"
    terminal_name="Alacritty"
elif command -v kitty &>/dev/null; then
    terminal_cmd="kitty -e"
    terminal_name="Kitty"
elif command -v wezterm &>/dev/null; then
    terminal_cmd="wezterm start --"
    terminal_name="WezTerm"
elif command -v tmux &>/dev/null; then
    terminal_cmd="tmux new-session -d -s hemlock-tui \\; send-keys 'HEMLOCK_DIR=\"$HEMLOCK_DIR\" \"$TUI_SCRIPT\"' Enter \\; attach-session -t hemlock-tui"
    terminal_name="tmux (new session)"
elif [[ "$OSTYPE" == "darwin"* ]] && command -v osascript &>/dev/null; then
    # macOS - use osascript to open new Terminal window
    osascript <<EOF
tell application "Terminal"
    do script "HEMLOCK_DIR=\"$HEMLOCK_DIR\" \"$TUI_SCRIPT\""
    activate
end tell
EOF
    print_success "Launched Hemlock TUI in new macOS Terminal window"
    exit 0
else
    print_error "No supported terminal emulator found."
    print_info "Supported: gnome-terminal, konsole, xterm, terminator, alacritty, kitty, wezterm, tmux"
    print_info "On macOS: Uses native Terminal.app via osascript"
    exit 1
fi

if [[ -n "$terminal_cmd" ]]; then
    print_info "Launching in $terminal_name..."
    # Export HEMLOCK_DIR so the TUI can find the CLI
    HEMLOCK_DIR="$HEMLOCK_DIR" $terminal_cmd bash -c "HEMLOCK_DIR=\"$HEMLOCK_DIR\" \"$TUI_SCRIPT\"" &
    print_success "Launched Hemlock TUI in new $terminal_name window"
    print_info "The TUI will run independently. Close the window to exit."
fi