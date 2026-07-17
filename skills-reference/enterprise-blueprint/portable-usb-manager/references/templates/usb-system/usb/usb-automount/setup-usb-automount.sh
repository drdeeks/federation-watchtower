#!/usr/bin/env bash
# =============================================================================
# USB Automount Installer
# =============================================================================
# Installs the USB automount system:
# - Copies scripts to /usr/local/bin/
# - Installs udev rules
# - Installs systemd service
# - Creates mount base directory
#
# Usage: sudo ./install.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOUNT_BASE="/mnt/usb"

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
echo "  USB Automount Installer"
echo "=========================================="
echo -e "${NC}"

# 1. Install usb-mount.sh
log "Installing usb-mount.sh to /usr/local/bin/..."
cp "$SCRIPT_DIR/usb-mount.sh" /usr/local/bin/usb-mount.sh
chmod +x /usr/local/bin/usb-mount.sh
log "Installed: /usr/local/bin/usb-mount.sh"

# 2. Install udev rules
log "Installing udev rules..."
cp "$SCRIPT_DIR/udev-usb-automount.rules" /etc/udev/rules.d/99-usb-automount.rules
chmod 644 /etc/udev/rules.d/99-usb-automount.rules
log "Installed: /etc/udev/rules.d/99-usb-automount.rules"

# 3. Reload udev rules
log "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger
log "Udev rules reloaded"

# 4. Create mount base directory
log "Creating mount base directory: $MOUNT_BASE..."
mkdir -p "$MOUNT_BASE"
chmod 755 "$MOUNT_BASE"
log "Created: $MOUNT_BASE"

# 5. Create log file
log "Creating log file..."
touch /var/log/usb-mount.log
chmod 644 /var/log/usb-mount.log
log "Created: /var/log/usb-mount.log"

# 6. Install systemd service
log "Installing systemd service..."
cp "$SCRIPT_DIR/usb-automount.service" /etc/systemd/system/usb-automount.service
chmod 644 /etc/systemd/system/usb-automount.service
systemctl daemon-reload
systemctl enable usb-automount.service
log "Installed and enabled: usb-automount.service"

# 7. Mount current USB devices
log "Mounting current USB devices..."
/usr/local/bin/usb-mount.sh mount-all

echo ""
echo -e "${GREEN}=========================================="
echo "  Installation Complete!"
echo "==========================================${NC}"
echo ""
echo "USB devices will now automatically mount to:"
echo "  $MOUNT_BASE/<device-name>/"
echo ""
echo "Commands:"
echo "  usb-mount.sh list              List mounted devices"
echo "  usb-mount.sh add <device>      Mount a device"
echo "  usb-mount.sh remove <device>   Unmount a device"
echo "  usb-mount.sh mount-all         Mount all devices"
echo "  usb-mount.sh unmount-all       Unmount all devices"
echo "  usb-mount.sh status            Show status"
echo ""
echo "Logs: /var/log/usb-mount.log"
echo ""
echo "To uninstall:"
echo "  sudo ./uninstall.sh"
