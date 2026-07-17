# Popout Terminal Launch for Hemlock TUI

## Overview

The Hemlock Agent Orchestration System supports launching the TUI (Terminal User Interface) in a separate, independent terminal window. This allows the TUI to run continuously while the user continues working in their current terminal.

## Multi-Platform Terminal Detection

The system automatically detects the best available terminal emulator:

```bash
launch_hemlock_popout() {
    local hemlock_tui="$1"
    local hemlock_dir="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}"
    
    print_header "Launching Hemlock TUI in Popout Terminal"
    
    # Detect available terminal emulators
    local terminal_cmd=""
    local terminal_name=""
    
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
        terminal_cmd="tmux new-session -d -s hemlock-tui \\; send-keys 'HEMLOCK_DIR=\"$hemlock_dir\" \"$hemlock_tui\"' Enter \\; attach-session -t hemlock-tui"
        terminal_name="tmux (new session)"
    elif [[ "$OSTYPE" == "darwin"* ]] && command -v osascript &>/dev/null; then
        # macOS - use osascript to open new Terminal window
        osascript <<EOF
tell application "Terminal"
    do script "HEMLOCK_DIR=\"$hemlock_dir\" \"$hemlock_tui\""
    activate
end tell
EOF
        print_success "Launched Hemlock TUI in new macOS Terminal window"
        return 0
    else
        print_error "No supported terminal emulator found."
        print_info "Supported: gnome-terminal, konsole, xterm, terminator, alacritty, kitty, wezterm, tmux"
        print_info "On macOS: Uses native Terminal.app via osascript"
        return 1
    fi
    
    if [[ -n "$terminal_cmd" ]]; then
        print_info "Launching in $terminal_name..."
        # Export HEMLOCK_DIR so the TUI can find the CLI
        HEMLOCK_DIR="$hemlock_dir" $terminal_cmd bash -c "HEMLOCK_DIR=\"$hemlock_dir\" \"$hemlock_tui\"" &
        print_success "Launched Hemlock TUI in new $terminal_name window"
        print_info "The TUI will run independently. Close the window to exit."
    fi
}
```

## Terminal Priority by Platform

| Platform | 1st Choice | 2nd Choice | 3rd Choice | Fallback |
|---|---|---|---|---|
| **Linux** | gnome-terminal | konsole | terminator | xterm |
| **Linux (i3/sway)** | alacritty | kitty | wezterm | foot |
| **macOS** | Terminal.app (osascript) | iTerm2 | Alacritty | xterm |
| **WSL2** | Windows Terminal (wt.exe) | wsl.exe | Alacritty | xterm |
| **Windows** | Windows Terminal | cmd.exe | PowerShell | - |

## Launch Options in USB Setup Assistant

When selecting Option 13 (Hemlock Agent Orchestration), the user sees:

```
Launch Options:
  1) Launch TUI in NEW terminal window (recommended)
  2) Launch TUI in CURRENT terminal
  3) Run Hemlock CLI command (single command)
  4) Show Hemlock status (doctor)
  5) Attach to RUNNING CONTAINER (Hemlock TUI/CLI inside container)
     → All model/agent/skill/MCP/plugin management happens HERE
  q) Cancel
```

### Option 1: Popout Terminal (Recommended)

```bash
case "1" in
    1)
        launch_hemlock_popout "$hemlock_tui"
        ;;
```

### Option 2: Current Terminal

```bash
case "2" in
    2)
        print_info "Launching Hemlock TUI in current terminal..."
        print_info "Press Ctrl+C to exit TUI and return here."
        sleep 2
        "$hemlock_tui"
        ;;
```

### Option 5: Attach to Running Container

```bash
case "5" in
    5)
        if docker ps --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
            print_info "Attaching to hemlock-runtime container..."
            print_info "Running Hemlock TUI inside container (Ctrl+C to exit)"
            docker exec -it hemlock-runtime /scripts/hemlock-tui
        else
            print_error "hemlock-runtime container not running"
            print_info "Deploy Hemlock first (Option 13 in main menu) or start container manually"
        fi
        ;;
```

## Container TUI Integration

### Direct Container Exec

```bash
# Run TUI inside container (from host)
docker exec -it hemlock-runtime /scripts/hemlock-tui
```

### Host CLI Wrapper

The host `hemlock` CLI provides a `tui` command:

```bash
# In /scripts/hemlock (host CLI)
tui() {
    docker exec -it hemlock-runtime /scripts/hemlock-tui
}
```

### TUI Inside Container

The container's `/scripts/hemlock-tui` provides:

- **Dashboard**: Real-time system health
- **Agents**: Create, attach, export, delete agents
- **Crews**: Create, attach, export, delete crews
- **Skills**: Browse 157+ skills
- **Doctor**: System diagnostics
- **Backup**: Full/standard/minimal backups
- **Settings**: Gateway, Telegram, iMessage, MCP, Network

## Popout Terminal Template

For reusability, the popout launch logic is available as a template:

```bash
# templates/launch-popout-terminal.sh
#!/usr/bin/env bash
# Hemlock Popout Terminal Launcher

TUI_SCRIPT="${1:-/scripts/hemlock-tui}"
HEMLOCK_DIR="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}"

# Auto-detect terminal and launch
# ... (same as launch_hemlock_popout function)
```

### Usage

```bash
# From USB Setup Assistant
bash templates/launch-popout-terminal.sh /scripts/hemlock-tui /tmp/hemlock-minimal/hemlock-minimal

# Direct usage
HEMLOCK_DIR=/path/to/hemlock-minimal bash templates/launch-popout-terminal.sh
```

## Environment Variables

| Variable | Purpose | Default |
|---|---|---|
| `HEMLOCK_DIR` | Path to hemlock-minimal directory | `/tmp/hemlock-minimal/hemlock-minimal` |
| `TERMINAL_TOOL` | Override auto-detected terminal | Auto-detected |
| `TUI_SCRIPT` | Path to hemlock-tui script | `/scripts/hemlock-tui` |

## Error Handling

| Error | Resolution |
|---|---|
| No supported terminal | Install gnome-terminal, konsole, alacritty, kitty, wezterm, or tmux |
| macOS osascript fails | Grant Terminal.app accessibility permissions |
| Docker container not running | Deploy Hemlock first (Option 13 in main menu) |
| TUI exits immediately | Check container logs: `docker logs hemlock-runtime` |

## Best Practices

1. **Always prefer popout terminal** (Option 1) for persistent TUI sessions
2. **Use container attach (Option 5)** for direct container interaction
3. **Set `HEMLOCK_DIR`** if hemlock-minimal is in non-standard location
4. **Use tmux fallback** for headless/remote servers
5. **On macOS**: Grant Terminal.app "Full Disk Access" in System Preferences