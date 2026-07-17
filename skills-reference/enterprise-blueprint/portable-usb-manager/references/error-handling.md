# Error Handling

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.
## Table of Contents

- [Common Errors](#common-errors)
- [Recovery Procedures](#recovery-procedures)
- [Prevention](#prevention)
- [Error Codes](#error-codes)


Comprehensive error catalog and recovery procedures for portable Linux USB operations.

## Common Errors

### USB Detection Errors

#### "Device or resource busy"

**Cause:** USB partitions are mounted or in use.

**Solution:**
```bash
# Find what's using the device:
sudo lsof /dev/sdX
sudo fuser -v /dev/sdX

# Unmount all partitions:
sudo umount /dev/sdX*

# If still busy, kill processes:
sudo fuser -k /dev/sdX
```

#### "No medium found"

**Cause:** USB drive not detected or not properly connected.

**Solution:**
```bash
# Rescan SCSI devices:
sudo scsi-rescan

# Or reload USB modules:
sudo modprobe -r usb-storage
sudo modprobe usb-storage

# Check kernel messages:
dmesg | tail -20
```

#### "Permission denied"

**Cause:** User lacks permissions for device access.

**Solution:**
```bash
# Add user to disk group:
sudo usermod -aG disk $USER

# Or run command with sudo:
sudo <command>

# For persistent access, create udev rule:
echo 'SUBSYSTEM=="block", GROUP="disk", MODE="0660"' | \
    sudo tee /etc/udev/rules.d/99-usb.rules
sudo udevadm control --reload-rules
```

### Ventoy Installation Errors

#### "mkexfatfs: command not found"

**Cause:** Ventoy cannot find the exfat formatting tool.

**Solution:**
```bash
# Install exfat support:
sudo apt install exfatprogs exfat-fuse -y

# Create symlink:
sudo ln -s /usr/sbin/mkfs.exfat /usr/sbin/mkexfatfs

# Copy Ventoy's bundled tools:
sudo cp /tmp/ventoy-1.1.12/tool/x86_64/* /usr/sbin/
```

#### "vtoycli: command not found"

**Cause:** Ventoy's CLI tools not in PATH.

**Solution:**
```bash
# Copy Ventoy tools to PATH:
sudo cp /tmp/ventoy-1.1.12/tool/x86_64/* /usr/sbin/

# Or run from Ventoy directory:
cd /tmp/ventoy-1.1.12 && sudo ./Ventoy2Disk.sh -i /dev/sdX
```

#### "Partition(s) on /dev/sdX are being used"

**Cause:** Existing partitions are mounted.

**Solution:**
```bash
# Unmount all partitions:
sudo umount /dev/sdX*

# Clear partition table:
sudo wipefs -a /dev/sdX

# Then retry Ventoy installation
```

### Persistence Errors

#### "Read-only file system"

**Cause:** Attempting to write to read-only ISO9660 filesystem.

**Solution:**
```bash
# This is expected when using dd with ISO files
# Use Ventoy's persistence mechanism instead:
# 1. Create persistence file separately
# 2. Configure ventoy.json
# 3. Ventoy handles the overlay automatically
```

#### "casper-rw label not found"

**Cause:** Persistence partition missing required label.

**Solution:**
```bash
# Check partition label:
sudo blkid /dev/sdX5

# Relabel if needed:
sudo e2fsck -f /dev/sdX5
sudo tune2fs -L casper-rw /dev/sdX5
```

### Boot Errors

#### Black screen in QEMU

**Cause:** Graphics driver or boot configuration issue.

**Solution:**
```bash
# Try different VGA options:
sudo qemu-system-x86_64 -m 4G \
    -drive file=/dev/sdX,format=raw \
    -boot c -vga std -display gtk

# Or without KVM:
sudo qemu-system-x86_64 -m 4G \
    -drive file=/dev/sdX,format=raw \
    -boot c -vga std -display gtk
```

#### "No bootable device"

**Cause:** BIOS/UEFI not recognizing USB as bootable.

**Solution:**
```bash
# Verify boot flag:
sudo parted /dev/sdX print

# For UEFI boot, ensure EFI partition exists:
sudo parted /dev/sdX print | grep -i efi

# Try different boot mode (UEFI vs Legacy)
```

### Filesystem Errors

#### "EXT4-fs error"

**Cause:** Filesystem corruption.

**Solution:**
```bash
# Check filesystem:
sudo e2fsck -f /dev/sdX5

# If严重 corruption, try recovery:
sudo e2fsck -fy /dev/sdX5

# If still fails, recreate:
sudo mkfs.ext4 -F -L casper-rw /dev/sdX5
```

#### "No space left on device"

**Cause:** Partition or file is full.

**Solution:**
```bash
# Check disk usage:
df -h /dev/sdX5

# Find large files:
sudo du -sh $USB_MOUNT/persistence/*

# Clean up:
sudo rm $USB_MOUNT/persistence/large-file

# Or expand partition:
sudo parted /dev/sdX --script resizepart 5 100%
sudo e2fsck -f /dev/sdX5
sudo resize2fs /dev/sdX5
```

### Agent Isolation Errors

#### "Agent already exists"

**Cause:** Trying to create agent with existing name.

**Solution:**
```bash
# List existing agents:
ls -la $USB_MOUNT/agents/

# Delete or rename existing agent:
python3 scripts/agent-manager.py delete --name existing-agent

# Or use different name:
python3 scripts/agent-manager.py create --name new-agent-name
```

#### "Cannot mount agent partition"

**Cause:** Agent partition corrupted or missing.

**Solution:**
```bash
# Check partition:
sudo e2fsck -f $USB_MOUNT/agents/agent-alpha-home.dat

# Recreate if needed:
sudo dd if=/dev/zero of=$USB_MOUNT/agents/agent-alpha-home.dat \
    bs=1M count=5000
sudo mkfs.ext4 -F -L agent-alpha-home $USB_MOUNT/agents/agent-alpha-home.dat
```

### Network Errors

#### "SSH connection refused"

**Cause:** SSH server not running or network issue.

**Solution:**
```bash
# On USB system:
sudo apt install openssh-server -y
sudo systemctl enable ssh
sudo systemctl start ssh

# Check firewall:
sudo ufw status
sudo ufw allow ssh
```

#### "Cannot reach USB via network"

**Cause:** Network configuration issue.

**Solution:**
```bash
# Check IP address:
ip addr show

# Ping USB:
ping <USB-IP>

# Check routing:
ip route show
```

## Recovery Procedures

### Emergency Recovery

If USB becomes unbootable:

```bash
# 1. Boot from Ubuntu live CD/USB

# 2. Mount USB:
sudo mount /dev/sdX1 /mnt/usb

# 3. Check for errors:
sudo e2fsck -f /dev/sdX1

# 4. Restore from backup:
sudo dd if=~/usb-backup.img of=/dev/sdX bs=4M status=progress

# 5. Or recreate from scratch:
sudo parted /dev/sdX --script mklabel gpt
sudo parted /dev/sdX --script mkpart primary fat32 1MiB 100%
sudo mkfs.vfat -F 32 -n VENTOY /dev/sdX1
```

### Data Recovery

```bash
# Install testdisk:
sudo apt install testdisk photorec -y

# Run PhotoRec:
sudo photorec /dev/sdX

# Follow prompts to recover files
```

### Partition Table Recovery

```bash
# If partition table is corrupted:
sudo testdisk /dev/sdX

# Or manually recreate:
sudo parted /dev/sdX --script mklabel gpt
sudo parted /dev/sdX --script mkpart primary fat32 1MiB 10GiB
sudo parted /dev/sdX --script mkpart primary ext4 10GiB 100%
```

## Prevention

### Regular Maintenance

```bash
# Check filesystem weekly:
sudo e2fsck -f /dev/sdX5

# Monitor disk usage:
df -h /dev/sdX*

# Backup regularly:
python3 scripts/pipeline.py backup --usb /dev/sdX --full
```

### Monitoring

```bash
# Watch for errors:
dmesg -w | grep -i sdX

# Check SMART status:
sudo smartctl -a /dev/sdX

# Monitor I/O:
iostat -x 1 5 /dev/sdX
```

## Error Codes

| Code | Meaning | Solution |
|---|---|---|
| EBUSY | Device busy | Unmount all partitions |
| ENOENT | No such file or directory | Check path/connections |
| EACCES | Permission denied | Use sudo or add to disk group |
| EIO | I/O error | Check USB cable, try different port |
| ENOSPC | No space left | Expand partition or clean up |
| EROFS | Read-only filesystem | Check mount options |
