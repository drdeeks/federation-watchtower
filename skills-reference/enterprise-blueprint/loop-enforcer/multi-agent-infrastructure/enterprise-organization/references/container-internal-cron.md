# Container-Internal Cron Jobs

## Overview
Running cron jobs INSIDE containers for daily maintenance tasks like skill updates. The container runs cron as a service alongside the main gateway process.

## Architecture

```
Container (PID 1: OpenClaw Gateway)
├── Gateway process (port 18789)
├── MCP loopback server (random port, e.g., 43247)
├── cron daemon (started by container-init.sh)
│   └── Daily job: 0 2 * * * /scripts/pull-drdeeks-daily.sh
└── MCP Proxy (port 41214) - forwards to loopback
```

## Implementation

### 1. container-init.sh (runs on container startup)
```bash
#!/bin/bash
# Container initialization - sets up daily cron job for drdeeks skills pull

set -e

# Install cron if not present
if ! command -v cron &> /dev/null; then
    apt-get update && apt-get install -y cron 2>/dev/null | tail -5
fi

# Create crontab entry for daily pull at 2 AM
CRON_JOB="0 2 * * * /home/ubuntu/hemlock-minimal/scripts/pull-drdeeks-daily.sh >> /var/log/drdeeks-cron.log 2>&1"

# Check if already in crontab
if ! crontab -l 2>/dev/null | grep -q "pull-drdeeks-daily.sh"; then
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    echo "Added daily drdeeks pull cron job (2 AM daily)"
fi

# Start cron daemon
service cron start 2>/dev/null || cron

echo "Container initialization complete - drdeeks daily pull scheduled"
```

### 2. pull-drdeeks-daily.sh (runs daily at 2 AM)
```bash
#!/bin/bash
# Daily pull of drdeeks skills repo - runs inside container
# Keeps skills up to date on the portable USB

set -e

SKILLS_DIR="/home/ubuntu/hemlock-minimal/hemlock-minimal/skills/drdeeks"
LOG_FILE="/var/log/drdeeks-pull.log"

echo "[$(date)] Starting drdeeks skills pull" >> $LOG_FILE

# Check if drdeeks repo exists
if [ -d "$SKILLS_DIR/.git" ]; then
    cd "$SKILLS_DIR"
    echo "[$(date)] Pulling latest changes..." >> $LOG_FILE
    git pull origin main 2>&1 | tee -a $LOG_FILE
    echo "[$(date)] Pull complete" >> $LOG_FILE
else
    echo "[$(date)] Initial clone..." >> $LOG_FILE
    git clone --depth 1 https://github.com/drdeeks/skills.git "$SKILLS_DIR" 2>&1 | tee -a $LOG_FILE
    echo "[$(date)] Initial clone complete" >> $LOG_FILE
fi

echo "[$(date)] drdeeks skills update finished" >> $LOG_FILE
```

### 3. Entrypoint Integration
```bash
# In entrypoint.sh - call container-init.sh before gateway startup
# ============================================================================
# CONTAINER INITIALIZATION
# ============================================================================
/home/ubuntu/hemlock-minimal/scripts/container-init.sh

# ============================================================================
# GATEWAY INITIALIZATION (Hemlock Gateway)
# ============================================================================
```

## Cron Service Management

### systemd vs cron in Container
- Use `service cron start` for systemd-based containers
- Fallback: `cron` directly for minimal containers
- Log to `/var/log/drdeeks-cron.log` for visibility

### Log Rotation
```bash
# Add to crontab for log rotation
0 3 * * * /usr/sbin/logrotate /etc/logrotate.d/drdeeks
```

### /etc/logrotate.d/drdeeks
```
/var/log/drdeeks-pull.log /var/log/drdeeks-cron.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
```

## Key Learnings (Session 2026-06-13)

1. **Cron must run inside container** - not on host, for USB portability
2. **Install cron if missing** - many base images don't include it
3. **Check crontab before adding** - avoid duplicate entries on restart
4. **Log to file** - `tee -a` for both stdout and log file
5. **Use `git pull origin main`** not just `git pull` - explicit remote/branch
5. **Use `--depth 1` for initial clone** - shallow clone saves space
6. **Log timestamps** - `[$(date)]` prefix for debugging
7. **Check `.git` directory** - not just directory existence
8. **Redirect stderr** - `2>&1 | tee -a` captures all output

## Cron Syntax Reference
```
* * * * * command
- - - - -
| | | | └── Day of week (0-7) (Sun=0 or 7)
| | | └──── Month (1-12)
| | └────── Day of month (1-31)
| └──────── Hour (0-23)
└────────── Minute (0-59)

0 2 * * *  = 2:00 AM daily
```

## Verification
```bash
# Check cron is running
service cron status

# View crontab
crontab -l

# Check logs
tail -f /var/log/drdeeks-pull.log
tail -f /var/log/drdeeks-cron.log

# Test pull manually
/scripts/pull-drdeeks-daily.sh
```

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| Cron not running | Service not started | `service cron start` |
| Duplicate entries | Restart adds duplicates | Check `crontab -l | grep` before adding |
| Git pull fails | No internet | Log failure, retry next day |
| Permission denied | Script not executable | `chmod +x /scripts/pull-drdeeks-daily.sh` |
| Cron not persisting | Container restart loses crontab | Add to entrypoint.sh startup |