# Automount Architecture

## Overview

The portable-linux-usb skill includes a complete udev-based automount system for USB drives.

## Components

### udev Rules (`udev-usb-automount.rules`)
- Triggers on block device add/remove events
- Filters for USB storage devices
- Calls the mount script with appropriate action

### Mount Script (`usb-mount.sh`)
- Handles mount/unmount operations
- Creates predictable mount points at `/mnt/usb/<label>/`
- Supports multiple filesystems (ext4, vfat, ntfs, exfat)
- Manages mount options per filesystem type

### Systemd Service (`usb-automount.service`)
- Runs the mount script as a oneshot service
- Started by udev on device events

## Mount Point Structure

```
/mnt/usb/
├── <label-or-device-name>/
│   └── (filesystem contents)
```

If no label is present, uses the device name (e.g., `sdb1`).

## Filesystem Support

| Filesystem | Mount Options |
|------------|---------------|
| ext4       | defaults,noatime |
| vfat       | defaults,uid=1000,gid=1000,umask=022 |
| ntfs       | defaults,uid=1000,gid=1000,umask=022,windows_names |
| exfat      | defaults,uid=1000,gid=1000,umask=022 |

## Installation

Run `./setup-usb-automount.sh` as root to install:
1. udev rules to `/etc/udev/rules.d/99-usb-automount.rules`
2. Mount script to `/usr/local/bin/usb-mount.sh`
3. Systemd service to `/etc/systemd/system/usb-automount.service`
4. Reloads udev and systemd

## Removal

Run `./teardown-usb-automount.sh` as root to uninstall all components.