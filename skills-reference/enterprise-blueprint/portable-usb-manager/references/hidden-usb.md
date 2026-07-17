# Hidden and Unrecognized USB Device Recovery Guide
## Table of Contents

- [Overview](#overview)
- [Common Causes](#common-causes)
- [Detection Methods](#detection-methods)
- [Recovery Procedures](#recovery-procedures)
- [Diagnostic Workflow](#diagnostic-workflow)
- [Prevention Tips](#prevention-tips)
- [When to Seek Professional Help](#when-to-seek-professional-help)
- [References](#references)


## Overview

Hidden or unrecognized USB devices are storage devices that are physically connected but not properly detected or accessible by the operating system. This guide covers detection, diagnosis, and recovery methods.

## Common Causes

| Cause | Symptoms | Recovery Difficulty |
|-------|----------|---------------------|
| Corrupted partition table | Device detected but no partitions | Easy |
| Write protection | Read-only access, cannot format | Medium |
| Kernel driver issues | Device not detected at all | Medium |
| Hardware failure | Intermittent detection, errors | Hard |
| Incorrect filesystem | Device detected but won't mount | Easy |
| USB controller issues | Device disconnects frequently | Medium |

## Detection Methods

### Via USB Manager
```bash
# Scan for hidden devices
sudo bash scripts/usb-manager.sh --scan-hidden

# Or in interactive mode
sudo bash scripts/usb-manager.sh
# Select device -> option h (Scan for hidden devices)
```

### Manual Detection Commands

```bash
# List all block devices
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL

# Check kernel logs for USB events
dmesg | grep -i "usb\|sd[a-z]\|removable"

# List all SCSI devices
ls /sys/block/ | grep sd

# Check for write-protected devices
for dev in /sys/block/sd*; do
    echo -n "$dev: "
    cat "$dev/ro" 2>/dev/null || echo "N/A"
done

# Scan for devices without filesystem
for dev in /dev/sd?; do
    [[ -b "$dev" ]] || continue
    fs=$(blkid -o value -s TYPE "$dev" 2>/dev/null || echo "none")
    echo "$dev: $fs"
done
```

## Recovery Procedures

### 1. Corrupted Partition Table

**Symptoms**: Device appears in `lsblk` but no partitions shown.

**Recovery**:
```bash
# Wipe partition table
sudo dd if=/dev/zero of=/dev/sdX bs=1M count=10

# Create new MBR partition table
sudo fdisk /dev/sdX
# Press 'o' to create new DOS partition table
# Press 'w' to write changes

# Or create GPT
sudo gdisk /dev/sdX
# Press 'o' to create new GPT
# Press 'w' to write changes
```

### 2. Write Protection

**Symptoms**: Device is read-only, cannot format or write.

**Recovery**:
```bash
# Check write protection status
cat /sys/block/sdX/ro

# Attempt software unlock
sudo blockdev --setrw /dev/sdX

# If hardware switch, check device physically
# Some USB drives have write-protect switches
```

### 3. Kernel Driver Issues

**Symptoms**: Device not detected at all.

**Recovery**:
```bash
# Reload USB storage driver
sudo modprobe -r usb_storage
sudo modprobe usb_storage

# Check USB device
lsusb

# Reset USB port
echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/unbind
sleep 2
echo '1-1' | sudo tee /sys/bus/usb/drivers/usb/bind
```

### 4. Incorrect Filesystem

**Symptoms**: Device detected but won't mount.

**Recovery**:
```bash
# Identify filesystem
sudo blkid /dev/sdX1
sudo file -s /dev/sdX1

# Install missing drivers
# For NTFS:
sudo apt install ntfs-3g

# For exFAT:
sudo apt install exfat-fuse exfat-utils

# Mount manually
sudo mount -t ntfs-3g /dev/sdX1 /mnt/usb
```

### 5. Low-Level Format (Last Resort)

**WARNING**: This destroys all data and may take hours.

```bash
# Zero-fill entire device
sudo dd if=/dev/zero of=/dev/sdX bs=512

# Or use badblocks for thorough wipe
sudo badblocks -wsv /dev/sdX
```

## Diagnostic Workflow

```
USB Device Issue
    │
    ├─ Device not detected?
    │   ├─ Check USB connection
    │   ├─ Try different port
    │   ├─ Check dmesg for errors
    │   └─ Reload kernel drivers
    │
    ├─ Device detected but no partitions?
    │   ├─ Check partition table
    │   ├─ Wipe and recreate
    │   └─ Test with different partition tool
    │
    ├─ Device detected but won't mount?
    │   ├─ Check filesystem type
    │   ├─ Install missing drivers
    │   └─ Try manual mount
    │
    └─ Device read-only?
        ├─ Check software write protection
        ├─ Check hardware switch
        └─ Attempt blockdev unlock
```

## Prevention Tips

1. **Always eject safely** before removing USB drives
2. **Avoid force-removing** during write operations
3. **Use quality USB drives** from reputable manufacturers
4. **Keep backups** of important data
5. **Avoid power interruptions** during writes

## When to Seek Professional Help

- Physical damage to USB connector
- Water/fire damage
- Firmware corruption
- Persistent detection failures after all recovery attempts

## References

- Linux USB Guide: https://www.kernel.org/doc/html/latest/driver-api/usb/
- USB Storage: https://www.kernel.org/doc/html/latest/driver-api/usb/usb.html
- Troubleshooting USB: https://help.ubuntu.com/community/USBTroubleshooting
