#!/usr/bin/env bash
# ============================================================================
# SSH Host Manager - USB Compute Automation System
# ============================================================================
#
# Manages SSH host aliases stored in ~/.ssh/hosts_usb. Each host entry
# includes: alias, hostname, user, port, key_path, and optional description.
#
# Features:
# - Add/remove/list/edit SSH host configurations
# - Connect to hosts by alias
# - Push/pull files using scp/rsync per host
# - Generate SSH config entries
# - Test SSH connectivity
# - Import from existing SSH config
#
# Usage:
#   ./ssh_host_manager.sh                      # Interactive menu
#   ./ssh_host_manager.sh --list               # List all hosts
#   ./ssh_host_manager.sh --add alias host     # Add host interactively
#   ./ssh_host_manager.sh --connect alias      # Connect to host
#   ./ssh_host_manager.sh --push alias src dst # Push file to host
#   ./ssh_host_manager.sh --pull alias src dst # Pull file from host
#   ./ssh_host_manager.sh --sync alias src dst # rsync to/from host
#   ./ssh_host_manager.sh --generate           # Generate SSH config
#
# ============================================================================

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

HOSTS_FILE="${HOME}/.ssh/hosts_usb"
SSH_CONFIG_FILE="${HOME}/.ssh/config"
HOSTS_BACKUP_DIR="${HOME}/.ssh/hosts_backups"
# Format: alias|hostname|user|port|key_path|description

# Dry-run mode
DRY_RUN=false

# Track if CLI arguments were processed
CLI_ARG_PROCESSED=false
[[ $# -gt 0 ]] && CLI_ARG_PROCESSED=true

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

# Report a mutation outcome honestly: in dry-run nothing was written, so do
# not assert success.
say_done() {
    if [[ "$DRY_RUN" == "true" ]]; then
        print_info "[DRY RUN] No write performed — would have: $*"
    else
        print_success "$*"
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

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

print_header() {
    echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}\n"
}

# ============================================================================
# INITIALIZATION
# ============================================================================

init_hosts_file() {
    mkdir -p "$(dirname "$HOSTS_FILE")"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        cat > "$HOSTS_FILE" << 'EOF'
# ============================================================================
# USB Compute Automation - SSH Host Aliases
# ============================================================================
# Format: alias|hostname|user|port|key_path|description
# Example: vps1|192.168.1.100|root|22|~/.ssh/id_rsa|Production VPS
#
# Lines starting with # are comments
# Empty lines are ignored
# ============================================================================

EOF
        print_success "Created hosts file: $HOSTS_FILE"
    fi
}

backup_hosts() {
    if [[ -f "$HOSTS_FILE" ]] && [[ -s "$HOSTS_FILE" ]]; then
        if [[ "$DRY_RUN" == "true" ]]; then
            print_info "[DRY RUN] Would back up $HOSTS_FILE before mutation"
            return 0
        fi
        mkdir -p "$HOSTS_BACKUP_DIR"
        local backup_file="$HOSTS_BACKUP_DIR/hosts-$(date +%Y%m%d-%H%M%S).txt"
        cp "$HOSTS_FILE" "$backup_file"
        print_info "Backup saved: $backup_file"
    fi
}

# ============================================================================
# HOST OPERATIONS
# ============================================================================

# List all hosts in a formatted table
list_hosts() {
    local format="${1:-table}"
    
    if [[ ! -f "$HOSTS_FILE" ]] || [[ ! -s "$HOSTS_FILE" ]]; then
        print_warning "No hosts found. File: $HOSTS_FILE"
        return 0
    fi
    
    # Extract hosts
    local -a aliases=()
    local -a hostnames=()
    local -a users=()
    local -a ports=()
    local -a keys=()
    local -a descriptions=()
    
    while IFS='|' read -r alias hostname user port key desc; do
        # Skip comments and blank lines
        [[ "$alias" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$alias" ]] && continue
        
        aliases+=("$alias")
        hostnames+=("$hostname")
        users+=("$user")
        ports+=("$port")
        keys+=("$key")
        descriptions+=("$desc")
    done < "$HOSTS_FILE"
    
    if [[ ${#aliases[@]} -eq 0 ]]; then
        print_warning "No hosts found in $HOSTS_FILE"
        return 0
    fi
    
    case "$format" in
        table)
            printf "\n${BOLD}%-15s %-25s %-12s %-6s %-30s %s${NC}\n" \
                "ALIAS" "HOSTNAME" "USER" "PORT" "KEY" "DESCRIPTION"
            echo "────────────────────────────────────────────────────────────────────────────────────────────────────────────────"
            for i in "${!aliases[@]}"; do
                local key_display="${keys[$i]}"
                [[ "$key_display" == "~/.ssh/id_rsa" ]] && key_display="(default)"
                [[ -z "$key_display" ]] && key_display="(default)"
                
                printf "${CYAN}%-15s${NC} %-25s %-12s %-6s %-30s ${YELLOW}%s${NC}\n" \
                    "${aliases[$i]}" \
                    "${hostnames[$i]}" \
                    "${users[$i]}" \
                    "${ports[$i]}" \
                    "$key_display" \
                    "${descriptions[$i]}"
            done
            echo ""
            print_info "Total: ${#aliases[@]} hosts"
            ;;
        csv)
            for i in "${!aliases[@]}"; do
                echo "${aliases[$i]},${hostnames[$i]},${users[$i]},${ports[$i]},${keys[$i]},\"${descriptions[$i]}\""
            done
            ;;
        json)
            echo "["
            local last=$((${#aliases[@]} - 1))
            for i in "${!aliases[@]}"; do
                printf '  {"alias": "%s", "hostname": "%s", "user": "%s", "port": "%s", "key": "%s", "description": "%s"}' \
                    "${aliases[$i]}" "${hostnames[$i]}" "${users[$i]}" "${ports[$i]}" "${keys[$i]}" "${descriptions[$i]}"
                [[ $i -ne $last ]] && echo ","
            done
            echo "]"
            ;;
    esac
}

# Add a new host
add_host() {
    local alias_name="${1:-}"
    local hostname="${2:-}"
    local user="${3:-}"
    local port="${4:-22}"
    local key_path="${5:-}"
    local description="${6:-}"
    
    # CLI mode = alias + hostname supplied as positional args (per FS-004:
    # `--add ALIAS HOSTNAME [USER] [PORT]`). In CLI mode the optional fields
    # default silently — we must NOT block on prompts, especially under
    # `set -e` where an EOF on `read` would abort the script. Only the fully
    # interactive menu path (add_host called with no args) prompts for every
    # field. Each prompt also tolerates EOF (`|| true`) so a closed stdin can
    # never crash the manager.
    local interactive=true
    [[ -n "$alias_name" && -n "$hostname" ]] && interactive=false

    if [[ -z "$alias_name" ]]; then
        read -p "$(echo -e "${YELLOW}Host alias (short name): ${NC}")" alias_name || true
    fi
    if [[ -z "$hostname" ]]; then
        read -p "$(echo -e "${YELLOW}Hostname or IP: ${NC}")" hostname || true
    fi
    if [[ -z "$user" ]]; then
        if [[ "$interactive" == "true" ]]; then
            read -p "$(echo -e "${YELLOW}SSH username [root]: ${NC}")" user || true
        fi
        user="${user:-root}"
    fi
    if [[ "$interactive" == "true" ]]; then
        read -p "$(echo -e "${YELLOW}SSH port [${port}]: ${NC}")" _port_in || true
        port="${_port_in:-$port}"
    fi
    if [[ -z "$key_path" ]]; then
        if [[ "$interactive" == "true" ]]; then
            read -p "$(echo -e "${YELLOW}SSH key path (Enter for default ~/.ssh/id_rsa): ${NC}")" key_path || true
        fi
        key_path="${key_path:-~/.ssh/id_rsa}"
    fi
    if [[ -z "$description" && "$interactive" == "true" ]]; then
        read -p "$(echo -e "${YELLOW}Description (optional): ${NC}")" description || true
    fi
    
    # Validate alias name
    if [[ ! "$alias_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        print_error "Invalid alias name: $alias_name (use only letters, numbers, underscore, hyphen)"
        return 1
    fi
    
    # Check if alias already exists
    if grep -q "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null; then
        print_warning "Host alias '$alias_name' already exists"
        read -p "$(echo -e "${YELLOW}Overwrite? [y/N]: ${NC}")" response
        [[ "$response" =~ ^[Yy]$ ]] || return 0
        # Remove existing host
        backup_hosts
        run_or_dry sed -i "/^${alias_name}|/d" "$HOSTS_FILE"
    else
        backup_hosts
    fi
    
    # Add the host
    run_or_dry bash -c "echo \"${alias_name}|${hostname}|${user}|${port}|${key_path}|${description}\" >> \"${HOSTS_FILE}\""
    
    say_done "Added host: $alias_name -> $user@$hostname:$port"
    [[ -n "$description" ]] && print_info "Description: $description"
    
    # Test connection
    read -p "$(echo -e "${YELLOW}Test SSH connection? [y/N]: ${NC}")" test_conn
    if [[ "$test_conn" =~ ^[Yy]$ ]]; then
        test_connection "$alias_name"
    fi
}

# Remove a host
remove_host() {
    local alias_name="$1"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    if ! grep -q "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    backup_hosts
    
    # Remove the host line
    run_or_dry sed -i "/^${alias_name}|/d" "$HOSTS_FILE"
    
    say_done "Removed host: $alias_name"
}

# Edit an existing host
edit_host() {
    local alias_name="$1"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    # Find existing host
    local existing_line
    existing_line=$(grep "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$existing_line" ]]; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    # Parse existing host
    IFS='|' read -r _ hostname user port key desc <<< "$existing_line"
    
    echo -e "\n${CYAN}Editing host: $alias_name${NC}"
    echo -e "Current: $user@$hostname:$port"
    [[ -n "$key" ]] && echo -e "Key: $key"
    [[ -n "$desc" ]] && echo -e "Description: $desc"
    echo ""
    
    read -p "$(echo -e "${YELLOW}Hostname [$hostname]: ${NC}")" new_hostname
    new_hostname="${new_hostname:-$hostname}"
    
    read -p "$(echo -e "${YELLOW}Username [$user]: ${NC}")" new_user
    new_user="${new_user:-$user}"
    
    read -p "$(echo -e "${YELLOW}Port [$port]: ${NC}")" new_port
    new_port="${new_port:-$port}"
    
    read -p "$(echo -e "${YELLOW}Key path [$key]: ${NC}")" new_key
    new_key="${new_key:-$key}"
    
    read -p "$(echo -e "${YELLOW}Description [$desc]: ${NC}")" new_desc
    new_desc="${new_desc:-$desc}"
    
    backup_hosts
    
    # Remove old host
    run_or_dry sed -i "/^${alias_name}|/d" "$HOSTS_FILE"
    
    # Add updated host
    run_or_dry bash -c "echo \"${alias_name}|${new_hostname}|${new_user}|${new_port}|${new_key}|${new_desc}\" >> \"${HOSTS_FILE}\""
    
    say_done "Updated host: $alias_name"
}

# Test SSH connection to a host
test_connection() {
    local alias_name="$1"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    local host_line
    host_line=$(grep "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$host_line" ]]; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    IFS='|' read -r _ hostname user port key _ <<< "$host_line"
    
    print_info "Testing connection to $user@$hostname:$port..."
    
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -p $port"
    [[ -n "$key" && -f "$key" ]] && ssh_opts="$ssh_opts -i $key"
    
    if ssh $ssh_opts "$user@$hostname" "echo 'Connection successful'" 2>/dev/null; then
        print_success "Connection to $alias_name successful"
        return 0
    else
        print_error "Connection to $alias_name failed"
        print_info "Check: hostname, port, user, key, firewall"
        return 1
    fi
}

# Connect to a host
connect_host() {
    local alias_name="$1"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    local host_line
    host_line=$(grep "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$host_line" ]]; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    IFS='|' read -r _ hostname user port key _ <<< "$host_line"
    
    print_info "Connecting to $user@$hostname:$port..."
    
    local ssh_opts="-p $port"
    [[ -n "$key" && -f "$key" ]] && ssh_opts="$ssh_opts -i $key"
    
    ssh $ssh_opts "$user@$hostname"
}

# Push file to host
push_file() {
    local alias_name="$1"
    local src="$2"
    local dst="$3"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    local host_line
    host_line=$(grep "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$host_line" ]]; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    IFS='|' read -r _ hostname user port key _ <<< "$host_line"
    
    print_info "Pushing $src to $user@$hostname:$dst..."
    
    local scp_opts="-P $port"
    [[ -n "$key" && -f "$key" ]] && scp_opts="$scp_opts -i $key"
    
    if scp $scp_opts -r "$src" "$user@$hostname:$dst"; then
        print_success "Push successful"
    else
        print_error "Push failed"
        return 1
    fi
}

# Pull file from host
pull_file() {
    local alias_name="$1"
    local src="$2"
    local dst="$3"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    local host_line
    host_line=$(grep "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$host_line" ]]; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    IFS='|' read -r _ hostname user port key _ <<< "$host_line"
    
    print_info "Pulling $src from $user@$hostname to $dst..."
    
    local scp_opts="-P $port"
    [[ -n "$key" && -f "$key" ]] && scp_opts="$scp_opts -i $key"
    
    if scp $scp_opts -r "$user@$hostname:$src" "$dst"; then
        print_success "Pull successful"
    else
        print_error "Pull failed"
        return 1
    fi
}

# Sync directory using rsync
sync_directory() {
    local alias_name="$1"
    local src="$2"
    local dst="$3"
    local direction="${4:-push}"  # push or pull
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    local host_line
    host_line=$(grep "^${alias_name}|" "$HOSTS_FILE" 2>/dev/null | head -1)
    
    if [[ -z "$host_line" ]]; then
        print_error "Host not found: $alias_name"
        return 1
    fi
    
    IFS='|' read -r _ hostname user port key _ <<< "$host_line"
    
    local rsync_opts="-avz --progress -e 'ssh -p $port"
    [[ -n "$key" && -f "$key" ]] && rsync_opts="$rsync_opts -i $key"
    rsync_opts="$rsync_opts'"
    
    if [[ "$direction" == "push" ]]; then
        print_info "Syncing $src to $user@$hostname:$dst..."
        if eval rsync $rsync_opts "$src" "$user@$hostname:$dst"; then
            print_success "Sync successful"
        else
            print_error "Sync failed"
            return 1
        fi
    else
        print_info "Syncing $user@$hostname:$src to $dst..."
        if eval rsync $rsync_opts "$user@$hostname:$src" "$dst"; then
            print_success "Sync successful"
        else
            print_error "Sync failed"
            return 1
        fi
    fi
}

# Generate SSH config entries for all hosts
generate_ssh_config() {
    if [[ ! -f "$HOSTS_FILE" ]] || [[ ! -s "$HOSTS_FILE" ]]; then
        print_warning "No hosts found to generate config"
        return 0
    fi
    
    print_header "Generated SSH Config"
    echo "# Generated by ssh_host_manager.sh"
    echo "# Source: $HOSTS_FILE"
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
    done < "$HOSTS_FILE"
}

# Append generated config to SSH config file
append_to_ssh_config() {
    if [[ ! -f "$HOSTS_FILE" ]] || [[ ! -s "$HOSTS_FILE" ]]; then
        print_warning "No hosts found to append"
        return 0
    fi
    
    mkdir -p "$(dirname "$SSH_CONFIG_FILE")"
    
    # Check if already has USB hosts section
    if grep -q "# USB Compute Automation Hosts" "$SSH_CONFIG_FILE" 2>/dev/null; then
        print_warning "USB hosts section already exists in SSH config"
        read -p "$(echo -e "${YELLOW}Replace? [y/N]: ${NC}")" response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            # Remove existing section (between markers)
            run_or_dry sed -i '/# USB Compute Automation Hosts/,/# End USB Hosts/d' "$SSH_CONFIG_FILE"
        else
            return 0
        fi
    fi
    
    # Append new section
    run_or_dry bash -c '
    {
        echo ""
        echo "# USB Compute Automation Hosts"
        echo "# Generated: $(date)"
        
        while IFS="|" read -r alias hostname user port key desc; do
            [[ "$alias" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$alias" ]] && continue
            
            echo ""
            echo "Host $alias"
            echo "    HostName $hostname"
            echo "    User $user"
            echo "    Port $port"
            [[ -n "$key" && -f "$key" ]] && echo "    IdentityFile $key"
            [[ -n "$desc" ]] && echo "    # $desc"
        done < "'"$HOSTS_FILE"'"
        
        echo ""
        echo "# End USB Hosts"
    } >> "'"$SSH_CONFIG_FILE"'"'
    
    print_success "Appended USB hosts to: $SSH_CONFIG_FILE"
}

# Search hosts
search_hosts() {
    local query="$1"
    
    if [[ ! -f "$HOSTS_FILE" ]]; then
        print_error "Hosts file not found: $HOSTS_FILE"
        return 1
    fi
    
    print_info "Searching for: $query"
    echo ""
    
    local found=0
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        if echo "$line" | grep -qi "$query"; then
            IFS='|' read -r alias hostname user port key desc <<< "$line"
            printf "${CYAN}%-15s${NC} %s@%s:%s\n" "$alias" "$user" "$hostname" "$port"
            ((found++))
        fi
    done < "$HOSTS_FILE"
    
    echo ""
    print_info "Found $found matching hosts"
}

# Import from existing SSH config
import_from_ssh_config() {
    local source_file="${1:-$SSH_CONFIG_FILE}"
    
    if [[ ! -f "$source_file" ]]; then
        print_error "SSH config not found: $source_file"
        return 1
    fi
    
    print_info "Importing hosts from: $source_file"
    
    local count=0
    local current_alias=""
    local current_hostname=""
    local current_user=""
    local current_port="22"
    local current_key=""
    
    while IFS= read -r line; do
        # Match Host directive
        if [[ "$line" =~ ^[[:space:]]*Host[[:space:]]+(.+) ]]; then
            # Save previous host if exists
            if [[ -n "$current_alias" && -n "$current_hostname" ]]; then
                # Skip if already exists
                if ! grep -q "^${current_alias}|" "$HOSTS_FILE" 2>/dev/null; then
                    run_or_dry bash -c "echo \"${current_alias}|${current_hostname}|${current_user:-root}|${current_port}|${current_key}|Imported from SSH config\" >> \"${HOSTS_FILE}\""
                    print_success "Imported: $current_alias"
                    ((count++))
                else
                    print_info "Skipped (exists): $current_alias"
                fi
            fi
            
            current_alias="${BASH_REMATCH[1]}"
            current_hostname=""
            current_user=""
            current_port="22"
            current_key=""
        fi
        
        # Match HostName
        if [[ "$line" =~ ^[[:space:]]*HostName[[:space:]]+(.+) ]]; then
            current_hostname="${BASH_REMATCH[1]}"
        fi
        
        # Match User
        if [[ "$line" =~ ^[[:space:]]*User[[:space:]]+(.+) ]]; then
            current_user="${BASH_REMATCH[1]}"
        fi
        
        # Match Port
        if [[ "$line" =~ ^[[:space:]]*Port[[:space:]]+(.+) ]]; then
            current_port="${BASH_REMATCH[1]}"
        fi
        
        # Match IdentityFile
        if [[ "$line" =~ ^[[:space:]]*IdentityFile[[:space:]]+(.+) ]]; then
            current_key="${BASH_REMATCH[1]}"
        fi
    done < "$source_file"
    
    # Save last host
    if [[ -n "$current_alias" && -n "$current_hostname" ]]; then
        if ! grep -q "^${current_alias}|" "$HOSTS_FILE" 2>/dev/null; then
            run_or_dry bash -c "echo \"${current_alias}|${current_hostname}|${current_user:-root}|${current_port}|${current_key}|Imported from SSH config\" >> \"${HOSTS_FILE}\""
            print_success "Imported: $current_alias"
            ((count++))
        fi
    fi
    
    echo ""
    print_info "Imported $count hosts from $source_file"
}

# ============================================================================
# INTERACTIVE MENU
# ============================================================================

show_menu() {
    print_header "SSH Host Manager"
    echo -e "${BOLD}Hosts file:${NC} $HOSTS_FILE"
    echo ""
    
    # Count hosts
    local count=0
    if [[ -f "$HOSTS_FILE" ]]; then
        count=$(grep -c "^[^#]" "$HOSTS_FILE" 2>/dev/null || echo "0")
    fi
    echo -e "${BOLD}Total hosts:${NC} $count"
    echo ""
    
    echo -e "${CYAN}1)${NC} List all hosts"
    echo -e "${CYAN}2)${NC} Add new host"
    echo -e "${CYAN}3)${NC} Remove host"
    echo -e "${CYAN}4)${NC} Edit host"
    echo -e "${CYAN}5)${NC} Test connection"
    echo -e "${CYAN}6)${NC} Connect to host"
    echo -e "${CYAN}7)${NC} Push file to host"
    echo -e "${CYAN}8)${NC} Pull file from host"
    echo -e "${CYAN}9)${NC} Sync directory (rsync)"
    echo -e "${CYAN}10)${NC} Generate SSH config"
    echo -e "${CYAN}11)${NC} Append to SSH config"
    echo -e "${CYAN}12)${NC} Search hosts"
    echo -e "${CYAN}13)${NC} Import from SSH config"
    echo -e "${CYAN}14)${NC} Open hosts file in editor"
    echo -e "${CYAN}15)${NC} View hosts file"
    echo -e "${CYAN}0)${NC} Back to main menu"
    echo ""
}

interactive_menu() {
    init_hosts_file
    
    while true; do
        show_menu
        read -p "$(echo -e "${YELLOW}Select option [0-15]: ${NC}")" choice
        
        case "$choice" in
            1)
                list_hosts
                ;;
            2)
                echo ""
                add_host
                ;;
            3)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias to remove: ${NC}")" name
                remove_host "$name"
                ;;
            4)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias to edit: ${NC}")" name
                edit_host "$name"
                ;;
            5)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias to test: ${NC}")" name
                test_connection "$name"
                ;;
            6)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias to connect: ${NC}")" name
                connect_host "$name"
                ;;
            7)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias: ${NC}")" name
                read -p "$(echo -e "${YELLOW}Local source path: ${NC}")" src
                read -p "$(echo -e "${YELLOW}Remote destination: ${NC}")" dst
                push_file "$name" "$src" "$dst"
                ;;
            8)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias: ${NC}")" name
                read -p "$(echo -e "${YELLOW}Remote source: ${NC}")" src
                read -p "$(echo -e "${YELLOW}Local destination: ${NC}")" dst
                pull_file "$name" "$src" "$dst"
                ;;
            9)
                echo ""
                list_hosts 2>/dev/null || true
                echo ""
                read -p "$(echo -e "${YELLOW}Host alias: ${NC}")" name
                read -p "$(echo -e "${YELLOW}Local path: ${NC}")" local_path
                read -p "$(echo -e "${YELLOW}Remote path: ${NC}")" remote_path
                read -p "$(echo -e "${YELLOW}Direction (push/pull) [push]: ${NC}")" direction
                sync_directory "$name" "$local_path" "$remote_path" "${direction:-push}"
                ;;
            10)
                generate_ssh_config
                ;;
            11)
                append_to_ssh_config
                ;;
            12)
                echo ""
                read -p "$(echo -e "${YELLOW}Search query: ${NC}")" query
                search_hosts "$query"
                ;;
            13)
                echo ""
                read -p "$(echo -e "${YELLOW}SSH config file [$SSH_CONFIG_FILE]: ${NC}")" source_file
                import_from_ssh_config "${source_file:-$SSH_CONFIG_FILE}"
                ;;
            14)
                if command -v nano &>/dev/null; then
                    nano "$HOSTS_FILE"
                elif command -v vim &>/dev/null; then
                    vim "$HOSTS_FILE"
                else
                    print_error "No editor found (nano, vim)"
                    print_info "Manually edit: $HOSTS_FILE"
                fi
                ;;
            15)
                echo ""
                if [[ -f "$HOSTS_FILE" ]]; then
                    cat "$HOSTS_FILE"
                else
                    print_warning "Hosts file not found: $HOSTS_FILE"
                fi
                ;;
            0)
                print_info "Returning to main menu..."
                return 0
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
# COMMAND-LINE INTERFACE
# ============================================================================

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run|-n)
            DRY_RUN=true
            shift
            ;;
        --list|-l)
            init_hosts_file
            list_hosts "${2:-table}"
            shift
            ;;
        --add|-a)
            if [[ $# -lt 3 ]]; then
                echo "Usage: $0 [--dry-run] --add ALIAS HOSTNAME [USER] [PORT]"
                exit 1
            fi
            init_hosts_file
            add_host "$2" "$3" "${4:-root}" "${5:-22}"
            if [[ -n "${5:-}" ]]; then
                shift 5
            elif [[ -n "${4:-}" ]]; then
                shift 4
            else
                shift 3
            fi
            ;;
        --remove|-r)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 [--dry-run] --remove ALIAS"
                exit 1
            fi
            init_hosts_file
            remove_host "$2"
            shift 2
            ;;
        --test|-t)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 --test ALIAS"
                exit 1
            fi
            init_hosts_file
            test_connection "$2"
            shift 2
            ;;
        --connect|-c)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 --connect ALIAS"
                exit 1
            fi
            init_hosts_file
            connect_host "$2"
            shift 2
            ;;
        --push|-p)
            if [[ $# -lt 4 ]]; then
                echo "Usage: $0 [--dry-run] --push ALIAS SRC DST"
                exit 1
            fi
            init_hosts_file
            push_file "$2" "$3" "$4"
            shift 4
            ;;
        --pull)
            if [[ $# -lt 4 ]]; then
                echo "Usage: $0 [--dry-run] --pull ALIAS SRC DST"
                exit 1
            fi
            init_hosts_file
            pull_file "$2" "$3" "$4"
            shift 4
            ;;
        --sync|-s)
            if [[ $# -lt 4 ]]; then
                echo "Usage: $0 [--dry-run] --sync ALIAS SRC DST [push|pull]"
                exit 1
            fi
            init_hosts_file
            sync_directory "$2" "$3" "$4" "${5:-push}"
            if [[ -n "${5:-}" ]]; then
                shift 5
            else
                shift 4
            fi
            ;;
        --generate|-g)
            init_hosts_file
            generate_ssh_config
            shift
            ;;
        --search|-S)
            if [[ $# -lt 2 ]]; then
                echo "Usage: $0 --search QUERY"
                exit 1
            fi
            init_hosts_file
            search_hosts "$2"
            shift 2
            ;;
        --import|-i)
            init_hosts_file
            import_from_ssh_config "${2:-$SSH_CONFIG_FILE}"
            shift
            ;;
        --help|-h)
            echo "SSH Host Manager - USB Compute Automation System"
            echo ""
            echo "Usage:"
            echo "  $0                              Interactive menu"
            echo "  $0 --dry-run                    Dry-run mode (no changes made)"
            echo "  $0 --list [format]              List all hosts (table/csv/json)"
            echo "  $0 --add ALIAS HOST [USER] [PORT] Add host"
            echo "  $0 --remove ALIAS               Remove host"
            echo "  $0 --test ALIAS                 Test connection"
            echo "  $0 --connect ALIAS              Connect to host"
            echo "  $0 --push ALIAS SRC DST         Push file to host"
            echo "  $0 --pull ALIAS SRC DST         Pull file from host"
            echo "  $0 --sync ALIAS SRC DST [DIR]   rsync to/from host"
            echo "  $0 --generate                   Generate SSH config"
            echo "  $0 --search QUERY               Search hosts"
            echo "  $0 --import [FILE]              Import from SSH config"
            echo ""
            echo "Examples:"
            echo "  $0 --dry-run --add vps1 192.168.1.100 root 22"
            echo "  $0 --push vps1 ./file.txt /tmp/"
            echo "  $0 --pull vps1 /var/log/syslog ./logs/"
            echo "  $0 --sync vps1 ./project/ /opt/project/ push"
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
if [[ "$CLI_ARG_PROCESSED" == "false" ]]; then
    interactive_menu
fi