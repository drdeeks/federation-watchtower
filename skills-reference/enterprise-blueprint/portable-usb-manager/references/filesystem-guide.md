# Filesystem Selection and Management Reference
## Table of Contents

- [Overview](#overview)
- [Filesystem Comparison](#filesystem-comparison)
- [Filesystem Selection Guide](#filesystem-selection-guide)
- [Filesystem Operations](#filesystem-operations)
- [Performance Comparison](#performance-comparison)
- [Mounting Filesystems](#mounting-filesystems)
- [Filesystem Conversions](#filesystem-conversions)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [References](#references)


## Overview

Choosing the right filesystem for your USB drive depends on your use case, compatibility requirements, and performance needs. This guide helps you select and manage filesystems effectively.

## Filesystem Comparison

| Filesystem | Max File Size | Max Drive Size | Windows | Mac | Linux | Best For |
|------------|---------------|----------------|---------|-----|-------|----------|
| FAT32 | 4 GB | 2 TB | ✓ | ✓ | ✓ | Universal compatibility |
| exFAT | 16 EB | 128 PB | ✓ | ✓ | ✓ | Modern cross-platform |
| NTFS | 16 EB | 256 TB | ✓ | R/O | ✓ | Windows primary |
| ext4 | 16 TB | 1 EB | R/O | R/O | ✓ | Linux native |
| ext3 | 2 TB | 2 TB | R/O | R/O | ✓ | Older Linux systems |
| ext2 | 2 TB | 2 TB | R/O | R/O | ✓ | Minimal Linux |
| Btrfs | 16 EB | 16 EB | R/O | R/O | ✓ | Advanced Linux features |
| XFS | 8 EB | 8 EB | R/O | R/O | ✓ | High performance |

**Legend**: ✓ = Full support, R/O = Read-only support, EB = Exabyte, PB = Petabyte

## Filesystem Selection Guide

### Use Case: Cross-Platform (Windows/Mac/Linux)
**Recommended**: exFAT

```bash
# Format as exFAT
sudo mkfs.exfat -n "CROSS-PLATFORM" /dev/sdX1

# Install exFAT support if needed
sudo apt install exfat-fuse exfat-utils
```

### Use Case: Windows Primary
**Recommended**: NTFS

```bash
# Format as NTFS
sudo mkfs.ntfs -f -L "WINDOWS-USB" /dev/sdX1

# Install NTFS support if needed
sudo apt install ntfs-3g
```

### Use Case: Maximum Compatibility
**Recommended**: FAT32

```bash
# Format as FAT32
sudo mkfs.vfat -F 32 -n "UNIVERSAL" /dev/sdX1

# Note: 4GB file size limit
```

### Use Case: Linux Only
**Recommended**: ext4

```bash
# Format as ext4
sudo mkfs.ext4 -L "LINUX-USB" /dev/sdX1
```

### Use Case: Large File Transfer
**Recommended**: exFAT or NTFS

```bash
# Format as exFAT (no file size limit)
sudo mkfs.exfat -n "LARGE-FILES" /dev/sdX1
```

## Filesystem Operations

### Detecting Filesystem

```bash
# Using blkid
sudo blkid /dev/sdX1

# Using file command
sudo file -s /dev/sdX1

# Using lsblk
lsblk -o NAME,FSTYPE,LABEL /dev/sdX1
```

### Checking Filesystem Health

```bash
# ext2/ext3/ext4
sudo e2fsck -f /dev/sdX1

# NTFS
sudo ntfsfix /dev/sdX1

# FAT32
sudo fsck.vfat -a /dev/sdX1

# exFAT
sudo fsck.exfat /dev/sdX1
```

### Repairing Filesystem

```bash
# ext2/ext3/ext4
sudo e2fsck -y /dev/sdX1

# NTFS
sudo ntfsfix -d /dev/sdX1

# FAT32
sudo fsck.vfat -a -w /dev/sdX1
```

### Resizing Filesystem

```bash
# ext4 (shrink must be done offline)
sudo umount /dev/sdX1
sudo resize2fs /dev/sdX1 20G  # Resize to 20GB

# NTFS
sudo ntfsresize /dev/sdX1 20G
```

## Performance Comparison

| Filesystem | Sequential Read | Sequential Write | Random I/O | CPU Usage |
|------------|-----------------|------------------|------------|-----------|
| FAT32 | Medium | Medium | Low | Low |
| exFAT | High | High | Low | Low |
| NTFS | High | Medium | Medium | Medium |
| ext4 | High | High | High | Low |
| Btrfs | Medium | Medium | Medium | High |
| XFS | High | High | High | Medium |

## Mounting Filesystems

### Automatic Mounting

```bash
# Find device
lsblk -o NAME,SIZE,FSTYPE,LABEL

# Mount with automatic options
sudo mount /dev/sdX1 /mnt/usb
```

### Manual Mounting with Options

```bash
# FAT32 (set ownership)
sudo mount -o uid=$(id -u),gid=$(id -g),umask=0022 /dev/sdX1 /mnt/usb

# NTFS (with ntfs-3g)
sudo mount -t ntfs-3g -o uid=$(id -u),gid=$(id -g),umask=0022 /dev/sdX1 /mnt/usb

# ext4 (with full permissions)
sudo mount -o rw /dev/sdX1 /mnt/usb
```

### Persistent Mounting

Add to `/etc/fstab`:
```
# FAT32
/dev/sdX1  /mnt/usb  vfat  uid=$(id -u),gid=$(id -g),umask=0022  0  0

# NTFS
/dev/sdX1  /mnt/usb  ntfs-3g  uid=$(id -u),gid=$(id -g),umask=0022  0  0

# ext4
/dev/sdX1  /mnt/usb  ext4  rw  0  0
```

## Filesystem Conversions

### FAT32 to exFAT
```bash
# Backup data, then format
sudo mkfs.exfat -n "NEW-LABEL" /dev/sdX1
```

### ext4 to ext2 (for compatibility)
```bash
sudo tune2fs -O ^has_journal /dev/sdX1
sudo e2fsck -f /dev/sdX1
```

### Create ext4 from ext2
```bash
sudo tune2fs -O has_journal /dev/sdX1
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Read-only mount | Filesystem errors | Run fsck, remount rw |
| Cannot write | Permission issues | Check uid/gid mount options |
| Large files fail | FAT32 limit | Use exFAT or NTFS |
| Slow performance | Wrong filesystem | Consider ext4 or XFS |
| Mount fails | Missing drivers | Install ntfs-3g/exfat-fuse |
| Corruption | Improper eject | Run fsck, use safe removal |

## Best Practices

1. **Match filesystem to use case** - Don't use ext4 for Windows drives
2. **Check compatibility** - Ensure target system supports chosen filesystem
3. **Use labels** - Makes drives easier to identify
4. **Backup before conversion** - Filesystem changes can lose data
5. **Safely eject** - Prevents corruption and data loss
6. **Monitor health** - Run periodic fsck on Linux filesystems

## References

- Linux Filesystems: https://www.kernel.org/doc/html/latest/filesystems/
- mkfs Commands: https://man7.org/linux/man-pages/man8/mkfs.8.html
- Mount Options: https://man7.org/linux/man-pages/man8/mount.8.html
- Filesystem Wiki: https://en.wikipedia.org/wiki/Comparison_of_file_systems
