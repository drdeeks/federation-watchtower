#!/usr/bin/env bash
# =============================================================================
# USB Automount Script
# =============================================================================
# Handles mounting/unmounting USB storage devices to predictable locations.
#
# Mount points: /mnt/usb/<device-name>-<label> or /mnt/usb/<device-name>
# Supports: ext4, exfat, ntfs, vfat, btrfs, xfs, and more
#
# Usage:
#   usb-mount.sh add <device>      Mount a device
#   usb-mount.sh remove <device>   Unmount a device
#   usb-mount.sh list              List mounted USB devices
#   usb-mount.sh mount-all         Mount all connected USB devices
#   usb-mount.sh unmount-all       Unmount all USB devices
#
# Install:
#   sudo cp usb-mount.sh /usr/local/bin/usb-mount.sh
#   sudo chmod +x /usr/local/bin/usb-mount.sh
#
# =============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

MOUNT_BASE="/mnt/usb"
DEFAULT_LOG_FILE="/var/log/usb-mount.log"
USER_LOG_FILE="$HOME/.usb-mount.log"
LOG_FILE="$DEFAULT_LOG_FILE"
LOCK_FILE="/var/run/usb-mount.lock"
DEFAULT_OPTIONS="utf8,uid=$(id -u),gid=$(id -g),shortname=mixed,nodev,nosuid"

# Use user-writable log file if not root
if [[ $EUID -ne 0 ]]; then
    LOG_FILE="$USER_LOG_FILE"
    LOCK_FILE="/tmp/usb-mount-$$.lock"
fi

# Filesystem-specific mount options
declare -A FS_OPTIONS=(
    ["ext4"]="defaults"
    ["ext3"]="defaults"
    ["ext2"]="defaults"
    ["exfat"]="$DEFAULT_OPTIONS"
    ["ntfs"]="$DEFAULT_OPTIONS,permissions"
    ["vfat"]="$DEFAULT_OPTIONS,dmask=0022,fmask=0022"
    ["btrfs"]="defaults"
    ["xfs"]="defaults"
    ["iso9660"]="$DEFAULT_OPTIONS"
    ["udf"]="$DEFAULT_OPTIONS"
)

# ============================================================================
# LOGGING
# ============================================================================

log() {
    local level="$1"
    shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    case "$level" in
        ERROR) echo -e "\033[0;31m$msg\033[0m" ;;
        WARN)  echo -e "\033[1;33m$msg\033[0m" ;;
        INFO)  echo -e "\033[0;32m$msg\033[0m" ;;
        DEBUG) [[ "${VERBOSE:-0}" == "1" ]] && echo -e "\033[0;36m$msg\033[0m" ;;
    esac
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

# Get device info
get_device_info() {
    local dev="$1"
    local devname=$(basename "$dev")
    
    # Get filesystem type
    local fstype=$(blkid -o value -s TYPE "/dev/$devname" 2>/dev/null || echo "unknown")
    
    # Get label
    local label=$(blkid -o value -s LABEL "/dev/$devname" 2>/dev/null || echo "")
    
    # Get UUID
    local uuid=$(blkid -o value -s UUID "/dev/$devname" 2>/dev/null || echo "")
    
    # Get model/vendor info
    local model=""
    local vendor=""
    if [[ -f "/sys/block/${devname%%[0-9]}/device/model" ]]; then
        model=$(cat "/sys/block/${devname%%[0-9]}/device/model" 2>/dev/null | xargs || echo "")
    fi
    if [[ -f "/sys/block/${devname%%[0-9]}/device/vendor" ]]; then
        vendor=$(cat "/sys/block/${devname%%[0-9]}/device/vendor" 2>/dev/null | xargs || echo "")
    fi
    
    # Get size
    local size=$(lsblk -nd -o SIZE "/dev/$devname" 2>/dev/null | xargs || echo "unknown")
    
    echo "$fstype|$label|$uuid|$model|$vendor|$size"
}

# Generate mount point name
get_mount_point() {
    local devname="$1"
    local label="$2"
    local mount_name=""
    
    # Use label if available, otherwise use device name
    if [[ -n "$label" ]]; then
        # Sanitize label for use as directory name
        mount_name=$(echo "$label" | sed 's/[^a-zA-Z0-9_-]/-/g' | tr '[:upper:]' '[:lower:]')
    else
        mount_name="$devname"
    fi
    
    echo "$MOUNT_BASE/$mount_name"
}

# Check if device is already mounted
is_mounted() {
    local devname="$1"
    mount | grep -q "^/dev/$devname " 2>/dev/null
}

# Get current mount point
get_current_mount() {
    local devname="$1"
    mount | grep "^/dev/$devname " | awk '{print $3}' | head -1
}

# Lock management
acquire_lock() {
    local timeout=10
    local count=0
    
    # Try to create lock file (may fail if not root)
    while [[ -f "$LOCK_FILE" ]]; do
        local lock_pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$lock_pid" ]] && ! kill -0 "$lock_pid" 2>/dev/null; then
            rm -f "$LOCK_FILE" 2>/dev/null || true
            break
        fi
        count=$((count + 1))
        if [[ $count -ge $timeout ]]; then
            log WARN "Lock timeout, breaking stale lock"
            rm -f "$LOCK_FILE" 2>/dev/null || true
            break
        fi
        sleep 1
    done
    
    # Write PID to lock file (may fail if not root, but that's okay)
    echo $$ > "$LOCK_FILE" 2>/dev/null || true
}

release_lock() {
    rm -f "$LOCK_FILE" 2>/dev/null || true
}

# ============================================================================
# MOUNT FUNCTIONS
# ============================================================================

mount_device() {
    local devname="$1"
    local devpath="/dev/$devname"
    
    # Check if device exists
    if [[ ! -b "$devpath" ]]; then
        log ERROR "Device $devpath does not exist"
        return 1
    fi
    
    # Check if already mounted
    if is_mounted "$devname"; then
        local current_mount=$(get_current_mount "$devname")
        log INFO "Device $devname already mounted at $current_mount"
        return 0
    fi
    
    # Get device info
    local info=$(get_device_info "$devname")
    IFS='|' read -r fstype label uuid model vendor size <<< "$info"
    
    log INFO "Mounting $devname: fs=$fstype label=$label uuid=$uuid size=$size"
    
    # Handle unknown filesystem
    if [[ "$fstype" == "unknown" || "$fstype" == "" ]]; then
        log WARN "Unknown filesystem on $devname, attempting to mount..."
        fstype="auto"
    fi
    
    # Generate mount point
    local mount_point=$(get_mount_point "$devname" "$label")
    
    # Create mount point
    mkdir -p "$mount_point"
    
    # Get mount options
    local options="${FS_OPTIONS[$fstype]:-defaults}"
    
    # Special handling for NTFS
    if [[ "$fstype" == "ntfs" ]]; then
        if command -v ntfs-3g &>/dev/null; then
            fstype="ntfs-3g"
        else
            log WARN "ntfs-3g not installed, trying kernel ntfs driver"
            options="$options,ro"
        fi
    fi
    
    # Mount the device
    log INFO "Mounting $devpath to $mount_point with options: $options"
    
    if mount -t "$fstype" -o "$options" "$devpath" "$mount_point" 2>/dev/null; then
        log INFO "Successfully mounted $devname at $mount_point"
        
        # Set permissions
        chmod 755 "$mount_point" 2>/dev/null || true
        
        # Log mount info
        echo "$(date '+%Y-%m-%d %H:%M:%S') MOUNTED $devname $mount_point $fstype $label $size" >> "$LOG_FILE"
        
        # Create .usb-mount-info file
        cat > "$mount_point/.usb-mount-info" << EOF
device=/dev/$devname
filesystem=$fstype
label=$label
uuid=$uuid
model=$model
vendor=$vendor
size=$size
mounted=$(date -u +%Y-%m-%dT%H:%M:%SZ)
mount_point=$mount_point
EOF
        chmod 644 "$mount_point/.usb-mount-info" 2>/dev/null || true
        
        return 0
    else
        log ERROR "Failed to mount $devname at $mount_point"
        rmdir "$mount_point" 2>/dev/null || true
        return 1
    fi
}

unmount_device() {
    local devname="$1"
    
    if ! is_mounted "$devname"; then
        log INFO "Device $devname is not mounted"
        return 0
    fi
    
    local mount_point=$(get_current_mount "$devname")
    
    log INFO "Unmounting $devname from $mount_point"
    
    # Try lazy unmount first
    if umount -l "$devpath" 2>/dev/null; then
        log INFO "Successfully unmounted $devname"
        echo "$(date '+%Y-%m-%d %H:%M:%S') UNMOUNTED $devname $mount_point" >> "$LOG_FILE"
        
        # Remove empty mount point
        if [[ -d "$mount_point" ]] && [[ -z "$(ls -A "$mount_point" 2>/dev/null)" ]]; then
            rmdir "$mount_point" 2>/dev/null || true
        fi
        return 0
    else
        log ERROR "Failed to unmount $devname"
        return 1
    fi
}

# ============================================================================
# BATCH OPERATIONS
# ============================================================================

mount_all_usb() {
    log INFO "Mounting all USB devices..."
    
    local count=0
    for dev in /dev/sd[a-z][0-9]; do
        [[ -b "$dev" ]] || continue
        local devname=$(basename "$dev")
        
        # Skip internal drives (sda)
        [[ "$devname" == sda* ]] && continue
        
        # Skip if already mounted
        is_mounted "$devname" && continue
        
        # Skip partitions without filesystem
        local fstype=$(blkid -o value -s TYPE "$dev" 2>/dev/null || echo "")
        [[ -z "$fstype" || "$fstype" == "unknown" ]] && continue
        
        if mount_device "$devname"; then
            count=$((count + 1))
        fi
    done
    
    log INFO "Mounted $count USB device(s)"
}

unmount_all_usb() {
    log INFO "Unmounting all USB devices..."
    
    local count=0
    for mount_point in "$MOUNT_BASE"/*/; do
        [[ -d "$mount_point" ]] || continue
        local devname=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null | sed 's|/dev/||' || continue)
        
        if [[ -n "$devname" ]] && [[ "$devname" == sd[a-z][0-9]* ]]; then
            if unmount_device "$devname"; then
                count=$((count + 1))
            fi
        fi
    done
    
    log INFO "Unmounted $count USB device(s)"
}

list_usb() {
    echo "Mounted USB Devices:"
    echo "==================="
    echo ""
    
    local found=0
    
    # First, show devices in our mount base
    for mount_point in "$MOUNT_BASE"/*/; do
        [[ -d "$mount_point" ]] || continue
        
        local source=$(findmnt -n -o SOURCE "$mount_point" 2>/dev/null || echo "unknown")
        local fstype=$(findmnt -n -o FSTYPE "$mount_point" 2>/dev/null || echo "unknown")
        local size=$(du -sh "$mount_point" 2>/dev/null | cut -f1 || echo "unknown")
        
        # Read .usb-mount-info if available
        local label="" model="" device_size=""
        if [[ -f "$mount_point/.usb-mount-info" ]]; then
            label=$(grep "^label=" "$mount_point/.usb-mount-info" | cut -d= -f2 || echo "")
            model=$(grep "^model=" "$mount_point/.usb-mount-info" | cut -d= -f2 || echo "")
            device_size=$(grep "^size=" "$mount_point/.usb-mount-info" | cut -d= -f2 || echo "")
        fi
        
        printf "  %-30s %-10s %-15s %-20s %s\n" \
            "$(basename "$mount_point")" \
            "$fstype" \
            "$device_size" \
            "$source" \
            "$mount_point"
        found=$((found + 1))
    done
    
    # Also show other USB mounts outside our base
    local usb_mounts=$(mount | grep '^/dev/sd[a-z]' | grep -v '/dev/sda' || true)
    if [[ -n "$usb_mounts" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            local source=$(echo "$line" | awk '{print $1}')
            local mount_point=$(echo "$line" | awk '{print $3}')
            local fstype=$(echo "$line" | awk '{print $5}')
            
            # Skip if already in our list
            [[ "$mount_point" == "$MOUNT_BASE"* ]] && continue
            
            # Skip internal drives
            [[ "$source" == /dev/sda* ]] && continue
            
            # Skip loop devices
            [[ "$source" == /dev/loop* ]] && continue
            
            local size=$(du -sh "$mount_point" 2>/dev/null | cut -f1 || echo "unknown")
            
            printf "  %-30s %-10s %-15s %-20s %s\n" \
                "$(basename "$mount_point")" \
                "$fstype" \
                "" \
                "$source" \
                "$mount_point"
            found=$((found + 1))
        done <<< "$usb_mounts"
    fi
    
    if [[ $found -eq 0 ]]; then
        echo "  No USB devices mounted"
    fi
    echo ""
    echo "Mount base: $MOUNT_BASE"
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    # Ensure mount base exists
    mkdir -p "$MOUNT_BASE" 2>/dev/null || true
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    case "${1:-}" in
        add)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 add <device>"; exit 1; }
            acquire_lock
            trap release_lock EXIT
            mount_device "$2"
            ;;
        remove)
            [[ -z "${2:-}" ]] && { echo "Usage: $0 remove <device>"; exit 1; }
            acquire_lock
            trap release_lock EXIT
            unmount_device "$2"
            ;;
        list)
            list_usb
            ;;
        mount-all)
            acquire_lock
            trap release_lock EXIT
            mount_all_usb
            ;;
        unmount-all)
            acquire_lock
            trap release_lock EXIT
            unmount_all_usb
            ;;
        status)
            echo "USB Mount Status"
            echo "================"
            echo "Mount base: $MOUNT_BASE"
            echo "Log file:   $LOG_FILE"
            echo ""
            list_usb
            ;;
        --help|-h)
            echo "USB Automount Script"
            echo ""
            echo "Usage:"
            echo "  $0 add <device>      Mount a device (e.g., sdb1)"
            echo "  $0 remove <device>   Unmount a device"
            echo "  $0 list              List mounted USB devices"
            echo "  $0 mount-all         Mount all connected USB devices"
            echo "  $0 unmount-all       Unmount all USB devices"
            echo "  $0 status            Show mount status"
            echo ""
            echo "Examples:"
            echo "  $0 add sdb1"
            echo "  $0 remove sdb1"
            echo "  $0 mount-all"
            ;;
        *)
            echo "Usage: $0 {add|remove|list|mount-all|unmount-all|status} [device]"
            exit 1
            ;;
    esac
}

main "$@"