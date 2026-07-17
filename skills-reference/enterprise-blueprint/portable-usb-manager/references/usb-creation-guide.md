# USB Creation Guide

## Overview

Complete workflow for creating a bootable Ventoy USB with persistence for Hemlock Agent Orchestration.

## Prerequisites

- USB drive (16GB minimum, 32GB+ recommended for models)
- Ubuntu 24.04.4 LTS ISO (or compatible)
- Root/sudo access
- Internet connection for downloads

## Quick Start (Automated)

```bash
# From USB Setup Assistant
sudo bash ~/usb-setup-assistant.sh
# Select Option 1: Complete System Setup
```

## Manual Step-by-Step

### Step 1: Preparation

```bash
# 1. Identify USB device
lsblk -f

# 2. Download Ubuntu ISO
wget https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-desktop-amd64.iso

# 3. Verify ISO integrity
sha256sum -c SHA256SUMS 2>/dev/null | grep ubuntu-24.04.4-desktop-amd64.iso
```

### Step 2: Install Ventoy

```bash
# 1. Download Ventoy
wget https://github.com/ventoy/Ventoy/releases/download/v1.0.99/ventoy-1.0.99-linux.tar.gz
tar -xf ventoy-1.0.99-linux.tar.gz -C /tmp

# 2. Install to USB (WARNING: wipes drive)
cd /tmp/ventoy-1.0.99 && sudo ./Ventoy2Disk.sh -i /dev/sdX

# 3. Verify installation
sudo blkid /dev/sdX1 | grep Ventoy
```

### Step 3: Configure Persistence

```bash
# 1. Mount Ventoy partition
sudo mount /dev/sdX1 /mnt/ventoy

# 2. Copy ISO
sudo cp ~/ubuntu-24.04.4-desktop-amd64.iso /mnt/ventoy/

# 3. Create persistence file (20GB default)
sudo mkdir -p /mnt/ventoy/persistence
sudo dd if=/dev/zero of=/mnt/ventoy/persistence/ubuntu-persistence.dat bs=1M count=20000 status=progress
sudo mkfs.ext4 -F -L casper-rw /mnt/ventoy/persistence/ubuntu-persistence.dat

# 4. Configure Ventoy
sudo tee /mnt/ventoy/ventoy/ventoy.json > /dev/null << 'EOF'
{
    "persistence": [{
        "image": "/ubuntu-24.04.4-desktop-amd64.iso",
        "backend": "/persistence/ubuntu-persistence.dat"
    }]
}
EOF

sudo umount /mnt/ventoy
```

### Step 4: Install Build Essentials (Optional)

```bash
# Option 4 in USB Setup Assistant
sudo bash ~/usb-setup-assistant.sh
# Select Option 4: Install Build Essentials and Dependencies
# Choose components: [A] All recommended
```

### Step 5: Deploy Hemlock

```bash
# Option 13 in USB Setup Assistant
# Select: 13) Hemlock Agent Orchestration
# → Deploy Hemlock now? Yes
```

### Step 6: Configure Auto-Start

```bash
# Option 1 → Complete System Setup includes:
# → Auto-start services configured automatically
# → Systemd service (Linux) or LaunchAgent (macOS)
```

## USB Layout

```
/dev/sdX
├── sdX1  exfat   Ventoy        (ISO + config)
│   ├── ubuntu-24.04.4-desktop-amd64.iso
│   ├── ventoy/ventoy.json
│   ├── persistence/ubuntu-persistence.dat  (ext4, casper-rw)
│   └── agents/                              (agent workspaces)
│       ├── alpha-home.dat
│       ├── beta-home.dat
│       └── gamma-home.dat
└── sdX2  vfat    VTOYEFI       (EFI boot)
```

## Persistence Size Guidelines

| Use Case | Recommended Size |
|---|---|
| Minimal (base tools only) | 8-10 GB |
| Development (tools + containers) | 20-30 GB |
| AI/ML (models + tools) | 40-60 GB |
| Full (everything) | 80+ GB |

## Verification

```bash
# 1. Boot from USB on target machine
# 2. Verify persistence works
# 3. Test reboot and data retention
# 4. SSH into VM: ssh -p 2222 user@localhost

# Check Hemlock
curl http://localhost:18789/health

# List models
hemlock model-list

# TUI
hemlock tui
```

## Troubleshooting

| Issue | Solution |
|---|---|
| USB not detected | `sudo partprobe` or unplug/replug |
| Ventoy tools fail | `sudo cp /tmp/ventoy-*/tool/x86_64/* /usr/sbin/` |
| Black screen QEMU | Use `-vga std` instead of `-vga virtio` |
| No persistence | Verify `casper-rw` label and `persistent` boot option |
| Windows can't read | Create ExFAT exchange partition |
| KVM unavailable | Use QEMU without `-enable-kvm` |

## Advanced: Multi-Agent Layout

```bash
# Create additional agent workspaces
hemlock agent-create delta
hemlock agent-create epsilon

# Create crew
hemlock crew-create research delta epsilon

# Export agent
hemlock agent-export alpha STANDARD ./backups/

# Import agent
hemlock agent-import ./backups/alpha-STANDARD-20240614.tar.gz alpha-restored
```

## Maintenance

### Backup Persistence

```bash
# Option 7 in USB Setup Assistant
# 1) Backup persistence file
# → Creates ~/usb-backups/ubuntu-persistence-YYYYMMDD-HHMMSS.dat
```

### Update Ventoy

```bash
# Option 2 → 10) Ventoy upgrade (preserves ISOs)
```

### Update Skills

```bash
# From host
hemlock populate-skills

# Or inside container
hemlock tui
# → Skills → Update all skills
```

### Update llama.cpp

```bash
# Inside container
docker exec -it hemlock-runtime /scripts/model-manager.sh optimize
# → 6) Build/Update llama.cpp (hardware-aware)
```

## Resources

- Ventoy: https://www.ventoy.net
- Ubuntu ISO: https://ubuntu.com/download
- Hemlock: https://github.com/nousresearch/hermes-agent
- llama.cpp: https://github.com/ggerganov/llama.cpp
- Ollama: https://ollama.com