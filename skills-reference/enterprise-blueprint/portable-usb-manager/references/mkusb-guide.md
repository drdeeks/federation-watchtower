# mkusb Live/Persistent USB Creation Guide
## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Installation](#installation)
- [Usage via USB Manager](#usage-via-usb-manager)
- [Creating a Live USB](#creating-a-live-usb)
- [Creating a Persistent USB](#creating-a-persistent-usb)
- [Supported Linux Distributions](#supported-linux-distributions)
- [Comparing Live vs Persistent](#comparing-live-vs-persistent)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [References](#references)


## Overview

mkusb (Make USB Bootable) is a tool for creating bootable USB drives from ISO images. It supports both live USB (read-only) and persistent USB (with storage for saving files and settings).

## Key Features

- **Live USB Creation**: Write ISO images directly to USB
- **Persistent Storage**: Create overlays for saving data between sessions
- **Multi-Distro Support**: Works with most Linux distribution ISOs
- **Safe Operations**: Built-in safety checks and confirmations
- **Automatic Dependency Installation**: Installs required packages

## Installation

```bash
# Ubuntu/Debian
sudo apt install mkusb

# Or use USB Manager's auto-install
sudo bash scripts/usb-manager.sh
# Select mkusb option - will prompt to install if missing
```

## Usage via USB Manager

### Interactive Mode
```bash
sudo bash scripts/usb-manager.sh
# Select device -> option m (Create live USB) or p (Create persistent USB)
```

### CLI Mode
```bash
# Create live USB
sudo bash scripts/usb-manager.sh --mkusb-live

# Create persistent USB
sudo bash scripts/usb-manager.sh --mkusb-persistent
```

## Creating a Live USB

### What is a Live USB?
A live USB boots into a complete Linux environment without installation. Changes are lost on reboot.

### Process
1. Select source ISO file
2. Select target USB device
3. Choose "Live USB" mode
4. Confirm data destruction warning
5. Wait for write completion

### Boot Instructions
1. Insert USB into target computer
2. Restart and enter BIOS/UEFI (F2, F12, or Del)
3. Select USB as boot device
4. Boot into live environment

## Creating a Persistent USB

### What is Persistent Storage?
A persistent USB saves files, settings, and installed software between sessions. Data survives reboots.

### Persistence Size Options
| Size | Use Case |
|------|----------|
| 1 GB | Minimal saves (documents, config files) |
| 4 GB | Documents, settings, and small applications |
| Full Space | Complete workspace with large applications |

### Process
1. Select source ISO file
2. Select target USB device
3. Choose "Persistent USB" mode
4. Select persistence size
5. Confirm data destruction warning
6. Wait for creation completion

## Supported Linux Distributions

| Distribution | Live | Persistent | Notes |
|--------------|------|------------|-------|
| Ubuntu | ✓ | ✓ | Full support |
| Fedora | ✓ | ✓ | Full support |
| Debian | ✓ | ✓ | Full support |
| Linux Mint | ✓ | ✓ | Full support |
| Manjaro | ✓ | ✓ | Full support |
| Arch Linux | ✓ | ✓ | Manual configuration |
| Kali Linux | ✓ | ✓ | Full support |
| openSUSE | ✓ | ✓ | Full support |

## Comparing Live vs Persistent

| Feature | Live USB | Persistent USB |
|---------|----------|----------------|
| Boot speed | Fast | Fast |
| Storage | Read-only | Writable |
| Data persistence | None | Full |
| Software installation | Temporary | Permanent |
| File changes | Lost on reboot | Saved |
| Recommended use | Testing, rescue | Daily use, development |

## Troubleshooting

| Issue | Solution |
|-------|----------|
| USB not detected | Check connection, try different port, verify `lsblk` output |
| ISO not found | Verify file path, check ISO integrity (md5sum/sha256sum) |
| Write fails | Ensure device is unmounted, check write protection |
| Boot fails | Try different USB port, check BIOS boot order |
| Persistence not working | Verify persistence size, check overlay creation |

## Advanced Usage

### Manual dd Method (Fallback)
If mkusb is unavailable, use `dd` directly:
```bash
# WARNING: This destroys all data on the device
sudo dd if=/path/to/image.iso of=/dev/sdX bs=4M status=progress conv=fsync
```

### Creating Persistence Manually
```bash
# Partition layout for persistent USB
# 1: Boot partition (FAT32)
# 2: Root filesystem (ext4)
# 3: Persistence overlay (ext4)

# Create partitions
sudo fdisk /dev/sdX
# Create partitions as needed

# Format partitions
sudo mkfs.vfat -F 32 /dev/sdX1
sudo mkfs.ext4 -L casper-rw /dev/sdX2

# Mount and extract ISO
sudo mount /dev/sdX2 /mnt
sudo bsdtar -xf /path/to/image.iso -C /mnt

# Configure persistence
echo "/ union" | sudo tee /mnt/persistence.conf
```

## References

- mkusb Documentation: https://help.ubuntu.com/community/mkusb
- Ubuntu Live USB: https://ubuntu.com/tutorials/tutorial-create-a-usb-stick
- Persistent Storage: https://help.ubuntu.com/community/LiveCDPersistence
