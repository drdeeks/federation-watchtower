# WSL2 Optimizations for Hemlock USB Compute

## Overview

WSL2 provides the best Windows experience for Hemlock USB Compute with full Linux kernel, systemd support, and native Docker. This guide covers optimizations specific to WSL2 environments.

## Prerequisites

### Windows Host Setup

```powershell
# Install usbipd for USB passthrough
winget install usbipd

# Enable WSL2 with systemd
wsl --update
wsl --set-default-version 2
```

### WSL2 Configuration

```bash
# /etc/wsl.conf (inside WSL2)
[boot]
systemd=true

[network]
generateResolvConf=false
```

```bash
# Apply and restart
wsl --shutdown
wsl.exe -d <DISTRO>
```

## USB Passthrough with usbipd

### Windows Host (PowerShell Admin)

```powershell
# List USB devices
usbipd list

# Bind the USB device (replace <BUSID> with actual ID)
usbipd bind --busid <BUSID>

# Attach to WSL2
usbipd attach --wsl --busid <BUSID>

# Or auto-attach on boot
usbipd attach --wsl --auto --busid <BUSID>
```

### WSL2 Side

```bash
# Inside WSL2 - verify device appears
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL | grep -i usb

# If using usbipd attach, device should appear automatically
# For manual attach:
sudo usbipd attach --remote $WSL_HOST_IP --busid <BUSID>
```

## Ventoy in WSL2

### Mounting Ventoy USB

```bash
# After usbipd attach, device appears as /dev/sdX
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL | grep -i ventoy

# Mount Ventoy partition
sudo mkdir -p /mnt/ventoy
sudo mount /dev/sdX1 /mnt/ventoy

# Verify
ls /mnt/ventoy/
```

### Running Ventoy Tools in WSL2

```bash
# Ventoy2Disk.sh works in WSL2
cd /tmp/ventoy-*
sudo ./Ventoy2Disk.sh -i /dev/sdX

# Persistence setup works identically
sudo mkdir -p /mnt/ventoy/persistence
sudo dd if=/dev/zero of=/mnt/ventoy/persistence/ubuntu-persistence.dat bs=1M count=20000
sudo mkfs.ext4 -F -L casper-rw /mnt/ventoy/persistence/ubuntu-persistence.dat
```

## Hemlock Deployment in WSL2

### Docker in WSL2

```bash
# Native Docker Engine (no Docker Desktop needed)
sudo apt update && sudo apt install -y docker.io
sudo usermod -aG docker $USER
newgrp docker

# Verify
docker run --rm hello-world
```

### Hemlock Deployment

```bash
# Deploy Hemlock container
cd /path/to/hemlock-minimal
docker build -f Dockerfile.runtime -t hemlock-runtime .

# Create volumes
for vol in hemlock-gateway hemlock-agents hemlock-crews hemlock-shared-skills hemlock-models; do
    docker volume create $vol
done

# Start with WSL2-appropriate port forwarding
docker run -d \
    --name hemlock-runtime \
    --restart unless-stopped \
    -p 18789:18789 \
    -p 41214:41214 \
    -p 8080:8080 \
    -p 8888:8888 \
    -v hemlock-gateway:/workspace/gateway \
    -v hemlock-agents:/agents \
    -v hemlock-crews:/crews \
    -v hemlock-shared-skills:/skills:ro \
    -v hemlock-models:/models \
    hemlock-runtime gateway
```

### Auto-Start Services in WSL2

```bash
# Create systemd service (WSL2 supports systemd)
sudo tee /etc/systemd/system/hemlock-gateway.service <<'EOF'
[Unit]
Description=Hemlock Agent Orchestration Gateway
After=docker.service network.target
Requires=docker.service
Restart=always
RestartSec=10

[Service]
Type=simple
ExecStart=/usr/bin/docker start -a hemlock-runtime
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable hemlock-gateway
sudo systemctl start hemlock-gateway
```

```bash
# USB detection service
sudo tee /etc/systemd/system/hemlock-usb-detect.service <<'EOF'
[Unit]
Description=Hemlock USB Detection and Auto-Start
After=hemlock-gateway.service
Requires=hemlock-gateway.service

[Service]
Type=simple
ExecStart=/path/to/hemlock-minimal/scripts/usb-detector.sh
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable hemlock-usb-detect
sudo systemctl start hemlock-usb-detect
```

## Ventoy USB Auto-Mount in WSL2

### udev Rules

```bash
# /etc/udev/rules.d/99-ventoy-automount.rules
ACTION=="add", KERNEL=="sd*[0-9]", ENV{ID_FS_LABEL}=="Ventoy", RUN+="/usr/local/bin/ventoy-mount.sh %k"
```

```bash
# /usr/local/bin/ventoy-mount.sh
#!/bin/bash
DEV="/dev/$1"
MOUNT_POINT="/mnt/ventoy-usb"

mkdir -p "$MOUNT_POINT"
if mount "$DEV" "$MOUNT_POINT" 2>/dev/null; then
    logger "Ventoy USB mounted at $MOUNT_POINT"
    # Trigger Hemlock USB detection
    systemctl reload hemlock-usb-detect 2>/dev/null || true
fi
```

```bash
sudo chmod +x /usr/local/bin/ventoy-mount.sh
sudo udevadm control --reload-rules
sudo udevadm trigger
```

## Hardware Acceleration in WSL2

### GPU Passthrough for llama.cpp

```bash
# Check GPU availability in WSL2
lspci | grep -i nvidia
lspci | grep -i amd

# NVIDIA GPU (requires Windows host with NVIDIA driver + WSL2 GPU support)
docker run --rm --gpus all nvidia/cuda:12.4-base nvidia-smi

# Build llama.cpp with CUDA in WSL2
# Dockerfile automatically detects CUDA in WSL2
```

### CPU Optimization

```bash
# Check CPU capabilities
lscpu | grep -E "flags|Model name"

# llama.cpp build uses all cores
make -j$(nproc)
```

## Network Configuration

### Port Forwarding in WSL2

```bash
# WSL2 uses separate network namespace
# Ports forwarded from Windows host to WSL2 automatically for systemd services
# For direct access, use:
# Windows host: localhost:18789 -> WSL2:18789

# For external access, configure Windows Firewall
netsh advfirewall firewall add rule name="Hemlock Gateway" dir=in action=allow protocol=TCP localport=18789
```

### SSH Access

```bash
# From Windows host to WSL2 VM
ssh -p 2222 user@localhost

# From external machine to Windows host
ssh -p 2222 user@<WINDOWS_HOST_IP>
```

## USB Auto-Detection in WSL2

### usb-detector.sh for WSL2

```bash
#!/usr/bin/env bash
# /path/to/hemlock-minimal/scripts/usb-detector.sh

LOG_FILE="/tmp/hemlock-usb-detect-$(date +%Y%m%d).log"
VENTOY_LABEL="Ventoy"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

is_ventoy_connected() {
    if blkid -l 2>/dev/null | grep -q "$VENTOY_LABEL"; then
        return 0
    fi
    return 1
}

start_hemlock_if_needed() {
    if docker ps --format '{{.Names}}' | grep -q "^hemlock-runtime$"; then
        log "Hemlock already running"
        return 0
    fi
    
    log "Starting Hemlock gateway..."
    systemctl is-active --quiet hemlock-gateway.service || systemctl start hemlock-gateway.service
}

start_vm_if_usb() {
    if is_ventoy_connected; then
        log "Ventoy USB detected"
        start_hemlock_if_needed
        
        # Start QEMU VM if not running
        if ! pgrep -q "qemu"; then
            log "Starting QEMU VM..."
            if [[ -f "${USB_AUTOMATION_DIR:-$HOME/usb-compute-automation}/scripts/start-usb-vm.sh" ]]; then
                bash "${USB_AUTOMATION_DIR:-$HOME/usb-compute-automation}/scripts/start-usb-vm.sh" >> "$LOG_FILE" 2>&1 &
            fi
        fi
    else
        log "Ventoy USB not connected"
    fi
}

log "Hemlock USB Detector started (WSL2)"

while true; do
    start_vm_if_usb
    sleep 10
done
```

## Performance Tips

### Disk I/O

```bash
# Use native Linux filesystem for best performance
# Avoid /mnt/c/ paths for heavy I/O
# Use /home/ or /opt/ for workspace

# For USB persistence:
# - Use ext4 on USB (better than exFAT for Linux workloads)
# - Enable write-back caching: mount -o remount,rw,noatime /mnt/usb
```

### Memory

```bash
# WSL2 memory limit (in .wslconfig on Windows)
[wsl2]
memory=8GB
processors=4
swap=2GB
```

### Compilation

```bash
# Use all cores for llama.cpp build
export MAKEFLAGS="-j$(nproc)"

# Pre-built binaries available in Docker image
# No need to recompile unless hardware changes
```

## Troubleshooting

### USB Not Detected

```bash
# Check usbipd status
usbipd list

# Re-attach
usbipd detach --busid <BUSID>
usbipd attach --wsl --busid <BUSID>

# Check WSL2 sees device
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL
```

### Docker Not Working

```bash
# Restart Docker in WSL2
sudo systemctl restart docker

# Or use Docker Desktop with WSL2 integration enabled
```

### Systemd Not Working

```bash
# Check systemd status
systemctl is-system-running

# Re-enable systemd
echo -e "[boot]\nsystemd=true" | sudo tee /etc/wsl.conf
wsl --shutdown
# Restart WSL2 from Windows
```

### USB Passthrough Issues

```bash
# Reset usbipd
usbipd unbind --busid <BUSID>
usbipd bind --busid <BUSID>
usbipd attach --wsl --busid <BUSID>

# Check Windows Event Viewer for usbipd errors
```

## Quick Reference

| Task | Command |
|---|---|
| List USB devices | `lsblk -o NAME,SIZE,TYPE,TRAN,MODEL | grep -i usb` |
| Mount Ventoy | `sudo mount /dev/sdX1 /mnt/ventoy` |
| Start Hemlock | `docker start hemlock-runtime` |
| Check Hemlock | `curl http://localhost:18789/health` |
| SSH to VM | `ssh -p 2222 user@localhost` |
| Model management | `hemlock model-list` |
| TUI | `hemlock tui` |
| View logs | `docker logs hemlock-runtime -f` |
| Restart services | `sudo systemctl restart hemlock-gateway hemlock-usb-detect` |