# Universal Portable Shell Utilities

## Overview

Shell utilities that work identically across environments: local machine, USB boot, VM, host, any Linux box. These utilities handle environment detection, input handling, tilde expansion, alias management, and universal alias management.

## Environment Detection

### Universal Alias Manager Integration

The alias manager provides universal alias management with automatic environment detection:

```bash
# In bash_enhanced.sh - Universal environment detection

# Detect the best location for portable alias storage
# Priority: USB persistence > detected USB mount > home fallback
_detect_persistent_storage() {
    # 1. Check explicit USB persistence mount
    if [[ -d "/mnt/usb-persistence" && -w "/mnt/usb-persistence" ]]; then
        echo "/mnt/usb-persistence"
        return 0
    fi
    
    # 2. Check systemd mount units for USB persistence
    for mount in $(systemctl list-units --type=mount --no-legend 2>/dev/null | awk '$1 ~ /persistence/ {print $1}'); do
        local where=$(systemctl show "$mount" -p Where --value 2>/dev/null)
        [[ -d "$where" && -w "$where" ]] && { echo "$where"; return 0; }
    done
    
    # 3. Check common USB media mounts
    for media in /media/*/ /run/media/*/; do
        for m in "$media"*/; do
            [[ -d "$m" && -w "$m" && -f "$m/.usb-persistence-marker" ]] && { echo "$m"; return 0; }
        done
    done
    
    # 4. Check for explicit USB flag file anywhere
    if [[ -f "${HOME}/.usb-persistence-path" ]]; then
        local p=$(cat "${HOME}/.usb-persistence-path" 2>/dev/null)
        [[ -d "$p" && -w "$p" ]] && { echo "$p"; return 0; }
    fi
    
    return 1
}

# Initialize portable storage locations
USB_PERSISTENCE=$(_detect_persistent_storage)

# Set primary alias file location
if [[ -n "$USB_PERSISTENCE" ]]; then
    USB_ALIAS_FILE="${USB_PERSISTENCE}/.bash_aliases_usb"
    USB_ALIAS_BACKUP_DIR="${USB_PERSISTENCE}/.alias_backups"
    USB_ALIAS_MANAGER="${USB_PERSISTENCE}/alias_manager.sh"
    export USB_PERSISTENCE USB_ALIAS_FILE USB_ALIAS_BACKUP_DIR USB_ALIAS_MANAGER
    
    # Mark environment as USB-persistent
    export IS_USB_PERSISTENT=1
    echo -e "  ${GREEN}[USB]${NC} Portable aliases enabled at: ${USB_PERSISTENCE}"
else
    USB_ALIAS_FILE="${HOME}/.bash_aliases_usb"
    USB_ALIAS_BACKUP_DIR="${HOME}/.alias_backups"
    USB_ALIAS_MANAGER="${BASH_SOURCE[0]%/*}/alias_manager.sh"
    export IS_USB_PERSISTENT=0
fi

# Load USB-specific aliases if file exists
if [[ -f "$USB_ALIAS_FILE" ]]; then
    source "$USB_ALIAS_FILE"
fi

# Dynamic alias manager finder (searches multiple locations)
_find_alias_manager() {
    local candidates=(
        "${USB_ALIAS_MANAGER:-}"
        "${BASH_SOURCE[0]%/*}/alias_manager.sh"
        "/usr/local/bin/alias_manager.sh"
        "/opt/usb-compute/alias_manager.sh"
    )
    for c in "${candidates[@]}"; do
        [[ -f "$c" ]] && { echo "$c"; return 0; }
    done
    return 1
}

_am_candidates=(
    "${USB_ALIAS_MANAGER:-}"
    "${BASH_SOURCE[0]%/*}/alias_manager.sh"
    "/usr/local/bin/alias_manager.sh"
    "/opt/usb-compute/alias_manager.sh"
)

am() {
    local am_path
    am_path=$(_find_alias_manager)
    if [[ -n "$am_path" ]]; then
        bash "$am_path" "$@"
    else
        echo "alias_manager.sh not found. Searched locations:"
        for c in "${_am_candidates[@]}"; do [[ -n "$c" ]] && echo "  $c"; done
        return 1
    fi
}

# Quick alias manager commands
alias aml='am --list'              # List all aliases
alias ama='am --add'               # Add alias: ama name "cmd" "desc"
alias amr='am --remove'            # Remove alias
alias ams='am --search'            # Search aliases
alias ami='am --import'            # Import from .bashrc
alias ame='am --export'            # Export aliases
alias ammenu='am'                  # Interactive menu
alias alias-location='echo "Alias file: $USB_ALIAS_FILE"'

# Show environment info
alias alias-env='echo "USB_PERSISTENT=$IS_USB_PERSISTENT"; echo "Alias file: $USB_ALIAS_FILE"; echo "Manager: $(_find_alias_manager)"'

# Quick setup for new machines - creates persistence marker
alias alias-init='mkdir -p "${HOME}/.usb-persistence-marker" && echo "$(pwd)" > "${HOME}/.usb-persistence-path" && echo "Marked $(pwd) as USB persistence root"'
```

## Bash Input Handling Fixes

### Common Input Issues and Fixes

| Problem | Cause | Fix |
|---------|-------|-----|
| `read -p` hangs on paste | Escape codes in prompt | Use `echo -ne` + `read -e -r` |
| Paste eats characters | Readline not enabled | Use `read -e -r` |
| Ctrl+C needed to exit prompt | Blocking read | Separate prompt from read: `echo -ne` + `read -e -r` |
| Aliases not expanding | Non-interactive shell | `shopt -s expand_aliases` |

### Proper Input Pattern

```bash
# ❌ BAD - hangs on paste, no readline
read -p "Enter name: " name

# ✅ GOOD - readline enabled, prompt separated
echo -ne "${YELLOW}Enter name: ${NC}"
read -e -r name

# ❌ BAD - prompt and read combined, breaks with complex prompts
read -p "$(echo -e "${YELLOW}Enter: ${NC}")" var

# ✅ GOOD - prompt separate from read
echo -ne "${YELLOW}Enter: ${NC}"
read -e -r var
```

### Enable Readline in Scripts

```bash
# At top of script, after shebang
shopt -s expand_aliases  # Enable alias expansion in non-interactive shells
```

### CLI Command Exit Pattern

```bash
# ❌ BAD - falls through to interactive menu after command
--list)
    list_aliases
    shift
    ;;

# ✅ GOOD - exit after command
--list)
    list_aliases
    exit 0
    ;;
```

## Tilde Expansion

### Universal Tilde Expansion

```bash
# In alias import or file path functions
source_file="${source_file/#~/$HOME}"

# For user-provided paths with tilde
path="${path/#~/$HOME}"
```

## Alias Manager Commands

### Universal Alias Manager (am)

```bash
# Load aliases on any machine
source usb-compute-automation/bash_enhanced.sh

# Import with tilde - WORKS!
ami ~/.bashrc       # ℹ Importing from: $HOME/.bashrc
am --import ~/.bashrc  # Same via CLI

# All CLI commands work & exit properly
am --list              # List (table)
am --list csv          # List (CSV)
am --list json         # List (JSON)
am --add gs "git status" "Git shortcut"
am --search git
am --remove gs
am --import ~/.bashrc
am --export json

# Interactive menu - FIXED
ammenu                   # Proper readline, paste, arrow keys, no hangs

# Environment info
agenv                    # Show detection status
alias-location           # Show alias file path
alias-env                # Show detection status
alias-init               # Mark current dir as USB persistence root
```

### Interactive Menu (Fixed)

```bash
# Now works with:
# - Readline (arrow keys, history, tab completion)
# - Paste support (Ctrl+Shift+V works)
# - No hanging on paste
# - Proper prompt separation

ammenu

# Menu:
# 1) List all aliases
# 2) Add new alias
# 3) Remove alias
# 4) Edit alias
# 5) Search aliases
# 6) Import from .bashrc
# 7) Export aliases
# 8) Open alias file in editor
# 9) View alias file
# 0) Back
```

## Environment Detection

### Universal Detection Logic

```bash
_detect_persistent_storage() {
    # 1. Explicit USB persistence mount
    if [[ -d "/mnt/usb-persistence" && -w "/mnt/usb-persistence" ]]; then
        echo "/mnt/usb-persistence"; return 0; fi
    
    # 2. Systemd mount units
    for mount in $(systemctl list-units --type=mount --no-legend 2>/dev/null | awk '$1 ~ /persistence/ {print $1}'); do
        local where=$(systemctl show "$mount" -p Where --value 2>/dev/null)
        [[ -d "$where" && -w "$where" ]] && { echo "$where"; return 0; }
    done
    
    # 3. USB media with marker
    for media in /media/*/ /run/media/*/; do
        for m in "$media"*/; do
            [[ -d "$m" && -w "$m" && -f "$m/.usb-persistence-marker" ]] && { echo "$m"; return 0; }
        done
    done
    
    # 4. Home fallback marker
    if [[ -f "${HOME}/.usb-persistence-path" ]]; then
        local p=$(cat "${HOME}/.usb-persistence-path" 2>/dev/null)
        [[ -d "$p" && -w "$p" ]] && { echo "$p"; return 0; }
    fi
    
    return 1
}
```

## Quick Reference

### Bash Enhanced Integration

```bash
# Source once
source /path/to/bash_enhanced.sh

# All aliases available
aml              # am --list
ama name "cmd" "desc"   # am --add
amr name         # am --remove
ams query        # am --search
ami ~/.bashrc    # am --import ~/.bashrc
ame json         # am --export json
amenv            # Show environment
alias-env        # Same as amenv
alias-location   # Show alias file path
alias-init       # Mark current dir as USB persistence
ammenu           # Interactive menu
```

### Alias Manager CLI

```bash
./alias_manager.sh              # Interactive menu
./alias_manager.sh --list       # List table
./alias_manager.sh --list csv   # CSV
./alias_manager.sh --list json  # JSON
./alias_manager.sh --add name "cmd" "desc"
./alias_manager.sh --remove name
./alias_manager.sh --search query
./alias_manager.sh --import [file]
./alias_manager.sh --import ~/.bashrc  # with tilde
./alias_manager.sh --export json
./alias_manager.sh --dry-run --add test "echo test" "test alias"
./alias_manager.sh --help
```

## Testing Checklist

```bash
# Test on different environments
✅ Local machine (home fallback)
✅ USB persistence mount
✅ VM with USB passthrough
✅ Non-interactive execution (am --list)
✅ Interactive menu (arrow keys, paste, history)
✅ Tilde expansion (~/.bashrc)
✅ Tilde expansion (~/custom/path)
✅ Duplicate prevention
✅ Auto-backup on changes
✅ Readline history/search
✅ Paste without char loss
✅ Exit after CLI commands
```