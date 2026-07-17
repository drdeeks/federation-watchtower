# Chroot Persistence Access

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.

## Overview

Direct terminal access to the USB persistence environment via chroot. This provides a full shell inside the USB persistence image without booting a VM or starting the Hemlock container.

## When to Use

- **Test packages** without booting VM
- **Quick debugging** and configuration changes
- **Install additional packages** via apt/pip
- **Verify installed tools** work correctly
- **Emergency recovery** when VM won't boot

## Access Methods

### Method 1: USB Setup Assistant (Option 11)

```bash
# From USB Setup Assistant Main Menu
# Select: 11) Access USB Persistent Terminal (chroot into USB persistence)

# This opens a chroot shell with:
# - Prompt shows [USB-PERSIST] indicator
# - Full access to installed tools
# - Type 'exit' or Ctrl+D to return to host
```

### Method 2: Manual Chroot (Advanced)

```bash
# Mount Ventoy partition
sudo mount /dev/sdX1 /media/ventoy-usb

# Mount persistence image
PERSIST_FILE="$USB_MOUNT/persistence/ubuntu-persistence.dat"
PERSIST_MNT="/tmp/usb-persist-$$"
mkdir -p "$PERSIST_MNT"
sudo mount -o loop "$PERSIST_FILE" "$PERSIST_MNT"

# Prepare chroot environment
sudo mount --bind /dev "$PERSIST_MNT/dev"
sudo mount --bind /proc "$PERSIST_MNT/proc"
sudo mount --bind /sys "$PERSIST_MNT/sys"
sudo mount --bind /dev/pts "$PERSIST_MNT/dev/pts"
sudo mount --bind /tmp "$PERSIST_MNT/tmp"
sudo cp /etc/resolv.conf "$PERSIST_MNT/etc/resolv.conf"

# Set prompt indicator
echo "USB_PERSISTENCE=1" | sudo tee "$PERSIST_MNT/etc/environment.usb" >/dev/null
cat | sudo tee "$PERSIST_MNT/etc/profile.d/usb-prompt.sh" >/dev/null << 'EOF'
# USB Persistence Terminal Prompt
if [[ -n "$USB_PERSISTENCE" ]] || [[ "$(cat /etc/environment.usb 2>/dev/null)" == *"USB_PERSISTENCE=1"* ]]; then
    export PS1="\[\033[1;35m\][USB-PERSIST]\[\033[0m\] \[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ "
fi
EOF

# Enter chroot
sudo chroot "$PERSIST_MNT" /bin/bash --login

# Cleanup on exit
sudo umount "$PERSIST_MNT/dev/pts" "$PERSIST_MNT/dev" "$PERSIST_MNT/proc" "$PERSIST_MNT/sys" "$PERSIST_MNT"
sudo umount "$PERSIST_MNT"
rmdir "$PERSIST_MNT"
```

## Template Script

```bash
# templates/access-persistence-terminal.sh
#!/usr/bin/env bash
# Access USB Persistence Terminal (Chroot into persistence image)

set -euo pipefail

USB_DEVICE="${1:-}"
if [[ -z "$USB_DEVICE" ]]; then
    echo "Usage: $0 <usb-device> (e.g., /dev/sdX)"
    exit 1
fi

# Detect OS
if [[ "$(uname)" == "Darwin" ]]; then
    PART="${USB_DEVICE}s1"
else
    PART="${USB_DEVICE}1"
fi

# Mount Ventoy partition
VENTOY_MOUNT="/mnt/ventoy-chroot-$$"
mkdir -p "$VENTOY_MOUNT"
if ! mount "$PART" "$VENTOY_MOUNT"; then
    echo "Failed to mount Ventoy partition: $PART"
    exit 1
fi

PERSIST_FILE="$VENTOY_MOUNT/persistence/ubuntu-persistence.dat"
if [[ ! -f "$PERSIST_FILE" ]]; then
    echo "No persistence file found: $PERSIST_FILE"
    umount "$VENTOY_MOUNT"
    rmdir "$VENTOY_MOUNT"
    exit 1
fi

# Mount persistence image
PERSIST_MNT="/tmp/usb-persist-$$"
mkdir -p "$PERSIST_MNT"
mount -o loop "$PERSIST_FILE" "$PERSIST_MNT"

# Prepare chroot
mount --bind /dev "$PERSIST_MNT/dev"
mount --bind /proc "$PERSIST_MNT/proc"
mount --bind /sys "$PERSIST_MNT/sys"
mount --bind /dev/pts "$PERSIST_MNT/dev/pts"
mount --bind /tmp "$PERSIST_MNT/tmp"
cp /etc/resolv.conf "$PERSIST_MNT/etc/resolv.conf"

# Set prompt
echo "USB_PERSISTENCE=1" > "$PERSIST_MNT/etc/environment.usb"
cat > "$PERSIST_MNT/etc/profile.d/usb-prompt.sh" << 'EOF'
if [[ -n "$USB_PERSISTENCE" ]] || [[ "$(cat /etc/environment.usb 2>/dev/null)" == *"USB_PERSISTENCE=1"* ]]; then
    export PS1="\[\033[1;35m\][USB-PERSIST]\[\033[0m\] \[\033[1;32m\]\u@\h\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ "
fi
EOF

echo "Entering USB persistent terminal..."
echo "Prompt shows [USB-PERSIST] indicator"
echo "Type 'exit' or Ctrl+D to return to host"
echo ""

chroot "$PERSIST_MNT" /bin/bash --login

# Cleanup
umount "$PERSIST_MNT/dev/pts" "$PERSIST_MNT/dev" "$PERSIST_MNT/proc" "$PERSIST_MNT/sys" "$PERSIST_MNT"
umount "$PERSIST_MNT"
rmdir "$PERSIST_MNT"
umount "$VENTOY_MOUNT"
rmdir "$VENTOY_MOUNT"
```

## Usage

### From USB Setup Assistant (Recommended)

```bash
# Option 11 from main menu
sudo bash ~/usb-setup-assistant.sh
# Select: 11) Access USB Persistent Terminal (chroot into USB persistence)
```

### Direct Usage

```bash
# Using template
sudo bash templates/access-persistence-terminal.sh /dev/sdX

# Or if USB already selected in assistant
# The assistant tracks SELECTED_DEVICE and uses it automatically
```

## What You Can Do Inside Chroot

| Task | Command |
|---|---|
| Install packages | `apt-get update && apt-get install -y <package>` |
| Install Python packages | `pip3 install <package>` |
| Check installed tools | `which python3 node gcc docker` |
| Edit config files | `vim /etc/ssh/sshd_config` |
| Test services | `systemctl status ssh` (limited in chroot) |
| Verify persistence | `ls -la /home/` |
| Check disk usage | `df -h` |

## Prompt Indicator

The chroot session shows a distinctive prompt:

```
[USB-PERSIST] user@host:/path$
```

This clearly indicates you're inside the USB persistence environment.

## Limitations

| Limitation | Workaround |
|---|---|
| No systemd services | Use VM (Option 3) or container (Option 13) |
| No kernel modules | Use VM for kernel testing |
| Network limited | Use host network via bind mounts |
| GUI apps won't work | Use VM with display forwarding |
| Some systemctl commands fail | Use service commands or VM |

## Cleanup

Always exit cleanly with `exit` or `Ctrl+D`:

```bash
# On exit, script automatically:
# 1. Unmounts /dev/pts, /dev, /proc, /sys, /tmp
# 2. Unmounts persistence image
# 3. Unmounts Ventoy partition
# 4. Removes temp directories
```

## Template

```bash
# templates/access-persistence-terminal.sh
# See full script above
```

## Integration with USB Setup Assistant

The access is integrated as **Option 11** in the main menu:

```
  11) Access USB Persistent Terminal (chroot into USB persistence)
```

This provides immediate, direct access without booting the VM or starting Hemlock container.

## Best Practices

1. **Always exit cleanly** with `exit` or `Ctrl+D` - don't kill the terminal
2. **Use for quick tasks** - package installs, config edits, verification
3. **Use VM/Container for services** - systemd, networking, daemons
4. **Backup before major changes** - Option 7 (Backup) in main menu
5. **Verify after changes** - re-enter chroot to confirm
