#!/usr/bin/env bash
# ============================================================================
# System Manager (sysman) - USB Compute Automation System
# ============================================================================
#
# Whiptail-based interactive system management dashboard. Provides access to:
# - System Cleanup (clean-local.sh integration)
# - Disk Analysis
# - Failed Services
# - Startup Programs
# - Network Diagnostics
# - System Repair
# - Health Dashboard
#
# Requires: whiptail, bash
#
# Usage: ./sysman.sh
#
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_NAME="System Manager (sysman)"
VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEAN_SCRIPT="${SCRIPT_DIR}/scripts/clean-local.sh"
LOG_FILE="/tmp/sysman-$(date +%Y%m%d-%H%M%S).log"

# Dry-run mode
DRY_RUN=false

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

# Run a command with a hard wall-clock limit so read-only diagnostics can
# never stall the dashboard on a huge journal, a slow disk scan, or a wedged
# mount. Falls back to running unbounded if `timeout` is unavailable. Returns
# the command's exit status; a timeout surfaces as a non-zero code the caller
# can ignore (these are best-effort, informational probes).
run_bounded() {
    local secs="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "${secs}s" "$@"
    else
        "$@"
    fi
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

print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

# ============================================================================
# WHIPTAIL WRAPPER
# ============================================================================

# Check if whiptail is available
check_whiptail() {
    if ! command -v whiptail &>/dev/null; then
        print_error "whiptail is not installed"
        print_info "Install with: sudo apt-get install whiptail"
        return 1
    fi
    return 0
}

# ============================================================================
# SYSTEM CLEANUP
# ============================================================================

system_cleanup_menu() {
    if [[ -f "$CLEAN_SCRIPT" ]]; then
        print_info "Launching clean-local.sh..."
        bash "$CLEAN_SCRIPT"
    else
        print_warning "clean-local.sh not found at: $CLEAN_SCRIPT"
        print_info "Running built-in cleanup functions..."
        builtin_cleanup
    fi
}

builtin_cleanup() {
    print_header "System Cleanup"
    
    echo -e "${CYAN}1)${NC} Clean package manager cache"
    echo -e "${CYAN}2)${NC} Remove old kernels"
    echo -e "${CYAN}3)${NC} Clean temporary files"
    echo -e "${CYAN}4)${NC} Clean systemd journal logs"
    echo -e "${CYAN}5)${NC} Clean Docker (if installed)"
    echo -e "${CYAN}6)${NC} Clean npm/yarn cache"
    echo -e "${CYAN}7)${NC} Clean pip cache"
    echo -e "${CYAN}0)${NC} Back"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-7]: ${NC}")" choice
    
    case "$choice" in
        1)
            print_info "Cleaning package manager cache..."
            if command -v apt-get &>/dev/null; then
                run_or_dry sudo apt-get clean
                run_or_dry sudo apt-get autoremove -y
            elif command -v dnf &>/dev/null; then
                run_or_dry sudo dnf clean all
            elif command -v pacman &>/dev/null; then
                run_or_dry sudo pacman -Scc --noconfirm
            fi
            print_success "Package cache cleaned"
            ;;
        2)
            print_info "Removing old kernels..."
            if command -v apt-get &>/dev/null; then
                run_or_dry sudo apt-get autoremove --purge -y
            fi
            print_success "Old kernels removed"
            ;;
        3)
            print_info "Cleaning temporary files..."
            run_or_dry sudo rm -rf /tmp/* 2>/dev/null || true
            run_or_dry sudo rm -rf /var/tmp/* 2>/dev/null || true
            print_success "Temporary files cleaned"
            ;;
        4)
            print_info "Cleaning systemd journal logs..."
            if command -v journalctl &>/dev/null; then
                run_or_dry sudo journalctl --vacuum-time=7d
            fi
            print_success "Journal logs cleaned"
            ;;
        5)
            print_info "Cleaning Docker..."
            if command -v docker &>/dev/null; then
                run_or_dry docker system prune -af 2>/dev/null || true
                run_or_dry docker volume prune -f 2>/dev/null || true
            else
                print_warning "Docker not installed"
            fi
            ;;
        6)
            print_info "Cleaning npm/yarn cache..."
            if command -v npm &>/dev/null; then
                run_or_dry npm cache clean --force 2>/dev/null || true
            fi
            if command -v yarn &>/dev/null; then
                run_or_dry yarn cache clean 2>/dev/null || true
            fi
            print_success "npm/yarn cache cleaned"
            ;;
        7)
            print_info "Cleaning pip cache..."
            if command -v pip &>/dev/null; then
                run_or_dry pip cache purge 2>/dev/null || true
            fi
            if command -v pip3 &>/dev/null; then
                run_or_dry pip3 cache purge 2>/dev/null || true
            fi
            print_success "pip cache cleaned"
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
# DISK ANALYSIS
# ============================================================================

disk_analysis() {
    print_header "Disk Analysis"
    
    echo -e "${BOLD}Disk Usage Overview:${NC}"
    echo ""
    df -h | grep -vE 'tmpfs|udev|none' | head -20
    echo ""
    
    echo -e "${BOLD}Largest Directories in /home:${NC}"
    echo ""
    if command -v ncdu &>/dev/null; then
        print_info "Use 'ncdu /home' for interactive analysis"
    else
        # Bounded: a deep/large home tree must not stall the dashboard.
        run_bounded 10 du -h --max-depth=2 /home 2>/dev/null | sort -hr | head -20 \
            || print_warning "Directory scan timed out — /home is large; use 'ncdu /home' for detail"
    fi
    echo ""

    echo -e "${BOLD}Largest Files in /home (depth-limited):${NC}"
    echo ""
    # Bounded + depth-limited: an unbounded `find /home -type f` walks every
    # file (caches, node_modules, …) and can run for minutes. Cap traversal
    # depth and wall-clock time so this stays an at-a-glance probe.
    run_bounded 10 find /home -maxdepth 4 -type f -size +50M -exec du -h {} + 2>/dev/null \
        | sort -hr | head -20 \
        || print_warning "File scan timed out — use 'ncdu /home' for a full breakdown"
    echo ""
    
    echo -e "${BOLD}Inode Usage:${NC}"
    echo ""
    df -i | grep -vE 'tmpfs|udev|none' | head -10
    echo ""
    
    echo -e "${BOLD}Disk Space Warning:${NC}"
    echo ""
    while read -r line; do
        local usage=$(echo "$line" | awk '{print $5}' | sed 's/%//')
        local mount=$(echo "$line" | awk '{print $6}')
        if [[ "$usage" -gt 90 ]]; then
            print_error "CRITICAL: $mount is ${usage}% full!"
        elif [[ "$usage" -gt 80 ]]; then
            print_warning "WARNING: $mount is ${usage}% full"
        fi
    done < <(df -h | grep -vE 'tmpfs|udev|none' | tail -n +2)
}

# ============================================================================
# FAILED SERVICES
# ============================================================================

failed_services() {
    print_header "Failed Services"
    
    if ! command -v systemctl &>/dev/null; then
        print_warning "systemctl not available"
        return 1
    fi
    
    echo -e "${BOLD}Failed Systemd Services:${NC}"
    echo ""
    
    local failed_services
    failed_services=$(systemctl --failed --no-legend 2>/dev/null || true)
    
    if [[ -z "$failed_services" ]]; then
        print_success "No failed services found"
    else
        echo "$failed_services"
        echo ""
        
        echo -e "${BOLD}Service Details:${NC}"
        echo ""
        while IFS= read -r service; do
            local service_name
            service_name=$(echo "$service" | awk '{print $1}')
            echo -e "${CYAN}$service_name${NC}"
            run_bounded 5 systemctl status "$service_name" --no-pager 2>/dev/null | head -10 || true
            echo ""
        done <<< "$failed_services"
    fi

    echo -e "${BOLD}Recent Journal Errors:${NC}"
    echo ""
    # Bounded: journalctl can take many seconds on a large journal.
    run_bounded 15 journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | tail -20 \
        || print_warning "Journal query timed out — journal may be large"
    echo ""
}

# ============================================================================
# STARTUP PROGRAMS
# ============================================================================

startup_programs() {
    print_header "Startup Programs"
    
    echo -e "${BOLD}Systemd Services Enabled:${NC}"
    echo ""
    systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null | head -30 || true
    echo ""
    
    echo -e "${BOLD}User Services:${NC}"
    echo ""
    systemctl --user list-unit-files --type=service --state=enabled --no-pager 2>/dev/null | head -20 || true
    echo ""
    
    echo -e "${BOLD}Cron Jobs (current user):${NC}"
    echo ""
    crontab -l 2>/dev/null || echo "No crontab entries"
    echo ""
    
    echo -e "${BOLD}System Cron Jobs:/etc/cron.d/${NC}"
    echo ""
    ls -la /etc/cron.d/ 2>/dev/null || echo "No /etc/cron.d directory"
    echo ""
    
    if [[ -f /etc/rc.local ]]; then
        echo -e "${BOLD}rc.local:${NC}"
        echo ""
        cat /etc/rc.local
        echo ""
    fi
    
    echo -e "${BOLD}Boot Scripts:/etc/init.d/${NC}"
    echo ""
    ls -la /etc/init.d/ 2>/dev/null | head -20 || echo "No /etc/init.d directory"
    echo ""
}

# ============================================================================
# NETWORK DIAGNOSTICS
# ============================================================================

network_diagnostics() {
    print_header "Network Diagnostics"
    
    echo -e "${BOLD}Network Interfaces:${NC}"
    echo ""
    ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "No network tools available"
    echo ""
    
    echo -e "${BOLD}Routing Table:${NC}"
    echo ""
    ip route show 2>/dev/null || route -n 2>/dev/null || echo "No routing tools available"
    echo ""
    
    echo -e "${BOLD}DNS Resolution:${NC}"
    echo ""
    if command -v nslookup &>/dev/null; then
        run_bounded 6 nslookup google.com 2>/dev/null | head -10 || echo "(DNS lookup timed out or failed)"
    elif command -v dig &>/dev/null; then
        run_bounded 6 dig google.com +short 2>/dev/null || echo "(DNS lookup timed out or failed)"
    else
        echo "No DNS tools available"
    fi
    echo ""
    
    echo -e "${BOLD}Open Ports:${NC}"
    echo ""
    if command -v ss &>/dev/null; then
        ss -tuln 2>/dev/null | head -20 || true
    elif command -v netstat &>/dev/null; then
        netstat -tuln 2>/dev/null | head -20 || true
    else
        echo "No port scanning tools available"
    fi
    echo ""
    
    echo -e "${BOLD}Internet Connectivity:${NC}"
    echo ""
    # -W 2 caps per-packet wait; run_bounded is a belt-and-suspenders ceiling
    # so a black-holed network can never hang the dashboard.
    if run_bounded 8 ping -c 3 -W 2 8.8.8.8 &>/dev/null; then
        print_success "Internet connection: OK"
    else
        print_error "Internet connection: FAILED (or timed out)"
    fi
    echo ""
    
    echo -e "${BOLD}Default Gateway:${NC}"
    echo ""
    ip route show default 2>/dev/null || route -n 2>/dev/null | grep default || echo "No default gateway found"
    echo ""
}

# ============================================================================
# SYSTEM REPAIR
# ============================================================================

system_repair() {
    print_header "System Repair"
    
    echo -e "${CYAN}1)${NC} Fix broken packages"
    echo -e "${CYAN}2)${NC} Repair filesystem (fsck)"
    echo -e "${CYAN}3)${NC} Reset systemd services"
    echo -e "${CYAN}4)${NC} Reinstall kernel"
    echo -e "${CYAN}5)${NC} Fix GRUB bootloader"
    echo -e "${CYAN}6)${NC} Restore default network config"
    echo -e "${CYAN}7)${NC} Check and repair SSH keys"
    echo -e "${CYAN}0)${NC} Back"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Select option [0-7]: ${NC}")" choice
    
    case "$choice" in
        1)
            print_info "Fixing broken packages..."
            if command -v apt-get &>/dev/null; then
                run_or_dry sudo apt-get update
                run_or_dry sudo apt-get install -f -y
                run_or_dry sudo dpkg --configure -a
            elif command -v dnf &>/dev/null; then
                run_or_dry sudo dnf check
                run_or_dry sudo dnf distro-sync
            fi
            print_success "Package repair completed"
            ;;
        2)
            print_warning "Filesystem repair requires unmounting the partition"
            print_info "This is typically done from a live USB or recovery mode"
            print_info "For now, running fsck in read-only mode on /..."
            if command -v fsck &>/dev/null; then
                run_or_dry sudo fsck -n / 2>/dev/null || true
            fi
            ;;
        3)
            print_info "Resetting systemd services..."
            if command -v systemctl &>/dev/null; then
                run_or_dry sudo systemctl daemon-reload
                run_or_dry sudo systemctl reset-failed
            fi
            print_success "Systemd reset completed"
            ;;
        4)
            print_warning "Kernel reinstallation is a high-risk operation"
            print_info "Please consult documentation before proceeding"
            if command -v apt-get &>/dev/null; then
                echo "Available kernels:"
                apt list --installed 2>/dev/null | grep linux-image || true
            fi
            ;;
        5)
            print_info "Checking GRUB bootloader..."
            if command -v update-grub &>/dev/null; then
                run_or_dry sudo update-grub
            elif command -v grub-mkconfig &>/dev/null; then
                run_or_dry sudo grub-mkconfig -o /boot/grub/grub.cfg
            fi
            print_success "GRUB update completed"
            ;;
        6)
            print_info "Restoring default network configuration..."
            if [[ -f /etc/network/interfaces ]]; then
                run_or_dry sudo cp /etc/network/interfaces /etc/network/interfaces.backup.$(date +%s)
            fi
            print_info "Network configuration backed up"
            print_info "Manual configuration may be required"
            ;;
        7)
            print_info "Checking SSH keys..."
            if [[ -d ~/.ssh ]]; then
                ls -la ~/.ssh/
                echo ""
                if [[ -f ~/.ssh/id_rsa ]]; then
                    ssh-keygen -l -f ~/.ssh/id_rsa 2>/dev/null || echo "Invalid key"
                fi
                if [[ -f ~/.ssh/id_ed25519 ]]; then
                    ssh-keygen -l -f ~/.ssh/id_ed25519 2>/dev/null || echo "Invalid key"
                fi
            else
                print_warning "No .ssh directory found"
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
# HEALTH DASHBOARD
# ============================================================================

health_dashboard() {
    print_header "System Health Dashboard"
    
    echo -e "${BOLD}System Information:${NC}"
    echo ""
    echo "Hostname: $(hostname)"
    echo "Kernel: $(uname -r)"
    echo "Uptime: $(uptime -p 2>/dev/null || uptime)"
    echo "Load Average: $(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "N/A")"
    echo ""
    
    echo -e "${BOLD}CPU Usage:${NC}"
    echo ""
    if command -v mpstat &>/dev/null; then
        mpstat 1 1 2>/dev/null | tail -1 || true
    else
        top -bn1 | grep "Cpu(s)" | awk '{print "User: "$2"% System: "$4"% Idle: "$8"%"}' || true
    fi
    echo ""
    
    echo -e "${BOLD}Memory Usage:${NC}"
    echo ""
    free -h 2>/dev/null || echo "free command not available"
    echo ""
    
    echo -e "${BOLD}Disk Usage:${NC}"
    echo ""
    df -h / 2>/dev/null | tail -1 || echo "df command not available"
    echo ""
    
    echo -e "${BOLD}Top Processes by CPU:${NC}"
    echo ""
    ps aux --sort=-%cpu 2>/dev/null | head -6 || ps aux 2>/dev/null | head -6
    echo ""
    
    echo -e "${BOLD}Top Processes by Memory:${NC}"
    echo ""
    ps aux --sort=-%mem 2>/dev/null | head -6 || ps aux 2>/dev/null | head -6
    echo ""
    
    echo -e "${BOLD}Recent Logins:${NC}"
    echo ""
    last -10 2>/dev/null || echo "last command not available"
    echo ""
    
    echo -e "${BOLD}System Errors (last hour):${NC}"
    echo ""
    journalctl -p err --since "1 hour ago" --no-pager 2>/dev/null | tail -10 || echo "No journal errors"
    echo ""
}

# ============================================================================
# MAIN MENU (WHIPTAIL)
# ============================================================================

main_menu_whiptail() {
    if ! check_whiptail; then
        # Fallback to text menu
        main_menu_text
        return
    fi
    
    while true; do
        local choice
        choice=$(whiptail --title "$SCRIPT_NAME v$VERSION" \
            --menu "Select an option:" 20 70 12 \
            "1" "System Cleanup" \
            "2" "Disk Analysis" \
            "3" "Failed Services" \
            "4" "Startup Programs" \
            "5" "Network Diagnostics" \
            "6" "System Repair" \
            "7" "Health Dashboard" \
            "8" "System Information" \
            "9" "Process Monitor" \
            "10" "Log Viewer" \
            "0" "Exit" \
            3>&1 1>&2 2>&3)
        
        case "$choice" in
            1) system_cleanup_menu ;;
            2) disk_analysis ;;
            3) failed_services ;;
            4) startup_programs ;;
            5) network_diagnostics ;;
            6) system_repair ;;
            7) health_dashboard ;;
            8) show_system_info ;;
            9) show_process_monitor ;;
            10) show_log_viewer ;;
            0) 
                print_info "Exiting $SCRIPT_NAME..."
                exit 0
                ;;
            *) 
                if [[ -z "$choice" ]]; then
                    print_info "Exiting $SCRIPT_NAME..."
                    exit 0
                fi
                print_error "Invalid option: $choice"
                ;;
        esac
        
        echo ""
        read -p "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" _
    done
}

# ============================================================================
# TEXT MENU (FALLBACK)
# ============================================================================

main_menu_text() {
    while true; do
        print_header "$SCRIPT_NAME v$VERSION"
        
        echo -e "${CYAN}1)${NC} System Cleanup"
        echo -e "${CYAN}2)${NC} Disk Analysis"
        echo -e "${CYAN}3)${NC} Failed Services"
        echo -e "${CYAN}4)${NC} Startup Programs"
        echo -e "${CYAN}5)${NC} Network Diagnostics"
        echo -e "${CYAN}6)${NC} System Repair"
        echo -e "${CYAN}7)${NC} Health Dashboard"
        echo -e "${CYAN}8)${NC} System Information"
        echo -e "${CYAN}9)${NC} Process Monitor"
        echo -e "${CYAN}10)${NC} Log Viewer"
        echo -e "${CYAN}0)${NC} Exit"
        echo ""
        
        read -p "$(echo -e "${YELLOW}Select option [0-10]: ${NC}")" choice
        
        case "$choice" in
            1) system_cleanup_menu ;;
            2) disk_analysis ;;
            3) failed_services ;;
            4) startup_programs ;;
            5) network_diagnostics ;;
            6) system_repair ;;
            7) health_dashboard ;;
            8) show_system_info ;;
            9) show_process_monitor ;;
            10) show_log_viewer ;;
            0)
                print_info "Exiting $SCRIPT_NAME..."
                exit 0
                ;;
            *)
                print_error "Invalid option"
                ;;
        esac
        
        echo ""
        read -p "$(echo -e "${YELLOW}Press Enter to continue...${NC}")" _
    done
}

# ============================================================================
# ADDITIONAL FUNCTIONS
# ============================================================================

show_system_info() {
    print_header "System Information"
    echo ""
    echo -e "${BOLD}Operating System:${NC}"
    cat /etc/os-release 2>/dev/null | head -5 || echo "Unknown"
    echo ""
    echo -e "${BOLD}Kernel:${NC}"
    uname -a
    echo ""
    echo -e "${BOLD}CPU:${NC}"
    lscpu 2>/dev/null | grep -E 'Model name|Socket|Core|Thread|CPU\(s\)' | head -10 || echo "lscpu not available"
    echo ""
    echo -e "${BOLD}Memory:${NC}"
    free -h 2>/dev/null || echo "free not available"
    echo ""
    echo -e "${BOLD}Disk:${NC}"
    lsblk 2>/dev/null | head -10 || echo "lsblk not available"
    echo ""
    echo -e "${BOLD}Network:${NC}"
    ip addr show 2>/dev/null | grep -E 'inet |link/' | head -10 || echo "ip not available"
    echo ""
}

show_process_monitor() {
    print_header "Process Monitor"
    echo ""
    echo -e "${BOLD}Top Processes by CPU:${NC}"
    echo ""
    ps aux --sort=-%cpu 2>/dev/null | head -11 || ps aux 2>/dev/null | head -11
    echo ""
    echo -e "${BOLD}Top Processes by Memory:${NC}"
    echo ""
    ps aux --sort=-%mem 2>/dev/null | head -11 || ps aux 2>/dev/null | head -11
    echo ""
    echo -e "${BOLD}Process Count:${NC}"
    echo "Total: $(ps aux 2>/dev/null | wc -l || echo "N/A")"
    echo "Running: $(ps aux 2>/dev/null | grep -c '[R]' || echo "N/A")"
    echo "Sleeping: $(ps aux 2>/dev/null | grep -c '[S]' || echo "N/A")"
    echo ""
}

show_log_viewer() {
    print_header "Log Viewer"
    echo ""
    echo -e "${BOLD}Recent System Logs:${NC}"
    echo ""
    journalctl --since "1 hour ago" --no-pager 2>/dev/null | tail -30 || echo "journalctl not available"
    echo ""
    echo -e "${BOLD}Recent Auth Logs:${NC}"
    echo ""
    tail -20 /var/log/auth.log 2>/dev/null || echo "No auth.log or not readable"
    echo ""
    echo -e "${BOLD}Recent Syslog:${NC}"
    echo ""
    tail -20 /var/log/syslog 2>/dev/null || echo "No syslog or not readable"
    echo ""
}

# ============================================================================
# INITIALIZATION
# ============================================================================

initialize() {
    # Create log file
    : > "$LOG_FILE"
    log "Starting $SCRIPT_NAME v$VERSION"
    
    # Check dependencies
    local missing_deps=()
    for cmd in whiptail; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_warning "Missing optional dependencies: ${missing_deps[*]}"
        print_info "Text menu will be used as fallback"
    fi
}

# ============================================================================
# MAIN ENTRY POINT
# ============================================================================

main() {
    initialize
    
    # Track if CLI arguments were provided
    local cli_args_provided=false
    [[ $# -gt 0 ]] && cli_args_provided=true
    
    # Parse command-line arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n)
                DRY_RUN=true
                shift
                ;;
            --cleanup|-c) system_cleanup_menu; shift ;;
            --disk|-d) disk_analysis; shift ;;
            --services|-s) failed_services; shift ;;
            --startup|-S) startup_programs; shift ;;
            --network|-N) network_diagnostics; shift ;;
            --repair|-r) system_repair; shift ;;
            --health|-H) health_dashboard; shift ;;
            --info|-i) show_system_info; shift ;;
            --process|-p) show_process_monitor; shift ;;
            --logs|-l) show_log_viewer; shift ;;
            --text|-t) main_menu_text; shift ;;
            --help|-h)
                echo "System Manager (sysman) - USB Compute Automation System"
                echo ""
                echo "Usage:"
                echo "  $0                  Interactive menu (whiptail or text fallback)"
                echo "  $0 --dry-run        Dry-run mode (no changes made)"
                echo "  $0 --cleanup        System Cleanup"
                echo "  $0 --disk           Disk Analysis"
                echo "  $0 --services       Failed Services"
                echo "  $0 --startup        Startup Programs"
                echo "  $0 --network|-N    Network Diagnostics"
                echo "  $0 --repair         System Repair"
                echo "  $0 --health         Health Dashboard"
                echo "  $0 --info           System Information"
                echo "  $0 --process        Process Monitor"
                echo "  $0 --logs           Log Viewer"
                echo "  $0 --text           Force text menu (no whiptail)"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use $0 --help for usage information"
                exit 1
                ;;
        esac
    done
    
    # If no arguments provided, run interactive menu
    if [[ "$cli_args_provided" == "false" ]]; then
        if check_whiptail; then
            main_menu_whiptail
        else
            main_menu_text
        fi
    fi
}

# Run main function
main "$@"