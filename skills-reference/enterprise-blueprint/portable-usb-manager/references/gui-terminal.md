# GUI and Terminal Access Guide for USB Drives
## Table of Contents

- [Overview](#overview)
- [Linux GUI Access](#linux-gui-access)
- [Linux Terminal Access](#linux-terminal-access)
- [Windows GUI Access](#windows-gui-access)
- [Windows Terminal Access](#windows-terminal-access)
- [macOS GUI Access](#macos-gui-access)
- [macOS Terminal Access](#macos-terminal-access)
- [Cross-Platform Tools](#cross-platform-tools)
- [GUI File Managers Comparison](#gui-file-managers-comparison)
- [Terminal Emulators Comparison](#terminal-emulators-comparison)
- [Common Operations by OS](#common-operations-by-os)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [References](#references)


## Overview

This guide covers how to access and manage USB drives using both graphical user interfaces (GUI) and command-line tools across different operating systems.

## Linux GUI Access

### GNOME Files (Nautilus)
1. Insert USB drive
2. Open Files (Nautilus)
3. USB drive appears in left sidebar under "Devices"
4. Click to mount and browse
5. Right-click for options (Open, Eject, Properties)

### KDE Dolphin
1. Insert USB drive
2. Open Dolphin file manager
3. USB drive appears in "Devices" panel
4. Click to mount and browse
5. Right-click for options (Open, Unmount, Properties)

### Thunar (XFCE)
1. Insert USB drive
2. Open Thunar file manager
3. USB drive appears in sidebar
4. Click to mount and browse
5. Right-click for options

### Auto-Mount Settings
```bash
# Enable auto-mount in GNOME
gsettings set org.gnome.desktop.media-handling automount true
gsettings set org.gnome.desktop.media-handling automount-open false

# Enable auto-mount in KDE
# System Settings → Removable Storage → Removable Devices
# Check "Auto mount when inserted"
```

## Linux Terminal Access

### Basic Commands

```bash
# List USB devices
lsblk -o NAME,SIZE,TYPE,TRAN,MODEL

# List all block devices
lsblk

# Check device details
sudo fdisk -l /dev/sdX

# View device information
sudo blkid /dev/sdX1
```

### Mounting

```bash
# Create mount point
sudo mkdir -p /mnt/usb

# Mount USB drive
sudo mount /dev/sdX1 /mnt/usb

# Mount with options
sudo mount -o uid=$(id -u),gid=$(id -g),umask=0022 /dev/sdX1 /mnt/usb

# Unmount
sudo umount /mnt/usb
```

### File Operations

```bash
# List files
ls -la /mnt/usb/

# Copy files to USB
cp /path/to/file /mnt/usb/

# Copy files from USB
cp /mnt/usb/file /path/to/destination/

# Move files to USB
mv /path/to/file /mnt/usb/

# Delete files from USB
rm /mnt/usb/file

# Create directory
mkdir /mnt/usb/new-directory

# Change permissions
chmod 755 /mnt/usb/file
chown $(id -u):$(id -g) /mnt/usb/file
```

### Disk Usage

```bash
# Check disk usage
df -h /mnt/usb

# Check directory size
du -sh /mnt/usb/*

# Find largest files
find /mnt/usb -type f -exec du -h {} + | sort -rh | head -10
```

### Safe Removal

```bash
# Check if device is in use
lsof /mnt/usb

# Sync data to USB
sync

# Unmount
sudo umount /mnt/usb

# Or eject (unmount + power off)
sudo eject /dev/sdX
```

## Windows GUI Access

### File Explorer
1. Insert USB drive
2. Open File Explorer
3. USB drive appears under "This PC"
4. Double-click to open
5. Right-click for options (Open, Eject, Format)

### Disk Management
1. Press Win + X, select "Disk Management"
2. USB drive appears in disk list
3. Right-click for options (Initialize, Create Volume, Format)

### Settings
1. Open Settings → Devices → Disks & drives
2. USB drive appears in list
3. Click to manage

## Windows Terminal Access

### Basic Commands

```bash
# List disks
diskpart
list disk

# List volumes
diskpart
list volume

# Check disk details
wmic diskdrive get model,size,status

# Check volume details
wmic logicaldisk get caption,description,size,freespace
```

### Using diskpart

```bash
# Start diskpart
diskpart

# List disks
list disk

# Select disk
select disk 1

# List partitions
list partition

# Select partition
select partition 1

# Assign drive letter
assign letter=Z

# Remove drive letter
remove letter=Z

# Clean disk (DESTRUCTIVE)
clean

# Create partition
create partition primary

# Format partition
format fs=ntfs quick

# Exit diskpart
exit
```

### PowerShell Commands

```bash
# Get disk information
Get-Disk

# Get volume information
Get-Volume

# Get partition information
Get-Partition

# Initialize disk
Initialize-Disk -Number 1 -PartitionStyle GPT

# Create partition
New-Partition -DiskNumber 1 -UseMaximumSize -AssignDriveLetter

# Format partition
Format-Volume -DriveLetter Z -FileSystem NTFS -NewFileSystemLabel "USB"

# Remove drive letter
Remove-PartitionAccessPath -DiskNumber 1 -AccessPath "Z:\"
```

## macOS GUI Access

### Finder
1. Insert USB drive
2. USB drive appears in Finder sidebar
3. Click to mount and browse
4. Right-click for options (Open, Eject, Get Info)

### Disk Utility
1. Open Applications → Utilities → Disk Utility
2. USB drive appears in sidebar
3. Click for options (Mount, Unmount, Erase, First Aid)

### System Information
1. Open Apple Menu → About This Mac → System Report
2. Navigate to USB section
3. View USB device details

## macOS Terminal Access

### Basic Commands

```bash
# List USB devices
diskutil list

# Get device details
diskutil info /dev/disk2

# Mount device
diskutil mount /dev/disk2s1

# Unmount device
diskutil unmount /dev/disk2s1

# Eject device
diskutil eject /dev/disk2

# Erase device (DESTRUCTIVE)
diskutil eraseDisk FAT32 "USB" MBRFormat /dev/disk2
```

### File Operations

```bash
# List files
ls -la /Volumes/USB/

# Copy files to USB
cp /path/to/file /Volumes/USB/

# Copy files from USB
cp /Volumes/USB/file /path/to/destination/

# Safe removal
diskutil unmount /Volumes/USB
diskutil eject /dev/disk2
```

## Cross-Platform Tools

### rsync (Linux/macOS)

```bash
# Sync directory to USB
rsync -av /path/to/source/ /mnt/usb/backup/

# Sync from USB to local
rsync -av /mnt/usb/backup/ /path/to/destination/

# Delete files not in source
rsync -av --delete /path/to/source/ /mnt/usb/backup/
```

### scp (SSH)

```bash
# Copy files to remote USB
scp /path/to/file user@remote:/mnt/usb/

# Copy files from remote USB
scp user@remote:/mnt/usb/file /path/to/destination/

# Copy directory recursively
scp -r /path/to/directory user@remote:/mnt/usb/
```

### tar (Archive)

```bash
# Create archive on USB
tar -czf /mnt/usb/backup.tar.gz /path/to/source

# Extract archive from USB
tar -xzf /mnt/usb/backup.tar.gz -C /path/to/destination

# List archive contents
tar -tzf /mnt/usb/backup.tar.gz
```

## GUI File Managers Comparison

| Feature | Nautilus | Dolphin | Thunar | Explorer | Finder |
|---------|----------|---------|--------|----------|--------|
| Auto-mount | ✓ | ✓ | ✓ | ✓ | ✓ |
| Mount notification | ✓ | ✓ | ✓ | ✓ | ✓ |
| Right-click menu | ✓ | ✓ | ✓ | ✓ | ✓ |
| Properties dialog | ✓ | ✓ | ✓ | ✓ | ✓ |
| Terminal integration | ✓ | ✓ | ✓ | ✓ | ✗ |
| Network support | ✓ | ✓ | ✓ | ✓ | ✓ |
| Plugin system | ✓ | ✓ | ✓ | ✗ | ✓ |

## Terminal Emulators Comparison

| Feature | GNOME Terminal | Konsole | xterm | PowerShell | Terminal.app |
|---------|---------------|---------|-------|------------|--------------|
| Tabs | ✓ | ✓ | ✓ | ✓ | ✓ |
| Split view | ✓ | ✓ | ✗ | ✓ | ✓ |
| Custom profiles | ✓ | ✓ | ✓ | ✓ | ✓ |
| Unicode support | ✓ | ✓ | ✓ | ✓ | ✓ |
| Mouse support | ✓ | ✓ | ✓ | ✓ | ✓ |
| 256 colors | ✓ | ✓ | ✓ | ✓ | ✓ |
| True color | ✓ | ✓ | ✗ | ✓ | ✓ |

## Common Operations by OS

### Mount USB Drive
**Linux**: `sudo mount /dev/sdX1 /mnt/usb`
**Windows**: Automatic or `diskpart` → `assign letter=Z`
**macOS**: `diskutil mount /dev/disk2s1`

### Unmount USB Drive
**Linux**: `sudo umount /mnt/usb`
**Windows**: `diskpart` → `remove letter=Z` or Eject in Explorer
**macOS**: `diskutil unmount /Volumes/USB`

### Check Disk Space
**Linux**: `df -h /mnt/usb`
**Windows**: `wmic logicaldisk get caption,freespace,size`
**macOS**: `df -h /Volumes/USB`

### List Files
**Linux**: `ls -la /mnt/usb/`
**Windows**: `dir Z:\`
**macOS**: `ls -la /Volumes/USB/`

### Copy Files
**Linux**: `cp /path/to/file /mnt/usb/`
**Windows**: `copy file.txt Z:\`
**macOS**: `cp /path/to/file /Volumes/USB/`

## Troubleshooting

| Issue | Linux | Windows | macOS |
|-------|-------|---------|-------|
| Drive not mounting | Check `dmesg`, use `mount` | Check Disk Management | Check Disk Utility |
| Permission denied | Use `sudo` or fix ownership | Run as Administrator | Use `sudo` |
| Slow performance | Check USB port, use `hdparm` | Check USB driver | Check USB port |
| Drive not ejecting | `lsof` to find processes | Close all handles | Force eject |
| Corrupted filesystem | Run `fsck` | Run `chkdsk` | Run First Aid |

## Best Practices

1. **Always eject safely** before removing USB drives
2. **Use consistent mount points** for scripts and automation
3. **Check disk space** before large file transfers
4. **Use appropriate filesystem** for target OS
5. **Backup important data** before formatting
6. **Avoid force-removing** during write operations

## References

- Linux Mount: https://man7.org/linux/man-pages/man8/mount.8.html
- Disk Utility: https://man7.org/linux/man-pages/man8/diskutil.8.html
- Windows DiskPart: https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/diskpart
- macOS Terminal: https://support.apple.com/guide/terminal/welcome/mac
