#!/usr/bin/env bash
# USB Compute Essentials Installer - Enhanced Version with Self-Healing, Testing, and Configuration Management
# This script provides a robust installation process with dry-run capabilities, self-healing properties,
# comprehensive testing sweeps, and persistent configuration logging.
# Includes cleanup and maintenance functions for safe debloating.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_NAME="USB Compute Essentials Installer (Enhanced)"
VERSION="2.0.0"
DRY_RUN=false
SELF_HEALING_MODE=false
VERBOSE=false
RUN_CLEANUP=false

# Parse command line arguments first to set DRY_RUN, and answer --help
# BEFORE any directory creation — printing usage must never require sudo
# or touch the filesystem.
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]] || [[ "$arg" == "-n" ]]; then
    DRY_RUN=true
  elif [[ "$arg" == "--help" ]] || [[ "$arg" == "-h" ]]; then
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --dry-run, -n        Show what would be done without actually doing it"
    echo "  --self-heal          Enable self-healing mode (restarts services if needed)"
    echo "  --verbose, -v        Enable verbose output"
    echo "  --cleanup            Run cleanup and debloating process"
    echo "  --help, -h           Show this help message"
    exit 0
  fi
done

# Set file paths based on dry-run mode
if [[ "$DRY_RUN" == "true" ]]; then
  LOG_FILE="/tmp/usb-essentials-install-$(date +%Y%m%d-%H%M%S).log"
  TEST_RESULTS_FILE="/tmp/usb-test-results-$(date +%Y%m%d-%H%M%S).log"
  CLEANUP_LOG_FILE="/tmp/usb-cleanup-$(date +%Y%m%d).log"
  CONFIG_FILE="/tmp/usb-compute-automation/config/installation-config.json"
  HOST_ID_FILE="/tmp/usb-compute-automation/config/host-id.json"
else
  LOG_FILE="/var/log/usb-essentials-install-$(date +%Y%m%d-%H%M%S).log"
  TEST_RESULTS_FILE="/var/log/usb-test-results-$(date +%Y%m%d-%H%M%S).log"
  CLEANUP_LOG_FILE="/var/log/usb-cleanup-$(date +%Y%m%d).log"
  CONFIG_FILE="/opt/usb-compute-automation/config/installation-config.json"
  HOST_ID_FILE="/opt/usb-compute-automation/config/host-id.json"
fi

# Ensure directories for log and config files exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$TEST_RESULTS_FILE")"
mkdir -p "$(dirname "$CLEANUP_LOG_FILE")"
mkdir -p "$(dirname "$CONFIG_FILE")"
mkdir -p "$(dirname "$HOST_ID_FILE")"

# Default installation paths (all within persistence layer)
DEFAULT_PATHS=(
    "LLAMA=/opt/llama.cpp"
    "OLLAMA=/opt/ollama"
    "AGENTS=/opt/agent-harnesses"
    "AI_SYSTEMS=/opt/ai-systems"
    "MODELS=/opt/models"
    "CONTAINERS=/opt/containers"
    "RUST=/opt/rust"
    "FOUNDRY=/opt/foundry"
    "HARDHAT=/opt/hardhat"
    "PLAYWRIGHT=/opt/playwright"
    "ELECTRON=/opt/electron"
    "TAURI=/opt/tauri"
    "TAILSCALE=/opt/tailscale"
    "BUN=/usr/local/bin/bun"
)

# Process default paths to set individual variables
for path_mapping in "${DEFAULT_PATHS[@]}"; do
    IFS='=' read -r key value <<< "$path_mapping"
    # Convert to uppercase and replace hyphens with underscores for env var format
    var_name="INSTALL_PATH_${key^^}"
    # Declare and set the variable
    declare "${var_name}=${value}"
done

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
    local message="$1"
    local level="${2:-INFO}"
    local timestamp="$(date +'%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1" | tee -a "$LOG_FILE"
    log "SUCCESS: $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1" | tee -a "$LOG_FILE"
    log "ERROR: $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1" | tee -a "$LOG_FILE"
    log "WARNING: $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1" | tee -a "$LOG_FILE"
    log "INFO: $1"
}

print_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}DEBUG:${NC} $1" | tee -a "$LOG_FILE"
        log "DEBUG: $1"
    fi
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

# Check if we should run in dry-run mode
check_dry_run() {
    for arg in "$@"; do
        if [[ "$arg" == "--dry-run" ]] || [[ "$arg" == "-n" ]]; then
            DRY_RUN=true
            return 0
        fi
    done
    return 1
}

# Check if we should enable self-healing mode
check_self_healing() {
    for arg in "$@"; do
        if [[ "$arg" == "--self-heal" ]]; then
            SELF_HEALING_MODE=true
            return 0
        fi
    done
    return 1
}

# Check if we should enable verbose output
check_verbose() {
    for arg in "$@"; do
        if [[ "$arg" == "--verbose" ]] || [[ "$arg" == "-v" ]]; then
            VERBOSE=true
            return 0
        fi
    done
    return 1
}

# Check if we should run cleanup
check_cleanup() {
    for arg in "$@"; do
        if [[ "$arg" == "--cleanup" ]]; then
            RUN_CLEANUP=true
            return 0
        fi
    done
    return 1
}

# Execute command with dry-run support
run_cmd() {
    local cmd="$1"
    local description="${2:-Executing command}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] $description: $cmd"
        log "[DRY-RUN] $description: $cmd"
        return 0
    fi
    
    print_debug "Running: $cmd"
    if eval "$cmd"; then
        print_success "$description"
        log "SUCCESS: $description"
        return 0
    else
        print_error "Failed: $description"
        log "ERROR: $description"
        return 1
    fi
}

# Create directory with proper permissions
create_dir() {
    local dir_path="$1"
    local description="${2:-Creating directory}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] $description: $dir_path"
        log "[DRY-RUN] $description: $dir_path"
        return 0
    fi
    
    mkdir -p "$dir_path"
    # Set ownership to root:root for security (prevents host tampering)
    chown root:root "$dir_path"
    chmod 755 "$dir_path"
    print_success "$description: $dir_path"
    log "SUCCESS: $description: $dir_path (owned by root:root, perms 755)"
    return 0
}

# Create file with content
create_file() {
    local file_path="$1"
    local content="$2"
    local description="${3:-Creating file}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] $description: $file_path"
        log "[DRY-RUN] $description: $file_path"
        return 0
    fi
    
    mkdir -p "$(dirname "$file_path")"
    echo "$content" > "$file_path"
    # Set ownership to root:root for security
    chown root:root "$file_path"
    chmod 644 "$file_path"
    print_success "$description: $file_path"
    log "SUCCESS: $description: $file_path (owned by root:root, perms 644)"
    return 0
}

# Test if a command is available
test_command() {
    local cmd="$1"
    local description="${2:-Checking command}"
    
    if command -v "$cmd" >/dev/null 2>&1; then
        print_success "$description: $cmd (available)"
        log "SUCCESS: $description: $cmd (available)"
        return 0
    else
        print_error "$description: $cmd (NOT available)"
        log "ERROR: $description: $cmd (NOT available)"
        return 1
    fi
}

# Test if a file/directory exists
test_path() {
    local path="$1"
    local description="${2:-Checking path}"
    
    if [[ -e "$path" ]]; then
        print_success "$description: $path (exists)"
        log "SUCCESS: $description: $path (exists)"
        return 0
    else
        print_error "$description: $path (does not exist)"
        log "ERROR: $description: $path (does not exist)"
        return 1
    fi
}

# Test port forwarding
test_port_forward() {
    local host_port="$1"
    local guest_port="${2:-22}"
    local description="${3:-Testing port forward}"
    
    # This is a simplified test - in reality, we'd need to check if the VM is running
    # For now, we'll just verify the concept is sound
    print_info "$description: Host port $host_port → Guest port $guest_port"
    log "INFO: $description: Host port $host_port → Guest port $guest_port"
    return 0  # Placeholder - actual test would require VM to be running
}

# ============================================================================
# HOST IDENTIFICATION AND CONFIGURATION LOGGING
# ============================================================================

generate_host_id() {
    print_header "Generating Host Identification"
    
    # Collect host identifying information
    local hostname=""
    local mac_address=""
    local ip_address=""
    local os_info=""
    local kernel_version=""
    
    # Get hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    
    # Get MAC address (primary interface)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        mac_address=$(ifconfig | grep ether | head -1 | awk '{print $2}' 2>/dev/null || echo "unknown")
        ip_address=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unknown")
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        # Linux
        mac_address=$(ip link show | grep -v "LOOPBACK" | grep "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "unknown")
        ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    fi
    
    # Get OS info
    if [[ "$(uname)" == "Darwin" ]]; then
        os_info="macOS $(sw_vers -productVersion 2>/dev/null || echo "unknown")"
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        os_info="Linux $(hostnamectl | grep "Operating System" | cut -d: -f2 | xargs 2>/dev/null || echo "unknown")"
    else
        os_info="Unknown OS"
    fi
    
    # Get kernel version
    kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    
    # Create host ID JSON
    local host_id_json=$(cat <<EOF
{
  "host_id": "usb-compute-$(echo -n "${hostname}-${mac_address}" | md5sum | cut -d' ' -f1 | cut -c1-8)",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$hostname",
  "mac_address": "$mac_address",
  "ip_address": "$ip_address",
  "os_info": "$os_info",
  "kernel_version": "$kernel_version",
  "installation_version": "$VERSION",
  "script_name": "$SCRIPT_NAME"
}
EOF
)
    
    # Save host ID
    create_file "$HOST_ID_FILE" "$host_id_json" "Host identification file"
    
    # Also save to config file for completeness
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        create_file "$CONFIG_FILE" '{"installations":{},"host_id":'"$(cat "$HOST_ID_FILE")"',"last_updated":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' "Initial configuration file"
    else
        # Update existing config with host ID
        local temp_config=$(mktemp)
        jq --argjson host_id "$(cat "$HOST_ID_FILE")" '.host_id = $host_id | .last_updated = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || cp "$CONFIG_FILE" "$temp_config"
        mv "$temp_config" "$CONFIG_FILE"
    fi
    
    print_success "Host identification generated and saved"
    log "Host ID: $(jq -r '.host_id' "$HOST_ID_FILE")"
    return 0
}

# Load or create configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_info "Configuration file not found, creating new one"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        create_file "$CONFIG_FILE" '{"installations":{},"host_id":{},"last_updated":"1970-01-01T00:00:00Z"}' "Initial configuration file"
    fi
    
    # Ensure host ID exists
    if [[ ! -f "$HOST_ID_FILE" ]]; then
        generate_host_id
    fi
    
    return 0
}

# Save installation record to config
save_installation_record() {
    local component="$1"
    local path="$2"
    local version="${3:-unknown}"
    local status="${4:-installed}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would save installation record: $component -> $path (v$version, $status)"
        log "[DRY-RUN] Would save installation record: $component -> $path (v$version, $status)"
        return 0
    fi
    
    # Load existing config
    local config_content
    config_content=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{"installations":{}}')
    
    # Add or update installation record
    local updated_config=$(echo "$config_content" | jq --arg comp "$component" --arg path "$path" --arg ver "$version" --arg stat "$status" \
        '.installations[$comp] = {path: $path, version: $ver, status: $status, installed_at: "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' 2>/dev/null || echo "$config_content")
    
    # Update last updated timestamp
    updated_config=$(echo "$updated_config" | jq '.last_updated = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' 2>/dev/null || echo "$updated_config")
    
    # Save back
    echo "$updated_config" > "$CONFIG_FILE"
    
    print_success "Installation record saved for $component"
    log "Installation record saved: $component -> $path (v$version, $status)"
    return 0
}

# Test installation
test_installation() {
    local component="$1"
    local test_cmd="$2"
    local description="$3"
    
    print_header "Testing Installation: $component"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would test: $component with command: $test_cmd"
        log "[DRY-RUN] Would test: $component with command: $test_cmd"
        return 0
    fi
    
    # Run the test command
    if eval "$test_cmd" >"$TEST_RESULTS_FILE" 2>&1; then
        print_success "$description"
        log "SUCCESS: $description"
        # Log test results
        cat "$TEST_RESULTS_FILE" >> "$LOG_FILE"
        return 0
    else
        print_error "$description"
        log "ERROR: $description"
        # Log test results for debugging
        cat "$TEST_RESULTS_FILE" >> "$LOG_FILE"
        return 1
    fi
}

# Self-healing service restart
self_heal_service() {
    if [[ "$SELF_HEALING_MODE" != "true" ]]; then
        return 0
    fi
    
    print_header "Self-Healing Service Check"
    
    # Check if our auto-boot service is running (platform-specific)
    local service_running=false
    
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: Check LaunchAgent
        if launchctl list | grep -q "com.usbcompute.autostart"; then
            service_running=true
        fi
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        # Linux: Check systemd service
        if systemctl is-active --quiet usb-compute-vm.service 2>/dev/null; then
            service_running=true
        fi
    fi
    
    if [[ "$service_running" == "false" ]]; then
        print_warning "Auto-boot service is not running - attempting self-heal..."
        log "WARNING: Auto-boot service is not running - attempting self-heal"
        
        # Try to restart the service
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: Reload LaunchAgent
            local user_home="${HOME:-$USERPROFILE}"
            if [[ -f "$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist" ]]; then
                run_cmd "launchctl unload '$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist'" "Unloading LaunchAgent"
                run_cmd "launchctl load '$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist'" "Loading LaunchAgent"
            fi
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            # Linux: Restart systemd service
            run_cmd "systemctl daemon-reload" "Reloading systemd daemon"
            run_cmd "systemctl start usb-compute-vm.service" "Starting USB Compute VM service"
        fi
        
        # Verify service is now running
        service_running=false
        if [[ "$(uname)" == "Darwin" ]]; then
            if launchctl list | grep -q "com.usbcompute.autostart"; then
                service_running=true
            fi
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            if systemctl is-active --quiet usb-compute-vm.service 2>/dev/null; then
                service_running=true
            fi
        fi
        
        if [[ "$service_running" == "true" ]]; then
            print_success "Self-heal successful: Auto-boot service is now running"
            log "SUCCESS: Self-heal successful: Auto-boot service is now running"
        else
            print_error "Self-heal failed: Auto-boot service is still not running"
            log "ERROR: Self-heal failed: Auto-boot service is still not running"
        fi
    else
        print_info "Auto-boot service is running normally"
        log "INFO: Auto-boot service is running normally"
    fi
    
    return 0
}

# Comprehensive testing sweep
run_testing_sweep() {
    print_header "Running Comprehensive Testing Sweep"
    
    local tests_passed=0
    local tests_total=0
    
    # Test 1: Basic system commands
    ((tests_total++))
    if test_command "ls" "Basic command test"; then
        ((tests_passed++))
    fi
    
    # Test 2: File system access
    ((tests_total++))
    if test_path "/tmp" "Temp directory access"; then
        ((tests_passed++))
    fi
    
    # Test 3: Package manager access
    ((tests_total++))
    if test_command "apt-get" "Package manager access"; then
        ((tests_passed++))
    fi
    
    # Test 4: Git access
    ((tests_total++))
    if test_command "git" "Git access"; then
        ((tests_passed++))
    fi
    
    # Test 5: Python access
    ((tests_total++))
    if test_command "python3" "Python 3 access"; then
        ((tests_passed++))
    fi
    
    # Test 6: Node.js access
    ((tests_total++))
    if test_command "node" "Node.js access"; then
        ((tests_passed++))
    fi
    
    # Test 7: Directory creation and permissions
    ((tests_total++))
    local test_dir="/tmp/usb-test-$$"
    if run_cmd "mkdir -p '$test_dir'" "Create test directory" && \
       run_cmd "chown root:root '$test_dir'" "Set ownership to root" && \
       run_cmd "chmod 755 '$test_dir'" "Set permissions to 755" && \
       test_path "$test_dir" "Test directory exists"; then
        ((tests_passed++))
        # Clean up
        run_cmd "rm -rf '$test_dir'" "Clean up test directory"
    fi
    
    # Test 8: Network connectivity (basic)
    ((tests_total++))
    if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
        print_success "Network connectivity test: Internet accessible"
        log "SUCCESS: Network connectivity test: Internet accessible"
        ((tests_passed++))
    else
        print_warning "Network connectivity test: No internet access (may be offline)"
        log "WARNING: Network connectivity test: No internet access (may be offline)"
    fi
    
    # Test 9: Disk space
    ((tests_total++))
    local disk_space=$(df -h / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0B")
    if [[ "$disk_space" != "0B" ]]; then
        print_success "Disk space check: $disk_space available"
        log "SUCCESS: Disk space check: $disk_space available"
        ((tests_passed++))
    else
        print_error "Disk space check: Unable to determine available space"
        log "ERROR: Disk space check: Unable to determine available space"
    fi
    
    # Print test results
    print_header "Testing Sweep Results"
    echo "Tests passed: $tests_passed/$tests_total"
    log "Testing sweep completed: $tests_passed/$tests_total tests passed"
    
    if [[ "$tests_passed" -eq "$tests_total" ]]; then
        print_success "All tests passed!"
        log "All tests in sweep passed"
        return 0
    else
        print_warning "$((tests_total - tests_passed)) tests failed"
        log "WARNING: $((tests_total - tests_passed)) tests failed in sweep"
        return 1
    fi
}

# Cleanup and debloating function
run_cleanup() {
    print_header "Running Cleanup and Debloating Process"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would run cleanup and debloating process"
        log "[DRY-RUN] Would run cleanup and debloating process"
        return 0
    fi
    
    local cleanup_start_time=$(date +%s)
    local cleanup_log_entry="[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] CLEANUP STARTED"
    
    # Initialize cleanup log
    echo "$cleanup_log_entry" > "$CLEANUP_LOG_FILE"
    
    # Track what we cleaned
    local cleaned_items=()
    local freed_space_before=$(df -h / | awk 'NR==2 {print $3}' 2>/dev/null || echo "0B")
    
    # 1. Clean APT cache
    print_info "Cleaning APT package cache..."
    run_cmd "apt-get clean" "Cleaning APT package cache"
    run_cmd "apt-get autoclean" "Autocleaning APT package cache"
    cleaned_items+=("APT cache")
    
    # 2. Clean journal logs (if systemd is available)
    if command -v journalctl >/dev/null 2>&1; then
        print_info "Cleaning journal logs (keeping 2 days)..."
        run_cmd "journalctl --vacuum-time=2days" "Vacuuming journal logs"
        cleaned_items+=("Journal logs (older than 2 days)")
    fi
    
    # 3. Clean old log files in /var/log/
    print_info "Cleaning old log files in /var/log/..."
    # Find and remove log files older than 7 days, but keep recent ones
    local old_logs=$(find /var/log -name "*.log" -o -name "*.log.*" -o -name "*.gz" -type f -mtime +7 2>/dev/null | head -20)
    if [[ -n "$old_logs" ]]; then
        while IFS= read -r logfile; do
            if [[ -f "$logfile" ]]; then
                run_cmd "rm -f '$logfile'" "Removing old log file: $logfile"
                cleaned_items+=("Old log file: $(basename "$logfile")")
            fi
        done <<< "$old_logs"
    fi
    
    # 4. Clean temporary files
    print_info "Cleaning temporary files..."
    # Clean /tmp (but be careful not to break running processes)
    run_cmd "find /tmp -type f -atime +1 -delete 2>/dev/null || true" "Cleaning old temporary files in /tmp"
    run_cmd "find /tmp -type d -empty -delete 2>/dev/null || true" "Removing empty directories in /tmp"
    cleaned_items+=("Temporary files in /tmp")
    
    # 5. Clean thumbnail caches
    print_info "Cleaning thumbnail caches..."
    local thumb_caches=("${HOME:-$USERPROFILE}/.thumbnails" "${HOME:-$USERPROFILE}/.cache/thumbnails")
    for thumb_cache in "${thumb_caches[@]}"; do
        if [[ -d "$thumb_cache" ]]; then
            run_cmd "rm -rf '$thumb_cache'/* 2>/dev/null || true" "Cleaning thumbnail cache: $thumb_cache"
            cleaned_items+=("Thumbnail cache: $thumb_cache")
            mkdir -p "$thumb_cache"
        fi
    done
    
    # 6. Clean browser caches (if any browsers installed)
    print_info "Cleaning browser caches..."
    local browser_caches=(
        "${HOME:-$USERPROFILE}/.cache/mozilla"
        "${HOME:-$USERPROFILE}/.cache/google-chrome"
        "${HOME:-$USERPROFILE}/.cache/chromium"
        "${HOME:-$USERPROFILE}/.Library/Caches/com.apple.Safari"
    )
    for browser_cache in "${browser_caches[@]}"; do
        if [[ -d "$browser_cache" ]]; then
            run_cmd "rm -rf '$browser_cache'/* 2>/dev/null || true" "Cleaning browser cache: $browser_cache"
            cleaned_items+=("Browser cache: $(basename "$browser_cache")")
        fi
    done
    
    # 7. Clean application caches
    print_info "Cleaning application caches..."
    local app_caches=(
        "${HOME:-$USERPROFILE}/.cache/pip"
        "${HOME:-$USERPROFILE}/.cache/npm"
        "${HOME:-$USERPROFILE}/.cache/yarn"
        "${HOME:-$USERPROFILE}/.cargo/git"
        "${HOME:-$USERPROFILE}/.cargo/registry"
    )
    for app_cache in "${app_caches[@]}"; do
        if [[ -d "$app_cache" ]]; then
            run_cmd "rm -rf '$app_cache'/* 2>/dev/null || true" "Cleaning application cache: $app_cache"
            cleaned_items+=("Application cache: $(basename "$app_cache")")
        fi
    done
    
    # 8. Clean USB Compute Automation specific logs (keep recent ones)
    print_info "Cleaning USB Compute Automation logs..."
    local usb_log_dir="/var/log"
    if [[ -d "$usb_log_dir" ]]; then
        # Keep only recent logs (last 3 days) for our specific logs
        find "$usb_log_dir" -name "usb-essentials-install-*.log" -mtime +3 -delete 2>/dev/null || true
        find "$usb_log_dir" -name "usb-test-results-*.log" -mtime +3 -delete 2>/dev/null || true
        find "$usb_log_dir" -name "usb-cleanup-*.log" -mtime +3 -delete 2>/dev/null || true
        cleaned_items+=("Old USB Compute Automation logs (older than 3 days)")
    fi
    
    # 9. Clean persistent temporary directories
    print_info "Cleaning persistent temporary directories..."
    local temp_dirs=(
        "/opt/usb-compute-automation/tmp"
        "${HOME:-$USERPROFILE}/tmp"
        "/tmp"
    )
    for temp_dir in "${temp_dirs[@]}"; do
        if [[ -d "$temp_dir" ]]; then
            # Remove files older than 1 day
            run_cmd "find '$temp_dir' -type f -mtime +1 -delete 2>/dev/null || true" "Cleaning old files in $temp_dir"
            # Remove empty directories
            run_cmd "find '$temp_dir' -type d -empty -delete 2>/dev/null || true" "Removing empty directories in $temp_dir"
            cleaned_items+=("Temporary directory: $temp_dir")
        fi
    done
    
    # 10. Run final package cleanup
    print_info "Running final package cleanup..."
    run_cmd "apt-get autoremove -y" "Autoremoving unused packages"
    run_cmd "apt-get clean" "Cleaning package cache"
    cleaned_items+=("Unused packages and package cache")
    
    # Calculate freed space
    local freed_space_after=$(df -h / | awk 'NR==2 {print $3}' 2>/dev/null || echo "0B")
    
    # Log cleanup completion
    local cleanup_end_time=$(date +%s)
    local cleanup_duration=$((cleanup_end_time - cleanup_start_time))
    local cleanup_log_entry="[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] CLEANUP COMPLETED - Duration: ${cleanup_duration}s - Items cleaned: ${#cleaned_items[@]}"
    
    echo "$cleanup_log_entry" >> "$CLEANUP_LOG_FILE"
    
    # Print summary
    print_header "Cleanup Summary"
    echo "Cleanup duration: $cleanup_duration seconds"
    echo "Items cleaned: ${#cleaned_items[@]}"
    echo "Space before: $freed_space_before"
    echo "Space after: $freed_space_after"
    echo ""
    echo "Cleaned items:"
    for item in "${cleaned_items[@]}"; do
        echo "  - $item"
    done
    
    print_success "Cleanup and debloating process completed!"
    log "SUCCESS: Cleanup and debloating process completed - Duration: ${cleanup_duration}s - Items cleaned: ${#cleaned_items[@]}"
    
    return 0
}

# Self-healing service restart
self_heal_service() {
    if [[ "$SELF_HEALING_MODE" != "true" ]]; then
        return 0
    fi
    
    print_header "Self-Healing Service Check"
    
    # Check if our auto-boot service is running (platform-specific)
    local service_running=false
    
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: Check LaunchAgent
        if launchctl list | grep -q "com.usbcompute.autostart"; then
            service_running=true
        fi
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        # Linux: Check systemd service
        if systemctl is-active --quiet usb-compute-vm.service 2>/dev/null; then
            service_running=true
        fi
    fi
    
    if [[ "$service_running" == "false" ]]; then
        print_warning "Auto-boot service is not running - attempting self-heal..."
        log "WARNING: Auto-boot service is not running - attempting self-heal"
        
        # Try to restart the service
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: Reload LaunchAgent
            local user_home="${HOME:-$USERPROFILE}"
            if [[ -f "$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist" ]]; then
                run_cmd "launchctl unload '$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist'" "Unloading LaunchAgent"
                run_cmd "launchctl load '$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist'" "Loading LaunchAgent"
            fi
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            # Linux: Restart systemd service
            run_cmd "systemctl daemon-reload" "Reloading systemd daemon"
            run_cmd "systemctl start usb-compute-vm.service" "Starting USB Compute VM service"
        fi
        
        # Verify service is now running
        service_running=false
        if [[ "$(uname)" == "Darwin" ]]; then
            if launchctl list | grep -q "com.usbcompute.autostart"; then
                service_running=true
            fi
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            if systemctl is-active --quiet usb-compute-vm.service 2>/dev/null; then
                service_running=true
            fi
        fi
        
        if [[ "$service_running" == "true" ]]; then
            print_success "Self-heal successful: Auto-boot service is now running"
            log "SUCCESS: Self-heal successful: Auto-boot service is now running"
        else
            print_error "Self-heal failed: Auto-boot service is still not running"
            log "ERROR: Self-heal failed: Auto-boot service is still not running"
        fi
    else
        print_info "Auto-boot service is running normally"
        log "INFO: Auto-boot service is running normally"
    fi
    
    return 0
}

# Comprehensive testing sweep
run_testing_sweep() {
    print_header "Running Comprehensive Testing Sweep"
    
    local tests_passed=0
    local tests_total=0
    
    # Test 1: Basic system commands
    ((tests_total++))
    if test_command "ls" "Basic command test"; then
        ((tests_passed++))
    fi
    
    # Test 2: File system access
    ((tests_total++))
    if test_path "/tmp" "Temp directory access"; then
        ((tests_passed++))
    fi
    
    # Test 3: Package manager access
    ((tests_total++))
    if test_command "apt-get" "Package manager access"; then
        ((tests_passed++))
    fi
    
    # Test 4: Git access
    ((tests_total++))
    if test_command "git" "Git access"; then
        ((tests_passed++))
    fi
    
    # Test 5: Python access
    ((tests_total++))
    if test_command "python3" "Python 3 access"; then
        ((tests_passed++))
    fi
    
    # Test 6: Node.js access
    ((tests_total++))
    if test_command "node" "Node.js access"; then
        ((tests_passed++))
    fi
    
    # Test 7: Directory creation and permissions
    ((tests_total++))
    local test_dir="/tmp/usb-test-$$"
    if run_cmd "mkdir -p '$test_dir'" "Create test directory" && \
       run_cmd "chown root:root '$test_dir'" "Set ownership to root" && \
       run_cmd "chmod 755 '$test_dir'" "Set permissions to 755" && \
       test_path "$test_dir" "Test directory exists"; then
        ((tests_passed++))
        # Clean up
        run_cmd "rm -rf '$test_dir'" "Clean up test directory"
    fi
    
    # Test 8: Network connectivity (basic)
    ((tests_total++))
    if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
        print_success "Network connectivity test: Internet accessible"
        log "SUCCESS: Network connectivity test: Internet accessible"
        ((tests_passed++))
    else
        print_warning "Network connectivity test: No internet access (may be offline)"
        log "WARNING: Network connectivity test: No internet access (may be offline)"
    fi
    
    # Test 9: Disk space
    ((tests_total++))
    local disk_space=$(df -h / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0B")
    if [[ "$disk_space" != "0B" ]]; then
        print_success "Disk space check: $disk_space available"
        log "SUCCESS: Disk space check: $disk_space available"
        ((tests_passed++))
    else
        print_error "Disk space check: Unable to determine available space"
        log "ERROR: Disk space check: Unable to determine available space"
    fi
    
    # Print test results
    print_header "Testing Sweep Results"
    echo "Tests passed: $tests_passed/$tests_total"
    log "Testing sweep completed: $tests_passed/$tests_total tests passed"
    
    if [[ "$tests_passed" -eq "$tests_total" ]]; then
        print_success "All tests passed!"
        log "All tests in sweep passed"
        return 0
    else
        print_warning "$((tests_total - tests_passed)) tests failed"
        log "WARNING: $((tests_total - tests_passed)) tests failed in sweep"
        return 1
    fi
}

# ============================================================================
# HOST IDENTIFICATION AND CONFIGURATION LOGGING
# ============================================================================

generate_host_id() {
    print_header "Generating Host Identification"
    
    # Collect host identifying information
    local hostname=""
    local mac_address=""
    local ip_address=""
    local os_info=""
    local kernel_version=""
    
    # Get hostname
    hostname=$(hostname 2>/dev/null || echo "unknown")
    
    # Get MAC address (primary interface)
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS
        mac_address=$(ifconfig | grep ether | head -1 | awk '{print $2}' 2>/dev/null || echo "unknown")
        ip_address=$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "unknown")
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        # Linux
        mac_address=$(ip link show | grep -v "LOOPBACK" | grep "link/ether" | head -1 | awk '{print $2}' 2>/dev/null || echo "unknown")
        ip_address=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "unknown")
    fi
    
    # Get OS info
    if [[ "$(uname)" == "Darwin" ]]; then
        os_info="macOS $(sw_vers -productVersion 2>/dev/null || echo "unknown")"
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        os_info="Linux $(hostnamectl | grep "Operating System" | cut -d: -f2 | xargs 2>/dev/null || echo "unknown")"
    else
        os_info="Unknown OS"
    fi
    
    # Get kernel version
    kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    
    # Create host ID JSON
    local host_id_json=$(cat <<EOF
{
  "host_id": "usb-compute-$(echo -n "${hostname}-${mac_address}" | md5sum | cut -d' ' -f1 | cut -c1-8)",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "hostname": "$hostname",
  "mac_address": "$mac_address",
  "ip_address": "$ip_address",
  "os_info": "$os_info",
  "kernel_version": "$kernel_version",
  "installation_version": "$VERSION",
  "script_name": "$SCRIPT_NAME"
}
EOF
)
    
    # Save host ID
    create_file "$HOST_ID_FILE" "$host_id_json" "Host identification file"
    
    # Also save to config file for completeness
    if [[ ! -f "$CONFIG_FILE" ]]; then
        mkdir -p "$(dirname "$CONFIG_FILE")"
        create_file "$CONFIG_FILE" '{"installations":{},"host_id":'"$(cat "$HOST_ID_FILE")"',"last_updated":"'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' "Initial configuration file"
    else
        # Update existing config with host ID
        local temp_config=$(mktemp)
        jq --argjson host_id "$(cat "$HOST_ID_FILE")" '.host_id = $host_id | .last_updated = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' "$CONFIG_FILE" > "$temp_config" 2>/dev/null || cp "$CONFIG_FILE" "$temp_config"
        mv "$temp_config" "$CONFIG_FILE"
    fi
    
    print_success "Host identification generated and saved"
    log "Host ID: $(jq -r '.host_id' "$HOST_ID_FILE")"
    return 0
}

# Load or create configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_info "Configuration file not found, creating new one"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        create_file "$CONFIG_FILE" '{"installations":{},"host_id":{},"last_updated":"1970-01-01T00:00:00Z"}' "Initial configuration file"
    fi
    
    # Ensure host ID exists
    if [[ ! -f "$HOST_ID_FILE" ]]; then
        generate_host_id
    fi
    
    return 0
}

# Save installation record to config
save_installation_record() {
    local component="$1"
    local path="$2"
    local version="${3:-unknown}"
    local status="${4:-installed}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would save installation record: $component -> $path (v$version, $status)"
        log "[DRY-RUN] Would save installation record: $component -> $path (v$version, $status)"
        return 0
    fi
    
    # Load existing config
    local config_content
    config_content=$(cat "$CONFIG_FILE" 2>/dev/null || echo '{"installations":{}}')
    
    # Add or update installation record
    local updated_config=$(echo "$config_content" | jq --arg comp "$component" --arg path "$path" --arg ver "$version" --arg stat "$status" \
        '.installations[$comp] = {path: $path, version: $ver, status: $status, installed_at: "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}' 2>/dev/null || echo "$config_content")
    
    # Update last updated timestamp
    updated_config=$(echo "$updated_config" | jq '.last_updated = "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"' 2>/dev/null || echo "$updated_config")
    
    # Save back
    echo "$updated_config" > "$CONFIG_FILE"
    
    print_success "Installation record saved for $component"
    log "Installation record saved: $component -> $path (v$version, $status)"
    return 0
}

# Test installation
test_installation() {
    local component="$1"
    local test_cmd="$2"
    local description="$3"
    
    print_header "Testing Installation: $component"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY-RUN] Would test: $component with command: $test_cmd"
        log "[DRY-RUN] Would test: $component with command: $test_cmd"
        return 0
    fi
    
    # Run the test command
    if eval "$test_cmd" >"$TEST_RESULTS_FILE" 2>&1; then
        print_success "$description"
        log "SUCCESS: $description"
        # Log test results
        cat "$TEST_RESULTS_FILE" >> "$LOG_FILE"
        return 0
    else
        print_error "$description"
        log "ERROR: $description"
        # Log test results for debugging
        cat "$TEST_RESULTS_FILE" >> "$LOG_FILE"
        return 1
    fi
}

# Self-healing service restart
self_heal_service() {
    if [[ "$SELF_HEALING_MODE" != "true" ]]; then
        return 0
    fi
    
    print_header "Self-Healing Service Check"
    
    # Check if our auto-boot service is running (platform-specific)
    local service_running=false
    
    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS: Check LaunchAgent
        if launchctl list | grep -q "com.usbcompute.autostart"; then
            service_running=true
        fi
    elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
        # Linux: Check systemd service
        if systemctl is-active --quiet usb-compute-vm.service 2>/dev/null; then
            service_running=true
        fi
    fi
    
    if [[ "$service_running" == "false" ]]; then
        print_warning "Auto-boot service is not running - attempting self-heal..."
        log "WARNING: Auto-boot service is not running - attempting self-heal"
        
        # Try to restart the service
        if [[ "$(uname)" == "Darwin" ]]; then
            # macOS: Reload LaunchAgent
            local user_home="${HOME:-$USERPROFILE}"
            if [[ -f "$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist" ]]; then
                run_cmd "launchctl unload '$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist'" "Unloading LaunchAgent"
                run_cmd "launchctl load '$user_home/Library/LaunchAgents/com.usbcompute.autostart.plist'" "Loading LaunchAgent"
            fi
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            # Linux: Restart systemd service
            run_cmd "systemctl daemon-reload" "Reloading systemd daemon"
            run_cmd "systemctl start usb-compute-vm.service" "Starting USB Compute VM service"
        fi
        
        # Verify service is now running
        service_running=false
        if [[ "$(uname)" == "Darwin" ]]; then
            if launchctl list | grep -q "com.usbcompute.autostart"; then
                service_running=true
            fi
        elif [[ "$(expr substr $(uname -s) 1 5)" == "Linux" ]]; then
            if systemctl is-active --quiet usb-compute-vm.service 2>/dev/null; then
                service_running=true
            fi
        fi
        
        if [[ "$service_running" == "true" ]]; then
            print_success "Self-heal successful: Auto-boot service is now running"
            log "SUCCESS: Self-heal successful: Auto-boot service is now running"
        else
            print_error "Self-heal failed: Auto-boot service is still not running"
            log "ERROR: Self-heal failed: Auto-boot service is still not running"
        fi
    else
        print_info "Auto-boot service is running normally"
        log "INFO: Auto-boot service is running normally"
    fi
    
    return 0
}

# Comprehensive testing sweep
run_testing_sweep() {
    print_header "Running Comprehensive Testing Sweep"
    
    local tests_passed=0
    local tests_total=0
    
    # Test 1: Basic system commands
    ((tests_total++))
    if test_command "ls" "Basic command test"; then
        ((tests_passed++))
    fi
    
    # Test 2: File system access
    ((tests_total++))
    if test_path "/tmp" "Temp directory access"; then
        ((tests_passed++))
    fi
    
    # Test 3: Package manager access
    ((tests_total++))
    if test_command "apt-get" "Package manager access"; then
        ((tests_passed++))
    fi
    
    # Test 4: Git access
    ((tests_total++))
    if test_command "git" "Git access"; then
        ((tests_passed++))
    fi
    
    # Test 5: Python access
    ((tests_total++))
    if test_command "python3" "Python 3 access"; then
        ((tests_passed++))
    fi
    
    # Test 6: Node.js access
    ((tests_total++))
    if test_command "node" "Node.js access"; then
        ((tests_passed++))
    fi
    
    # Test 7: Directory creation and permissions
    ((tests_total++))
    local test_dir="/tmp/usb-test-$$"
    if run_cmd "mkdir -p '$test_dir'" "Create test directory" && \
       run_cmd "chown root:root '$test_dir'" "Set ownership to root" && \
       run_cmd "chmod 755 '$test_dir'" "Set permissions to 755" && \
       test_path "$test_dir" "Test directory exists"; then
        ((tests_passed++))
        # Clean up
        run_cmd "rm -rf '$test_dir'" "Clean up test directory"
    fi
    
    # Test 8: Network connectivity (basic)
    ((tests_total++))
    if ping -c 1 1.1.1.1 >/dev/null 2>&1; then
        print_success "Network connectivity test: Internet accessible"
        log "SUCCESS: Network connectivity test: Internet accessible"
        ((tests_passed++))
    else
        print_warning "Network connectivity test: No internet access (may be offline)"
        log "WARNING: Network connectivity test: No internet access (may be offline)"
    fi
    
    # Test 9: Disk space
    ((tests_total++))
    local disk_space=$(df -h / | awk 'NR==2 {print $4}' 2>/dev/null || echo "0B")
    if [[ "$disk_space" != "0B" ]]; then
        print_success "Disk space check: $disk_space available"
        log "SUCCESS: Disk space check: $disk_space available"
        ((tests_passed++))
    else
        print_error "Disk space check: Unable to determine available space"
        log "ERROR: Disk space check: Unable to determine available space"
    fi
    
    # Print test results
    print_header "Testing Sweep Results"
    echo "Tests passed: $tests_passed/$tests_total"
    log "Testing sweep completed: $tests_passed/$tests_total tests passed"
    
    if [[ "$tests_passed" -eq "$tests_total" ]]; then
        print_success "All tests passed!"
        log "All tests in sweep passed"
        return 0
    else
        print_warning "$((tests_total - tests_passed)) tests failed"
        log "WARNING: $((tests_total - tests_passed)) tests failed in sweep"
        return 1
    fi
}

# ============================================================================
# MAIN INSTALLATION FUNCTIONS
# ============================================================================

install_build_essentials() {
    print_header "Installing Build Essentials"
    
    # Update package list
    run_cmd "apt-get update" "Updating package list"
    
    # Install build-essential
    run_cmd "apt-get install -y build-essential" "Installing build-essential"
    
    # Test installation
    if test_installation "build-essential" "gcc --version" "GCC compiler"; then
        save_installation_record "build-essential" "/usr/bin/gcc" "$(gcc --version | head -1 | cut -d' ' -f1-3)" "installed"
    else
        print_error "Build essentials installation verification failed"
        return 1
    fi
    
    return 0
}

install_development_tools() {
    print_header "Installing Development Tools"
    
    # Install development tools
    run_cmd "apt-get install -y git curl wget vim nano htop" "Installing development tools"
    
    # Test installations
    local all_passed=true
    
    if ! test_installation "git" "git --version" "Git"; then
        all_passed=false
    fi
    
    if ! test_installation "curl" "curl --version" "Curl"; then
        all_passed=false
    fi
    
    if ! test_installation "wget" "wget --version" "Wget"; then
        all_passed=false
    fi
    
    if ! test_installation "vim" "vim --version | head -1" "Vim"; then
        all_passed=false
    fi
    
    if ! test_installation "nano" "nano --version | head -1" "Nano"; then
        all_passed=false
    fi
    
    if ! test_installation "htop" "htop --version | head -1" "Htop"; then
        all_passed=false
    fi
    
    if [[ "$all_passed" == "true" ]]; then
        save_installation_record "development-tools" "multiple" "various" "installed"
        return 0
    else
        print_error "Some development tools failed to install properly"
        return 1
    fi
}

install_python_tools() {
    print_header "Installing Python Tools"
    
    # Install Python and pip
    run_cmd "apt-get install -y python3 python3-pip python3-venv" "Installing Python 3 and pip"
    
    # Test installations
    if test_installation "python3" "python3 --version" "Python 3" && \
       test_installation "pip3" "pip3 --version" "Pip 3"; then
        save_installation_record "python-tools" "multiple" "Python 3 + Pip" "installed"
        return 0
    else
        print_error "Python tools installation verification failed"
        return 1
    fi
}

install_nodejs_tools() {
    print_header "Installing Node.js Tools"
    
    # Install Node.js and npm
    run_cmd "apt-get install -y nodejs npm" "Installing Node.js and npm"
    
    # Test installations
    if test_installation "node" "node --version" "Node.js" && \
       test_installation "npm" "npm --version" "Npm"; then
        save_installation_record "nodejs-tools" "multiple" "Node.js + Npm" "installed"
        return 0
    else
        print_error "Node.js tools installation verification failed"
        return 1
    fi
}

install_additional_tools() {
    print_header "Installing Additional Tools"
    
    # Install additional useful tools
    run_cmd "apt-get install -y make cmake pkg-config libssl-dev zlib1g-dev libffi-dev libreadline-dev libbz2-dev liblzma-dev sqlite3 libsqlite3-dev tk-dev libgdbm-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxslt1-dev libjpeg-dev libpng-dev unzip p7zip-full rsync ssh net-tools dnsutil" "Installing additional tools"
    
    # Test a few key installations
    if test_installation "make" "make --version" "Make" && \
       test_installation "cmake" "cmake --version | head -1" "CMake" && \
       test_installation "rsync" "rsync --version | head -1" "Rsync"; then
        save_installation_record "additional-tools" "multiple" "various" "installed"
        return 0
    else
        print_error "Some additional tools failed to install properly"
        return 1
    fi
}

install_llama_cpp() {
    print_header "Installing llama.cpp"
    
    # Install dependencies
    run_cmd "apt-get install -y cmake build-essential git" "Installing dependencies for llama.cpp"
    
    # Clone and build llama.cpp
    run_cmd "git clone https://github.com/ggerganov/llama.cpp $INSTALL_PATH_LLAMA" "Cloning llama.cpp repository"
    run_cmd "cd '$INSTALL_PATH_LLAMA' && make" "Building llama.cpp"
    
    # Test installation
    if test_path "$INSTALL_PATH_LLAMA/main" "llama.cpp main executable" && \
       test_installation "llama.cpp" "$INSTALL_PATH_LLAMA/main --help" "llama.cpp"; then
        save_installation_record "llama.cpp" "$INSTALL_PATH_LLAMA" "latest from github" "installed"
        return 0
    else
        print_error "llama.cpp installation verification failed"
        return 1
    fi
}

install_ollama() {
    print_header "Installing Ollama"
    
    # Install ollama
    run_cmd "curl -fsSL https://ollama.com/install.sh | sh" "Installing ollama"
    
    # Test installation
    if test_installation "ollama" "ollama --version" "Ollama"; then
        save_installation_record "ollama" "/usr/local/bin/ollama" "$(ollama --version)" "installed"
        return 0
    else
        print_error "Ollama installation verification failed"
        return 1
    fi
}

install_agent_harnesses() {
    print_header "Installing Agent Harnesses"
    
    # Install agent harnesses via pip
    run_cmd "pip3 install autogen-agentchat crewai langchain" "Installing agent harnesses"
    
    # Test installation (check if Python packages are importable)
    if run_cmd "python3 -c \"import autogen; import crewai; import langchain; print('All agent harnesses imported successfully')\"" "Testing agent harnesses import"; then
        save_installation_record "agent-harnesses" "Python site-packages" "latest from PyPI" "installed"
        return 0
    else
        print_error "Agent harnesses installation verification failed"
        return 1
    fi
}

install_ai_systems() {
    print_header "Installing AI Agent Systems"
    
    # Create AI systems directory
    if ! create_dir "$INSTALL_PATH_AI_SYSTEMS" "Creating AI systems directory"; then
        return 1
    fi
    
    # Ask about specific AI systems
    print_info "Which AI agent systems would you like to install?"
    
    local install_opencode=false
    local install_mistral_vibe=false
    local install_github_copilot_cli=false
    local install_gemini_cli=false
    local install_claude_code=false
    local install_cursor_cli=false
    local install_openclaw=false
    local install_hermes_agent=false
    
    # OpenClaw and Hermes-agent (Hemlock framework)
    if print_info "Do you want to install Hemlock framework components?" && \
       confirm "Install Hemlock framework components?"; then
        if confirm "Install OpenClaw (Control Plane)?"; then
            install_openclaw=true
        fi
        if confirm "Install Hermes-agent (Cognition Layer)?"; then
            install_hermes_agent=true
        fi
    fi
    
    # OpenAI-compatible systems
    if print_info "Do you want to install OpenAI-compatible CLI systems?" && \
       confirm "Install OpenAI-compatible CLI systems?"; then
        if confirm "Install Opencode?"; then
            install_opencode=true
        fi
        if confirm "Install Mistral Vibe?"; then
            install_mistral_vibe=true
        fi
        if confirm "Install GitHub Copilot CLI?"; then
            install_github_copilot_cli=true
        fi
        if confirm "Install Gemini CLI?"; then
            install_gemini_cli=true
        fi
        if confirm "Install Claude Code?"; then
            install_claude_code=true
        fi
        if confirm "Install Cursor CLI?"; then
            install_cursor_cli=true
        fi
    fi
    
    # Install OpenClaw if requested
    if [[ "$install_openclaw" == "true" ]]; then
        print_info "Installing OpenClaw (Control Plane)..."
        # OpenClaw is typically installed via npm or from source
        # For this example, we'll use a placeholder installation
        # In practice, this would be: npm install -g @openclaw/framework
        # or building from source
        if run_cmd "mkdir -p '$INSTALL_PATH_AI_SYSTEMS/openclaw' && echo 'OpenClaw placeholder' > '$INSTALL_PATH_AI_SYSTEMS/openclaw/README.md'"; then
            save_installation_record "openclaw" "$INSTALL_PATH_AI_SYSTEMS/openclaw" "placeholder" "installed"
            print_success "OpenClaw placeholder installed"
        else
            print_error "Failed to install OpenClaw placeholder"
        fi
    fi
    
    # Install Hermes-agent if requested
    if [[ "$install_hermes_agent" == "true" ]]; then
        print_info "Installing Hermes-agent (Cognition Layer)..."
        # Similar to OpenClaw, this would be installed via npm or from source
        if run_cmd "mkdir -p '$INSTALL_PATH_AI_SYSTEMS/hermes-agent' && echo 'Hermes-agent placeholder' > '$INSTALL_PATH_AI_SYSTEMS/hermes-agent/README.md'"; then
            save_installation_record "hermes-agent" "$INSTALL_PATH_AI_SYSTEMS/hermes-agent" "placeholder" "installed"
            print_success "Hermes-agent placeholder installed"
        else
            print_error "Failed to install Hermes-agent placeholder"
        fi
    fi
    
    # Install Opencode if requested
    if [[ "$install_opencode" == "true" ]]; then
        print_info "Installing Opencode..."
        # Opencode installation would depend on the specific implementation
        # For now, we'll create a placeholder
        if run_cmd "mkdir -p '$INSTALL_PATH_AI_SYSTEMS/opencode' && echo 'Opencode placeholder' > '$INSTALL_PATH_AI_SYSTEMS/opencode/README.md'"; then
            save_installation_record "opencode" "$INSTALL_PATH_AI_SYSTEMS/opencode" "placeholder" "installed"
            print_success "Opencode placeholder installed"
        else
            print_error "Failed to install Opencode placeholder"
        fi
    fi
    
    # Install Mistral Vibe if requested
    if [[ "$install_mistral_vibe" == "true" ]]; then
        print_info "Installing Mistral Vibe..."
        # Mistral Vibe would be installed similarly
        if run_cmd "mkdir -p '$INSTALL_PATH_AI_SYSTEMS/mistral-vibe' && echo 'Mistral Vibe placeholder' > '$INSTALL_PATH_AI_SYSTEMS/mistral-vibe/README.md'"; then
            save_installation_record "mistral-vibe" "$INSTALL_PATH_AI_SYSTEMS/mistral-vibe" "placeholder" "installed"
            print_success "Mistral Vibe placeholder installed"
        else
            print_error "Failed to install Mistral Vibe placeholder"
        fi
    fi
    
    # Install GitHub Copilot CLI if requested
    if [[ "$install_github_copilot_cli" == "true" ]]; then
        print_info "Installing GitHub Copilot CLI..."
        # GitHub Copilot CLI installation
        if run_cmd "npm install -g @githubnext/github-copilot-cli"; then
            save_installation_record "github-copilot-cli" "/usr/local/bin/github-copilot" "latest from npm" "installed"
            print_success "GitHub Copilot CLI installed successfully"
        else
            print_error "Failed to install GitHub Copilot CLI"
            if ! confirm "Continue despite GitHub Copilot CLI failure?" "n"; then
                return 1
            fi
        fi
    fi
    
    # Install Gemini CLI if requested
    if [[ "$install_gemini_cli" == "true" ]]; then
        print_info "Installing Gemini CLI..."
        # Gemini CLI installation (Google's CLI for Gemini AI)
        if run_cmd "npm install -g @google/gemini-cli"; then
            save_installation_record "gemini-cli" "/usr/local/bin/gemini" "latest from npm" "installed"
            print_success "Gemini CLI installed successfully"
        else
            print_error "Failed to install Gemini CLI"
            if ! confirm "Continue despite Gemini CLI failure?" "n"; then
                return 1
            fi
        fi
    fi
    
    # Install Claude Code if requested
    if [[ "$install_claude_code" == "true" ]]; then
        print_info "Installing Claude Code..."
        # Claude Code installation (Anthropic's CLI)
        if run_cmd "npm install -g @anthropic/claude-code"; then
            save_installation_record "claude-code" "/usr/local/bin/claude" "latest from npm" "installed"
            print_success "Claude Code installed successfully"
        else
            print_error "Failed to install Claude Code"
            if ! confirm "Continue despite Claude Code failure?" "n"; then
                return 1
            fi
        fi
    fi
    
    # Install Cursor CLI if requested
    if [[ "$install_cursor_cli" == "true" ]]; then
        print_info "Installing Cursor CLI..."
        # Cursor CLI installation
        if run_cmd "npm install -g @cursorsh/cli"; then
            save_installation_record "cursor-cli" "/usr/local/bin/cursor" "latest from npm" "installed"
            print_success "Cursor CLI installed successfully"
        else
            print_error "Failed to install Cursor CLI"
            if ! confirm "Continue despite Cursor CLI failure?" "n"; then
                return 1
            fi
        fi
    fi
    
    # Test AI systems installation (basic check)
    print_info "Verifying AI systems installation..."
    local ai_test_passed=true
    
    [[ "$install_openclaw" == "true" ]] && test_path "$INSTALL_PATH_AI_SYSTEMS/openclaw" || ai_test_passed=false
    [[ "$install_hermes_agent" == "true" ]] && test_path "$INSTALL_PATH_AI_SYSTEMS/hermes-agent" || ai_test_passed=false
    [[ "$install_opencode" == "true" ]] && test_path "$INSTALL_PATH_AI_SYSTEMS/opencode" || ai_test_passed=false
    [[ "$install_mistral_vibe" == "true" ]] && test_path "$INSTALL_PATH_AI_SYSTEMS/mistral-vibe" || ai_test_passed=false
    [[ "$install_github_copilot_cli" == "true" ]] && test_command "github-copilot --version" || ai_test_passed=false
    [[ "$install_gemini_cli" == "true" ]] && test_command "gemini --version" || ai_test_passed=false
    [[ "$install_claude_code" == "true" ]] && test_command "claude --version" || ai_test_passed=false
    [[ "$install_cursor_cli" == "true" ]] && test_command "cursor --version" || ai_test_passed=false
    
    if [[ "$ai_test_passed" == "true" ]]; then
        save_installation_record "ai-systems" "$INSTALL_PATH_AI_SYSTEMS" "various" "installed"
        print_success "AI systems installation completed"
        return 0
    else
        print_error "Some AI systems failed to install properly"
        return 1
    fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
    # Steps: [1/5] parse args, [2/5] check deps, [3/5] install, [4/5] configure, [5/5] validate
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --self-heal)
                SELF_HEALING_MODE=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --cleanup)
                RUN_CLEANUP=true
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [options]"
                echo "Options:"
                echo "  --dry-run, -n        Show what would be done without actually doing it"
                echo "  --self-heal          Enable self-healing mode (restarts services if needed)"
                echo "  --verbose, -v        Enable verbose output"
                echo "  --cleanup            Run cleanup and debloating process"
                echo "  --help, -h           Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done
    
    print_header "$SCRIPT_NAME v$VERSION"
    log "Starting $SCRIPT_NAME"
    
    # Show mode information
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "Running in DRY-RUN mode - no changes will be made"
        log "Running in DRY-RUN mode"
    fi
    
    if [[ "$SELF_HEALING_MODE" == "true" ]]; then
        print_info "Self-healing mode ENABLED"
        log "Self-healing mode enabled"
    fi
    
    if [[ "$VERBOSE" == "true" ]]; then
        print_info "Verbose mode ENABLED"
        log "Verbose mode enabled"
    fi
    
    if [[ "$RUN_CLEANUP" == "true" ]]; then
        print_info "Cleanup mode ENABLED"
        log "Cleanup mode enabled"
    fi
    
    # Initialize
    log "Initializing installation process"
    
    # Load or create configuration
    load_config
    
    # Generate or load host ID
    generate_host_id
    
    # Run self-heal check (if enabled)
    self_heal_service
    
    # Run cleanup if requested
    if [[ "$RUN_CLEANUP" == "true" ]]; then
        run_cleanup
        # After cleanup, exit unless other operations were also requested
        if [[ "$#" -eq 0 ]]; then
            print_success "Cleanup process completed. Exiting."
            exit 0
        fi
    fi
    
    # Run testing sweep to verify basic system functionality
    print_info "Running initial system validation..."
    if ! run_testing_sweep; then
        print_warning "Initial system validation had some issues, but continuing anyway..."
        log "WARNING: Initial system validation had some issues"
    fi
    
    # Install core components
    print_header "Starting Core Installation Process"
    
    local installation_steps=(
        "install_build_essentials:Build Essentials"
        "install_development_tools:Development Tools"
        "install_python_tools:Python Tools"
        "install_nodejs_tools:Node.js Tools"
        "install_additional_tools:Additional Tools"
    )
    
    local failed_steps=0
    local total_steps=${#installation_steps[@]}
    
    for step in "${installation_steps[@]}"; do
        IFS=':' read -r step_func step_name <<< "$step"
        print_header "Installing: $step_name"
        
        if $step_func; then
            print_success "Completed: $step_name"
        else
            print_error "Failed: $step_name"
            ((failed_steps++))
            
            # Ask if user wants to continue despite failure
            if ! confirm "Step '$step_name' failed. Continue with remaining steps?" "n"; then
                print_error "Installation aborted by user"
                log "Installation aborted by user after failure in $step_name"
                read -p "Press Enter to continue..."
                exit 1; print_error "aborted"
            fi
        fi
        
        echo ""
    done
    
    # Ask about optional components
    print_header "Optional Component Installation"
    
    # LLM engines
    if print_info "Do you want to install LLM engines?" && \
       confirm "Install LLM engines?"; then
        
        local install_llama=false
        local install_ollama=false
        
        if confirm "Install llama.cpp?"; then
            install_llama=true
        fi
        
        if confirm "Install ollama?"; then
            install_ollama=true
        fi
        
        if [[ "$install_llama" == "true" ]]; then
            if install_llama_cpp; then
                print_success "llama.cpp installed successfully"
            else
                print_error "llama.cpp installation failed"
                if ! confirm "Continue despite llama.cpp failure?" "n"; then
                    read -p "Press Enter to continue..."
                    exit 1; print_error "llama.cpp failed"
                fi
            fi
        fi
        
        if [[ "$install_ollama" == "true" ]]; then
            if install_ollama; then
                print_success "Ollama installed successfully"
            else
                print_error "Ollama installation failed"
                if ! confirm "Continue despite ollama failure?" "n"; then
                    read -p "Press Enter to continue..."
                    exit 1; print_error "ollama failed"
                fi
            fi
        fi
    fi
    
    # Agent harnesses
    if print_info "Do you want to install agent harnesses?" && \
       confirm "Install agent harnesses?"; then
        if install_agent_harnesses; then
            print_success "Agent harnesses installed successfully"
            else
                print_error "Agent harnesses installation failed"
                if ! confirm "Continue despite agent harnesses failure?" "n"; then
                    read -p "Press Enter to continue..."
                    exit 1; print_error "harnesses failed"
                fi
        fi
    fi
    
    # AI systems
    if print_info "Do you want to install AI agent systems?" && \
       confirm "Install AI agent systems?"; then
        if install_ai_systems; then
            print_success "AI systems installed successfully"
            else
                print_error "AI systems installation failed"
                if ! confirm "Continue despite AI systems failure?" "n"; then
                    read -p "Press Enter to continue..."
                    exit 1; print_error "ai systems failed"
                fi
        fi
    fi
    
    # Models directory
    if print_info "Do you want to set up a models directory for GGUF files?" && \
       confirm "Set up models directory?"; then
        # Ask for custom path
        read -p "$(echo -e "${YELLOW}Models directory path [/opt/models]: ${NC}")" models_path
        INSTALL_PATH_MODELS="${models_path:-/opt/models}"
        # Ensure path starts with /
        if [[ ! "$INSTALL_PATH_MODELS" =~ ^/ ]]; then
            INSTALL_PATH_MODELS="/${INSTALL_PATH_MODELS}"
        fi
        
        if create_dir "$INSTALL_PATH_MODELS" "Creating models directory"; then
            # Create README for models directory
            create_file "$INSTALL_PATH_MODELS/README.md" "# Models Directory\n\nThis directory is intended for storing GGUF model files for use with llama.cpp, ollama, etc.\n\n## Usage\n- Place .gguf model files in this directory\n- Reference them by full path when using with llama.cpp or ollama\n- Example: ./llama.cpp/main -m ./models/my-model.gguf -p \"Hello world\"" "Creating models directory README"
            save_installation_record "models-directory" "$INSTALL_PATH_MODELS" "directory" "created"
            print_success "Models directory set up at: $INSTALL_PATH_MODELS"
            else
                print_error "Failed to create models directory"
                if ! confirm "Continue despite models directory failure?" "n"; then
                    read -p "Press Enter to continue..."
                    exit 1; print_error "models dir failed"
                fi
        fi
    fi
    
    # Final validation
    print_header "Final Validation"
    
    # Run final testing sweep
    if run_testing_sweep; then
        print_success "Final validation passed!"
    else
        print_warning "Final validation had some issues, but installation may still be usable"
        log "WARNING: Final validation had some issues"
    fi
    
    # Self-heal check at the end
    self_heal_service
    
    # Final summary
    print_header "Installation Complete"
    
    if [[ "$failed_steps" -eq 0 ]]; then
        print_success "All core components installed successfully!"
        log "Installation completed successfully with 0 failed steps"
    else
        print_warning "Installation completed with $failed_steps failed step(s) out of $total_steps"
        log "Installation completed with $failed_steps failed step(s) out of $total_steps"
    fi
    
    print_info "Installation log saved to: $LOG_FILE"
    print_info "Host identification saved to: $HOST_ID_FILE"
    print_info "Configuration saved to: $CONFIG_FILE"
    if [[ -f "$TEST_RESULTS_FILE" ]]; then
        print_info "Test results saved to: $TEST_RESULTS_FILE"
    fi
    if [[ -f "$CLEANUP_LOG_FILE" ]]; then
        print_info "Cleanup log saved to: $CLEANUP_LOG_FILE"
    fi
    
    echo ""
    echo "Next Steps:"
    echo "1. Ensure your VM is configured for headless boot with USB passthrough"
    echo "2. Ensure SSH port forwarding is set up (Host:2222 → Guest:22)"
    echo "3. Plug in your USB drive to trigger auto-boot"
    echo "4. Connect via SSH: ssh -p 2222 user@localhost"
    echo "5. All installed tools will be available in the persistent environment"
    echo ""
    
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "This was a dry-run - no actual changes were made"
        log "DRY-RUN completed - no changes made"
    fi
    
    return 0
}

# Execute main function
main "$@"