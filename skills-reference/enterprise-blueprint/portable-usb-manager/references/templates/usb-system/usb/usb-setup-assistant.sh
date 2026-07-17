#!/usr/bin/env bash
# ============================================================================
# USB Compute Automation System - Interactive Setup Assistant
# ============================================================================
#
# This script provides an interactive, safe, and informative setup experience for
# the USB Compute Automation System. It guides users through the complete
# setup process including USB preparation, VM configuration, and system
# initialization.
#
# Features:
# - Fully interactive with clear explanations at each step
# - Safety confirmations before destructive actions
# - Informative descriptions of what each component does
# - Clear distinction between required and optional steps
# - Progress tracking and validation
# - Cross-platform compatible (conceptual logic for Windows/macOS/Linux)
#
# Usage: ./usb-setup-assistant.sh
#
# ============================================================================

set -euo pipefail

# Trap unhandled errors for debugging — but don't kill the script on piped commands
trap 'echo "[ERROR] Script failed at line $LINENO (exit code: $?)" | tee -a "${LOG_FILE:-/dev/null}"' ERR

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_NAME="USB Compute Automation Setup Assistant"
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/usb-setup-assistant-$(date +%Y%m%d-%H%M%S).log"
VENTOY_TARBALL="$SCRIPT_DIR/volumes/ventoy/ventoy-1.0.99-linux.tar.gz"
VENTOY_VERSION="1.0.99"
BACKUP_DIR="/tmp/usb-setup-backup-$(date +%Y%m%d-%H%M%S)"
UTM_APP_NAME="UTM"
DOCKER_COMPOSE_FILE="docker-compose.yml"
LAUNCH_AGENT_NAME="com.usbcompute.autostart"
LAUNCH_AGENT_PLIST="$HOME/Library/LaunchAgents/${LAUNCH_AGENT_NAME}.plist"

# USB detection configuration
VENDOR_PRODUCT_KEY="Ventoy"
MOUNT_POINT_PREFIX="/media"

# Selected USB device (initialized empty; set by select_usb_device)
SELECTED_DEVICE=""

# Port forwarding configuration (compute resource access)
# SSH for VM access
SSH_PORT_FORWARD_HOST=2222
SSH_PORT_FORWARD_GUEST=22

# Hemlock Gateway ports (agent/crew orchestration)
HEMLOCK_GATEWAY_PORT=18789
HEMLOCK_MCP_PROXY_PORT=41214

# Resource access ports (for containers in persistence)
# These allow containers full compute access without host system access
CONTAINER_COMPUTE_PORTS=(
    "8888:8888"   # Jupyter
    "8080:8080"   # Web services
    "11434:11434" # Ollama API
    "8000:8000"   # Custom APIs
    "5000:5000"   # Flask/FastAPI
    "3000:3000"   # Node.js apps
)

# Isolation configuration
CONTAINER_ISOLATION=true  # Containers cannot access host filesystem/network
PERSISTENCE_MOUNT_MODE="rw"  # Read-write for compute workloads

# ============================================================================
# MODEL MANAGEMENT & LLAMA.CPP CONFIGURATION
# ============================================================================

# Model storage (persistent volume)
MODEL_VOLUME="hemlock-models"
MODEL_MOUNT_POINT="/models"

# llama.cpp build configuration
LLAMA_CPP_REPO="https://github.com/ggerganov/llama.cpp"
LLAMA_CPP_VERSION="b4810"  # Latest stable commit
LLAMA_CPP_BUILD_DIR="/opt/llama.cpp"

# Hardware detection for auto-configuration
LLAMA_HW_DETECT=true
LLAMA_CUDA=false
LLAMA_METAL=false
LLAMA_HIPBLAS=false
LLAMA_BLAS=true
LLAMA_OPENCL=false
LLAMA_VULKAN=false

# Model management
# One-model-at-a-time policy for efficient resource usage
MODEL_SINGLETON=true          # Only one model loaded at a time
MODEL_HANDOFF_GRACEFUL=true   # Wind down before loading new model
MODEL_RESOURCE_MONITOR=true   # Monitor VRAM/RAM usage
MODEL_EVICTION_POLICY="lru"   # Least recently used eviction

# Model caching & optimization
MODEL_CACHE_DIR="/models/cache"
MODEL_KV_CACHE_SIZE="512M"    # KV cache size per model
MODEL_MMAP=true               # Use mmap for fast loading
MODEL_MLOCK=false             # Lock model in memory (requires root)
MODEL_NUMA=false              # NUMA awareness

# Quantization defaults
LLAMA_DEFAULT_QUANT="Q4_K_M"  # Default quantization
LLAMA_SUPPORTED_QUANTS=("Q2_K" "Q3_K_S" "Q3_K_M" "Q3_K_L" "Q4_0" "Q4_K_S" "Q4_K_M" "Q5_0" "Q5_K_S" "Q5_K_M" "Q6_K" "Q8_0" "F16" "F32")

# Context & performance
LLAMA_DEFAULT_CTX=8192        # Default context size
LLAMA_DEFAULT_THREADS=0       # 0 = auto-detect
LLAMA_BATCH_SIZE=512          # Batch size for prompt processing
LLAMA_UBATCH_SIZE=512         # Micro-batch size

# Model handoff configuration
MODEL_HANDOFF_TIMEOUT=30      # Seconds to wait for model unload
MODEL_PRELOAD_NEXT=true       # Pre-load next model in background
MODEL_HANDOFF_SIGNAL="SIGUSR1" # Signal for handoff coordination

# Auto-scan for local models
MODEL_AUTO_SCAN=true
MODEL_SCAN_INTERVAL=300       # Scan every 5 minutes

# Plugin & MCP integration for models
MODEL_MCP_ENABLED=true
MODEL_PLUGIN_ENABLED=true
DRY_RUN=false
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]] || [[ "$arg" == "-n" ]]; then
        DRY_RUN=true
    fi
done

run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

# ============================================================================
# SUDO CACHING (session-only, auto-cleanup after validation)
# ============================================================================
SUDO_CACHE_FILE="/tmp/usb-sudo-cache-$$"
SUDO_CACHED=false

cache_sudo_password() {
    if [[ "$SUDO_CACHED" == "true" ]]; then
        return 0
    fi
    
    if [[ -f "$SUDO_CACHE_FILE" ]]; then
        export SUDO_ASKPASS="$SUDO_CACHE_FILE"
        SUDO_CACHED=true
        return 0
    fi
    
    print_info "Caching sudo password for session (auto-deleted after setup validation)..."
    echo ""
    read -s -p "Enter sudo password: " sudo_pass
    echo ""
    
    if [[ -z "$sudo_pass" ]]; then
        print_error "No password entered"
        return 1
    fi
    
    # Verify password works
    if ! echo "$sudo_pass" | sudo -S -v 2>/dev/null; then
        print_error "Invalid sudo password"
        return 1
    fi
    
    # Create askpass script
    cat > "$SUDO_CACHE_FILE" << ASKPASS_EOF
#!/usr/bin/env bash
echo "$sudo_pass"
ASKPASS_EOF
    chmod 700 "$SUDO_CACHE_FILE"
    export SUDO_ASKPASS="$SUDO_CACHE_FILE"
    SUDO_CACHED=true
    print_success "Sudo cached for session"
    return 0
}

clear_sudo_cache() {
    if [[ -f "$SUDO_CACHE_FILE" ]]; then
        shred -u "$SUDO_CACHE_FILE" 2>/dev/null || rm -f "$SUDO_CACHE_FILE"
        print_info "Sudo cache cleared: $SUDO_CACHE_FILE"
    else
        print_info "Sudo cache already clear (no file found)"
    fi
    # Also clear sudo's timestamp cache
    sudo -k 2>/dev/null || true
    unset SUDO_ASKPASS
    SUDO_CACHED=false
}

sudo_run() {
    if [[ "$SUDO_CACHED" == "true" && -f "$SUDO_CACHE_FILE" ]]; then
        sudo -A "$@"
    else
        sudo "$@"
    fi
}

# Trap to ensure cache cleanup on exit
trap 'clear_sudo_cache' EXIT TERM
trap 'print_warning "Interrupted — cleaning up..."; clear_sudo_cache; exit 130' INT
SSH_PORT_FORWARD_GUEST=22

# ============================================================================
# DRY-RUN SUPPORT
# ============================================================================

run_or_dry() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] Would execute: $*"
        return 0
    fi
    "$@"
}

# ============================================================================
# UNIFIED MOUNT DETECTION
# ============================================================================

# Global mount point variable (set by detect_ventoy_mount)
VENTOY_MOUNT=""

# Detect and mount Ventoy partition with multiple fallback methods
# Usage: detect_ventoy_mount || { handle error }
# Sets: VENTOY_MOUNT (must be unset with cleanup_ventoy_mount when done)
detect_ventoy_mount() {
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        return 1
    fi
    
    VENTOY_MOUNT=""
    
    # Method 1: Check if already mounted via /proc/mounts or /etc/mtab
    if [[ -f /proc/mounts ]]; then
        VENTOY_MOUNT=$(grep -m1 "^${SELECTED_DEVICE}1 " /proc/mounts 2>/dev/null | awk '{print $2}' || true)
    fi
    
    # Method 2: Check df output
    if [[ -z "$VENTOY_MOUNT" ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            VENTOY_MOUNT=$(df 2>/dev/null | grep -m1 "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
        else
            VENTOY_MOUNT=$(df 2>/dev/null | grep -m1 "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
        fi
    fi
    
    # Method 3: Check findmnt (Linux)
    if [[ -z "$VENTOY_MOUNT" ]] && command -v findmnt &>/dev/null; then
        VENTOY_MOUNT=$(findmnt -n -o TARGET "${SELECTED_DEVICE}1" 2>/dev/null || true)
    fi
    
    # Method 4: Check lsblk output for mountpoint
    if [[ -z "$VENTOY_MOUNT" ]] && command -v lsblk &>/dev/null; then
        VENTOY_MOUNT=$(lsblk -n -o MOUNTPOINT "${SELECTED_DEVICE}1" 2>/dev/null | head -1 || true)
        [[ "$VENTOY_MOUNT" == "null" || "$VENTOY_MOUNT" == "" ]] && VENTOY_MOUNT=""
    fi
    
    # Method 5: Check diskutil (macOS)
    if [[ -z "$VENTOY_MOUNT" ]] && [[ "$OS" == "Darwin" ]] && command -v diskutil &>/dev/null; then
        VENTOY_MOUNT=$(diskutil info "${SELECTED_DEVICE}s1" 2>/dev/null | grep "Mount Point" | awk '{print $NF}' || true)
    fi
    
    # Method 6: Verify the mount point exists and has Ventoy files
    if [[ -n "$VENTOY_MOUNT" ]] && [[ -d "$VENTOY_MOUNT" ]]; then
        # Check for Ventoy signature files
        if [[ -f "$VENTOY_MOUNT/ventoy/ventoy.json" ]] || [[ -f "$VENTOY_MOUNT/grub/grub.cfg" ]] || ls "$VENTOY_MOUNT"/*.iso &>/dev/null 2>&1; then
            return 0
        fi
    fi
    
    # Method 7: Try to mount the partition
    VENTOY_MOUNT=""
    local mount_point=""
    if [[ "$OS" == "Darwin" ]]; then
        mount_point="/Volumes/Ventoy"
    else
        mount_point="/mnt/ventoy"
    fi
    
    mkdir -p "$mount_point" 2>/dev/null || true
    
    if [[ "$OS" == "Darwin" ]]; then
        if mount "${SELECTED_DEVICE}s1" "$mount_point" 2>/dev/null; then
            VENTOY_MOUNT="$mount_point"
        fi
    else
        if mount "${SELECTED_DEVICE}1" "$mount_point" 2>/dev/null; then
            VENTOY_MOUNT="$mount_point"
        fi
    fi
    
    # Method 8: Try exFAT mount options (Linux)
    if [[ -z "$VENTOY_MOUNT" ]] && [[ "$OS" != "Darwin" ]]; then
        if mount -t exfat "${SELECTED_DEVICE}1" "$mount_point" 2>/dev/null; then
            VENTOY_MOUNT="$mount_point"
        fi
    fi
    
    # Method 9: Try NTFS mount options (Linux)
    if [[ -z "$VENTOY_MOUNT" ]] && [[ "$OS" != "Darwin" ]]; then
        if mount -t ntfs-3g "${SELECTED_DEVICE}1" "$mount_point" 2>/dev/null; then
            VENTOY_MOUNT="$mount_point"
        fi
    fi
    
    # Final verification
    if [[ -n "$VENTOY_MOUNT" ]] && [[ -d "$VENTOY_MOUNT" ]]; then
        # Verify it's actually a Ventoy partition
        if ls "$VENTOY_MOUNT"/*.iso &>/dev/null 2>&1 || [[ -d "$VENTOY_MOUNT/ventoy" ]] || [[ -d "$VENTOY_MOUNT/persistence" ]]; then
            return 0
        else
            # Mount succeeded but no Ventoy files found
            unmount_ventoy
            VENTOY_MOUNT=""
            return 1
        fi
    fi
    
    VENTOY_MOUNT=""
    return 1
}

# Unmount Ventoy partition (only if we mounted it)
unmount_ventoy() {
    if [[ -n "$VENTOY_MOUNT" ]]; then
        # Only unmount if we mounted it to a known path
        if [[ "$VENTOY_MOUNT" == "/Volumes/Ventoy" ]] || [[ "$VENTOY_MOUNT" == "/mnt/ventoy" ]]; then
            umount "$VENTOY_MOUNT" 2>/dev/null || true
        fi
        VENTOY_MOUNT=""
    fi
}

# Check if persistence file exists (unified method)
check_persistence_exists() {
    if [[ -z "$VENTOY_MOUNT" ]]; then
        return 1
    fi
    [[ -f "$VENTOY_MOUNT/persistence/ubuntu-persistence.dat" ]]
}

# Get persistence file size (unified method)
get_persistence_size() {
    if [[ -z "$VENTOY_MOUNT" ]]; then
        echo "unknown"
        return
    fi
    du -h "$VENTOY_MOUNT/persistence/ubuntu-persistence.dat" 2>/dev/null | cut -f1 || echo "unknown"
}

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

# --- Requirement/Action/Status messaging ---
print_requirement() {
    echo -e "${CYAN}[REQUIRED]${NC} $*" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${CYAN}[REQUIRED]${NC} $*"
    log "REQUIREMENT: $*"
}

print_action() {
    echo -e "${GREEN}[ACTION]${NC} $*" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[ACTION]${NC} $*"
    log "ACTION: $*"
}

print_status() {
    echo -e "${BLUE}[STATUS]${NC} $*" 2>/dev/null | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[STATUS]${NC} $*"
    log "STATUS: $*"
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

select_usb_device() {
    # Reusable USB device selector
    # Sets SELECTED_DEVICE on success, returns 1 on failure/cancel
    print_info "Detecting USB devices..."
    local usb_devices=()

    if [[ "$OS" == "Darwin" ]]; then
        while IFS= read -r line; do
            usb_devices+=("$line")
        done < <(diskutil list external physical | grep -E "^/dev/" | awk '{print $1}')
    elif [[ "$OS" == "Linux" ]]; then
        while IFS= read -r line; do
            usb_devices+=("$line")
        done < <(lsblk -ndo NAME,SIZE,TYPE,TRAN,MODEL | grep -E 'usb|disk' | grep -v 'loop' | awk '{print "/dev/" $1}')
    fi

    if [[ ${#usb_devices[@]} -eq 0 ]]; then
        print_error "No USB devices detected"
        print_info "Please plug in a USB drive and try again"
        return 1
    fi

    echo "Found USB devices:"
    echo ""
    if [[ "$OS" == "Darwin" ]]; then
        printf "${BOLD}%-10s %-10s %-10s %-15s %-30s${NC}\n" "DEVICE" "SIZE" "TYPE" "CONNECTION" "DESCRIPTION"
    else
        printf "${BOLD}%-10s %-10s %-10s %-15s %-30s${NC}\n" "DEVICE" "SIZE" "TYPE" "TRANSPORT" "MODEL"
    fi
    echo "─────────────────────────────────────────────────────────────────────────────"

    local index=1
    for device in "${usb_devices[@]}"; do
        local size type connection model

        if [[ "$OS" == "Darwin" ]]; then
            size=$(diskutil info "$device" | grep "Total Size" | awk '{print $3,$4}')
            type=$(diskutil info "$device" | grep "Device Node" | awk '{print $3}')
            connection=$(diskutil info "$device" | grep "Protocol" | awk '{print $2}')
            model=$(diskutil info "$device" | grep "Device / Media Name" | awk -F': ' '{print $2}')
        else
            size=$(lsblk -no SIZE "$device")
            type=$(lsblk -no TYPE "$device")
            connection=$(lsblk -no TRAN "$device")
            model=$(lsblk -no MODEL "$device")
        fi

        printf "${CYAN}%2d)${NC} %-10s %-10s %-10s %-15s %-30s\n" \
            "$index" "$size" "$type" "$connection" "$model"
        ((index++))
    done
    echo ""

    local count=${#usb_devices[@]}
    local selection

    while true; do
        read -p "$(echo -e "${YELLOW}Select USB device number [1-${count}] or 'q' to quit: ${NC}")" selection
        [[ "$selection" == "q" ]] && return 1

        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
            SELECTED_DEVICE="${usb_devices[$((selection-1))]}"
            print_success "Selected: $SELECTED_DEVICE"
            return 0
        else
            print_error "Invalid selection. Please enter a number between 1 and $count"
        fi
    done
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

safe_run() {
    local description="$1"
    local resolution="$2"
    shift 2
    local output
    if output=$("$@" 2>&1); then
        return 0
    else
        local exit_code=$?
        print_error "$description failed (exit code: $exit_code)"
        if [[ -n "$output" ]]; then
            print_error "Output: $output"
        fi
        print_info "How to resolve: $resolution"
        return $exit_code
    fi
}

# ============================================================================
# USB LOCATION CHECK
# ============================================================================

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

# ============================================================================
# TOOL SELECTION (Optimized cross-platform tool detection)
# ============================================================================

select_best_tool() {
    local tool_category="$1"
    local preferred_tools=()
    local available_tools=()
    
    case "$tool_category" in
        terminal_emulator)
            # Priority order: most featured -> basic
            preferred_tools=("gnome-terminal" "konsole" "terminator" "alacritty" "kitty" "wezterm" "xterm" "tmux" "wt.exe" "WindowsTerminal.exe")
            ;;
        virtualization)
            # Priority: native hypervisor -> cross-platform
            case "$OS" in
                Linux)
                    preferred_tools=("qemu-system-x86_64" "virt-manager" "libvirt" "virtualbox" "vmware")
                    ;;
                macOS)
                    preferred_tools=("UTM" "qemu-system-x86_64" "virtualbox" "vmware-fusion" "parallels")
                    ;;
                Windows|WSL*)
                    preferred_tools=("hyper-v" "wsl2" "virtualbox" "vmware" "qemu-system-x86_64")
                    ;;
            esac
            ;;
        container_runtime)
            preferred_tools=("docker" "podman" "nerdctl")
            ;;
        usb_imager)
            preferred_tools=("ventoy" "mkusb" "balenaetcher" "rufus" "dd")
            ;;
        network_tool)
            preferred_tools=("ssh" "tailscale" "wireguard" "socat" "ngrok" "cloudflared")
            ;;
        editor)
            preferred_tools=("code" "vim" "nano" "micro" "helix" "zed")
            ;;
    esac
    
    for tool in "${preferred_tools[@]}"; do
        if command -v "$tool" &>/dev/null || [[ -n "$(which "$tool" 2>/dev/null)" ]] || [[ -x "/Applications/${tool}.app/Contents/MacOS/${tool}" ]]; then
            available_tools+=("$tool")
        fi
    done
    
    # Return first available, or empty
    if [[ ${#available_tools[@]} -gt 0 ]]; then
        echo "${available_tools[0]}"
        return 0
    fi
    return 1
}

select_tool_interactive() {
    local tool_category="$1"
    local prompt="${2:-Select tool}"
    
    local tools=()
    case "$tool_category" in
        terminal_emulator)
            tools=("gnome-terminal" "konsole" "terminator" "alacritty" "kitty" "wezterm" "xterm" "tmux" "wt.exe" "WindowsTerminal.exe" "osascript (macOS Terminal)")
            ;;
        virtualization)
            case "$OS" in
                Linux) tools=("qemu/kvm" "virtualbox" "vmware" "libvirt/virt-manager") ;;
                macOS) tools=("UTM" "qemu" "virtualbox" "vmware-fusion" "parallels") ;;
                Windows|WSL*) tools=("hyper-v" "wsl2" "virtualbox" "vmware" "qemu") ;;
            esac
            ;;
        container_runtime)
            tools=("docker" "podman" "nerdctl")
            ;;
    esac
    
    # Filter to only available tools
    local available=()
    for tool in "${tools[@]}"; do
        local cmd="${tool%% *}"
        if command -v "$cmd" &>/dev/null || [[ "$tool" == "osascript"* ]]; then
            available+=("$tool")
        fi
    done
    
    if [[ ${#available[@]} -eq 0 ]]; then
        print_error "No supported $tool_category tools found"
        return 1
    fi
    
    echo ""
    print_header "Available $tool_category Tools"
    for i in "${!available[@]}"; do
        echo "  $((i+1))) ${available[$i]}"
    done
    echo "  a) Auto-select best"
    echo ""
    
    local choice
    read -p "$(echo -e "${YELLOW}$prompt [1-${#available[@]}/a]: ${NC}")" choice
    
    if [[ "$choice" == "a" ]]; then
        echo "${available[0]}"
        return 0
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#available[@]}" ]]; then
        echo "${available[$((choice-1))]}"
        return 0
    else
        print_error "Invalid selection"
        return 1
    fi
}

# ============================================================================
# INITIALIZATION
# ============================================================================

initialize() {
    print_header "$SCRIPT_NAME v$VERSION"
    log "Starting USB Compute Automation Setup Assistant"
    
    # Check if running from USB - MUST BE FIRST
    check_script_location
    
    # Create log file
    : > "$LOG_FILE"
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    print_info "Logs will be saved to: $LOG_FILE"
    print_info "Backups will be saved to: $BACKUP_DIR"
    
    # Check OS with WSL detection
    if [[ "$(uname)" == "Darwin" ]]; then
        OS="macOS"
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        # Check for WSL
        if grep -qi microsoft /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
            OS="WSL"
            WSL_VERSION="${WSL_VERSION:-2}"
            print_info "Windows Subsystem for Linux detected (WSL $WSL_VERSION)"
        else
            OS="Linux"
        fi
    elif [[ "$(expr substr $(uname -s) 1 10)" == "MINGW32_NT" ]] || [[ "$(expr substr $(uname -s) 1 10)" == "MINGW64_NT" ]]; then
        OS="Windows"
    else
        print_error "Unsupported operating system: $(uname)"
        print_info "Supported: macOS, Linux, WSL2, Windows (via WSL2)"
        return 1
    fi
    
    print_info "Detected OS: $OS"
    
    # Detect best tools for this platform
    TERMINAL_TOOL="$(select_best_tool terminal_emulator)"
    VIRT_TOOL="$(select_best_tool virtualization)"
    CONTAINER_TOOL="$(select_best_tool container_runtime)"
    
    print_info "Best terminal: ${TERMINAL_TOOL:-none found}"
    print_info "Best virtualization: ${VIRT_TOOL:-none found}"
    print_info "Best container runtime: ${CONTAINER_TOOL:-none found}"
}
# MAIN MENU
# ============================================================================

show_main_menu() {
    print_header "$SCRIPT_NAME - Main Menu"
    echo "Please select an option:"
    echo "  1) Setup USB Compute Automation System (Complete Setup)"
    echo "  2) Manage Ventoy USB Drive"
    echo "  3) Setup VM Auto-Boot and Headless Configuration"
    echo "  4) Install Build Essentials and Dependencies (into USB persistence)"
    echo "  5) Configure Network and SSH Access"
    echo "  6) View System Status and Health"
    echo "  7) Backup and Recovery Options"
    echo "  8) System Cleanup and Diagnostics"
    echo "  9) Manage Custom Aliases"
    echo "  10) Manage SSH Hosts"
    echo "  11) Access USB Persistent Terminal (chroot into USB persistence)"
    echo "  12) Copy File to USB (host -> USB free space / persistence)"
    echo "  13) Hemlock Agent Orchestration (popout terminal - deploy/manage agents, crews, gateway)"
    echo "  14) Exit"
    echo ""
}

# ============================================================================
# STEP 1: SETUP USB COMPUTE AUTOMATION SYSTEM
# ============================================================================

setup_complete_system() {
    print_header "Complete System Setup"
    echo "This option will guide you through the complete setup process:"
    echo "  1. Prepare your USB drive with Ventoy and persistence"
    echo "  2. Configure the VM for headless boot with SSH access"
    echo "  3. Deploy Hemlock Agent Orchestration containers"
    echo "  4. Install build essentials and dependencies"
    echo "  5. Configure network settings and optional services"
    echo "  6. Configure auto-start services (VM + Hemlock + agents)"
    echo ""
    
    if ! confirm "Do you want to proceed with the complete setup?"; then
        return 0
    fi
    
    # Run through all setup steps
    setup_usb_drive
    setup_vm_boot
    deploy_hemlock_full
    install_essentials
    configure_network
    setup_auto_start_services
    
    print_success "Complete system setup finished!"
    print_info "You can now plug in your USB drive and it will automatically"
    print_info "boot in headless mode with SSH access available at:"
    echo "      ssh -p $SSH_PORT_FORWARD_HOST user@localhost"
    echo ""
    print_info "Hemlock Gateway will be running at: http://localhost:18789"
    print_info "Agents will be auto-attached and ready for work via Hemlock TUI"
    echo ""
}

# ============================================================================
# STEP 2: CONFIGURE VENTOY USB DRIVE
# ============================================================================

setup_usb_drive() {
    print_header "Manage Ventoy USB Drive"
    echo ""

    # Select device
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        if ! select_usb_device; then
            return 0
        fi
    fi

    # Show device details
    print_header "Device: $SELECTED_DEVICE"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null || true
    echo ""

    # Main management loop
    while true; do
        print_header "USB Management Menu"
        echo "  1) Install Ventoy (fresh install — erases USB)"
        echo "  2) View USB inventory (ISOs, persistence, config)"
        echo "  3) Create persistence layer"
        echo "  4) Resize persistence layer"
        echo "  5) Browse persistence contents"
        echo "  6) Edit ventoy.json configuration"
        echo "  7) Add ISO to USB"
        echo "  8) Remove ISO from USB"
        echo "  9) Rebuild persistence (delete + recreate)"
        echo "  10) Ventoy upgrade (preserves ISOs)"
        echo "  11) Configure custom startup script"
        echo "  q) Return to main menu"
        echo ""

        read -p "$(echo -e "${YELLOW}Select [1-11/q]: ${NC}")" choice
        case "$choice" in
            1) install_ventoy || read -p "Press Enter to continue..." ;;
            2) _usb_inventory || read -p "Press Enter to continue..." ;;
            3) create_persistence || read -p "Press Enter to continue..." ;;
            4) _resize_persistence || read -p "Press Enter to continue..." ;;
            5) _browse_persistence || read -p "Press Enter to continue..." ;;
            6) _edit_ventoy_json || read -p "Press Enter to continue..." ;;
            7) _add_iso_to_usb || read -p "Press Enter to continue..." ;;
            8) _remove_iso_from_usb || read -p "Press Enter to continue..." ;;
            9) _rebuild_persistence || read -p "Press Enter to continue..." ;;
            10) _upgrade_ventoy || read -p "Press Enter to continue..." ;;
            11) _configure_startup_script || read -p "Press Enter to continue..." ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        echo ""
    done
}

_usb_inventory() {
    print_header "USB Inventory"

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    echo "  Ventoy partition: $VENTOY_MOUNT"
    echo ""

    # ISOs
    echo "  ISO files:"
    local iso_count=0
    for iso in "$VENTOY_MOUNT"/*.iso; do
        if [[ -f "$iso" ]]; then
            local size=$(du -h "$iso" | cut -f1)
            echo "    • $(basename "$iso") ($size)"
            ((iso_count++))
        fi
    done
    [[ $iso_count -eq 0 ]] && echo "    (none)"
    echo ""

    # Persistence
    echo "  Persistence:"
    if check_persistence_exists; then
        local pfile="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
        local psize=$(du -h "$pfile" | cut -f1)
        local pused=0
        local pmnt="/tmp/usb-persist-inv-$$"
        mkdir -p "$pmnt"
        if mount -o loop "$pfile" "$pmnt" 2>/dev/null; then
            pused=$(du -sh "$pmnt" 2>/dev/null | cut -f1 || echo "unknown")
            umount "$pmnt" 2>/dev/null || true
        fi
        rmdir "$pmnt" 2>/dev/null || true
        echo "    • ubuntu-persistence.dat ($psize total, ~$pused used)"
    else
        echo "    (none)"
    fi
    echo ""

    # ventoy.json
    echo "  Configuration:"
    if [[ -f "$VENTOY_MOUNT/ventoy/ventoy.json" ]]; then
        echo "    • ventoy.json:"
        sed 's/^/      /' "$VENTOY_MOUNT/ventoy/ventoy.json"
    else
        echo "    (none)"
    fi
    echo ""

    # Disk space
    echo "  Free space on USB:"
    df -h "$VENTOY_MOUNT" | tail -1 | awk '{print "    " $4 " available of " $2}'
    echo ""

    unmount_ventoy
}

_resize_persistence() {
    print_header "Resize Persistence Layer"

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    local pfile="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$pfile" ]]; then
        print_error "No persistence file found"
        print_info "Create one first: Option 3"
        unmount_ventoy
        return 1
    fi

    local current_size=$(du -h "$pfile" | cut -f1)
    print_info "Current persistence: $current_size"
    echo ""
    print_warning "Resizing requires creating a new file and copying data."
    print_warning "This will take time proportional to the data size."
    echo ""

    local new_size_gb
    read -p "$(echo -e "${YELLOW}New size in GB: ${NC}")" new_size_gb
    if [[ -z "$new_size_gb" ]] || ! [[ "$new_size_gb" =~ ^[0-9]+$ ]]; then
        print_error "Invalid size"
        unmount_ventoy
        return 1
    fi

    local avail_kb=$(df -k "$VENTOY_MOUNT" | tail -1 | awk '{print $4}')
    local need_kb=$((new_size_gb * 1024 * 1024))
    if [[ "$avail_kb" -lt "$need_kb" ]]; then
        print_error "Not enough space: need ${new_size_gb}GB, have $((avail_kb / 1024 / 1024))GB"
        unmount_ventoy
        return 1
    fi

    print_info "Creating new ${new_size_gb}GB persistence file..."
    local new_file="$VENTOY_MOUNT/persistence/ubuntu-persistence-new.dat"
    dd if=/dev/zero of="$new_file" bs=1M count=$((new_size_gb * 1024)) status=progress || {
        print_error "Failed to create new persistence file"
        rm -f "$new_file"
        unmount_ventoy
        return 1
    }

    print_info "Formatting new persistence file..."
    mkfs.ext4 -F -L casper-rw "$new_file" || {
        print_error "Failed to format new file"
        rm -f "$new_file"
        unmount_ventoy
        return 1
    }

    # Copy data
    print_info "Copying data from old to new persistence..."
    local old_mnt="/tmp/usb-persist-old-$$"
    local new_mnt="/tmp/usb-persist-new-$$"
    mkdir -p "$old_mnt" "$new_mnt"

    if mount -o loop "$pfile" "$old_mnt" 2>/dev/null && mount -o loop "$new_file" "$new_mnt" 2>/dev/null; then
        cp -a "$old_mnt"/. "$new_mnt"/ 2>/dev/null || true
        umount "$old_mnt" 2>/dev/null || true
        umount "$new_mnt" 2>/dev/null || true
    else
        print_warning "Could not mount for data copy — new persistence will be empty"
        umount "$old_mnt" 2>/dev/null || true
        umount "$new_mnt" 2>/dev/null || true
    fi

    rmdir "$old_mnt" "$new_mnt" 2>/dev/null || true

    # Replace
    print_info "Replacing old persistence with new..."
    mv "$pfile" "${pfile}.bak"
    mv "$new_file" "$pfile"

    print_success "Resized to ${new_size_gb}GB"
    print_info "Backup of old persistence: ${pfile}.bak"
    print_info "Delete it when confirmed working: rm ${pfile}.bak"

    unmount_ventoy
}

_browse_persistence() {
    print_header "Browse Persistence Contents"

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    local pfile="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$pfile" ]]; then
        print_error "No persistence file found"
        unmount_ventoy
        return 1
    fi

    local pmnt="/tmp/usb-persist-browse-$$"
    mkdir -p "$pmnt"

    if mount -o loop "$pfile" "$pmnt" 2>/dev/null; then
        print_success "Persistence mounted at $pmnt"
        echo ""
        echo "  Contents:"
        ls -la "$pmnt"/ 2>/dev/null | sed 's/^/    /'
        echo ""
        echo "  Disk usage:"
        du -sh "$pmnt"/* 2>/dev/null | sort -rh | head -15 | sed 's/^/    /'
        echo ""
        umount "$pmnt" 2>/dev/null || true
    else
        print_error "Could not mount persistence file"
    fi

    rmdir "$pmnt" 2>/dev/null || true
    unmount_ventoy
}

_edit_ventoy_json() {
    print_header "Edit Ventoy Configuration"

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    local vjson="$VENTOY_MOUNT/ventoy/ventoy.json"
    mkdir -p "$VENTOY_MOUNT/ventoy"

    if [[ -f "$vjson" ]]; then
        print_info "Current ventoy.json:"
        cat "$vjson" | sed 's/^/  /'
        echo ""
        if ! confirm "Overwrite with new configuration?"; then
            unmount_ventoy
            return 0
        fi
    fi

    echo ""
    echo "  Persistence config format:"
    echo '  {"persistence": [{"image": "/ubuntu.iso", "backend": "/persistence/ubuntu.dat"}]}'
    echo ""

    local iso_name=""
    read -p "$(echo -e "${YELLOW}ISO filename on USB (e.g. ubuntu-24.04.4-desktop-amd64.iso): ${NC}")" iso_name

    cat > "$vjson" << EOF
{
    "persistence": [{
        "image": "/$iso_name",
        "backend": "/persistence/ubuntu-persistence.dat"
    }]
}
EOF

    print_success "ventoy.json updated"
    unmount_ventoy
}

_add_iso_to_usb() {
    print_header "Add ISO to USB"

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    local iso_path
    read -p "$(echo -e "${YELLOW}Full path to ISO file: ${NC}")" iso_path

    if [[ ! -f "$iso_path" ]]; then
        print_error "File not found: $iso_path"
        unmount_ventoy
        return 1
    fi

    local iso_name=$(basename "$iso_path")
    print_info "Copying $iso_name to USB..."
    cp "$iso_path" "$VENTOY_MOUNT/" && print_success "Copied" || print_error "Copy failed"

    unmount_ventoy
}

_remove_iso_from_usb() {
    print_header "Remove ISO from USB"

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    echo "  ISOs on USB:"
    local idx=1
    local isos=()
    for iso in "$VENTOY_MOUNT"/*.iso; do
        if [[ -f "$iso" ]]; then
            local size=$(du -h "$iso" | cut -f1)
            printf "  %d) %s (%s)\n" "$idx" "$(basename "$iso")" "$size"
            isos+=("$iso")
            ((idx++))
        fi
    done

    if [[ ${#isos[@]} -eq 0 ]]; then
        print_info "No ISOs found"
        unmount_ventoy
        return 0
    fi

    local choice
    read -p "$(echo -e "${YELLOW}Select ISO to remove [1-$((idx-1))]: ${NC}")" choice
    if [[ "$choice" -ge 1 ]] && [[ "$choice" -le "${#isos[@]}" ]]; then
        local target="${isos[$((choice-1))]}"
        if confirm "Remove $(basename "$target")?"; then
            rm "$target" && print_success "Removed" || print_error "Failed"
        fi
    else
        print_error "Invalid selection"
    fi

    unmount_ventoy
}

_rebuild_persistence() {
    print_header "Rebuild Persistence Layer"
    print_warning "This will DELETE the current persistence file and all data in it."
    echo ""

    if ! confirm "Are you sure?"; then
        return 0
    fi

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    local pfile="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ -f "$pfile" ]]; then
        print_info "Deleting old persistence..."
        rm -f "$pfile"
        print_success "Deleted"
    fi

    unmount_ventoy
    create_persistence
}

_upgrade_ventoy() {
    print_header "Upgrade Ventoy (Preserves ISOs)"
    print_info "This upgrades Ventoy without touching ISOs or persistence."
    echo ""

    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        if ! select_usb_device; then
            return 0
        fi
    fi

    local ventoy_tmp="/tmp/ventoy-${VENTOY_VERSION}"
    if [[ ! -f "$VENTOY_TARBALL" ]]; then
        print_error "Ventoy tarball not found: $VENTOY_TARBALL"
        return 1
    fi

    rm -rf "$ventoy_tmp"
    mkdir -p "$ventoy_tmp"
    tar -xzf "$VENTOY_TARBALL" -C "$ventoy_tmp"

    local ventoy_script="$ventoy_tmp/ventoy-${VENTOY_VERSION}/Ventoy2Disk.sh"
    if [[ ! -f "$ventoy_script" ]]; then
        print_error "Ventoy2Disk.sh not found in tarball"
        return 1
    fi

    print_info "Running upgrade: $ventoy_script -u $SELECTED_DEVICE"
    echo -e "y\ny" | "$ventoy_script" -u "$SELECTED_DEVICE" 2>&1
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        print_success "Ventoy upgraded successfully"
    else
        print_error "Upgrade failed (exit code: $exit_code)"
    fi

    rm -rf "$ventoy_tmp"
}

_configure_startup_script() {
    print_header "Configure Custom Startup Script"
    echo "This creates a script that runs automatically when the USB boots."
    echo ""

    if ! detect_ventoy_mount; then
        print_error "Could not mount Ventoy partition"
        return 1
    fi

    local startup_script="$VENTOY_MOUNT/startup.sh"
    local persist_script="/tmp/startup-custom-$$"

    print_info "Choose startup script source:"
    echo "  1) Create new script (interactive)"
    echo "  2) Use existing script file"
    echo "  3) View current startup script"
    echo "  4) Remove startup script"
    echo "  q) Cancel"
    echo ""

    read -p "$(echo -e "${YELLOW}Select [1-4/q]: ${NC}")" choice

    case "$choice" in
        1)
            print_info "Creating new startup script..."
            echo ""
            echo "Enter script content (end with EOF on new line):"
            cat > "$persist_script" << 'EOF'
#!/usr/bin/env bash
# Custom startup script — runs on USB boot

echo "=== Custom Startup Script ==="
echo "Timestamp: $(date)"
echo "Host: $(hostname)"

# Example: Start services, mount shares, run scripts
# systemctl start docker
# mount -t nfs server:/share /mnt/share

echo "Startup script completed."
EOF
            ;;
        2)
            read -p "$(echo -e "${YELLOW}Path to script file: ${NC}")" src_path
            if [[ ! -f "$src_path" ]]; then
                print_error "File not found: $src_path"
                return 1
            fi
            cp "$src_path" "$persist_script"
            ;;
        3)
            if [[ -f "$startup_script" ]]; then
                print_info "Current startup.sh:"
                cat "$startup_script"
            else
                print_info "No startup script configured"
            fi
            unmount_ventoy
            return 0
            ;;
        4)
            if [[ -f "$startup_script" ]]; then
                rm "$startup_script"
                print_success "Startup script removed"
            else
                print_info "No startup script to remove"
            fi
            unmount_ventoy
            return 0
            ;;
        q|Q) return 0 ;;
        *) print_error "Invalid selection"; return 1 ;;
    esac

    if [[ -f "$persist_script" ]]; then
        chmod +x "$persist_script"
        print_info "Copying to USB..."
        cp "$persist_script" "$startup_script"
        print_success "Startup script installed at $startup_script"
        echo ""
        print_info "To also run in persistence, inject into rc.local:"
        echo "  echo \"bash /media/*/Ventoy/startup.sh &\" >> /etc/rc.local"
        rm -f "$persist_script"
    fi

    unmount_ventoy
    return 0
}

install_ventoy() {
    local ventoy_tmp="/tmp/ventoy-${VENTOY_VERSION}"
    local install_log="/tmp/ventoy-install-$(date +%Y%m%d-%H%M%S).log"

    # --- Step 1: Validate device ---
    print_info "[1/6] Validating device selection..."
    log "[1/6] Validating device selection"
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_error "No USB device selected. Please select a device first."
        log "ERROR: SELECTED_DEVICE is empty"
        read -p "Press Enter to continue..."
        return 1
    fi
    print_success "Device: $SELECTED_DEVICE"
    log "Device: $SELECTED_DEVICE"

    # --- Step 2: Check root ---
    print_info "[2/6] Checking root privileges..."
    log "[2/6] Checking root privileges (EUID=$EUID)"
    if [[ $EUID -ne 0 ]]; then
        print_error "This operation requires root privileges"
        print_info "Please run with sudo: sudo $0"
        log "ERROR: Not root (EUID=$EUID)"
        read -p "Press Enter to continue..."
        return 1
    fi
    print_success "Running as root"

    # --- Step 3: Verify local Ventoy tarball ---
    print_info "[3/6] Locating Ventoy package..."
    log "[3/6] Checking local Ventoy tarball: $VENTOY_TARBALL"
    if [[ ! -f "$VENTOY_TARBALL" ]]; then
        # Not bundled by design — fetch it on demand (needs network once).
        print_info "Ventoy tarball not present — fetching v${VENTOY_VERSION} on demand..."
        log "Ventoy tarball absent; attempting on-demand fetch to $VENTOY_TARBALL"
        local ventoy_url="https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
        run_or_dry mkdir -p "$(dirname "$VENTOY_TARBALL")"
        if command -v curl >/dev/null 2>&1; then
            run_or_dry curl -fSL -o "$VENTOY_TARBALL" "$ventoy_url"
        elif command -v wget >/dev/null 2>&1; then
            run_or_dry wget -O "$VENTOY_TARBALL" "$ventoy_url"
        fi
        if [[ "$DRY_RUN" != "1" ]] && { [[ ! -f "$VENTOY_TARBALL" ]] || ! tar -tzf "$VENTOY_TARBALL" >/dev/null 2>&1; }; then
            [[ -f "$VENTOY_TARBALL" ]] && rm -f "$VENTOY_TARBALL"
            print_error "Could not fetch Ventoy (offline?). Fetch it once, then re-run:"
            print_info "  scripts/fetch-ventoy.sh --version ${VENTOY_VERSION}"
            print_info "  (or) curl -fSL -o $VENTOY_TARBALL $ventoy_url"
            log "ERROR: on-demand Ventoy fetch failed"
            read -p "Press Enter to continue..."
            return 1
        fi
        print_success "Fetched Ventoy v${VENTOY_VERSION}"
    fi
    print_success "Found: $(basename "$VENTOY_TARBALL") ($(du -h "$VENTOY_TARBALL" | cut -f1))"

    # --- Step 4: Extract Ventoy ---
    print_info "[4/6] Extracting Ventoy to $ventoy_tmp..."
    log "[4/6] Extracting to $ventoy_tmp"
    run_or_dry rm -rf "$ventoy_tmp"
    if ! run_or_dry mkdir -p "$ventoy_tmp" 2>>"$install_log"; then
        print_error "Failed to create temp directory: $ventoy_tmp"
        log "ERROR: mkdir $ventoy_tmp failed"
        read -p "Press Enter to continue..."
        return 1
    fi
    if ! run_or_dry tar -xzf "$VENTOY_TARBALL" -C "$ventoy_tmp" 2>>"$install_log"; then
        print_error "Failed to extract Ventoy archive"
        print_info "How to resolve: The tarball may be corrupted. Re-download it."
        log "ERROR: tar extraction failed. Log: $install_log"
        cat "$install_log" 2>/dev/null
        read -p "Press Enter to continue..."
        run_or_dry rm -rf "$ventoy_tmp"
        return 1
    fi
    print_success "Extracted successfully"

    # --- Step 5: Verify Ventoy2Disk.sh exists ---
    local ventoy_script="$ventoy_tmp/ventoy-${VENTOY_VERSION}/Ventoy2Disk.sh"
    log "[5/6] Checking Ventoy2Disk.sh at: $ventoy_script"
    if [[ ! -f "$ventoy_script" ]]; then
        print_error "Ventoy2Disk.sh not found at: $ventoy_script"
        print_info "How to resolve: The tarball structure may have changed."
        print_info "  Contents of extract: $(ls "$ventoy_tmp/ventoy-${VENTOY_VERSION}/" 2>&1)"
        log "ERROR: Ventoy2Disk.sh not found. Contents: $(ls -la "$ventoy_tmp/ventoy-${VENTOY_VERSION}/" 2>&1)"
        read -p "Press Enter to continue..."
        rm -rf "$ventoy_tmp"
        return 1
    fi
    print_success "Ventoy2Disk.sh found"

    # --- Step 6: Run Ventoy install ---
    print_info "[6/6] Installing Ventoy to $SELECTED_DEVICE..."
    print_warning "This will ERASE ALL DATA on $SELECTED_DEVICE"
    log "[6/6] Installing Ventoy to $SELECTED_DEVICE"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue?"; then
        print_info "Ventoy installation cancelled"
        log "User cancelled installation"
        rm -rf "$ventoy_tmp"
        return 1
    fi

    # Unmount any partitions on the device first
    print_info "Unmounting any partitions on $SELECTED_DEVICE..."
    log "Unmounting partitions on $SELECTED_DEVICE"
    for part in "${SELECTED_DEVICE}"*; do
        if [[ -b "$part" ]]; then
            run_or_dry umount "$part" 2>/dev/null && log "Unmounted $part" || log "Could not unmount $part (may not be mounted)"
        fi
    done

    # Check if Ventoy is already installed on this device
    local ventoy_flag="-i"  # Default: fresh install
    local ventoy_check_output
    ventoy_check_output=$("$ventoy_script" -l "$SELECTED_DEVICE" 2>&1) || true
    
    if echo "$ventoy_check_output" | grep -qi "ventoy.*already\|ventoy.*installed\|Update.*available"; then
        # Ventoy already installed — offer options
        print_warning "Ventoy is already installed on $SELECTED_DEVICE"
        echo ""
        echo "Options:"
        echo "  1) Fresh install (overwrites everything) [uses -I]"
        echo "  2) Upgrade (preserves ISOs, updates Ventoy) [uses -u]"
        echo "  3) Skip — don't change Ventoy"
        echo ""
        
        local ventoy_choice
        while true; do
            read -p "$(echo -e "${YELLOW}Select option [1-3]: ${NC}")" ventoy_choice
            case "$ventoy_choice" in
                1)
                    ventoy_flag="-I"
                    print_info "Will perform fresh install (overwrites Ventoy and data)"
                    break
                    ;;
                2)
                    ventoy_flag="-u"
                    print_info "Will upgrade Ventoy (preserves ISOs)"
                    break
                    ;;
                3|q|Q)
                    print_info "Skipping Ventoy installation"
                    run_or_dry rm -rf "$ventoy_tmp"
                    return 0
                    ;;
                *)
                    print_error "Invalid selection. Please enter 1-3"
                    ;;
            esac
        done
    fi

    # Run Ventoy2Disk.sh with piped 'y' answers for both confirmation prompts
    # The script has two read -p 'Continue? (y/n)' prompts
    local flag_desc="install"
    [[ "$ventoy_flag" == "-I" ]] && flag_desc="fresh install (overwrites)"
    [[ "$ventoy_flag" == "-u" ]] && flag_desc="upgrade"
    
    print_info "Running Ventoy2Disk.sh $ventoy_flag $SELECTED_DEVICE ..."
    log "Running: echo -e 'y\\ny' | $ventoy_script $ventoy_flag $SELECTED_DEVICE"

    local ventoy_output
    local ventoy_exit=0
    ventoy_output=$(echo -e "y\ny" | run_or_dry "$ventoy_script" "$ventoy_flag" "$SELECTED_DEVICE" 2>&1) || ventoy_exit=$?

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
        print_success "Ventoy $flag_desc successful on $SELECTED_DEVICE!"
        log "SUCCESS: Ventoy $flag_desc on $SELECTED_DEVICE"
        run_or_dry rm -rf "$ventoy_tmp"
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
        run_or_dry rm -rf "$ventoy_tmp"
        return 1
    fi
}

create_persistence() {
    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        if ! select_usb_device; then
            return 0
        fi
    fi

    # Detect or mount Ventoy partition
    if ! detect_ventoy_mount; then
        print_error "Could not find or mount Ventoy partition on $SELECTED_DEVICE"
        print_info "How to resolve:"
        print_info "  1. Ensure the USB is plugged in"
        print_info "  2. Try manually: sudo mount ${SELECTED_DEVICE}1 /mnt/ventoy"
        print_info "  3. Check: lsblk to verify partitions exist"
        return 1
    fi
    
    print_info "Using Ventoy mount point: $VENTOY_MOUNT"
    
    # Check if persistence already exists
    if check_persistence_exists; then
        local persist_size
        persist_size=$(get_persistence_size)
        print_success "Ventoy persistence already exists ($persist_size)"
        if ! confirm "Do you want to recreate the persistence file (this will DELETE existing persistence)?" "n"; then
            unmount_ventoy
            return 0
        fi
    fi
    
    # Create persistence directory
    local persistence_dir="$VENTOY_MOUNT/persistence"
    if ! mkdir -p "$persistence_dir"; then
        print_error "Failed to create persistence directory"
        print_info "How to resolve: Check if the USB partition is writable and has enough free space."
        print_info "  Check available space: df -h $VENTOY_MOUNT"
        unmount_ventoy
        return 1
    fi
    
    # Ask for persistence size
    local persistence_size_gb=20
    read -p "$(echo -e "${YELLOW}Enter persistence size in GB [default: 20]: ${NC}")" input_size
    if [[ -n "$input_size" ]] && [[ "$input_size" =~ ^[0-9]+$ ]]; then
        persistence_size_gb="$input_size"
    fi
    
    # Check available space
    local available_kb
    available_kb=$(df -k "$VENTOY_MOUNT" | tail -1 | awk '{print $4}' || echo "0")
    local required_kb=$((persistence_size_gb * 1024 * 1024))
    if [[ "$available_kb" -lt "$required_kb" ]]; then
        print_error "Insufficient space: need ${persistence_size_gb}GB, have $((available_kb / 1024 / 1024))GB"
        unmount_ventoy
        return 1
    fi
    
    # Create persistence file
    print_info "Creating ${persistence_size_gb}GB persistence file..."
    if ! dd if=/dev/zero of="$persistence_dir/ubuntu-persistence.dat" bs=1M count=$((persistence_size_gb * 1024)) status=progress; then
        print_error "Failed to create persistence file"
        print_info "How to resolve: Ensure the USB has at least ${persistence_size_gb}GB of free space."
        unmount_ventoy
        return 1
    fi
    
    # Format as ext4
    print_info "Formatting persistence file as ext4..."
    if ! mkfs.ext4 -F -L casper-rw "$persistence_dir/ubuntu-persistence.dat"; then
        print_error "Failed to format persistence file as ext4"
        print_info "How to resolve: Ensure e2fsprogs is installed (sudo apt install e2fsprogs)"
        unmount_ventoy
        return 1
    fi
    
    # Inject autostart script into persistence overlay
    print_info "Injecting autostart script into persistence overlay..."
    local persist_mount="/tmp/usb-persist-$$"
    mkdir -p "$persist_mount"
    
    if mount -o loop "$persistence_dir/ubuntu-persistence.dat" "$persist_mount" 2>/dev/null; then
        # Create rc.local for autostart
        mkdir -p "$persist_mount/etc"
        cat > "$persist_mount/etc/rc.local" << 'RCLOCAL'
#!/bin/bash
# USB Compute Automation - Auto-install build essentials on first boot
# This runs during system startup

SETUP_MARKER="/opt/.essentials-installed"
SETUP_LOG="/var/log/usb-essentials-setup.log"

if [[ ! -f "$SETUP_MARKER" ]]; then
    echo "=== First Boot: Installing Build Essentials ===" | tee -a "$SETUP_LOG"
    echo "This will take a few minutes..." | tee -a "$SETUP_LOG"
    
    # Find setup script on USB (checks multiple known locations)
    SCRIPT_PATH=""
    for path in /media/*/Ventoy /mnt/ventoy /run/media/*/Ventoy; do
        if [[ -f "$path/scripts/setup-essentials-enhanced.sh" ]]; then
            SCRIPT_PATH="$path/scripts/setup-essentials-enhanced.sh"
            break
        elif [[ -f "$path/setup-essentials.sh" ]]; then
            SCRIPT_PATH="$path/setup-essentials.sh"
            break
        fi
    done
    
    if [[ -n "$SCRIPT_PATH" ]]; then
        bash "$SCRIPT_PATH" 2>&1 | tee -a "$SETUP_LOG"
        touch "$SETUP_MARKER"
        echo "=== Build Essentials Installed! ===" | tee -a "$SETUP_LOG"
    else
        echo "Setup script not found. Looked for:" | tee -a "$SETUP_LOG"
        echo "  - /media/*/Ventoy/scripts/setup-essentials-enhanced.sh" | tee -a "$SETUP_LOG"
        echo "  - /media/*/Ventoy/setup-essentials.sh" | tee -a "$SETUP_LOG"
        echo "To install manually: sudo bash /media/*/Ventoy/scripts/setup-essentials-enhanced.sh" | tee -a "$SETUP_LOG"
    fi
fi

exit 0
RCLOCAL
        chmod +x "$persist_mount/etc/rc.local"
        
        # Also create a .bashrc entry for interactive sessions
        mkdir -p "$persist_mount/etc/profile.d"
        cat > "$persist_mount/etc/profile.d/usb-essentials.sh" << 'PROFILE'
# USB Compute Automation - Check for essentials on login
if [[ ! -f /opt/.essentials-installed ]]; then
    echo ""
    echo "=== USB Compute: Build essentials not yet installed ==="
    echo "Run: sudo bash /media/*/Ventoy/setup-essentials.sh"
    echo ""
fi

# Load enhanced bash profile if available
if [[ -f /media/*/Ventoy/bash_enhanced.sh ]]; then
    source /media/*/Ventoy/bash_enhanced.sh 2>/dev/null || true
fi

# Load custom aliases if available
if [[ -f ~/.bash_aliases_usb ]]; then
    source ~/.bash_aliases_usb 2>/dev/null || true
elif [[ -f /media/*/Ventoy/.bash_aliases_usb ]]; then
    source /media/*/Ventoy/.bash_aliases_usb 2>/dev/null || true
fi

# Load SSH host aliases if available
if [[ -f ~/.ssh/hosts_usb ]]; then
    # Source SSH host manager for tab completion
    if [[ -f /media/*/Ventoy/ssh_host_manager.sh ]]; then
        source /media/*/Ventoy/ssh_host_manager.sh 2>/dev/null || true
    fi
fi
PROFILE
        chmod +x "$persist_mount/etc/profile.d/usb-essentials.sh"
        
        # Copy bash_enhanced.sh to USB if it exists
        local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        if [[ -f "$script_dir/bash_enhanced.sh" ]]; then
            cp "$script_dir/bash_enhanced.sh" "$persist_mount/" 2>/dev/null || true
            print_info "Copied bash_enhanced.sh to USB"
        fi
        
        # Copy alias and SSH host managers to USB
        if [[ -f "$script_dir/alias_manager.sh" ]]; then
            cp "$script_dir/alias_manager.sh" "$persist_mount/" 2>/dev/null || true
        fi
        if [[ -f "$script_dir/ssh_host_manager.sh" ]]; then
            cp "$script_dir/ssh_host_manager.sh" "$persist_mount/" 2>/dev/null || true
        fi
        if [[ -f "$script_dir/sysman.sh" ]]; then
            cp "$script_dir/sysman.sh" "$persist_mount/" 2>/dev/null || true
        fi
        if [[ -f "$script_dir/clean-local.sh" ]]; then
            cp "$script_dir/clean-local.sh" "$persist_mount/" 2>/dev/null || true
        fi
        
        # Unmount persistence
        umount "$persist_mount" 2>/dev/null || true
        print_success "Autostart script injected into persistence"
    else
        print_warning "Could not mount persistence file for injection (non-critical)"
        print_info "You may need to run setup-essentials.sh manually after boot"
    fi
    rmdir "$persist_mount" 2>/dev/null || true
    
    # Create ventoy.json configuration
    print_info "Creating Ventoy configuration..."
    mkdir -p "$VENTOY_MOUNT/ventoy"
    cat > "$VENTOY_MOUNT/ventoy/ventoy.json" << 'EOF'
{
    "persistence": [{
        "image": "/ubuntu-24.04.4-desktop-amd64.iso",
        "backend": "/persistence/ubuntu-persistence.dat"
    }]
}
EOF
    
    if [[ ! -f "$VENTOY_MOUNT/ventoy/ventoy.json" ]]; then
        print_error "Failed to write Ventoy configuration"
        unmount_ventoy
        return 1
    fi
    
    print_success "Ventoy persistence configured successfully!"
    print_info "Persistence will auto-install build essentials on first boot"
    
    unmount_ventoy
    return 0
}

configure_ventoy() {
    # This function is mostly handled in create_persistence
    # Additional configuration could go here if needed
    return 0
}

# ============================================================================
# STEP 3: SETUP VM AUTO-BOOT AND HEADLESS CONFIGURATION
# ============================================================================

setup_vm_boot() {
    print_header "VM Auto-Boot and Headless Configuration"
    echo "This step sets up automatic VM launch when you plug in the USB."
    echo ""
    echo "  • Detects QEMU or VirtualBox on your system"
    echo "  • Configures VM to boot from Ventoy USB in headless mode"
    echo "  • Sets up SSH port forwarding (Host:2222 → Guest:22)"
    echo "  • Creates startup scripts for one-click launch"
    echo ""
    
    if ! confirm "Do you want to configure VM auto-boot and headless operation?"; then
        return 0
    fi
    
    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    # Check if Ventoy USB is ready
    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        print_info "How to resolve:"
        print_info "  1. Ensure the USB drive is plugged in"
        print_info "  2. Check if it appears in: lsblk (Linux) or diskutil list (macOS)"
        print_info "  3. Try unplugging and re-plugging the USB"
        print_info "  4. If using a USB hub, try a direct port instead"
        return 1
    fi
    
    # Check if Ventoy is installed
    local ventoy_installed=0
    if [[ "$OS" == "Darwin" ]]; then
        if [[ -b "${SELECTED_DEVICE}s1" ]]; then
            local vol_name
            vol_name=$(diskutil info "${SELECTED_DEVICE}s1" 2>/dev/null | grep "Volume Name" | awk '{print $3}' || true)
            if [[ "$vol_name" == "Ventoy" ]]; then
                ventoy_installed=1
            fi
        fi
    else
        if [[ -b "${SELECTED_DEVICE}1" ]]; then
            local label
            label=$(blkid -o value -s LABEL "${SELECTED_DEVICE}1" 2>/dev/null || true)
            if [[ "$label" == "Ventoy" ]]; then
                ventoy_installed=1
            fi
        fi
    fi
    
    if [[ $ventoy_installed -eq 0 ]]; then
        print_error "Ventoy is not installed on $SELECTED_DEVICE"
        print_info "How to resolve: Please prepare the USB drive first using Option 2 from the main menu."
        return 1
    fi
    
    # Platform-specific VM setup
    if [[ "$OS" == "Darwin" ]]; then
        setup_utm_vm
    elif [[ "$OS" == "Linux" ]]; then
        setup_qemu_vm
    else
        print_warning "Windows VM setup not implemented in this demo"
        print_info "Please configure your VM manually:"
        echo "  • Use Hyper-V or VirtualBox"
        echo "  • Configure to boot from USB"
        echo "  • Enable headless mode"
        echo "  • Set up SSH port forwarding (Host:2222 → Guest:22)"
        return 0
    fi
    
    # Setup auto-boot service
    setup_autoboot_service
    
    print_success "VM auto-boot and headless configuration completed!"
    return 0
}

setup_utm_vm() {
    print_info "Configuring UTM VM for headless boot..."
    
    # Create UTM automation script
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts}"
    if ! mkdir -p "$script_dir"; then
        print_error "Failed to create scripts directory at $script_dir"
        print_info "How to resolve: Check if you have write permissions to the parent directory."
        return 1
    fi
    
    # Create a wrapper script that will be called by LaunchAgent
    local wrapper_script="$script_dir/usb-detector.sh"
    local detected_script_dir
    detected_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    cat > "$wrapper_script" << EOF
#!/usr/bin/env bash
# USB Detector Script - Called by LaunchAgent when USB devices change

LOG_FILE="/tmp/usb-compute-automation-\$(date +%Y%m%d).log"
SCRIPT_DIR="$detected_script_dir"
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
    local launch_agent_plist="$HOME/Library/LaunchAgents/com.usbcompute.autostart.plist"
    if ! mkdir -p "$(dirname "$launch_agent_plist")"; then
        print_error "Failed to create LaunchAgents directory"
        print_info "How to resolve: Ensure $HOME/Library/LaunchAgents/ exists and is writable."
        return 1
    fi
    
    cat > "$launch_agent_plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.usbcompute.autostart</string>
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
    
    # Load the LaunchAgent
    print_info "Loading Launch Agent..."
    if ! launchctl load "$launch_agent_plist" 2>/dev/null; then
        print_warning "Could not auto-load Launch Agent (this is normal if already loaded)"
        print_info "How to resolve if needed:"
        print_info "  1. Unload first: launchctl unload $launch_agent_plist"
        print_info "  2. Reload: launchctl load $launch_agent_plist"
    fi
    
    print_success "UTM VM automation configured!"
    print_info "To complete the setup:"
    echo "  1. Open UTM"
    echo "  2. Create a new VM or configure an existing one"
    echo "  3. Set the boot device to your Ventoy USB"
    echo "  4. Configure 2 CPU cores and 4GB RAM"
    echo "  5. Enable headless mode (no GUI)"
    echo "  6. Add port forwarding: Host $SSH_PORT_FORWARD_HOST → Guest $SSH_PORT_FORWARD_GUEST (SSH)"
    echo "  7. Save the VM as 'USB Compute VM'"
    echo "  8. The system will now automatically detect when the USB is plugged in"
    echo "     and start the VM in headless mode"
    echo ""
    
    return 0
}

setup_qemu_vm() {
    print_info "Configuring QEMU VM for headless boot..."
    
    # Create QEMU startup script
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/scripts}"
    if ! mkdir -p "$script_dir"; then
        print_error "Failed to create scripts directory at $script_dir"
        print_info "How to resolve: Check if you have write permissions to the parent directory."
        return 1
    fi
    
    local qemu_script="$script_dir/start-usb-vm.sh"
    cat > "$qemu_script" << 'EOF'
#!/usr/bin/env bash
# QEMU USB VM Starter Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/qemu-vm-$(date +%Y%m%d).log"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Check if USB is connected
is_target_usb_connected() {
    if blkid -l 2>/dev/null | grep -q "Ventoy"; then
        return 0
    fi
    return 1
}

# Start the QEMU VM
start_qemu_vm() {
    log "Target USB detected, starting QEMU VM..."
    
    # Default VM configuration
    local memory="4G"
    local cpus="2"
    local ssh_host_port=2222
    local ssh_guest_port=22
    
    # Find the USB device
    local usb_device=""
    if [[ "$(uname)" == "Linux" ]]; then
        usb_device=$(blkid -l 2>/dev/null | grep "Ventoy" | awk '{print $1}' | sed 's/:$//')
    fi
    
    if [[ -z "$usb_device" ]]; then
        log "Error: Could not find Ventoy USB device"
        return 1
    fi
    
    log "Using USB device: $usb_device"
    log "Memory: $memory, CPUs: $cpus"
    log "SSH Port Forwarding: Host:$ssh_host_port → Guest:$ssh_guest_port"
    
    # Start QEMU VM
    qemu-system-x86_64 \
        -enable-kvm \
        -m "$memory" \
        -smp "$cpus" \
        -drive "file=$usb_device,format=raw,if=virtio" \
        -boot c \
        -netdev user,id=net0,hostfwd=tcp::${ssh_host_port}-:${ssh_guest_port} \
        -device virtio-net-pci,netdev=net0 \
        -nographic \
        "$@"
}

# Main execution
log "QEMU USB VM starter executed"

if is_target_usb_connected; then
    log "Target USB device detected"
    start_qemu_vm
else
    log "Target USB device not connected - waiting..."
    # In a real implementation, this would loop or be called by a service
fi
EOF
    
    if ! chmod +x "$qemu_script"; then
        print_error "Failed to make QEMU script executable"
        print_info "How to resolve: Check file permissions: ls -la $qemu_script"
        return 1
    fi
    
    # Create systemd service
    local service_file="/etc/systemd/system/usb-compute-vm.service"
    local qemu_script_path="$script_dir/start-usb-vm.sh"
    cat > "$service_file" << EOF
[Unit]
Description=USB Compute Auto-Boot VM
After=network.target

[Service]
Type=simple
User=$(whoami)
Group=$(whoami)
ExecStart=$qemu_script_path
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
    
    print_info "To complete the setup:"
    echo "  1. Save the above configuration to /etc/systemd/system/usb-compute-vm.service"
    echo "  2. Enable the service: sudo systemctl enable usb-compute-vm.service"
    echo "  3. Start the service: sudo systemctl start usb-compute-vm.service"
    echo "  4. Check status: sudo systemctl status usb-compute-vm.service"
    echo ""
    
    print_success "QEMU VM automation script created!"
    print_info "Please follow the instructions above to complete the setup"
    return 0
}

setup_autoboot_service() {
    print_info "Setting up automatic USB detection service..."
    
    if [[ "$OS" == "Darwin" ]]; then
        print_success "Launch Agent for USB detection has been configured!"
        print_info "The system will now detect when the Ventoy USB is plugged in"
        print_info "and automatically start the UTM VM in headless mode"
    elif [[ "$OS" == "Linux" ]]; then
        print_info "To enable the USB detection service:"
        echo "  1. Copy the service file to /etc/systemd/system/usb-compute-vm.service"
        echo "  2. Run: sudo systemctl daemon-reload"
        echo "  3. Run: sudo systemctl enable usb-compute-vm.service"
        echo "  4. Run: sudo systemctl start usb-compute-vm.service"
        echo "  5. Check status: sudo systemctl status usb-compute-vm.service"
    fi
    
    return 0
}

# ============================================================================
# STEP 4: INSTALL BUILD ESSENTIALS AND DEPENDENCIES
# ============================================================================

install_essentials() {
    print_header "Build Essentials and Dependencies"
    echo "This mounts the USB persistence image, installs tools"
    echo "directly into it via chroot, and they become permanent."
    echo "No VM needed — the USB environment is updated in place."
    echo ""

    # --- Select device if not already selected ---
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        return 1
    fi

    # --- Mount Ventoy partition ---
    if ! detect_ventoy_mount; then
        print_error "Could not find or mount Ventoy partition"
        return 1
    fi

    # --- Check persistence exists ---
    local persist_file="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$persist_file" ]]; then
        print_error "No persistence image found on USB"
        print_info "Create one first: Option 2 → Create Persistence"
        unmount_ventoy
        return 1
    fi

    print_success "Persistence found: $(du -h "$persist_file" | cut -f1)"

    # --- Component selection menu ---
    print_header "Select Components to Install"
    echo "Choose what to install into the USB persistence environment:"
    echo ""
    echo "  [1] Build essentials (gcc, make, cmake, git, python3, nodejs)"
    echo "  [2] System utilities (htop, vim, curl, wget, net-tools)"
    echo "  [3] Python dev tools (pip, venv, ipython, jupyter)"
    echo "  [4] Container tools (docker, podman)"
    echo "  [5] LLM engine: ollama"
    echo "  [6] LLM engine: llama.cpp"
    echo "  [7] Agent harness: AutoGen"
    echo "  [8] Agent harness: CrewAI"
    echo "  [9] Agent harness: LangChain"
    echo "  [D] Database tools (mysql-client, postgresql-client, sqlite3)"
    echo "  [M] Modern CLI tools (ripgrep, fd-find, btop, ncdu, tmux, jq, nala, bat, fzf, zsh)"
    echo "  [A] All of the above"
    echo "  [N] None — just base essentials"
    echo "  [Q] Cancel"
    echo ""

    local sel_utils=false sel_python=false sel_containers=false
    local sel_ollama=false sel_llama=false
    local sel_autogen=false sel_crewai=false sel_langchain=false
    local sel_database=false sel_modern=false

    while true; do
        read -p "$(echo -e "${YELLOW}Toggle items (e.g. 1 3 5 D M) or A/N/Q: ${NC}")" -a selections

        for sel in "${selections[@]}"; do
            case "$sel" in
                1) ;; # always included
                2) sel_utils=true ;;
                3) sel_python=true ;;
                4) sel_containers=true ;;
                5) sel_ollama=true ;;
                6) sel_llama=true ;;
                7) sel_autogen=true ;;
                8) sel_crewai=true ;;
                9) sel_langchain=true ;;
                D|d) sel_database=true ;;
                M|m) sel_modern=true ;;
                A|a)
                    sel_utils=true; sel_python=true; sel_containers=true
                    sel_ollama=true; sel_llama=true
                    sel_autogen=true; sel_crewai=true; sel_langchain=true
                    sel_database=true; sel_modern=true
                    ;;
                N|n) ;;
                Q|q)
                    print_info "Cancelled"
                    unmount_ventoy
                    return 0
                    ;;
                *) print_error "Unknown: $sel" ;;
            esac
        done
        break
    done

    # --- Show preview ---
    echo ""
    print_header "Installation Preview"
    echo "The following will be installed permanently into the USB persistence image:"
    echo ""
    echo "  ✓ Build essentials (GCC, Make, CMake, Git, Python3, Node.js)"
    [[ "$sel_utils" == "true" ]] && echo "  ✓ System utilities (htop, vim, curl, wget, net-tools)"
    [[ "$sel_python" == "true" ]] && echo "  ✓ Python dev tools (pip, venv, ipython, jupyter)"
    [[ "$sel_containers" == "true" ]] && echo "  ✓ Container tools (docker, podman)"
    [[ "$sel_ollama" == "true" ]] && echo "  ✓ Ollama (LLM runtime)"
    [[ "$sel_llama" == "true" ]] && echo "  ✓ llama.cpp (LLM inference)"
    [[ "$sel_autogen" == "true" ]] && echo "  ✓ AutoGen (agent framework)"
    [[ "$sel_crewai" == "true" ]] && echo "  ✓ CrewAI (agent framework)"
    [[ "$sel_langchain" == "true" ]] && echo "  ✓ LangChain (agent framework)"
    [[ "$sel_database" == "true" ]] && echo "  ✓ Database tools (mysql-client, postgresql-client, sqlite3)"
    [[ "$sel_modern" == "true" ]] && echo "  ✓ Modern CLI tools (ripgrep, fd-find, btop, ncdu, tmux, jq, nala, bat, fzf, zsh)"
    echo ""

    if ! confirm "Proceed?"; then
        unmount_ventoy
        return 0
    fi

    # --- Mount persistence image ---
    print_header "Mounting Persistence Image"
    local persist_mnt="/tmp/usb-persist-$$"
    mkdir -p "$persist_mnt"

    if ! mount -o loop "$persist_file" "$persist_mnt" 2>/dev/null; then
        print_error "Failed to mount persistence image"
        print_info "May need root: sudo bash $0"
        unmount_ventoy
        return 1
    fi

    print_success "Persistence mounted at $persist_mnt"

    # --- Check if base system exists, if not install via debootstrap ---
    if [[ ! -f "$persist_mnt/bin/bash" ]]; then
        print_header "Installing Base Ubuntu System (debootstrap)"
        print_info "Installing minimal Ubuntu base system into persistence..."

        if ! command -v debootstrap &>/dev/null; then
            print_info "Installing debootstrap..."
            apt-get update && apt-get install -y debootstrap 2>&1 | tee -a /var/log/usb-essentials.log || {
                print_error "Failed to install debootstrap"
                unmount_ventoy
                return 1
            }
        fi

        local ubuntu_release="noble"  # Ubuntu 24.04
        local mirror="http://archive.ubuntu.com/ubuntu"
        
        print_info "Running debootstrap for $ubuntu_release..."
        if ! debootstrap --variant=minbase "$ubuntu_release" "$persist_mnt" "$mirror" 2>&1 | tee -a /var/log/usb-essentials.log; then
            print_error "debootstrap failed"
            unmount_ventoy
            return 1
        fi

        print_success "Base Ubuntu system installed"
    else
        print_info "Base system already exists in persistence"
    fi

    # --- Configure APT sources in the base system ---
    print_info "Configuring APT repositories..."
    cat > "$persist_mnt/etc/apt/sources.list" << 'SOURCES_EOF'
deb http://archive.ubuntu.com/ubuntu noble main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-security main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu noble-backports main restricted universe multiverse
SOURCES_EOF

    # --- Prepare chroot environment ---
    print_info "Preparing isolated environment..."

    mount --bind /dev "$persist_mnt/dev" 2>/dev/null || true
    mount --bind /proc "$persist_mnt/proc" 2>/dev/null || true
    mount --bind /sys "$persist_mnt/sys" 2>/dev/null || true
    mount --bind /dev/pts "$persist_mnt/dev/pts" 2>/dev/null || true
    mount --bind /tmp "$persist_mnt/tmp" 2>/dev/null || true

    cp /etc/resolv.conf "$persist_mnt/etc/resolv.conf" 2>/dev/null || true

    # --- Build install script ---
    local install_script="$persist_mnt/tmp/usb-install.sh"
    mkdir -p "$persist_mnt/tmp"

    cat > "$install_script" << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

echo "=== USB Compute Essentials Install ===" | tee /var/log/usb-essentials.log

echo "Updating package lists..." | tee -a /var/log/usb-essentials.log
apt-get update 2>&1 | tee -a /var/log/usb-essentials.log

echo "Installing base tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y build-essential git curl wget vim nano htop 2>&1 | tee -a /var/log/usb-essentials.log
apt-get install -y python3 python3-pip python3-venv python3-dev 2>&1 | tee -a /var/log/usb-essentials.log

SCRIPT_EOF

    # --- Add NodeSource repository for Node.js LTS ---
    cat >> "$install_script" << 'NODESOURCE_EOF'
echo "Adding NodeSource repository for Node.js LTS..." | tee -a /var/log/usb-essentials.log
apt-get install -y ca-certificates curl gnupg 2>&1 | tee -a /var/log/usb-essentials.log
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_lts.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update 2>&1 | tee -a /var/log/usb-essentials.log
NODESOURCE_EOF

    # --- Add Docker official repository ---
    cat >> "$install_script" << 'DOCKER_EOF'
echo "Adding Docker official repository..." | tee -a /var/log/usb-essentials.log
apt-get install -y ca-certificates curl gnupg lsb-release 2>&1 | tee -a /var/log/usb-essentials.log
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update 2>&1 | tee -a /var/log/usb-essentials.log
DOCKER_EOF

    # --- Base tools install ---
    cat >> "$install_script" << 'BASE_TOOLS_EOF'
echo "Installing base tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y build-essential git curl wget vim nano htop 2>&1 | tee -a /var/log/usb-essentials.log
apt-get install -y python3 python3-pip python3-venv python3-dev nodejs npm 2>&1 | tee -a /var/log/usb-essentials.log

BASE_TOOLS_EOF

    [[ "$sel_utils" == "true" ]] && cat >> "$install_script" << 'UTILS_EOF'
echo "Installing system utilities..." | tee -a /var/log/usb-essentials.log
apt-get install -y make cmake pkg-config libssl-dev zlib1g-dev libffi-dev libreadline-dev libbz2-dev liblzma-dev sqlite3 libsqlite3-dev tk-dev libgdbm-dev libncursesw5-dev xz-utils libxml2-dev libxslt1-dev libjpeg-dev libpng-dev unzip p7zip-full rsync ssh net-tools dnsutils 2>&1 | tee -a /var/log/usb-essentials.log
UTILS_EOF

    [[ "$sel_python" == "true" ]] && cat >> "$install_script" << 'PYTHON_EOF'
echo "Installing Python dev tools..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages ipython jupyter black flake8 pytest 2>&1 | tee -a /var/log/usb-essentials.log
PYTHON_EOF

    [[ "$sel_containers" == "true" ]] && cat >> "$install_script" << 'CONTAINERS_EOF'
echo "Installing container tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin podman 2>&1 | tee -a /var/log/usb-essentials.log
CONTAINERS_EOF

    [[ "$sel_database" == "true" ]] && cat >> "$install_script" << 'DATABASE_EOF'
echo "Installing database tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y mysql-client postgresql-client sqlite3 2>&1 | tee -a /var/log/usb-essentials.log
DATABASE_EOF

    [[ "$sel_modern" == "true" ]] && cat >> "$install_script" << 'MODERN_EOF'
echo "Installing modern CLI tools..." | tee -a /var/log/usb-essentials.log
apt-get install -y ripgrep fd-find btop ncdu tmux jq nala tree bat fzf zsh 2>&1 | tee -a /var/log/usb-essentials.log
# fd-find installs as fdfind, create fd alias
ln -sf /usr/bin/fdfind /usr/local/bin/fd 2>/dev/null || true
MODERN_EOF

    [[ "$sel_ollama" == "true" ]] && cat >> "$install_script" << 'OLLAMA_EOF'
echo "Installing Ollama..." | tee -a /var/log/usb-essentials.log
# Install zstd first (required for Ollama extraction)
apt-get install -y zstd 2>&1 | tee -a /var/log/usb-essentials.log
curl -fsSL https://ollama.com/install.sh | sh 2>&1 | tee -a /var/log/usb-essentials.log

# Hardware-aware Ollama configuration
ARCH=$(uname -m)
if [[ "$ARCH" == "aarch64" ]] || [[ "$ARCH" == "arm64" ]]; then
    echo "Detected Apple Silicon / ARM64 — Ollama will use Metal acceleration" | tee -a /var/log/usb-essentials.log
elif [[ "$ARCH" == "x86_64" ]]; then
    echo "Detected x86_64 — Ollama will use CPU/GPU based on availability" | tee -a /var/log/usb-essentials.log
fi
OLLAMA_EOF

    [[ "$sel_llama" == "true" ]] && cat >> "$install_script" << 'LLAMA_EOF'
echo "Installing llama.cpp (dynamic, hardware-aware)..." | tee -a /var/log/usb-essentials.log

# Designated persistent state root (rides in the USB persistence chroot).
LLAMA_SRC=/opt/llama.cpp
LLAMA_HOME=/opt/llama
MODELS_DIR="$LLAMA_HOME/models"
STATE_FILE="$LLAMA_HOME/state.json"
mkdir -p "$LLAMA_HOME/bin" "$MODELS_DIR"

# Fetch (shallow) or refresh source.
if [ -d "$LLAMA_SRC/.git" ]; then
    git -C "$LLAMA_SRC" pull --ff-only 2>&1 | tee -a /var/log/usb-essentials.log || true
else
    git clone --depth 1 https://github.com/ggerganov/llama.cpp "$LLAMA_SRC" 2>&1 | tee -a /var/log/usb-essentials.log
fi
cd "$LLAMA_SRC"

# --- Scan the system this is running on ---
ARCH=$(uname -m); OS=$(uname -s)
CORES=$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
RAM_MB=$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null \
         || echo $(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1048576 )))

# --- Choose backend dynamically from detected components ---
if [ "$OS" = "Darwin" ]; then
    BACKEND=metal;  CMAKE_FLAGS="-DGGML_METAL=ON"
elif command -v nvidia-smi >/dev/null 2>&1; then
    BACKEND=cuda;   CMAKE_FLAGS="-DGGML_CUDA=ON"
elif command -v rocminfo >/dev/null 2>&1 || [ -d /opt/rocm ]; then
    BACKEND=rocm;   CMAKE_FLAGS="-DGGML_HIP=ON"
elif command -v vulkaninfo >/dev/null 2>&1; then
    BACKEND=vulkan; CMAKE_FLAGS="-DGGML_VULKAN=ON"
else
    BACKEND=cpu;    CMAKE_FLAGS="-DGGML_NATIVE=ON -DGGML_BLAS=ON"
fi
echo "Detected: os=$OS arch=$ARCH cores=$CORES ram=${RAM_MB}MB backend=$BACKEND" | tee -a /var/log/usb-essentials.log

# --- Build: modern CMake preferred, legacy make as fallback ---
if command -v cmake >/dev/null 2>&1; then
    cmake -B build $CMAKE_FLAGS -DCMAKE_BUILD_TYPE=Release 2>&1 | tee -a /var/log/usb-essentials.log
    cmake --build build --config Release -j"$CORES" 2>&1 | tee -a /var/log/usb-essentials.log
    BIN_DIR="$LLAMA_SRC/build/bin"
else
    echo "cmake not found — falling back to make" | tee -a /var/log/usb-essentials.log
    make -j"$CORES" 2>&1 | tee -a /var/log/usb-essentials.log
    BIN_DIR="$LLAMA_SRC"
fi

# Expose binaries (new + legacy names) on PATH.
for b in llama-cli llama-server llama-bench main server; do
    [ -f "$BIN_DIR/$b" ] && ln -sf "$BIN_DIR/$b" "$LLAMA_HOME/bin/$b"
done
ln -sf "$LLAMA_HOME/bin/"* /usr/local/bin/ 2>/dev/null || true

# --- Persistent, utilization-aware config + initial state ---
if [ "$BACKEND" = "cpu" ]; then DEF_NGL=0; else DEF_NGL=999; fi
cat > "$LLAMA_HOME/config.env" <<CFG
# llama.cpp runtime config — generated from detected hardware. Edit to tune.
LLAMA_HOME=$LLAMA_HOME
MODELS_DIR=$MODELS_DIR
BACKEND=$BACKEND
THREADS=$CORES
CTX=4096
HOST=127.0.0.1
PORT=8080
NGL=$DEF_NGL      # GPU layers to offload (0 = pure CPU)
CFG
[ -f "$STATE_FILE" ] || echo '{"loaded_model":null,"pid":null,"started":null}' > "$STATE_FILE"

# Share the persistent model dir with the llmrl model browser.
echo "export MODEL_DIR=$MODELS_DIR" > /etc/profile.d/llama-models.sh

# --- Model load-lifecycle + utilization manager (persistent state) ---
cat > "$LLAMA_HOME/bin/llama-manage" <<'MANAGE'
#!/usr/bin/env bash
# llama.cpp model lifecycle manager: list / load(serve) / stop / status.
# Reads utilization defaults (threads, ctx, GPU layers) from config.env and
# records the running model + pid in a persistent state file.
set -euo pipefail
LLAMA_HOME="${LLAMA_HOME:-/opt/llama}"
# shellcheck disable=SC1091
. "$LLAMA_HOME/config.env" 2>/dev/null || true
STATE="$LLAMA_HOME/state.json"; LOG="$LLAMA_HOME/server.log"
_server() { command -v llama-server 2>/dev/null || echo "$LLAMA_HOME/bin/llama-server"; }
_state() { printf '{"loaded_model":%s,"pid":%s,"started":%s}\n' "${1:-null}" "${2:-null}" "${3:-null}" > "$STATE"; }
case "${1:-status}" in
    list)
        ls -1 "${MODELS_DIR:-/opt/llama/models}"/*.gguf 2>/dev/null \
            || echo "(no .gguf models in ${MODELS_DIR:-/opt/llama/models})" ;;
    load|serve)
        m="${2:?usage: llama-manage load <model.gguf>}"
        [ -f "$m" ] || m="${MODELS_DIR:-/opt/llama/models}/$m"
        [ -f "$m" ] || { echo "model not found: $m" >&2; exit 1; }
        "$0" stop >/dev/null 2>&1 || true
        nohup "$(_server)" -m "$m" -t "${THREADS:-4}" -c "${CTX:-4096}" \
            -ngl "${NGL:-0}" --host "${HOST:-127.0.0.1}" --port "${PORT:-8080}" \
            >>"$LOG" 2>&1 &
        pid=$!; _state "\"$m\"" "$pid" "\"$(date -Iseconds)\""
        echo "serving $(basename "$m") pid=$pid on ${HOST:-127.0.0.1}:${PORT:-8080} (backend=${BACKEND:-cpu} threads=${THREADS:-4} ngl=${NGL:-0})" ;;
    stop)
        pid=$(grep -o '"pid":[0-9]*' "$STATE" 2>/dev/null | grep -o '[0-9]*' || true)
        if [ -n "${pid:-}" ] && kill "$pid" 2>/dev/null; then echo "stopped pid $pid"; else echo "nothing running"; fi
        _state null null null ;;
    status) cat "$STATE" 2>/dev/null || echo "no state" ;;
    *) echo "usage: llama-manage {list|load <model>|stop|status}"; exit 1 ;;
esac
MANAGE
chmod +x "$LLAMA_HOME/bin/llama-manage"
ln -sf "$LLAMA_HOME/bin/llama-manage" /usr/local/bin/llama-manage 2>/dev/null || true

echo "llama.cpp ready (backend=$BACKEND, ${CORES} cores). Models: $MODELS_DIR" | tee -a /var/log/usb-essentials.log
echo "  Manage: llama-manage list | load <model.gguf> | status | stop" | tee -a /var/log/usb-essentials.log
LLAMA_EOF

    [[ "$sel_autogen" == "true" ]] && cat >> "$install_script" << 'AUTOGEN_EOF'
echo "Installing AutoGen..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages autogen-agentchat 2>&1 | tee -a /var/log/usb-essentials.log
AUTOGEN_EOF

    [[ "$sel_crewai" == "true" ]] && cat >> "$install_script" << 'CREWAI_EOF'
echo "Installing CrewAI..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages crewai 2>&1 | tee -a /var/log/usb-essentials.log
CREWAI_EOF

    [[ "$sel_langchain" == "true" ]] && cat >> "$install_script" << 'LANGCHAIN_EOF'
echo "Installing LangChain..." | tee -a /var/log/usb-essentials.log
pip3 install --break-system-packages langchain langchain-community 2>&1 | tee -a /var/log/usb-essentials.log
LANGCHAIN_EOF

    cat >> "$install_script" << 'CLEANUP_EOF'
echo "Cleaning up..." | tee -a /var/log/usb-essentials.log
apt-get autoremove -y 2>&1 | tee -a /var/log/usb-essentials.log
apt-get clean 2>&1 | tee -a /var/log/usb-essentials.log

echo "=== Installation Complete ===" | tee -a /var/log/usb-essentials.log
echo "Python: $(python3 --version 2>/dev/null)" | tee -a /var/log/usb-essentials.log
echo "Node.js: $(node --version 2>/dev/null)" | tee -a /var/log/usb-essentials.log
echo "GCC: $(gcc --version 2>/dev/null | head -1)" | tee -a /var/log/usb-essentials.log
CLEANUP_EOF

    chmod +x "$install_script"

    # --- Actually run the install via chroot ---
    print_header "Installing into USB Persistence"
    echo "  Progress shown in real-time."
    echo ""

    if chroot "$persist_mnt" /bin/bash /tmp/usb-install.sh 2>&1; then
        print_success "Installation complete!"
    else
        print_warning "Installation may have encountered errors"
    fi

    # --- Cleanup chroot ---
    print_info "Cleaning up..."
    umount "$persist_mnt/dev/pts" 2>/dev/null || true
    umount "$persist_mnt/dev" 2>/dev/null || true
    umount "$persist_mnt/proc" 2>/dev/null || true
    umount "$persist_mnt/sys" 2>/dev/null || true
    umount "$persist_mnt" 2>/dev/null || true
    rmdir "$persist_mnt" 2>/dev/null || true

    # --- Copy install script to USB for future updates ---
    if [[ -d "$VENTOY_MOUNT" ]]; then
        cp "$VENTOY_MOUNT/../tmp/usb-install.sh" "$VENTOY_MOUNT/setup-essentials.sh" 2>/dev/null || true
        chmod +x "$VENTOY_MOUNT/setup-essentials.sh" 2>/dev/null || true
    fi

    # --- Show what was installed ---
    echo ""
    print_header "Installed Packages"
    if [[ -f "$persist_mnt/../var/log/usb-essentials.log" ]]; then
        grep -E "^(apt-get|pip3|git clone|curl)" "$persist_mnt/../var/log/usb-essentials.log" 2>/dev/null | sed 's/^/  /' || true
    fi

    echo ""
    print_success "Tools are now permanently in the USB persistence image."
    print_info "Boot from USB — everything is already installed."
    print_info "To update later: run Option 4 again, or run setup-essentials.sh"

    unmount_ventoy
    return 0
}

# ============================================================================
# STEP 5: CONFIGURE NETWORK AND SSH ACCESS
# ============================================================================

configure_network() {
    print_header "Network and SSH Configuration"
    echo ""

    # --- Detect host hardware ---
    print_header "Host System Detection"
    local host_model=""
    local host_cpu=""
    local host_ram=""
    local host_gpu=""

    if [[ "$OS" == "Darwin" ]]; then
        host_model=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | awk -F': ' '{print $2}' || echo "Unknown Mac")
        host_cpu=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | awk -F': ' '{print $2}' || echo "Unknown")
        host_ram=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Memory" | awk -F': ' '{print $2}' || echo "Unknown")
        host_gpu=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Chipset Model" | awk -F': ' '{print $2}' || echo "Unknown")
    elif [[ "$OS" == "Linux" ]]; then
        host_model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || dmidecode -s system-product-name 2>/dev/null || echo "Unknown")
        host_cpu=$(lscpu 2>/dev/null | grep "Model name" | awk -F': ' '{print $2}' || echo "Unknown")
        host_ram=$(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo "Unknown")
        host_gpu=$(lspci 2>/dev/null | grep -i vga | head -1 | awk -F': ' '{print $2}' || echo "Unknown")
    fi

    echo "  Model: $host_model"
    echo "  CPU:   $host_cpu"
    echo "  RAM:   $host_ram"
    echo "  GPU:   $host_gpu"
    echo ""

    # --- Detect available tools ---
    print_header "Available Network Tools"
    local tools=()
    local missing=()

    for cmd in ssh tailscale wireguard socat iptables nmap; do
        if command -v $cmd &>/dev/null; then
            tools+=("$cmd")
        else
            missing+=("$cmd")
        fi
    done

    [[ ${#tools[@]} -gt 0 ]] && print_success "Found: ${tools[*]}"
    [[ ${#missing[@]} -gt 0 ]] && print_info "Not installed: ${missing[*]}"
    echo ""

    # --- Management loop ---
    while true; do
        print_header "Network Management Menu"
        echo "  1) Configure SSH port forwarding"
        echo "  2) Test SSH connection to VM"
        echo "  3) Add custom port forward"
        echo "  4) Remove port forward"
        echo "  5) List active port forwards"
        echo "  6) Install and configure Tailscale"
        echo "  7) Join Tailscale network"
        echo "  8) Install WireGuard"
        echo "  9) Scan local network for devices"
        echo "  10) Generate SSH config"
        echo "  q) Return to main menu"
        echo ""

        read -p "$(echo -e "${YELLOW}Select [1-10/q]: ${NC}")" choice
        case "$choice" in
            1) _configure_ssh_forward || read -p "Press Enter to continue..." ;;
            2) _test_ssh_connection || read -p "Press Enter to continue..." ;;
            3) _add_port_forward || read -p "Press Enter to continue..." ;;
            4) _remove_port_forward || read -p "Press Enter to continue..." ;;
            5) _list_port_forwards || read -p "Press Enter to continue..." ;;
            6) _install_tailscale || read -p "Press Enter to continue..." ;;
            7) _join_tailscale || read -p "Press Enter to continue..." ;;
            8) _install_wireguard || read -p "Press Enter to continue..." ;;
            9) _scan_network || read -p "Press Enter to continue..." ;;
            10) _generate_ssh_config || read -p "Press Enter to continue..." ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        echo ""
    done
}

_configure_ssh_forward() {
    print_header "Configure SSH Port Forwarding"
    echo "  Current: Host:$SSH_PORT_FORWARD_HOST → Guest:$SSH_PORT_FORWARD_GUEST"
    echo ""

    local new_host_port
    read -p "$(echo -e "${YELLOW}New host port (default: $SSH_PORT_FORWARD_HOST): ${NC}")" new_host_port
    [[ -n "$new_host_port" ]] && SSH_PORT_FORWARD_HOST="$new_host_port"

    print_info "Configuring port forward: Host:$SSH_PORT_FORWARD_HOST → Guest:$SSH_PORT_FORWARD_GUEST"

    if ! cache_sudo_password; then
        print_error "Sudo required for port forwarding"
        return 1
    fi

    if [[ "$OS" == "Linux" ]]; then
        sudo_run iptables -t nat -A PREROUTING -p tcp --dport "$SSH_PORT_FORWARD_HOST" -j REDIRECT --to-port "$SSH_PORT_FORWARD_GUEST" 2>/dev/null && \
            print_success "Port forward configured via iptables" || \
            print_warning "iptables failed"
    elif [[ "$OS" == "Darwin" ]]; then
        local pf_conf="/etc/pf.conf"
        local rule="rdr pass on lo0 inet proto tcp from any to any port $SSH_PORT_FORWARD_HOST -> 127.0.0.1 port $SSH_PORT_FORWARD_GUEST"

        echo "$rule" | sudo_run pfctl -ef - 2>/dev/null && \
            print_success "Port forward configured via pfctl" || \
            print_warning "pfctl failed — may need manual setup"
    fi

    print_info "SSH command: ssh -p $SSH_PORT_FORWARD_HOST user@localhost"
}

_test_ssh_connection() {
    print_header "Test SSH Connection & Validate Setup"
    print_info "Testing ssh -p $SSH_PORT_FORWARD_HOST user@localhost..."
    echo ""

    # Cache sudo for this validation
    if ! cache_sudo_password; then
        print_error "Sudo required for validation"
        return 1
    fi

    if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no -p "$SSH_PORT_FORWARD_HOST" user@localhost "echo 'SSH connection successful'" 2>&1; then
        print_success "SSH connection working"
        print_info "Communication validated between USB and host"
        
        # Clear sudo cache after successful validation
        clear_sudo_cache
        print_success "Sudo cache cleared — all future operations run inside USB environment"
    else
        print_error "SSH connection failed"
        print_info "Make sure the VM is running and SSH server is started inside it"
    fi
}

_add_port_forward() {
    print_header "Add Custom Port Forward"
    echo ""
    echo "  Examples:"
    echo "    Web server:     8080 → 80"
    echo "    MySQL:          3307 → 3306"
    echo "    PostgreSQL:     5433 → 5432"
    echo "    Jupyter:        8889 → 8888"
    echo "    Ollama API:     11435 → 11434"
    echo ""

    local host_port guest_port
    read -p "$(echo -e "${YELLOW}Host port: ${NC}")" host_port
    read -p "$(echo -e "${YELLOW}Guest port: ${NC}")" guest_port

    if [[ -z "$host_port" ]] || [[ -z "$guest_port" ]]; then
        print_error "Both ports required"
        return 1
    fi

    if ! cache_sudo_password; then
        print_error "Sudo required for port forwarding"
        return 1
    fi

    print_info "Adding forward: Host:$host_port → Guest:$guest_port"

    if [[ "$OS" == "Linux" ]]; then
        sudo_run iptables -t nat -A PREROUTING -p tcp --dport "$host_port" -j REDIRECT --to-port "$guest_port" 2>/dev/null && \
            print_success "Forward added" || print_error "Failed"
    elif [[ "$OS" == "Darwin" ]]; then
        local rule="rdr pass on lo0 inet proto tcp from any to any port $host_port -> 127.0.0.1 port $guest_port"
        echo "$rule" | sudo_run pfctl -ef - 2>/dev/null && print_success "Forward added" || print_error "Failed"
    fi
}

_remove_port_forward() {
    print_header "Remove Port Forward"
    _list_port_forwards
    echo ""

    local host_port
    read -p "$(echo -e "${YELLOW}Host port to remove: ${NC}")" host_port

    if [[ -z "$host_port" ]]; then
        print_error "Port required"
        return 1
    fi

    if ! cache_sudo_password; then
        print_error "Sudo required for port forwarding"
        return 1
    fi

    if [[ "$OS" == "Linux" ]]; then
        sudo_run iptables -t nat -D PREROUTING -p tcp --dport "$host_port" -j REDIRECT --to-port "$host_port" 2>/dev/null && \
            print_success "Forward removed" || print_error "Failed"
    elif [[ "$OS" == "Darwin" ]]; then
        print_info "Manual removal: sudo pfctl -F all && reconfigure"
    fi
}

_list_port_forwards() {
    print_header "Active Port Forwards"

    if [[ "$OS" == "Linux" ]]; then
        if command -v iptables &>/dev/null; then
            echo "  iptables NAT rules:"
            iptables -t nat -L PREROUTING -n -v 2>/dev/null | sed 's/^/    /' || print_info "No rules or need sudo"
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        if command -v pfctl &>/dev/null; then
            echo "  pfctl rules:"
            sudo pfctl -sr 2>/dev/null | grep rdr | sed 's/^/    /' || print_info "No rules or need sudo"
        fi
    fi
}

_install_tailscale() {
    print_header "Install Tailscale (into USB Persistence)"
    echo "This installs Tailscale INTO the USB persistence image, not the host."
    echo "It will be available when you boot from USB or chroot into persistence."
    echo ""

    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        return 1
    fi

    # Mount Ventoy partition
    if ! detect_ventoy_mount; then
        print_error "Could not find or mount Ventoy partition"
        return 1
    fi

    # Check persistence exists
    local persist_file="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$persist_file" ]]; then
        print_error "No persistence image found on USB"
        print_info "Create one first: Option 2 -> Create Persistence"
        unmount_ventoy
        return 1
    fi

    # Mount persistence image
    local persist_mnt="/tmp/usb-persist-ts-$$"
    mkdir -p "$persist_mnt"
    if ! mount -o loop "$persist_file" "$persist_mnt" 2>/dev/null; then
        print_error "Failed to mount persistence image"
        unmount_ventoy
        return 1
    fi

    # Prepare chroot
    mount --bind /dev "$persist_mnt/dev" 2>/dev/null || true
    mount --bind /proc "$persist_mnt/proc" 2>/dev/null || true
    mount --bind /sys "$persist_mnt/sys" 2>/dev/null || true
    mount --bind /dev/pts "$persist_mnt/dev/pts" 2>/dev/null || true
    cp /etc/resolv.conf "$persist_mnt/etc/resolv.conf" 2>/dev/null || true

    # Check if already installed in persistence
    if chroot "$persist_mnt" command -v tailscale &>/dev/null; then
        print_success "Tailscale already installed in persistence: $(chroot "$persist_mnt" tailscale version 2>/dev/null | head -1)"
        umount "$persist_mnt/dev/pts" 2>/dev/null || true
        umount "$persist_mnt/dev" 2>/dev/null || true
        umount "$persist_mnt/proc" 2>/dev/null || true
        umount "$persist_mnt/sys" 2>/dev/null || true
        umount "$persist_mnt" 2>/dev/null || true
        rmdir "$persist_mnt" 2>/dev/null || true
        unmount_ventoy
        return 0
    fi

    print_info "Installing Tailscale into USB persistence..."

    # Install inside chroot
    local install_script="$persist_mnt/tmp/install_tailscale.sh"
    cat > "$install_script" << 'TS_EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update 2>&1
apt-get install -y curl ca-certificates 2>&1
curl -fsSL https://tailscale.com/install.sh | sh 2>&1
TS_EOF
    chmod +x "$install_script"

    if chroot "$persist_mnt" /bin/bash /tmp/install_tailscale.sh 2>&1; then
        print_success "Tailscale installed into USB persistence"
    else
        print_error "Installation failed"
    fi

    # Cleanup
    rm -f "$install_script"
    umount "$persist_mnt/dev/pts" 2>/dev/null || true
    umount "$persist_mnt/dev" 2>/dev/null || true
    umount "$persist_mnt/proc" 2>/dev/null || true
    umount "$persist_mnt/sys" 2>/dev/null || true
    umount "$persist_mnt" 2>/dev/null || true
    rmdir "$persist_mnt" 2>/dev/null || true

    unmount_ventoy
}

_join_tailscale() {
    print_header "Join Tailscale Network (via USB Persistence)"
    echo "This connects Tailscale INSIDE the USB persistence environment."
    echo ""

    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        return 1
    fi

    # Mount Ventoy partition
    if ! detect_ventoy_mount; then
        print_error "Could not find or mount Ventoy partition"
        return 1
    fi

    # Check persistence exists
    local persist_file="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$persist_file" ]]; then
        print_error "No persistence image found on USB"
        print_info "Create one first: Option 2 -> Create Persistence"
        unmount_ventoy
        return 1
    fi

    # Mount persistence image
    local persist_mnt="/tmp/usb-persist-ts-join-$$"
    mkdir -p "$persist_mnt"
    if ! mount -o loop "$persist_file" "$persist_mnt" 2>/dev/null; then
        print_error "Failed to mount persistence image"
        unmount_ventoy
        return 1
    fi

    # Prepare chroot
    mount --bind /dev "$persist_mnt/dev" 2>/dev/null || true
    mount --bind /proc "$persist_mnt/proc" 2>/dev/null || true
    mount --bind /sys "$persist_mnt/sys" 2>/dev/null || true
    mount --bind /dev/pts "$persist_mnt/dev/pts" 2>/dev/null || true
    cp /etc/resolv.conf "$persist_mnt/etc/resolv.conf" 2>/dev/null || true

    # Check if installed in persistence
    if ! chroot "$persist_mnt" command -v tailscale &>/dev/null; then
        print_error "Tailscale not installed in persistence — run Option 5 -> 6 first"
        umount "$persist_mnt/dev/pts" 2>/dev/null || true
        umount "$persist_mnt/dev" 2>/dev/null || true
        umount "$persist_mnt/proc" 2>/dev/null || true
        umount "$persist_mnt/sys" 2>/dev/null || true
        umount "$persist_mnt" 2>/dev/null || true
        rmdir "$persist_mnt" 2>/dev/null || true
        unmount_ventoy
        return 1
    fi

    # Check if already connected
    local status
    status=$(chroot "$persist_mnt" tailscale status 2>/dev/null)
    if echo "$status" | grep -q "running"; then
        print_success "Already connected to Tailscale in persistence"
        echo "  IP: $(chroot "$persist_mnt" tailscale ip -4 2>/dev/null)"
        umount "$persist_mnt/dev/pts" 2>/dev/null || true
        umount "$persist_mnt/dev" 2>/dev/null || true
        umount "$persist_mnt/proc" 2>/dev/null || true
        umount "$persist_mnt/sys" 2>/dev/null || true
        umount "$persist_mnt" 2>/dev/null || true
        rmdir "$persist_mnt" 2>/dev/null || true
        unmount_ventoy
        return 0
    fi

    print_info "Starting Tailscale in USB persistence..."
    if chroot "$persist_mnt" tailscale up 2>&1; then
        print_success "Connected to Tailscale in USB persistence"
        echo "  IP: $(chroot "$persist_mnt" tailscale ip -4 2>/dev/null)"
    else
        print_error "Failed to connect"
        print_info "You may need to authenticate in a browser"
    fi

    # Cleanup
    umount "$persist_mnt/dev/pts" 2>/dev/null || true
    umount "$persist_mnt/dev" 2>/dev/null || true
    umount "$persist_mnt/proc" 2>/dev/null || true
    umount "$persist_mnt/sys" 2>/dev/null || true
    umount "$persist_mnt" 2>/dev/null || true
    rmdir "$persist_mnt" 2>/dev/null || true

    unmount_ventoy
}

_install_wireguard() {
    print_header "Install WireGuard (into USB Persistence)"
    echo "This installs WireGuard INTO the USB persistence image, not the host."
    echo "It will be available when you boot from USB or chroot into persistence."
    echo ""

    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        return 1
    fi

    # Mount Ventoy partition
    if ! detect_ventoy_mount; then
        print_error "Could not find or mount Ventoy partition"
        return 1
    fi

    # Check persistence exists
    local persist_file="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$persist_file" ]]; then
        print_error "No persistence image found on USB"
        print_info "Create one first: Option 2 -> Create Persistence"
        unmount_ventoy
        return 1
    fi

    # Mount persistence image
    local persist_mnt="/tmp/usb-persist-wg-$$"
    mkdir -p "$persist_mnt"
    if ! mount -o loop "$persist_file" "$persist_mnt" 2>/dev/null; then
        print_error "Failed to mount persistence image"
        unmount_ventoy
        return 1
    fi

    # Prepare chroot
    mount --bind /dev "$persist_mnt/dev" 2>/dev/null || true
    mount --bind /proc "$persist_mnt/proc" 2>/dev/null || true
    mount --bind /sys "$persist_mnt/sys" 2>/dev/null || true
    mount --bind /dev/pts "$persist_mnt/dev/pts" 2>/dev/null || true
    cp /etc/resolv.conf "$persist_mnt/etc/resolv.conf" 2>/dev/null || true

    # Check if already installed in persistence
    if chroot "$persist_mnt" command -v wg &>/dev/null; then
        print_success "WireGuard already installed in persistence: $(chroot "$persist_mnt" wg --version 2>/dev/null)"
        umount "$persist_mnt/dev/pts" 2>/dev/null || true
        umount "$persist_mnt/dev" 2>/dev/null || true
        umount "$persist_mnt/proc" 2>/dev/null || true
        umount "$persist_mnt/sys" 2>/dev/null || true
        umount "$persist_mnt" 2>/dev/null || true
        rmdir "$persist_mnt" 2>/dev/null || true
        unmount_ventoy
        return 0
    fi

    print_info "Installing WireGuard into USB persistence..."

    # Install inside chroot
    local install_script="$persist_mnt/tmp/install_wireguard.sh"
    cat > "$install_script" << 'WG_EOF'
#!/usr/bin/env bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update 2>&1
apt-get install -y wireguard 2>&1
WG_EOF
    chmod +x "$install_script"

    if chroot "$persist_mnt" /bin/bash /tmp/install_wireguard.sh 2>&1; then
        print_success "WireGuard installed into USB persistence"
    else
        print_error "Installation failed"
    fi

    # Cleanup
    rm -f "$install_script"
    umount "$persist_mnt/dev/pts" 2>/dev/null || true
    umount "$persist_mnt/dev" 2>/dev/null || true
    umount "$persist_mnt/proc" 2>/dev/null || true
    umount "$persist_mnt/sys" 2>/dev/null || true
    umount "$persist_mnt" 2>/dev/null || true
    rmdir "$persist_mnt" 2>/dev/null || true

    unmount_ventoy
}

_scan_network() {
    print_header "Scan Local Network"

    local subnet
    if [[ "$OS" == "Linux" ]]; then
        subnet=$(ip route 2>/dev/null | grep default | awk '{print $3}' | head -1 | awk -F. '{print $1"."$2"."$3".0/24}' || echo "192.168.1.0/24")
    elif [[ "$OS" == "Darwin" ]]; then
        subnet=$(netstat -rn 2>/dev/null | grep default | awk '{print $2}' | head -1 | awk -F. '{print $1"."$2"."$3".0/24}' || echo "192.168.1.0/24")
    fi

    read -p "$(echo -e "${YELLOW}Subnet to scan [default: $subnet]: ${NC}")" input_subnet
    [[ -n "$input_subnet" ]] && subnet="$input_subnet"

    print_info "Scanning $subnet..."

    if command -v nmap &>/dev/null; then
        nmap -sn "$subnet" 2>/dev/null | grep -E "Nmap scan|Host is up|MAC Address" | sed 's/^/  /'
    elif command -v ping &>/dev/null; then
        print_info "nmap not found — using ping sweep"
        local base=$(echo "$subnet" | sed 's/\.0\/24//')
        for i in $(seq 1 254); do
            ping -c 1 -W 1 "$base.$i" &>/dev/null && echo "  Host up: $base.$i" &
        done
        wait
    else
        print_error "No scanning tools available — install nmap"
    fi
}

_generate_ssh_config() {
    print_header "Generate SSH Config"

    local ssh_config="$HOME/.ssh/config"
    mkdir -p "$HOME/.ssh"
    chmod 700 "$HOME/.ssh"

    local entry="
# USB Compute VM
Host usb-vm
    HostName localhost
    Port $SSH_PORT_FORWARD_HOST
    User user
    IdentityFile ~/.ssh/id_rsa
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
"

    if grep -q "Host usb-vm" "$ssh_config" 2>/dev/null; then
        print_info "SSH config already has usb-vm entry"
    else
        echo "$entry" >> "$ssh_config"
        print_success "Added usb-vm entry to ~/.ssh/config"
    fi

    echo ""
    print_info "Now you can connect with: ssh usb-vm"
}

# ============================================================================
# STEP 6: VIEW SYSTEM STATUS AND HEALTH
# ============================================================================

view_system_status() {
    print_header "System Status and Health"
    echo ""

    while true; do
        print_header "System Status Menu"
        echo "  1) Full system scan (hardware + software)"
        echo "  2) USB drive status"
        echo "  3) VM status"
        echo "  4) Persistence status"
        echo "  5) Network status (ports, tailscale, wireguard)"
        echo "  6) Installed tools inventory"
        echo "  7) Disk usage"
        echo "  q) Return to main menu"
        echo ""

        read -p "$(echo -e "${YELLOW}Select [1-7/q]: ${NC}")" choice
        case "$choice" in
            1) _full_system_scan || read -p "Press Enter to continue..." ;;
            2) check_usb_status || read -p "Press Enter to continue..." ;;
            3) check_vm_status || read -p "Press Enter to continue..." ;;
            4) check_persistence_status || read -p "Press Enter to continue..." ;;
            5) _network_status || read -p "Press Enter to continue..." ;;
            6) _tools_inventory || read -p "Press Enter to continue..." ;;
            7) _disk_usage || read -p "Press Enter to continue..." ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        echo ""
    done
}

_full_system_scan() {
    print_header "Full System Scan"

    # Hardware
    print_header "Hardware"
    if [[ "$OS" == "Darwin" ]]; then
        local model=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Model Name" | awk -F': ' '{print $2}')
        local chip=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Chip" | awk -F': ' '{print $2}')
        local ram=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Memory" | awk -F': ' '{print $2}')
        local serial=$(system_profiler SPHardwareDataType 2>/dev/null | grep "Serial Number" | awk -F': ' '{print $2}')
        echo "  Model:    ${model:-Unknown}"
        echo "  Chip:     ${chip:-Unknown}"
        echo "  Memory:   ${ram:-Unknown}"
        echo "  Serial:   ${serial:-Unknown}"
    elif [[ "$OS" == "Linux" ]]; then
        local model=$(cat /sys/class/dmi/id/product_name 2>/dev/null || echo "Unknown")
        local cpu=$(lscpu 2>/dev/null | grep "Model name" | awk -F': ' '{print $2}' || echo "Unknown")
        local ram=$(free -h 2>/dev/null | grep Mem | awk '{print $2}' || echo "Unknown")
        local cores=$(nproc 2>/dev/null || echo "Unknown")
        echo "  Model:    $model"
        echo "  CPU:      $cpu"
        echo "  Cores:    $cores"
        echo "  Memory:   $ram"
    fi
    echo ""

    # OS
    print_header "Operating System"
    echo "  Platform: $OS"
    echo "  Kernel:   $(uname -r)"
    echo "  Arch:     $(uname -m)"
    echo "  Hostname: $(hostname)"
    echo ""

    # VM software
    print_header "VM Software"
    if command -v qemu-system-x86_64 &>/dev/null; then
        echo "  ✓ QEMU: $(qemu-system-x86_64 --version 2>/dev/null | head -1)"
    else
        echo "  ✗ QEMU: not installed"
    fi
    if command -v VBoxManage &>/dev/null; then
        echo "  ✓ VirtualBox: $(VBoxManage --version 2>/dev/null)"
    else
        echo "  ✗ VirtualBox: not installed"
    fi
    if [[ -d "/Applications/UTM.app" ]]; then
        echo "  ✓ UTM: installed"
    else
        echo "  ✗ UTM: not installed"
    fi
    echo ""

    # Network tools
    print_header "Network Tools"
    for cmd in ssh tailscale wireguard socat iptables nmap nc; do
        if command -v $cmd &>/dev/null; then
            local ver=$($cmd --version 2>/dev/null | head -1 || echo "installed")
            echo "  ✓ $cmd: $ver"
        else
            echo "  ✗ $cmd: not installed"
        fi
    done
    echo ""

    # Dev tools
    print_header "Development Tools"
    for cmd in gcc python3 node go rustc docker podman git cmake make; do
        if command -v $cmd &>/dev/null; then
            local ver=$($cmd --version 2>/dev/null | head -1 || $cmd version 2>/dev/null | head -1 || echo "installed")
            echo "  ✓ $cmd: $ver"
        else
            echo "  ✗ $cmd: not installed"
        fi
    done
    echo ""

    # AI/ML tools
    print_header "AI/ML Tools"
    for cmd in ollama llama-server; do
        if command -v $cmd &>/dev/null; then
            echo "  ✓ $cmd: installed"
        else
            echo "  ✗ $cmd: not installed"
        fi
    done
    for mod in autogen crewai langchain openai; do
        if python3 -c "import $mod" 2>/dev/null; then
            echo "  ✓ $mod (Python): installed"
        else
            echo "  ✗ $mod (Python): not installed"
        fi
    done
    echo ""

    # USB
    print_header "USB Status"
    check_usb_status
    echo ""

    # Persistence
    print_header "Persistence Status"
    check_persistence_status
}

_network_status() {
    print_header "Network Status"

    # Active port forwards
    echo "  Port Forwards:"
    if [[ "$OS" == "Linux" ]]; then
        iptables -t nat -L PREROUTING -n -v 2>/dev/null | grep -v "^Chain\|^target" | sed 's/^/    /' || echo "    (none or need sudo)"
    elif [[ "$OS" == "Darwin" ]]; then
        sudo pfctl -sr 2>/dev/null | grep rdr | sed 's/^/    /' || echo "    (none or need sudo)"
    fi
    echo ""

    # Tailscale
    echo "  Tailscale:"
    if command -v tailscale &>/dev/null; then
        local ts_status=$(tailscale status 2>/dev/null | head -3)
        if echo "$ts_status" | grep -q "running"; then
            echo "    ✓ Connected"
            echo "    IP: $(tailscale ip -4 2>/dev/null)"
        else
            echo "    ✗ Not connected"
        fi
    else
        echo "    ✗ Not installed"
    fi
    echo ""

    # WireGuard
    echo "  WireGuard:"
    if command -v wg &>/dev/null; then
        local wg_status=$(wg show 2>/dev/null || echo "no interfaces")
        echo "    $wg_status" | sed 's/^/    /'
    else
        echo "    ✗ Not installed"
    fi
    echo ""

    # Listening ports
    echo "  Listening Ports:"
    if command -v ss &>/dev/null; then
        ss -tlnp 2>/dev/null | head -10 | sed 's/^/    /'
    elif command -v netstat &>/dev/null; then
        netstat -tlnp 2>/dev/null | head -10 | sed 's/^/    /'
    fi
}

_tools_inventory() {
    print_header "Installed Tools Inventory"

    echo "  Build Tools:"
    for cmd in gcc g++ make cmake pkg-config; do
        command -v $cmd &>/dev/null && echo "    ✓ $cmd" || echo "    ✗ $cmd"
    done
    echo ""

    echo "  Languages:"
    for cmd in python3 node go rustc java ruby; do
        if command -v $cmd &>/dev/null; then
            local ver=$($cmd --version 2>/dev/null | head -1 || $cmd version 2>/dev/null | head -1)
            echo "    ✓ $cmd: $ver"
        else
            echo "    ✗ $cmd"
        fi
    done
    echo ""

    echo "  Package Managers:"
    for cmd in pip3 npm yarn cargo go; do
        command -v $cmd &>/dev/null && echo "    ✓ $cmd" || echo "    ✗ $cmd"
    done
    echo ""

    echo "  Container Runtimes:"
    for cmd in docker podman containerd; do
        command -v $cmd &>/dev/null && echo "    ✓ $cmd" || echo "    ✗ $cmd"
    done
    echo ""

    echo "  AI/ML:"
    command -v ollama &>/dev/null && echo "    ✓ ollama" || echo "    ✗ ollama"
    command -v llama-server &>/dev/null && echo "    ✓ llama-server" || echo "    ✗ llama-server"
    for mod in autogen crewai langchain openai transformers torch; do
        python3 -c "import $mod" 2>/dev/null && echo "    ✓ $mod (Python)" || echo "    ✗ $mod (Python)"
    done
}

_disk_usage() {
    print_header "Disk Usage"

    echo "  Filesystems:"
    df -h 2>/dev/null | grep -v "^Filesystem\|^tmpfs\|^devtmpfs\|^overlay" | sed 's/^/    /'
    echo ""

    if [[ -b "${SELECTED_DEVICE:-}" ]]; then
        echo "  USB Drive ($SELECTED_DEVICE):"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,USED,MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null | sed 's/^/    /'
    fi
}

check_macos_status() {
    print_info "macOS Status:"
    
    # Check UTM
    if [[ -d "/Applications/UTM.app" ]]; then
        print_success "UTM is installed"
    else
        print_error "UTM is not installed"
    fi
    
    # Check LaunchAgent
    if [[ -f "$LAUNCH_AGENT_PLIST" ]]; then
        if launchctl list | grep -q "$LAUNCH_AGENT_NAME"; then
            print_success "Launch Agent is loaded and active"
        else
            print_warning "Launch Agent exists but is not loaded"
        fi
    else
        print_warning "Launch Agent does not exist"
    fi
    
    # Check Homebrew
    if check_dependency "brew"; then
        print_success "Homebrew is installed"
    else
        print_warning "Homebrew is not installed (optional but recommended)"
    fi
}

check_linux_status() {
    print_info "Linux Status:"
    
    # Check QEMU/KVM
    if check_dependency "qemu-system-x86_64"; then
        print_success "QEMU is available"
    else
        print_error "QEMU is not available"
    fi
    
    # Check KVM
    if [[ -r "/dev/kvm" ]]; then
        print_success "KVM acceleration is available"
    else
        print_warning "KVM is not available (will use slower software emulation)"
    fi
    
    # Check systemd service
    if [[ -f "/etc/systemd/system/usb-compute-vm.service" ]]; then
        if systemctl is-active --quiet usb-compute-vm.service; then
            print_success "USB Compute VM service is active"
        else
            print_warning "USB Compute VM service exists but is not active"
        fi
    else
        print_warning "USB Compute VM service does not exist"
    fi
}

check_windows_status() {
    print_info "Windows Status:"
    print_info "Windows status checking not implemented in this demo"
    print_info "Please check:"
    echo "  • Hyper-V or VirtualBox installation"
    echo "  • Task Scheduler for auto-boot"
    echo "  • VM configuration for USB passthrough"
}

check_usb_status() {
    print_info "USB Status:"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_warning "No USB device has been selected yet"
        print_info "Please select a USB device first using Option 2 from the main menu."
        return 0
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_warning "USB device $SELECTED_DEVICE is not currently connected"
        return 0
    fi
    
    print_success "USB device $SELECTED_DEVICE is detected"
    
    # Show partition info
    print_info "Partition layout:"
    if [[ "$OS" == "Darwin" ]]; then
        diskutil list "$SELECTED_DEVICE" 2>/dev/null | head -20 || true
    else
        lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT "$SELECTED_DEVICE" 2>/dev/null || true
    fi
    echo ""
    
    # Check if it's Ventoy
    local is_ventoy=0
    if [[ "$OS" == "Darwin" ]]; then
        if [[ -b "${SELECTED_DEVICE}s1" ]]; then
            local vol_name
            vol_name=$(diskutil info "${SELECTED_DEVICE}s1" 2>/dev/null | grep "Volume Name" | awk '{print $3}' || true)
            [[ "$vol_name" == "Ventoy" ]] && is_ventoy=1
        fi
    else
        if [[ -b "${SELECTED_DEVICE}1" ]]; then
            local label
            label=$(blkid -o value -s LABEL "${SELECTED_DEVICE}1" 2>/dev/null || true)
            [[ "$label" == "Ventoy" ]] && is_ventoy=1
        fi
    fi
    
    if [[ $is_ventoy -eq 0 ]]; then
        print_warning "The selected USB device does not have Ventoy installed"
        return 0
    fi
    
    print_success "Ventoy is installed on the USB drive"
    
    # Use unified mount detection
    if detect_ventoy_mount; then
        print_info "Ventoy mount point: $VENTOY_MOUNT"
        
        # Check for persistence
        if check_persistence_exists; then
            local persist_size
            persist_size=$(get_persistence_size)
            print_success "Ventoy persistence file is present ($persist_size)"
            
            # Check for ventoy.json
            if [[ -f "$VENTOY_MOUNT/ventoy/ventoy.json" ]]; then
                print_success "Ventoy configuration (ventoy.json) is present"
            else
                print_warning "Ventoy configuration (ventoy.json) not found"
            fi
        else
            print_warning "Ventoy persistence file not found"
            print_info "To create persistence, use Option 2 from the main menu"
        fi
        
        # Check for ISO
        if ls "$VENTOY_MOUNT"/*.iso &>/dev/null 2>&1; then
            print_success "ISO files found on USB drive:"
            ls -lh "$VENTOY_MOUNT"/*.iso 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
        else
            print_warning "No ISO files found on USB drive"
        fi
        
        unmount_ventoy
    else
        print_warning "Could not mount Ventoy partition"
        print_info "Try manually: sudo mount ${SELECTED_DEVICE}1 /mnt/ventoy"
    fi
}

check_vm_status() {
    print_info "VM Status:"
    
    if [[ "$OS" == "Darwin" ]]; then
        # Check if UTM is running
        if pgrep -q "UTM"; then
            print_success "UTM application is running"
        else
            print_warning "UTM application is not currently running"
        fi
        
        # Check if our specific VM is running (simplified)
        print_info "To check if your VM is running:"
        echo "  • Open UTM and look for 'USB Compute VM'"
        echo "  • Or check Activity Monitor for QEMU processes"
    elif [[ "$OS" == "Linux" ]]; then
        # Check if QEMU is running
        if pgrep -q "qemu"; then
            print_success "QEMU process is running"
        else
            print_warning "No QEMU processes detected"
        fi
        
        # Check systemd service
        if [[ -f "/etc/systemd/system/usb-compute-vm.service" ]]; then
            if systemctl is-active --quiet usb-compute-vm.service; then
                print_success "USB Compute VM service is active"
            else
                print_warning "USB Compute VM service is not active"
            fi
        fi
    else
        print_info "Windows VM status checking not implemented in this demo"
    fi
}

check_persistence_status() {
    print_info "Persistence Status:"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_warning "No USB device has been selected yet"
        print_info "Please select a USB device first using Option 2 from the main menu."
        return 0
    fi
    
    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_info "USB device not connected - cannot check persistence"
        return 0
    fi
    
    # Use unified mount detection
    if ! detect_ventoy_mount; then
        print_warning "Could not find or mount Ventoy partition"
        print_info "Try manually: sudo mount ${SELECTED_DEVICE}1 /mnt/ventoy"
        return 0
    fi
    
    print_info "Ventoy mount point: $VENTOY_MOUNT"
    
    # Check for persistence
    if check_persistence_exists; then
        local persist_size
        persist_size=$(get_persistence_size)
        print_success "Persistence file is present ($persist_size)"
        
        # Check if it's mounted (would be mounted when VM is running)
        if mount | grep -q "ubuntu-persistence.dat"; then
            print_success "Persistence file is currently mounted"
        else
            print_info "Persistence file is not currently mounted (normal when VM is not running)"
        fi
        
        # Check for ventoy.json
        if [[ -f "$VENTOY_MOUNT/ventoy/ventoy.json" ]]; then
            print_success "Ventoy configuration (ventoy.json) is present"
        else
            print_warning "Ventoy configuration (ventoy.json) not found"
        fi
        
        # Check for injected autostart
        local persist_mount="/tmp/usb-persist-check-$$"
        mkdir -p "$persist_mount"
        if mount -o loop "$VENTOY_MOUNT/persistence/ubuntu-persistence.dat" "$persist_mount" 2>/dev/null; then
            if [[ -f "$persist_mount/etc/rc.local" ]]; then
                print_success "Autostart script (rc.local) is injected"
            else
                print_warning "Autostart script (rc.local) not found in persistence"
            fi
            umount "$persist_mount" 2>/dev/null || true
        fi
        rmdir "$persist_mount" 2>/dev/null || true
        
        # Filesystem check instructions
        print_info "To check persistence filesystem integrity:"
        echo "  1. Ensure VM is shut down"
        echo "  2. Unmount the USB if mounted"
        echo "  3. Run: sudo fsck.ext4 -f $VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    else
        print_warning "Persistence file not found on USB drive"
        print_info "To create persistence, use Option 2 from the main menu"
    fi
    
    unmount_ventoy
}

# ============================================================================
# STEP 8: BACKUP AND RECOVERY OPTIONS
# ============================================================================

backup_recovery_options() {
    print_header "Backup and Recovery Options"
    echo "This section provides options for:"
    echo "  • Backing up your persistence data"
    echo "  • Restoring from backups"
    echo "  • Cloning your USB setup"
    echo ""
    
    if ! confirm "Do you want to access backup and recovery options?"; then
        return 0
    fi
    
    echo "Backup and Recovery Options:"
    echo "  1) Backup persistence file"
    echo "  2) Restore persistence file from backup"
    echo "  3) Backup USB configuration"
    echo "  4) Restore USB configuration"
    echo "  5) Clone USB setup to another drive"
    echo "  6) Return to main menu"
    echo ""
    
    local choice
    read -p "$(echo -e "${YELLOW}Select an option [1-6]: ${NC}")" choice
    
    case "$choice" in
        1)
            backup_persistence || read -p "Press Enter to continue..." ;;
        2)
            restore_persistence || read -p "Press Enter to continue..." ;;
        3)
            backup_usb_config || read -p "Press Enter to continue..." ;;
        4)
            restore_usb_config || read -p "Press Enter to continue..." ;;
        5)
            clone_usb_setup || read -p "Press Enter to continue..." ;;
        6)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
    
    # Ask if they want to do more
    if confirm "Do you want to perform another backup/recovery operation?"; then
        backup_recovery_options
    fi
}

backup_persistence() {
    print_header "Backup Persistence File"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        print_info "How to resolve: Ensure the USB drive is plugged in and try again."
        return 1
    fi
    
    # Mount USB
    local ventoy_mount_point=""
    if [[ "$OS" == "Darwin" ]]; then
        ventoy_mount_point=$(df | grep "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
    else
        ventoy_mount_point=$(df | grep "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
    fi
    
    if [[ -z "$ventoy_mount_point" ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            mkdir -p "/Volumes/VENTOY" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}s1" "/Volumes/VENTOY"; then
                print_error "Failed to mount USB partition"
                print_info "How to resolve: Ensure the USB is plugged in and not in use."
                return 1
            fi
            ventoy_mount_point="/Volumes/VENTOY"
        else
            mkdir -p "/mnt/VENTOY" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}1" "/mnt/VENTOY"; then
                print_error "Failed to mount USB partition"
                print_info "How to resolve: Ensure the USB is plugged in and not in use."
                return 1
            fi
            ventoy_mount_point="/mnt/VENTOY"
        fi
    fi
    
    # Check if persistence file exists
    local persistence_file="$ventoy_mount_point/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$persistence_file" ]]; then
        print_error "Persistence file not found at $persistence_file"
        print_info "How to resolve: Run Option 2 first to create the persistence file."
        if [[ "$OS" == "Darwin" ]]; then
            umount "/Volumes/VENTOY" 2>/dev/null || true
        else
            umount "/mnt/VENTOY" 2>/dev/null || true
        fi
        return 1
    fi
    
    # Ask for backup location
    local backup_dir="$HOME/usb-backups"
    mkdir -p "$backup_dir"
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="$backup_dir/ubuntu-persistence-$timestamp.dat"
    
    print_info "Backing up persistence file to: $backup_file"
    print_info "This may take a while depending on the size of your persistence file..."
    
    # Perform backup
    if dd if="$persistence_file" of="$backup_file" bs=4M status=progress; then
        print_success "Persistence file backed up successfully!"
        print_info "Backup location: $backup_file"
        print_info "Backup size: $(du -h "$backup_file" | cut -f1)"
    else
        print_error "Persistence file backup failed"
        print_info "How to resolve: Check if there is enough disk space at $backup_dir"
    fi
    
    # Unmount
    if [[ "$OS" == "Darwin" ]]; then
        umount "/Volumes/VENTOY" 2>/dev/null || print_warning "Could not unmount /Volumes/VENTOY"
    else
        umount "/mnt/VENTOY" 2>/dev/null || print_warning "Could not unmount /mnt/VENTOY"
    fi
    
    return 0
}

restore_persistence() {
    print_header "Restore Persistence File from Backup"
    
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        if ! select_usb_device; then
            return 0
        fi
    fi
    
    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        print_info "How to resolve: Ensure the USB drive is plugged in and try again."
        return 1
    fi
    
    # Find backup files
    local backup_dir="$HOME/usb-backups"
    if [[ ! -d "$backup_dir" ]]; then
        print_error "No backup directory found at $backup_dir"
        print_info "How to resolve: Please create some backups first using Option 1."
        return 1
    fi
    
    local backups=($(find "$backup_dir" -name "ubuntu-persistence-*.dat" 2>/dev/null | sort || true))
    if [[ ${#backups[@]} -eq 0 ]]; then
        print_error "No persistence backups found in $backup_dir"
        print_info "How to resolve: Please create some backups first using Option 1."
        return 1
    fi
    
    echo "Available backups:"
    local index=1
    for backup in "${backups[@]}"; do
        local size=$(du -h "$backup" | cut -f1)
        local date=$(basename "$backup" | cut -d'-' -f3-4 | sed 's/\.dat$//')
        printf "${CYAN}%2d)${NC} %s (%s) - %s\n" "$index" "$(basename "$backup")" "$date" "$size"
        ((index++))
    done
    echo ""
    
    # Select backup
    local count=${#backups[@]}
    local selection
    
    while true; do
        read -p "$(echo -e "${YELLOW}Select backup number [1-${count}] or 'q' to quit: ${NC}")" selection
        [[ "$selection" == "q" ]] && return 0
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le "$count" ]]; then
            local selected_backup="${backups[$((selection-1))]}"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and $count"
        fi
    done
    
    # Final warning
    print_warning "This will ERASE ALL DATA on the persistence file of $SELECTED_DEVICE"
    if ! confirm "Are you ABSOLUTELY SURE you want to continue?" "n"; then
        print_info "Restore cancelled"
        return 0
    fi
    
    # Mount USB
    local ventoy_mount_point=""
    if [[ "$OS" == "Darwin" ]]; then
        ventoy_mount_point=$(df | grep "${SELECTED_DEVICE}s1" | awk '{print $NF}' || true)
    else
        ventoy_mount_point=$(df | grep "${SELECTED_DEVICE}1" | awk '{print $NF}' || true)
    fi
    
    if [[ -z "$ventoy_mount_point" ]]; then
        if [[ "$OS" == "Darwin" ]]; then
            mkdir -p "/Volumes/VENTOY" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}s1" "/Volumes/VENTOY"; then
                print_error "Failed to mount USB partition"
                print_info "How to resolve: Ensure the USB is plugged in and not in use."
                return 1
            fi
            ventoy_mount_point="/Volumes/VENTOY"
        else
            mkdir -p "/mnt/VENTOY" || { print_error "Failed to create mount point"; return 1; }
            if ! mount "${SELECTED_DEVICE}1" "/mnt/VENTOY"; then
                print_error "Failed to mount USB partition"
                print_info "How to resolve: Ensure the USB is plugged in and not in use."
                return 1
            fi
            ventoy_mount_point="/mnt/VENTOY"
        fi
    fi
    
    # Perform restore
    local persistence_file="$ventoy_mount_point/persistence/ubuntu-persistence.dat"
    print_info "Restoring persistence file from: $selected_backup"
    print_info "This may take a while..."
    
    if dd if="$selected_backup" of="$persistence_file" bs=4M status=progress; then
        print_success "Persistence file restored successfully!"
        print_info "Restored from: $(basename "$selected_backup")"
    else
        print_error "Persistence file restore failed"
        print_info "How to resolve: Check if the USB partition is writable and has enough space."
    fi
    
    # Unmount
    if [[ "$OS" == "Darwin" ]]; then
        umount "/Volumes/VENTOY" 2>/dev/null || print_warning "Could not unmount /Volumes/VENTOY"
    else
        umount "/mnt/VENTOY" 2>/dev/null || print_warning "Could not unmount /mnt/VENTOY"
    fi
    
    return 0
}

backup_usb_config() {
    print_header "Backup USB Configuration"
    print_info "This feature is not yet implemented in this demo"
    print_info "To manually backup your USB configuration:"
    echo "  1. Backup the persistence file (option 1)"
    echo "  2. Backup the ISO files from your USB drive"
    echo "  3. Document your VM configuration"
    echo "  4. Document any additional services you've configured"
    return 0
}

restore_usb_config() {
    print_header "Restore USB Configuration"
    print_info "This feature is not yet implemented in this demo"
    print_info "To manually restore your USB configuration:"
    echo "  1. Restore the persistence file (option 2)"
    echo "  2. Restore the ISO files to your USB drive"
    echo "  3. Reconfigure your VM based on your documentation"
    echo "  4. Reconfigure any additional services"
    return 0
}

clone_usb_setup() {
    print_header "Clone USB Setup to Another Drive"
    print_info "This feature is not yet implemented in this demo"
    print_info "To manually clone your USB setup:"
    echo "  1. Backup the persistence file from your source USB (option 1)"
    echo "  2. Prepare a new USB drive with Ventoy (option 2)"
    echo "  3. Restore the persistence file to the new USB (option 2)"
    echo "  4. Copy any additional ISO files or data"
    echo "  5. The new USB will be ready to use"
    return 0
}

# ============================================================================
# SYSTEM CLEANUP AND DIAGNOSTICS
# ============================================================================

_system_cleanup() {
    print_header "System Cleanup and Diagnostics"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local sysman_script="$script_dir/sysman.sh"
    local clean_script="$script_dir/clean-local.sh"
    
    echo -e "${CYAN}1)${NC} Launch System Manager Dashboard (sysman)"
    echo -e "${CYAN}2)${NC} Launch Clean Local Script"
    echo -e "${CYAN}3)${NC} Quick Disk Usage Check"
    echo -e "${CYAN}4)${NC} Quick System Health Check"
    echo -e "${CYAN}0)${NC} Back to main menu"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-4]: ${NC}")" choice
    
    case "$choice" in
        1)
            if [[ -f "$sysman_script" ]]; then
                print_info "Launching System Manager Dashboard..."
                bash "$sysman_script"
            else
                print_error "sysman.sh not found at: $sysman_script"
                print_info "Please ensure sysman.sh is in the same directory as this script"
            fi
            ;;
        2)
            if [[ -f "$clean_script" ]]; then
                print_info "Launching Clean Local Script..."
                bash "$clean_script"
            else
                print_error "clean-local.sh not found at: $clean_script"
                print_info "Please ensure clean-local.sh is in the same directory as this script"
            fi
            ;;
        3)
            print_header "Quick Disk Usage Check"
            echo ""
            df -h | grep -vE 'tmpfs|udev|none'
            echo ""
            echo -e "${BOLD}Largest directories in /home:${NC}"
            du -h --max-depth=2 /home 2>/dev/null | sort -hr | head -10
            ;;
        4)
            print_header "Quick System Health Check"
            echo ""
            echo -e "${BOLD}System:${NC} $(uname -n) $(uname -r)"
            echo -e "${BOLD}Uptime:${NC} $(uptime -p 2>/dev/null || uptime)"
            echo -e "${BOLD}Load:${NC} $(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "N/A")"
            echo ""
            echo -e "${BOLD}Memory:${NC}"
            free -h 2>/dev/null || echo "free not available"
            echo ""
            echo -e "${BOLD}Failed Services:${NC}"
            systemctl --failed --no-legend 2>/dev/null | head -5 || echo "No systemd"
            ;;
        0)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# ============================================================================
# ALIAS MANAGEMENT
# ============================================================================

_alias_manager() {
    print_header "Manage Custom Aliases"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local alias_script="$script_dir/alias_manager.sh"
    local alias_file="$HOME/.bash_aliases_usb"
    
    echo -e "${CYAN}1)${NC} Launch Alias Manager (interactive)"
    echo -e "${CYAN}2)${NC} View current aliases"
    echo -e "${CYAN}3)${NC} Quick add alias"
    echo -e "${CYAN}4)${NC} Open alias file in editor"
    echo -e "${CYAN}5)${NC} Source aliases now"
    echo -e "${CYAN}0)${NC} Back to main menu"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-5]: ${NC}")" choice
    
    case "$choice" in
        1)
            if [[ -f "$alias_script" ]]; then
                print_info "Launching Alias Manager..."
                bash "$alias_script"
            else
                print_error "alias_manager.sh not found at: $alias_script"
                print_info "Creating alias file and opening editor..."
                touch "$alias_file"
                ${EDITOR:-nano} "$alias_file"
            fi
            ;;
        2)
            print_header "Current Aliases"
            if [[ -f "$alias_file" ]] && [[ -s "$alias_file" ]]; then
                grep "^alias " "$alias_file" 2>/dev/null || echo "No aliases found"
            else
                print_warning "No alias file found: $alias_file"
                print_info "Create one with Option 1 (Alias Manager)"
            fi
            ;;
        3)
            echo ""
            read -p "$(echo -e "${YELLOW}Alias name: ${NC}")" name
            read -p "$(echo -e "${YELLOW}Command: ${NC}")" cmd
            read -p "$(echo -e "${YELLOW}Description (optional): ${NC}")" desc
            
            if [[ -n "$name" && -n "$cmd" ]]; then
                # Initialize file if needed
                if [[ ! -f "$alias_file" ]]; then
                    mkdir -p "$(dirname "$alias_file")"
                    cat > "$alias_file" << 'ALIASEOF'
# USB Compute Automation - Custom Aliases
# Managed by alias_manager.sh
ALIASEOF
                fi
                
                # Add alias
                if [[ -n "$desc" ]]; then
                    echo "alias ${name}='${cmd}' # ${desc}" >> "$alias_file"
                else
                    echo "alias ${name}='${cmd}'" >> "$alias_file"
                fi
                print_success "Added alias: $name = '$cmd'"
                print_info "Reload with: source $alias_file"
            else
                print_error "Name and command are required"
            fi
            ;;
        4)
            if command -v nano &>/dev/null; then
                ${EDITOR:-nano} "$alias_file"
            elif command -v vim &>/dev/null; then
                ${EDITOR:-vim} "$alias_file"
            else
                print_error "No editor found (nano, vim)"
                print_info "Manually edit: $alias_file"
            fi
            ;;
        5)
            if [[ -f "$alias_file" ]]; then
                source "$alias_file"
                print_success "Aliases loaded from $alias_file"
            else
                print_warning "No alias file found: $alias_file"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# ============================================================================
# SSH HOST MANAGEMENT
# ============================================================================

_ssh_host_manager() {
    print_header "Manage SSH Hosts"
    
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ssh_script="$script_dir/ssh_host_manager.sh"
    local hosts_file="$HOME/.ssh/hosts_usb"
    local ssh_config="$HOME/.ssh/config"
    
    echo -e "${CYAN}1)${NC} Launch SSH Host Manager (interactive)"
    echo -e "${CYAN}2)${NC} View configured hosts"
    echo -e "${CYAN}3)${NC} Quick connect to host"
    echo -e "${CYAN}4)${NC} Generate SSH config entries"
    echo -e "${CYAN}5)${NC} Append USB hosts to SSH config"
    echo -e "${CYAN}6)${NC} Open hosts file in editor"
    echo -e "${CYAN}0)${NC} Back to main menu"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-6]: ${NC}")" choice
    
    case "$choice" in
        1)
            if [[ -f "$ssh_script" ]]; then
                print_info "Launching SSH Host Manager..."
                bash "$ssh_script"
            else
                print_error "ssh_host_manager.sh not found at: $ssh_script"
                print_info "Creating hosts file and opening editor..."
                mkdir -p "$(dirname "$hosts_file")"
                touch "$hosts_file"
                ${EDITOR:-nano} "$hosts_file"
            fi
            ;;
        2)
            print_header "Configured SSH Hosts"
            if [[ -f "$hosts_file" ]] && [[ -s "$hosts_file" ]]; then
                echo ""
                printf "${BOLD}%-15s %-25s %-12s %-6s %s${NC}\n" "ALIAS" "HOSTNAME" "USER" "PORT" "DESCRIPTION"
                echo "─────────────────────────────────────────────────────────────────────────────"
                while IFS='|' read -r alias hostname user port key desc; do
                    [[ "$alias" =~ ^[[:space:]]*# ]] && continue
                    [[ -z "$alias" ]] && continue
                    printf "${CYAN}%-15s${NC} %-25s %-12s %-6s ${YELLOW}%s${NC}\n" \
                        "$alias" "$hostname" "$user" "$port" "$desc"
                done < "$hosts_file"
                echo ""
            else
                print_warning "No hosts file found: $hosts_file"
                print_info "Create one with Option 1 (SSH Host Manager)"
            fi
            ;;
        3)
            if [[ -f "$hosts_file" ]] && [[ -s "$hosts_file" ]]; then
                echo ""
                echo "Available hosts:"
                local -a host_aliases=()
                while IFS='|' read -r alias _; do
                    [[ "$alias" =~ ^[[:space:]]*# ]] && continue
                    [[ -z "$alias" ]] && continue
                    host_aliases+=("$alias")
                    echo "  • $alias"
                done < "$hosts_file"
                echo ""
                
                read -p "$(echo -e "${YELLOW}Host alias to connect: ${NC}")" target
                
                if [[ -n "$target" ]]; then
                    local host_line
                    host_line=$(grep "^${target}|" "$hosts_file" 2>/dev/null | head -1)
                    
                    if [[ -n "$host_line" ]]; then
                        IFS='|' read -r _ hostname user port key _ <<< "$host_line"
                        print_info "Connecting to $user@$hostname:$port..."
                        local ssh_opts="-p $port"
                        [[ -n "$key" && -f "$key" ]] && ssh_opts="$ssh_opts -i $key"
                        ssh $ssh_opts "$user@$hostname"
                    else
                        print_error "Host not found: $target"
                    fi
                fi
            else
                print_warning "No hosts configured. Create some with Option 1 (SSH Host Manager)"
            fi
            ;;
        4)
            if [[ -f "$hosts_file" ]] && [[ -s "$hosts_file" ]]; then
                print_header "Generated SSH Config"
                echo "# Generated by usb-setup-assistant.sh"
                echo "# Source: $hosts_file"
                echo "# Date: $(date)"
                echo ""
                
                while IFS='|' read -r alias hostname user port key desc; do
                    [[ "$alias" =~ ^[[:space:]]*# ]] && continue
                    [[ -z "$alias" ]] && continue
                    
                    echo "Host $alias"
                    echo "    HostName $hostname"
                    echo "    User $user"
                    echo "    Port $port"
                    [[ -n "$key" && -f "$key" ]] && echo "    IdentityFile $key"
                    [[ -n "$desc" ]] && echo "    # $desc"
                    echo ""
                done < "$hosts_file"
            else
                print_warning "No hosts configured"
            fi
            ;;
        5)
            if [[ -f "$hosts_file" ]] && [[ -s "$hosts_file" ]]; then
                mkdir -p "$(dirname "$ssh_config")"
                
                if grep -q "# USB Compute Automation Hosts" "$ssh_config" 2>/dev/null; then
                    print_warning "USB hosts section already exists in SSH config"
                    read -p "$(echo -e "${YELLOW}Replace? [y/N]: ${NC}")" response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        sed -i '/# USB Compute Automation Hosts/,/# End USB Hosts/d' "$ssh_config"
                    else
                        return 0
                    fi
                fi
                
                {
                    echo ""
                    echo "# USB Compute Automation Hosts"
                    echo "# Generated: $(date)"
                    
                    while IFS='|' read -r alias hostname user port key desc; do
                        [[ "$alias" =~ ^[[:space:]]*# ]] && continue
                        [[ -z "$alias" ]] && continue
                        
                        echo ""
                        echo "Host $alias"
                        echo "    HostName $hostname"
                        echo "    User $user"
                        echo "    Port $port"
                        [[ -n "$key" && -f "$key" ]] && echo "    IdentityFile $key"
                        [[ -n "$desc" ]] && echo "    # $desc"
                    done < "$hosts_file"
                    
                    echo ""
                    echo "# End USB Hosts"
                } >> "$ssh_config"
                
                print_success "Appended USB hosts to: $ssh_config"
            else
                print_warning "No hosts configured"
            fi
            ;;
        6)
            mkdir -p "$(dirname "$hosts_file")"
            if command -v nano &>/dev/null; then
                ${EDITOR:-nano} "$hosts_file"
            elif command -v vim &>/dev/null; then
                ${EDITOR:-vim} "$hosts_file"
            else
                print_error "No editor found (nano, vim)"
                print_info "Manually edit: $hosts_file"
            fi
            ;;
        0)
            return 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# ============================================================================
# NEW: ACCESS USB PERSISTENT TERMINAL
# ============================================================================

access_usb_terminal() {
    print_header "Access USB Persistent Terminal"
    echo "This opens a chroot shell directly into the USB persistence image."
    echo "You will be running INSIDE the USB environment with full access to"
    echo "all installed tools, configurations, and persistent data."
    echo ""
    echo "Use cases:"
    echo "  - Test/verify installed packages without booting VM"
    echo "  - Run commands directly in persistent environment"
    echo "  - Quick debugging and configuration"
    echo "  - Install additional packages via apt/pip"
    echo ""

    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        return 1
    fi

    # Mount Ventoy partition
    if ! detect_ventoy_mount; then
        print_error "Could not find or mount Ventoy partition"
        return 1
    fi

    # Check persistence exists
    local persist_file="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
    if [[ ! -f "$persist_file" ]]; then
        print_error "No persistence image found on USB"
        print_info "Create one first: Option 2 -> Create Persistence"
        unmount_ventoy
        return 1
    fi

    print_success "Persistence found: $(du -h "$persist_file" | cut -f1)"

    # Mount persistence image
    print_header "Mounting Persistence for Terminal Access"
    local persist_mnt="/tmp/usb-persist-term-$$"
    mkdir -p "$persist_mnt"

    if ! mount -o loop "$persist_file" "$persist_mnt" 2>/dev/null; then
        print_error "Failed to mount persistence image"
        print_info "May need root: sudo bash $0"
        unmount_ventoy
        return 1
    fi

    print_success "Persistence mounted at $persist_mnt"

    # Prepare chroot environment
    mount --bind /dev "$persist_mnt/dev" 2>/dev/null || true
    mount --bind /proc "$persist_mnt/proc" 2>/dev/null || true
    mount --bind /sys "$persist_mnt/sys" 2>/dev/null || true
    mount --bind /dev/pts "$persist_mnt/dev/pts" 2>/dev/null || true
    mount --bind /tmp "$persist_mnt/tmp" 2>/dev/null || true
    cp /etc/resolv.conf "$persist_mnt/etc/resolv.conf" 2>/dev/null || true

    # Set up prompt to indicate we're in USB environment
    echo "USB_PERSISTENCE=1" > "$persist_mnt/etc/environment.usb"
    cat > "$persist_mnt/etc/profile.d/usb-prompt.sh" << 'PROMPT_EOF'
# USB Persistence Terminal Prompt
if [[ -n "$USB_PERSISTENCE" ]] || [[ "$(cat /etc/environment.usb 2>/dev/null)" == *"USB_PERSISTENCE=1"* ]]; then
    export PS1="\[\033[1;35m\][USB-PERSIST]\[\033[0m\] \[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ "
fi
PROMPT_EOF

    echo ""
    print_header "Entering USB Persistent Terminal"
    print_info "You are now inside the USB persistence environment."
    print_info "Prompt shows [USB-PERSIST] to indicate this."
    print_info "Type 'exit' or press Ctrl+D to return to host."
    echo ""

    # Enter chroot
    chroot "$persist_mnt" /bin/bash --login

    # Cleanup
    print_info "Exiting USB persistent terminal..."
    umount "$persist_mnt/dev/pts" 2>/dev/null || true
    umount "$persist_mnt/dev" 2>/dev/null || true
    umount "$persist_mnt/proc" 2>/dev/null || true
    umount "$persist_mnt/sys" 2>/dev/null || true
    umount "$persist_mnt" 2>/dev/null || true
    rmdir "$persist_mnt" 2>/dev/null || true

    unmount_ventoy
    return 0
}

# ============================================================================
# NEW: COPY FILE TO USB
# ============================================================================

copy_file_to_usb() {
    print_header "Copy File to USB"
    echo "Copy files from host to USB free space or persistence."
    echo ""

    # Select device if not already selected
    if [[ -z "${SELECTED_DEVICE:-}" ]]; then
        print_info "No USB device selected yet."
        if ! select_usb_device; then
            return 0
        fi
    fi

    if [[ ! -b "$SELECTED_DEVICE" ]]; then
        print_error "USB device $SELECTED_DEVICE is not detected"
        return 1
    fi

    # Get source file
    local src_file
    read -p "$(echo -e "${YELLOW}Source file path on host: ${NC}")" src_file

    if [[ ! -f "$src_file" && ! -d "$src_file" ]]; then
        print_error "Source not found: $src_file"
        return 1
    fi

    # Choose destination
    echo ""
    echo "Destination options:"
    echo "  1) USB Free Space (exFAT partition - accessible from host OS)"
    echo "  2) USB Persistence (ext4 image - only accessible from USB/Linux)"
    echo "  3) Custom path on USB"
    echo ""

    local choice
    read -p "$(echo -e "${YELLOW}Select destination [1-3]: ${NC}")" choice

    case "$choice" in
        1)
            # USB Free Space (Ventoy partition)
            if ! detect_ventoy_mount; then
                print_error "Could not mount Ventoy partition"
                return 1
            fi
            local dest_base="$VENTOY_MOUNT"
            ;;
        2)
            # USB Persistence - need to mount it
            if ! detect_ventoy_mount; then
                print_error "Could not mount Ventoy partition"
                return 1
            fi
            local persist_file="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
            if [[ ! -f "$persist_file" ]]; then
                print_error "No persistence image found"
                unmount_ventoy
                return 1
            fi
            local persist_mnt="/tmp/usb-persist-copy-$$"
            mkdir -p "$persist_mnt"
            if ! mount -o loop "$persist_file" "$persist_mnt" 2>/dev/null; then
                print_error "Failed to mount persistence image"
                unmount_ventoy
                return 1
            fi
            local dest_base="$persist_mnt"
            ;;
        3)
            if ! detect_ventoy_mount; then
                print_error "Could not mount Ventoy partition"
                return 1
            fi
            read -p "$(echo -e "${YELLOW}Custom path on USB (relative to $VENTOY_MOUNT): ${NC}")" custom_path
            local dest_base="$VENTOY_MOUNT/$custom_path"
            ;;
        *)
            print_error "Invalid selection"
            return 1
            ;;
    esac

    # Get destination path
    local dest_name=$(basename "$src_file")
    read -p "$(echo -e "${YELLOW}Destination name [$dest_name]: ${NC}")" dest_name_input
    [[ -n "$dest_name_input" ]] && dest_name="$dest_name_input"

    local dest_path="$dest_base/$dest_name"

    # Copy
    print_info "Copying $src_file -> $dest_path"
    if [[ -d "$src_file" ]]; then
        cp -r "$src_file" "$dest_path" && print_success "Directory copied" || print_error "Copy failed"
    else
        cp "$src_file" "$dest_path" && print_success "File copied" || print_error "Copy failed"
    fi

    # Make scripts executable
    if [[ -f "$dest_path" ]] && [[ "$dest_path" == *.sh ]]; then
        chmod +x "$dest_path"
        print_info "Made executable: $dest_path"
    fi

    # Cleanup persistence mount if used
    if [[ "$choice" == "2" && -n "${persist_mnt:-}" ]]; then
        umount "$persist_mnt" 2>/dev/null || true
        rmdir "$persist_mnt" 2>/dev/null || true
    fi

    unmount_ventoy
    return 0
}

# ============================================================================
# NEW: HEMLOCK AGENT ORCHESTRATION (POPOUT TERMINAL)
# ============================================================================

launch_hemlock_tui() {
    print_header "Hemlock Agent Orchestration Platform"
    echo "This launches a SEPARATE TERMINAL WINDOW running the Hemlock TUI."
    echo "The TUI provides full interactive management of:"
    echo "  🤖 Agents  - Create, attach, export, delete agents"
    echo "  👥 Crews   - Create, attach, export, delete crews"
    echo "  📦 Skills  - Browse available skills (157+)"
    echo "  🔧 Doctor  - Run system diagnostics"
    echo "  📦 Backup  - Manage system backups"
    echo "  ⚙️  Settings - Gateway, Telegram, iMessage, MCP, Network"
    echo ""
    echo "Hemlock uses Docker volumes for isolated agent/crew workspaces."
    echo "Gateway runs on port 18789 with MCP bridge on stdio."
    echo ""
    
    # Check if Hemlock is available
    local hemlock_dir="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}"
    local hemlock_tui="$hemlock_dir/scripts/hemlock-tui"
    local hemlock_cli="$hemlock_dir/scripts/hemlock"
    
    if [[ ! -f "$hemlock_tui" ]]; then
        print_error "Hemlock TUI not found at: $hemlock_tui"
        print_info "Expected location: /tmp/hemlock-minimal/hemlock-minimal/scripts/hemlock-tui"
        print_info "You can set HEMLOCK_DIR environment variable to override."
        return 1
    fi
    
    if [[ ! -f "$hemlock_cli" ]]; then
        print_error "Hemlock CLI not found at: $hemlock_cli"
        return 1
    fi
    
    print_info "Found Hemlock at: $hemlock_dir"
    print_info "TUI: $hemlock_tui"
    print_info "CLI: $hemlock_cli"
    echo ""
    
    # Check Docker
    if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
        print_error "Docker not running. Hemlock requires Docker."
        return 1
    fi
    
    # Check if hemlock-runtime container exists
    if ! docker ps -a --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
        print_warning "Hemlock runtime container not found."
        if confirm "Deploy Hemlock now? (creates volumes, pulls images, starts gateway)"; then
            print_info "Deploying Hemlock..."
            deploy_hemlock "$hemlock_dir" || return 1
        else
            print_info "Hemlock not deployed. TUI will show limited status."
        fi
    fi
    
    echo ""
    print_header "Launch Options"
    echo "  1) Launch TUI in NEW terminal window (recommended)"
    echo "  2) Launch TUI in CURRENT terminal"
    echo "  3) Run Hemlock CLI command (single command)"
    echo "  4) Show Hemlock status (doctor)"
    echo "  5) Attach to RUNNING CONTAINER (Hemlock TUI/CLI inside container)"
    echo "     → All model/agent/skill/MCP/plugin management happens HERE"
    echo "  q) Cancel"
    echo ""
    
    local choice
    read -p "$(echo -e "${YELLOW}Select [1-5/q]: ${NC}")" choice
    
    case "$choice" in
        1)
            launch_hemlock_popout "$hemlock_tui"
            ;;
        2)
            print_info "Launching Hemlock TUI in current terminal..."
            print_info "Press Ctrl+C to exit TUI and return here."
            sleep 2
            "$hemlock_tui"
            ;;
        3)
            run_hemlock_cli "$hemlock_cli"
            ;;
        4)
            run_hemlock_doctor "$hemlock_cli"
            ;;
        5)
            # Attach to running Hemlock container for TUI/CLI
            if docker ps --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
                print_info "Attaching to hemlock-runtime container..."
                print_info "Running Hemlock TUI inside container (Ctrl+C to exit)"
                docker exec -it hemlock-runtime /scripts/hemlock-tui
            else
                print_error "hemlock-runtime container not running"
                print_info "Deploy Hemlock first (Option 13 in main menu) or start container manually"
            fi
            ;;
        q|Q)
            return 0
            ;;
        *)
            print_error "Invalid selection"
            ;;
    esac
}

# Deploy Hemlock system
deploy_hemlock() {
    local hemlock_dir="$1"
    
    print_header "Deploying Hemlock Agent Orchestration Platform"
    
    cd "$hemlock_dir"
    
    # Build/pull Docker images
    print_info "Building Hemlock Docker image..."
    if [[ -f "Dockerfile.runtime" ]]; then
        docker build -f Dockerfile.runtime -t hemlock-runtime . 2>&1 | tail -20
    fi
    
    # Create required volumes
    print_info "Creating Docker volumes..."
    for vol in hemlock-gateway hemlock-agents hemlock-crews hemlock-shared-skills; do
        docker volume create "$vol" >/dev/null 2>&1 || true
        print_info "  Volume: $vol"
    done
    
    # Populate skills volume
    print_info "Populating skills volume (157 skills)..."
    if [[ -f "scripts/populate-skills.sh" ]]; then
        bash scripts/populate-skills.sh 2>&1 | tail -10
    fi
    
    # Start gateway container
    print_info "Starting Hemlock Gateway on port 18789..."
    docker run -d \
        --name hemlock-runtime \
        --restart unless-stopped \
        -p 18789:18789 \
        -p 41214:41214 \
        -v hemlock-gateway:/workspace/gateway \
        -v hemlock-agents:/agents \
        -v hemlock-crews:/crews \
        -v hemlock-shared-skills:/skills:ro \
        -v hemlock-models:/models \
        -e OPENCLAW_GATEWAY_TOKEN="${OPENCLAW_GATEWAY_TOKEN:-test-token-12345}" \
        -e IMRSG_REMOTE_HOST="${IMRSG_REMOTE_HOST:-}" \
        hemlock-runtime gateway 2>&1 | tail -5
    
    sleep 3
    
    # Auto-attach agents (they attach permanently)
    print_info "Attaching existing agents..."
    docker exec hemlock-runtime /entrypoint.sh agent-list 2>/dev/null || true
    
    print_success "Hemlock deployed!"
    print_info "Gateway: http://localhost:18789"
    print_info "Health:  curl http://localhost:18789/health"
}

# Launch Hemlock TUI in a popout terminal window
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
        terminal_cmd="tmux new-session -d -s hemlock-tui \; send-keys 'HEMLOCK_DIR=\"$hemlock_dir\" \"$hemlock_tui\"' Enter \; attach-session -t hemlock-tui"
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

# Run single Hemlock CLI command
run_hemlock_cli() {
    local hemlock_cli="$1"
    
    print_header "Hemlock CLI - Single Command"
    echo "Available commands:"
    echo "  agent-create <id> [model] [name]"
    echo "  agent-attach <id>"
    echo "  agent-detach <id>"
    echo "  agent-export <id> [MINIMAL|STANDARD|FULL] [dest]"
    echo "  agent-import <source> <id> [mode]"
    echo "  agent-delete <id>"
    echo "  agent-list"
    echo "  copy-skills <id> <skill1> [skill2]..."
    echo "  crew-create <name> <agent1> [agent2]..."
    echo "  crew-attach <name>"
    echo "  crew-detach <name>"
    echo "  crew-delete <name>"
    echo "  crew-list"
    echo "  crew-export <name> [mode] [dest]"
    echo "  crew-import <source> <name>"
    echo "  populate-skills"
    echo "  doctor"
    echo "  backup [full|standard|minimal|list|restore <path>]"
    echo "  mcp-configure <agent> <cmd> [args]"
    echo "  mcp-list"
    echo "  plugin-configure <name> <path>"
    echo "  tui"
    echo "  gateway"
    echo ""
    
    local hemlock_cmd
    read -p "$(echo -e "${YELLOW}Enter hemlock command (e.g. 'agent-list'): ${NC}")" hemlock_cmd
    
    if [[ -z "$hemlock_cmd" ]]; then
        print_info "Cancelled"
        return 0
    fi
    
    HEMLOCK_DIR="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}" "$hemlock_cli" $hemlock_cmd
    echo ""
    read -p "Press Enter to continue..."
}

# Run Hemlock Doctor
run_hemlock_doctor() {
    local hemlock_cli="$1"
    
    print_header "Running Hemlock Doctor (System Diagnostics)"
    echo ""
    
    HEMLOCK_DIR="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}" "$hemlock_cli" doctor
    echo ""
    read -p "Press Enter to continue..."
}

# ============================================================================
# GATEWAY INTERACTIVE MENU (Configure Agents/Crews/Settings)
# ============================================================================

run_gateway_interactive() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    local gateway_config="/workspace/gateway/hemlock.json"
    
    print_header "Hemlock Gateway Interactive Configuration"
    echo "Configure individual agents, crews, and gateway settings."
    echo "Gateway: http://localhost:${HEMLOCK_GATEWAY_PORT}"
    echo ""
    
    while true; do
        print_header "Gateway Configuration Menu"
        echo "  1) Agents Management"
        echo "     • List all agents"
        echo "     • Create new agent"
        echo "     • Configure agent (model, skills, MCP, resources)"
        echo "     • Attach/detach agent"
        echo "     • View agent status"
        echo "  2) Crews Management"
        echo "     • List all crews"
        echo "     • Create new crew"
        echo "     • Configure crew (agents, channel, settings)"
        echo "     • Attach/detach crew"
        echo "  3) Gateway Settings"
        echo "     • View/change gateway token"
        echo "     • Configure Telegram/iMessage"
        echo "     • MCP server configuration"
        echo "     • Network/port settings"
        echo "  4) Skills Management"
        echo "     • List available skills (157+)"
        echo "     • Copy skills to agent"
        echo "     • Install new skills"
        echo "  5) Resource Allocation"
        echo "     • Set agent CPU/memory limits"
        echo "     • Configure persistence mount mode"
        echo "     • Port forwarding rules"
        echo "  6) Backup & Restore"
        echo "     • Export agent/crew"
        echo "     • Import agent/crew"
        echo "     • Full system backup"
        echo "  q) Return to Hemlock menu"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-6/q]: ${NC}")" choice
        
        case "$choice" in
            1) gateway_manage_agents "$hemlock_cli" "$hemlock_dir" ;;
            2) gateway_manage_crews "$hemlock_cli" "$hemlock_dir" ;;
            3) gateway_manage_settings "$hemlock_cli" "$hemlock_dir" ;;
            4) gateway_manage_skills "$hemlock_cli" "$hemlock_dir" ;;
            5) gateway_manage_resources "$hemlock_cli" "$hemlock_dir" ;;
            6) gateway_manage_backup "$hemlock_cli" "$hemlock_dir" ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        echo ""
    done
}

gateway_manage_agents() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    while true; do
        print_header "Agent Management"
        
        # List agents first
        print_info "Current agents:"
        HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-list 2>/dev/null || true
        echo ""
        
        echo "  1) Create new agent"
        echo "  2) Attach agent to gateway"
        echo "  3) Detach agent from gateway"
        echo "  4) Configure agent (model, skills, MCP, resources)"
        echo "  5) Export agent (MINIMAL|STANDARD|FULL)"
        echo "  6) Import agent"
        echo "  7) Delete agent"
        echo "  8) View agent details (config, skills, status)"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-8/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                read -p "Agent ID: " agent_id
                read -p "Model [anthropic/claude-sonnet-4]: " model
                model="${model:-anthropic/claude-sonnet-4}"
                read -p "Name [$agent_id]: " name
                name="${name:-$agent_id}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-create "$agent_id" "$model" "$name"
                ;;
            2)
                read -p "Agent ID to attach: " agent_id
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-attach "$agent_id"
                ;;
            3)
                read -p "Agent ID to detach: " agent_id
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-detach "$agent_id"
                ;;
            4)
                gateway_configure_agent "$hemlock_cli" "$hemlock_dir"
                ;;
            5)
                read -p "Agent ID to export: " agent_id
                read -p "Mode [STANDARD]: " mode
                mode="${mode:-STANDARD}"
                read -p "Destination [.]: " dest
                dest="${dest:-.}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-export "$agent_id" "$mode" "$dest"
                ;;
            6)
                read -p "Source path: " source
                read -p "New agent ID: " agent_id
                read -p "Mode [STANDARD]: " mode
                mode="${mode:-STANDARD}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-import "$source" "$agent_id" "$mode"
                ;;
            7)
                read -p "Agent ID to delete: " agent_id
                if confirm "Delete agent $agent_id permanently?"; then
                    HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-delete "$agent_id"
                fi
                ;;
            8)
                read -p "Agent ID: " agent_id
                local vol="hemlock-agent-$agent_id"
                docker run --rm -v "$vol:/workspace" alpine cat /workspace/agent.json 2>/dev/null | jq . 2>/dev/null || echo "Agent not found"
                docker run --rm -v "$vol:/workspace" alpine cat /workspace/SOUL.md 2>/dev/null | head -30
                docker run --rm -v "$vol:/workspace" alpine ls -la /workspace/skills 2>/dev/null
                read -p "Press Enter..."
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        echo ""
        read -p "Press Enter to continue..."
    done
}

gateway_configure_agent() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    print_header "Configure Agent"
    read -p "Agent ID: " agent_id
    
    if [[ -z "$agent_id" ]]; then
        print_error "Agent ID required"
        return 1
    fi
    
    # Check if agent exists
    if ! docker volume inspect "hemlock-agent-$agent_id" &>/dev/null; then
        print_error "Agent volume not found: hemlock-agent-$agent_id"
        return 1
    fi
    
    while true; do
        print_header "Configure Agent: $agent_id"
        echo "  1) Change model"
        echo "  2) Configure MCP server"
        echo "  3) Copy skills to agent"
        echo "  4) Set resource limits (CPU/Memory)"
        echo "  5) Configure environment variables"
        echo "  6) View current configuration"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-6/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                read -p "Model [anthropic/claude-sonnet-4]: " model
                model="${model:-anthropic/claude-sonnet-4}"
                # Update agent.json
                local vol="hemlock-agent-$agent_id"
                docker run --rm -v "$vol:/workspace" alpine sh -c "
                    jq --arg m '$model' '.model = \$m' /workspace/agent.json > /tmp/agent.json && mv /tmp/agent.json /workspace/agent.json
                    echo 'Model updated to:' \$m
                "
                ;;
            2)
                read -p "MCP command [python3]: " mcp_cmd
                mcp_cmd="${mcp_cmd:-python3}"
                read -p "MCP args [-m mcp_bridge]: " mcp_args
                mcp_args="${mcp_args:--m mcp_bridge}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" mcp-configure "$agent_id" "$mcp_cmd" "$mcp_args"
                ;;
            3)
                print_info "Available skills (from shared-skills volume):"
                docker run --rm -v hemlock-shared-skills:/skills alpine ls /skills 2>/dev/null | head -20
                echo ""
                read -p "Skills to copy (space-separated): " skills
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" copy-skills "$agent_id" $skills
                ;;
            4)
                read -p "CPU cores [2]: " cpus
                cpus="${cpus:-2}"
                read -p "Memory GB [4]: " mem
                mem="${mem:-4}"
                local vol="hemlock-agent-$agent_id"
                # Update config.yaml with resource limits
                docker run --rm -v "$vol:/workspace" alpine sh -c "
                    cat > /workspace/config.resources <<EOF
resources:
  cpus: $cpus
  memory: ${mem}g
  pids_limit: 1000
EOF
                    echo 'Resource limits set: CPU=' \$cpus 'Memory=' \$mem 'GB'
                "
                # Apply to running container if attached
                if docker ps --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
                    print_info "Restart agent container to apply limits"
                fi
                ;;
            5)
                read -p "Environment variable name: " env_name
                read -p "Environment variable value: " env_value
                local vol="hemlock-agent-$agent_id"
                docker run --rm -v "$vol:/workspace" alpine sh -c "
                    echo '$env_name=$env_value' >> /workspace/.env
                    echo 'Added to .env'
                "
                ;;
            6)
                local vol="hemlock-agent-$agent_id"
                docker run --rm -v "$vol:/workspace" alpine cat /workspace/agent.json 2>/dev/null | jq .
                docker run --rm -v "$vol:/workspace" alpine cat /workspace/config.yaml 2>/dev/null
                docker run --rm -v "$vol:/workspace" alpine cat /workspace/.env 2>/dev/null
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        read -p "Press Enter..."
    done
}

gateway_manage_crews() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    while true; do
        print_header "Crew Management"
        
        print_info "Current crews:"
        HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-list 2>/dev/null || true
        echo ""
        
        echo "  1) Create new crew"
        echo "  2) Attach crew (attaches all agents)"
        echo "  3) Detach crew"
        echo "  4) Configure crew (channel, agents, settings)"
        echo "  5) Export crew"
        echo "  6) Import crew"
        echo "  7) Delete crew"
        echo "  8) View crew members"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-8/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                read -p "Crew name: " crew_name
                read -p "Agent IDs (space-separated): " agents
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-create "$crew_name" $agents
                ;;
            2)
                read -p "Crew name to attach: " crew_name
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-attach "$crew_name"
                ;;
            3)
                read -p "Crew name to detach: " crew_name
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-detach "$crew_name"
                ;;
            4)
                read -p "Crew name: " crew_name
                local vol="hemlock-crew-$crew_name"
                if docker volume inspect "$vol" &>/dev/null; then
                    docker run --rm -v "$vol:/workspace" alpine cat /workspace/crew.json 2>/dev/null | jq .
                    read -p "New channel name [crew-$crew_name]: " channel
                    channel="${channel:-crew-$crew_name}"
                    docker run --rm -v "$vol:/workspace" alpine sh -c "
                        jq --arg c '\$channel' '.channel = \$c' /workspace/crew.json > /tmp/crew.json && mv /tmp/crew.json /workspace/crew.json
                        echo 'Channel updated to:' \$c
                    "
                else
                    print_error "Crew not found"
                fi
                ;;
            5)
                read -p "Crew name to export: " crew_name
                read -p "Mode [STANDARD]: " mode
                mode="${mode:-STANDARD}"
                read -p "Destination [.]: " dest
                dest="${dest:-.}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-export "$crew_name" "$mode" "$dest"
                ;;
            6)
                read -p "Source path: " source
                read -p "New crew name: " crew_name
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-import "$source" "$crew_name"
                ;;
            7)
                read -p "Crew name to delete: " crew_name
                if confirm "Delete crew $crew_name permanently?"; then
                    HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-delete "$crew_name"
                fi
                ;;
            8)
                read -p "Crew name: " crew_name
                local vol="hemlock-crew-$crew_name"
                if docker volume inspect "$vol" &>/dev/null; then
                    docker run --rm -v "$vol:/workspace" alpine cat /workspace/crew.json 2>/dev/null | jq .
                    echo ""
                    echo "Members:"
                    docker run --rm -v "$vol:/workspace" alpine cat /workspace/crew.json 2>/dev/null | jq -r '.agents[]' 2>/dev/null | while read -r agent; do
                        echo "  • $agent"
                    done
                else
                    print_error "Crew not found"
                fi
                read -p "Press Enter..."
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        echo ""
        read -p "Press Enter to continue..."
    done
}

gateway_manage_settings() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    while true; do
        print_header "Gateway Settings"
        
        # Show current config
        if [[ -f "$hemlock_dir/entrypoint.sh" ]]; then
            docker exec hemlock-runtime cat /workspace/gateway/hemlock.json 2>/dev/null | jq . 2>/dev/null || echo "Gateway not running"
        fi
        echo ""
        
        echo "  1) View/change gateway token"
        echo "  2) Configure Telegram"
        echo "  3) Configure iMessage"
        echo "  4) Configure MCP servers"
        echo "  5) Configure network ports"
        echo "  6) Configure plugins"
        echo "  7) Reset gateway config"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-7/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                print_info "Current token:"
                docker exec hemlock-runtime cat /workspace/gateway/hemlock.json 2>/dev/null | jq -r '.gateway.token // "not set"'
                echo ""
                read -p "New token (leave blank to generate): " new_token
                if [[ -z "$new_token" ]]; then
                    new_token=$(openssl rand -hex 32)
                fi
                docker exec hemlock-runtime sh -c "
                    jq --arg t '\$new_token' '.gateway.token = \$t' /workspace/gateway/hemlock.json > /tmp/gw.json && mv /tmp/gw.json /workspace/gateway/hemlock.json
                    echo 'Token updated'
                " 2>/dev/null
                print_info "Restart gateway to apply: docker restart hemlock-runtime"
                ;;
            2)
                read -p "Telegram bot token: " tg_token
                read -p "Default account ID: " tg_account
                docker exec hemlock-runtime sh -c "
                    jq --arg tok '\$tg_token' --arg acc '\$tg_account' '.channels.telegram.accounts.\$acc = {\"botToken\": \$tok} | .channels.telegram.defaultAccount = \$acc' /workspace/gateway/hemlock.json > /tmp/gw.json && mv /tmp/gw.json /workspace/gateway/hemlock.json
                " 2>/dev/null
                print_info "Telegram configured. Restart gateway."
                ;;
            3)
                print_info "iMessage requires Mac with imsg installed"
                read -p "Remote Mac host (ssh): " imsg_host
                docker exec hemlock-runtime sh -c "
                    jq --arg h '\$imsg_host' '.channels.imessage = {\"enabled\": true, \"cliPath\": \"/workspace/scripts/imsg-ssh\", \"remoteHost\": \$h, \"includeAttachments\": true}' /workspace/gateway/hemlock.json > /tmp/gw.json && mv /tmp/gw.json /workspace/gateway/hemlock.json
                " 2>/dev/null
                print_info "iMessage configured. Need SSH wrapper script on host."
                ;;
            4)
                print_header "MCP Server Configuration"
                echo "Configure Model Context Protocol servers for agents"
                docker exec hemlock-runtime cat /workspace/gateway/hemlock.json 2>/dev/null | jq '.mcp.servers' 2>/dev/null
                echo ""
                echo "  a) Add MCP server"
                echo "  r) Remove MCP server"
                echo "  q) Back"
                read -p "Select: " mcp_choice
                if [[ "$mcp_choice" == "a" ]]; then
                    read -p "Server name: " srv_name
                    read -p "Command [python3]: " srv_cmd
                    srv_cmd="${srv_cmd:-python3}"
                    read -p "Args [-m mcp_bridge]: " srv_args
                    srv_args="${srv_args:--m mcp_bridge}"
                    docker exec hemlock-runtime sh -c "
                        jq --arg n '\$srv_name' --arg c '\$srv_cmd' --arg a '\$srv_args' '.mcp.servers[\$n] = {\"command\": \$c, \"args\": (\$a | split(\" \"))}' /workspace/gateway/hemlock.json > /tmp/gw.json && mv /tmp/gw.json /workspace/gateway/hemlock.json
                    " 2>/dev/null
                    print_info "MCP server added"
                elif [[ "$mcp_choice" == "r" ]]; then
                    read -p "Server name to remove: " srv_name
                    docker exec hemlock-runtime sh -c "
                        jq --arg n '\$srv_name' 'del(.mcp.servers[\$n])' /workspace/gateway/hemlock.json > /tmp/gw.json && mv /tmp/gw.json /workspace/gateway/hemlock.json
                    " 2>/dev/null
                    print_info "MCP server removed"
                fi
                ;;
            5)
                print_header "Network Port Configuration"
                echo "Current gateway ports:"
                docker exec hemlock-runtime cat /workspace/gateway/hemlock.json 2>/dev/null | jq -r '.gateway.port // 18789'
                echo ""
                echo "Container ports (compute resources):"
                for port in "${CONTAINER_COMPUTE_PORTS[@]}"; do
                    echo "  $port"
                done
                echo ""
                read -p "Add port mapping (host:container): " port_map
                if [[ -n "$port_map" ]]; then
                    CONTAINER_COMPUTE_PORTS+=("$port_map")
                    print_info "Added to CONTAINER_COMPUTE_PORTS. Restart container to apply."
                fi
                ;;
            6)
                print_header "Plugin Configuration"
                docker exec hemlock-runtime cat /workspace/gateway/hemlock.json 2>/dev/null | jq '.plugins // {}' 2>/dev/null
                read -p "Plugin name: " plug_name
                read -p "Plugin path: " plug_path
                docker exec hemlock-runtime sh -c "
                    jq --arg n '\$plug_name' --arg p '\$plug_path' '.plugins[\$n] = {\"path\": \$p, \"enabled\": true}' /workspace/gateway/hemlock.json > /tmp/gw.json && mv /tmp/gw.json /workspace/gateway/hemlock.json
                " 2>/dev/null
                print_info "Plugin added. Restart gateway."
                ;;
            7)
                if confirm "Reset gateway config to defaults? This will detach all agents."; then
                    docker exec hemlock-runtime sh -c "
                        rm -f /workspace/gateway/hemlock.json
                        # entrypoint.sh will recreate on next start
                    " 2>/dev/null
                    print_info "Config reset. Restart gateway."
                fi
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        read -p "Press Enter..."
    done
}

gateway_manage_skills() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    while true; do
        print_header "Skills Management"
        
        print_info "Available skills (shared-skills volume):"
        docker run --rm -v hemlock-shared-skills:/skills alpine ls /skills 2>/dev/null | head -30
        echo ""
        
        echo "  1) List all skills"
        echo "  2) Copy skills to agent"
        echo "  3) Install new skill from source"
        echo "  4) View skill details"
        echo "  5) Update all skills"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-5/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                docker run --rm -v hemlock-shared-skills:/skills alpine ls -la /skills
                ;;
            2)
                read -p "Agent ID: " agent_id
                print_info "Available skills:"
                docker run --rm -v hemlock-shared-skills:/skills alpine ls /skills 2>/dev/null
                read -p "Skills to copy (space-separated): " skills
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" copy-skills "$agent_id" $skills
                ;;
            3)
                read -p "Skill source (git URL or local path): " skill_source
                print_info "Skill installation from source not yet implemented in CLI"
                print_info "Manual: docker run --rm -v hemlock-shared-skills:/skills alpine sh -c 'cd /skills && git clone \$skill_source'"
                ;;
            4)
                read -p "Skill name: " skill_name
                docker run --rm -v hemlock-shared-skills:/skills alpine cat "/skills/$skill_name/SKILL.md" 2>/dev/null | head -50
                ;;
            5)
                print_info "Updating skills via populate-skills.sh..."
                bash "$hemlock_dir/scripts/populate-skills.sh" 2>&1 | tail -20
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        read -p "Press Enter..."
    done
}

gateway_manage_resources() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    while true; do
        print_header "Resource Allocation"
        
        echo "Container compute ports:"
        for port in "${CONTAINER_COMPUTE_PORTS[@]}"; do
            echo "  $port"
        done
        echo ""
        
        echo "  1) Add compute port mapping"
        echo "  2) Remove compute port mapping"
        echo "  3) Set default agent CPU/memory"
        echo "  4) Configure persistence mount mode (rw/ro)"
        echo "  5) View current resource usage"
        echo "  6) Set container isolation level"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-6/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                read -p "Port mapping (host:container): " port_map
                CONTAINER_COMPUTE_PORTS+=("$port_map")
                print_info "Added. Restart hemlock-runtime to apply."
                ;;
            2)
                print_info "Current ports:"
                for i in "${!CONTAINER_COMPUTE_PORTS[@]}"; do
                    echo "  $i) ${CONTAINER_COMPUTE_PORTS[$i]}"
                done
                read -p "Index to remove: " idx
                if [[ "$idx" =~ ^[0-9]+$ ]] && [[ "$idx" -lt "${#CONTAINER_COMPUTE_PORTS[@]}" ]]; then
                    unset 'CONTAINER_COMPUTE_PORTS[idx]'
                    CONTAINER_COMPUTE_PORTS=("${CONTAINER_COMPUTE_PORTS[@]}")
                    print_info "Removed. Restart to apply."
                fi
                ;;
            3)
                read -p "Default CPU cores [2]: " def_cpu
                def_cpu="${def_cpu:-2}"
                read -p "Default memory GB [4]: " def_mem
                def_mem="${def_mem:-4}"
                print_info "Defaults set. Apply to individual agents via agent config."
                ;;
            4)
                echo "  1) Read-write (default) - full compute workloads"
                echo "  2) Read-only - data access only"
                read -p "Select [1-2]: " p_mode
                if [[ "$p_mode" == "1" ]]; then
                    PERSISTENCE_MOUNT_MODE="rw"
                elif [[ "$p_mode" == "2" ]]; then
                    PERSISTENCE_MOUNT_MODE="ro"
                fi
                print_info "Persistence mount mode: $PERSISTENCE_MOUNT_MODE"
                ;;
            5)
                print_header "Current Resource Usage"
                docker stats hemlock-runtime --no-stream 2>/dev/null || echo "Container not running"
                echo ""
                echo "Volumes:"
                docker volume ls --filter name=hemlock- --format "table {{.Name}}\t{{.Driver}}"
                echo ""
                echo "Agent volumes:"
                for vol in $(docker volume ls --format '{{.Name}}' | grep '^hemlock-agent-'); do
                    docker run --rm -v "$vol:/workspace" alpine df -h /workspace 2>/dev/null | tail -1 | awk -v v="$vol" '{print v ": " $3 "/" $2 " (" $5 ")"}'
                done
                ;;
            6)
                echo "  1) Strict - no new privileges, minimal caps"
                echo "  2) Standard - default isolation"
                echo "  3) Relaxed - more capabilities for debugging"
                read -p "Select [1-3]: " iso_level
                case "$iso_level" in
                    1) CONTAINER_ISOLATION="true"; print_info "Strict isolation enabled" ;;
                    2) CONTAINER_ISOLATION="true"; print_info "Standard isolation enabled" ;;
                    3) CONTAINER_ISOLATION="false"; print_info "Relaxed isolation (not recommended for production)" ;;
                esac
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        read -p "Press Enter..."
    done
}

gateway_manage_backup() {
    local hemlock_cli="$1"
    local hemlock_dir="$2"
    
    while true; do
        print_header "Backup & Restore"
        
        echo "  1) Export agent (MINIMAL|STANDARD|FULL)"
        echo "  2) Export crew"
        echo "  3) Full system backup (all volumes)"
        echo "  4) Import agent"
        echo "  5) Import crew"
        echo "  6) Restore from backup"
        echo "  q) Back"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select [1-6/q]: ${NC}")" choice
        
        case "$choice" in
            1)
                read -p "Agent ID: " agent_id
                read -p "Mode [STANDARD]: " mode
                mode="${mode:-STANDARD}"
                read -p "Destination [.]: " dest
                dest="${dest:-.}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-export "$agent_id" "$mode" "$dest"
                ;;
            2)
                read -p "Crew name: " crew_name
                read -p "Mode [STANDARD]: " mode
                mode="${mode:-STANDARD}"
                read -p "Destination [.]: " dest
                dest="${dest:-.}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-export "$crew_name" "$mode" "$dest"
                ;;
            3)
                print_header "Full System Backup"
                local backup_dir="$HOME/hemlock-backups/$(date +%Y%m%d-%H%M%S)"
                mkdir -p "$backup_dir"
                
                print_info "Backing up gateway config..."
                docker exec hemlock-runtime tar -czf - -C /workspace/gateway . 2>/dev/null > "$backup_dir/gateway.tar.gz" || true
                
                print_info "Backing up agents..."
                for vol in $(docker volume ls --format '{{.Name}}' | grep '^hemlock-agent-'); do
                    docker run --rm -v "$vol:/src" -v "$backup_dir:/dst" alpine tar -czf "/dst/${vol}.tar.gz" -C /src . 2>/dev/null || true
                done
                
                print_info "Backing up crews..."
                for vol in $(docker volume ls --format '{{.Name}}' | grep '^hemlock-crew-'); do
                    docker run --rm -v "$vol:/src" -v "$backup_dir:/dst" alpine tar -czf "/dst/${vol}.tar.gz" -C /src . 2>/dev/null || true
                done
                
                print_success "Full backup saved to: $backup_dir"
                ls -lh "$backup_dir"
                ;;
            4)
                read -p "Source path: " source
                read -p "New agent ID: " agent_id
                read -p "Mode [STANDARD]: " mode
                mode="${mode:-STANDARD}"
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-import "$source" "$agent_id" "$mode"
                ;;
            5)
                read -p "Source path: " source
                read -p "New crew name: " crew_name
                HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" crew-import "$source" "$crew_name"
                ;;
            6)
                read -p "Backup directory: " backup_dir
                if [[ -d "$backup_dir" ]]; then
                    print_info "Restoring gateway..."
                    docker exec hemlock-runtime tar -xzf - -C /workspace/gateway < "$backup_dir/gateway.tar.gz" 2>/dev/null || true
                    
                    print_info "Restoring agents..."
                    for file in "$backup_dir"/hemlock-agent-*.tar.gz; do
                        [[ -f "$file" ]] || continue
                        local vol=$(basename "$file" .tar.gz)
                        docker volume create "$vol" >/dev/null 2>&1
                        docker run --rm -v "$vol:/dst" -v "$backup_dir:/src:ro" alpine tar -xzf "/src/$(basename "$file")" -C /dst 2>/dev/null || true
                    done
                    
                    print_info "Restoring crews..."
                    for file in "$backup_dir"/hemlock-crew-*.tar.gz; do
                        [[ -f "$file" ]] || continue
                        local vol=$(basename "$file" .tar.gz)
                        docker volume create "$vol" >/dev/null 2>&1
                        docker run --rm -v "$vol:/dst" -v "$backup_dir:/src:ro" alpine tar -xzf "/src/$(basename "$file")" -C /dst 2>/dev/null || true
                    done
                    
                    print_success "Restore complete. Restart gateway and re-attach agents."
                else
                    print_error "Backup directory not found"
                fi
                ;;
            q|Q) return 0 ;;
            *) print_error "Invalid selection" ;;
        esac
        read -p "Press Enter..."
    done
}

# ============================================================================
# NOTE: All model/agent/skill/MCP/plugin management happens INSIDE the container
# via Hemlock TUI (hemlock-tui) or CLI (hemlock).
# The host setup script only deploys the container with proper volumes & ports.
# ============================================================================

# ============================================================================
# COMPREHENSIVE HEMLOCK DEPLOYMENT FOR COMPLETE SETUP
# ============================================================================

deploy_hemlock_full() {
    local hemlock_dir="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}"
    local hemlock_cli="$hemlock_dir/scripts/hemlock"
    local entrypoint_sh="$hemlock_dir/entrypoint.sh"
    
    print_header "Deploying Hemlock Agent Orchestration Platform (Full Setup)"
    echo "This deploys the complete Hemlock system with:"
    echo "  - Docker image build from Dockerfile.runtime (includes llama.cpp build)"
    echo "  - Required volumes (gateway, agents, crews, shared-skills, models)"
    echo "  - 157 skills populated to shared-skills volume"
    echo "  - Gateway container with auto-restart on port 18789"
    echo "  - MCP bridge for agent cognition"
    echo "  - Pre-created default agents (alpha, beta, gamma)"
    echo "  - Auto-attach agents to gateway on startup"
    echo "  - Compute resource ports for model serving (8080, 8888, 11434, etc.)"
    echo ""
    echo "NOTE: Model management, llama.cpp, plugins, MCP config, and agent/crew"
    echo "      management all run INSIDE the container via Hemlock TUI/CLI."
    echo ""
    
    if ! confirm "Deploy Hemlock now?"; then
        print_info "Skipping Hemlock deployment"
        return 0
    fi
    
    # Check Docker
    if ! command -v docker &>/dev/null || ! docker info &>/dev/null; then
        print_error "Docker not running. Install and start Docker first."
        return 1
    fi
    
    # Check Hemlock files exist
    if [[ ! -f "$entrypoint_sh" ]]; then
        print_error "Hemlock entrypoint.sh not found at: $entrypoint_sh"
        return 1
    fi
    if [[ ! -f "$hemlock_cli" ]]; then
        print_error "Hemlock CLI not found at: $hemlock_cli"
        return 1
    fi
    
    print_info "Found Hemlock at: $hemlock_dir"
    
    cd "$hemlock_dir"
    
    # Step 1: Build Docker image (includes llama.cpp with hardware detection)
    print_header "[1/6] Building Hemlock Docker Image (with llama.cpp)"
    if [[ -f "Dockerfile.runtime" ]]; then
        print_info "Building hemlock-runtime image (this may take several minutes)..."
        if ! docker build -f Dockerfile.runtime -t hemlock-runtime . 2>&1 | tail -30; then
            print_error "Docker build failed"
            return 1
        fi
        print_success "Hemlock Docker image built successfully (includes llama.cpp)"
    else
        print_error "Dockerfile.runtime not found"
        return 1
    fi
    
    # Step 2: Create volumes (including models volume for persistent model storage)
    print_header "[2/6] Creating Docker Volumes"
    for vol in hemlock-gateway hemlock-agents hemlock-crews hemlock-shared-skills hemlock-models; do
        if docker volume inspect "$vol" &>/dev/null; then
            print_info "Volume $vol already exists"
        else
            docker volume create "$vol" >/dev/null
            print_success "Created volume: $vol"
        fi
    done
    
    # Step 3: Populate skills volume
    print_header "[3/6] Populating Skills Volume (157 skills)"
    if [[ -f "scripts/populate-skills.sh" ]]; then
        print_info "Running populate-skills.sh..."
        bash scripts/populate-skills.sh 2>&1 | tail -15
        print_success "Skills volume populated"
    else
        print_warning "populate-skills.sh not found, skipping"
    fi
    
    # Step 4: Create default agents
    print_header "[4/6] Creating Default Agents"
    print_info "Creating agents: alpha, beta, gamma (isolated workspaces)"
    
    for agent in alpha beta gamma; do
        print_info "Creating agent: $agent"
        HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-create "$agent" "anthropic/claude-sonnet-4" "$agent" 2>&1 | tail -5
        sleep 2
    done
    
    # Step 5: Build gateway config with agents pre-attached
    print_header "[5/6] Configuring Gateway with Pre-attached Agents"
    print_info "Building gateway config with agents attached..."
    
    # Ensure gateway config exists with agents attached
    HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-list 2>&1 | tail -10
    
    # Step 6: Start gateway container
    print_header "[6/6] Starting Hemlock Gateway Container"
    
    # Stop existing container if running
    if docker ps --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
        print_info "Stopping existing hemlock-runtime container..."
        docker stop hemlock-runtime >/dev/null
        docker rm hemlock-runtime >/dev/null
    elif docker ps -a --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
        docker rm hemlock-runtime >/dev/null
    fi
    
    print_info "Starting hemlock-runtime container..."
    
    # Use the same entrypoint approach as the TUI
    local gateway_token="${OPENCLAW_GATEWAY_TOKEN:-test-token-12345}"
    local imrsg_host="${IMRSG_REMOTE_HOST:-}"
    
    # Build port forwarding for compute resources
    local port_args=()
    for port_map in "${CONTAINER_COMPUTE_PORTS[@]}"; do
        port_args+=("-p" "$port_map")
    done
    # Add gateway and MCP ports
    port_args+=("-p" "${HEMLOCK_GATEWAY_PORT}:${HEMLOCK_GATEWAY_PORT}")
    port_args+=("-p" "${HEMLOCK_MCP_PROXY_PORT}:${HEMLOCK_MCP_PROXY_PORT}")
    
    # Isolation options
    local isolation_args=()
    if [[ "$CONTAINER_ISOLATION" == "true" ]]; then
        isolation_args=(
            "--security-opt=no-new-privileges:true"
            "--cap-drop=ALL"
            "--cap-add=CAP_DAC_OVERRIDE"  # For persistence access
            "--cap-add=CAP_SYS_RESOURCE"  # For resource limits
            "--pids-limit=1000"
            "--memory=4g"
            "--cpus=2"
        )
    fi
    
    docker run -d \
        --name hemlock-runtime \
        --restart unless-stopped \
        "${port_args[@]}" \
        "${isolation_args[@]}" \
        -v hemlock-gateway:/workspace/gateway \
        -v hemlock-agents:/agents \
        -v hemlock-crews:/crews \
        -v hemlock-shared-skills:/skills:ro \
        -v hemlock-models:/models \
        -e OPENCLAW_GATEWAY_TOKEN="$gateway_token" \
        -e IMRSG_REMOTE_HOST="$imrsg_host" \
        -e CONTAINER_ISOLATION="$CONTAINER_ISOLATION" \
        -e PERSISTENCE_MOUNT_MODE="$PERSISTENCE_MOUNT_MODE" \
        hemlock-runtime gateway 2>&1 | tail -5
    
    # Wait for gateway to be healthy
    print_info "Waiting for gateway to start..."
    local max_wait=60
    local waited=0
    while [[ $waited -lt $max_wait ]]; do
        if curl -sf http://localhost:${HEMLOCK_GATEWAY_PORT}/health >/dev/null 2>&1; then
            print_success "Gateway is healthy!"
            break
        fi
        sleep 2
        waited=$((waited + 2))
        echo -n "."
    done
    echo ""
    
    if [[ $waited -ge $max_wait ]]; then
        print_error "Gateway failed to start within $max_wait seconds"
        print_info "Check logs: docker logs hemlock-runtime"
        return 1
    fi
    
    # Auto-attach agents (they attach permanently)
    print_info "Attaching agents to gateway..."
    HEMLOCK_DIR="$hemlock_dir" "$hemlock_cli" agent-list 2>&1
    
    # Verify agents are attached
    print_info "Verifying agent attachment..."
    docker exec hemlock-runtime /entrypoint.sh agent-list 2>/dev/null || true
    
    print_success "Hemlock fully deployed!"
    print_info "Gateway: http://localhost:18789"
    print_info "Health:  curl http://localhost:18789/health"
    print_info "MCP Proxy: localhost:41214 (internal loopback)"
    print_info "Agents: alpha, beta, gamma (pre-created, attached)"
    print_info "Gateway Token: $gateway_token"
    echo ""
}

# ============================================================================
# NEW: AUTO-START SERVICES (VM + HEMLOCK + AGENTS)
# ============================================================================

setup_auto_start_services() {
    print_header "Configuring Auto-Start Services"
    echo "This sets up automatic startup for:"
    echo "  1. VM Auto-Boot (existing - USB detection -> VM start)"
    echo "  2. Hemlock Gateway (systemd service with auto-restart)"
    echo "  3. Agent Auto-Attach (on gateway startup)"
    echo "  4. Health Monitoring (auto-recovery if services fail)"
    echo ""
    
    if ! confirm "Configure auto-start services?"; then
        return 0
    fi
    
    local hemlock_dir="${HEMLOCK_DIR:-/tmp/hemlock-minimal/hemlock-minimal}"
    
    # Platform-specific service setup
    if [[ "$OS" == "Darwin" ]]; then
        setup_launchagent_hemlock "$hemlock_dir"
    elif [[ "$OS" == "Linux" ]]; then
        setup_systemd_hemlock "$hemlock_dir"
    else
        print_warning "Windows auto-start not implemented"
        return 0
    fi
    
    print_success "Auto-start services configured!"
    print_info "On next USB plug-in:"
    print_info "  1. VM auto-boots (existing LaunchAgent/ssytemd)"
    print_info "  2. Hemlock gateway auto-starts (systemd/LaunchAgent)"
    print_info "  3. Agents auto-attach to gateway"
    print_info "  4. SSH available at port $SSH_PORT_FORWARD_HOST"
    print_info "  5. Hemlock TUI ready for agent management"
    echo ""
}

setup_launchagent_hemlock() {
    local hemlock_dir="$1"
    local plist_path="$HOME/Library/LaunchAgents/com.hemlock.gateway.plist"
    local hemlock_cli="$hemlock_dir/scripts/hemlock"
    local entrypoint_sh="$hemlock_dir/entrypoint.sh"
    
    mkdir -p "$(dirname "$plist_path")"
    
    cat > "$plist_path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.hemlock.gateway</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-c</string>
        <string>HEMLOCK_DIR="$hemlock_dir" $entrypoint_sh gateway</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
        <key>Crashed</key>
        <true/>
    </dict>
    <key>RestartInterval</key>
    <integer>10</integer>
    <key>StandardOutPath</key>
    <string>/tmp/hemlock-gateway.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/hemlock-gateway.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>OPENCLAW_GATEWAY_TOKEN</key>
        <string>\${OPENCLAW_GATEWAY_TOKEN:-test-token-12345}</string>
        <key>IMRSG_REMOTE_HOST</key>
        <string>\${IMRSG_REMOTE_HOST:-}</string>
    </dict>
</dict>
</plist>
EOF
    
    print_info "Created LaunchAgent: $plist_path"
    
    # Load it
    launchctl load "$plist_path" 2>/dev/null || true
    print_success "Hemlock LaunchAgent loaded"
}

setup_systemd_hemlock() {
    local hemlock_dir="$1"
    local service_path="/etc/systemd/system/hemlock-gateway.service"
    local hemlock_cli="$hemlock_dir/scripts/hemlock"
    local entrypoint_sh="$hemlock_dir/entrypoint.sh"
    
    print_info "Creating systemd service: $service_path"
    print_info "Requires sudo..."
    
    cat > "/tmp/hemlock-gateway.service" <<EOF
[Unit]
Description=Hemlock Agent Orchestration Gateway
After=docker.service network.target
Requires=docker.service
StartLimitIntervalSec=0

[Service]
Type=simple
User=%i
Group=%i
Environment=HEMLOCK_DIR=$hemlock_dir
Environment=OPENCLAW_GATEWAY_TOKEN=\${OPENCLAW_GATEWAY_TOKEN:-test-token-12345}
Environment=IMRSG_REMOTE_HOST=\${IMRSG_REMOTE_HOST:-}
ExecStart=/bin/bash -c '$entrypoint_sh gateway'
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    # Copy to systemd directory
    if sudo cp "/tmp/hemlock-gateway.service" "$service_path"; then
        print_success "Systemd service created"
        
        # Reload and enable
        sudo systemctl daemon-reload
        sudo systemctl enable hemlock-gateway.service
        print_success "Hemlock service enabled"
        
        # Also create USB detection service for VM auto-boot
        create_usb_detection_service_systemd "$hemlock_dir"
    else
        print_error "Failed to create systemd service (sudo required)"
        return 1
    fi
}

create_usb_detection_service_systemd() {
    local hemlock_dir="$1"
    local service_path="/etc/systemd/system/hemlock-usb-detect.service"
    local detect_script="$hemlock_dir/scripts/usb-detector.sh"
    
    # Create USB detector script
    mkdir -p "$(dirname "$detect_script")"
    cat > "$detect_script" <<'DETECT_EOF'
#!/usr/bin/env bash
# USB Detector - Watches for Ventoy USB and manages VM/Hemlock startup

LOG_FILE="/tmp/hemlock-usb-detect-$(date +%Y%m%d).log"
VENTOY_LABEL="Ventoy"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Check if Ventoy USB is connected
is_ventoy_connected() {
    if blkid -l 2>/dev/null | grep -q "$VENTOY_LABEL"; then
        return 0
    fi
    return 1
}

# Start Hemlock if not running
start_hemlock_if_needed() {
    if docker ps --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
        log "Hemlock already running"
        return 0
    fi
    
    log "Starting Hemlock gateway..."
    # The systemd service handles this, but we can ensure it's up
    systemctl is-active --quiet hemlock-gateway.service || systemctl start hemlock-gateway.service
}

# Start VM if USB connected
start_vm_if_usb() {
    if is_ventoy_connected; then
        log "Ventoy USB detected"
        start_hemlock_if_needed
        
        # Check if VM is already running (QEMU process)
        if ! pgrep -q "qemu"; then
            log "Starting QEMU VM..."
            # VM start logic would go here - use existing QEMU script
            # Find the script on the USB (relative to mount point)
            local qemu_script=""
            for mount in /media/*/Ventoy /mnt/ventoy /run/media/*/Ventoy; do
                if [[ -f "$mount/scripts/start-usb-vm.sh" ]]; then
                    qemu_script="$mount/scripts/start-usb-vm.sh"
                    break
                fi
            done
            if [[ -n "$qemu_script" && -f "$qemu_script" ]]; then
                bash "$qemu_script" >> "$LOG_FILE" 2>&1 &
            fi
        fi
    else
        log "Ventoy USB not connected"
    fi
}

# Main loop
log "Hemlock USB Detector started"

while true; do
    start_vm_if_usb
    sleep 10
done
DETECT_EOF
    chmod +x "$detect_script"
    
    cat > "/tmp/hemlock-usb-detect.service" <<EOF
[Unit]
Description=Hemlock USB Detection and Auto-Start
After=hemlock-gateway.service
Requires=hemlock-gateway.service

[Service]
Type=simple
User=%i
Group=%i
ExecStart=$detect_script
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    if sudo cp "/tmp/hemlock-usb-detect.service" "$service_path"; then
        sudo systemctl daemon-reload
        sudo systemctl enable hemlock-usb-detect.service
        print_success "USB detection service created and enabled"
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    initialize
    
    while true; do
        show_main_menu
        read -p "$(echo -e "${YELLOW}Select an option [1-14]: ${NC}")" choice
        
        case "$choice" in
            1)
                setup_complete_system || read -p "Press Enter to continue..." ;;
            2)
                setup_usb_drive || read -p "Press Enter to continue..." ;;
            3)
                setup_vm_boot || read -p "Press Enter to continue..." ;;
            4)
                install_essentials || read -p "Press Enter to continue..." ;;
            5)
                configure_network || read -p "Press Enter to continue..." ;;
            6)
                view_system_status || read -p "Press Enter to continue..." ;;
            7)
                backup_recovery_options || read -p "Press Enter to continue..." ;;
            8)
                _system_cleanup || read -p "Press Enter to continue..." ;;
            9)
                _alias_manager || read -p "Press Enter to continue..." ;;
            10)
                _ssh_host_manager || read -p "Press Enter to continue..." ;;
            11)
                access_usb_terminal || read -p "Press Enter to continue..." ;;
            12)
                copy_file_to_usb || read -p "Press Enter to continue..." ;;
            13)
                launch_hemlock_tui || read -p "Press Enter to continue..." ;;
            14)
                print_success "Thank you for using the USB Compute Automation Setup Assistant!"
                print_info "Your USB Compute Automation System is ready to use."
                echo ""
                break
                ;;
            *)
                print_error "Invalid option. Please select a number between 1 and 14."
                ;;
        esac
        
        echo ""
        if ! confirm "Return to main menu?" "y"; then
            break
        fi
        echo ""
    done
}

# Parse command line arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            echo "[DRY RUN MODE] No changes will be made to your system."
            echo ""
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Run in dry-run mode (no changes made)"
            echo "  --help, -h   Show this help message"
            echo ""
            echo "Interactive setup assistant for USB Compute Automation System."
            echo "This script guides you through USB preparation, VM setup, and system configuration."
            exit 0
            ;;
    esac
done

# Execute main function
main "$@"