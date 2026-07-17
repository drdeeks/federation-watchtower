# Ventoy Multi-ISO Boot Setup Guide
## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Supported ISO Types](#supported-iso-types)
- [Installation via USB Manager](#installation-via-usb-manager)
- [Manual Ventoy Setup](#manual-ventoy-setup)
- [Ventoy Configuration](#ventoy-configuration)
- [Updating Ventoy](#updating-ventoy)
- [Troubleshooting](#troubleshooting)
- [References](#references)


## Overview

Ventoy is an open-source tool that creates bootable USB drives for ISO/WIM/IMG/VHD(x)/EFI files. With Ventoy, you can copy multiple ISO files to a single USB drive and boot any of them directly without reformatting.

## Key Features

- **Multi-ISO Support**: Boot multiple ISO files from one USB drive
- **No Extraction Needed**: ISO files boot directly without extraction
- **Persistent Storage**: Optional persistence partition for saving data
- **Secure Boot Support**: Works with UEFI Secure Boot
- **Wide Compatibility**: Supports Linux, Windows, and utility ISOs

## Supported ISO Types

| Category | Examples |
|----------|----------|
| **Linux** | Ubuntu, Fedora, Debian, Arch, Mint, openSUSE, Manjaro, Kali |
| **Windows** | Windows 10, 11, Server 2019/2022 installers |
| **Utilities** | GParted, Clonezilla, Hiren's, MemTest86, SystemRescue |
| **BSD** | FreeBSD, OpenBSD, NetBSD |

## Installation via USB Manager

### Interactive Mode
```bash
sudo bash scripts/usb-manager.sh
# Select device -> option v (Setup Ventoy)
```

### CLI Mode
```bash
# Set up Ventoy on a device
sudo bash scripts/usb-manager.sh --ventoy-setup

# List ISOs on existing Ventoy drive
sudo bash scripts/usb-manager.sh --ventoy-list
```

## Manual Ventoy Setup

### Prerequisites
- USB drive (8GB or larger recommended)
- Root/sudo access
- Internet connection (for Ventoy download)

### Step-by-Step Process

1. **Download Ventoy**
   ```bash
   VENTOY_VERSION="1.0.99"
   wget "https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
   tar -xzf ventoy-*.tar.gz
   ```

2. **Install to USB**
   ```bash
   sudo ./Ventoy2Disk.sh -i /dev/sdX
   ```
   Replace `/dev/sdX` with your USB device.

3. **Copy ISO Files**
   ```bash
   sudo mount /dev/sdX1 /mnt/usb
   cp /path/to/*.iso /mnt/usb/
   sudo umount /mnt/usb
   ```

4. **Boot from USB**
   - Insert USB into target computer
   - Restart and enter BIOS/UEFI (usually F2, F12, or Del)
   - Select USB as boot device
   - Choose ISO from Ventoy menu

## Ventoy Configuration

### persistence.dat
For persistent storage across reboots:
```bash
# Create persistence file
dd if=/dev/zero of=persistence.dat bs=1M count=4096
mkfs.ext4 -F persistence.dat
```
Place `persistence.dat` in the Ventoy partition root.

### ventoy.json
Custom configuration file for advanced options:
```json
{
    "boot": {
        "themes": ["ventoy"],
        "menu_style": "graphics"
    }
}
```

## Updating Ventoy

```bash
# Update preserves existing ISO files
sudo bash scripts/usb-manager.sh --ventoy-update
```

Or manually:
```bash
sudo ./Ventoy2Disk.sh -u /dev/sdX
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| ISO not booting | Verify ISO integrity, check Secure Boot settings |
| USB not detected | Try different port, check `dmesg` for errors |
| Ventoy menu not showing | Reinstall Ventoy, check partition table |
| Slow boot | Try different USB port (USB 3.0 recommended) |

## References

- Official Ventoy: https://www.ventoy.net
- GitHub Repository: https://github.com/ventoy/Ventoy
- Documentation: https://www.ventoy.net/en/doc_start
