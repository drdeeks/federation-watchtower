# USB Boot Guide
## Table of Contents

- [Overview](#overview)
- [Boot Methods](#boot-methods)
- [Boot Menu Keys by Manufacturer](#boot-menu-keys-by-manufacturer)
- [Secure Boot Configuration](#secure-boot-configuration)
- [Booting Different USB Types](#booting-different-usb-types)
- [BIOS/UEFI Settings for USB Boot](#bios/uefi-settings-for-usb-boot)
- [Troubleshooting Boot Issues](#troubleshooting-boot-issues)
- [Dual-Boot with USB](#dual-boot-with-usb)
- [USB Boot Performance](#usb-boot-performance)
- [References](#references)


## Overview

This guide covers how to boot from USB drives, including BIOS/UEFI configuration, boot menu access, and troubleshooting boot issues.

## Boot Methods

### 1. BIOS Boot (Legacy/CSM)

**Supported**: MBR partition table, BIOS firmware

**Steps**:
1. Insert USB drive into target computer
2. Restart computer
3. Enter BIOS setup (usually F2, F10, Del, or Esc)
4. Navigate to Boot Order/Boot Priority
5. Move USB device to first position
6. Save and exit (usually F10)

**Common BIOS Keys**:
| Manufacturer | BIOS Key | Boot Menu Key |
|--------------|----------|---------------|
| Dell | F2 | F12 |
| HP | F10 | F9 |
| Lenovo | F1/F2 | F12 |
| Acer | F2 | F12 |
| ASUS | F2/Del | F8 |
| MSI | Del | F11 |
| Gigabyte | Del | F12 |

### 2. UEFI Boot

**Supported**: GPT partition table, UEFI firmware

**Steps**:
1. Insert USB drive into target computer
2. Restart computer
3. Enter UEFI firmware setup (usually Del or F2)
4. Disable Secure Boot (if needed)
5. Enable CSM/Legacy Boot (if dual-booting)
6. Set USB as first boot device
7. Save and exit

### 3. One-Time Boot Menu

**Most modern computers support a boot menu** that doesn't require changing BIOS settings.

**Steps**:
1. Insert USB drive
2. Restart computer
3. Press boot menu key during POST (see table above)
4. Select USB device from menu
5. Press Enter

## Boot Menu Keys by Manufacturer

| Manufacturer | Desktop | Laptop |
|--------------|---------|--------|
| Dell | F12 | F12 |
| HP | F9 | F9 |
| Lenovo | F12 | F12 |
| Acer | F12 | F12 |
| ASUS | F8 | Esc |
| MSI | F11 | F11 |
| Gigabyte | F12 | F12 |
| Samsung | F10 | F10 |
| Sony | F11 | F11 |
| Toshiba | F12 | F12 |

## Secure Boot Configuration

### What is Secure Boot?
UEFI Secure Boot ensures only signed bootloaders can run. This can prevent booting from USB drives.

### Disabling Secure Boot
1. Enter UEFI setup (usually Del or F2)
2. Navigate to Security or Boot settings
3. Find "Secure Boot" option
4. Disable it
5. Save and exit

### Re-enabling Secure Boot
After installing a Linux distribution with signed bootloader:
1. Enter UEFI setup
2. Navigate to Security or Boot settings
3. Enable Secure Boot
4. Save and exit

## Booting Different USB Types

### Ventoy Multi-ISO Boot
1. Boot from Ventoy USB
2. Select ISO from Ventoy menu
3. Press Enter to boot selected ISO

### Live USB Boot
1. Boot from USB
2. Select "Try Ubuntu" or similar option
3. Wait for desktop to load

### Persistent USB Boot
1. Boot from USB
2. Select "Try Ubuntu" option
3. Changes will be saved to persistence partition

### Windows Installer USB
1. Boot from USB
2. Select language and preferences
3. Follow installation wizard

## BIOS/UEFI Settings for USB Boot

### Enable USB Boot Support
Ensure these settings are enabled:
- **USB Boot**: Enabled
- **Legacy Support**: Enabled (for MBR boot)
- **CSM (Compatibility Support Module)**: Enabled (for legacy boot)
- **Fast Boot**: Disabled (to allow USB detection)

### Boot Order Priority
Set boot order to:
1. USB Device (first priority)
2. Hard Drive
3. Network Boot
4. Optical Drive

## Troubleshooting Boot Issues

### USB Not Detected in Boot Menu
**Causes**:
- USB not inserted properly
- BIOS doesn't support USB boot
- USB drive not bootable
- BIOS settings disable USB boot

**Solutions**:
1. Try different USB port
2. Check BIOS USB boot settings
3. Verify USB is bootable (use `fdisk -l /dev/sdX`)
4. Update BIOS firmware

### Boot Fails with "No Bootable Device"
**Causes**:
- Corrupted bootloader
- Wrong partition table (MBR vs GPT)
- Secure Boot blocking unsigned bootloader

**Solutions**:
1. Verify partition table matches firmware (MBR=BIOS, GPT=UEFI)
2. Disable Secure Boot temporarily
3. Reinstall bootloader (GRUB)
4. Check USB drive integrity

### Boot Hangs on Black Screen
**Causes**:
- Graphics driver issues
- Kernel parameters needed
- USB controller issues

**Solutions**:
1. Try "nomodeset" kernel parameter
2. Use different USB port (USB 2.0 instead of 3.0)
3. Check BIOS USB controller settings

### Boot Loop (Restarting Repeatedly)
**Causes**:
- Incompatible hardware
- Corrupted installation media
- Driver conflicts

**Solutions**:
1. Try different USB drive
2. Re-download and verify ISO
3. Check hardware compatibility

## Dual-Boot with USB

### Installing Linux to USB
1. Boot from USB (live environment)
2. Select "Install Ubuntu"
3. Choose "Something Else" for partitioning
4. Select USB device as target
5. Install GRUB to USB device

### Booting from Installed USB
1. Insert USB into target computer
2. Boot from USB (should show GRUB menu)
3. Select operating system

## USB Boot Performance

### Optimization Tips
- Use USB 3.0 ports for faster boot
- Use high-speed USB drives (USB 3.1/3.2)
- Avoid USB hubs (connect directly to computer)
- Use SSD-based USB drives for best performance

### Expected Boot Times
| Boot Type | USB 2.0 | USB 3.0 | USB 3.1 |
|-----------|---------|---------|---------|
| Live USB | 30-60s | 10-20s | 5-10s |
| Persistent USB | 45-90s | 15-30s | 8-15s |
| Ventoy Multi-ISO | 40-80s | 12-25s | 6-12s |

## References

- BIOS Configuration: https://www.computerhope.com/issues/ch000228.htm
- UEFI Boot: https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface
- Secure Boot: https://wiki.archlinux.org/title/Secure_Boot
- USB Boot: https://wiki.archlinux.org/title/USB_flash_installation_medium
