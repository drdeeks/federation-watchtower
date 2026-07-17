# Alias System

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.
## Table of Contents

- [Installation](#installation)
- [Core Aliases](#core-aliases)
- [Custom Alias Creation](#custom-alias-creation)
- [Alias Groups](#alias-groups)
- [Troubleshooting Aliases](#troubleshooting-aliases)


Complete alias system for streamlined USB management.

## Installation

### Option 1: System-wide (all users)

```bash
sudo cp scripts/usb-aliases.sh /etc/profile.d/
sudo chmod +x /etc/profile.d/usb-aliases.sh
```

### Option 2: User-specific

```bash
cat scripts/usb-aliases.sh >> ~/.bashrc
source ~/.bashrc
```

## Core Aliases

### Device Management

```bash
# List all block devices with filesystems
alias usb-list='lsblk -f /dev/sd*'

# List only USB devices (removable)
alias usb-removable='lsblk -o NAME,SIZE,TYPE,TRAN,RM | grep disk | grep usb'

# Show detailed USB info
alias usb-info='lsblk -f /dev/sdX && sudo fdisk -l /dev/sdX'
```

### Mount/Unmount

```bash
# Mount USB Ventoy partition
alias usb-mount='sudo mount /dev/sdX1 /media/ventoy-usb'

# Unmount all USB partitions
alias usb-unmount='sudo umount /dev/sdX*'

# Mount with write access
alias usb-mount-rw='sudo mount -o rw /dev/sdX1 /media/ventoy-usb'
```

### ISO Management

```bash
# List ISOs on USB
alias usb-iso-list='ls -lh $USB_MOUNT/*.iso 2>/dev/null'

# Add ISO to USB
alias usb-iso-add='sudo cp'

# Remove ISO from USB
alias usb-iso-remove='sudo rm $USB_MOUNT/'

# Verify ISO integrity
alias usb-iso-verify='sha256sum -c $USB_MOUNT/SHA256SUMS 2>/dev/null'
```

### Persistence

```bash
# Check persistence configuration
alias usb-persist-check='cat $USB_MOUNT/ventoy/ventoy.json'

# Show persistence file info
alias usb-persist-info='file $USB_MOUNT/persistence/*.dat'

# Check persistence size
alias usb-persist-size='du -sh $USB_MOUNT/persistence/*.dat'
```

### VM Operations

```bash
# Boot USB in QEMU (no KVM)
alias usb-vm-boot='sudo qemu-system-x86_64 -m 4G -drive file=/dev/sdX,format=raw -boot c -display gtk'

# Boot USB in QEMU with KVM
alias usb-vm-boot-kvm='sudo qemu-system-x86_64 -enable-kvm -m 4G -cpu host -drive file=/dev/sdX,format=raw,if=virtio -boot c -vga virtio -display gtk'

# Boot USB headless with VNC
alias usb-vm-vnc='sudo qemu-system-x86_64 -m 4G -drive file=/dev/sdX,format=raw -boot c -display vnc=:1'

# Stop QEMU
alias usb-vm-stop='pkill qemu-system-x86'
```

### SSH Operations

```bash
# Connect to USB via SSH
alias usb-ssh='ssh user@usb-system.local'

# SSH with X11 forwarding
alias usb-ssh-x='ssh -X user@usb-system.local'

# SSH with port forwarding
alias usb-ssh-tunnel='ssh -L 8080:localhost:80 user@usb-system.local'
```

### Backup/Restore

```bash
# Full USB backup
alias usb-backup='sudo dd if=/dev/sdX of=~/usb-backup-$(date +%Y%m%d).img bs=4M status=progress'

# Full USB restore
alias usb-restore='sudo dd if=~/usb-backup.img of=/dev/sdX bs=4M status=progress'

# Backup persistence only
alias usb-backup-persist='sudo dd if=/dev/sdX5 of=~/persist-backup-$(date +%Y%m%d).dat bs=4M status=progress'

# Restore persistence only
alias usb-restore-persist='sudo dd if=~/persist-backup.dat of=/dev/sdX5 bs=4M status=progress'
```

### Agent Management

```bash
# List agents
alias usb-agent-list='ls -la $USB_MOUNT/agents/'

# Create agent
alias usb-agent-create='python3 scripts/agent-manager.py create'

# Enter agent workspace
alias usb-agent-enter='python3 scripts/agent-manager.py enter'

# Backup agent
alias usb-agent-backup='python3 scripts/agent-manager.py backup'
```

### Diagnostics

```bash
# Check USB health
alias usb-health='sudo smartctl -a /dev/sdX'

# Check for errors
alias usb-errors='sudo dmesg | grep -i sdX | tail -20'

# Monitor USB I/O
alias usb-monitor='iostat -x 1 5 /dev/sdX'

# Check Ventoy version
alias usb-ventoy-version='cat $USB_MOUNT/ventoy/ventoy.dat 2>/dev/null || echo "Unknown"'
```

## Custom Alias Creation

### Add New Alias

```bash
# Function to create aliases
usb-custom-alias() {
    local name="$1"
    local command="$2"
    local desc="$3"
    
    # Add to bashrc
    echo "# $desc" >> ~/.bashrc
    echo "alias $name='$command'" >> ~/.bashrc
    
    # Reload
    source ~/.bashrc
    
    echo "Alias '$name' created: $desc"
}

# Usage:
usb-custom-alias usb-dev 'cd /media/ventoy-usb && ls -la' "Navigate to USB and list files"
usb-custom-alias usb-ping 'ping -c 4 usb-system.local' "Ping USB system"
```

### Alias Configuration File

Create `~/.usb-aliases.conf`:

```bash
# ~/.usb-aliases.conf
# Device configuration
USB_DEVICE="/dev/sdb"
USB_MOUNT="/media/ventoy-usb"
USB_EFI_MOUNT="/media/ventoy-efi"

# ISO configuration
USB_DEFAULT_ISO="ubuntu-24.04.4-desktop-amd64.iso"
USB_ISO_DIR="/media/ventoy-usb"

# Persistence configuration
USB_PERSIST_SIZE="20G"
USB_PERSIST_FILE="ubuntu-persistence.dat"

# VM configuration
USB_QEMU_MEMORY="4G"
USB_QEMU_DISPLAY="gtk"
USB_QEMU_VGA="std"

# SSH configuration
USB_SSH_USER="drdeek"
USB_SSH_HOST="usb-system.local"
USB_SSH_KEY="~/.ssh/id_rsa"
USB_SSH_PORT="22"

# Agent configuration
USB_AGENT_PREFIX="agent"
USB_AGENT_SIZE="5G"
USB_AGENT_HOME="$USB_MOUNT/agents"

# Backup configuration
USB_BACKUP_DIR="~/usb-backups"
USB_BACKUP_KEEP="5"
```

### Loading Configuration

```bash
# Add to ~/.bashrc:
if [ -f ~/.usb-aliases.conf ]; then
    source ~/.usb-aliases.conf
fi
```

## Alias Groups

### Development Aliases

```bash
# Create development alias group
alias usb-dev-group='
    alias dev-build="cd /media/ventoy-usb && make build";
    alias dev-test="cd /media/ventoy-usb && make test";
    alias dev-deploy="cd /media/ventoy-usb && make deploy";
'
```

### Production Aliases

```bash
# Create production alias group
alias usb-prod-group='
    alias prod-status="ssh usb-system.local systemctl status";
    alias prod-logs="ssh usb-system.local journalctl -f";
    alias prod-restart="ssh usb-system.local sudo systemctl restart";
'
```

## Troubleshooting Aliases

### Alias Not Found

```bash
# Check if alias is defined:
alias | grep usb

# Reload shell:
source ~/.bashrc

# Check for syntax errors:
bash -n ~/.bashrc
```

### Alias Conflicts

```bash
# List all aliases:
alias | sort

# Remove conflicting alias:
unalias old-alias

# Check for duplicate definitions:
grep "alias usb-" ~/.bashrc | sort
```

### Performance

```bash
# Profile shell startup:
time zsh -i -c exit

# Check for slow aliases:
zprof | head -20

# Optimize by moving heavy aliases to lazy loading:
usb-lazy-alias() {
    local name="$1"
    local command="$2"
    
    eval "alias $name() {
        unalias $name
        $command
    }"
}
```
