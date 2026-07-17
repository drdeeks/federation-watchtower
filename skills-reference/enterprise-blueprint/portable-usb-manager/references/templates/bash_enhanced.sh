#!/usr/bin/env bash
# =============================================================================
# Enhanced System Management — Bash Profile
# Ported from EnhancedSystemManagement PowerShell suite (Chitus Tech style)
# Source from ~/.bashrc: source /path/to/bash_enhanced.sh
# =============================================================================

# ─────────────────────────────────────────────────────────────────────────────
# COLORS & CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
# Only declare if not already set (allows safe re-sourcing without "readonly variable" errors)
: "${RED:=\033[0;31m}"
: "${GREEN:=\033[0;32m}"
: "${YELLOW:=\033[1;33m}"
: "${BLUE:=\033[0;34m}"
: "${CYAN:=\033[0;36m}"
: "${WHITE:=\033[1;37m}"
: "${DIM:=\033[2m}"
: "${BOLD:=\033[1m}"
: "${NC:=\033[0m}"

# ─────────────────────────────────────────────────────────────────────────────
# WELCOME BANNER
# ─────────────────────────────────────────────────────────────────────────────
_esm_banner() {
    echo ""
    echo -e "${BOLD}${BLUE}  ╔═══════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}  ║     Enhanced System Management — Bash       ║${NC}"
    echo -e "${BOLD}${BLUE}  ║         @drdeeks  |  Phoenix, AZ            ║${NC}"
    echo -e "${BOLD}${BLUE}  ╚═══════════════════════════════════════════════╝${NC}"
    echo -e "  ${DIM}$(date '+%A, %B %d %Y  %H:%M')${NC}"
    echo ""

    # Quick system stats
    local mem_used mem_total cpu_load disk_use
    mem_used=$(awk '/MemTotal/{t=$2}/MemAvailable/{a=$2}END{printf "%.0f", (t-a)/1024}' /proc/meminfo 2>/dev/null || echo "?")
    mem_total=$(awk '/MemTotal/{printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo "?")
    cpu_load=$(cut -d' ' -f1 /proc/loadavg 2>/dev/null || echo "?")
    disk_use=$(df / 2>/dev/null | awk 'NR==2{print $5}')

    echo -e "  ${CYAN}RAM:${NC} ${mem_used}M / ${mem_total}M   ${CYAN}Load:${NC} ${cpu_load}   ${CYAN}Disk:${NC} ${disk_use} used"
    echo ""
    echo -e "  ${DIM}Type ${NC}${CYAN}syshelp${NC}${DIM} for available functions${NC}"
    echo ""
}

# Run banner on interactive shells only
[[ $- == *i* ]] && _esm_banner

# ─────────────────────────────────────────────────────────────────────────────
# HELP SYSTEM
# ─────────────────────────────────────────────────────────────────────────────
syshelp() {
    cat <<'HELPEOF'

══ Enhanced System Management — Bash Functions ══

  System Info & Resources:
    sysinfo          — Full system information (OS, CPU, RAM, disk)
    sysresources     — Live resource usage + top processes
    diskinfo         — Disk usage breakdown

  Environment Management:
    checkenv         — Validate PATH + managed directories
    repairenv        — Auto-fix invalid/duplicate PATH entries
    envset VAR VAL   — Set environment variable (session)
    envget VAR       — Get environment variable value
    envdel VAR       — Unset environment variable
    envlist          — List all user environment variables
    cleanpath        — Remove invalid/duplicate PATH entries
    addpath DIR      — Add directory to PATH (deduped)

  Process Management:
    psgrep NAME      — Find process by name
    pstop            — Show top 15 by CPU + memory
    killbyname NAME  — Kill all processes matching name
    zombies          — List zombie processes

  Startup & Services:
    showstartup      — List enabled systemd services + autostart apps
    svcstatus NAME   — Check service status
    svcenable NAME   — Enable a service at boot
    svcdisable NAME  — Disable a service at boot
    svcrestart NAME  — Restart a service

  Cleanup & Maintenance:
    quickclean       — Fast cache + log cleanup (no prompts)
    exportinfo       — Generate system report file
    logsize          — Show log directory sizes
    findnm [DIR]     — Find all node_modules directories

  File & Directory:
    mkcd DIR         — Create directory and cd into it
    bak FILE         — Create timestamped backup of a file
    extract FILE     — Extract any archive (.tar.gz .zip .7z etc)
    fsize DIR        — Show largest files in a directory
    findfile NAME    — Find file by name from current dir

  Network:
    myip             — Show public and local IP addresses
    ports            — Show all listening ports
    pingcheck HOST   — Ping test with stats

  Git Shortcuts:
    gs, ga, gc, gp, gpl, gl, gco, gnb, gdiff, gstash

  Navigation:
    dev, shared, projects, scripts
    ..  ...  ....    — Go up 1, 2, 3 directories

  Alias Manager (Universal Portable):
    am                    # Interactive menu
    aml / am --list       # List all aliases
    ama / am --add        # Add alias (ama name "cmd" "desc")
    amr / am --remove     # Remove alias
    ams / am --search     # Search aliases (ams query)
    ami / am --import     # Import from .bashrc
    ame / am --export     # Export aliases (table/csv/json)
    ammenu                # Interactive menu
    alias-location        # Show where aliases are stored
    alias-env             # Show environment detection status

  Run any function with --help for more detail.
HELPEOF
}

# ─────────────────────────────────────────────────────────────────────────────
# SYSTEM INFO
# ─────────────────────────────────────────────────────────────────────────────
sysinfo() {
    cat <<'INFOEOF'

══ System Information ══

  Machine:
INFOEOF
    echo "  Hostname:    $(hostname)"
    echo "  OS:          $(lsb_release -ds 2>/dev/null || grep PRETTY /etc/os-release | cut -d= -f2 | tr -d '\"')"
    echo "  Kernel:      $(uname -r)"
    echo "  Architecture: $(uname -m)"
    echo "  Uptime:      $(uptime -p 2>/dev/null || uptime)"
    echo "  Shell:       $SHELL $BASH_VERSION"
    echo "  User:        $USER (uid=$(id -u))"
    echo ""

    cat <<'EOF'
  CPU:
EOF
    echo "  Model:   $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
    echo "  Cores:   $(nproc)"
    echo "  Load:    $(cut -d' ' -f1-3 /proc/loadavg)"
    echo ""

    cat <<'EOF'
  Memory:
EOF
    awk '
        /MemTotal/{t=$2}
        /MemAvailable/{a=$2}
        /SwapTotal/{st=$2}
        /SwapFree/{sf=$2}
        END{
            printf "  %-18s %.1f GB\n","RAM Total:", t/1048576
            printf "  %-18s %.1f GB (%.0f%%)\n","RAM Used:", (t-a)/1048576, (t-a)/t*100
            printf "  %-18s %.1f GB\n","RAM Free:", a/1048576
            printf "  %-18s %.1f GB total, %.1f GB free\n","Swap:", st/1048576, sf/1048576
        }
    ' /proc/meminfo

    cat <<'EOF'

  Disk:
EOF
    df -h | grep -v "tmpfs\|udev\|loop" \
        | awk 'NR==1{printf "  %-22s %5s %5s %5s %5s\n",$1,$2,$3,$4,$5}
               NR>1{printf "  %-22s %5s %5s %5s %5s\n",$1,$2,$3,$4,$5}'

    cat <<'EOF'

  Environment:
EOF
    for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT NODE_HOME GOPATH CARGO_HOME; do
        VAL="${!var}"
        [ -n "$VAL" ] && printf "  %-18s %s\n" "$var:" "$VAL"
    done

    cat <<'EOF'

  Key tools:
EOF
    for t in git node npm python3 docker sqlite3 gcc; do
        if command -v "$t" &>/dev/null; then
            V=$("$t" --version 2>/dev/null | head -1 | grep -oP '[\d]+\.[\d]+\.?[\d]*' | head -1 || echo "ok")
            printf "  \033[0;32m✓\033[0m %-14s %s\n" "$t" "$V"
        else
            printf "  \033[2m—\033[0m %-14s not found\n" "$t"
        fi
    done
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# LIVE RESOURCE USAGE
# ─────────────────────────────────────────────────────────────────────────────
sysresources() {
    cat <<'EOF'

══ System Resource Usage ══

  CPU Load:
EOF
    read -r l1 l5 l15 _ < /proc/loadavg
    CORES=$(nproc)
    printf "  %-18s %s / %s / %s  (1m / 5m / 15m)  [%s cores]\n" "Load avg:" "$l1" "$l5" "$l15" "$CORES"
    echo ""

    cat <<'EOF'
  Memory:
EOF
    free -h | awk '
        NR==1{next}
        /Mem:/ {printf "  %-18s used: %s / total: %s  free: %s\n","RAM:",$3,$2,$4}
        /Swap:/ {printf "  %-18s used: %s / total: %s  free: %s\n","Swap:",$3,$2,$4}
    '

    cat <<'EOF'

  Top 8 processes by CPU:
  ────────────────────────────────────────────────────
EOF
    printf "  \033[1m  %-7s %-24s %6s %6s %8s\033[0m\n" "PID" "NAME" "CPU%" "MEM%" "MEM(MB)"
    echo "  ────────────────────────────────────────────────────"
    ps aux --sort=-%cpu 2>/dev/null \
        | awk 'NR>=2 && NR<=10{
            mem_mb = $6/1024
            printf "  %-7s %-24s %5s%% %5s%% %7.0fM\n",$2,$11,$3,$4,mem_mb
          }'

    cat <<'EOF'

  Top 8 processes by Memory:
  ────────────────────────────────────────────────────
EOF
    printf "  \033[1m  %-7s %-24s %6s %8s\033[0m\n" "PID" "NAME" "MEM%" "MEM(MB)"
    echo "  ────────────────────────────────────────────────────"
    ps aux --sort=-%mem 2>/dev/null \
        | awk 'NR>=2 && NR<=8{
            mem_mb = $6/1024
            printf "  %-7s %-24s %5s%% %7.0fM\n",$2,$11,$4,mem_mb
          }'
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# DISK USAGE
# ─────────────────────────────────────────────────────────────────────────────
diskinfo() {
    cat <<'EOF'

══ Disk Usage ══
EOF
    df -h | grep -v "tmpfs\|udev\|loop" \
        | awk 'NR==1{printf "  %-22s %6s %6s %6s  %s\n",$1,$2,$3,$4,$5}
               NR>1{printf "  %-22s %6s %6s %6s  %s\n",$1,$2,$3,$4,$5}'
    echo ""
    echo "  Largest directories in home:"
    timeout 10 du -sh "$HOME"/*/ 2>/dev/null | sort -hr | head -10 \
        | awk '{printf "    %-8s %s\n",$1,$2}'
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# ENVIRONMENT MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
checkenv() {
    echo ""
    echo -e "${BOLD}${CYAN}══ Environment Consistency Check ══${NC}"
    echo ""
    local issues=0

    echo -e "  ${YELLOW}PATH validation:${NC}"
    declare -A _seen=()
    IFS=':' read -ra _entries <<< "$PATH"
    for p in "${_entries[@]}"; do
        [ -z "$p" ] && continue
        local norm="${p%/}"
        if [ -n "${_seen[$norm]+_}" ]; then
            echo -e "  ${YELLOW}[DUP]${NC}  $p"
            issues=$((issues+1))
        elif [ ! -d "$p" ]; then
            echo -e "  ${RED}[BAD]${NC}  $p"
            issues=$((issues+1))
        else
            echo -e "  ${GREEN}[OK]${NC}  $p"
        fi
        _seen[$norm]=1
    done

    echo ""
    echo -e "  ${YELLOW}Managed directories:${NC}"
    for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT; do
        VAL="${!var}"
        if [ -z "$VAL" ]; then
            echo -e "  ${YELLOW}[UNSET]${NC} $var"
        elif [ ! -d "$VAL" ]; then
            echo -e "  ${RED}[MISSING]${NC} $var = $VAL"
            issues=$((issues+1))
        else
            echo -e "  ${GREEN}[OK]${NC}    $var = $VAL"
        fi
    done

    echo ""
    if [ "$issues" -eq 0 ]; then
        echo -e "  ${GREEN}Environment is consistent — $issues issues found.${NC}"
    else
        echo -e "  ${YELLOW}Found $issues issue(s). Run ${CYAN}repairenv${YELLOW} to auto-fix.${NC}"
    fi
    echo ""
}

# Auto-fix PATH and recreate missing directories
repairenv() {
    echo ""
    echo -e "${BOLD}${CYAN}══ Environment Repair ══${NC}"
    echo ""
    local new_path="" removed=0
    declare -A _seen2=()

    IFS=':' read -ra _entries <<< "$PATH"
    for p in "${_entries[@]}"; do
        [ -z "$p" ] && continue
        local norm="${p%/}"
        if [ -n "${_seen2[$norm]+_}" ]; then
            echo -e "  ${YELLOW}[-]${NC} Removed duplicate: $p"
            removed=$((removed+1))
        elif [ ! -d "$p" ]; then
            echo -e "  ${RED}[-]${NC} Removed invalid: $p"
            removed=$((removed+1))
        else
            new_path="${new_path:+$new_path:}$p"
            _seen2[$norm]=1
        fi
    done

    export PATH="$new_path"
    echo ""
    echo -e "  ${GREEN}PATH cleaned. Removed $removed entries.${NC}"
    echo -e "  ${DIM}Add to ~/.bashrc to persist: export PATH=\"$new_path\"${NC}"

    # Recreate missing managed dirs
    for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT; do
        VAL="${!var}"
        [ -z "$VAL" ] && continue
        if [ ! -d "$VAL" ]; then
            read -r -p "  Create missing dir $VAL? [yes/no]: " ans
            [ "$ans" = "yes" ] && mkdir -p "$VAL" \
                && echo -e "  ${GREEN}[✓]${NC} Created $VAL"
        fi
    done
    echo ""
}

# Simple env var management
envset()  { [ -z "$1" ] && { echo "Usage: envset VAR VALUE"; return 1; }; export "$1"="$2"; echo "Set $1=$2 (session only)"; }
envget()  { [ -z "$1" ] && { echo "Usage: envget VAR"; return 1; }; echo "${!1:-<not set>}"; }
envdel()  { [ -z "$1" ] && { echo "Usage: envdel VAR"; return 1; }; unset "$1"; echo "Unset $1"; }
envlist() { env | sort | grep -v "^LS_COLORS\|^BASH_FUNC" | less; }
cleanpath() { repairenv; }

addpath() {
    local dir="${1%/}"
    [ -z "$dir" ] && { echo "Usage: addpath DIRECTORY"; return 1; }
    [ ! -d "$dir" ] && { echo "Directory not found: $dir"; return 1; }
    if [[ ":$PATH:" != *":$dir:"* ]]; then
        export PATH="$PATH:$dir"
        echo "Added to PATH: $dir"
        echo "To persist: echo 'export PATH=\"\$PATH:$dir\"' >> ~/.bashrc"
    else
        echo "Already in PATH: $dir"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# PROCESS MANAGEMENT
# ─────────────────────────────────────────────────────────────────────────────
psgrep() {
    [ -z "$1" ] && { echo "Usage: psgrep PROCESS_NAME"; return 1; }
    echo ""
    printf "\033[1m  %-7s %-12s %-24s %6s %6s\033[0m\n" "PID" "USER" "NAME" "CPU%" "MEM%"
    echo "  ──────────────────────────────────────────────────"
    ps aux 2>/dev/null | awk -v name="$1" 'NR>1 && $11 ~ name || $0 ~ name {
        printf "  %-7s %-12s %-24s %5s%% %5s%%\n",$2,$1,$11,$3,$4
    }' | grep -v "awk\|psgrep"
    echo ""
}

pstop() {
    echo ""
    echo -e "${BOLD}${CYAN}  Top 15 processes:${NC}"
    echo ""
    printf "\033[1m  %-7s %-12s %-24s %6s %6s %8s\033[0m\n" "PID" "USER" "COMMAND" "CPU%" "MEM%" "MEM(MB)"
    echo "  ──────────────────────────────────────────────────────────────"
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR>=2 && NR<=17 {
        mem_mb=$6/1024
        printf "  %-7s %-12s %-24s %5s%% %5s%% %7.0fM\n",$2,$1,$11,$3,$4,mem_mb
    }'
    echo ""
}

killbyname() {
    [ -z "$1" ] && { echo "Usage: killbyname PROCESS_NAME"; return 1; }
    PIDS=$(pgrep -f "$1" 2>/dev/null | tr '\n' ' ')
    if [ -z "$PIDS" ]; then
        echo "No processes found matching: $1"
        return
    fi
    echo "Found PIDs: $PIDS"
    read -r -p "Kill all? [yes/no]: " ans
    [ "$ans" = "yes" ] && pkill -f "$1" && echo "Killed processes matching: $1"
}

zombies() {
    echo ""
    RESULT=$(ps aux 2>/dev/null | awk '$8=="Z"')
    if [ -z "$RESULT" ]; then
        echo -e "  ${GREEN}[✓]${NC} No zombie processes"
    else
        echo -e "  ${RED}Zombie processes:${NC}"
        echo "$RESULT"
    fi
    echo ""
}

# ─────────────────────────────────────────────────────────────────────────────
# STARTUP & SERVICES
# ─────────────────────────────────────────────────────────────────────────────
showstartup() {
    echo ""
    echo -e "${BOLD}${CYAN}══ Startup Programs & Services ══${NC}"
    echo ""
    echo -e "  ${YELLOW}Enabled systemd services:${NC}"
    systemctl list-unit-files --type=service --state=enabled --no-pager 2>/dev/null \
        | grep -v '^UNIT\|^$\|loaded units' \
        | awk '{printf "  %-48s %s\n",$1,$2}' | head -25
    echo ""
    echo -e "  ${YELLOW}XDG autostart:${NC}"
    for dir in "$HOME/.config/autostart" "/etc/xdg/autostart"; do
        [ -d "$dir" ] || continue
        for f in "$dir"/*.desktop; do
            [ -f "$f" ] || continue
            NAME=$(grep -m1 '^Name=' "$f" | cut -d= -f2)
            EXEC=$(grep -m1 '^Exec=' "$f" | cut -d= -f2 | cut -d' ' -f1)
            printf "  %-30s %s\n" "$NAME" "$EXEC"
        done
    done
    echo ""
}

svcstatus()  { [ -z "$1" ] && { echo "Usage: svcstatus SERVICE"; return 1; }; systemctl status "$1"; }
svcenable()  { [ -z "$1" ] && { echo "Usage: svcenable SERVICE"; return 1; }; sudo systemctl enable "$1" && echo "Enabled: $1"; }
svcdisable() { [ -z "$1" ] && { echo "Usage: svcdisable SERVICE"; return 1; }; sudo systemctl disable "$1" && echo "Disabled: $1"; }
svcrestart() { [ -z "$1" ] && { echo "Usage: svcrestart SERVICE"; return 1; }; sudo systemctl restart "$1" && echo "Restarted: $1"; }

# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP & MAINTENANCE
# ─────────────────────────────────────────────────────────────────────────────
quickclean() {
    echo ""
    echo -e "${BOLD}${CYAN}══ Quick Clean ══${NC}"
    echo ""

    # Journal
    sudo journalctl --vacuum-time=3d 2>&1 | tail -1
    echo -e "  ${GREEN}[✓]${NC} Journal vacuumed (3 days)"

    # APT
    sudo apt autoremove -y > /dev/null 2>&1
    sudo apt autoclean   > /dev/null 2>&1
    echo -e "  ${GREEN}[✓]${NC} APT cache cleaned"

    # npm cache
    if command -v npm &>/dev/null; then
        npm cache clean --force > /dev/null 2>&1
        echo -e "  ${GREEN}[✓]${NC} npm cache cleared"
    fi

    # pip cache
    [ -d "$HOME/.cache/pip" ] && rm -rf "$HOME/.cache/pip" \
        && echo -e "  ${GREEN}[✓]${NC} pip cache cleared"

    # Thumbnails
    [ -d "$HOME/.cache/thumbnails" ] && rm -rf "$HOME/.cache/thumbnails"/* 2>/dev/null \
        && echo -e "  ${GREEN}[✓]${NC} Thumbnails cleared"

    echo ""
    df -h / | awk 'NR==2{printf "  Disk: %s used of %s (%s full)\n",$3,$2,$5}'
    echo ""
}

logsize() {
    echo ""
    echo -e "${BOLD}${CYAN}  Log directory sizes:${NC}"
    echo ""
    sudo du -sh /var/log/*/ 2>/dev/null | sort -hr | head -15 \
        | awk '{printf "    %-8s %s\n",$1,$2}'
    echo ""
    echo -e "  Total /var/log: $(du -sh /var/log 2>/dev/null | awk '{print $1}')"
    echo ""
}

findnm() {
    local dir="${1:-$HOME}"
    echo "Scanning $dir for node_modules..."
    find "$dir" -maxdepth 8 -name "node_modules" -type d \
        -not -path "*/node_modules/*/node_modules" \
        2>/dev/null | while read -r d; do
        SIZE=$(du -sh "$d" 2>/dev/null | awk '{print $1}')
        PARENT=$(dirname "$d")
        HAS_PKG="no"
        [ -f "$PARENT/package.json" ] && HAS_PKG="yes"
        printf "  %-8s  pkg.json: %-4s  %s\n" "$SIZE" "$HAS_PKG" "$d"
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# EXPORT SYSTEM INFO
# ─────────────────────────────────────────────────────────────────────────────
exportinfo() {
    local out_dir="${DEV_ROOT:-$HOME}/exports"
    mkdir -p "$out_dir" 2>/dev/null || out_dir="/tmp"
    local out_file="$out_dir/system_info_$(date '+%Y%m%d_%H%M%S').txt"

    cat > "$out_file" <<'EXPEOF'
Enhanced System Management — System Info Export
Generated: $(date)
==================================================

SYSTEM:
  Hostname:    $(hostname)
  OS:          $(lsb_release -ds 2>/dev/null || echo 'Linux')
  Kernel:      $(uname -r)
  Uptime:      $(uptime -p 2>/dev/null || uptime)
  User:        $USER

CPU:
  $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)
  Cores: $(nproc)
  Load:  $(cat /proc/loadavg | cut -d' ' -f1-3)

MEMORY:
  $(free -h)

DISK:
  $(df -h | grep -v tmpfs)

ENVIRONMENT:
EXPEOF
    for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT NODE_HOME GOPATH; do
        VAL="${!var}"; [ -n "$VAL" ] && echo "  $var = $VAL" >> "$out_file"
    done
    echo "  PATH entries: $(echo "$PATH" | tr ':' '\n' | wc -l)" >> "$out_file"
    echo "" >> "$out_file"
    echo "INSTALLED TOOLS:" >> "$out_file"
    for t in git node npm pnpm python3 pip3 docker sqlite3 gcc make; do
        if command -v "$t" &>/dev/null; then
            V=$("$t" --version 2>/dev/null | head -1)
            echo "  [✓] $t: $V" >> "$out_file"
        else
            echo "  [—] $t: not found" >> "$out_file"
        fi
    done

    echo -e "  ${GREEN}[✓]${NC} System info exported to: $out_file"
}

# ─────────────────────────────────────────────────────────────────────────────
# FILE & DIRECTORY
# ─────────────────────────────────────────────────────────────────────────────
mkcd() { mkdir -p "$1" && cd "$1" || return; }

bak() {
    [ -z "$1" ] && { echo "Usage: bak FILE"; return 1; }
    cp -a "$1" "${1}.bak.$(date '+%Y%m%d_%H%M%S')" && echo "Backup created"
}

extract() {
    [ -z "$1" ] && { echo "Usage: extract ARCHIVE"; return 1; }
    case "$1" in
        *.tar.bz2) tar xjf "$1" ;;   *.tar.gz)  tar xzf "$1" ;;
        *.tar.xz)  tar xJf "$1" ;;   *.tar)     tar xf  "$1" ;;
        *.bz2)     bunzip2  "$1" ;;   *.gz)      gunzip  "$1" ;;
        *.zip)     unzip    "$1" ;;   *.7z)      7z x    "$1" ;;
        *.rar)     unrar x  "$1" ;;   *.Z)       uncompress "$1" ;;
        *) echo "Cannot extract '$1' — unknown format" ;;
    esac
}

fsize() {
    local dir="${1:-.}"
    echo "Largest files in $dir:"
    find "$dir" -maxdepth 3 -type f -printf '%s %p\n' 2>/dev/null \
        | sort -rn | head -15 \
        | awk '{printf "    %-10s %s\n", $1>1073741824 ? sprintf("%.1fG",$1/1073741824) : $1>1048576 ? sprintf("%.1fM",$1/1048576) : sprintf("%.0fK",$1/1024), $2}'
}

findfile() {
    [ -z "$1" ] && { echo "Usage: findfile FILENAME"; return 1; }
    find . -name "*$1*" 2>/dev/null | head -30
}

# ─────────────────────────────────────────────────────────────────────────────
# NETWORK
# ─────────────────────────────────────────────────────────────────────────────
myip() {
    echo ""
    echo -e "  ${YELLOW}Local IP:${NC}"
    ip addr show 2>/dev/null | awk '/inet / && !/127.0.0.1/{printf "    %s  (%s)\n",$2,$NF}' \
        || hostname -I | tr ' ' '\n' | awk '{printf "    %s\n",$0}'
    echo ""
    echo -e "  ${YELLOW}Public IP:${NC}"
    curl -s --max-time 5 https://api.ipify.org 2>/dev/null && echo "" \
        || echo "    (timeout — no internet?)"
    echo ""
}

ports() {
    echo ""
    echo -e "  ${YELLOW}Listening ports:${NC}"
    ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null | head -30
    echo ""
}

pingcheck() {
    local host="${1:-1.1.1.1}"
    ping -c 5 "$host"
}

# ─────────────────────────────────────────────────────────────────────────────
# GIT SHORTCUTS
# ─────────────────────────────────────────────────────────────────────────────
gs()  { git status; }
ga()  { git add -A; }
gc()  { git commit -m "$*"; }
gp()  { git push; }
gpl() { git pull; }
gl()  { git log --oneline --graph --decorate --all | head -30; }
gco() { git checkout "$@"; }
gnb() { git checkout -b "$@"; }
gdiff(){ git diff "$@"; }
gstash(){ git stash "$@"; }

# ─────────────────────────────────────────────────────────────────────────────
# NAVIGATION SHORTCUTS
# ─────────────────────────────────────────────────────────────────────────────
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

dev()     { cd "${DEV_ROOT:-$HOME/dev}" || echo "DEV_ROOT not set"; }
shared()  { cd "${SHARED_HOME:-$HOME/shared}" || echo "SHARED_HOME not set"; }
projects(){ cd "${PROJECTS_ROOT:-$HOME/projects}" || echo "PROJECTS_ROOT not set"; }
scripts() { cd "${SHARED_HOME:-$HOME}/scripts" 2>/dev/null || cd "${DEV_ROOT:-$HOME}/scripts" 2>/dev/null || echo "scripts dir not found"; }

# ─────────────────────────────────────────────────────────────────────────────
# GENERAL ALIASES
# ─────────────────────────────────────────────────────────────────────────────
alias ll='ls -lhF --color=auto'
alias la='ls -lhAF --color=auto'
alias lt='ls -lhFt --color=auto'       # sort by modified time
alias lz='ls -lhFS --color=auto'       # sort by size
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias df='df -h'
alias du='du -sh'
alias free='free -h'
alias top='htop 2>/dev/null || top'
alias cls='clear'
alias reload='source ~/.bashrc && echo "bashrc reloaded"'
alias path='echo $PATH | tr ":" "\n" | nl'
alias which='command -v'               # consistent with PS alias
alias update='sudo apt update && sudo apt upgrade -y'
alias myhistory='history | grep'

# ─────────────────────────────────────────────────────────────────────────────
# ALIAS MANAGER INTEGRATION (Universal Portable)
# ─────────────────────────────────────────────────────────────────────────────
# Universal environment detection for portable alias management
# Works on: local machine, USB boot, VM, host, any Linux box
# ─────────────────────────────────────────────────────────────────────────────

# Enable alias expansion in non-interactive shells
shopt -s expand_aliases

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

# Alias manager wrapper with universal path finding
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

# Add to syshelp: alias manager section
_syshelp_alias_manager() {
    cat <<'EOF'

  Alias Manager (Universal Portable):
    am                    # Interactive menu
    aml / am --list       # List all aliases
    ama / am --add        # Add alias (ama name "cmd" "desc")
    amr / am --remove     # Remove alias
    ams / am --search     # Search aliases (ams query)
    ami / am --import     # Import from .bashrc
    ame / am --export     # Export aliases (table/csv/json)
    ammenu                # Interactive menu
    alias-location        # Show where aliases are stored
    alias-env             # Show environment detection status
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
# PROMPT (minimal but informative, Chitus Tech style)
# ─────────────────────────────────────────────────────────────────────────────
# STATIC PROMPT - No dynamic PROMPT_COMMAND rebuilding to avoid terminal issues
# (Old dynamic approach caused "stuck prompt" and "can't backspace" issues)
_git_branch() {
    git branch 2>/dev/null | awk '/\*/{print " ("$2")"}'
}

_exit_code() {
    local code=$?
    [ $code -ne 0 ] && printf " \[\033[0;31m\][%d]\[\033[0m\]" $code
}

# Static prompt with printf for exit code (no echo -e in prompt)
PS1='\[\033[1m\]\[\033[0;34m\]\u\[\033[0m\]@\[\033[0;36m\]\h\[\033[0m\]:\[\033[0;32m\]\w\[\033[1;33m\]$(_git_branch)\[\033[0m\] $(_exit_code)\n\[\033[0;36m\]▶\[\033[0m\] '

# Clean PROMPT_COMMAND - no dynamic PS1 rebuilding, no history double-append
HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth:erasedups    # no dupes, no leading spaces
HISTTIMEFORMAT="%F %T  "
shopt -s histappend                 # append to history, don't overwrite
PROMPT_COMMAND="history -a"

# ─────────────────────────────────────────────────────────────────────────────
# COMPLETION
# ─────────────────────────────────────────────────────────────────────────────
[ -f /usr/share/bash-completion/bash_completion ] \
    && source /usr/share/bash-completion/bash_completion 2>/dev/null || true
[ -f /etc/bash_completion ] \
    && source /etc/bash_completion 2>/dev/null || true

# end of bash_enhanced.sh