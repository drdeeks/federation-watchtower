#!/usr/bin/env bash
# Access USB Persistence Terminal (Chroot into persistence image)
# Usage: bash access-persistence-terminal.sh <usb-device>

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