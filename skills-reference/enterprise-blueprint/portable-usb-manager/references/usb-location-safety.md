# USB Location Safety Check

## Problem

Running USB setup scripts from within the USB drive itself causes catastrophic failures:
- Ventoy installation wipes the drive while scripts are running from it
- Persistence formatting corrupts the running filesystem
- `debootstrap` and `chroot` operations fail on the mounted source
- Scripts get corrupted mid-execution

## Solution: Mandatory Location Check

Every USB management script MUST start with a location check that validates the script is running from the host system, not from the USB drive.

## Implementation

```bash
check_script_location() {
    # Check if script is running from a USB-mounted path
    local script_path="$(realpath "${BASH_SOURCE[0]}")"
    
    # Common USB mount points (cross-platform)
    local usb_paths=(
        "/media/*/Ventoy"
        "/mnt/ventoy"
        "/Volumes/Ventoy"
        "/run/media/*/Ventoy"
        "/media/*/usb*"
        "/mnt/usb*"
        # Windows/WSL paths
        "/mnt/c/*/Ventoy"
        "/mnt/d/*/Ventoy"
        "/mnt/e/*/Ventoy"
    )
    
    for pattern in "${usb_paths[@]}"; do
        for path in $pattern; do
            if [[ -d "$path" ]] && [[ "$script_path" == "$path"* ]]; then
                print_error "================================================================="
                print_error "  WARNING: SCRIPT RUNNING FROM USB DRIVE!"
                print_error "================================================================="
                print_error ""
                print_error "  This script MUST run from the HOST system, not from the USB drive."
                print_error ""
                print_error "  Current location: $script_path"
                print_error "  Detected USB path: $path"
                print_error ""
                print_error "  REQUIRED ACTION:"
                print_error "  1. Copy this script to your host system:"
                print_error "     cp \"$script_path\" ~/usb-setup-assistant.sh"
                print_error "  2. Run it from the host:"
                print_error "     sudo bash ~/usb-setup-assistant.sh"
                print_error ""
                print_error "  WHY? Operations like Ventoy installation, persistence formatting, "
                print_error "  debootstrap, and chroot REQUIRE host privileges and will FAIL or "
                print_error "  CORRUPT the USB if run from within the USB environment."
                print_error ""
                print_error "================================================================="
                
                if ! confirm "Continue anyway? (NOT RECOMMENDED)" "n"; then
                    exit 1
                fi
                return 0
            fi
        done
    done
}
```

## Usage

Call as the **very first operation** in `initialize()`:

```bash
initialize() {
    print_header "$SCRIPT_NAME v$VERSION"
    log "Starting USB Compute Automation Setup Assistant"
    
    # Check if running from USB - MUST BE FIRST
    check_script_location
    
    # ... rest of initialization
}
```

## Error Message Explained

```
=================================================================
  WARNING: SCRIPT RUNNING FROM USB DRIVE!
=================================================================

  This script MUST run from the HOST system, not from the USB drive.

  Current location: /media/$USER/Ventoy/usb-setup-assistant.sh
  Detected USB path: /media/$USER/Ventoy

  REQUIRED ACTION:
  1. Copy this script to your host system:
     cp "/media/$USER/Ventoy/usb-setup-assistant.sh" ~/usb-setup-assistant.sh
  2. Run it from the host:
     sudo bash ~/usb-setup-assistant.sh

  WHY? Operations like Ventoy installation, persistence formatting, 
  debootstrap, and chroot REQUIRE host privileges and will FAIL or 
  CORRUPT the USB if run from within the USB environment.

=================================================================
```

## Why This Is Critical

| Operation | Running from USB | Running from Host |
|---|---|---|
| Ventoy Install | Corrupts running script | Safe - operates on raw device |
| Persistence Format | Corrupts running filesystem | Safe - unmounts first |
| debootstrap | Fails (source on target) | Works - source is host |
| chroot | Deadlock | Works - proper isolation |
| USB unmount | Fails (busy) | Clean unmount |

## Common USB Mount Paths

The check covers all common mount points:

| Platform | Mount Points |
|---|---|
| **Linux** | `/media/*/Ventoy`, `/mnt/ventoy`, `/run/media/*/Ventoy`, `/media/*/usb*`, `/mnt/usb*` |
| **macOS** | `/Volumes/Ventoy` |
| **Windows/WSL** | `/mnt/c/*/Ventoy`, `/mnt/d/*/Ventoy`, `/mnt/e/*/Ventoy` |

## User Workflow Enforcement

The script **blocks execution** until the user copies it to the host:

```bash
if ! confirm "Continue anyway? (NOT RECOMMENDED)" "n"; then
    exit 1
fi
```

This forces the correct workflow:
1. User sees clear error with exact copy commands
2. User copies script to host (`~/usb-setup-assistant.sh`)
3. User runs from host with sudo
4. Script proceeds normally

## Integration

The check is the **very first operation** in `initialize()`, before any logging, backup directories, or OS detection.

```bash
initialize() {
    print_header "$SCRIPT_NAME v$VERSION"
    log "Starting USB Compute Automation Setup Assistant"
    
    # Check if running from USB - MUST BE FIRST
    check_script_location
    
    # Create log file
    : > "$LOG_FILE"
    # ... rest of initialization
}
```

## Template for New Scripts

```bash
#!/usr/bin/env bash
# USB Management Script
# 
# CRITICAL: Must run from HOST, not USB drive!

check_script_location() {
    # ... implementation ...
}

initialize() {
    check_script_location  # FIRST!
    # ... rest ...
}

initialize "$@"
```