#!/usr/bin/env bash
# =============================================================================
# USB Automount Uninstaller
# =============================================================================
# Removes the USB automount system
#
# Usage: sudo ./uninstall.sh
# =============================================================================

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; exit 1; }

# Check root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
fi

echo -e "${BLUE}"
echo "=========================================="
echo "  USB Automount Uninstaller"
echo "=========================================="
echo -e "${NC}"

# 1. Stop and disable systemd service
log "Stopping systemd service..."
systemctl stop usb-automount.service 2>/dev/null || true
systemctl disable usb-automount.service 2>/dev/null || true
log "Service stopped and disabled"

# 2. Remove systemd service file
log "Removing systemd service file..."
rm -f /etc/systemd/system/usb-automount.service
systemctl daemon-reload
log "Removed: /etc/systemd/system/usb-automount.service"

# 3. Unmount all USB devices
log "Unmounting all USB devices..."
/usr/local/bin/usb-mount.sh unmount-all 2>/dev/null || true

# 4. Remove udev rules
log "Removing udev rules..."
rm -f /etc/udev/rules.d/99-usb-automount.rules
udevadm control --reload-rules
udevadm trigger
log "Removed: /etc/udev/rules.d/99-usb-automount.rules"

# 5. Remove scripts
log "Removing scripts..."
rm -f /usr/local/bin/usb-mount.sh
log "Removed: /usr/local/bin/usb-mount.sh"

# 6. Optionally remove mount base (ask user)
echo ""
read -p "Remove mount base directory /mnt/usb? [y/N]: " response
if [[ "$response" =~ ^[Yy]$ ]]; then
    rm -rf /mnt/usb/*
    rmdir /mnt/usb 2>/dev/null || true
    log "Removed: /mnt/usb"
else
    warn "Keeping: /mnt/usb"
fi

echo ""
echo -e "${GREEN}=========================================="
echo "  Uninstallation Complete!"
echo "==========================================${NC}"
echo ""
echo "The USB automount system has been removed."
echo "USB devices will now use default udisks2 behavior."
