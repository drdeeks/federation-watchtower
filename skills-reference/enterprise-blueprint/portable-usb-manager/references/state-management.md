# USB State Management

## Overview

The portable-linux-usb skill includes a persistent state tracking system for USB devices using a JSON-based database.

## Components

### State Manager (`usb_state_manager.py`)
- Tracks USB devices by UUID
- Persists device metadata, tags, and history
- Supports CRUD operations on device records

## Data Structure

```json
{
  "devices": {
    "uuid-string": {
      "label": "MY_USB",
      "device": "/dev/sdb1",
      "uuid": "1234-5678",
      "filesystem": "ext4",
      "tags": ["backup", "boot"],
      "first_seen": "2026-06-12T10:00:00Z",
      "last_seen": "2026-06-12T14:30:00Z",
      "mount_count": 5,
      "history": [
        {"action": "mount", "timestamp": "2026-06-12T14:30:00Z", "mount_point": "/mnt/usb/MY_USB"},
        {"action": "unmount", "timestamp": "2026-06-12T14:35:00Z"}
      ]
    }
  }
}
```

## Storage Location

State is stored at:
- `$HOME/.local/share/portable-linux-usb/state.json` (user-level)
- Or `/var/lib/portable-linux-usb/state.json` (system-level)

## Usage

```bash
# Scan for USB devices and update state
python3 usb_state_manager.py scan

# List all tracked devices
python3 usb_state_manager.py list

# Get device info by UUID
python3 usb_state_manager.py info <uuid>

# Add tags to a device
python3 usb_state_manager.py tag <uuid> backup boot

# Export state to JSON
python3 usb_state_manager.py export > backup.json

# Import state from JSON
python3 usb_state_manager.py import backup.json
```

## Integration with Automount

When the udev-based automount system mounts a device, it can optionally update the state database with:
- Mount timestamp
- Mount point
- Filesystem type
- Device label and UUID

This enables tracking of device usage patterns and automated management decisions.