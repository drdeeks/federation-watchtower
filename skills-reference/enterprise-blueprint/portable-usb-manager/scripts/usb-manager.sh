#!/bin/bash
#
# USB Manager - Comprehensive USB Drive Management Tool
# Handles detection, mounting, partitioning, formatting, Ventoy, mkusb,
# hidden device recovery, and unrecognized drive troubleshooting.
#
# Version: 2.0.0
#

set -euo pipefail

# ==================== CONFIGURATION ====================

DRY_RUN=false
SCRIPT_NAME="USB Manager"
MOUNT_BASE="/mnt"
LOG_FILE="${TMPDIR:-/tmp}/usb-manager.log"
TEMP_DIR="${TMPDIR:-/tmp}/usb-manager"
VENTOY_VERSION="1.0.99"
VENTOY_URL="https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
SUPPORTED_FS=("vfat" "ntfs" "exfat" "ext4" "ext3" "ext2" "xfs" "btrfs")

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ==================== UTILITY FUNCTIONS ====================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
    log "ERROR: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    read -p "$(echo -e "${YELLOW}${prompt}${NC}")" response
    response="${response:-$default}"
    [[ "$response" =~ ^[Yy] ]]
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This operation requires root privileges"
        echo "Please run with sudo: sudo $0"
        read -p "Press Enter to continue..."
        exit 1; print_error "root required"
    fi
}

# Step indicator for multi-step operations
STEP_CURRENT=0
STEP_TOTAL=0
step_init() {
    STEP_TOTAL=$1
    STEP_CURRENT=0
}
step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    echo -e "\n${CYAN}${BOLD}[${STEP_CURRENT}/${STEP_TOTAL}]${NC} $1"
}

# Dry-run wrapper
run_or_dry() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
        return 0
    fi
    "$@"
}

check_dependencies() {
    local missing=()
    local deps=("lsblk" "blkid" "fdisk" "file" "du" "find")
    for cmd in "${deps[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required tools: ${missing[*]}"
        echo "Install with: sudo apt install ${missing[*]}"
        read -p "Press Enter to continue..."
        exit 1; print_error "missing tools"
    fi
}

install_package() {
    local package="$1"
    if command -v apt &> /dev/null; then
        sudo apt update && sudo apt install -y "$package"
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y "$package"
    elif command -v pacman &> /dev/null; then
        sudo pacman -S --noconfirm "$package"
    else
        print_error "Unsupported package manager. Install '$package' manually."
        return 1
    fi
}

# ==================== DEVICE DETECTION ====================

list_removable_devices() {
    print_header "Detecting Removable Devices"
    local devices=()
    while IFS= read -r line; do
        devices+=("$line")
    done < <(lsblk -ndo NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | grep -E 'usb|disk' | grep -v 'loop')

    if [[ ${#devices[@]} -eq 0 ]]; then
        print_warning "No removable devices detected"
        return 1
    fi

    echo "Found removable devices:"
    echo ""
    printf "${BOLD}%-10s %-10s %-10s %-15s %-30s${NC}\n" "DEVICE" "SIZE" "TYPE" "TRANSPORT" "MODEL"
    echo "─────────────────────────────────────────────────────────────────────────────"
    local index=1
    for device in "${devices[@]}"; do
        printf "${CYAN}%2d)${NC} %s\n" "$index" "$device"
        ((index++))
    done
    echo ""
}

scan_hidden_devices() {
    print_header "Scanning for Hidden/Unrecognized Devices"
    local found=0

    print_info "Checking kernel device logs..."
    if dmesg 2>/dev/null | grep -qi "usb\|sd[a-z]\|removable"; then
        echo -e "\n${BOLD}Recent kernel USB events:${NC}"
        dmesg 2>/dev/null | grep -i "usb\|sd[a-z]\|removable" | tail -20
        echo ""
        found=1
    fi

    print_info "Checking for devices without filesystem signatures..."
    for dev in /dev/sd?; do
        [[ -b "$dev" ]] || continue
        local fs_type
        fs_type=$(blkid -o value -s TYPE "$dev" 2>/dev/null || echo "")
        local part_label
        part_label=$(lsblk -no LABEL "$dev" 2>/dev/null | head -1)
        if [[ -z "$fs_type" && -z "$part_label" ]]; then
            local size
            size=$(lsblk -no SIZE "$dev" 2>/dev/null | head -1)
            print_warning "Unrecognized: $dev ($size) - no filesystem detected"
            found=1
        fi
    done

    print_info "Checking for write-protected devices..."
    for dev in /sys/block/sd*; do
        [[ -f "$dev/ro" ]] || continue
        local ro
        ro=$(cat "$dev/ro" 2>/dev/null)
        if [[ "$ro" == "1" ]]; then
            local devname
            devname=$(basename "$dev")
            print_warning "Write-protected: /dev/$devname"
            found=1
        fi
    done

    if [[ $found -eq 0 ]]; then
        print_success "No hidden or unrecognized devices found"
    fi
    echo ""
}

select_device() {
    list_removable_devices || return 1
    local count
    count=$(lsblk -ndo NAME,TYPE 2>/dev/null | grep -E 'usb|disk' | grep -v 'loop' | wc -l)
    read -p "$(echo -e "${YELLOW}Select device number [1-${count}] or 'q' to quit: ${NC}")" selection
    [[ "$selection" == "q" ]] && exit 0

    local device_name
    device_name=$(lsblk -ndo NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | grep -E 'usb|disk' | grep -v 'loop' | sed -n "${selection}p" | awk '{print $1}')
    if [[ -z "$device_name" ]]; then
        print_error "Invalid selection"
        return 1
    fi
    SELECTED_DEVICE="/dev/$device_name"
    print_success "Selected: $SELECTED_DEVICE"
    echo ""
}

# ==================== DEVICE ANALYSIS ====================

analyze_device() {
    local device="$1"
    print_header "Device Analysis: $device"

    echo -e "${BOLD}Device Information:${NC}"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$device" 2>/dev/null
    echo ""

    echo -e "${BOLD}Partition Table:${NC}"
    local pt_type
    pt_type=$(fdisk -l "$device" 2>/dev/null | grep "Disklabel type" | awk '{print $3}')
    if [[ -n "$pt_type" ]]; then
        echo "Type: $pt_type"
    else
        print_warning "No partition table detected"
    fi
    echo ""

    echo -e "${BOLD}Partitions:${NC}"
    local partitions
    partitions=$(lsblk -nlo NAME "$device" 2>/dev/null | tail -n +2)
    if [[ -z "$partitions" ]]; then
        print_warning "No partitions found on this device"
    else
        for part in $partitions; do
            analyze_partition "/dev/$part"
        done
    fi
    echo ""
}

analyze_partition() {
    local partition="$1"
    echo -e "\n  ${BOLD}Partition: $partition${NC}"
    local fs_type
    fs_type=$(blkid -o value -s TYPE "$partition" 2>/dev/null || echo "unknown")
    local fs_label
    fs_label=$(blkid -o value -s LABEL "$partition" 2>/dev/null || echo "")
    local fs_uuid
    fs_uuid=$(blkid -o value -s UUID "$partition" 2>/dev/null || echo "")
    echo "    Filesystem: $fs_type"
    [[ -n "$fs_label" ]] && echo "    Label: $fs_label"
    [[ -n "$fs_uuid" ]] && echo "    UUID: $fs_uuid"
    local mountpoint
    mountpoint=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null)
    if [[ -n "$mountpoint" ]]; then
        echo -e "    ${GREEN}Status: Mounted at $mountpoint${NC}"
    else
        echo -e "    ${YELLOW}Status: Not mounted${NC}"
    fi
    local size
    size=$(lsblk -no SIZE "$partition" 2>/dev/null)
    echo "    Size: $size"
    check_filesystem_health "$partition" "$fs_type"
}

check_filesystem_health() {
    local partition="$1"
    local fs_type="$2"
    echo -n "    Health: "
    case "$fs_type" in
        ext2|ext3|ext4)
            if dumpe2fs -h "$partition" &>/dev/null; then
                local errors
                errors=$(dumpe2fs -h "$partition" 2>/dev/null | grep "Filesystem state" | grep -v "clean")
                if [[ -n "$errors" ]]; then
                    echo -e "${RED}NEEDS CHECK${NC}"
                    print_warning "Filesystem may have errors. Consider running fsck."
                else
                    echo -e "${GREEN}OK${NC}"
                fi
            else
                echo -e "${YELLOW}UNKNOWN${NC}"
            fi
            ;;
        vfat|ntfs|exfat)
            if file -s "$partition" 2>/dev/null | grep -qE 'FAT|NTFS|exFAT'; then
                echo -e "${GREEN}OK${NC}"
            else
                echo -e "${YELLOW}UNKNOWN${NC}"
            fi
            ;;
        *)
            echo -e "${YELLOW}UNKNOWN (unsupported FS)${NC}"
            ;;
    esac
}

# ==================== SAFETY CHECKS ====================

safety_scan() {
    local device="$1"
    print_header "Safety Scan: $device"
    local warnings=0

    if lsof 2>/dev/null | grep -q "$device"; then
        print_warning "Device is currently in use by running processes"
        ((warnings++))
    fi

    local mounted
    mounted=$(lsblk -no MOUNTPOINT "$device" 2>/dev/null | grep -v '^$')
    if [[ -n "$mounted" ]]; then
        print_warning "Device has mounted partitions:"
        echo "$mounted" | while read -r mp; do echo "  - $mp"; done
        ((warnings++))
    fi

    if [[ -f "/sys/block/$(basename "$device")/ro" ]]; then
        local ro
        ro=$(cat "/sys/block/$(basename "$device")/ro" 2>/dev/null)
        if [[ "$ro" == "1" ]]; then
            print_warning "Device is write-protected (read-only)"
            ((warnings++))
        fi
    fi

    local size_bytes
    size_bytes=$(lsblk -bno SIZE "$device" 2>/dev/null | head -1)
    local size_gb=$((size_bytes / 1024 / 1024 / 1024))
    if [[ $size_gb -gt 100 ]]; then
        print_warning "Large device detected ($size_gb GB). Operations may take time."
        ((warnings++))
    fi

    if [[ $warnings -eq 0 ]]; then
        print_success "No safety issues detected"
    else
        echo ""
        print_warning "Found $warnings potential issues"
    fi
    echo ""
}

# ==================== MOUNTING OPERATIONS ====================

mount_partition() {
    local partition="$1"
    require_root
    print_header "Mount Partition: $partition"

    local current_mount
    current_mount=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null)
    if [[ -n "$current_mount" ]]; then
        print_info "Already mounted at: $current_mount"
        return 0
    fi

    local fs_type
    fs_type=$(blkid -o value -s TYPE "$partition" 2>/dev/null || echo "unknown")
    if [[ "$fs_type" == "unknown" ]]; then
        print_error "Cannot detect filesystem type"
        if confirm "Try to detect with file command?"; then
            local file_info
            file_info=$(file -s "$partition")
            echo "File info: $file_info"
            echo ""
            read -p "$(echo -e "${YELLOW}Manually specify filesystem type (vfat/ntfs/exfat/ext4): ${NC}")" fs_type
        else
            return 1
        fi
    fi

    print_info "Filesystem type: $fs_type"

    case "$fs_type" in
        ntfs)
            if ! command -v ntfs-3g &> /dev/null; then
                print_error "ntfs-3g not installed"
                if confirm "Install ntfs-3g?"; then
                    install_package ntfs-3g
                else
                    return 1
                fi
            fi
            ;;
        exfat)
            if ! command -v mount.exfat &> /dev/null; then
                print_error "exfat support not installed"
                if confirm "Install exfat-fuse and exfat-utils?"; then
                    install_package exfat-fuse exfat-utils
                else
                    return 1
                fi
            fi
            ;;
    esac

    local label
    label=$(blkid -o value -s LABEL "$partition" 2>/dev/null)
    local mount_name="${label:-usb-$(basename "$partition")}"
    local mount_point="$MOUNT_BASE/$mount_name"
    read -p "$(echo -e "${YELLOW}Mount point [$mount_point]: ${NC}")" custom_mount
    mount_point="${custom_mount:-$mount_point}"
    mkdir -p "$mount_point"

    local mount_opts=""
    case "$fs_type" in
        vfat)   mount_opts="-o uid=$(id -u),gid=$(id -g),umask=0022" ;;
        ntfs)   mount_opts="-t ntfs-3g -o uid=$(id -u),gid=$(id -g),umask=0022" ;;
        exfat)  mount_opts="-o uid=$(id -u),gid=$(id -g),umask=0022" ;;
    esac

    if mount $mount_opts "$partition" "$mount_point"; then
        print_success "Mounted at: $mount_point"
        local file_count
        file_count=$(find "$mount_point" -type f 2>/dev/null | wc -l)
        local dir_count
        dir_count=$(find "$mount_point" -type d 2>/dev/null | wc -l)
        print_info "Contains: $file_count files in $dir_count directories"
    else
        print_error "Failed to mount"
        rmdir "$mount_point" 2>/dev/null
        return 1
    fi
}

unmount_partition() {
    local partition="$1"
    require_root
    print_header "Unmount Partition: $partition"
    local mount_point
    mount_point=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null)
    if [[ -z "$mount_point" ]]; then
        print_warning "Partition is not mounted"
        return 1
    fi
    print_info "Currently mounted at: $mount_point"
    if ! confirm "Unmount this partition?"; then
        return 0
    fi
    if lsof "$mount_point" 2>/dev/null | grep -q .; then
        print_warning "Files are still open on this partition"
        lsof "$mount_point" 2>/dev/null
        if confirm "Force unmount (may cause data loss)?"; then
            if umount -f "$mount_point"; then
                print_success "Force unmounted"
            else
                print_error "Failed to unmount"
                return 1
            fi
        else
            return 1
        fi
    else
        if umount "$mount_point"; then
            print_success "Unmounted successfully"
            rmdir "$mount_point" 2>/dev/null
        else
            print_error "Failed to unmount"
            return 1
        fi
    fi
}

# ==================== FILE TYPE SCANNING ====================

scan_file_types() {
    local path="$1"
    print_header "File Type Analysis: $path"
    print_info "Scanning... (this may take a moment)"

    echo -e "\n${BOLD}File Types by Extension:${NC}"
    find "$path" -type f 2>/dev/null | sed 's/.*\.//' | sort | uniq -c | sort -rn | head -20 | \
        awk '{printf "  %6d  %s\n", $1, $2}'

    echo -e "\n${BOLD}Security Scan:${NC}"
    local exe_count
    exe_count=$(find "$path" -type f \( -name "*.exe" -o -name "*.bat" -o -name "*.cmd" \) 2>/dev/null | wc -l)
    local script_count
    script_count=$(find "$path" -type f \( -name "*.sh" -o -name "*.py" -o -name "*.pl" \) 2>/dev/null | wc -l)
    local hidden_count
    hidden_count=$(find "$path" -name ".*" -type f 2>/dev/null | wc -l)

    [[ $exe_count -gt 0 ]] && print_warning "Found $exe_count executable files (.exe, .bat, .cmd)"
    [[ $script_count -gt 0 ]] && print_info "Found $script_count script files (.sh, .py, .pl)"
    [[ $hidden_count -gt 0 ]] && print_info "Found $hidden_count hidden files"

    echo -e "\n${BOLD}Disk Usage:${NC}"
    local usage
    usage=$(du -sh "$path" 2>/dev/null | awk '{print $1}')
    echo "  Total size: $usage"

    echo -e "\n${BOLD}Largest Files:${NC}"
    find "$path" -type f -exec du -h {} + 2>/dev/null | sort -rh | head -10 | \
        awk '{printf "  %8s  %s\n", $1, $2}'
}

# ==================== PARTITIONING OPERATIONS ====================

create_partition_table() {
    local device="$1"
    require_root
    print_header "Create Partition Table: $device"
    print_warning "This will DESTROY ALL DATA on $device"
    safety_scan "$device"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue?" "n"; then
        print_info "Operation cancelled"
        return 0
    fi
    echo ""
    echo "Select partition table type:"
    echo "  1) MBR/DOS (compatible, <2TB drives)"
    echo "  2) GPT (modern, >2TB drives, UEFI)"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-2]: ${NC}")" pt_choice
    case "$pt_choice" in
        1) print_info "Creating MBR partition table..."
           echo -e "o\nw\n" | fdisk "$device" &>/dev/null ;;
        2) print_info "Creating GPT partition table..."
           echo -e "g\nw\n" | fdisk "$device" &>/dev/null ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac
    print_success "Partition table created"
    if confirm "Create a partition now?"; then
        create_partition "$device"
    fi
}

create_partition() {
    local device="$1"
    require_root
    print_header "Create Partition: $device"
    print_info "Creating primary partition using full disk..."
    echo -e "n\np\n1\n\n\nw\n" | fdisk "$device" &>/dev/null
    sleep 2
    partprobe "$device" 2>/dev/null || true
    local new_part
    new_part=$(lsblk -nlo NAME "$device" 2>/dev/null | tail -1)
    if [[ -n "$new_part" ]]; then
        print_success "Created partition: /dev/$new_part"
        if confirm "Format this partition now?"; then
            format_partition "/dev/$new_part"
        fi
    else
        print_error "Failed to create partition"
        return 1
    fi
}

format_partition() {
    local partition="$1"
    require_root
    print_header "Format Partition: $partition"
    print_warning "This will DESTROY ALL DATA on $partition"
    if ! confirm "Continue with format?" "n"; then
        print_info "Format cancelled"
        return 0
    fi
    echo ""
    echo "Select filesystem type:"
    echo "  1) FAT32/VFAT (universal compatibility, <4GB file limit)"
    echo "  2) exFAT (modern, no file size limit, works on most systems)"
    echo "  3) NTFS (Windows native, good compatibility)"
    echo "  4) ext4 (Linux native, best performance)"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-4]: ${NC}")" fs_choice
    read -p "$(echo -e "${YELLOW}Volume label [optional]: ${NC}")" label
    case "$fs_choice" in
        1) print_info "Formatting as FAT32..."
           local label_opt=""
           [[ -n "$label" ]] && label_opt="-n $label"
           mkfs.vfat -F 32 $label_opt "$partition" ;;
        2) print_info "Formatting as exFAT..."
           if ! command -v mkfs.exfat &> /dev/null; then
               install_package exfat-fuse exfat-utils
           fi
           local label_opt=""
           [[ -n "$label" ]] && label_opt="-n $label"
           mkfs.exfat $label_opt "$partition" ;;
        3) print_info "Formatting as NTFS..."
           if ! command -v mkfs.ntfs &> /dev/null; then
               install_package ntfs-3g
           fi
           local label_opt=""
           [[ -n "$label" ]] && label_opt="-L $label"
           mkfs.ntfs -f $label_opt "$partition" ;;
        4) print_info "Formatting as ext4..."
           local label_opt=""
           [[ -n "$label" ]] && label_opt="-L $label"
           mkfs.ext4 $label_opt "$partition" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac
    print_success "Format complete!"
    if confirm "Mount this partition now?"; then
        mount_partition "$partition"
    fi
}

# ==================== VENTOY OPERATIONS ====================

ventoy_check() {
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        print_error "Neither curl nor wget available"
        return 1
    fi
}

ventoy_download() {
    print_header "Downloading Ventoy v${VENTOY_VERSION}"
    local tmp_dir="$TEMP_DIR/ventoy-download"
    mkdir -p "$tmp_dir"

    if [[ -f "$tmp_dir/ventoy-${VENTOY_VERSION}-linux.tar.gz" ]]; then
        print_info "Ventoy archive already downloaded"
    else
        print_info "Downloading from GitHub..."
        if command -v curl &> /dev/null; then
            curl -L -o "$tmp_dir/ventoy-${VENTOY_VERSION}-linux.tar.gz" "$VENTOY_URL"
        else
            wget -O "$tmp_dir/ventoy-${VENTOY_VERSION}-linux.tar.gz" "$VENTOY_URL"
        fi
    fi

    if [[ ! -f "$tmp_dir/ventoy-${VENTOY_VERSION}-linux.tar.gz" ]]; then
        print_error "Download failed"
        return 1
    fi

    print_info "Extracting..."
    tar -xzf "$tmp_dir/ventoy-${VENTOY_VERSION}-linux.tar.gz" -C "$tmp_dir"
    echo "$tmp_dir/ventoy-${VENTOY_VERSION}"
}

ventoy_setup() {
    local device="$1"
    require_root
    print_header "Ventoy Setup: $device"
    print_warning "This will DESTROY ALL DATA on $device"
    print_info "Ventoy creates a multi-ISO bootable USB drive"
    safety_scan "$device"

    if ! confirm "Continue with Ventoy installation?" "n"; then
        return 0
    fi

    # Steps: [1/3] check, [2/3] download, [3/3] install
    step_init 3
    step "Checking dependencies"
    ventoy_check || return 1

    step "Downloading Ventoy"
    local ventoy_dir
    ventoy_dir=$(ventoy_download) || return 1

    step "Installing Ventoy to $device"
    if "$ventoy_dir/Ventoy2Disk.sh" -i "$device"; then
        print_success "Ventoy installed successfully!"
        echo ""
        echo -e "${BOLD}Next steps:${NC}"
        echo "  1. Mount the Ventoy partition: sudo bash $0 --mount ${device}1"
        echo "  2. Copy ISO files to the mounted partition"
        echo "  3. Safely eject and boot from the USB"
        echo ""
        echo -e "${BOLD}Supported ISO types:${NC}"
        echo "  Linux: Ubuntu, Fedora, Debian, Arch, Mint, openSUSE, etc."
        echo "  Windows: Windows 10, 11, Server installers"
        echo "  Utilities: GParted, Clonezilla, Hiren's, MemTest86, etc."
    else
        print_error "Ventoy installation failed"
        return 1
    fi
}

ventoy_list_isos() {
    local partition="$1"
    print_header "ISOs on Ventoy USB"

    local mountpoint
    mountpoint=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null)
    if [[ -z "$mountpoint" ]]; then
        print_info "Partition not mounted. Mounting..."
        mount_partition "$partition" || return 1
        mountpoint=$(lsblk -no MOUNTPOINT "$partition" 2>/dev/null)
    fi

    local iso_count
    iso_count=$(find "$mountpoint" -maxdepth 1 -name "*.iso" -o -name "*.img" 2>/dev/null | wc -l)
    if [[ $iso_count -eq 0 ]]; then
        print_info "No ISO files found on Ventoy drive"
        echo "  Copy .iso or .img files to: $mountpoint"
    else
        echo "Found $iso_count bootable images:"
        echo ""
        find "$mountpoint" -maxdepth 1 \( -name "*.iso" -o -name "*.img" \) -exec ls -lh {} \; 2>/dev/null | \
            awk '{printf "  %-60s %s\n", $NF, $5}'
    fi
    echo ""
}

ventoy_update() {
    local device="$1"
    require_root
    print_header "Update Ventoy: $device"
    print_info "Updating Ventoy preserves existing ISO files on the drive"

    ventoy_check || return 1

    local ventoy_dir
    ventoy_dir=$(ventoy_download) || return 1

    if confirm "Update Ventoy on $device?"; then
        if "$ventoy_dir/Ventoy2Disk.sh" -u "$device"; then
            print_success "Ventoy updated successfully!"
        else
            print_error "Ventoy update failed"
            return 1
        fi
    fi
}

# ==================== VENTOY PERSISTENCE OPERATIONS ====================

detect_ventoy_persistence() {
    local mount_point="$1"
    local persistence_dir="$mount_point/persistence"
    
    if [[ ! -d "$persistence_dir" ]]; then
        print_warning "No persistence directory found at $persistence_dir"
        return 1
    fi
    
    local dat_files=()
    while IFS= read -r -d '' file; do
        dat_files+=("$file")
    done < <(find "$persistence_dir" -name "*.dat" -o -name "persistence*" -print0 2>/dev/null)
    
    if [[ ${#dat_files[@]} -eq 0 ]]; then
        print_warning "No persistence .dat files found"
        return 1
    fi
    
    print_info "Found persistence files:"
    for file in "${dat_files[@]}"; do
        local size
        size=$(du -h "$file" | cut -f1)
        echo "  $file ($size)"
    done
    echo ""
    echo "${dat_files[0]}"
}

mount_ventoy_persistence() {
    local dat_file="$1"
    require_root
    print_header "Mount Ventoy Persistence: $dat_file"
    
    if [[ ! -f "$dat_file" ]]; then
        print_error "Persistence file not found: $dat_file"
        return 1
    fi
    
    local mount_point="${USB_MOUNT_POINT:-/mnt/ventoy-persistence}"
    mkdir -p "$mount_point"
    
    print_info "Setting up loop device..."
    local loop_dev
    loop_dev=$(sudo losetup -f --show "$dat_file")
    
    if [[ -z "$loop_dev" ]]; then
        print_error "Failed to create loop device"
        return 1
    fi
    
    print_info "Loop device: $loop_dev"
    
    # Check if it has partitions
    if sudo partprobe "$loop_dev" 2>/dev/null; then
        sleep 1
    fi
    
    local part_dev="${loop_dev}p1"
    if [[ ! -b "$part_dev" ]]; then
        part_dev="$loop_dev"
    fi
    
    print_info "Mounting $part_dev to $mount_point..."
    if sudo mount "$part_dev" "$mount_point"; then
        print_success "Mounted at: $mount_point"
        echo "$mount_point"
    else
        print_error "Failed to mount"
        sudo losetup -d "$loop_dev" 2>/dev/null
        return 1
    fi
}

unmount_ventoy_persistence() {
    local mount_point="$1"
    require_root
    
    if mountpoint -q "$mount_point" 2>/dev/null; then
        print_info "Unmounting $mount_point..."
        sudo umount "$mount_point"
        
        # Find and detach loop device
        local loop_dev
        loop_dev=$(sudo losetup -j "$mount_point" 2>/dev/null | head -1 | cut -d: -f1)
        if [[ -n "$loop_dev" ]]; then
            sudo losetup -d "$loop_dev" 2>/dev/null
        fi
        print_success "Unmounted"
    fi
}

ventoy_persistence_copy() {
    local source="$1"
    local device="$2"
    require_root
    print_header "Copy to Ventoy Persistence"
    
    # Find persistence file
    local mount_point
    mount_point=$(lsblk -no MOUNTPOINT "${device}1" 2>/dev/null)
    if [[ -z "$mount_point" ]]; then
        print_info "Mounting Ventoy partition..."
        sudo mkdir -p "${USB_MOUNT_TEMP:-/mnt/ventoy-temp}"
        sudo mount "${device}1" "${USB_MOUNT_TEMP:-/mnt/ventoy-temp}"
        mount_point="${USB_MOUNT_TEMP:-/mnt/ventoy-temp}"
    fi
    
    local dat_file
    dat_file=$(detect_ventoy_persistence "$mount_point")
    if [[ -z "$dat_file" ]]; then
        print_error "No persistence file found"
        return 1
    fi
    
    print_info "Mounting persistence image..."
    local persist_mount="${USB_MOUNT_POINT:-/mnt/ventoy-persistence}"
    mount_ventoy_persistence "$dat_file" || return 1
    
    print_info "Copying $source to persistence..."
    if [[ -d "$source" ]]; then
        sudo cp -a "$source"/* "$persist_mount/"
    else
        sudo cp -a "$source" "$persist_mount/"
    fi
    
    print_success "Copy complete"
    
    # Cleanup
    unmount_ventoy_persistence "$persist_mount"
    if [[ "$mount_point" == "${USB_MOUNT_TEMP:-/mnt/ventoy-temp}" ]]; then
        sudo umount "$mount_point" 2>/dev/null
    fi
}

ventoy_persistence_manage() {
    local device="$1"
    require_root
    print_header "Manage Ventoy Persistence"
    
    local mount_point
    mount_point=$(lsblk -no MOUNTPOINT "${device}1" 2>/dev/null)
    if [[ -z "$mount_point" ]]; then
        print_info "Mounting Ventoy partition..."
        sudo mkdir -p "${USB_MOUNT_TEMP:-/mnt/ventoy-temp}"
        sudo mount "${device}1" "${USB_MOUNT_TEMP:-/mnt/ventoy-temp}"
        mount_point="${USB_MOUNT_TEMP:-/mnt/ventoy-temp}"
    fi
    
    local dat_file
    dat_file=$(detect_ventoy_persistence "$mount_point")
    if [[ -z "$dat_file" ]]; then
        print_error "No persistence file found"
        return 1
    fi

    local persist_mount="${USB_MOUNT_POINT:-/mnt/ventoy-persistence}"

    echo "Persistence Management Options:"
    echo "  1) View contents"
    echo "  2) Copy files to persistence"
    echo "  3) Copy files from persistence"
    echo "  4) Check disk usage"
    echo "  5) Resize persistence image"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-5]: ${NC}")" choice
    
    case "$choice" in
        1)
            mount_ventoy_persistence "$dat_file" || return 1
            echo -e "\n${BOLD}Persistence Contents:${NC}"
            ls -la "$persist_mount/"
            unmount_ventoy_persistence "$persist_mount"
            ;;
        2)
            read -p "$(echo -e "${YELLOW}Source path to copy: ${NC}")" src_path
            if [[ ! -e "$src_path" ]]; then
                print_error "Source not found: $src_path"
                return 1
            fi
            mount_ventoy_persistence "$dat_file" || return 1
            print_info "Copying $src_path to persistence..."
            if [[ -d "$src_path" ]]; then
                sudo cp -a "$src_path"/* "$persist_mount/"
            else
                sudo cp -a "$src_path" "$persist_mount/"
            fi
            print_success "Copy complete"
            unmount_ventoy_persistence "$persist_mount"
            ;;
        3)
            read -p "$(echo -e "${YELLOW}Destination path: ${NC}")" dst_path
            mkdir -p "$dst_path"
            mount_ventoy_persistence "$dat_file" || return 1
            print_info "Copying from persistence to $dst_path..."
            sudo cp -a "$persist_mount"/* "$dst_path/"
            print_success "Copy complete"
            unmount_ventoy_persistence "$persist_mount"
            ;;
        4)
            mount_ventoy_persistence "$dat_file" || return 1
            echo -e "\n${BOLD}Disk Usage:${NC}"
            df -h "$persist_mount"
            echo ""
            du -sh "$persist_mount"/*
            unmount_ventoy_persistence "$persist_mount"
            ;;
        5)
            local img_size
            img_size=$(du -b "$dat_file" | cut -f1)
            local img_size_gb=$((img_size / 1024 / 1024 / 1024))
            print_info "Current size: ${img_size_gb}GB"
            read -p "$(echo -e "${YELLOW}New size in GB: ${NC}")" new_size_gb
            if [[ "$new_size_gb" -le "$img_size_gb" ]]; then
                print_error "New size must be larger than current size"
                return 1
            fi
            print_warning "Resizing will require sudo and may take time"
            print_info "Run: sudo resize2fs ${dat_file} ${new_size_gb}G"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    if [[ "$mount_point" == "${USB_MOUNT_TEMP:-/mnt/ventoy-temp}" ]]; then
        sudo umount "$mount_point" 2>/dev/null
    fi
}

# ==================== DISK IMAGE MANAGEMENT ====================

create_disk_image() {
    local target_path="$1"
    require_root
    print_header "Create Disk Image"
    
    echo "Image type:"
    echo "  1) Raw image (dd format)"
    echo "  2) QCOW2 image (with snapshots)"
    echo "  3) VDI image (VirtualBox)"
    echo "  4) VMDK image (VMware)"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-4]: ${NC}")" img_type
    
    read -p "$(echo -e "${YELLOW}Image name (without extension): ${NC}")" img_name
    read -p "$(echo -e "${YELLOW}Size in GB: ${NC}")" img_size
    
    local ext=""
    local create_cmd=""
    
    case "$img_type" in
        1)
            ext="img"
            print_info "Creating raw ${img_size}GB image..."
            create_cmd="dd if=/dev/zero of=$target_path/$img_name.$ext bs=1M count=$((img_size * 1024)) status=progress"
            ;;
        2)
            ext="qcow2"
            if ! command -v qemu-img &> /dev/null; then
                print_warning "qemu-img not installed"
                if confirm "Install qemu-utils?"; then
                    install_package qemu-utils
                else
                    return 1
                fi
            fi
            print_info "Creating QCOW2 ${img_size}GB image..."
            create_cmd="qemu-img create -f qcow2 $target_path/$img_name.$ext ${img_size}G"
            ;;
        3)
            ext="vdi"
            if ! command -v VBoxManage &> /dev/null; then
                print_error "VirtualBox not installed"
                return 1
            fi
            print_info "Creating VDI ${img_size}GB image..."
            create_cmd="VBoxManage createhd --filename $target_path/$img_name.$ext --size $((img_size * 1024))"
            ;;
        4)
            ext="vmdk"
            if ! command -v qemu-img &> /dev/null; then
                print_warning "qemu-img not installed"
                if confirm "Install qemu-utils?"; then
                    install_package qemu-utils
                else
                    return 1
                fi
            fi
            print_info "Creating VMDK ${img_size}GB image..."
            create_cmd="qemu-img create -f vmdk $target_path/$img_name.$ext ${img_size}G"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
    
    if eval "$create_cmd"; then
        print_success "Image created: $target_path/$img_name.$ext"
        ls -lh "$target_path/$img_name.$ext"
    else
        print_error "Failed to create image"
        return 1
    fi
}

mount_disk_image() {
    local image_path="$1"
    require_root
    print_header "Mount Disk Image: $image_path"
    
    if [[ ! -f "$image_path" ]]; then
        print_error "Image not found: $image_path"
        return 1
    fi
    
    local img_type
    img_type=$(file -b "$image_path" | head -1)
    
    local mount_point="${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image}"
    mkdir -p "$mount_point"
    
    if [[ "$img_type" == *"QEMU QCOW2"* ]]; then
        # QCOW2 needs NBD or conversion
        if ! command -v qemu-nbd &> /dev/null; then
            print_warning "qemu-nbd not installed"
            if confirm "Install qemu-utils?"; then
                install_package qemu-utils
            else
                return 1
            fi
        fi
        
        print_info "Connecting QCOW2 image via NBD..."
        sudo modprobe nbd max_part=8
        local nbd_dev=$(sudo qemu-nbd --connect=/dev/nbd0 "$image_path")
        
        # Wait for partitions to appear
        sleep 2
        
        local part_dev="/dev/nbd0p1"
        if [[ ! -b "$part_dev" ]]; then
            part_dev="/dev/nbd0"
        fi
        
        print_info "Mounting $part_dev..."
        if sudo mount "$part_dev" "$mount_point"; then
            print_success "Mounted at: $mount_point"
            echo "$mount_point"
        else
            print_error "Failed to mount"
            sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null
            return 1
        fi
    elif [[ "$img_type" == *" DOS/MBR"* ]] || [[ "$img_type" == *"partition"* ]]; then
        # Raw image with partition table
        print_info "Setting up loop device..."
        local loop_dev
        loop_dev=$(sudo losetup -fP --show "$image_path")
        
        local part_dev="${loop_dev}p1"
        if [[ ! -b "$part_dev" ]]; then
            part_dev="$loop_dev"
        fi
        
        print_info "Mounting $part_dev..."
        if sudo mount "$part_dev" "$mount_point"; then
            print_success "Mounted at: $mount_point"
            echo "$mount_point"
        else
            print_error "Failed to mount"
            sudo losetup -d "$loop_dev" 2>/dev/null
            return 1
        fi
    else
        # Try direct mount
        print_info "Attempting direct mount..."
        if sudo mount -o loop,ro "$image_path" "$mount_point"; then
            print_success "Mounted at: $mount_point"
            echo "$mount_point"
        else
            print_error "Failed to mount - unknown image format"
            return 1
        fi
    fi
}

unmount_disk_image() {
    local mount_point="$1"
    require_root
    
    if ! mountpoint -q "$mount_point" 2>/dev/null; then
        print_warning "Not mounted: $mount_point"
        return 1
    fi
    
    print_info "Unmounting $mount_point..."
    sudo umount "$mount_point"
    
    # Cleanup loop devices
    local loop_dev
    loop_dev=$(sudo losetup -j "$mount_point" 2>/dev/null | head -1 | cut -d: -f1)
    if [[ -n "$loop_dev" ]]; then
        sudo losetup -d "$loop_dev" 2>/dev/null
    fi
    
    # Cleanup NBD
    if sudo qemu-nbd --list 2>/dev/null | grep -q nbd0; then
        sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null
    fi
    
    print_success "Unmounted"
}

convert_disk_image() {
    local source="$1"
    require_root
    print_header "Convert Disk Image"
    
    if [[ ! -f "$source" ]]; then
        print_error "Source image not found: $source"
        return 1
    fi
    
    echo "Convert to:"
    echo "  1) Raw (img)"
    echo "  2) QCOW2"
    echo "  3) VDI"
    echo "  4) VMDK"
    echo "  5) ISO"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-5]: ${NC}")" format_choice
    
    local ext=""
    local format=""
    local extra_opts=""
    
    case "$format_choice" in
        1) ext="img"; format="raw" ;;
        2) ext="qcow2"; format="qcow2" ;;
        3) ext="vdi"; format="vdi" ;;
        4) ext="vmdk"; format="vmdk" ;;
        5) ext="iso"; format="raw"; extra_opts="-O iso" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac
    
    local dest="${source%.*}.$ext"
    read -p "$(echo -e "${YELLOW}Output path [$dest]: ${NC}")" custom_dest
    dest="${custom_dest:-$dest}"
    
    if ! command -v qemu-img &> /dev/null; then
        print_warning "qemu-img not installed"
        if confirm "Install qemu-utils?"; then
            install_package qemu-utils
        else
            return 1
        fi
    fi
    
    print_info "Converting $source to $format..."
    if qemu-img convert -f raw -O "$format" $extra_opts "$source" "$dest"; then
        print_success "Converted: $dest"
        ls -lh "$dest"
    else
        print_error "Conversion failed"
        return 1
    fi
}

inspect_disk_image() {
    local image_path="$1"
    print_header "Inspect Disk Image: $image_path"
    
    if [[ ! -f "$image_path" ]]; then
        print_error "Image not found: $image_path"
        return 1
    fi
    
    echo -e "${BOLD}File Information:${NC}"
    ls -lh "$image_path"
    echo ""
    
    echo -e "${BOLD}Image Type:${NC}"
    file -b "$image_path"
    echo ""
    
    if command -v qemu-img &> /dev/null; then
        echo -e "${BOLD}QEMU Image Info:${NC}"
        qemu-img info "$image_path" 2>/dev/null
        echo ""
    fi
    
    echo -e "${BOLD}Partition Table:${NC}"
    sudo fdisk -l "$image_path" 2>/dev/null || echo "  Unable to read partition table"
    echo ""
    
    echo -e "${BOLD}Filesystem Type:${NC}"
    sudo blkid "$image_path" 2>/dev/null || echo "  Unknown"
}

list_disk_images() {
    local search_path="$1"
    print_header "Disk Images in: $search_path"
    
    echo -e "${BOLD}Found Images:${NC}"
    find "$search_path" -type f \( -name "*.img" -o -name "*.qcow2" -o -name "*.vdi" -o -name "*.vmdk" -o -name "*.iso" -o -name "*.dat" \) -exec ls -lh {} \; 2>/dev/null | awk '{printf "  %-60s %s\n", $NF, $5}'
    echo ""
    
    local total_size
    total_size=$(find "$search_path" -type f \( -name "*.img" -o -name "*.qcow2" -o -name "*.vdi" -o -name "*.vmdk" -o -name "*.iso" -o -name "*.dat" \) -exec du -ch {} + 2>/dev/null | tail -1 | cut -f1)
    echo "Total: $total_size"
}

manage_disk_images() {
    local mount_point="$1"
    require_root
    print_header "Manage Disk Images"
    
    echo "Image Management Options:"
    echo "  1) List all images"
    echo "  2) Create new image"
    echo "  3) Mount image"
    echo "  4) Unmount image"
    echo "  5) Convert image format"
    echo "  6) Inspect image"
    echo "  7) Delete image"
    echo "  8) Copy files to mounted image"
    echo "  9) Copy files from mounted image"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-9]: ${NC}")" choice
    
    case "$choice" in
        1)
            list_disk_images "$mount_point"
            ;;
        2)
            create_disk_image "$mount_point"
            ;;
        3)
            read -p "$(echo -e "${YELLOW}Image path: ${NC}")" img_path
            mount_disk_image "$img_path"
            ;;
        4)
            unmount_disk_image "${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image}"
            ;;
        5)
            read -p "$(echo -e "${YELLOW}Source image path: ${NC}")" src_img
            convert_disk_image "$src_img"
            ;;
        6)
            read -p "$(echo -e "${YELLOW}Image path: ${NC}")" img_path
            inspect_disk_image "$img_path"
            ;;
        7)
            read -p "$(echo -e "${YELLOW}Image path to delete: ${NC}")" img_path
            if [[ -f "$img_path" ]]; then
                print_warning "DELETE: $img_path"
                if confirm "Are you ABSOLUTELY SURE?" "n"; then
                    rm -f "$img_path"
                    print_success "Deleted"
                fi
            else
                print_error "Image not found"
            fi
            ;;
        8)
            read -p "$(echo -e "${YELLOW}Source path to copy: ${NC}")" src_path
             if [[ -e "$src_path" ]]; then
                 print_info "Copying $src_path to ${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image}..."
                 sudo cp -a "$src_path" "${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image}/"
                 print_success "Copy complete"
            else
                print_error "Source not found"
            fi
            ;;
        9)
            read -p "$(echo -e "${YELLOW}Destination path: ${NC}")" dst_path
             mkdir -p "$dst_path"
             print_info "Copying from ${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image} to $dst_path..."
             sudo cp -a "${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image}"/* "$dst_path/"
             print_success "Copy complete"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
}

# ==================== MKUSB OPERATIONS ====================

mkusb_check() {
    if ! command -v mkusb &> /dev/null; then
        print_warning "mkusb is not installed"
        echo "  Install from: https://help.ubuntu.com/community/mkusb"
        echo "  Or use: sudo apt install mkusb"
        if confirm "Attempt to install mkusb?"; then
            install_package mkusb || return 1
        else
            return 1
        fi
    fi
}

mkusb_create_live() {
    local device="$1"
    require_root
    print_header "Create Live USB with mkusb"

    mkusb_check || return 1

    echo "Select ISO source:"
    echo "  1) Browse for ISO file"
    echo "  2) Enter path manually"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-2]: ${NC}")" iso_choice

    local iso_path=""
    case "$iso_choice" in
        1)
            read -p "$(echo -e "${YELLOW}Path to ISO file: ${NC}")" iso_path
            ;;
        2)
            read -p "$(echo -e "${YELLOW}Path to ISO file: ${NC}")" iso_path
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac

    if [[ ! -f "$iso_path" ]]; then
        print_error "ISO file not found: $iso_path"
        return 1
    fi

    print_info "ISO: $iso_path"
    print_info "Target: $device"
    print_warning "This will DESTROY ALL DATA on $device"

    if ! confirm "Continue?" "n"; then
        return 0
    fi

    echo ""
    echo "Select mode:"
    echo "  1) Live USB (read-only, bootable)"
    echo "  2) Persistent USB (with storage for saving files)"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-2]: ${NC}")" mode_choice

    case "$mode_choice" in
        1)
            print_info "Creating live USB..."
            sudo dd if="$iso_path" of="$device" bs=4M status=progress conv=fsync
            print_success "Live USB created!"
            ;;
        2)
            print_info "Creating persistent USB..."
            print_info "This uses mkusb with dus (Drive Utility Suite)"
            sudo mkusb "$iso_path" "$device"
            print_success "Persistent USB created!"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac

    echo ""
    echo -e "${BOLD}Boot instructions:${NC}"
    echo "  1. Insert USB into target computer"
    echo "  2. Restart and enter BIOS/UEFI (usually F2, F12, or Del)"
    echo "  3. Select USB as boot device"
    echo "  4. Boot into live environment"
}

mkusb_persistent() {
    local device="$1"
    require_root
    print_header "Create Persistent USB"
    print_info "Persistent USB saves files and settings between sessions"

    mkusb_check || return 1

    read -p "$(echo -e "${YELLOW}Path to ISO file: ${NC}")" iso_path
    if [[ ! -f "$iso_path" ]]; then
        print_error "ISO file not found: $iso_path"
        return 1
    fi

    print_warning "This will DESTROY ALL DATA on $device"
    if ! confirm "Continue?" "n"; then
        return 0
    fi

    echo ""
    echo "Persistence size (space for saved data):"
    echo "  1) Small (1 GB) - minimal saves"
    echo "  2) Medium (4 GB) - documents and settings"
    echo "  3) Large (remaining space) - full workspace"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-3]: ${NC}")" size_choice

    local persist_size=""
    case "$size_choice" in
        1) persist_size="1G" ;;
        2) persist_size="4G" ;;
        3) persist_size="" ;;
        *) print_error "Invalid choice"; return 1 ;;
    esac

    print_info "Creating persistent live USB..."
    sudo mkusb -d "$device" -i "$iso_path" -p "$persist_size"
    print_success "Persistent USB created!"
}

# ==================== DEVICE RECOVERY ====================

recover_device() {
    local device="$1"
    require_root
    print_header "Device Recovery: $device"

    echo "Recovery options:"
    echo "  1) Wipe and re-create partition table"
    echo "  2) Clear write protection"
    echo "  3) Reset partition attributes"
    echo "  4) Low-level format (destructive)"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-4]: ${NC}")" recovery_choice

    case "$recovery_choice" in
        1)
            print_warning "This will DESTROY ALL DATA on $device"
            if confirm "Continue?" "n"; then
                print_info "Wiping partition table..."
                dd if=/dev/zero of="$device" bs=1M count=10 2>/dev/null
                print_success "Partition table wiped"
                if confirm "Create new MBR partition table?"; then
                    echo -e "o\nw\n" | fdisk "$device" &>/dev/null
                    print_success "New MBR partition table created"
                fi
            fi
            ;;
        2)
            print_info "Attempting to clear write protection..."
            blockdev --setrw "$device" 2>/dev/null && print_success "Write protection cleared" || \
                print_error "Could not clear write protection (may be hardware switch)"
            ;;
        3)
            print_info "Resetting partition attributes..."
            sgdisk --zap-all "$device" 2>/dev/null && print_success "Attributes reset" || \
                print_error "sgdisk not available. Install with: sudo apt install gdisk"
            ;;
        4)
            print_warning "LOW-LEVEL FORMAT: This will DESTROY ALL DATA and may take hours"
            if confirm "Are you ABSOLUTELY SURE?" "n"; then
                print_info "Running low-level format (this may take a long time)..."
                dd if=/dev/zero of="$device" bs=512 2>/dev/null
                print_success "Low-level format complete"
            fi
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
}

# ==================== CLONE ====================

clone_disk() {
    local source="$1"
    require_root
    print_header "Clone Disk: $source"
    print_warning "This will create an exact copy of $source"
    safety_scan "$source"

    echo "Available destination devices:"
    lsblk -ndo NAME,SIZE,TYPE 2>/dev/null | grep disk | grep -v "$(basename "$source")"
    echo ""

    read -p "$(echo -e "${YELLOW}Destination device (e.g., sdc): ${NC}")" dest_name
    local destination="/dev/$dest_name"

    if [[ ! -b "$destination" ]]; then
        print_error "Invalid destination device"
        return 1
    fi

    print_warning "ALL DATA on $destination will be DESTROYED"
    if ! confirm "Clone $source to $destination?" "n"; then
        return 0
    fi

    local src_size
    src_size=$(lsblk -bno SIZE "$source" | head -1)
    local dst_size
    dst_size=$(lsblk -bno SIZE "$destination" | head -1)

    if [[ $dst_size -lt $src_size ]]; then
        print_error "Destination too small ($dst_size < $src_size)"
        return 1
    fi

    print_info "Cloning... (this will take time)"
    if dd if="$source" of="$destination" bs=4M status=progress conv=fsync; then
        print_success "Clone complete!"
        if confirm "Verify clone integrity?"; then
            print_info "Verifying..."
            local src_hash
            src_hash=$(dd if="$source" bs=4M 2>/dev/null | md5sum | awk '{print $1}')
            local dst_hash
            dst_hash=$(dd if="$destination" bs=4M 2>/dev/null | md5sum | awk '{print $1}')
            if [[ "$src_hash" == "$dst_hash" ]]; then
                print_success "Verification passed!"
            else
                print_error "Verification failed! Hashes don't match"
            fi
        fi
    else
        print_error "Clone failed"
        return 1
    fi
}

# ==================== DOCKER OPERATIONS ====================

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_warning "Docker is not installed"
        echo "  Install from: https://docs.docker.com/engine/install/"
        if confirm "Attempt to install Docker?"; then
            print_info "Installing Docker..."
            curl -fsSL https://get.docker.com | sh
            sudo usermod -aG docker "$USER"
            print_success "Docker installed. Log out and back in for group changes to take effect."
        else
            return 1
        fi
    fi
}

docker_setup_usb() {
    local mount_point="$1"
    require_root
    check_docker || return 1
    print_header "Setup Docker on USB: $mount_point"

    local docker_dir="$mount_point/docker"
    mkdir -p "$docker_dir"/{bin,lib,etc,var/lib/docker,volumes,containers}

    print_info "Docker directory created at: $docker_dir"
    echo ""
    echo -e "${BOLD}Docker USB Setup Options:${NC}"
    echo "  1) Use USB as Docker data directory"
    echo "  2) Create portable Docker binaries"
    echo "  3) Setup Docker volumes on USB"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-3]: ${NC}")" setup_choice

    case "$setup_choice" in
        1)
            print_info "Setting up Docker data directory on USB..."
            local docker_data="$mount_point/docker-data"
            mkdir -p "$docker_data"

            # Create systemd override for Docker
            sudo mkdir -p /etc/systemd/system/docker.service.d
            cat > "$TEMP_DIR/docker-override.conf" <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/dockerd --data-root=$docker_data
EOF
            sudo mv "$TEMP_DIR/docker-override.conf" /etc/systemd/system/docker.service.d/override.conf
            sudo systemctl daemon-reload
            print_success "Docker data directory configured at: $docker_data"
            print_info "Restart Docker: sudo systemctl restart docker"
            ;;
        2)
            print_info "Downloading Docker static binaries..."
            local docker_bin="$mount_point/docker/bin"
            DOCKER_VERSION="24.0.7"
            if command -v curl &> /dev/null; then
                curl -L -o "$TEMP_DIR/docker.tgz" "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"
            else
                wget -O "$TEMP_DIR/docker.tgz" "https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"
            fi
            tar -xzf "$TEMP_DIR/docker.tgz" -C "$TEMP_DIR"
            sudo cp "$TEMP_DIR/docker"/* "$docker_bin/"
            sudo chmod +x "$docker_bin"/*
            rm -rf "$TEMP_DIR/docker" "$TEMP_DIR/docker.tgz"
            print_success "Docker binaries installed to: $docker_bin"
            print_info "Add to PATH: export PATH=$docker_bin:\$PATH"
            ;;
        3)
            print_info "Creating Docker volumes directory..."
            local volumes_dir="$mount_point/docker/volumes"
            mkdir -p "$volumes_dir"
            print_success "Docker volumes directory created at: $volumes_dir"
            print_info "Use with: docker run -v $volumes_dir/myvolume:/data myimage"
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac
}

docker_volume_create() {
    local mount_point="$1"
    require_root
    check_docker || return 1
    print_header "Create Docker Volume on USB"

    read -p "$(echo -e "${YELLOW}Volume name: ${NC}")" volume_name
    if [[ -z "$volume_name" ]]; then
        print_error "Volume name required"
        return 1
    fi

    local volumes_dir="$mount_point/docker/volumes"
    mkdir -p "$volumes_dir/$volume_name"

    print_info "Creating Docker volume: $volume_name"
    if docker volume create \
        --driver local \
        --opt type=none \
        --opt device="$volumes_dir/$volume_name" \
        --opt o=bind \
        "$volume_name"; then
        print_success "Docker volume created: $volume_name"
        print_info "Path: $volumes_dir/$volume_name"
    else
        print_error "Failed to create Docker volume"
        return 1
    fi
}

docker_volume_list() {
    require_root
    check_docker || return 1
    print_header "Docker Volumes"

    echo -e "${BOLD}All Docker Volumes:${NC}"
    docker volume ls
    echo ""
}

docker_volume_backup() {
    local mount_point="$1"
    require_root
    check_docker || return 1
    print_header "Backup Docker Volume to USB"

    read -p "$(echo -e "${YELLOW}Volume name to backup: ${NC}")" volume_name
    if [[ -z "$volume_name" ]]; then
        print_error "Volume name required"
        return 1
    fi

    local backup_dir="$mount_point/docker/backups"
    mkdir -p "$backup_dir"
    local backup_file="$backup_dir/${volume_name}-$(date +%Y%m%d-%H%M%S).tar.gz"

    print_info "Backing up volume: $volume_name"
    if docker run --rm \
        -v "$volume_name":/source:ro \
        -v "$backup_dir":/backup \
        alpine tar czf "/backup/$(basename "$backup_file")" -C /source .; then
        print_success "Backup complete: $backup_file"
    else
        print_error "Backup failed"
        return 1
    fi
}

docker_container_run() {
    local mount_point="$1"
    require_root
    check_docker || return 1
    print_header "Run Docker Container with USB Storage"

    read -p "$(echo -e "${YELLOW}Container name: ${NC}")" container_name
    read -p "$(echo -e "${YELLOW}Docker image: ${NC}")" docker_image

    if [[ -z "$container_name" || -z "$docker_image" ]]; then
        print_error "Container name and image required"
        return 1
    fi

    echo "Mount options:"
    echo "  1) Data directory"
    echo "  2) Volume"
    echo "  3) Multiple mounts"
    echo ""
    read -p "$(echo -e "${YELLOW}Choice [1-3]: ${NC}")" mount_choice

    local mount_args=""
    case "$mount_choice" in
        1)
            local data_dir="$mount_point/data"
            mkdir -p "$data_dir"
            mount_args="-v $data_dir:/app/data"
            ;;
        2)
            read -p "$(echo -e "${YELLOW}Volume name: ${NC}")" vol_name
            mount_args="-v $vol_name:/app/data"
            ;;
        3)
            read -p "$(echo -e "${YELLOW}Mount paths (space-separated): ${NC}")" mount_paths
            for path in $mount_paths; do
                local full_path="$mount_point/$path"
                mkdir -p "$full_path"
                mount_args="$mount_args -v $full_path:/$path"
            done
            ;;
        *)
            print_error "Invalid choice"
            return 1
            ;;
    esac

    print_info "Running container: $container_name"
    if docker run -d \
        --name "$container_name" \
        $mount_args \
        "$docker_image"; then
        print_success "Container started: $container_name"
        docker ps --filter "name=$container_name"
    else
        print_error "Failed to start container"
        return 1
    fi
}

docker_container_list() {
    require_root
    check_docker || return 1
    print_header "Docker Containers"

    echo -e "${BOLD}Running Containers:${NC}"
    docker ps
    echo ""
    echo -e "${BOLD}All Containers (including stopped):${NC}"
    docker ps -a
    echo ""
}

docker_backup_all() {
    local mount_point="$1"
    require_root
    check_docker || return 1
    print_header "Backup All Docker Data to USB"

    local backup_dir="$mount_point/docker/full-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"/{volumes,images,containers}

    print_info "Backing up Docker volumes..."
    for vol in $(docker volume ls -q); do
        print_info "  Backing up volume: $vol"
        docker run --rm \
            -v "$vol":/source:ro \
            -v "$backup_dir/volumes":/backup \
            alpine tar czf "/backup/$vol.tar.gz" -C /source . 2>/dev/null
    done

    print_info "Backing up Docker images..."
    for img in $(docker images -q); do
        local img_name
        img_name=$(docker inspect --format='{{.RepoTags}}' "$img" 2>/dev/null | tr -d '[]' | tr ':' '-' || echo "$img")
        print_info "  Backing up image: $img_name"
        docker save "$img" | gzip > "$backup_dir/images/$img_name.tar.gz"
    done

    print_success "Full backup complete: $backup_dir"
    echo "  Volumes: $(ls "$backup_dir/volumes" | wc -l) backed up"
    echo "  Images: $(ls "$backup_dir/images" | wc -l) backed up"
}

# ==================== MAIN MENU ====================

show_main_menu() {
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        return 1
    fi
    clear
    print_header "$SCRIPT_NAME - Device: $SELECTED_DEVICE"

    echo "Available Operations:"
    echo ""
    echo "  ${BOLD}Analysis & Information:${NC}"
    echo "    1) Analyze device"
    echo "    2) Safety scan"
    echo "    3) File type scan (if mounted)"
    echo ""
    echo "  ${BOLD}Mounting:${NC}"
    echo "    4) Mount partition"
    echo "    5) Unmount partition"
    echo ""
    echo "  ${BOLD}Partitioning & Formatting:${NC}"
    echo "    6) Create partition table (DESTRUCTIVE)"
    echo "    7) Create partition"
    echo "    8) Format partition (DESTRUCTIVE)"
    echo ""
    echo "  ${BOLD}Ventoy (Multi-ISO Boot):${NC}"
    echo "    v) Setup Ventoy on this device"
    echo "    i) List ISOs on Ventoy drive"
    echo "    u) Update Ventoy"
    echo "    p) Manage Ventoy persistence"
    echo ""
    echo "  ${BOLD}mkusb (Live/Persistent USB):${NC}"
    echo "    m) Create live USB from ISO"
    echo "    s) Create persistent USB from ISO"
    echo ""
    echo "  ${BOLD}Recovery & Advanced:${NC}"
    echo "    r) Recover device (hidden, write-protected, corrupted)"
    echo "    c) Clone this device"
    echo "    h) Scan for hidden/unrecognized devices"
    echo ""
    echo "  ${BOLD}Docker Management:${NC}"
    echo "    d) Setup Docker on USB"
    echo "    v) Create Docker volume on USB"
    echo "    l) List Docker volumes"
    echo "    b) Backup Docker volume to USB"
    echo "    n) Run Docker container with USB storage"
    echo "    k) List Docker containers"
    echo "    f) Full Docker backup to USB"
    echo ""
    echo "  ${BOLD}Disk Image Management:${NC}"
    echo "    g) Manage disk images"
    echo ""
    echo "  ${BOLD}Other:${NC}"
    echo "    9) Select different device"
    echo "    q) Quit"
    echo ""
}

main_loop() {
    while true; do
        show_main_menu
        read -p "$(echo -e "${YELLOW}Select operation: ${NC}")" choice
        echo ""
        case "$choice" in
            1) analyze_device "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            2) safety_scan "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            3)
                echo "Enter partition to scan (e.g., ${SELECTED_DEVICE}1):"
                read -p "$(echo -e "${YELLOW}Partition: ${NC}")" part
                if [[ -b "$part" ]]; then
                    local mp
                    mp=$(lsblk -no MOUNTPOINT "$part" 2>/dev/null)
                    if [[ -n "$mp" ]]; then
                        scan_file_types "$mp"
                    else
                        print_error "Partition not mounted"
                    fi
                else
                    print_error "Invalid partition"
                fi
                read -p "Press Enter to continue..."
                ;;
            4)
                echo "Enter partition to mount (e.g., ${SELECTED_DEVICE}1):"
                read -p "$(echo -e "${YELLOW}Partition: ${NC}")" part
                [[ -b "$part" ]] && mount_partition "$part" || print_error "Invalid partition"
                read -p "Press Enter to continue..."
                ;;
            5)
                echo "Enter partition to unmount (e.g., ${SELECTED_DEVICE}1):"
                read -p "$(echo -e "${YELLOW}Partition: ${NC}")" part
                [[ -b "$part" ]] && unmount_partition "$part" || print_error "Invalid partition"
                read -p "Press Enter to continue..."
                ;;
            6) create_partition_table "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            7) create_partition "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            8)
                echo "Enter partition to format (e.g., ${SELECTED_DEVICE}1):"
                read -p "$(echo -e "${YELLOW}Partition: ${NC}")" part
                [[ -b "$part" ]] && format_partition "$part" || print_error "Invalid partition"
                read -p "Press Enter to continue..."
                ;;
            v|V) ventoy_setup "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            i|I) ventoy_list_isos "${SELECTED_DEVICE}1"; read -p "Press Enter to continue..." ;;
            u|U) ventoy_update "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            p|P) ventoy_persistence_manage "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            m|M) mkusb_create_live "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            s|S) mkusb_persistent "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            r|R) recover_device "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            c|C) clone_disk "$SELECTED_DEVICE"; read -p "Press Enter to continue..." ;;
            h|H) scan_hidden_devices; read -p "Press Enter to continue..." ;;
            d|D)
                echo "Enter the USB mount point (as shown by 'lsblk' / 'findmnt'):"
                read -p "$(echo -e "${YELLOW}Mount point: ${NC}")" mount_pt
                [[ -d "$mount_pt" ]] && docker_setup_usb "$mount_pt" || print_error "Invalid mount point"
                read -p "Press Enter to continue..."
                ;;
            v|V)
                echo "Enter the USB mount point (as shown by 'lsblk' / 'findmnt'):"
                read -p "$(echo -e "${YELLOW}Mount point: ${NC}")" mount_pt
                [[ -d "$mount_pt" ]] && docker_volume_create "$mount_pt" || print_error "Invalid mount point"
                read -p "Press Enter to continue..."
                ;;
            l|L) docker_volume_list; read -p "Press Enter to continue..." ;;
            b|B)
                echo "Enter the USB mount point (as shown by 'lsblk' / 'findmnt'):"
                read -p "$(echo -e "${YELLOW}Mount point: ${NC}")" mount_pt
                [[ -d "$mount_pt" ]] && docker_volume_backup "$mount_pt" || print_error "Invalid mount point"
                read -p "Press Enter to continue..."
                ;;
            n|N)
                echo "Enter the USB mount point (as shown by 'lsblk' / 'findmnt'):"
                read -p "$(echo -e "${YELLOW}Mount point: ${NC}")" mount_pt
                [[ -d "$mount_pt" ]] && docker_container_run "$mount_pt" || print_error "Invalid mount point"
                read -p "Press Enter to continue..."
                ;;
            k|K) docker_container_list; read -p "Press Enter to continue..." ;;
            f|F)
                echo "Enter the USB mount point (as shown by 'lsblk' / 'findmnt'):"
                read -p "$(echo -e "${YELLOW}Mount point: ${NC}")" mount_pt
                [[ -d "$mount_pt" ]] && docker_backup_all "$mount_pt" || print_error "Invalid mount point"
                read -p "Press Enter to continue..."
                ;;
            g|G)
                echo "Enter the USB mount point (as shown by 'lsblk' / 'findmnt'):"
                read -p "$(echo -e "${YELLOW}Mount point: ${NC}")" mount_pt
                [[ -d "$mount_pt" ]] && manage_disk_images "$mount_pt" || print_error "Invalid mount point"
                read -p "Press Enter to continue..."
                ;;
            9) unset SELECTED_DEVICE; select_device ;;
            q|Q) echo "Goodbye!"; exit 0 ;;
            *) print_error "Invalid choice"; sleep 1 ;;
        esac
    done
}

# ==================== CLI MODE ====================

show_help() {
    echo "USB Manager v2.1.0 - Comprehensive USB Drive Management"
    echo ""
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  (none)              Interactive menu mode"
    echo "  --scan-hidden       Scan for hidden/unrecognized devices"
    echo "  --ventoy-setup      Set up Ventoy on selected device"
    echo "  --ventoy-list       List ISOs on Ventoy drive"
    echo "  --ventoy-persist    Manage Ventoy persistence"
    echo "  --mkusb-live        Create live USB with mkusb"
    echo "  --mkusb-persistent  Create persistent USB with mkusb"
    echo "  --recover           Recover hidden/corrupted device"
    echo "  --clone             Clone a device"
    echo "  --analyze DEV       Analyze a specific device (e.g., /dev/sdb)"
    echo "  --docker-setup MP   Setup Docker on USB at mount point"
    echo "  --docker-volume MP  Create Docker volume on USB"
    echo "  --docker-backup MP  Backup Docker volume to USB"
    echo "  --docker-run MP     Run Docker container with USB storage"
    echo "  --docker-full-backup MP  Full Docker backup to USB"
    echo "  --image-manage MP   Manage disk images on USB"
    echo "  --image-create MP   Create new disk image"
    echo "  --image-mount IMG   Mount a disk image"
    echo "  --image-unmount     Unmount disk image"
    echo "  --image-convert SRC Convert disk image format"
    echo "  --image-inspect IMG Inspect disk image"
    echo "  --help              Show this help"
    echo ""
    echo "Examples:"
    echo "  sudo $0                        # Interactive mode"
    echo "  sudo $0 --scan-hidden          # Find hidden USB devices"
    echo "  sudo $0 --ventoy-setup         # Set up multi-ISO boot USB"
    echo "  sudo $0 --ventoy-persist       # Manage persistence"
    echo "  sudo $0 --analyze /dev/sdb     # Analyze specific device"
    echo "  sudo $0 --docker-setup \"\$USB_MOUNT\"  # Setup Docker on USB"
    echo "  sudo $0 --image-manage \"\$USB_MOUNT\"  # Manage disk images"
    echo ""
}

# ==================== MAIN ENTRY POINT ====================

main() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "╔═══════════════════════════════════════════════════════════╗"
    echo "║                                                           ║"
    echo "║                    USB MANAGER v2.1                       ║"
    echo "║  Ventoy | mkusb | Docker | Images | Recovery            ║"
    echo "║                                                           ║"
    echo "╚═══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    log "=== USB Manager v2.1 started ==="

    check_dependencies

    # CLI mode
    case "${1:-}" in
        --scan-hidden)   scan_hidden_devices; exit 0 ;;
        --ventoy-setup)  select_device && ventoy_setup "$SELECTED_DEVICE"; exit 0 ;;
        --ventoy-list)   select_device && ventoy_list_isos "${SELECTED_DEVICE}1"; exit 0 ;;
        --ventoy-persist) select_device && ventoy_persistence_manage "$SELECTED_DEVICE"; exit 0 ;;
        --mkusb-live)    select_device && mkusb_create_live "$SELECTED_DEVICE"; exit 0 ;;
        --mkusb-persistent) select_device && mkusb_persistent "$SELECTED_DEVICE"; exit 0 ;;
        --recover)       select_device && recover_device "$SELECTED_DEVICE"; exit 0 ;;
        --clone)         select_device && clone_disk "$SELECTED_DEVICE"; exit 0 ;;
        --analyze)       [[ -b "${2:-}" ]] && analyze_device "$2" || print_error "Invalid device"; exit 0 ;;
        --docker-setup)  [[ -d "${2:-}" ]] && docker_setup_usb "$2" || print_error "Invalid mount point"; exit 0 ;;
        --docker-volume) [[ -d "${2:-}" ]] && docker_volume_create "$2" || print_error "Invalid mount point"; exit 0 ;;
        --docker-backup) [[ -d "${2:-}" ]] && docker_volume_backup "$2" || print_error "Invalid mount point"; exit 0 ;;
        --docker-run)    [[ -d "${2:-}" ]] && docker_container_run "$2" || print_error "Invalid mount point"; exit 0 ;;
        --docker-full-backup) [[ -d "${2:-}" ]] && docker_backup_all "$2" || print_error "Invalid mount point"; exit 0 ;;
        --image-manage)  [[ -d "${2:-}" ]] && manage_disk_images "$2" || print_error "Invalid mount point"; exit 0 ;;
        --image-create)  [[ -d "${2:-}" ]] && create_disk_image "$2" || print_error "Invalid path"; exit 0 ;;
        --image-mount)   [[ -f "${2:-}" ]] && mount_disk_image "$2" || print_error "Invalid image"; exit 0 ;;
        --image-unmount) unmount_disk_image "${DISK_IMAGE_MOUNT_POINT:-/mnt/disk-image}"; exit 0 ;;
        --image-convert) [[ -f "${2:-}" ]] && convert_disk_image "$2" || print_error "Invalid image"; exit 0 ;;
        --image-inspect) [[ -f "${2:-}" ]] && inspect_disk_image "$2" || print_error "Invalid image"; exit 0 ;;
        --dry-run)       DRY_RUN=true; shift; set -- "$@" ;;
        --help|-h)       show_help; exit 0 ;;
    esac

    # Interactive mode
    if ! select_device; then
        print_error "No device selected"
        read -p "Press Enter to continue..."
        exit 1; print_error "no device"
    fi
    main_loop
}

main "$@"
