# Lesson: Mounted Partitions Block Ventoy Install

## Context
Installing Ventoy on a real USB device (`/dev/sdd`) that had an NTFS partition mounted at `/mnt/usb-test` via `fuseblk`.

## What Happened
Ventoy2Disk.sh refused to install:
```
/dev/sdd is already mounted, please umount it first!
```
The script checks `mount` output and refuses to install if ANY partition of the target device is mounted. NTFS partitions are commonly auto-mounted by the OS via `fuseblk`.

## Resolution
Added explicit unmount loop before running Ventoy:
```bash
for part in "${DEVICE}"*; do
    if [[ -b "$part" ]]; then
        umount "$part" 2>/dev/null || true
    fi
done
```

## Prevention
- Always unmount ALL partitions on the target device before disk operations
- Check with `mount | grep "/dev/sdX"` or `lsblk -o NAME,MOUNTPOINT /dev/sdX`
- Use `umount` not `mount -u`
- If unmount fails with "target is busy", use `fuser -km /dev/sdXN`
- For NTFS: `sudo umount /dev/sdXN` (fuseblk)

## Date: 2026-06-10
## Verified: yes
