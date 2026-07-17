# Complete System Integration: USB + Hemlock + Auto-Start + VM

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.

This document describes the complete integration of all components into a single, self-contained, auto-starting portable compute platform.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    HOST SYSTEM (Linux/macOS/WSL2)               │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  USB DRIVE (Ventoy)                                       │  │
│  │  ┌─────────────────┐  ┌─────────────────┐                 │  │
│  │  │ exFAT Partition │  │  EFI Partition  │                 │  │
│  │  │  (Free Space)   │  │  (VTOYEFI)      │                 │  │
│  │  │  • ISOs         │  └─────────────────┘                 │  │
│  │  │  • persistence/ │                                      │  │
│  │  │     ubuntu-persistence.dat (ext4 loop)                  │  │
│  │  │  • ventoy/ventoy.json                                   │  │
│  │  │  • scripts/ (host-accessible helpers)                   │  │
│  │  └──────────────────────────────────────────────────────┘  │
│  └──────────────────────────────────────────────────────────┘  │
│                              │                                   │
│         ┌────────────────────┼────────────────────┐             │
│         ▼                    ▼                    ▼             │
│  ┌─────────────┐    ┌─────────────────┐   ┌──────────────┐   │
│  │   VM (QEMU) │    │ Hemlock Gateway │   │ Auto-Start   │   │
│  │  Headless   │    │  (Docker)       │   │  Services    │   │
│  │  SSH 2222   │    │  Port 18789     │   │  systemd/    │   │
│  │  USB Pass-  │    │  MCP 41214      │   │  LaunchAgent │   │
│  │  through    │    │  Agents/Crews   │   │  USB Detect  │   │
│  └─────────────┘    └─────────────────┘   └──────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Component Integration Points

### 1. Ventoy USB + Persistence
- **Ventoy** provides multi-ISO boot on exFAT partition
- **Persistence** stored as `ubuntu-persistence.dat` (ext4 loop device)
- **ventoy.json** maps ISO to persistence backend
- Tools installed INTO persistence via chroot (not host)

### 2. VM Auto-Boot (Headless)
- **QEMU/KVM** on Linux, **UTM** on macOS, **Hyper-V** on Windows/WSL2
- **SSH port forwarding**: Host:2222 → Guest:22
- **USB passthrough**: Ventoy drive passed to VM as raw block device
- **Headless mode**: No GUI, `-nographic` or headless UTM config

### 3. Hemlock Agent Orchestration
- **Dockerized Gateway**: `hemlock-runtime` container with `--restart unless-stopped`
- **Volumes**: `hemlock-gateway`, `hemlock-agents`, `hemlock-crews`, `hemlock-shared-skills`
- **Ports**: Gateway 18789, MCP Proxy 41214, Compute ports (8888, 8080, 11434, etc.)
- **Isolation**: `--security-opt=no-new-privileges`, `--cap-drop=ALL`, resource limits

### 4. Auto-Start Pipeline

#### Linux (systemd)
```ini
# hemlock-gateway.service
[Unit]
Description=Hemlock Agent Orchestration Gateway
After=docker.service network.target
Requires=docker.service

[Service]
Type=simple
ExecStart=/entrypoint.sh gateway
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

```ini
# hemlock-usb-detect.service
[Unit]
Description=Hemlock USB Detection and Auto-Start
After=hemlock-gateway.service
Requires=hemlock-gateway.service

[Service]
Type=simple
ExecStart=/scripts/usb-detector.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**usb-detector.sh** loop:
```bash
while true; do
    if blkid -l | grep -q "Ventoy"; then
        # 1. Ensure Hemlock gateway running
        systemctl is-active hemlock-gateway || systemctl start hemlock-gateway
        
        # 2. Auto-attach agents (via entrypoint.sh agent-list)
        docker exec hemlock-runtime /entrypoint.sh agent-list
        
        # 3. Start QEMU VM if not running
        if ! pgrep -q qemu; then
            /scripts/start-usb-vm.sh &
        fi
    fi
    sleep 10
done
```

#### macOS (LaunchAgent)
```xml
<!-- com.hemlock.gateway.plist -->
<dict>
    <key>Label</key><string>com.hemlock.gateway</string>
    <key>ProgramArguments</key>
    <array><string>/bin/bash</string><string>-c</string><string>HEMLOCK_DIR=... /entrypoint.sh gateway</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/><key>Crashed</key><true/></dict>
    <key>RestartInterval</key><integer>10</integer>
</dict>
```

#### WSL2
- Enable systemd: `/etc/wsl.conf` → `[boot] systemd=true`
- Use `usbipd` on Windows host for USB passthrough
- Same systemd services as Linux

## Complete Setup Flow (Single Command)

```bash
# 1. Copy script to host (MANDATORY - runs from USB check)
cp $USB_MOUNT/usb-setup-assistant.sh ~/usb-setup-assistant.sh
sudo bash ~/usb-setup-assistant.sh --dry-run  # Preview

# 2. Run Option 1: Complete System Setup
#    → Ventoy USB + Persistence
#    → VM Headless + SSH
#    → Hemlock Deployment (6 steps)
#    → Build Tools into Persistence
#    → Network Config (SSH, Tailscale, WireGuard → USB)
#    → Auto-Start Services

# 3. Plug in USB → Everything Auto-Starts
#    1. hemlock-usb-detect detects Ventoy
#    2. Starts hemlock-gateway (agents auto-attach)
#    3. Starts QEMU VM (headless, SSH 2222)
#    4. Ready to work in < 60 seconds

# 4. SSH into system
ssh -p 2222 user@localhost
# → Agents alpha/beta/gamma already attached
# → Gateway: http://localhost:18789
# → Hemlock TUI available (Option 13)
```

## Hemlock Integration Details

### Agent/Crew Model
- **Agents**: Isolated Docker volumes (`hemlock-agent-<id>`)
- **Crews**: Grouped agents with shared channel (`hemlock-crew-<name>`)
- **Skills**: Read-only shared volume (`hemlock-shared-skills` with 157+ skills)
- **MCP Bridge**: stdio-based `mcp_bridge.py` for each agent

### Gateway Interactive Menu (Option 13 → 5)
```bash
# Sub-menus:
1) Agents: Create, Attach, Configure (model/skills/MCP/resources), Export/Import
2) Crews: Create, Attach, Configure (channel/agents), Export/Import
3) Settings: Token, Telegram, iMessage, MCP servers, Ports, Plugins
4) Skills: List 157+, Copy to agent, Install, Update
5) Resources: Port mappings, CPU/Memory defaults, Persistence mode, Isolation
6) Backup: Full system, Agent/Crew export/import, Restore
```

### Per-Agent Configuration
```bash
# In gateway interactive menu → 1) Agents → 4) Configure agent
# Options:
1) Change model (claude-sonnet-4, gpt-4, etc.)
2) Configure MCP server (command + args)
3) Copy skills from shared-skills (157+)
4) Set resource limits (CPU, memory, pids_limit)
5) Environment variables (.env)
6) View full config (agent.json, config.yaml, .env)
```

## Container Isolation & Compute Resources

```bash
# Compute ports exposed (persistent environment only, NO host access)
CONTAINER_COMPUTE_PORTS=(
    "8888:8888"   # Jupyter
    "8080:8080"   # Web services
    "11434:11434" # Ollama API
    "8000:8000"   # Custom APIs
    "5000:5000"   # Flask/FastAPI
    "3000:3000"   # Node.js apps
)

# Isolation
--security-opt=no-new-privileges:true
--cap-drop=ALL
--cap-add=CAP_DAC_OVERRIDE    # Persistence access
--cap-add=CAP_SYS_RESOURCE    # Resource limits
--pids-limit=1000
--memory=4g
--cpus=2
```

**Key principle**: Containers have FULL compute access (CPU, RAM, GPU via passthrough) but CANNOT access host filesystem/network. Only persistence volume is mounted.

## Persistence Package Installation

Tools installed INTO USB persistence via chroot (NOT host):

```bash
# Mount persistence
mount -o loop $USB_MOUNT/persistence/ubuntu-persistence.dat /mnt/persist

# Prepare chroot
mount --bind /dev /mnt/persist/dev
mount --bind /proc /mnt/persist/proc
# ... sys, dev/pts, tmp, resolv.conf

# Install via apt/pip inside chroot
chroot /mnt/persist apt-get install -y build-essential python3 nodejs docker.io
chroot /mnt/persist pip3 install autogen crewai langchain

# Tools NOW persist across reboots, available via:
# - Direct boot from USB
# - VM boot (persistence auto-mounted)
# - chroot access: sudo chroot /mnt/persist /bin/bash
```

## USB Location Safety (CRITICAL)

**The setup script MUST run from HOST, never from USB:**

```bash
check_script_location() {
    local script_path="$(realpath "${BASH_SOURCE[0]}")"
    local usb_paths=(
        "/media/*/Ventoy" "/mnt/ventoy" "/Volumes/Ventoy"
        "/run/media/*/Ventoy" "/mnt/c/*/Ventoy"  # WSL2
    )
    # If script_path starts with any usb_path → BLOCK
    echo "COPY TO HOST FIRST: cp \"$script_path\" ~/usb-setup-assistant.sh"
    echo "sudo bash ~/usb-setup-assistant.sh"
}
```

## Verification Checklist

After complete setup, verify:

- [ ] Ventoy USB boots to Ubuntu with persistence
- [ ] `ssh -p 2222 user@localhost` works
- [ ] `curl http://localhost:18789/health` returns `{"ok":true}`
- [ ] `docker ps` shows `hemlock-runtime` running
- [ ] Agents alpha/beta/gamma attached: `docker exec hemlock-runtime /entrypoint.sh agent-list`
- [ ] Auto-start services enabled: `systemctl is-enabled hemlock-gateway hemlock-usb-detect`
- [ ] USB plug-in → VM + Hemlock auto-start (test by unplug/replug)
- [ ] Option 13 → 1) Launch TUI in popout terminal works
- [ ] Option 13 → 5) Gateway menu allows agent/crew config
- [ ] Network tools (Tailscale/WireGuard) installed in persistence, not host

## References

- [USB Location Safety](usb-location-safety.md)
- [Hemlock Integration](hemlock-integration.md)
- [Persistence Package Install](persistence-package-install.md)
- [Popout Terminal Launch](popout-terminal-launch.md)
- [Chroot Persistence Access](chroot-persistence-access.md)
- [Cross-OS Guide](cross-os-guide.md)
- [WSL2 Optimization](wsl2-optimization.md)
