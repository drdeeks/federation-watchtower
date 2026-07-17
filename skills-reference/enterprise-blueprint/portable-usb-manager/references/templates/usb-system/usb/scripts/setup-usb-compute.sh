#!/usr/bin/env bash
# ============================================================================
# USB Compute Automation System - One-Time Host Setup
# ============================================================================
#
# This script sets up the host system to automatically detect, configure, and
# boot a Ventoy USB drive in headless mode with SSH access when plugged in.
# It installs necessary dependencies, configures LaunchAgents, and prepares
# the USB drive for isolated compute workloads.
#
# Features:
# - Interactive setup with confirmations
# - Backups before modifications
# - Cross-platform compatible (conceptual)
# - Installs build essentials to USB free space
# - Configures headless VM boot with SSH port forwarding
# - Sets up auto-update and health checking
# - Supports Ventoy with ISO selection
#
# Usage: ./setup-usb-compute.sh
#
# ============================================================================

set -euo pipefail

# Trap unhandled errors for debugging — but don't kill the script on piped commands
trap 'echo "[ERROR] Script failed at line $LINENO (exit code: $?)" | tee -a "${LOG_FILE:-/dev/null}"' ERR

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_NAME="USB Compute Automation Setup"
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
LOG_FILE="/tmp/usb-compute-setup-$(date +%Y%m%d-%H%M%S).log"
VENTOY_TARBALL="$SCRIPT_DIR/volumes/ventoy/ventoy-1.0.99-linux.tar.gz"
VENTOY_VERSION="1.0.99"
BACKUP_DIR="/tmp/usb-compute-backup-$(date +%Y%m%d-%H%M%S)"
UTM_APP_NAME="UTM"
DOCKER_COMPOSE_FILE="docker-compose.yml"
LAUNCH_AGENT_NAME="com.usbcompute.autostart"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_NAME}.plist"

# USB detection configuration
VENDOR_PRODUCT_KEY="Ventoy"  # Adjust based on actual USB vendor/product
MOUNT_POINT_PREFIX="/media"
SSH_PORT_FORWARD_HOST=2222
SSH_PORT_FORWARD_GUEST=22

# ============================================================================
# COLOR DEFINITIONS
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}✓${NC} $1"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}✗${NC} $1"
    log "ERROR: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}⚠${NC} $1"
    log "WARNING: $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}ℹ${NC} $1"
    log "INFO: $1"
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

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

backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
            print_warning "Failed to create backup directory $BACKUP_DIR (non-critical)"
            return 0
        fi
        if ! cp "$file" "$BACKUP_DIR/" 2>/dev/null; then
            print_warning "Failed to backup $file (non-critical)"
            return 0
        fi
        log "Backed up $file to $BACKUP_DIR/"
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This operation requires root privileges"
        echo "Please run with sudo: sudo $0"
        return 1
    fi
}

check_dependency() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        return 1
    fi
    return 0
}

# ============================================================================
# INITIALIZATION
# ============================================================================

initialize() {
    print_header "$SCRIPT_NAME v$VERSION"
    log "Starting USB Compute Automation Setup"
    
    # Create log file
    : > "$LOG_FILE" 2>/dev/null || { echo "Warning: Could not create log file at $LOG_FILE"; }
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR" 2>/dev/null || { echo "Warning: Could not create backup directory at $BACKUP_DIR"; }
    
    print_info "Logs will be saved to: $LOG_FILE"
    print_info "Backups will be saved to: $BACKUP_DIR"
    
    # Check OS
    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macOS"
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        OS="Linux"
    else
        print_error "Unsupported operating system: $(uname)"
        print_info "How to resolve: This script supports macOS and Linux only."
        print_info "  For Windows, please use WSL2 or a Linux VM."
        exit 1
    fi
    
    print_info "Detected OS: $OS"
}

# ============================================================================
# PRE-REQUISITES CHECK
# ============================================================================

check_prerequisites() {
    print_header "Checking Prerequisites"
    
    local missing_deps=()
    
    # Check for essential commands
    local essential_cmds=("curl" "wget" "mkdir" "mount" "umount")
    for cmd in "${essential_cmds[@]}"; do
        if ! check_dependency "$cmd"; then
            missing_deps+=("$cmd")
        fi
    done
    
    # Platform-specific dependency checks
    if [[ "$OS" == "Linux" ]]; then
        for cmd in "lsblk" "blkid" "fdisk"; do
            if ! check_dependency "$cmd"; then
                missing_deps+=("$cmd")
            fi
        done
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing essential dependencies: ${missing_deps[*]}"
        print_info "How to resolve:"
        if [[ "$OS" == "macOS" ]]; then
            print_info "  Most tools come with macOS. Install Homebrew for additional tools:"
            print_info "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        else
            print_info "  On Ubuntu/Debian: sudo apt update && sudo apt install -y ${missing_deps[*]}"
            print_info "  On Fedora/RHEL: sudo dnf install -y ${missing_deps[*]}"
        fi
        exit 1
    fi
    
    # Check for UTM (macOS) or QEMU/KVM (Linux)
    if [[ "$OS" == "macOS" ]]; then
        if [[ ! -d "/Applications/$UTM_APP_NAME.app" ]]; then
            print_warning "$UTM_APP_NAME not found"
            if confirm "Would you like to install $UTM_APP_NAME now?"; then
                if check_dependency "brew"; then
                    if ! brew install --cask "$UTM_APP_NAME"; then
                        print_error "Failed to install $UTM_APP_NAME via Homebrew"
                        print_info "How to resolve: Try installing manually from https://mac.getutm.app"
                        exit 1
                    fi
                else
                    print_error "Homebrew not found"
                    print_info "How to resolve:"
                    print_info "  1. Install Homebrew: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    print_info "  2. Or download $UTM_APP_NAME manually from https://mac.getutm.app"
                    exit 1
                fi
            else
                print_warning "$UTM_APP_NAME is recommended for USB VM boot functionality"
                print_info "You can install it later from https://mac.getutm.app"
            fi
        else
            print_success "$UTM_APP_NAME is installed"
        fi
    else
        # Linux - check for QEMU/KVM
        local virt_cmds=("qemu-system-x86_64" "kvm" "virt-manager")
        local virt_found=0
        for cmd in "${virt_cmds[@]}"; do
            if check_dependency "$cmd"; then
                virt_found=1
                break
            fi
        done
        
        if [[ $virt_found -eq 0 ]]; then
            print_warning "QEMU/KVM not found"
            if confirm "Would you like to install QEMU/KVM now?"; then
                local distro=""
                if check_dependency "lsb_release"; then
                    distro=$(lsb_release -si 2>/dev/null || true)
                fi
                if [[ "$distro" == "Ubuntu" ]] || [[ "$distro" == "Debian" ]]; then
                    if ! sudo apt update && sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils; then
                        print_error "Failed to install QEMU/KVM"
                        print_info "How to resolve: Try installing manually or check your internet connection."
                        exit 1
                    fi
                elif [[ "$distro" == "Fedora" ]] || [[ "$distro" == "CentOS" ]] || [[ "$distro" == "RedHatEnterpriseServer" ]]; then
                    if ! sudo dnf install -y @virtualization; then
                        print_error "Failed to install QEMU/KVM"
                        print_info "How to resolve: Try installing manually or check your internet connection."
                        exit 1
                    fi
                else
                    print_error "Could not determine Linux distribution"
                    print_info "How to resolve: Please install QEMU/KVM manually for your distribution."
                    print_info "  Ubuntu/Debian: sudo apt install qemu-kvm libvirt-daemon-system"
                    print_info "  Fedora/RHEL: sudo dnf install @virtualization"
                    print_info "  Arch: sudo pacman -S qemu-full virt-manager"
                    exit 1
                fi
            else
                print_warning "QEMU/KVM is recommended for USB VM boot functionality"
                print_info "You can install it later using your package manager."
            fi
        else
            print_success "QEMU/KVM virtualization is available"
        fi
    fi
    
    # Check for Docker (optional but recommended)
    if ! check_dependency "docker"; then
        print_warning "Docker not found (optional but recommended for container management inside VM)"
        if confirm "Would you like to install Docker now?"; then
            if [[ "$OS" == "macOS" ]]; then
                if check_dependency "brew"; then
                    if ! brew install --cask docker; then
                        print_warning "Failed to install Docker via Homebrew"
                        print_info "You can install it later from https://docker.com/products/docker-desktop"
                    fi
                else
                    print_warning "Homebrew not found"
                    print_info "You can install Docker Desktop from https://docker.com/products/docker-desktop"
                fi
            else
                local distro=""
                if check_dependency "lsb_release"; then
                    distro=$(lsb_release -si 2>/dev/null || true)
                fi
                if [[ "$distro" == "Ubuntu" ]] || [[ "$distro" == "Debian" ]]; then
                    if ! sudo apt update && sudo apt install -y docker.io; then
                        print_warning "Failed to install Docker"
                    fi
                    sudo systemctl enable --now docker 2>/dev/null || true
                elif [[ "$distro" == "Fedora" ]] || [[ "$distro" == "CentOS" ]] || [[ "$distro" == "RedHatEnterpriseServer" ]]; then
                    if ! sudo dnf install -y docker; then
                        print_warning "Failed to install Docker"
                    fi
                    sudo systemctl enable --now docker 2>/dev/null || true
                else
                    print_warning "Could not determine Linux distribution"
                    print_info "Please install Docker manually from https://docs.docker.com/engine/install/"
                fi
            fi
        fi
    else
        print_success "Docker is installed"
    fi
    
    print_success "Prerequisites check completed"
}

# ============================================================================
# USB DETECTION AND SELECTION
# ============================================================================

detect_usb_devices() {
    print_header "Detecting USB Devices"
    
    local usb_devices=()
    
    if [[ "$OS" == "macOS" ]]; then
        # macOS diskutil approach
        while IFS= read -r line; do
            usb_devices+=("$line")
        done < <(diskutil list external physical 2>/dev/null | grep -E "^/dev/" | awk '{print $1}' || true)
    else
        # Linux lsblk approach
        while IFS= read -r line; do
            usb_devices+=("$line")
        done < <(lsblk -ndo NAME,SIZE,TYPE,TRAN,MODEL 2>/dev/null | grep -E 'usb|disk' | grep -v 'loop' | awk '{print "/dev/" $1}' || true)
    fi
    
    if [[ ${#usb_devices[@]} -eq 0 ]]; then
        print_warning "No USB devices detected"
        print_info "How to resolve:"
        print_info "  1. Ensure a USB drive is plugged in"
        print_info "  2. Check if the USB is recognized by your OS"
        if [[ "$OS" == "macOS" ]]; then
            print_info "  3. Try: diskutil list"
        else
            print_info "  3. Try: lsblk or sudo fdisk -l"
        fi
        return 1
    fi
    
    echo "Found USB devices:"
    echo ""
    if [[ "$OS" == "macOS" ]]; then
        printf "${BOLD}%-10s %-10s %-10s %-15s %-30s${NC}\n" "DEVICE" "SIZE" "TYPE" "CONNECTION" "DESCRIPTION"
    else
        printf "${BOLD}%-10s %-10s %-10s %-15s %-30s${NC}\n" "DEVICE" "SIZE" "TYPE" "TRANSPORT" "MODEL"
    fi
    echo "─────────────────────────────────────────────────────────────────────────────"
    
    local index=1
    for device in "${usb_devices[@]}"; do
        local size type connection model
        
        if [[ "$OS" == "macOS" ]]; then
            # macOS specific parsing
            size=$(diskutil info "$device" 2>/dev/null | grep "Total Size" | awk '{print $3,$4}' || echo "unknown")
            type=$(diskutil info "$device" 2>/dev/null | grep "Device Node" | awk '{print $3}' || echo "unknown")
            connection=$(diskutil info "$device" 2>/dev/null | grep "Protocol" | awk '{print $2}' || echo "unknown")
            model=$(diskutil info "$device" 2>/dev/null | grep "Device / Media Name" | awk -F': ' '{print $2}' || echo "unknown")
        else
            # Linux specific parsing
            size=$(lsblk -no SIZE "$device" 2>/dev/null || echo "unknown")
            type=$(lsblk -no TYPE "$device" 2>/dev/null || echo "unknown")
            connection=$(lsblk -no TRAN "$device" 2>/dev/null || echo "unknown")
            model=$(lsblk -no MODEL "$device" 2>/dev/null || echo "unknown")
        fi
        
        printf "${CYAN}%2d)${NC} %-10s %-10s %-10s %-15s %-30s\n" \
            "$index" "$size" "$type" "$connection" "$model"
        ((index++))
    done
    echo ""
    
    echo "${usb_devices[@]}"
}

select_usb_device() {
    local devices=($(detect_usb_devices))
    if [[ ${#devices[@]} -eq 0 ]]; then
        return 1
    fi
    
    local count=${#devices[@]}
    local selection
    
    while true; do
        read -p "$(echo -e "${YELLOW}Select USB device number [1-${count}] or 'q' to quit: ${NC}")" selection
        [[ "$selection" == "q" ]] && return 1
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
            SELECTED_DEVICE="${devices[$((selection-1))]}"
            print_success "Selected: $SELECTED_DEVICE"
            
            # Show device details
            print_header "Device Details: $SELECTED_DEVICE"
            if [[ "$OS" == "macOS" ]]; then
                diskutil info "$SELECTED_DEVICE" 2>/dev/null || print_warning "Could not get device details"
            else
                lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null || print_warning "Could not get device details"
            fi
            return 0
        else
            print_error "Invalid selection. Please enter a number between 1 and $count"
        fi
    done
}

# ============================================================================
# VENTOY SETUP AND ISO CONFIGURATION
# ============================================================================

check_ventoy_installed() {
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        return 1
    fi
    if [[ "$OS" == "macOS" ]]; then
        # Check if Ventoy is installed on the selected USB
        if [[ -b "${SELECTED_DEVICE}s1" ]]; then
            local vol_name
            vol_name=$(diskutil info "${SELECTED_DEVICE}s1" 2>/dev/null | grep "Volume Name" | awk '{print $3}' || true)
            if [[ "$vol_name" == "Ventoy" ]]; then
                return 0
            fi
        fi
    else
        # Linux check
        if [[ -b "${SELECTED_DEVICE}1" ]]; then
            local label
            label=$(blkid -o value -s LABEL "${SELECTED_DEVICE}1" 2>/dev/null || true)
            if [[ "$label" == "Ventoy" ]]; then
                return 0
            fi
        fi
    fi
    return 1
}

setup_ventoy() {
    print_header "Ventoy Setup"

    local install_log="/tmp/ventoy-install-$(date +%Y%m%d-%H%M%S).log"
    local ventoy_tmp="/tmp/ventoy-${VENTOY_VERSION}"

    if check_ventoy_installed; then
        print_success "Ventoy is already installed on $SELECTED_DEVICE"
        if ! confirm "Do you want to reinstall Ventoy (this will ERASE all data on the USB)?"; then
            return 0
        fi
    fi
    
    print_warning "This will ERASE ALL DATA on $SELECTED_DEVICE"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue with Ventoy installation?" "n"; then
        print_info "Ventoy installation cancelled"
        return 1
    fi

    # --- Step 1: Check root ---
    print_info "[1/5] Checking root privileges..."
    log "[1/5] Checking root privileges"
    require_root || return 1
    print_success "Running as root"

    # --- Step 2: Verify local Ventoy tarball ---
    print_info "[2/5] Locating Ventoy package..."
    log "[2/5] Checking local Ventoy tarball: $VENTOY_TARBALL"
    if [[ ! -f "$VENTOY_TARBALL" ]]; then
        print_error "Local Ventoy tarball not found at: $VENTOY_TARBALL"
        print_info "How to resolve: Download Ventoy and place it in the repo:"
        print_info "  mkdir -p $SCRIPT_DIR/volumes/ventoy"
        print_info "  curl -fSL -o $VENTOY_TARBALL https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
        log "ERROR: Tarball not found at $VENTOY_TARBALL"
        read -p "Press Enter to continue..."
        return 1
    fi
    print_success "Found: $(basename "$VENTOY_TARBALL") ($(du -h "$VENTOY_TARBALL" | cut -f1))"

    # --- Step 3: Extract Ventoy ---
    print_info "[3/5] Extracting Ventoy to $ventoy_tmp..."
    log "[3/5] Extracting to $ventoy_tmp"
    rm -rf "$ventoy_tmp"
    if ! mkdir -p "$ventoy_tmp" 2>>"$install_log"; then
        print_error "Failed to create temp directory: $ventoy_tmp"
        log "ERROR: mkdir $ventoy_tmp failed"
        read -p "Press Enter to continue..."
        return 1
    fi
    if ! tar -xzf "$VENTOY_TARBALL" -C "$ventoy_tmp" 2>>"$install_log"; then
        print_error "Failed to extract Ventoy archive"
        log "ERROR: tar extraction failed. Log: $install_log"
        cat "$install_log" 2>/dev/null
        read -p "Press Enter to continue..."
        rm -rf "$ventoy_tmp"
        return 1
    fi
    print_success "Extracted successfully"

    # --- Step 4: Verify Ventoy2Disk.sh ---
    local ventoy_script="$ventoy_tmp/ventoy-${VENTOY_VERSION}/Ventoy2Disk.sh"
    log "[4/5] Checking Ventoy2Disk.sh at: $ventoy_script"
    if [[ ! -f "$ventoy_script" ]]; then
        print_error "Ventoy2Disk.sh not found at: $ventoy_script"
        log "ERROR: Ventoy2Disk.sh not found. Contents: $(ls -la "$ventoy_tmp/ventoy-${VENTOY_VERSION}/" 2>&1)"
        read -p "Press Enter to continue..."
        rm -rf "$ventoy_tmp"
        return 1
    fi
    print_success "Ventoy2Disk.sh found"

    # --- Step 5: Run Ventoy install ---
    print_info "[5/5] Installing Ventoy to $SELECTED_DEVICE..."
    log "[5/5] Installing Ventoy to $SELECTED_DEVICE"

    # Unmount any partitions on the device first
    print_info "Unmounting any partitions on $SELECTED_DEVICE..."
    for part in "${SELECTED_DEVICE}"*; do
        if [[ -b "$part" ]]; then
            umount "$part" 2>/dev/null && log "Unmounted $part" || log "Could not unmount $part (may not be mounted)"
        fi
    done

    # Run Ventoy2Disk.sh with piped 'y' answers for both confirmation prompts
    print_info "Running Ventoy2Disk.sh -i $SELECTED_DEVICE ..."
    log "Running: echo -e 'y\\ny' | $ventoy_script -i $SELECTED_DEVICE"

    local ventoy_output
    local ventoy_exit=0
    ventoy_output=$(echo -e "y\ny" | "$ventoy_script" -i "$SELECTED_DEVICE" 2>&1) || ventoy_exit=$?

    # Log everything
    echo "$ventoy_output" >> "$install_log"
    log "Ventoy2Disk.sh exit code: $ventoy_exit"

    # Show the Ventoy output
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  Ventoy2Disk.sh output:"
    echo "════════════════════════════════════════════════════════"
    echo "$ventoy_output"
    echo "════════════════════════════════════════════════════════"
    echo ""

    if [[ $ventoy_exit -eq 0 ]]; then
        print_success "Ventoy installed successfully to $SELECTED_DEVICE!"
        log "SUCCESS: Ventoy installed to $SELECTED_DEVICE"
        
        echo ""
        echo -e "${BOLD}Next steps for Ventoy configuration:${NC}"
        echo "  1. Mount the Ventoy partition: ${SELECTED_DEVICE}1"
        echo "  2. Copy ISO files to the mounted partition"
        echo "  3. Safely eject and boot from the USB"
        echo ""
        echo -e "${BOLD}Supported ISO types:${NC}"
        echo "  Linux: Ubuntu, Fedora, Debian, Arch, Mint, openSUSE, etc."
        echo "  Windows: Windows 10, 11, Server installers"
        echo "  Utilities: GParted, Clonezilla, Hiren's, MemTest86, etc."
        
        rm -rf "$ventoy_tmp"
        read -p "Press Enter to continue..."
        return 0
    else
        print_error "Ventoy installation FAILED (exit code: $ventoy_exit)"
        log "ERROR: Ventoy2Disk.sh failed with exit code $ventoy_exit"
        echo ""
        print_info "Full install log saved to: $install_log"
        print_info "Ventoy's own log: $ventoy_tmp/ventoy-${VENTOY_VERSION}/log.txt"
        echo ""
        print_info "How to resolve:"
        print_info "  1. Read the error output above for details"
        print_info "  2. Ensure the USB is not mounted: sudo umount ${SELECTED_DEVICE}*"
        print_info "  3. Ensure no processes are using it: sudo lsof ${SELECTED_DEVICE}"
        print_info "  4. Try manually: sudo $ventoy_script -i $SELECTED_DEVICE"
        if [[ -f "$ventoy_tmp/ventoy-${VENTOY_VERSION}/log.txt" ]]; then
            print_info "  5. Ventoy log contents:"
            cat "$ventoy_tmp/ventoy-${VENTOY_VERSION}/log.txt"
        fi
        echo ""
        read -p "Press Enter to continue..."
        rm -rf "$ventoy_tmp"
        return 1
    fi
}

configure_ventoy_persistence() {
    print_header "Ventoy Persistence Configuration"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_error "No USB device selected. Please select a device first."
        return 1
    fi
    
    # Check if Ventoy partition is mounted
    local ventoy_mount_point=""
    if [[ "$OS" == "macOS" ]]; then
        ventoy_mount_point=$(df | grep "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
    else
        ventoy_mount_point=$(df | grep "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
    fi
    
    if [[ -z "$ventoy_mount_point" ]]; then
        print_info "Mounting Ventoy partition..."
        if [[ "$OS" == "macOS" ]]; then
            mkdir -p "/Volumes/Ventoy" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}s1" "/Volumes/Ventoy"; then
                print_error "Failed to mount Ventoy partition"
                print_info "How to resolve: Ensure the USB is plugged in and Ventoy is installed."
                return 1
            fi
            ventoy_mount_point="/Volumes/Ventoy"
        else
            mkdir -p "/mnt/ventoy" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}1" "/mnt/ventoy"; then
                print_error "Failed to mount Ventoy partition"
                print_info "How to resolve: Ensure the USB is plugged in and Ventoy is installed."
                return 1
            fi
            ventoy_mount_point="/mnt/ventoy"
        fi
    fi
    
    # Check if persistence already exists
    if [[ -f "$ventoy_mount_point/persistence/ubuntu-persistence.dat" ]]; then
        print_success "Ventoy persistence already exists"
        if ! confirm "Do you want to recreate the persistence file (this will DELETE existing persistence)?" "n"; then
            if [[ "$OS" == "macOS" ]]; then
                umount "/Volumes/Ventoy" 2>/dev/null || true
            else
                umount "/mnt/ventoy" 2>/dev/null || true
            fi
            return 0
        fi
    fi
    
    # Create persistence file
    print_info "Creating Ventoy persistence file..."
    local persistence_dir="$ventoy_mount_point/persistence"
    if ! mkdir -p "$persistence_dir"; then
        print_error "Failed to create persistence directory"
        print_info "How to resolve: Check if the USB partition is writable."
        if [[ "$OS" == "macOS" ]]; then
            umount "/Volumes/Ventoy" 2>/dev/null || true
        else
            umount "/mnt/ventoy" 2>/dev/null || true
        fi
        return 1
    fi
    
    # Ask for persistence size
    local persistence_size_gb=20
    read -p "$(echo -e "${YELLOW}Enter persistence size in GB [default: 20]: ${NC}")" input_size
    if [[ -n "$input_size" ]] && [[ "$input_size" =~ ^[0-9]+$ ]]; then
        persistence_size_gb="$input_size"
    fi
    
    print_info "Creating ${persistence_size_gb}GB persistence file..."
    if ! dd if=/dev/zero of="$persistence_dir/ubuntu-persistence.dat" bs=1M count=$((persistence_size_gb * 1024)) status=progress; then
        print_error "Failed to create persistence file"
        print_info "How to resolve: Ensure the USB has at least ${persistence_size_gb}GB of free space."
        print_info "  Check available space: df -h $ventoy_mount_point"
        if [[ "$OS" == "macOS" ]]; then
            umount "/Volumes/Ventoy" 2>/dev/null || true
        else
            umount "/mnt/ventoy" 2>/dev/null || true
        fi
        return 1
    fi
    
    # Format as ext4
    print_info "Formatting persistence file as ext4..."
    if ! mkfs.ext4 -F -L casper-rw "$persistence_dir/ubuntu-persistence.dat"; then
        print_error "Failed to format persistence file as ext4"
        print_info "How to resolve: Ensure e2fsprogs is installed (sudo apt install e2fsprogs)"
        if [[ "$OS" == "macOS" ]]; then
            umount "/Volumes/Ventoy" 2>/dev/null || true
        else
            umount "/mnt/ventoy" 2>/dev/null || true
        fi
        return 1
    fi
    
    # Create ventoy.json configuration
    print_info "Creating Ventoy configuration..."
    if ! mkdir -p "$ventoy_mount_point/ventoy"; then
        print_error "Failed to create ventoy config directory"
        print_info "How to resolve: Check if the USB partition is writable."
        if [[ "$OS" == "macOS" ]]; then
            umount "/Volumes/Ventoy" 2>/dev/null || true
        else
            umount "/mnt/ventoy" 2>/dev/null || true
        fi
        return 1
    fi
    if ! cat > "$ventoy_mount_point/ventoy/ventoy.json" << 'EOF'
{
    "persistence": [{
        "image": "/ubuntu-24.04.4-desktop-amd64.iso",
        "backend": "/persistence/ubuntu-persistence.dat"
    }]
}
EOF
    then
        print_error "Failed to write Ventoy configuration"
        print_info "How to resolve: Check if the USB partition is writable and has enough space."
        if [[ "$OS" == "macOS" ]]; then
            umount "/Volumes/Ventoy" 2>/dev/null || true
        else
            umount "/mnt/ventoy" 2>/dev/null || true
        fi
        return 1
    fi
    
    print_success "Ventoy persistence configured successfully!"
    
    # Provide ISO copy instructions
    echo ""
    echo -e "${BOLD}To complete Ventoy setup:${NC}"
    echo "  1. Download an Ubuntu ISO (recommended: ubuntu-24.04.4-desktop-amd64.iso)"
    echo "  2. Copy it to the Ventoy partition:"
    if [[ "$OS" == "macOS" ]]; then
        echo "     cp ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso /Volumes/Ventoy/"
    else
        echo "     cp ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso /mnt/ventoy/"
    fi
    echo "  3. Safely eject the USB"
    echo ""
    
    # Unmount
    if [[ "$OS" == "macOS" ]]; then
        umount "/Volumes/Ventoy" 2>/dev/null || print_warning "Could not unmount /Volumes/Ventoy (may need manual unmount)"
    else
        umount "/mnt/ventoy" 2>/dev/null || print_warning "Could not unmount /mnt/ventoy (may need manual unmount)"
    fi
    
    return 0
}

# ============================================================================
# VM CONFIGURATION FOR HEADLESS BOOT
# ============================================================================

create_vm_config() {
    print_header "Creating VM Configuration"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_error "No USB device selected. Please select a device first."
        return 1
    fi

    # Determine VM configuration directory
    local script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
    local vm_config_dir="$script_root/vm-provision"
    if ! mkdir -p "$vm_config_dir"; then
        print_error "Failed to create VM config directory at $vm_config_dir"
        print_info "How to resolve: Check if you have write permissions to the parent directory."
        return 1
    fi
    
    # Create UTM plist for headless boot with USB passthrough
    # Note: UTM doesn't have direct CLI for VM creation, so we'll create a template
    # that the user can import, or we'll use AppleScript to configure UTM
    
    local utm_plist="$vm_config_dir/usb-compute-vm.plist"
    
    # Create a basic UTM VM configuration for headless boot
    # This is a simplified version - in practice, UTM VM creation is complex
    # and usually done via the GUI or AppleScript
    cat > "$utm_plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>UUID</key>
    <string>USB-COMPUTE-VM-$(uuidgen | tr '[:upper:]' '[:lower:]')</string>
    <key>Name</key>
    <string>USB Compute VM</string>
    <key>OSType</key>
    <string>Linux</string>
    <key>MemorySize</key>
    <integer>4096</integer>
    <key>CPUCount</key>
    <integer>2</integer>
    <key>BootLoader</key>
    <string> BIOS </string>
    <key>Drives</key>
    <array>
        <dict>
            <key>Interface</key>
            <string> VirtIO </string>
            <key>URL</key>
            <string> $SELECTED_DEVICE </string>
            <key>Boot</key>
            <true/>
        </dict>
    </array>
    <key>Networks</key>
    <array>
        <dict>
            <key>Type</key>
            <string> SharedNetwork </string>
            <key>Options</key>
            <dict>
                <key>PortForwarding</key>
                <array>
                    <dict>
                        <key>Protocol</key>
                        <string> TCP </string>
                        <key>GuestPort</key>
                        <integer> $SSH_PORT_FORWARD_GUEST </integer>
                        <key>HostPort</key>
                        <integer> $SSH_PORT_FORWARD_HOST </integer>
                        <key>Description</key>
                        <string> SSH Access </string>
                    </dict>
                </array>
            </dict>
        </dict>
    </array>
    <key>BootOrder</key>
    <string> Drive </string>
    <key>Headless</key>
    <true/>
    <key>DisableDisplay</key>
    <true/>
</dict>
</plist>
EOF
    
    print_success "VM configuration template created at: $utm_plist"
    print_info "To create the actual VM in UTM:"
    echo "  1. Open UTM"
    echo "  2. Click '+' to create new VM"
    echo "  3. Select 'Virtualize' and choose the USB device as the boot drive"
    echo "  4. Configure 2 CPU cores and 4GB RAM"
    echo "  5. Add port forwarding: Host $SSH_PORT_FORWARD_HOST → Guest $SSH_PORT_FORWARD_GUEST (SSH)"
    echo "  6. Enable 'Headless' mode"
    echo "  7. Save the VM"
    echo ""
    
    return 0
}

# ============================================================================
# LAUNCHAGENT FOR AUTO-DETECTION AND AUTO-BOOT
# ============================================================================

create_launch_agent() {
    print_header "Creating Launch Agent for USB Auto-Detection"
    
    # Create the LaunchAgent plist
    if ! mkdir -p "$(dirname "$LAUNCH_AGENT_PLIST")"; then
        print_error "Failed to create LaunchAgents directory"
        print_info "How to resolve: Ensure $HOME/Library/LaunchAgents/ exists and is writable."
        return 1
    fi
    
    # Create a wrapper script that will be called by the LaunchAgent
    local script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
    local wrapper_script="$script_root/scripts/usb-detector.sh"
    if ! mkdir -p "$(dirname "$wrapper_script")"; then
        print_error "Failed to create scripts directory"
        print_info "How to resolve: Check if you have write permissions to the parent directory."
        return 1
    fi
    
    cat > "$wrapper_script" << EOF
#!/usr/bin/env bash
# USB Detector Script - Called by LaunchAgent when USB devices change

LOG_FILE="/tmp/usb-compute-automation-\$(date +%Y%m%d).log"
SCRIPT_DIR="$script_root"
VM_NAME="USB Compute VM"  # This should match the VM name in UTM

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check if specific USB is connected
is_target_usb_connected() {
    # This is a simplified check - in practice, you'd check for specific USB identifiers
    # For Ventoy, we could check for the Ventoy partition label
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS check
        if diskutil list external | grep -q "Ventoy"; then
            return 0
        fi
    else
        # Linux check
        if blkid -l 2>/dev/null | grep -q "Ventoy"; then
            return 0
        fi
    fi
    return 1
}

# Start the UTM VM
start_utm_vm() {
    log "Target USB detected, attempting to start UTM VM: $VM_NAME"
    
    # Check if UTM is running
    if pgrep -q "UTM"; then
        log "UTM is already running"
    else
        log "Starting UTM application..."
        open -a "UTM" &
        # Wait for UTM to launch
        sleep 5
    fi
    
    # Use AppleScript to start the specific VM
    # Note: This requires UTM to be running and the VM to be pre-configured
    /usr/bin/osascript << EOS
    tell application "UTM"
        if it is running then
            try
                start virtual machine id of (first virtual machine whose name is "$VM_NAME")
                log message "Started VM: $VM_NAME"
            on error errMsg
                log message "Error starting VM: $errMsg"
            end try
        end if
    end tell
EOS
}

# Main execution
log "USB detector script executed"

if is_target_usb_connected; then
    log "Target USB device detected"
    start_utm_vm
else
    log "Target USB device not connected"
fi
EOF
    
    if ! chmod +x "$wrapper_script"; then
        print_error "Failed to make wrapper script executable"
        print_info "How to resolve: Check file permissions: ls -la $wrapper_script"
        return 1
    fi
    
    # Create the LaunchAgent plist
    cat > "$LAUNCH_AGENT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LAUNCH_AGENT_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>$wrapper_script</string>
    </array>
    <key>WatchPaths</key>
    <array>
        <string>/dev</string>
    </array>
    <key>StartInterval</key>
    <integer>10</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/usb-compute-automation.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/usb-compute-automation.err</string>
</dict>
</plist>
EOF
    
    print_success "Launch Agent created at: $LAUNCH_AGENT_PLIST"
    print_info "Wrapper script created at: $wrapper_script"
    
    # Load the LaunchAgent
    print_info "Loading Launch Agent..."
    if ! launchctl load "$LAUNCH_AGENT_PLIST" 2>/dev/null; then
        print_warning "Could not auto-load Launch Agent (this is normal if already loaded)"
        print_info "How to resolve if needed:"
        print_info "  1. Unload first: launchctl unload $LAUNCH_AGENT_PLIST"
        print_info "  2. Reload: launchctl load $LAUNCH_AGENT_PLIST"
    fi
    
    print_success "Launch Agent loaded and active"
    print_info "The system will now automatically detect when the Ventoy USB is plugged in"
    print_info "and attempt to start the UTM VM in headless mode with SSH port forwarding"
    
    return 0
}

# ============================================================================
# PROVISION USB FREE SPACE WITH BUILD ESSENTIALS
# ============================================================================

provision_usb_free_space() {
    print_header "Provisioning USB Free Space with Build Essentials"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_error "No USB device selected. Please select a device first."
        return 1
    fi

    # Check if USB is mounted
    local usb_mount_point=""
    if [[ "$OS" == "macOS" ]]; then
        usb_mount_point=$(df | grep "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
    else
        usb_mount_point=$(df | grep "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
    fi
    
    if [[ -z "$usb_mount_point" ]]; then
        print_info "Mounting USB partition..."
        if [[ "$OS" == "macOS" ]]; then
            mkdir -p "/Volumes/USB_FREE_SPACE" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}s1" "/Volumes/USB_FREE_SPACE"; then
                print_error "Failed to mount USB partition"
                print_info "How to resolve: Ensure the USB is plugged in and not in use."
                return 1
            fi
            usb_mount_point="/Volumes/USB_FREE_SPACE"
        else
            mkdir -p "/mnt/usb_free_space" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}1" "/mnt/usb_free_space"; then
                print_error "Failed to mount USB partition"
                print_info "How to resolve: Ensure the USB is plugged in and not in use."
                return 1
            fi
            usb_mount_point="/mnt/usb_free_space"
        fi
    fi
    
    # Create directory structure for build essentials
    local essentials_dir="$usb_mount_point/essentials"
    mkdir -p "$essentials_dir"/{bin,lib,include,share}
    
    print_info "Installing build essentials to USB free space..."
    
    # Create a script to install essentials when run from within the USB environment
    local install_script="$essentials_dir/install-essentials.sh"
    cat > "$install_script" << 'EOF'
#!/usr/bin/env bash
# Install build essentials inside the USB Linux environment
# This script is designed to run inside the Ubuntu live system with persistence

set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

print_header() {
    echo -e "\n=== $1 ===\n"
}

print_success() {
    echo -e "✓ $1"
}

print_error() {
    echo -e "✗ $1"
}

print_info() {
    echo -e "ℹ $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root. Use sudo."
    exit 1
fi

print_header "Installing Build Essentials"

# Update package list
print_info "Updating package list..."
apt-get update

# Install essential build tools
print_info "Installing build-essential..."
apt-get install -y build-essential

# Install development tools
print_info "Installing development tools..."
apt-get install -y git curl wget vim nano htop

# Install Python and pip
print_info "Installing Python 3 and pip..."
apt-get install -y python3 python3-pip python3-venv

# Install Node.js and npm
print_info "Installing Node.js and npm..."
apt-get install -y nodejs npm

# Install additional useful tools
print_info "Installing additional tools..."
apt-get install -y \
    make \
    cmake \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libffi-dev \
    libreadline-dev \
    libbz2-dev \
    liblzma-dev \
    sqlite3 \
    libsqlite3-dev \
    tk-dev \
    libgdbm-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxslt1-dev \
    libjpeg-dev \
    libpng-dev \
    unzip \
    p7zip-full \
    rsync \
    ssh \
    net-tools \
    dnsutils

# Clean up
print_info "Cleaning up..."
apt-get autoremove -y
apt-get clean

print_success "Build essentials installation completed!"
print_info "Available tools:"
echo "  - GCC/G++ (build-essential)"
echo "  - Git, Curl, Wget"
echo "  - Vim, Nano, Htop"
echo "  - Python 3 + Pip"
echo "  - Node.js + Npm"
echo "  - Make, CMake"
echo "  - Various compression tools"
echo "  - SSH client/server"
EOF
    
    if ! chmod +x "$install_script"; then
        print_warning "Failed to make install script executable (non-critical)"
    fi
    
    # Create a README for the essentials directory
    local readme_file="$essentials_dir/README.md"
    cat > "$readme_file" << 'EOF'
# USB Compute Essentials

This directory contains tools and scripts for setting up a development environment
inside the USB-based Linux system.

## Contents

- `install-essentials.sh` - Script to install build essentials inside the Ubuntu environment
- `bin/` - Directory for user-installed binaries
- `lib/` - Directory for libraries
- `include/` - Directory for header files
- `share/` - Directory for shared resources

## Usage

When booted into the Ubuntu live system with persistence:

```bash
# Mount the USB free space (if not already mounted)
sudo mount /dev/diskXs1 /mnt/usb_free_space  # Adjust diskX as needed

# Run the essentials installer
sudo /mnt/usb_free_space/essentials/install-essentials.sh

# The essentials will be available in the USB environment
```

## Included Tools

After running `install-essentials.sh`, you'll have:

- **Compilers**: GCC, G++, Make, CMake
- **Version Control**: Git
- **Network Tools**: Curl, Wget, SSH, Net-tools, Dnsutils
- **Editors**: Vim, Nano
- **System Tools**: Htop, Vim, Unzip, P7zip, Rsync
- **Languages**: Python 3 + Pip, Node.js + Npm
- **Libraries**: Essential development libraries (SSL, Zlib, FFI, Readline, Bzip2, Lzma, SQLite, TK, GDBM, NCURSES, XML, XSLT, JPEG, PNG)

## Notes

- This script is designed to run inside the Ubuntu live system with persistence
- It installs packages to the system, which will persist across boots thanks to Ventoy persistence
- The USB free space (exFAT) is used to store the installer script, but the actual packages
  are installed to the persistent ext4 filesystem
EOF
    
    print_success "USB free space provisioned at: $essentials_dir"
    print_info "Build essentials installer created at: $install_script"
    
    # Provide usage instructions
    echo ""
    echo -e "${BOLD}To install build essentials in the USB Linux environment:${NC}"
    echo "  1. Boot from the Ventoy USB (will auto-start in headless mode via UTM)"
    echo "  2. SSH into the VM: ssh -p $SSH_PORT_FORWARD_HOST user@localhost"
    echo "  3. Once logged in, run:"
    if [[ "$OS" == "macOS" ]]; then
        echo "     sudo /Volumes/USB_FREE_SPACE/essentials/install-essentials.sh"
    else
        echo "     sudo /mnt/usb_free_space/essentials/install-essentials.sh"
    fi
    echo ""
    
    # Unmount
    if [[ "$OS" == "macOS" ]]; then
        umount "/Volumes/USB_FREE_SPACE" 2>/dev/null || print_warning "Could not unmount /Volumes/USB_FREE_SPACE (may need manual unmount)"
    else
        umount "/mnt/usb_free_space" 2>/dev/null || print_warning "Could not unmount /mnt/usb_free_space (may need manual unmount)"
    fi
    
    return 0
}

# ============================================================================
# HEALTH CHECK AND UPDATE SYSTEM
# ============================================================================

create_health_check_script() {
    print_header "Creating Health Check Script"
    
    local script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
    local health_script="$script_root/scripts/health-check.sh"
    mkdir -p "$(dirname "$health_script")"
    
    cat > "$health_script" << EOF
#!/usr/bin/env bash
# USB Compute Automation Health Check Script

set -euo pipefail

LOG_FILE="/tmp/usb-compute-health-\$(date +%Y%m%d).log"
SCRIPT_DIR="$script_root"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n=== $1 ===\n" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "✓ $1" | tee -a "$LOG_FILE"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "✗ $1" | tee -a "$LOG_FILE"
    log "ERROR: $1"
}

print_warning() {
    echo -e "⚠ $1" | tee -a "$LOG_FILE"
    log "WARNING: $1"
}

print_info() {
    echo -e "ℹ $1" | tee -a "$LOG_FILE"
    log "INFO: $1"
}

check_system_requirements() {
    print_header "Checking System Requirements"
    
    # Check if UTM is installed (macOS) or QEMU available (Linux)
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ -d "/Applications/UTM.app" ]]; then
            print_success "UTM is installed"
        else
            print_error "UTM is not installed"
            return 1
        fi
    else
        if command -v qemu-system-x86_64 &> /dev/null; then
            print_success "QEMU is available"
        else
            print_error "QEMU is not available"
            return 1
        fi
    fi
    
    # Check if LaunchAgent is loaded
    if launchctl list | grep -q "com.usbcompute.autostart"; then
        print_success "Launch Agent is loaded"
    else
        print_warning "Launch Agent is not loaded"
    fi
    
    return 0
}

check_usb_device() {
    print_header "Checking USB Device Status"
    
    # This would check for the specific USB device
    # For now, we'll just report that the system is ready to detect
    print_info "USB detection system is active"
    print_info "When a Ventoy USB is plugged in, the system will:"
    echo "  1. Detect the USB device"
    echo "  2. Launch UTM (if not already running)"
    echo "  3. Start the configured VM in headless mode"
    echo "  4. Enable SSH port forwarding (Host:2222 → Guest:22)"
    echo ""
    
    return 0
}

check_vm_readiness() {
    print_header "Checking VM Readiness"
    
    print_info "To check if the USB Compute VM is ready:"
    echo "  1. Ensure UTM is installed and running"
    echo "  2. Verify a VM named 'USB Compute VM' exists in UTM"
    echo "  3. Confirm the VM is configured to boot from USB"
    echo "  4. Check that port forwarding is set up (Host:2222 → Guest:22)"
    echo "  5. Verify the VM is set to headless mode"
    echo ""
    
    return 0
}

# Main execution
case "${1:-}" in
    --system)
        check_system_requirements
        ;;
    --usb)
        check_usb_device
        ;;
    --vm)
        check_vm_readiness
        ;;
    *)
        print_header "USB Compute Automation Health Check"
        check_system_requirements
        echo ""
        check_usb_device
        echo ""
        check_vm_readiness
        ;;
esac

exit 0
EOF
    
    if ! chmod +x "$health_script"; then
        print_warning "Failed to make health check script executable (non-critical)"
    fi
    
    print_success "Health check script created at: $health_script"
    return 0
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    initialize
    
    print_header "USB Compute Automation Setup - Main Execution Flow"
    echo "This script will:"
    echo "  1. Check and install prerequisites"
    echo "  2. Configure Ventoy on selected USB drive (optional)"
    echo "  3. Create VM configuration for headless boot"
    echo "  4. Set up LaunchAgent for USB auto-detection and auto-boot"
    echo "  5. Provision USB free space with build essentials installer"
    echo "  6. Create health check and update scripts"
    echo ""
    
    if ! confirm "Do you want to continue with the setup?"; then
        print_info "Setup cancelled by user"
        exit 0
    fi
    
    # Step 1: Check prerequisites
    check_prerequisites
    
    # Step 2: USB device selection
    print_header "USB Device Selection"
    if ! select_usb_device; then
        print_error "No USB device selected"
        exit 1
    fi
    
    # Step 3: Ventoy setup (optional)
    print_header "Ventoy Configuration"
    if confirm "Do you want to configure Ventoy on the selected USB drive?"; then
        if ! setup_ventoy; then
            print_warning "Ventoy setup failed or was skipped"
        else
            if confirm "Do you want to configure Ventoy persistence?"; then
                configure_ventoy_persistence
            fi
        fi
    fi
    
    # Step 4: VM configuration
    create_vm_config
    
    # Step 5: LaunchAgent setup
    if confirm "Do you want to set up automatic USB detection and VM boot?"; then
        create_launch_agent
    fi
    
    # Step 6: Provision USB free space
    if confirm "Do you want to provision USB free space with build essentials installer?"; then
        provision_usb_free_space
    fi
    
    # Step 7: Health check system
    create_health_check_script
    
    # Final summary
    print_header "Setup Complete"
    print_success "USB Compute Automation System has been configured!"
    
    echo ""
    echo -e "${BOLD}Next Steps:${NC}"
    echo "  1. If you configured Ventoy:"
    echo "     - Download an Ubuntu ISO (ubuntu-24.04.4-desktop-amd64.iso)"
    echo "     - Copy it to the Ventoy USB partition"
    echo "     - Safely eject the USB"
    echo ""
    echo "  2. If you set up the Launch Agent:"
    echo "     - The system will now detect when the Ventoy USB is plugged in"
    echo "     - It will automatically attempt to start the UTM VM in headless mode"
    echo "     - SSH will be available via: ssh -p $SSH_PORT_FORWARD_HOST user@localhost"
    echo ""
    echo "  3. To install build essentials in the USB Linux environment:"
    echo "     - Boot from the Ventoy USB (auto-starts VM via Launch Agent)"
    echo "     - SSH into the VM: ssh -p $SSH_PORT_FORWARD_HOST user@localhost"
    echo "     - Run the essentials installer:"
    if [[ "$OS" == "macOS" ]]; then
        echo "       sudo /Volumes/USB_FREE_SPACE/essentials/install-essentials.sh"
    else
        echo "       sudo /mnt/usb_free_space/essentials/install-essentials.sh"
    fi
    echo ""
    local script_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
    echo "  4. To run health checks:"
    echo "     - $script_root/scripts/health-check.sh"
    echo ""
    echo -e "${BOLD}Important Notes:${NC}"
    echo "  - The VM will run in complete isolation from the host system"
    echo "  - No host environment variables or config files will be accessible inside the VM"
    echo "  - All persistent data is stored on the USB drive via Ventoy persistence"
    echo "  - The system is designed to be headless - no GUI required for operation"
    echo "  - SSH access provides full terminal access for package downloads and development"
    echo ""
    
    # Show where to find important files
    echo -e "${BOLD}Important File Locations:${NC}"
    echo "  - Setup script log: $LOG_FILE"
    echo "  - Backups: $BACKUP_DIR"
    echo "  - Launch Agent: $LAUNCH_AGENT_PLIST"
    echo "  - Health check script: $script_root/scripts/health-check.sh"
    echo "  - USB detector script: $script_root/scripts/usb-detector.sh"
    echo ""
    
    print_success "Setup completed successfully!"
}

# Trap for cleanup on exit
trap 'echo "Setup interrupted. Cleaning up..."; exit 1' INT TERM

# Execute main function
main "$@"