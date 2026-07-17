#!/bin/bash
# clean-local.sh — Interactive Ubuntu Machine Cleanup
# Ported methods from EnhancedSystemManagement PowerShell suite

# ─────────────────────────────────────────────────────────────────
# COLORS & SYMBOLS
# ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'
RED='\033[0;31m';   CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─────────────────────────────────────────────────────────────────
# CL-030: this cleaner deletes from host system locations (/var/log,
# /var/cache/apt, $HOME/.cache, /tmp, etc). In USB mode the contract is
# "no host writes after initial setup" — so refuse loudly with a path
# forward (re-run in HOST mode or pass --force-host).
# ─────────────────────────────────────────────────────────────────
if [[ "${UCA_MODE:-host}" == "usb" ]] && [[ "${1:-}" != "--force-host" ]]; then
    printf "${RED}[BLOCKED]${NC} clean-local.sh cleans HOST system files (/var/log, ~/.cache,\n" >&2
    printf "          /tmp, apt cache). UCA_MODE=usb forbids host writes by design.\n" >&2
    printf "${YELLOW}Options:${NC}\n" >&2
    printf "  - Re-run menu.sh with ${BOLD}--mode host${NC} to clean the host.\n" >&2
    printf "  - Pass ${BOLD}--force-host${NC} as the first arg to override this guard.\n" >&2
    exit 12
fi
# Drop the sentinel if the user explicitly opted in.
[[ "${1:-}" == "--force-host" ]] && shift

# ─────────────────────────────────────────────────────────────────
# GLOBAL STATE  (mirrors PS $Global:CurrentPhase / $Global:SetupConfig)
# ─────────────────────────────────────────────────────────────────
CURRENT_PHASE="Initialization"
declare -a CLEANUP_LOG=()
declare -a ISSUE_LOG=()
DISK_BEFORE=$(df / 2>/dev/null | awk 'NR==2{print $3}')
SESSION_START=$(date '+%Y-%m-%d %H:%M:%S')

# ─────────────────────────────────────────────────────────────────
# LOGGING  (port of Write-EnhancedLog — level + category)
# ─────────────────────────────────────────────────────────────────
log() {
    # Usage: log LEVEL CATEGORY "message"
    local level="$1" category="$2" msg="$3"
    local ts; ts=$(date '+%H:%M:%S')
    local color="$NC"
    case "$level" in
        INFO)     color="$CYAN"   ;;
        WARN)     color="$YELLOW" ;;
        ERROR)    color="$RED"    ;;
        CRITICAL) color="$RED$BOLD" ;;
        SUCCESS)  color="$GREEN"  ;;
    esac
    echo -e "${DIM}[$ts]${NC} ${color}[$level]${NC} ${DIM}[$category]${NC} $msg"
    # append to session log file
    echo "[$ts] [$level] [$category] $msg" >> /tmp/cleanup_session.log 2>/dev/null || true
}

ok()      { echo -e "${GREEN}[✓]${NC} $1"; }
info()    { echo -e "${CYAN}[→]${NC} $1"; }
warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
bad()     { echo -e "${RED}[✗]${NC} $1"; }
removed() { echo -e "${RED}[-]${NC} Removed: ${BOLD}$1${NC} ${CYAN}[$2]${NC}"; CLEANUP_LOG+=("$1 | $2"); }
kept()    { echo -e "${GREEN}[=]${NC} Kept: $1"; }
issue()   { echo -e "${YELLOW}[⚠]${NC} $1"; ISSUE_LOG+=("$1"); }
explain() { echo -e "\n  ${CYAN}ℹ  $1${NC}\n"; }
phase()   { CURRENT_PHASE="$1"; log INFO "Phase" "Entering: $CURRENT_PHASE"; }

section() {
    echo ""
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}  $1${NC}"
    echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

divider() { echo -e "  ${BLUE}────────────────────────────────────────${NC}"; }

confirm() {
    local ans
    read -r -p "$(echo -e "  ${YELLOW}?${NC} $1 [yes/no]: ")" ans
    [ "$ans" = "yes" ]
}

pause() { echo ""; read -r -p "  Press Enter to continue..."; }

# ─────────────────────────────────────────────────────────────────
# UTILITIES  (port of Test-CommandExists)
# ─────────────────────────────────────────────────────────────────
cmd_exists() { command -v "$1" &>/dev/null; }

safe_du() {
    timeout 10 du -sh --exclude=/proc --exclude=/sys \
        --exclude=/dev --exclude=/run --exclude=/snap \
        "$@" 2>/dev/null | awk '{print $1}' || echo "?"
}

safe_du_kb() {
    timeout 10 du -sk --exclude=/proc --exclude=/sys \
        --exclude=/dev --exclude=/run \
        "$@" 2>/dev/null | awk '{print $1}' || echo "0"
}

run_with_spinner() {
    local label="$1"; shift
    local spinchars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    "$@" &>/tmp/spinner_out.tmp &
    local pid=$!
    while kill -0 "$pid" 2>/dev/null; do
        local s="${spinchars:$((i % ${#spinchars})):1}"
        printf "\r  ${CYAN}%s${NC} %s " "$s" "$label"
        i=$((i+1)); sleep 0.1
    done
    wait "$pid"; local rc=$?
    printf "\r  ${GREEN}✓${NC} %-52s\n" "$label"
    rm -f /tmp/spinner_out.tmp
    return $rc
}

# ─────────────────────────────────────────────────────────────────
# PREREQUISITES  (port of Test-Prerequisites)
# ─────────────────────────────────────────────────────────────────
check_prerequisites() {
    phase "Prerequisites"
    log INFO "Prerequisites" "Checking system requirements..."
    local ok=true

    # Check running as non-root (warn if root)
    if [ "$(id -u)" -eq 0 ]; then
        log WARN "Prerequisites" "Running as root — some per-user paths may differ"
    fi

    # Check disk space (warn if under 1GB free)
    local free_kb; free_kb=$(df / | awk 'NR==2{print $4}')
    if [ "$free_kb" -lt 1048576 ]; then
        log WARN "Prerequisites" "Low disk space: $(( free_kb / 1024 ))MB free — cleanup recommended"
    fi

    # Check required tools
    for tool in find du df ps systemctl; do
        if cmd_exists "$tool"; then
            log SUCCESS "Prerequisites" "$tool — available"
        else
            log WARN "Prerequisites" "$tool — not found (some sections may be limited)"
        fi
    done

    log SUCCESS "Prerequisites" "Check complete"
    echo ""
}

# ─────────────────────────────────────────────────────────────────
# HEADER
# ─────────────────────────────────────────────────────────────────
clear
rm -f /tmp/cleanup_session.log
echo -e "${BOLD}${BLUE}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       Local Machine Cleanup Suite        ║"
echo "  ║   (Enhanced System Management — Bash)    ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${CYAN}$SESSION_START${NC}"
echo ""
df -h / | awk 'NR==2{printf "  Disk before:  %s used of %s  (%s full)\n",$3,$2,$5}'
echo ""
divider
check_prerequisites

# ─────────────────────────────────────────────────────────────────
# MENU
# ─────────────────────────────────────────────────────────────────
show_menu() {
    echo ""
    echo -e "${BOLD}  Select a section:${NC}"
    echo ""
    echo "    1)  Cron jobs & scheduled tasks"
    echo "    2)  Docker containers & images"
    echo "    3)  Phantom / stale processes"
    echo "    4)  System logs"
    echo "    5)  Package & tool caches"
    echo "    6)  Orphaned node_modules"
    echo "    7)  Temp files, locks & crash reports"
    echo "    8)  System info & resource usage"
    echo "    9)  Environment health check & repair"
    echo "   10)  Startup programs & services"
    echo "   11)  Run ALL sections"
    echo "   12)  Disk summary"
    echo "   13)  Export session report"
    echo "    0)  Exit & show session report"
    echo ""
    read -r -p "$(echo -e "  ${CYAN}▶${NC} Choice: ")" choice
}

# ─────────────────────────────────────────────────────────────────
# 1. CRON JOBS
# ─────────────────────────────────────────────────────────────────
manage_crons() {
    phase "Cron Jobs"
    section "Cron Jobs & Scheduled Tasks"

    explain "Cron jobs run commands on a schedule automatically.
     User crontab = your personal jobs. /etc/cron.d = system-wide.
     Systemd timers = modern cron replacement used by most daemons."

    echo -e "  ${BOLD}Your crontab:${NC}"
    echo ""
    USER_CRONS=$(crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' || true)
    if [ -z "$USER_CRONS" ]; then
        info "No personal cron jobs set"
    else
        echo "$USER_CRONS" | while IFS= read -r line; do echo "    $line"; done
    fi

    echo ""
    echo -e "  ${BOLD}System cron directories:${NC}"
    echo ""
    for dir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
        [ -d "$dir" ] || continue
        FILES=$(ls "$dir" 2>/dev/null | grep -v README | grep -v '.placeholder' || true)
        [ -z "$FILES" ] && continue
        echo -e "  ${CYAN}$dir/${NC}"
        timeout 5 ls -lh "$dir" 2>/dev/null \
            | awk 'NR>1 && $9!=""{printf "    %-28s  %s %s %s\n",$9,$6,$7,$8}'
        echo ""
    done

    echo -e "  ${BOLD}Active systemd timers:${NC}"
    explain "NEXT = next scheduled run. LAST = last run. PASSED = time since last run."
    timeout 5 systemctl list-timers --no-pager 2>/dev/null | head -20 \
        || warn "systemd timer list timed out"

    echo ""
    if confirm "Open your crontab to edit?"; then crontab -e; fi
}

# ─────────────────────────────────────────────────────────────────
# 2. DOCKER
# ─────────────────────────────────────────────────────────────────
manage_docker() {
    phase "Docker"
    section "Docker Containers & Images"

    if ! cmd_exists docker; then
        warn "Docker not installed — skipping"
        log WARN "Docker" "Docker not found"
        return
    fi

    explain "Running = active. Exited = stopped but taking disk space.
     Dangling images = downloaded layers nothing uses. Volumes = persistent data."

    echo -e "  ${BOLD}Running containers:${NC}"
    RUN_COUNT=$(timeout 5 docker ps -q 2>/dev/null | wc -l || echo 0)
    if [ "$RUN_COUNT" -eq 0 ]; then
        info "No running containers"
    else
        timeout 5 docker ps \
            --format "  {{.ID}}  {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}" \
            2>/dev/null || warn "Docker ps timed out"
    fi

    echo ""
    echo -e "  ${BOLD}Stopped / exited containers:${NC}"
    STOP_COUNT=$(timeout 5 docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l || echo 0)
    if [ "$STOP_COUNT" -eq 0 ]; then
        info "No stopped containers"
    else
        timeout 5 docker ps -a --filter "status=exited" \
            --format "  {{.ID}}  {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.CreatedAt}}" \
            2>/dev/null || warn "Docker ps timed out"
    fi

    echo ""
    echo -e "  ${BOLD}Disk usage:${NC}"
    timeout 10 docker system df 2>/dev/null || warn "Docker df timed out"

    echo ""
    echo "    1) Remove stopped containers   — frees exited container disk"
    echo "    2) Remove unused images        — removes untagged/unused layers"
    echo "    3) Remove unused volumes       — removes orphaned data volumes"
    echo "    4) Full prune (no volumes)     — containers + images + networks"
    echo "    5) Full prune + volumes        — everything unused"
    echo "    6) Skip"
    echo ""
    read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " docker_choice

    case "$docker_choice" in
        1) timeout 15 docker container prune -f 2>/dev/null \
               && removed "$STOP_COUNT stopped containers" "Docker" ;;
        2) timeout 30 docker image prune -af 2>/dev/null \
               && removed "Unused Docker images" "Docker images" ;;
        3) timeout 15 docker volume prune -f 2>/dev/null \
               && removed "Unused Docker volumes" "Docker volumes" ;;
        4) timeout 60 docker system prune -af 2>/dev/null \
               && removed "All unused Docker resources" "Docker prune" ;;
        5) timeout 60 docker system prune -af --volumes 2>/dev/null \
               && removed "All unused Docker resources + volumes" "Docker full prune" ;;
        *) info "Skipping Docker cleanup" ;;
    esac
    log SUCCESS "Docker" "Docker section complete"
}

# ─────────────────────────────────────────────────────────────────
# 3. PHANTOM / STALE PROCESSES
# ─────────────────────────────────────────────────────────────────
scan_processes() {
    phase "Process Scan"
    section "Phantom & Stale Processes"

    # ── Zombies ───────────────────────────────────────────────────
    echo -e "  ${BOLD}Zombie / defunct processes:${NC}"
    explain "A zombie finished running but its parent never cleaned it up.
     It holds no memory — just a process table slot.
     Kill the PARENT to reap the zombie, not the zombie itself."

    mapfile -t ZOMBIE_ROWS < <(timeout 5 ps aux 2>/dev/null | awk '$8=="Z"' || true)
    if [ ${#ZOMBIE_ROWS[@]} -eq 0 ]; then
        ok "No zombie processes"
        log SUCCESS "Processes" "No zombies found"
    else
        bad "${#ZOMBIE_ROWS[@]} zombie(s) detected"
        log WARN "Processes" "${#ZOMBIE_ROWS[@]} zombie(s) found"
        echo ""
        printf "  ${BOLD}  %-7s %-7s %-20s %s${NC}\n" "PID" "PPID" "NAME" "ELAPSED"
        divider
        declare -A ZOMBIE_PARENTS=()
        for row in "${ZOMBIE_ROWS[@]}"; do
            PID=$(awk '{print $2}' <<<"$row")
            PPID=$(awk '{print $3}' <<<"$row")
            CMD=$(awk '{print $11}' <<<"$row")
            ET=$(timeout 2 ps -p "$PID" -o etime= 2>/dev/null | xargs || echo "?")
            printf "  %-7s %-7s %-20s %s\n" "$PID" "$PPID" "$CMD" "$ET"
            ZOMBIE_PARENTS[$PPID]=1
        done
        echo ""
        echo -e "  ${BOLD}Parent processes (kill these to reap zombies):${NC}"
        printf "  ${BOLD}  %-7s %-20s %s${NC}\n" "PPID" "NAME" "COMMAND"
        divider
        for ppid in "${!ZOMBIE_PARENTS[@]}"; do
            PNAME=$(timeout 2 ps -p "$ppid" -o comm= 2>/dev/null || echo "gone")
            PCMD=$(timeout 2 ps -p "$ppid" -o cmd= 2>/dev/null | cut -c1-50 || echo "")
            printf "  %-7s %-20s %s\n" "$ppid" "$PNAME" "$PCMD"
        done
        echo ""
        echo "    a) Kill ALL parent processes"
        echo "    p) Kill a specific parent PID"
        echo "    s) Skip"
        echo ""
        read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " z_choice
        case "$z_choice" in
            a) for ppid in "${!ZOMBIE_PARENTS[@]}"; do
                   warn "Killing parent PID $ppid"
                   timeout 5 sudo kill -9 "$ppid" 2>/dev/null \
                       && ok "Killed $ppid" && removed "Zombie parent PID $ppid" "Zombie reap" \
                       || bad "Could not kill $ppid"
               done ;;
            p) read -r -p "  Enter PPID: " kpid
               [[ "$kpid" =~ ^[0-9]+$ ]] || { warn "Invalid PID"; return; }
               timeout 5 sudo kill -9 "$kpid" 2>/dev/null \
                   && ok "Killed $kpid" && removed "PID $kpid" "Zombie reap" \
                   || bad "Could not kill $kpid" ;;
            *) info "Skipping" ;;
        esac
    fi

    # ── Deleted executables ───────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Processes on deleted/updated binaries:${NC}"
    explain "After a package update the old binary on disk is replaced, but processes
     still using it run from the old version in memory. Normal after apt upgrades.
     They clear on reboot; kill now only if you need the new version immediately."

    mapfile -t DEL_PIDS < <(
        timeout 10 ls -la /proc/*/exe 2>/dev/null \
        | awk '/\(deleted\)/{print $NF}' \
        | sed 's|/proc/||;s|/exe.*||' \
        | grep -E '^[0-9]+$' || true
    )
    if [ ${#DEL_PIDS[@]} -eq 0 ]; then
        ok "No processes on deleted binaries"
    else
        warn "${#DEL_PIDS[@]} process(es) on old binaries"
        echo ""
        printf "  ${BOLD}  %-7s %-22s %-12s %s${NC}\n" "PID" "NAME" "ELAPSED" "USER"
        divider
        for pid in "${DEL_PIDS[@]}"; do
            CMD=$(timeout 2 ps -p "$pid" -o comm= 2>/dev/null || echo "gone")
            ET=$(timeout 2 ps -p "$pid" -o etime= 2>/dev/null | xargs || echo "?")
            USR=$(timeout 2 ps -p "$pid" -o user= 2>/dev/null || echo "?")
            printf "  %-7s %-22s %-12s %s\n" "$pid" "$CMD" "$ET" "$USR"
        done
        echo ""
        echo "    a) Kill ALL — will use updated binary on restart"
        echo "    p) Kill a specific PID"
        echo "    s) Skip — safe, clears on reboot"
        echo ""
        read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " del_choice
        case "$del_choice" in
            a) for pid in "${DEL_PIDS[@]}"; do
                   CMD=$(timeout 2 ps -p "$pid" -o comm= 2>/dev/null || echo "unknown")
                   warn "Killing PID $pid ($CMD)"
                   timeout 5 sudo kill -15 "$pid" 2>/dev/null \
                       || timeout 5 sudo kill -9 "$pid" 2>/dev/null || true
                   ok "Signal sent to $pid"
                   removed "PID $pid ($CMD)" "Deleted-binary process"
               done ;;
            p) read -r -p "  Enter PID: " kpid
               [[ "$kpid" =~ ^[0-9]+$ ]] || { warn "Invalid PID"; return; }
               CMD=$(timeout 2 ps -p "$kpid" -o comm= 2>/dev/null || echo "?")
               timeout 5 sudo kill -15 "$kpid" 2>/dev/null \
                   || timeout 5 sudo kill -9 "$kpid" 2>/dev/null || true
               ok "Signal sent to $kpid ($CMD)"
               removed "PID $kpid ($CMD)" "Deleted-binary process" ;;
            *) info "Skipping" ;;
        esac
    fi

    # ── Long-running ──────────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Long-running processes (7+ days):${NC}"
    explain "Usually fine — daemons and SSH sessions run indefinitely.
     Flag: shells left open for months, or services that should restart but haven't."

    mapfile -t LONG_PROCS < <(
        timeout 5 ps -eo pid,comm,etime,user --sort=-etime 2>/dev/null \
        | awk 'NR>1 && $3 ~ /^[0-9]{2,}-/' || true
    )
    if [ ${#LONG_PROCS[@]} -eq 0 ]; then
        ok "No processes running 7+ days"
    else
        printf "  ${BOLD}  %-7s %-22s %-14s %s${NC}\n" "PID" "NAME" "RUNNING FOR" "USER"
        divider
        for row in "${LONG_PROCS[@]}"; do
            printf "  %-7s %-22s %-14s %s\n" \
                "$(awk '{print $1}' <<<"$row")" \
                "$(awk '{print $2}' <<<"$row")" \
                "$(awk '{print $3}' <<<"$row")" \
                "$(awk '{print $4}' <<<"$row")"
        done
        echo ""
        echo "    p) Kill a specific PID   s) Skip"
        echo ""
        read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " long_choice
        if [ "$long_choice" = "p" ]; then
            read -r -p "  Enter PID: " kpid
            [[ "$kpid" =~ ^[0-9]+$ ]] || { warn "Invalid PID"; return; }
            CMD=$(timeout 2 ps -p "$kpid" -o comm= 2>/dev/null || echo "?")
            timeout 5 sudo kill -15 "$kpid" 2>/dev/null \
                || timeout 5 sudo kill -9 "$kpid" 2>/dev/null || true
            ok "Signal sent to $kpid"
            removed "PID $kpid ($CMD)" "Long-running process"
        else
            info "Skipping"
        fi
    fi

    # ── Stale locks ───────────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Stale lock / pid files:${NC}"
    explain "Lock files prevent duplicate processes. A stale lock has a PID that
     no longer exists — left after a crash. Safe to remove; blocks the app from starting."

    STALE_FOUND=0
    while IFS= read -r lockfile; do
        PID=$(timeout 2 cat "$lockfile" 2>/dev/null | tr -d '[:space:]' || echo "")
        if [[ "$PID" =~ ^[0-9]+$ ]] && [ -d "/proc/$PID" ]; then
            CMD=$(timeout 2 ps -p "$PID" -o comm= 2>/dev/null || echo "unknown")
            kept "$lockfile → PID $PID ($CMD) active"
        else
            bad "STALE: $lockfile (PID '$PID' not running)"
            log WARN "Processes" "Stale lock found: $lockfile (PID $PID)"
            if confirm "Remove $lockfile?"; then
                timeout 3 sudo rm -f "$lockfile" \
                    && ok "Removed" && removed "$lockfile" "Stale lock"
            fi
            STALE_FOUND=$((STALE_FOUND+1))
        fi
    done < <(timeout 10 sudo find /tmp /var/run /run \
        -maxdepth 3 \( -name "*.lock" -o -name "*.pid" \) 2>/dev/null || true)
    [ "$STALE_FOUND" -eq 0 ] && ok "No stale lock files"

    # ── Memory consumers ──────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Top memory consumers:${NC}"
    explain "MEM% = share of total RAM. High values are normal for browsers,
     databases, and JVMs. Kill only if you're certain it's safe."

    printf "  ${BOLD}  %-7s %-10s %-24s %6s %6s${NC}\n" "PID" "USER" "PROCESS" "CPU%" "MEM%"
    divider
    timeout 5 ps aux --sort=-%mem 2>/dev/null \
        | awk 'NR>=2 && NR<=11{printf "  %-7s %-10s %-24s %5s%% %5s%%\n",$2,$1,$11,$3,$4}' \
        || warn "ps timed out"
    echo ""
    read -r -p "  Enter PID to kill (or Enter to skip): " mem_pid
    if [[ "$mem_pid" =~ ^[0-9]+$ ]]; then
        CMD=$(timeout 2 ps -p "$mem_pid" -o comm= 2>/dev/null || echo "?")
        warn "Killing PID $mem_pid ($CMD)"
        timeout 5 sudo kill -15 "$mem_pid" 2>/dev/null \
            || timeout 5 sudo kill -9 "$mem_pid" 2>/dev/null || true
        ok "Signal sent"
        removed "PID $mem_pid ($CMD)" "Manual kill"
    else
        info "Skipping"
    fi
    log SUCCESS "Processes" "Process scan complete"
}

# ─────────────────────────────────────────────────────────────────
# 4. SYSTEM LOGS
# ─────────────────────────────────────────────────────────────────
clear_logs() {
    phase "Logs"
    section "System Logs"

    explain "journald = systemd log store for all services and the kernel.
     Rotated logs (.gz/.1/.old) = compressed old logs kept for reference.
     Trimming is always safe — logs rebuild automatically."

    LOG_SIZE=$(safe_du /var/log)
    log INFO "Logs" "Current /var/log size: $LOG_SIZE"
    info "Current /var/log size: $LOG_SIZE"
    echo ""

    echo -e "  ${BOLD}Oldest rotated logs:${NC}"
    timeout 5 sudo find /var/log -type f \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) \
        2>/dev/null | head -10 | while read -r f; do
        SIZE=$(timeout 2 du -sh "$f" 2>/dev/null | awk '{print $1}')
        echo "    $SIZE  $f"
    done

    echo ""
    echo "    1) Keep last 3 days  (recommended)"
    echo "    2) Keep last 1 day   (aggressive)"
    echo "    3) Clear entire journal"
    echo "    4) Skip"
    echo ""
    read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " log_choice

    case "$log_choice" in
        1) run_with_spinner "Vacuuming journal (keep 3 days)" \
               sudo journalctl --vacuum-time=3d
           removed "Journal entries older than 3 days" "Log vacuum"
           log SUCCESS "Logs" "Journal vacuumed (3d)" ;;
        2) run_with_spinner "Vacuuming journal (keep 1 day)" \
               sudo journalctl --vacuum-time=1d
           removed "Journal entries older than 1 day" "Log vacuum"
           log SUCCESS "Logs" "Journal vacuumed (1d)" ;;
        3) run_with_spinner "Clearing full journal" \
               sudo journalctl --vacuum-size=1K
           removed "All journal logs" "Full log clear"
           log WARN "Logs" "Full journal cleared" ;;
        *) info "Skipping journal"; log INFO "Logs" "Journal cleanup skipped" ;;
    esac

    ROTATED=$(timeout 5 sudo find /var/log \
        \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) 2>/dev/null | wc -l || echo 0)
    if [ "$ROTATED" -gt 0 ]; then
        echo ""
        if confirm "Remove $ROTATED rotated log files?"; then
            timeout 15 sudo find /var/log \
                \( -name "*.gz" -o -name "*.1" -o -name "*.old" \) -delete 2>/dev/null || true
            removed "$ROTATED rotated log files" "Rotated logs"
            log SUCCESS "Logs" "Removed $ROTATED rotated log files"
        fi
    fi

    NEW_SIZE=$(safe_du /var/log)
    ok "Log size: $LOG_SIZE → $NEW_SIZE"
}

# ─────────────────────────────────────────────────────────────────
# 5. CACHES
# ─────────────────────────────────────────────────────────────────
clear_caches() {
    phase "Caches"
    section "Package & Tool Caches"

    explain "Caches are always rebuilt on demand. Clearing is 100% safe.
     The app re-downloads or recomputes the data next time it needs it."

    # npm
    if cmd_exists npm; then
        NPM_DIR=$(npm config get cache 2>/dev/null || echo "$HOME/.npm")
        NPM_SIZE=$(safe_du "$NPM_DIR")
        info "npm cache: $NPM_SIZE  ($NPM_DIR)"
        explain "Stores downloaded packages to avoid re-downloading.
         Can grow to several GB with no ongoing benefit."
        if confirm "Clear npm cache?"; then
            run_with_spinner "Clearing npm cache" npm cache clean --force
            removed "npm cache ($NPM_SIZE)" "npm cache"
            log SUCCESS "Caches" "npm cache cleared ($NPM_SIZE)"
        fi
    fi

    # pnpm
    if cmd_exists pnpm; then
        PNPM_DIR=$(pnpm store path 2>/dev/null || echo "")
        if [ -n "$PNPM_DIR" ] && [ -d "$PNPM_DIR" ]; then
            PNPM_SIZE=$(safe_du "$PNPM_DIR")
            info "pnpm store: $PNPM_SIZE"
            if confirm "Prune pnpm store?"; then
                run_with_spinner "Pruning pnpm store" pnpm store prune
                removed "Unreferenced pnpm packages" "pnpm store"
                log SUCCESS "Caches" "pnpm store pruned"
            fi
        fi
    fi

    # pip
    PIP_DIR="$HOME/.cache/pip"
    if [ -d "$PIP_DIR" ]; then
        PIP_SIZE=$(safe_du "$PIP_DIR")
        info "pip cache: $PIP_SIZE"
        if confirm "Clear pip cache?"; then
            rm -rf "$PIP_DIR"
            removed "pip cache ($PIP_SIZE)" "pip cache"
            log SUCCESS "Caches" "pip cache cleared ($PIP_SIZE)"
        fi
    fi

    # apt
    APT_SIZE=$(safe_du /var/cache/apt)
    info "apt cache: $APT_SIZE"
    explain "'autoremove' removes packages nothing depends on anymore.
     'clean' removes all downloaded .deb files."
    if confirm "Run apt autoremove + clean?"; then
        run_with_spinner "apt autoremove" sudo apt autoremove -y
        run_with_spinner "apt clean"      sudo apt clean
        NEW_APT=$(safe_du /var/cache/apt)
        removed "APT cache ($APT_SIZE → $NEW_APT)" "apt clean"
        log SUCCESS "Caches" "apt cache cleaned"
    fi

    # snap
    if cmd_exists snap; then
        OLD_SNAPS=$(LANG=en_US.UTF-8 timeout 10 snap list --all 2>/dev/null \
            | awk '/disabled/' | wc -l || echo 0)
        if [ "$OLD_SNAPS" -gt 0 ]; then
            info "Old snap revisions: $OLD_SNAPS"
            explain "Snap keeps 2 old revisions as rollback safety. Safe to remove
             disabled revisions if you're happy with the current version."
            if confirm "Remove $OLD_SNAPS disabled snap revisions?"; then
                LANG=en_US.UTF-8 timeout 30 snap list --all 2>/dev/null \
                    | awk '/disabled/{print $1,$3}' \
                    | while read -r pkg rev; do
                        warn "Removing $pkg rev $rev"
                        timeout 15 sudo snap remove "$pkg" --revision="$rev" 2>/dev/null || true
                      done
                removed "$OLD_SNAPS disabled snap revisions" "Snap"
                log SUCCESS "Caches" "Snap old revisions removed"
            fi
        else
            ok "No old snap revisions"
        fi
    fi

    # ~/.cache
    echo ""
    echo -e "  ${BOLD}Top entries in ~/.cache:${NC}"
    explain "Holds temp data: thumbnails, compiled shaders, font caches.
     Everything here is regenerated on demand — safe to clear entirely."
    echo ""
    timeout 10 du -sh "$HOME/.cache/"* 2>/dev/null \
        | sort -hr | head -12 | awk '{printf "    %-8s %s\n",$1,$2}' \
        || info "Could not read ~/.cache"

    echo ""
    CACHE_TOTAL=$(safe_du "$HOME/.cache")
    if confirm "Clear entire ~/.cache? ($CACHE_TOTAL — all apps rebuild automatically)"; then
        run_with_spinner "Clearing ~/.cache" rm -rf "$HOME"/.cache/*
        removed "~/.cache ($CACHE_TOTAL)" "General cache"
        log SUCCESS "Caches" "~/.cache cleared ($CACHE_TOTAL)"
    fi
}

# ─────────────────────────────────────────────────────────────────
# 6. NODE_MODULES  (with root bypass prompt)
# ─────────────────────────────────────────────────────────────────
scan_node_modules() {
    phase "node_modules"
    section "Orphaned node_modules"

    explain "node_modules hold all npm dependencies for a project.
     They are never committed to git and can always be restored with 'npm install'.
     Orphaned = no package.json beside them (abandoned folder).

     ROOT-LEVEL node_modules (/usr/lib, /usr/local/lib, global installs) are
     skipped by default — removing them breaks globally installed tools."

    # Check if we should include root-level / system directories
    INCLUDE_SYSTEM=false
    echo ""
    warn "System node_modules (e.g. /usr/local/lib/node_modules) are EXCLUDED by default."
    warn "These contain globally installed npm packages (pm2, pnpm, tsx, etc.)."
    echo ""
    if confirm "BYPASS: Also scan system/root-level node_modules? (dangerous)"; then
        INCLUDE_SYSTEM=true
        warn "System directories INCLUDED — be careful what you remove!"
        log WARN "node_modules" "User bypassed system dir exclusion"
    fi

    echo ""
    echo "  Scanning $HOME for node_modules (timeout 20s)..."
    echo ""

    # Build find command based on bypass flag
    if [ "$INCLUDE_SYSTEM" = true ]; then
        # Include system dirs but warn clearly
        mapfile -t MODULES < <(
            timeout 20 sudo find / \
                -maxdepth 10 \
                -name "node_modules" \
                -type d \
                -not -path "*/node_modules/*/node_modules" \
                -not -path "*/.cache/*" \
                -not -path "*/.npm/*" \
                2>/dev/null || true
        )
    else
        # Default: home only, skip system paths
        mapfile -t MODULES < <(
            timeout 20 find "$HOME" \
                -maxdepth 8 \
                -name "node_modules" \
                -type d \
                -not -path "*/node_modules/*/node_modules" \
                -not -path "*/.cache/*" \
                -not -path "*/.npm/*" \
                2>/dev/null || true
        )
    fi

    if [ ${#MODULES[@]} -eq 0 ]; then
        ok "No node_modules found"
        log INFO "node_modules" "No node_modules found"
        return
    fi

    TOTAL_KB=0
    printf "  ${BOLD}  %-10s %-6s %-8s %s${NC}\n" "SIZE" "PKG?" "OWNER" "PATH"
    divider

    for dir in "${MODULES[@]}"; do
        SIZE=$(safe_du "$dir")
        SIZE_KB=$(safe_du_kb "$dir")
        TOTAL_KB=$((TOTAL_KB + SIZE_KB))
        PARENT=$(dirname "$dir")

        # Package.json check
        if [ -f "$PARENT/package.json" ]; then
            PKG="${GREEN}yes${NC}"
        else
            PKG="${RED}NO ${NC}"
        fi

        # Ownership classification
        OWNER=$(stat -c '%U' "$dir" 2>/dev/null || echo "?")
        if [ "$OWNER" = "root" ]; then
            OWN_LABEL="${RED}root${NC}"
        else
            OWN_LABEL="${GREEN}$OWNER${NC}"
        fi

        # Root-owned warning
        if [ "$OWNER" = "root" ] && [ "$INCLUDE_SYSTEM" = false ]; then
            # Shouldn't happen in home scan, but guard anyway
            continue
        fi

        printf "  %-10s " "$SIZE"
        echo -e "$PKG  $OWN_LABEL  $dir"
    done

    TOTAL_MB=$((TOTAL_KB / 1024))
    echo ""
    log INFO "node_modules" "Found ${#MODULES[@]} dirs, ~${TOTAL_MB}MB"
    info "Found ${#MODULES[@]} directories, ~${TOTAL_MB}MB total"
    echo ""

    echo "    1) Remove ALL listed"
    echo "       └─ npm install restores any active project"
    echo "    2) Remove ORPHANS only (no package.json parent)"
    echo "       └─ Safest — only removes abandoned ones"
    echo "    3) Skip"
    if [ "$INCLUDE_SYSTEM" = true ]; then
        echo ""
        warn "Root-owned directories require sudo and will break global tools if removed!"
    fi
    echo ""
    read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " nm_choice

    case "$nm_choice" in
        1)
            for dir in "${MODULES[@]}"; do
                OWNER=$(stat -c '%U' "$dir" 2>/dev/null || echo "?")
                if [ "$OWNER" = "root" ]; then
                    warn "Root-owned: $dir"
                    if ! confirm "  Confirm remove ROOT-owned $dir?"; then
                        kept "$dir (root-owned, skipped)"
                        continue
                    fi
                    sudo rm -rf "$dir" && removed "$dir" "node_modules (root)"
                else
                    SIZE=$(safe_du "$dir")
                    warn "Removing $dir ($SIZE)"
                    rm -rf "$dir" && removed "$dir ($SIZE)" "node_modules"
                fi
            done
            ok "Done"
            log SUCCESS "node_modules" "All node_modules removed" ;;
        2)
            REMOVED=0
            for dir in "${MODULES[@]}"; do
                PARENT=$(dirname "$dir")
                if [ ! -f "$PARENT/package.json" ]; then
                    OWNER=$(stat -c '%U' "$dir" 2>/dev/null || echo "?")
                    SIZE=$(safe_du "$dir")
                    if [ "$OWNER" = "root" ]; then
                        warn "Root-owned orphan: $dir — skipping (use bypass + option 1 to remove)"
                        log WARN "node_modules" "Skipped root-owned orphan: $dir"
                    else
                        warn "Removing orphan: $dir ($SIZE)"
                        rm -rf "$dir" && removed "$dir ($SIZE)" "Orphaned node_modules"
                        REMOVED=$((REMOVED+1))
                    fi
                else
                    kept "$(basename $(dirname $dir)) (has package.json)"
                fi
            done
            ok "Removed $REMOVED orphaned node_modules"
            log SUCCESS "node_modules" "Removed $REMOVED orphans" ;;
        *) info "Skipping"; log INFO "node_modules" "Skipped" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────
# 7. TEMP FILES
# ─────────────────────────────────────────────────────────────────
clean_temp() {
    phase "Temp Files"
    section "Temp Files, Locks & Crash Reports"

    # /tmp
    explain "/tmp is shared scratch space. Files older than 3 days are abandoned.
     The OS clears /tmp on reboot anyway — safe to remove anytime."

    echo -e "  ${BOLD}Files in /tmp older than 3 days:${NC}"
    OLD_TMP_COUNT=$(timeout 10 sudo find /tmp -mindepth 1 -mtime +3 2>/dev/null | wc -l || echo 0)
    if [ "$OLD_TMP_COUNT" -eq 0 ]; then
        ok "Nothing older than 3 days in /tmp"
    else
        TMP_SIZE=$(safe_du /tmp)
        timeout 10 sudo find /tmp -mindepth 1 -maxdepth 2 -mtime +3 2>/dev/null | head -10 \
            | while read -r f; do echo "    $f"; done
        echo ""
        if confirm "Remove $OLD_TMP_COUNT files from /tmp older than 3 days? ($TMP_SIZE total)"; then
            run_with_spinner "Removing old /tmp files" \
                sudo find /tmp -mindepth 1 -mtime +3 -delete
            removed "$OLD_TMP_COUNT old /tmp files" "Temp files"
            log SUCCESS "Temp" "Removed $OLD_TMP_COUNT /tmp files"
        fi
    fi

    # Trash
    echo ""
    TRASH="$HOME/.local/share/Trash"
    if [ -d "$TRASH" ]; then
        TRASH_COUNT=$(find "$TRASH/files" -mindepth 1 2>/dev/null | wc -l || echo 0)
        TRASH_SIZE=$(safe_du "$TRASH")
        explain "Trash = files deleted via file manager. They sit here wasting space
         until emptied."
        if [ "$TRASH_COUNT" -gt 0 ]; then
            if confirm "Empty trash? ($TRASH_COUNT items, $TRASH_SIZE)"; then
                rm -rf "$TRASH/files/"* "$TRASH/info/"* 2>/dev/null || true
                removed "Trash ($TRASH_COUNT items, $TRASH_SIZE)" "Trash"
                log SUCCESS "Temp" "Trash emptied ($TRASH_COUNT items)"
            fi
        else
            ok "Trash is empty"
        fi
    fi

    # Crash reports
    echo ""
    CRASHES=$(timeout 5 ls /var/crash/*.crash 2>/dev/null | wc -l || echo 0)
    if [ "$CRASHES" -gt 0 ]; then
        CRASH_SIZE=$(safe_du /var/crash)
        explain "Crash reports are generated when apps crash unexpectedly.
         Ubuntu sends them to Canonical once. After that they just sit here unused."
        if confirm "Remove $CRASHES crash report(s)? ($CRASH_SIZE)"; then
            sudo rm -f /var/crash/*.crash
            removed "$CRASHES crash report(s)" "Crash reports"
            log SUCCESS "Temp" "Removed $CRASHES crash reports"
        fi
    else
        ok "No crash reports"
    fi

    # Stale locks
    echo ""
    echo -e "  ${BOLD}Stale lock files:${NC}"
    explain "Lock files contain a PID. If that PID is gone, the lock is stale
     and can prevent an app from starting. Safe to remove."

    STALE_FOUND=0
    while IFS= read -r lockfile; do
        PID=$(timeout 2 cat "$lockfile" 2>/dev/null | tr -d '[:space:]' || echo "")
        if [[ "$PID" =~ ^[0-9]+$ ]] && [ -d "/proc/$PID" ]; then
            CMD=$(timeout 2 ps -p "$PID" -o comm= 2>/dev/null || echo "?")
            kept "$lockfile → PID $PID ($CMD) running"
        else
            bad "STALE: $lockfile (PID '$PID' not in /proc)"
            log WARN "Temp" "Stale lock: $lockfile (PID $PID)"
            if confirm "Remove $lockfile?"; then
                timeout 3 sudo rm -f "$lockfile"
                removed "$lockfile" "Stale lock"
            fi
            STALE_FOUND=$((STALE_FOUND+1))
        fi
    done < <(timeout 10 sudo find /tmp /var/run /run \
        -maxdepth 3 \( -name "*.lock" -o -name "*.pid" \) 2>/dev/null || true)
    [ "$STALE_FOUND" -eq 0 ] && ok "No stale lock files"

    # Old kernels
    echo ""
    OLD_K=$(dpkg -l 2>/dev/null | grep "^rc" | grep -c linux-image || echo 0)
    explain "Old kernel packages stay as safety nets. Once you've confirmed the
     new kernel works, old ones are safe to purge."
    if [ "$OLD_K" -gt 0 ]; then
        if confirm "Remove $OLD_K old kernel package(s)?"; then
            run_with_spinner "Removing old kernels" sudo apt autoremove --purge -y
            removed "$OLD_K old kernel package(s)" "Old kernels"
            log SUCCESS "Temp" "Removed $OLD_K old kernels"
        fi
    else
        ok "No old kernels to remove"
    fi
}

# ─────────────────────────────────────────────────────────────────
# 8. SYSTEM INFO & RESOURCE USAGE  (port of Get-SystemInfo + Show-ResourceUsage)
# ─────────────────────────────────────────────────────────────────
show_system_info() {
    phase "System Info"
    section "System Info & Resource Usage"

    explain "Ported from Get-SystemInfo + Show-ResourceUsage (EnhancedSystemManagement).
     Shows hardware, OS, runtime environment, and top resource consumers."

    # OS / Hardware
    echo -e "  ${BOLD}System:${NC}"
    echo ""
    printf "  %-20s %s\n" "Hostname:"    "$(hostname)"
    printf "  %-20s %s\n" "OS:"          "$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY | cut -d= -f2 | tr -d '"')"
    printf "  %-20s %s\n" "Kernel:"      "$(uname -r)"
    printf "  %-20s %s\n" "Architecture:" "$(uname -m)"
    printf "  %-20s %s\n" "Uptime:"      "$(uptime -p 2>/dev/null || uptime)"
    printf "  %-20s %s\n" "Shell:"       "$SHELL"
    printf "  %-20s %s\n" "User:"        "$USER"

    # CPU
    echo ""
    echo -e "  ${BOLD}CPU:${NC}"
    CPU_MODEL=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs || echo "?")
    CPU_CORES=$(nproc 2>/dev/null || echo "?")
    CPU_LOAD=$(timeout 3 cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo "?")
    printf "  %-20s %s\n" "Model:"  "$CPU_MODEL"
    printf "  %-20s %s\n" "Cores:"  "$CPU_CORES"
    printf "  %-20s %s\n" "Load avg (1/5/15m):" "$CPU_LOAD"

    # Memory
    echo ""
    echo -e "  ${BOLD}Memory:${NC}"
    if [ -f /proc/meminfo ]; then
        MEM_TOTAL=$(awk '/MemTotal/{printf "%.1fGB", $2/1048576}' /proc/meminfo)
        MEM_FREE=$(awk  '/MemAvailable/{printf "%.1fGB", $2/1048576}' /proc/meminfo)
        MEM_USED=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.1fGB (%.0f%%)", (t-a)/1048576, (t-a)/t*100}' /proc/meminfo)
        SWAP_TOTAL=$(awk '/SwapTotal/{printf "%.1fGB", $2/1048576}' /proc/meminfo)
        SWAP_FREE=$(awk  '/SwapFree/{printf "%.1fGB", $2/1048576}' /proc/meminfo)
        printf "  %-20s %s\n" "Total:"     "$MEM_TOTAL"
        printf "  %-20s %s\n" "Used:"      "$MEM_USED"
        printf "  %-20s %s\n" "Available:" "$MEM_FREE"
        printf "  %-20s %s / %s free\n" "Swap:" "$SWAP_TOTAL" "$SWAP_FREE"
    fi

    # Disk
    echo ""
    echo -e "  ${BOLD}Disk Usage:${NC}"
    df -h | grep -v "tmpfs\|udev\|loop" \
        | awk 'NR==1{printf "  %-22s %5s %5s %5s %5s\n",$1,$2,$3,$4,$5}
               NR>1{printf "  %-22s %5s %5s %5s %5s\n",$1,$2,$3,$4,$5}'

    # Top processes by CPU
    echo ""
    echo -e "  ${BOLD}Top 5 processes by CPU:${NC}"
    printf "  ${BOLD}  %-7s %-22s %6s %6s${NC}\n" "PID" "NAME" "CPU%" "MEM%"
    divider
    timeout 5 ps aux --sort=-%cpu 2>/dev/null \
        | awk 'NR>=2 && NR<=7{printf "  %-7s %-22s %5s%% %5s%%\n",$2,$11,$3,$4}' \
        || warn "ps timed out"

    # Top processes by MEM
    echo ""
    echo -e "  ${BOLD}Top 5 processes by Memory:${NC}"
    printf "  ${BOLD}  %-7s %-22s %6s %6s${NC}\n" "PID" "NAME" "MEM%" "CPU%"
    divider
    timeout 5 ps aux --sort=-%mem 2>/dev/null \
        | awk 'NR>=2 && NR<=7{printf "  %-7s %-22s %5s%% %5s%%\n",$2,$11,$4,$3}' \
        || warn "ps timed out"

    # Environment variables
    echo ""
    echo -e "  ${BOLD}Key environment variables:${NC}"
    for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT NODE_HOME GOPATH CARGO_HOME HOME USER PATH; do
        VAL="${!var}"
        if [ -n "$VAL" ]; then
            if [ "$var" = "PATH" ]; then
                printf "  %-20s %s entries\n" "$var:" "$(echo "$VAL" | tr ':' '\n' | wc -l)"
            else
                printf "  %-20s %s\n" "$var:" "$VAL"
            fi
        fi
    done

    log SUCCESS "System Info" "System info displayed"
}

# ─────────────────────────────────────────────────────────────────
# 9. ENVIRONMENT HEALTH CHECK & REPAIR
#    (port of Test-EnvironmentConsistency + Repair-Environment + Clean-EnvironmentPaths)
# ─────────────────────────────────────────────────────────────────
check_env() {
    phase "Environment Check"
    section "Environment Health Check & Repair"

    explain "Ported from Test-EnvironmentConsistency + Repair-Environment.
     Checks PATH for invalid/duplicate entries, missing managed dirs,
     and common development environment variables."

    ISSUES=()

    # ── PATH validation ───────────────────────────────────────────
    echo -e "  ${BOLD}Scanning PATH entries:${NC}"
    echo ""
    VALID=0; INVALID=0; DUPES=0
    declare -A SEEN_PATHS=()

    IFS=':' read -ra PATH_ENTRIES <<< "$PATH"
    for p in "${PATH_ENTRIES[@]}"; do
        [ -z "$p" ] && continue
        NORM="${p%/}"  # normalize trailing slash
        if [ -n "${SEEN_PATHS[$NORM]+_}" ]; then
            bad "Duplicate PATH entry: $p"
            ISSUES+=("DUPLICATE_PATH:$p")
            DUPES=$((DUPES+1))
        elif [ ! -d "$p" ]; then
            bad "Invalid (not a dir): $p"
            ISSUES+=("INVALID_PATH:$p")
            log WARN "Environment" "Invalid PATH entry: $p"
            INVALID=$((INVALID+1))
        else
            ok "$p"
            VALID=$((VALID+1))
        fi
        SEEN_PATHS[$NORM]=1
    done

    echo ""
    info "PATH: $VALID valid, $INVALID invalid, $DUPES duplicates"

    # ── Managed dirs ──────────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Managed directory check:${NC}"
    echo ""
    for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT; do
        VAL="${!var}"
        if [ -z "$VAL" ]; then
            warn "$var not set"
            ISSUES+=("MISSING_ENV:$var")
        elif [ ! -d "$VAL" ]; then
            bad "$var set but directory missing: $VAL"
            ISSUES+=("MISSING_DIR:$var=$VAL")
            log WARN "Environment" "Missing dir: $VAL ($var)"
        else
            ok "$var = $VAL"
        fi
    done

    # ── Tool availability ─────────────────────────────────────────
    echo ""
    echo -e "  ${BOLD}Tool availability:${NC}"
    echo ""
    printf "  ${BOLD}  %-20s %s${NC}\n" "TOOL" "STATUS"
    divider
    for tool in git node npm python3 pip3 docker sqlite3 curl wget gcc make; do
        if cmd_exists "$tool"; then
            VER=$(timeout 2 "$tool" --version 2>/dev/null | head -1 | awk '{print $NF}' || echo "ok")
            printf "  %-20s ${GREEN}✓${NC} %s\n" "$tool" "$VER"
        else
            printf "  %-20s ${YELLOW}—${NC} not found\n" "$tool"
        fi
    done

    # ── Issue report & repair ─────────────────────────────────────
    echo ""
    if [ ${#ISSUES[@]} -eq 0 ]; then
        ok "Environment is consistent — no issues found"
        log SUCCESS "Environment" "Environment check passed"
        return
    fi

    echo -e "  ${BOLD}${YELLOW}Found ${#ISSUES[@]} environment issue(s):${NC}"
    echo ""
    for iss in "${ISSUES[@]}"; do
        TYPE="${iss%%:*}"
        DETAIL="${iss#*:}"
        case "$TYPE" in
            INVALID_PATH)   warn "Invalid PATH: $DETAIL   [Severity: Medium]  Fix: remove from PATH" ;;
            DUPLICATE_PATH) warn "Duplicate PATH: $DETAIL [Severity: Low]     Fix: deduplicate PATH" ;;
            MISSING_ENV)    bad  "Missing env var: $DETAIL [Severity: High]   Fix: export $DETAIL=/your/path" ;;
            MISSING_DIR)    bad  "Missing directory: $DETAIL [Severity: High] Fix: mkdir -p" ;;
        esac
    done

    echo ""
    echo "    1) Auto-repair PATH (remove invalid + duplicate entries)"
    echo "    2) Create missing managed directories"
    echo "    3) Both"
    echo "    4) Skip"
    echo ""
    read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " env_choice

    case "$env_choice" in
        1|3)
            # Clean PATH (port of Clean-EnvironmentPaths)
            echo ""
            info "Cleaning PATH..."
            NEW_PATH=""
            declare -A SEEN2=()
            IFS=':' read -ra ENTRIES <<< "$PATH"
            for p in "${ENTRIES[@]}"; do
                [ -z "$p" ] && continue
                NORM="${p%/}"
                if [ -n "${SEEN2[$NORM]+_}" ]; then
                    warn "Removed duplicate: $p"
                    removed "Duplicate PATH entry: $p" "PATH cleanup"
                elif [ ! -d "$p" ]; then
                    warn "Removed invalid: $p"
                    removed "Invalid PATH entry: $p" "PATH cleanup"
                else
                    NEW_PATH="${NEW_PATH:+$NEW_PATH:}$p"
                    SEEN2[$NORM]=1
                fi
            done
            export PATH="$NEW_PATH"
            ok "PATH cleaned (session only — add to ~/.bashrc to persist)"
            log SUCCESS "Environment" "PATH cleaned"
            ;;&
        2|3)
            # Create missing dirs
            for iss in "${ISSUES[@]}"; do
                TYPE="${iss%%:*}"; DETAIL="${iss#*:}"
                if [ "$TYPE" = "MISSING_DIR" ]; then
                    DIRPATH="${DETAIL#*=}"
                    if confirm "Create missing directory $DIRPATH?"; then
                        mkdir -p "$DIRPATH" && ok "Created $DIRPATH" \
                            && log SUCCESS "Environment" "Created missing dir: $DIRPATH"
                    fi
                fi
            done ;;
        *) info "Skipping repair" ;;
    esac
}

# ─────────────────────────────────────────────────────────────────
# 10. STARTUP PROGRAMS & SERVICES  (port of Show-StartupPrograms)
# ─────────────────────────────────────────────────────────────────
show_startup() {
    phase "Startup"
    section "Startup Programs & Services"

    explain "Ported from Show-StartupPrograms (EnhancedSystemManagement).
     On Linux this covers: systemd enabled services, user systemd units,
     XDG autostart apps, and cron-based startup items."

    # Systemd enabled services
    echo -e "  ${BOLD}Enabled systemd services (system):${NC}"
    explain "These start automatically at boot. Severity = High if unexpected.
     'enabled' = starts at boot. 'static' = pulled in by others."
    echo ""
    timeout 10 systemctl list-unit-files --type=service --state=enabled \
        --no-pager 2>/dev/null \
        | grep -v '^UNIT\|^$\|loaded units listed' \
        | awk '{printf "  %-45s %s\n",$1,$2}' | head -30 \
        || warn "systemctl timed out"

    # User systemd services
    echo ""
    echo -e "  ${BOLD}Enabled systemd services (user):${NC}"
    timeout 10 systemctl --user list-unit-files --type=service --state=enabled \
        --no-pager 2>/dev/null \
        | grep -v '^UNIT\|^$\|loaded units listed' \
        | awk '{printf "  %-45s %s\n",$1,$2}' | head -15 \
        || info "No user services or systemd --user not available"

    # XDG autostart
    echo ""
    echo -e "  ${BOLD}XDG autostart programs (~/.config/autostart):${NC}"
    explain "These desktop apps launch automatically when you log into a GUI session."
    AUTOSTART_COUNT=0
    for dir in "$HOME/.config/autostart" "/etc/xdg/autostart"; do
        [ -d "$dir" ] || continue
        FILES=$(ls "$dir"/*.desktop 2>/dev/null || true)
        [ -z "$FILES" ] && continue
        echo -e "  ${CYAN}$dir/${NC}"
        for f in $FILES; do
            NAME=$(grep -m1 '^Name=' "$f" 2>/dev/null | cut -d= -f2 || basename "$f")
            EXEC=$(grep -m1 '^Exec=' "$f" 2>/dev/null | cut -d= -f2 | cut -d' ' -f1 || echo "?")
            HIDDEN=$(grep -m1 '^Hidden=true' "$f" 2>/dev/null || echo "")
            STATUS="active"
            [ -n "$HIDDEN" ] && STATUS="disabled"
            printf "    %-30s %-30s %s\n" "$NAME" "$EXEC" "$STATUS"
            AUTOSTART_COUNT=$((AUTOSTART_COUNT+1))
        done
        echo ""
    done
    [ "$AUTOSTART_COUNT" -eq 0 ] && info "No XDG autostart entries found"

    # rc.local
    echo ""
    if [ -f /etc/rc.local ]; then
        echo -e "  ${BOLD}/etc/rc.local (legacy startup):${NC}"
        grep -v '^#' /etc/rc.local | grep -v '^$' \
            | while read -r line; do echo "    $line"; done
    fi

    # Option to disable a service
    echo ""
    echo "    d) Disable a systemd service"
    echo "    s) Skip"
    echo ""
    read -r -p "  $(echo -e "${CYAN}▶${NC}") Choice: " svc_choice
    if [ "$svc_choice" = "d" ]; then
        read -r -p "  Service name to disable (e.g. bluetooth.service): " svc_name
        if [ -n "$svc_name" ]; then
            if confirm "Disable $svc_name? (stops it from starting at boot)"; then
                sudo systemctl disable "$svc_name" 2>/dev/null \
                    && ok "Disabled $svc_name" && removed "$svc_name" "Startup service disabled" \
                    && log SUCCESS "Startup" "Disabled service: $svc_name" \
                    || bad "Could not disable $svc_name"
            fi
        fi
    fi
    log SUCCESS "Startup" "Startup section complete"
}

# ─────────────────────────────────────────────────────────────────
# 12. DISK SUMMARY
# ─────────────────────────────────────────────────────────────────
disk_summary() {
    section "Disk Summary"

    echo -e "  ${BOLD}Filesystems:${NC}"
    df -h | grep -v "tmpfs\|udev\|loop" \
        | awk 'NR==1{printf "  %-20s %5s %5s %5s %5s\n",$1,$2,$3,$4,$5}
               NR>1{printf "  %-20s %5s %5s %5s %5s\n",$1,$2,$3,$4,$5}'

    echo ""
    echo -e "  ${BOLD}Largest directories in home:${NC}"
    timeout 15 du -sh "$HOME"/*/  2>/dev/null \
        | sort -hr | head -12 | awk '{printf "    %-8s %s\n",$1,$2}' \
        || warn "du timed out"

    echo ""
    echo -e "  ${BOLD}Cache snapshot:${NC}"
    for label_path in "npm:$HOME/.npm" "pip:$HOME/.cache/pip" "cache:$HOME/.cache" \
                      "logs:/var/log" "tmp:/tmp" "snap:/var/lib/snapd"; do
        label="${label_path%%:*}"; path="${label_path#*:}"
        SIZE=$(safe_du "$path")
        printf "    %-14s %s\n" "$label" "$SIZE"
    done
}

# ─────────────────────────────────────────────────────────────────
# 13. EXPORT SESSION REPORT  (port of Export-SystemInfo)
# ─────────────────────────────────────────────────────────────────
export_report() {
    phase "Export"
    section "Export Session Report"

    REPORT_DIR="${DEV_ROOT:-$HOME}/exports"
    mkdir -p "$REPORT_DIR" 2>/dev/null || REPORT_DIR="/tmp"
    REPORT_FILE="$REPORT_DIR/cleanup_report_$(date '+%Y%m%d_%H%M%S').txt"

    {
        echo "Enhanced System Management — Bash Cleanup Report"
        echo "Generated: $(date)"
        echo "Session start: $SESSION_START"
        echo "=================================================================="
        echo ""
        echo "SYSTEM INFORMATION:"
        echo "  Hostname:    $(hostname)"
        echo "  OS:          $(lsb_release -ds 2>/dev/null || echo 'Linux')"
        echo "  Kernel:      $(uname -r)"
        echo "  User:        $USER"
        echo "  Uptime:      $(uptime -p 2>/dev/null || uptime)"
        echo ""
        echo "DISK USAGE:"
        df -h | grep -v "tmpfs\|udev\|loop"
        echo ""
        echo "ENVIRONMENT:"
        echo "  PATH entries: $(echo "$PATH" | tr ':' '\n' | wc -l)"
        for var in DEV_ROOT SHARED_HOME PROJECTS_ROOT; do
            VAL="${!var}"
            [ -n "$VAL" ] && echo "  $var = $VAL"
        done
        echo ""
        echo "CLEANUP LOG (${#CLEANUP_LOG[@]} items removed):"
        if [ ${#CLEANUP_LOG[@]} -eq 0 ]; then
            echo "  Nothing removed this session"
        else
            for entry in "${CLEANUP_LOG[@]}"; do
                echo "  [-] $entry"
            done
        fi
        echo ""
        echo "ISSUES DETECTED (${#ISSUE_LOG[@]}):"
        if [ ${#ISSUE_LOG[@]} -eq 0 ]; then
            echo "  No issues detected"
        else
            for iss in "${ISSUE_LOG[@]}"; do
                echo "  [!] $iss"
            done
        fi
        echo ""
        DISK_AFTER=$(df / | awk 'NR==2{print $3}')
        FREED=$(( DISK_BEFORE - DISK_AFTER ))
        FREED_MB=$(( FREED / 1024 ))
        echo "DISK FREED THIS SESSION: ~${FREED_MB}MB"
        echo ""
        echo "Full session log: /tmp/cleanup_session.log"
    } > "$REPORT_FILE"

    ok "Report saved to: $REPORT_FILE"
    log SUCCESS "Export" "Report saved: $REPORT_FILE"

    if confirm "View report now?"; then
        less "$REPORT_FILE"
    fi
}

# ─────────────────────────────────────────────────────────────────
# EXIT REPORT
# ─────────────────────────────────────────────────────────────────
show_exit_report() {
    section "Session Report"

    DISK_AFTER=$(df / | awk 'NR==2{print $3}')
    FREED_KB=$(( DISK_BEFORE - DISK_AFTER ))

    if [ ${#CLEANUP_LOG[@]} -eq 0 ]; then
        info "Nothing was removed this session"
    else
        echo -e "  ${BOLD}Items removed:${NC}"
        echo ""
        for entry in "${CLEANUP_LOG[@]}"; do
            ITEM="${entry%% | *}"; TYPE="${entry##* | }"
            printf "    ${RED}✗${NC}  %-42s ${CYAN}[%s]${NC}\n" "$ITEM" "$TYPE"
        done
        echo ""
        echo -e "  ${BOLD}${GREEN}Total: ${#CLEANUP_LOG[@]} item(s) removed${NC}"
        if [ "$FREED_KB" -gt 0 ]; then
            FREED_MB=$(( FREED_KB / 1024 ))
            echo -e "  ${BOLD}${GREEN}Disk freed: ~${FREED_MB}MB${NC}"
        fi
    fi

    if [ ${#ISSUE_LOG[@]} -gt 0 ]; then
        echo ""
        echo -e "  ${BOLD}${YELLOW}Issues flagged (${#ISSUE_LOG[@]}):${NC}"
        for iss in "${ISSUE_LOG[@]}"; do
            warn "$iss"
        done
    fi

    echo ""
    df -h / | awk 'NR==2{printf "  Disk after:   %s used of %s  (%s full)\n",$3,$2,$5}'
    echo ""
    log INFO "Session" "Session complete. ${#CLEANUP_LOG[@]} items removed."
}

# ─────────────────────────────────────────────────────────────────
# MAIN LOOP
# ─────────────────────────────────────────────────────────────────
while true; do
    show_menu; echo ""
    case "$choice" in
        1)  manage_crons ;;
        2)  manage_docker ;;
        3)  scan_processes ;;
        4)  clear_logs ;;
        5)  clear_caches ;;
        6)  scan_node_modules ;;
        7)  clean_temp ;;
        8)  show_system_info ;;
        9)  check_env ;;
        10) show_startup ;;
        11)
            manage_crons;      pause
            clear_logs;        pause
            clear_caches;      pause
            scan_node_modules; pause
            manage_docker;     pause
            scan_processes;    pause
            clean_temp;        pause
            show_system_info;  pause
            check_env;         pause
            show_startup
            ;;
        12) disk_summary ;;
        13) export_report ;;
        0)
            show_exit_report
            echo -e "  ${GREEN}Done. Goodbye!${NC}"
            echo ""
            exit 0 ;;
        *) warn "Invalid choice — enter 0–13" ;;
    esac
    pause
    clear
    echo -e "${BOLD}${BLUE}  Local Machine Cleanup${NC}  |  $(date '+%H:%M')  |  Phase: $CURRENT_PHASE"
    divider
done
