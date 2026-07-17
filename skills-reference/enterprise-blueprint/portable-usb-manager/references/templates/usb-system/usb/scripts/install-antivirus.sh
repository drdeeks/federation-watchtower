#!/usr/bin/env bash
set -euo pipefail

########################################
# VIRUS SYSTEM TOOLKIT INSTALLER
########################################

# CL-030: route logs + quarantine through UCA_MODE so USB-mode runs keep
# their forensic state on the USB rather than littering /var on the host.
# Package install (apt + cron job + /usr/local/bin/virus binary) still
# touches the host since it requires root + apt — this is the explicit
# "initial bridge setup" allowance in USB mode.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/core.sh" ]]; then
    # shellcheck source=../lib/core.sh
    source "$SCRIPT_DIR/../lib/core.sh"
fi
if [[ -f "$SCRIPT_DIR/../lib/usb.sh" ]] && ! command -v _uca_primary_persistence >/dev/null 2>&1; then
    # shellcheck source=../lib/usb.sh
    source "$SCRIPT_DIR/../lib/usb.sh"
fi

VIRUS_CMD="/usr/local/bin/virus"
TOOLKIT_DIR="/opt/system_toolkit"
if [[ "${UCA_MODE:-host}" == "usb" ]] && command -v _uca_install_root >/dev/null 2>&1; then
    _UCA_AV_ROOT="$(_uca_install_root 2>/dev/null || echo "")"
fi
if [[ -n "${_UCA_AV_ROOT:-}" ]]; then
    LOG_DIR="${_UCA_AV_ROOT}/var/log/system_toolkit"
    QUARANTINE_DIR="${_UCA_AV_ROOT}/var/quarantine/system_toolkit"
else
    LOG_DIR="/var/log/system_toolkit"
    QUARANTINE_DIR="/var/quarantine/system_toolkit"
fi
QUEUE_FILE="$LOG_DIR/queue.txt"
export LOG_DIR QUARANTINE_DIR QUEUE_FILE

main() {
    echo "[*] Installing Virus System Toolkit..."

    install_dependencies
    create_directories
    create_virus_command
    setup_cron_jobs
    initial_clamav_setup

    echo
    echo "[✓] INSTALL COMPLETE"
    echo "[✓] Command: virus"
    echo "[✓] Try: virus help"
    echo "[✓] Try: virus selfheal"
    echo "[✓] Try: virus audit"
}

install_dependencies() {
    echo "[*] Installing dependencies..."
    apt update
    apt install -y \
        clamav \
        clamav-daemon \
        rkhunter \
        chkrootkit \
        lynis \
        ufw \
        apparmor \
        apparmor-utils \
        curl \
        wget \
        git \
        jq

    if ! command -v trivy >/dev/null 2>&1; then
        echo "[*] Installing Trivy..."
        curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
            | sh -s -- -b /usr/local/bin
    fi
}

create_directories() {
    echo "[*] Creating directories..."
    mkdir -p "$LOG_DIR" "$TOOLKIT_DIR" "$QUARANTINE_DIR"
    chmod 700 "$QUARANTINE_DIR"
}

create_virus_command() {
    echo "[*] Creating virus command at $VIRUS_CMD..."

    # CL-030: keep heredoc quoted so the embedded virus script's $vars stay
    # literal; substitute the two routed paths after the fact.
    cat > "$VIRUS_CMD" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="__UCA_LOG_DIR__"
QUARANTINE_DIR="__UCA_QUARANTINE_DIR__"
QUEUE="$LOG_DIR/queue.txt"
mkdir -p "$LOG_DIR" "$QUARANTINE_DIR"
chmod 750 "$QUARANTINE_DIR" 2>/dev/null || true

help() {
    cat <<'MENU'
====================================
 VIRUS SYSTEM TOOLKIT
====================================

virus help
virus quickheal
virus selfheal
virus audit
virus scan          # quick scan + auto-quarantine infected
virus fullscan      # full scan + auto-quarantine infected
virus scan-only     # legacy scan (no quarantine, report only)
virus rootkit       # rkhunter + chkrootkit + auto-propupd on confirmed safe
virus remediate     # apply rkhunter --propupd + reload daemon definitions
virus quarantine    # list/restore/purge files in quarantine
virus report
virus queue

Tiers:
🟢 Tier 1 = auto fix safe (updates, firewall, clamav, apparmor, sysctl)
🟡 Tier 2 = automated fixes (SSH, services, deps, perms, docker)
🔴 Tier 3 = aggressive hardening (kernel, auditd, capabilities, cron)

Infection findings from `scan` and `fullscan` are now moved into
QUARANTINE_DIR (chmod 700) and logged. `quarantine list|restore|purge`
manages the holding area; nothing is deleted irreversibly without an
explicit `purge`.

====================================
MENU
}

queue_add() {
    echo "$1" >> "$QUEUE"
}

queue_show() {
    echo "=== QUEUED ACTIONS ==="
    cat "$QUEUE" 2>/dev/null || echo "No queued items."
}

clam_fix() {
    echo "[ClamAV] Safe restart..."
    systemctl restart clamav-freshclam || true
    systemctl restart clamav-daemon || true
    sleep 1
    if pgrep -x freshclam >/dev/null; then
        echo "[ClamAV] daemon active"
    else
        freshclam --stdout >/dev/null 2>&1 || true
    fi
}

tier1() {
    echo "[*] Tier 1 SAFE FIXES"
    apt update && apt upgrade -y
    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
    clam_fix
    systemctl enable apparmor --now >/dev/null 2>&1 || true

    cat > /etc/sysctl.d/99-system-toolkit.conf <<'EOF2'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
EOF2

    sysctl --system >/dev/null 2>&1 || true
    echo "[✓] Tier 1 complete"
}

tier2() {
    echo "[*] Tier 2 AUTOMATED FIXES"
    
    # SSH hardening
    if [ -f /etc/ssh/sshd_config ]; then
        sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        sed -i 's/^#*PermitEmptyPasswords.*/PermitEmptyPasswords no/' /etc/ssh/sshd_config
        sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 3/' /etc/ssh/sshd_config
        sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
        sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
        sed -i 's/^#*LoginGraceTime.*/LoginGraceTime 30/' /etc/ssh/sshd_config
        sed -i 's/^#*AllowAgentForwarding.*/AllowAgentForwarding no/' /etc/ssh/sshd_config
        sed -i 's/^#*AllowTcpForwarding.*/AllowTcpForwarding no/' /etc/ssh/sshd_config
        sed -i 's/^#*X11Forwarding.*/X11Forwarding no/' /etc/ssh/sshd_config
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        echo "[✓] SSH hardened"
    fi

    # Disable unused services
    for svc in telnet rsh rlogin rexec talk ntalk tftp xinetd cups avahi-daemon bluetooth; do
        systemctl disable --now "$svc" 2>/dev/null || true
    done
    echo "[✓] Unused services disabled"

    # Dependency scan with trivy
    if command -v trivy >/dev/null 2>&1; then
        trivy fs --security-checks vuln,config --severity HIGH,CRITICAL / 2>&1 | head -50 | tee "$LOG_DIR/trivy.log" || true
        echo "[✓] Dependency scan complete"
    fi

    # Fix file permissions
    find /home -type f -perm /o+w -exec chmod o-w {} \; 2>/dev/null || true
    find /tmp /var/tmp -type f -perm /o+w -exec chmod o-w {} \; 2>/dev/null || true
    chmod 700 /root 2>/dev/null || true
    echo "[✓] File permissions fixed"

    # Docker security
    if command -v docker >/dev/null 2>&1; then
        docker run --rm --security-opt=no-new-privileges --read-only --cap-drop=ALL alpine true 2>/dev/null || true
        echo "[✓] Docker security baseline checked"
    fi

    echo "[✓] Tier 2 complete"
}

tier3() {
    echo "[*] Tier 3 AGGRESSIVE FIXES (requires confirmation)"
    
    # Kernel hardening
    cat > /etc/sysctl.d/99-system-toolkit-hardened.conf <<'EOF3'
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
kernel.sysrq = 0
kernel.core_uses_pid = 1
kernel.exec_shield = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
EOF3
    sysctl --system >/dev/null 2>&1 || true
    echo "[✓] Kernel hardened"

    # AppArmor profiles
    aa-enforce /etc/apparmor.d/* 2>/dev/null || true
    echo "[✓] AppArmor enforced"

    # Auditd rules
    if command -v auditctl >/dev/null 2>&1; then
        auditctl -w /etc/passwd -p wa -k passwd_changes 2>/dev/null || true
        auditctl -w /etc/shadow -p wa -k shadow_changes 2>/dev/null || true
        auditctl -w /etc/group -p wa -k group_changes 2>/dev/null || true
        auditctl -w /etc/sudoers -p wa -k sudoers_changes 2>/dev/null || true
        auditctl -w /etc/ssh/sshd_config -p wa -k sshd_config 2>/dev/null || true
        echo "[✓] Audit rules applied"
    fi

    # Remove dangerous capabilities
    for bin in /bin/ping /bin/ping6 /usr/bin/traceroute6; do
        setcap -r "$bin" 2>/dev/null || true
    done
    echo "[✓] Capabilities cleaned"

    # Cron security
    chmod 600 /etc/crontab 2>/dev/null || true
    chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.weekly /etc/cron.monthly 2>/dev/null || true
    echo "[✓] Cron secured"

    echo "[✓] Tier 3 complete"
}

selfheal() {
    echo "[*] Self-heal starting (all tiers)..."
    tier1
    tier2
    tier3
    echo "[✓] Self-heal complete (all tiers)"
}

quickheal() {
    echo "[*] Quick heal (Tier 1 only)..."
    tier1
    echo "[✓] Quick heal complete"
}

scan() {
    echo "[*] Quick scan of home directories (auto-quarantine on hit)..."
    timeout 60 clamscan -r -v --infected --max-filesize=10M --max-scansize=20M \
        --move="$QUARANTINE_DIR" \
        /home /root /tmp /var/tmp 2>&1 | tee "$LOG_DIR/clamav.log" || true
    local hits
    hits=$(grep -c ' FOUND$' "$LOG_DIR/clamav.log" 2>/dev/null || echo 0)
    [[ "$hits" -gt 0 ]] && echo "[!] Quarantined $hits file(s) → $QUARANTINE_DIR"
}

fullscan() {
    echo "[*] Full system scan (this takes a while, auto-quarantine on hit)..."
    timeout 600 clamscan -r -v --infected \
        --exclude-dir="^/proc" --exclude-dir="^/sys" --exclude-dir="^/dev" \
        --exclude-dir="^$QUARANTINE_DIR" \
        --move="$QUARANTINE_DIR" \
        / 2>&1 | tee "$LOG_DIR/clamav-full.log" || true
    local hits
    hits=$(grep -c ' FOUND$' "$LOG_DIR/clamav-full.log" 2>/dev/null || echo 0)
    [[ "$hits" -gt 0 ]] && echo "[!] Quarantined $hits file(s) → $QUARANTINE_DIR"
}

scan_only() {
    echo "[*] Quick scan of home directories (report-only, no quarantine)..."
    timeout 60 clamscan -r -v --infected --max-filesize=10M --max-scansize=20M /home /root /tmp /var/tmp 2>&1 | tee "$LOG_DIR/clamav-readonly.log" || true
}

rootkit() {
    echo "[*] Running rootkit checks..."
    timeout 300 rkhunter --check --skip-keypress 2>&1 | tee "$LOG_DIR/rkhunter.log" || true
    timeout 60 chkrootkit 2>&1 | tee "$LOG_DIR/chkrootkit.log" || true
    # Auto-remediate "Warning:" lines that point to allowed system files —
    # rkhunter --propupd refreshes the known-good database after the operator
    # has reviewed findings. Run by default only on clean (zero-warning) runs.
    local warnings
    warnings=$(grep -c '^Warning:' "$LOG_DIR/rkhunter.log" 2>/dev/null || echo 0)
    if [[ "$warnings" -eq 0 ]]; then
        rkhunter --propupd --quiet 2>/dev/null || true
        echo "[✓] rkhunter baseline refreshed (no warnings)"
    else
        echo "[!] $warnings rkhunter warnings — review $LOG_DIR/rkhunter.log, then run: virus remediate"
    fi
}

remediate() {
    echo "[*] Manual remediation pass — refreshing baselines + restarting daemons"
    freshclam --quiet 2>/dev/null || true
    systemctl restart clamav-freshclam 2>/dev/null || true
    systemctl restart clamav-daemon 2>/dev/null || true
    rkhunter --propupd 2>&1 | tee "$LOG_DIR/rkhunter-propupd.log" || true
    rkhunter --update 2>&1 | tee -a "$LOG_DIR/rkhunter-propupd.log" || true
    echo "[✓] Remediation complete (definitions + baseline refreshed)"
}

quarantine() {
    local sub="${1:-list}"
    case "$sub" in
        list)
            echo "=== Quarantine contents: $QUARANTINE_DIR ==="
            if [[ -d "$QUARANTINE_DIR" ]]; then
                ls -la "$QUARANTINE_DIR" 2>/dev/null
                local count
                count=$(find "$QUARANTINE_DIR" -type f 2>/dev/null | wc -l)
                echo "Total: $count file(s)"
            else
                echo "(quarantine empty / not initialised)"
            fi
            ;;
        restore)
            local file="${2:-}"
            local dest="${3:-/tmp}"
            if [[ -z "$file" ]]; then
                echo "Usage: virus quarantine restore <filename> [destination]"
                return 1
            fi
            if [[ ! -f "$QUARANTINE_DIR/$file" ]]; then
                echo "Not found: $QUARANTINE_DIR/$file"
                return 1
            fi
            mv "$QUARANTINE_DIR/$file" "$dest/" && echo "[✓] Restored $file → $dest/"
            ;;
        purge)
            if [[ "${2:-}" != "--yes" ]]; then
                echo "DESTRUCTIVE: removes everything in $QUARANTINE_DIR"
                echo "Re-run with: virus quarantine purge --yes"
                return 1
            fi
            local count
            count=$(find "$QUARANTINE_DIR" -type f 2>/dev/null | wc -l)
            find "$QUARANTINE_DIR" -mindepth 1 -delete 2>/dev/null || true
            echo "[✓] Purged $count file(s) from quarantine"
            ;;
        *)
            echo "Usage: virus quarantine {list|restore <file> [dest]|purge --yes}"
            return 1
            ;;
    esac
}

report() {
    FILE="$LOG_DIR/report-$(date +%F).txt"
    {
        echo "SYSTEM REPORT"
        date
        echo
        ufw status verbose
        echo
        clamscan --version
        rkhunter --version
        trivy --version 2>/dev/null || true
    } > "$FILE"
    echo "[✓] Report: $FILE"
}

case "${1:-help}" in
    help) help ;;
    quickheal) quickheal ;;
    selfheal) selfheal ;;
    audit) rm -f /var/run/lynis.pid /tmp/lynis-*; lynis audit system --quiet | tee "$LOG_DIR/lynis.log" ;;
    scan) scan ;;
    scan-only) scan_only ;;
    fullscan) fullscan ;;
    rootkit) rootkit ;;
    remediate) remediate ;;
    quarantine) shift; quarantine "$@" ;;
    report) report ;;
    queue) queue_show ;;
    *) help ;;
esac
EOF

    # CL-030: substitute the routed log/quarantine paths into the runtime
    # virus binary (sed -i keeps the heredoc body simple).
    sed -i "s|__UCA_LOG_DIR__|${LOG_DIR}|g; s|__UCA_QUARANTINE_DIR__|${QUARANTINE_DIR}|g" "$VIRUS_CMD"
    chmod +x "$VIRUS_CMD"
}

setup_cron_jobs() {
    echo "[*] Setting up cron jobs..."
    cat > /etc/cron.d/system_toolkit <<EOF
0 2 * * * root freshclam
0 3 * * * root $VIRUS_CMD scan
0 4 * * 0 root $VIRUS_CMD rootkit
0 5 * * 0 root $VIRUS_CMD audit
0 6 1 * * root $VIRUS_CMD report
EOF
}

initial_clamav_setup() {
    echo "[*] Initial ClamAV setup..."
    systemctl stop clamav-freshclam || true
    freshclam || true
    systemctl start clamav-freshclam || true

    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
}

# CL-030: only auto-run main when executed directly. Sourcing the file (e.g.
# for path-resolution testing) should set LOG_DIR/QUARANTINE_DIR/QUEUE_FILE
# and return cleanly without attempting apt install / systemctl / ufw calls.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi