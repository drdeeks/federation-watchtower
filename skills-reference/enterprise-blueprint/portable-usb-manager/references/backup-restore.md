# Backup & Restore

> **Mount variable:** examples use `$USB_MOUNT` for the USB mount point — set it once, e.g. `export USB_MOUNT="$(findmnt -no TARGET LABEL=Ventoy 2>/dev/null || echo /media/$USER/Ventoy)"`.
> **Backup variable:** `$BACKUP_MOUNT` is the backup destination mount — set it e.g. `export BACKUP_MOUNT="/media/$USER/backup"`.
## Table of Contents

- [Backup Strategies](#backup-strategies)
- [Backup Scripts](#backup-scripts)
- [Restore Procedures](#restore-procedures)
- [Backup Storage](#backup-storage)
- [Backup Management](#backup-management)
- [Disaster Recovery](#disaster-recovery)
- [Backup Best Practices](#backup-best-practices)


Automated backup and recovery procedures for portable Linux USB.

## Backup Strategies

### Full USB Image

Complete disk image backup - bit-for-bit copy.

```bash
# Create compressed image:
sudo dd if=/dev/sdX bs=4M status=progress | gzip > ~/usb-full-$(date +%Y%m%d).img.gz

# Or with progress and hash verification:
sudo dd if=/dev/sdX of=~/usb-full-$(date +%Y%m%d).img bs=4M status=progress
sha256sum ~/usb-full-$(date +%Y%m%d).img > ~/usb-full-$(date +%Y%m%d).img.sha256
```

### Selective Backup

Back up specific components.

```bash
# Backup persistence only:
sudo dd if=/dev/sdX5 of=~/persistence-$(date +%Y%m%d).dat bs=4M status=progress

# Backup all agents:
for agent in alpha beta gamma; do
    sudo dd if=$USB_MOUNT/agents/${agent}-home.dat \
        of=~/agent-${agent}-$(date +%Y%m%d).dat bs=4M status=progress
done

# Backup home directory:
sudo tar czf ~/home-$(date +%Y%m%d).tar.gz -C /media/ventoy-usb persistence/

# Backup Ventoy config:
sudo cp -r $USB_MOUNT/ventoy ~/ventoy-config-$(date +%Y%m%d)
```

### Incremental Backup

Back up only changes since last backup.

```bash
# Using rsync:
sudo rsync -av --delete \
    --link-dest=~/usb-backup/latest \
    $USB_MOUNT/ ~/usb-backup/$(date +%Y%m%d)/

# Update latest symlink:
ln -sfn ~/usb-backup/$(date +%Y%m%d) ~/usb-backup/latest
```

## Backup Scripts

### Full Backup Script

```bash
#!/bin/bash
# scripts/backup-full.sh

set -e

USB_DEVICE="${USB_DEVICE:-/dev/sdb}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/usb-backups}"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/${DATE}"

echo "=== USB Backup Started ==="
echo "Device: ${USB_DEVICE}"
echo "Destination: ${BACKUP_PATH}"

# Create backup directory
mkdir -p "${BACKUP_PATH}"

# Backup full image
echo "Creating full image backup..."
sudo dd if="${USB_DEVICE}" of="${BACKUP_PATH}/usb-image.img" \
    bs=4M status=progress

# Compress image
echo "Compressing image..."
gzip "${BACKUP_PATH}/usb-image.img"

# Create checksum
echo "Creating checksum..."
sha256sum "${BACKUP_PATH}/usb-image.img.gz" > "${BACKUP_PATH}/usb-image.img.gz.sha256"

# Backup individual components
echo "Backing up persistence..."
sudo dd if="${USB_DEVICE}5" of="${BACKUP_PATH}/persistence.dat" \
    bs=4M status=progress 2>/dev/null || true

echo "Backing up agents..."
for agent_file in $USB_MOUNT/agents/*-home.dat; do
    if [ -f "$agent_file" ]; then
        agent_name=$(basename "$agent_file" .dat)
        sudo dd if="$agent_file" of="${BACKUP_PATH}/${agent_name}.dat" \
            bs=4M status=progress 2>/dev/null || true
    fi
done

echo "Backing up Ventoy config..."
sudo cp -r $USB_MOUNT/ventoy "${BACKUP_PATH}/ventoy-config"

echo "Backing up ISOs list..."
ls -lh $USB_MOUNT/*.iso > "${BACKUP_PATH}/iso-list.txt"

# Create backup manifest
cat > "${BACKUP_PATH}/manifest.json" << EOF
{
    "date": "${DATE}",
    "device": "${USB_DEVICE}",
    "components": {
        "full_image": "usb-image.img.gz",
        "persistence": "persistence.dat",
        "ventoy_config": "ventoy-config/",
        "agents": "$(ls ${BACKUP_PATH}/*-home.dat 2>/dev/null | wc -l) agents"
    }
}
EOF

echo "=== Backup Complete ==="
echo "Backup location: ${BACKUP_PATH}"
ls -lh "${BACKUP_PATH}"
```

### Selective Backup Script

```bash
#!/bin/bash
# scripts/backup-selective.sh

set -e

USB_DEVICE="${USB_DEVICE:-/dev/sdb}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/usb-backups}"
DATE=$(date +%Y%m%d-%H%M%S)

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Options:"
    echo "  -p, --persistence    Backup persistence only"
    echo "  -a, --agents         Backup agents only"
    echo "  -c, --config         Backup Ventoy config only"
    echo "  -i, --isos           Backup ISO list only"
    echo "  -all, --all          Backup all selective components"
    exit 1
}

backup_persistence() {
    echo "Backing up persistence..."
    mkdir -p "${BACKUP_DIR}/${DATE}"
    sudo dd if="${USB_DEVICE}5" of="${BACKUP_DIR}/${DATE}/persistence.dat" \
        bs=4M status=progress
}

backup_agents() {
    echo "Backing up agents..."
    mkdir -p "${BACKUP_DIR}/${DATE}"
    for agent_file in $USB_MOUNT/agents/*-home.dat; do
        if [ -f "$agent_file" ]; then
            agent_name=$(basename "$agent_file" .dat)
            echo "  Backing up agent: ${agent_name}"
            sudo dd if="$agent_file" of="${BACKUP_DIR}/${DATE}/${agent_name}.dat" \
                bs=4M status=progress
        fi
    done
}

backup_config() {
    echo "Backing up Ventoy config..."
    mkdir -p "${BACKUP_DIR}/${DATE}"
    sudo cp -r $USB_MOUNT/ventoy "${BACKUP_DIR}/${DATE}/ventoy-config"
}

backup_isos() {
    echo "Backing up ISO list..."
    mkdir -p "${BACKUP_DIR}/${DATE}"
    ls -lh $USB_MOUNT/*.iso > "${BACKUP_DIR}/${DATE}/iso-list.txt"
}

case "$1" in
    -p|--persistence)
        backup_persistence
        ;;
    -a|--agents)
        backup_agents
        ;;
    -c|--config)
        backup_config
        ;;
    -i|--isos)
        backup_isos
        ;;
    -all|--all)
        backup_persistence
        backup_agents
        backup_config
        backup_isos
        ;;
    *)
        usage
        ;;
esac

echo "=== Backup Complete ==="
```

### Automated Backup Cron Job

```bash
# Install backup scripts:
sudo cp scripts/backup-full.sh /usr/local/bin/usb-backup-full
sudo cp scripts/backup-selective.sh /usr/local/bin/usb-backup-selective
sudo chmod +x /usr/local/bin/usb-backup-*

# Set up daily backup cron job:
sudo crontab -e

# Add:
# Daily full backup at 2 AM
0 2 * * * /usr/local/bin/usb-backup-full >> /var/log/usb-backup.log 2>&1

# Weekly incremental backup on Sundays
0 3 * * 0 /usr/local/bin/usb-backup-incremental >> /var/log/usb-backup.log 2>&1
```

## Restore Procedures

### Full Restore from Image

```bash
# Restore from compressed image:
gunzip -c ~/usb-backups/YYYYMMDD-HHMMSS/usb-image.img.gz | \
    sudo dd of=/dev/sdX bs=4M status=progress

# Or decompress first, then restore:
gunzip ~/usb-backups/YYYYMMDD-HHMMSS/usb-image.img.gz
sudo dd if=~/usb-backups/YYYYMMDD-HHMMSS/usb-image.img of=/dev/sdX bs=4M status=progress
```

### Selective Restore

```bash
# Restore persistence only:
sudo dd if=~/usb-backups/YYYYMMDD-HHMMSS/persistence.dat \
    of=/dev/sdX5 bs=4M status=progress

# Restore specific agent:
sudo dd if=~/usb-backups/YYYYMMDD-HHMMSS/agent-alpha.dat \
    of=$USB_MOUNT/agents/alpha-home.dat bs=4M status=progress

# Restore Ventoy config:
sudo cp -r ~/usb-backups/YYYYMMDD-HHMMSS/ventoy-config/* $USB_MOUNT/ventoy/
```

### Restore Verification

```bash
# Verify restored image:
sudo dd if=/dev/sdX of=/tmp/verify.img bs=4M count=100
sha256sum /tmp/verify.img
# Compare with backup checksum

# Check filesystem integrity:
sudo e2fsck -f /dev/sdX1
sudo e2fsck -f /dev/sdX5

# Verify persistence mount:
sudo mount -o loop /dev/sdX5 /tmp/test-persist
ls -la /tmp/test-persist
sudo umount /tmp/test-persist
```

## Backup Storage

### Local Storage

```bash
# Store backups on local drive:
BACKUP_DIR="/mnt/backup-drive/usb-backups"

# Or on separate USB:
BACKUP_DIR="$BACKUP_MOUNT/backups"
```

### Network Storage

```bash
# Store backups on NAS:
BACKUP_DIR="/mnt/nas/usb-backups"

# Mount NAS:
sudo mount -t nfs nas.local:/share /mnt/nas

# Or with SMB:
sudo mount -t cifs //nas.local/share /mnt/nas -o username=user,password=pass
```

### Cloud Storage

```bash
# Store backups on cloud (using rclone):
rclone sync ~/usb-backups remote:usb-backups

# Or with AWS S3:
aws s3 sync ~/usb-backups s3://my-usb-backups/

# Or with Google Cloud:
gsutil rsync -r ~/usb-backups gs://my-usb-backups/
```

## Backup Management

### List Backups

```bash
# List all backups:
ls -lh ~/usb-backups/

# List by date:
ls -lt ~/usb-backups/ | head -10

# Show backup details:
cat ~/usb-backups/YYYYMMDD-HHMMSS/manifest.json
```

### Verify Backups

```bash
# Verify backup integrity:
sha256sum -c ~/usb-backups/YYYYMMDD-HHMMSS/usb-image.img.gz.sha256

# Test restore to temporary location:
sudo dd if=~/usb-backups/YYYYMMDD-HHMMSS/usb-image.img.gz of=/dev/loop0 \
    bs=4M status=progress
```

### Cleanup Old Backups

```bash
# Remove backups older than 30 days:
find ~/usb-backups/ -type d -mtime +30 -exec rm -rf {} \;

# Keep only last 5 backups:
ls -dt ~/usb-backups/*/ | tail -n +6 | xargs rm -rf

# Compress old backups:
find ~/usb-backups/ -name "*.img" -mtime +7 -exec gzip {} \;
```

## Disaster Recovery

### USB Failure

```bash
# If USB is physically damaged:
# 1. Remove USB from system
# 2. Insert new USB
# 3. Restore from backup:
sudo dd if=~/usb-backups/latest/usb-image.img.gz of=/dev/sdX bs=4M status=progress

# Or create fresh USB:
python3 scripts/setup.py --device /dev/sdX --iso ~/Downloads/ubuntu-24.04.4-desktop-amd64.iso
# Then restore persistence:
sudo dd if=~/usb-backups/latest/persistence.dat of=/dev/sdX5 bs=4M status=progress
```

### Corruption Recovery

```bash
# If filesystem is corrupted:
sudo e2fsck -fy /dev/sdX1
sudo e2fsck -fy /dev/sdX5

# If partition table is damaged:
sudo parted /dev/sdX --script mklabel gpt
sudo parted /dev/sdX --script mkpart primary fat32 1MiB 10GiB
sudo parted /dev/sdX --script mkpart primary ext4 10GiB 100%
sudo mkfs.vfat -F 32 -n VENTOY /dev/sdX1
sudo mkfs.ext4 -L persistence /dev/sdX2

# Then restore data:
sudo dd if=~/usb-backups/latest/persistence.dat of=/dev/sdX2 bs=4M status=progress
sudo cp -r ~/usb-backups/latest/ventoy-config/* $USB_MOUNT/ventoy/
```

### Data Recovery

```bash
# Attempt data recovery from damaged USB:
sudo apt install testdisk photorec -y

# Run PhotoRec:
sudo photorec /dev/sdX

# Follow prompts to recover files
```

## Backup Best Practices

### 3-2-1 Rule

- **3** copies of data
- **2** different storage media
- **1** offsite backup

### Backup Schedule

| Frequency | Type | Retention |
|---|---|---|
| Daily | Full image | 7 days |
| Weekly | Selective | 4 weeks |
| Monthly | Archive | 12 months |

### Verification

- Test restore monthly
- Verify checksums weekly
- Monitor backup logs daily

### Security

```bash
# Encrypt backups:
gpg -c ~/usb-backups/latest/usb-image.img.gz

# Decrypt for restore:
gpg -d ~/usb-backups/latest/usb-image.img.gz.gpg | \
    gunzip | sudo dd of=/dev/sdX bs=4M status=progress
```
